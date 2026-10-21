--!strict
-- ClimbController (client): limb-by-limb climbing, modelled on the reference video.
--
-- How to climb
--   * Click and drag a hand or foot (a ring shows on each one near the wall) and drop it
--     on a hold. Green markers = holds that hand can reach, teal = feet, red = too far.
--   * Or click a limb (or press Q/E/Z/C) to select it, then click a hold.
--   * Or just click a hold: the nearest limb that can reach it takes it.
--   * Dropping a limb on empty wall lets that limb go. With nothing held you fall off.
--   * W A S D shift your weight (moves the body around the holds, like "rock / swing").
--   * Hold Space to charge a dyno, aim with the mouse, release to jump. A free hand that
--     passes close to a hand hold catches it; otherwise you fall.
--   * V lets go of the wall.
--
-- The server owns the truth (character attributes "Climb_<Limb>"). This script predicts
-- each request so it feels instant and rolls back if the server refuses it.
--
-- The climbing animation (arms and legs on the holds, reaching, torso, head) is done by
-- ClimbAnimator every frame after Roblox's animations, for this player and for every other
-- climber (from their attributes). It works on R6 and R15 and needs nothing from the server.

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClimbMath = require(Shared:WaitForChild("ClimbMath"))
local Config = require(Shared:WaitForChild("Config"))
local HoldUtil = require(Shared:WaitForChild("HoldUtil"))
local LimbRig = require(Shared:WaitForChild("LimbRig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))

local ClimbAnimator = require(script.Parent:WaitForChild("ClimbAnimator"))
local ClimbOverlay = require(script.Parent:WaitForChild("ClimbOverlay"))

local CLIMB = Config.Climb
local DYNO = CLIMB.Dyno
local COLORS = CLIMB.Colors
local ACTION_DYNO = "ClimbDyno"
local ACTION_LET_GO = "ClimbLetGo"
local ACTION_CENTRE = "ClimbCentre"
local MAX_RAY = 200

local player = Players.LocalPlayer

type Pending = { holdId: string?, at: number }
type Drag = {
	limb: string,
	input: InputObject?, -- the touch that started it (nil for mouse)
	start: Vector2,
	moved: boolean,
	candidate: BasePart?,
	valid: boolean,
}

local ClimbController = {}

local requestEvent: RemoteEvent
local controls: any = nil -- PlayerModule ControlModule (WASD / thumbstick / gamepad)
local rayParams = RaycastParams.new()
local weightShift = Vector2.zero -- -1..1 right/up, kept between frames (sticky)
local groundParams = RaycastParams.new()

-- Character
local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local tips: { [string]: Attachment } = {} -- the hand/foot points (rings and picking)
local alignPosition: AlignPosition? = nil
local alignOrientation: AlignOrientation? = nil
local characterConnections: { RBXScriptConnection } = {}

-- Holds by HoldId (only the ones streamed in near this player)
local holdsById: { [string]: BasePart } = {}

-- Climb state
local pending: { [string]: Pending } = {}
local climbing: boolean = false
local selected: string? = nil
local drag: Drag? = nil
local pointer: Vector2? = nil -- viewport coordinates
local dragPoints: { [string]: Vector3 } = {} -- where a dragged limb is reaching
local dynoCharge: number? = nil
local flightUntil: number? = nil
local flightHold: BasePart? = nil -- the hold a dyno is aimed at
local wallNormal = Vector3.zAxis
local warnedTired = false

---------------------------------------------------------------------------------------
-- Holds

-- Holds are also kept in a coarse grid, so "holds near here" only looks at nearby cells
-- (big walls have thousands of holds).
local CELL = 16
local holdCells: { [string]: { [BasePart]: boolean } } = {}
local cellOf: { [BasePart]: string } = {}

local function cellKey(x: number, y: number, z: number): string
	return `{x},{y},{z}`
end

local function indexHold(instance: Instance)
	local id = instance:GetAttribute("HoldId")
	if instance:IsA("BasePart") and type(id) == "string" then
		holdsById[id] = instance
		local p = instance.Position
		local key = cellKey(math.floor(p.X / CELL), math.floor(p.Y / CELL), math.floor(p.Z / CELL))
		local cell = holdCells[key]
		if cell == nil then
			cell = {}
			holdCells[key] = cell
		end
		cell[instance] = true
		cellOf[instance] = key
	end
end

local function unindexHold(instance: Instance)
	local id = instance:GetAttribute("HoldId")
	if type(id) == "string" and holdsById[id] == instance then
		holdsById[id] = nil
	end
	local part = instance :: BasePart
	local key = cellOf[part]
	if key then
		cellOf[part] = nil
		local cell = holdCells[key]
		if cell then
			cell[part] = nil
		end
	end
end

-- Every indexed hold whose part is within `radius` of `point` (roughly; callers check).
local function holdsNear(point: Vector3, radius: number): { BasePart }
	local found = {}
	local r = math.ceil(radius / CELL)
	local cx, cy, cz = math.floor(point.X / CELL), math.floor(point.Y / CELL), math.floor(point.Z / CELL)
	for x = cx - r, cx + r do
		for y = cy - r, cy + r do
			for z = cz - r, cz + r do
				local cell = holdCells[cellKey(x, y, z)]
				if cell then
					for hold in cell do
						table.insert(found, hold)
					end
				end
			end
		end
	end
	return found
end

local function gripPosition(hold: BasePart): Vector3
	return HoldUtil.getGripCFrame(hold).Position
end

local function holdId(hold: BasePart): string?
	local id = hold:GetAttribute("HoldId")
	return if type(id) == "string" then id else nil
end

local function limbKind(limb: string): "Hand" | "Foot"
	return Config.Limbs[limb].Kind
end

local function kindColor(limb: string): Color3
	return if limbKind(limb) == "Hand" then COLORS.Hand else COLORS.Foot
end

local function accepts(limb: string, hold: BasePart): boolean
	local info = HoldUtil.read(hold)
	return info ~= nil and HoldUtil.accepts(info, limbKind(limb))
end

local function inReach(limb: string, hold: BasePart): boolean
	return root ~= nil and ClimbMath.inReach(root.Position, gripPosition(hold), Config.Limbs[limb].Reach)
end

-- World position of a hand/foot (the body centre if this rig lacks that limb).
local function tipPosition(limb: string): Vector3?
	local tip = tips[limb]
	if tip then
		return tip.WorldPosition
	end
	return root and root.Position
end

-- 0 = fresh, 1 = about to fall off (from the server's "Stamina" attribute).
local function fatigueOf(someone: Model): number
	local stamina = someone:GetAttribute("Stamina")
	if type(stamina) ~= "number" then
		return 0
	end
	return math.clamp(1 - stamina / Config.Stamina.LowWarning, 0, 1)
end

local function isDown(someone: Model?): boolean
	return someone ~= nil and someone:GetAttribute("Ragdolled") == true
end

---------------------------------------------------------------------------------------
-- What each limb holds: the prediction if there is one, else the server's attribute.

local function heldId(limb: string): string?
	local p = pending[limb]
	if p then
		return p.holdId
	end
	local id = character and character:GetAttribute("Climb_" .. limb)
	return if type(id) == "string" then id else nil
end

local function heldHold(limb: string): BasePart?
	local id = heldId(limb)
	return if id then holdsById[id] else nil
end

local function attachedGrips(): { ClimbMath.Grip }
	local grips = {}
	for _, limb in Config.LimbOrder do
		local hold = heldHold(limb)
		if hold then
			table.insert(grips, { kind = limbKind(limb), position = gripPosition(hold), reach = Config.Limbs[limb].Reach })
		end
	end
	return grips
end

---------------------------------------------------------------------------------------
-- Entering / leaving the wall

local function setAligns(enabled: boolean)
	if alignPosition and alignOrientation and root then
		if enabled and not alignPosition.Enabled then
			alignPosition.Position = root.Position
			alignOrientation.CFrame = root.CFrame
		end
		alignPosition.Enabled = enabled
		alignOrientation.Enabled = enabled
	end
end

local letGo: () -> ()
local launchDyno: () -> ()

local function bindWallActions()
	ContextActionService:BindActionAtPriority(ACTION_DYNO, function(_, state)
		if state == Enum.UserInputState.Begin then
			if climbing and flightUntil == nil and #attachedGrips() > 0 then
				dynoCharge = 0
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			launchDyno()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.ContextActionPriority.High.Value, CLIMB.Keys.Dyno, Enum.KeyCode.ButtonA)
	ContextActionService:SetTitle(ACTION_DYNO, "Dyno")

	ContextActionService:BindActionAtPriority(ACTION_LET_GO, function(_, state)
		if state == Enum.UserInputState.Begin then
			letGo()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.ContextActionPriority.High.Value, CLIMB.Keys.LetGo, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(ACTION_LET_GO, "Let go")

	ContextActionService:BindActionAtPriority(ACTION_CENTRE, function(_, state)
		if state == Enum.UserInputState.Begin then
			weightShift = Vector2.zero
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.ContextActionPriority.High.Value, CLIMB.Keys.CentreWeight, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle(ACTION_CENTRE, "Centre")
end

local function enterClimb()
	if climbing or humanoid == nil then
		return
	end
	climbing = true
	weightShift = Vector2.zero
	humanoid.PlatformStand = true -- the humanoid stops walking/balancing; constraints hold the body
	setAligns(true)
	bindWallActions()
end

local function exitClimb()
	if not climbing then
		return
	end
	climbing = false
	selected = nil
	drag = nil
	dynoCharge = nil
	flightUntil = nil
	flightHold = nil
	setAligns(false)
	ContextActionService:UnbindAction(ACTION_DYNO)
	ContextActionService:UnbindAction(ACTION_LET_GO)
	ContextActionService:UnbindAction(ACTION_CENTRE)
	weightShift = Vector2.zero
	if humanoid and humanoid.Health > 0 then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	ClimbOverlay.setDyno(nil)
	ClimbOverlay.setHeight(nil)
end

---------------------------------------------------------------------------------------
-- Requests (predicted locally, confirmed or refused by ClimbService)

local function requestPlace(limb: string, hold: BasePart): boolean
	if not accepts(limb, hold) then
		ClimbOverlay.toast(if limbKind(limb) == "Hand" then "That hold is for feet" else "That hold is for hands")
		return false
	end
	if not inReach(limb, hold) then
		ClimbOverlay.toast("Out of reach - shift your weight (W A S D)")
		return false
	end
	-- Roped walls must be clipped into first (the server enforces it too).
	local route = HoldUtil.getRouteFolder(hold)
	if route and (route:GetAttribute("Rope") == true or route:GetAttribute("AutoBelay") == true) and (character == nil or character:GetAttribute("TiedIn") ~= route.Name) then
		ClimbOverlay.toast(if route:GetAttribute("AutoBelay") == true then "Clip in to the auto-belay first (orange carabiner)" else "Tie in at the rope bag first")
		return false
	end
	local id = holdId(hold)
	if id == nil then
		return false
	end
	pending[limb] = { holdId = id, at = os.clock() }
	requestEvent:FireServer("Place", limb, id)
	enterClimb()
	return true
end

local function requestRelease(limb: string)
	pending[limb] = { holdId = nil, at = os.clock() }
	requestEvent:FireServer("Release", limb)
end

function letGo()
	for _, limb in Config.LimbOrder do
		pending[limb] = { holdId = nil, at = os.clock() }
	end
	requestEvent:FireServer("LetGo")
	exitClimb()
end

---------------------------------------------------------------------------------------
-- Pointer helpers

local function viewportPoint(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.Touch then
		-- Touch positions exclude the top bar; the camera functions below want viewport space.
		local inset = GuiService:GetGuiInset()
		return Vector2.new(input.Position.X, input.Position.Y) + inset
	end
	return UserInputService:GetMouseLocation()
end

local function pickLimb(point: Vector2): (string?, number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, math.huge
	end
	local best, bestDistance = nil, CLIMB.PickRadiusPx
	for limb, tip in tips do
		local screen, onScreen = camera:WorldToViewportPoint(tip.WorldPosition)
		if onScreen then
			local distance = (Vector2.new(screen.X, screen.Y) - point).Magnitude
			if distance < bestDistance then
				best, bestDistance = limb, distance
			end
		end
	end
	return best, bestDistance
end

local function nearestHold(point: Vector3, radius: number, filter: (BasePart) -> boolean): BasePart?
	local best, bestDistance = nil, radius
	for _, hold in holdsNear(point, radius + 2) do
		local distance = (gripPosition(hold) - point).Magnitude
		if distance < bestDistance and filter(hold) then
			best, bestDistance = hold, distance
		end
	end
	return best
end

-- What's under the pointer: the world point, the hold `limb` would take there (the hold
-- itself, or one within SnapRadius of the point), and whether the pointer is right on it.
local function probe(point: Vector2, limb: string?): (Vector3?, BasePart?, boolean)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, nil, false
	end
	rayParams.FilterDescendantsInstances = if character then { character } else {}
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * MAX_RAY, rayParams)

	local worldPoint: Vector3? = nil
	local hit: BasePart? = nil
	if result then
		worldPoint = result.Position
		hit = HoldUtil.findHold(result.Instance)
	elseif root then
		-- Pointing past the wall's edge: use the plane of the wall instead.
		worldPoint = ClimbMath.rayPlane(ray.Origin, ray.Direction, root.Position - wallNormal * CLIMB.BodyOffset, wallNormal)
	end

	local function fits(hold: BasePart): boolean
		return limb == nil or accepts(limb, hold)
	end
	if hit and fits(hit) then
		return worldPoint, hit, true
	end
	if worldPoint then
		return worldPoint, nearestHold(worldPoint, CLIMB.SnapRadius, fits), false
	end
	return nil, nil, false
end

-- The limb that should take `hold` when it is clicked with nothing selected:
-- a free limb before a busy one, then the closest.
local function bestLimbFor(hold: BasePart): string?
	local best, bestScore = nil, math.huge
	for _, limb in Config.LimbOrder do
		local tip = tipPosition(limb)
		if tip and accepts(limb, hold) and inReach(limb, hold) and heldId(limb) ~= holdId(hold) then
			local score = (tip - gripPosition(hold)).Magnitude + (if heldId(limb) then 100 else 0)
			if score < bestScore then
				best, bestScore = limb, score
			end
		end
	end
	return best
end

local function nearWall(): boolean
	if root == nil then
		return false
	end
	local position = root.Position
	return nearestHold(position, Config.Limbs.LeftHand.Reach + 1, function()
		return true
	end) ~= nil
end

---------------------------------------------------------------------------------------
-- Dyno

-- What the dyno is aimed at: the hand hold under the pointer, or just a point on the wall.
local function dynoAim(): (Vector3?, BasePart?)
	if pointer == nil then
		return nil, nil
	end
	local point, hold = probe(pointer, "LeftHand")
	if hold then
		return gripPosition(hold), hold
	end
	return point, nil
end

-- Where a dyno with `charge` would carry the body, how long it flies, the hold it is aimed
-- at, and whether that hold will be in reach on arrival (enough charge).
local function planDyno(charge: number): (Vector3?, number, BasePart?, boolean)
	if root == nil then
		return nil, 0, nil, false
	end
	local aim, hold = dynoAim()
	if aim == nil then
		return nil, 0, nil, false
	end
	local arrival, time = ClimbMath.planDyno(root.Position, aim, wallNormal, charge, CLIMB.BodyOffset, DYNO)
	local reaches = hold ~= nil and ClimbMath.inReach(arrival, aim, Config.Limbs.LeftHand.Reach * CLIMB.ReachSlack)
	return arrival, time, hold, reaches
end

function launchDyno()
	local charge = dynoCharge
	dynoCharge = nil
	ClimbOverlay.setDyno(nil)
	if charge == nil or charge < DYNO.MinCharge or not climbing or root == nil then
		return
	end
	local arrival, time, hold = planDyno(charge)
	if arrival == nil or (arrival - root.Position).Magnitude < 0.5 then
		return
	end
	for _, limb in Config.LimbOrder do
		pending[limb] = { holdId = nil, at = os.clock() }
	end
	requestEvent:FireServer("Dyno")
	setAligns(false)
	-- A real ballistic arc under Roblox gravity, landing at `arrival` after `time` seconds.
	root.AssemblyLinearVelocity = ClimbMath.ballisticVelocity(root.Position, arrival, time, Workspace.Gravity)
	root.AssemblyAngularVelocity = Vector3.zero
	flightUntil = os.clock() + time + DYNO.CatchGrace
	flightHold = hold
end

local function closestFreeHand(hold: BasePart): string?
	local best, bestDistance = nil, math.huge
	for _, limb in { "LeftHand", "RightHand" } do
		local hand = tipPosition(limb)
		if hand and heldId(limb) == nil then
			local distance = (hand - gripPosition(hold)).Magnitude
			if distance < bestDistance then
				best, bestDistance = limb, distance
			end
		end
	end
	return best
end

-- During a dyno: grab the aimed-at hold as soon as it is in reach, or any hand hold a
-- free hand passes close to.
local function tryCatch()
	local aimed = flightHold
	if aimed and aimed.Parent and inReach("LeftHand", aimed) then
		local limb = closestFreeHand(aimed)
		if limb and requestPlace(limb, aimed) then
			return
		end
	end
	for _, limb in { "LeftHand", "RightHand" } do
		local hand = tipPosition(limb)
		if hand and heldId(limb) == nil then
			local hold = nearestHold(hand, DYNO.CatchRadius, function(h)
				return accepts(limb, h) and inReach(limb, h)
			end)
			if hold and requestPlace(limb, hold) then
				return
			end
		end
	end
end

---------------------------------------------------------------------------------------
-- Pointer input

local function beginPointer(input: InputObject)
	if character == nil or humanoid == nil or humanoid.Health <= 0 or isDown(character) then
		return
	end
	local point = viewportPoint(input)
	pointer = point

	local limb, limbDistance = pickLimb(point)
	-- Pointer right on a different hold and not right on the limb: the click is for the hold.
	local _, directHold, direct = probe(point, nil)
	if limb and direct and directHold and heldId(limb) ~= holdId(directHold) and limbDistance > CLIMB.PickRadiusPx * 0.4 then
		limb = nil
	end
	if limb and (climbing or nearWall()) then
		drag = {
			limb = limb,
			input = if input.UserInputType == Enum.UserInputType.Touch then input else nil,
			start = point,
			moved = false,
			candidate = nil,
			valid = false,
		}
		return
	end

	-- A plain click on a hold: the selected limb takes it, or the best limb does.
	local _, hold = probe(point, selected)
	if hold == nil then
		return
	end
	local chosen = selected or bestLimbFor(hold)
	if chosen then
		if requestPlace(chosen, hold) then
			selected = nil
		end
	elseif climbing or nearWall() then
		ClimbOverlay.toast("No free limb can reach that hold")
	end
end

local function endPointer(input: InputObject)
	local current = drag
	if current == nil or (current.input ~= nil and current.input ~= input) then
		return
	end
	drag = nil
	-- Settle the drop from where the pointer is now; a quick flick can end between frames.
	local point = viewportPoint(input)
	if (point - current.start).Magnitude > CLIMB.ClickMovePx then
		current.moved = true
		local _, hold = probe(point, current.limb)
		current.candidate = hold
		current.valid = hold ~= nil and inReach(current.limb, hold)
	end
	if not current.moved then
		-- A click on a limb selects it (click again to deselect).
		selected = if selected == current.limb then nil else current.limb
		return
	end
	if current.candidate then
		if current.valid then
			requestPlace(current.limb, current.candidate)
		else
			ClimbOverlay.toast("Out of reach - shift your weight (W A S D)")
		end
	elseif heldId(current.limb) then
		-- Dropped on empty wall: that limb lets go.
		requestRelease(current.limb)
	end
end

---------------------------------------------------------------------------------------
-- Per-frame update

local function updateDrag()
	local current = drag
	if current == nil or root == nil or pointer == nil then
		ClimbOverlay.setDragDot(nil)
		return
	end
	if (pointer - current.start).Magnitude > CLIMB.ClickMovePx then
		current.moved = true
	end
	if not current.moved then
		return
	end
	local point, hold = probe(pointer, current.limb)
	current.candidate = hold
	current.valid = hold ~= nil and inReach(current.limb, hold)

	-- The limb follows the pointer, stretched no further than it can reach.
	local reach = Config.Limbs[current.limb].Reach
	local target = if hold then gripPosition(hold) else point
	if target then
		local offset = target - root.Position
		if offset.Magnitude > reach then
			target = root.Position + offset.Unit * reach
		end
		dragPoints[current.limb] = target
	end
	ClimbOverlay.setDragDot(target, if current.valid then kindColor(current.limb) elseif hold then COLORS.OutOfReach else nil)
end

local function updateMarkers()
	local limb = if drag and drag.moved then drag.limb else selected
	if limb == nil or root == nil then
		ClimbOverlay.setMarkers({})
		return
	end
	local markers: { ClimbOverlay.Marker } = {}
	local candidate = drag and drag.candidate
	for _, hold in holdsNear(root.Position, CLIMB.MarkerRange + 2) do
		local position = gripPosition(hold)
		if (position - root.Position).Magnitude <= CLIMB.MarkerRange and accepts(limb, hold) then
			local reachable = inReach(limb, hold)
			local isCandidate = hold == candidate
			table.insert(markers, {
				position = position,
				color = if reachable then kindColor(limb) else COLORS.OutOfReach,
				radius = if isCandidate then 0.55 else 0.35,
				transparency = if isCandidate then 0.05 elseif reachable then 0.3 else 0.7,
			})
		end
	end
	ClimbOverlay.setMarkers(markers)
end

local function updateRings()
	local show = climbing or drag ~= nil or selected ~= nil or nearWall()
	for _, limb in Config.LimbOrder do
		local active = (drag ~= nil and drag.limb == limb) or selected == limb
		local color = if active then COLORS.Selected elseif heldId(limb) then COLORS.Attached else COLORS.Free
		ClimbOverlay.setLimbRing(limb, if show then tips[limb] else nil, color, active)
	end
end

---------------------------------------------------------------------------------------
-- Posing arms and legs (runs in PreSimulation, after animations)

-- Highest hand hold, a little above it: where a climber looks when not aiming at anything.
local function lookUpFrom(targets: { [string]: Vector3? }, normal: Vector3): Vector3?
	local best: Vector3? = nil
	for _, limb in { "LeftHand", "RightHand" } do
		local p = targets[limb]
		if p and (best == nil or p.Y > best.Y) then
			best = p
		end
	end
	local _, up = ClimbMath.wallAxes(normal)
	return if best then best + up * 1.5 else nil
end

-- Height of the floor under `position` (collidable parts only, so holds are ignored).
-- `who` is left out of the ray (default: this player's character).
local function groundBelow(position: Vector3, who: Model?): number?
	local skip = who or character
	groundParams.FilterDescendantsInstances = if skip then { skip } else {}
	local result = Workspace:Raycast(position + Vector3.yAxis, Vector3.yAxis * -12, groundParams)
	return if result then result.Position.Y else nil
end

-- What this player's body should be doing this frame (nil = not climbing or reaching).
local function localIntent(): ClimbAnimator.Intent?
	local isClimbing: boolean = climbing
	local current = drag
	local dragging = current ~= nil and current.moved
	if not isClimbing and not dragging then
		return nil
	end
	local targets: { [string]: Vector3? } = {}
	local direct: { [string]: boolean } = {}
	for _, limb in Config.LimbOrder do
		if current and current.moved and current.limb == limb and dragPoints[limb] then
			targets[limb] = dragPoints[limb]
			direct[limb] = true
		elseif isClimbing then
			if flightUntil then
				-- Mid-dyno both hands reach for the target hold.
				if flightHold and limbKind(limb) == "Hand" then
					targets[limb] = gripPosition(flightHold)
				end
			else
				local hold = heldHold(limb)
				if hold then
					targets[limb] = gripPosition(hold)
				end
			end
		end
	end
	local look: Vector3?
	if current and current.moved then
		look = dragPoints[current.limb]
	elseif flightHold then
		look = gripPosition(flightHold)
	elseif dynoCharge then
		look = dynoAim()
	else
		look = lookUpFrom(targets, wallNormal)
	end
	local intent: ClimbAnimator.Intent = {
		climbing = isClimbing,
		normal = wallNormal,
		targets = targets,
		direct = direct,
		look = look,
		charge = dynoCharge or 0,
		fatigue = if character then fatigueOf(character) else 0,
		floorY = if root then groundBelow(root.Position) else nil,
	}
	return intent
end

-- Another player's climbing pose, from the attributes the server sets on them.
local function otherIntent(otherCharacter: Model): ClimbAnimator.Intent?
	if otherCharacter:GetAttribute("Climbing") ~= true then
		return nil
	end
	local targets: { [string]: Vector3? } = {}
	local facing = Vector3.zero
	for _, limb in Config.LimbOrder do
		local id = otherCharacter:GetAttribute("Climb_" .. limb)
		local hold = if type(id) == "string" then holdsById[id] else nil
		if hold then
			local gripFrame = HoldUtil.getGripCFrame(hold)
			targets[limb] = gripFrame.Position
			facing += gripFrame.LookVector
		end
	end
	if facing.Magnitude < 1e-3 then
		return nil
	end
	local normal = facing.Unit
	local otherRoot = otherCharacter:FindFirstChild("HumanoidRootPart")
	return {
		climbing = true,
		normal = normal,
		targets = targets,
		look = lookUpFrom(targets, normal),
		charge = 0,
		fatigue = fatigueOf(otherCharacter),
		floorY = if otherRoot and otherRoot:IsA("BasePart") then groundBelow(otherRoot.Position, otherCharacter) else nil,
	}
end

-- PreSimulation: pose every climber (runs after Roblox's animations, so the pose wins).
local function animateAll(dt: number)
	if character and not isDown(character) then
		ClimbAnimator.animate(character, localIntent(), dt)
	end
	for _, other in Players:GetPlayers() do
		local otherCharacter = other.Character
		if other ~= player and otherCharacter and not isDown(otherCharacter) then
			ClimbAnimator.animate(otherCharacter, otherIntent(otherCharacter), dt)
		end
	end
end

local function updateBody(grips: { ClimbMath.Grip }, dt: number)
	if alignPosition == nil or alignOrientation == nil then
		return
	end
	-- The wall faces the way the held holds' Grips point.
	local sum = Vector3.zero
	for _, limb in Config.LimbOrder do
		local hold = heldHold(limb)
		if hold then
			sum += HoldUtil.getGripCFrame(hold).LookVector
		end
	end
	if sum.Magnitude > 1e-3 then
		wallNormal = sum.Unit
	end

	-- Weight shift sticks: WASD moves it and it stays where you leave it (X re-centres).
	if controls then
		local move: Vector3 = controls:GetMoveVector()
		local push = Vector2.new(move.X, -move.Z)
		if push.Magnitude > 1 then
			push = push.Unit
		end
		weightShift += push * (CLIMB.ShiftSpeed * dt)
		if weightShift.Magnitude > 1 then
			weightShift = weightShift.Unit
		end
	end
	local shift = weightShift
	if dynoCharge then
		-- Coil: sink down into the holds while the dyno charges.
		shift = Vector2.new(shift.X, math.max(-1, shift.Y - dynoCharge * 0.7))
	end
	local body = ClimbMath.solveBody(grips, wallNormal, shift, CLIMB)
	if root and humanoid then
		-- Hanging low from the start holds: stand on the mat instead of sinking into it.
		local standingHeight = LimbRig.standingHeight(humanoid, root)
		body = ClimbMath.clampAboveGround(body, groundBelow(body), standingHeight, CLIMB.GroundCrouch)
	end
	alignPosition.Position = body
	alignOrientation.CFrame = CFrame.lookAt(body, body - wallNormal)
end

local function updateHeight()
	if not climbing or root == nil or humanoid == nil then
		ClimbOverlay.setHeight(nil)
		return
	end
	local baseY = 0
	for _, limb in Config.LimbOrder do
		local hold = heldHold(limb)
		local route = hold and HoldUtil.getRouteFolder(hold)
		local y = route and route:GetAttribute("BaseY")
		if type(y) == "number" then
			baseY = y
			break
		end
	end
	local standingHeight = LimbRig.standingHeight(humanoid, root)
	ClimbOverlay.setHeight(Config.studsToMeters(math.max(0, root.Position.Y - baseY - standingHeight)))
end

local HINT_WALL = "<b>Click a hold</b> to grab it, or <b>drag a hand</b> onto one"
local HINT_CLIMBING = "<b>Drag</b> hands/feet to holds  ·  <b>WASD</b> shift weight (stays)  ·  <b>X</b> centre  ·  <b>Space</b> dyno  ·  <b>V</b> let go"
local HINT_DRAGGING = "Drop on a <font color=\"#5ce65c\">green</font> hold (hands) or <font color=\"#3fd1c9\">teal</font> hold (feet)"

local function updateHint()
	if drag and drag.moved then
		ClimbOverlay.setHint(HINT_DRAGGING)
	elseif climbing then
		ClimbOverlay.setHint(HINT_CLIMBING)
	elseif nearWall() then
		ClimbOverlay.setHint(HINT_WALL)
	else
		ClimbOverlay.setHint(nil)
	end
end

local function updateStamina()
	if character == nil or root == nil then
		ClimbOverlay.setStamina(nil)
		return
	end
	local value = character:GetAttribute("Stamina")
	local stamina = if type(value) == "number" then value else Config.Stamina.Max
	local fraction = stamina / Config.Stamina.Max
	ClimbOverlay.setStamina(if climbing or fraction < 0.995 then root else nil, fraction)
	if climbing and stamina < Config.Stamina.LowWarning and not warnedTired then
		warnedTired = true
		ClimbOverlay.toast("Getting tired! Rest with all four limbs on holds")
	elseif stamina > Config.Stamina.LowWarning + 15 then
		warnedTired = false
	end
end

-- Ledges on the big walls (tag Ledge) are solid to stand on but would block a body
-- climbing past them. While climbing, this client makes them non-solid for itself (it
-- simulates its own character); each turns solid again once you're off the wall and clear
-- of it, so letting go above a ledge lands you on it.
local ledgesOff: { [BasePart]: boolean } = {}
local function updateLedges(position: Vector3)
	if climbing then
		for _, ledge in CollectionService:GetTagged(Tags.Ledge) do
			if ledge:IsA("BasePart") and not ledgesOff[ledge] then
				ledgesOff[ledge] = true
				ledge.CanCollide = false
			end
		end
		return
	end
	for ledge in ledgesOff do
		local relative = ledge.CFrame:PointToObjectSpace(position)
		local half = ledge.Size / 2
		local overlapping = math.abs(relative.X) < half.X + 1
			and math.abs(relative.Z) < half.Z + 1
			and relative.Y > -half.Y - 2.6
			and relative.Y < half.Y + 1.4
		if not overlapping or ledge.Parent == nil then
			ledgesOff[ledge] = nil
			ledge.CanCollide = true
		end
	end
end

local function step(dt: number)
	if character == nil or root == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	for limb, p in pending do
		if now - p.at > CLIMB.PendingTimeout then
			pending[limb] = nil -- the server never answered: show its state again
			local actual = character:GetAttribute("Climb_" .. limb)
			if p.holdId ~= nil and actual ~= p.holdId then
				warn("[ClimbController] the server didn't answer a grab; look for 'SERVER ERROR' lines in Output")
				ClimbOverlay.toast("Server didn't answer - see Output")
			end
		end
	end

	local grips = attachedGrips()
	if climbing then
		if flightUntil then
			if #grips > 0 then
				flightUntil = nil
				flightHold = nil
				setAligns(true)
			elseif now > flightUntil then
				exitClimb()
			else
				tryCatch()
			end
		elseif #grips == 0 then
			exitClimb()
		end
	elseif #grips > 0 then
		enterClimb()
	end

	if climbing and flightUntil == nil and #grips > 0 then
		updateBody(grips, dt)
	end
	updateLedges(root.Position)
	if dynoCharge then
		dynoCharge = math.min(1, dynoCharge + dt / DYNO.ChargeTime)
		local aim, hold = dynoAim()
		local _, _, _, reaches = planDyno(dynoCharge)
		-- Aim dot: green once the charge is enough to reach the hold under the cursor.
		ClimbOverlay.setDyno(root, dynoCharge, aim, if reaches then COLORS.Hand elseif hold then COLORS.Selected else nil)
	end

	updateDrag()
	updateMarkers()
	updateRings()
	updateHeight()
	updateHint()
	updateStamina()
end

---------------------------------------------------------------------------------------
-- Character setup

local function clearCharacter()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	if climbing then
		exitClimb()
	end
	for _, tip in tips do
		tip:Destroy()
	end
	character, humanoid, root = nil, nil, nil
	alignPosition, alignOrientation = nil, nil
	tips = {}
	table.clear(pending)
	selected, drag = nil, nil
	for _, limb in Config.LimbOrder do
		ClimbOverlay.setLimbRing(limb, nil)
	end
	ClimbOverlay.setMarkers({})
	ClimbOverlay.setDragDot(nil)
	ClimbOverlay.setHint(nil)
	ClimbOverlay.setStamina(nil)
end

local function onCharacter(newCharacter: Model)
	clearCharacter()
	ClimbOverlay.showDeath(nil)
	warnedTired = false
	print("[ClimbController] character spawned, setting up climbing")
	local newHumanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if newHumanoid == nil or newRoot == nil then
		warn("[ClimbController] character has no Humanoid/HumanoidRootPart; climbing disabled for this life")
		return
	end

	-- Limb joints can arrive a moment after the character; keep looking for a few seconds.
	local rig = LimbRig.find(newCharacter)
	for _ = 1, 10 do
		if #rig.missing == 0 or newCharacter ~= player.Character then
			break
		end
		task.wait(0.5)
		rig = LimbRig.find(newCharacter)
	end
	if newCharacter ~= player.Character then
		return -- respawned while we were waiting; the newer call sets things up
	end
	if #rig.missing > 0 then
		warn(`[ClimbController] couldn't find {table.concat(rig.missing, ", ")}: you can still climb, those limbs just won't move`)
	end
	-- Roblox's own ladder climbing must never take over on the wall's features.
	newHumanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	-- Body constraints. Created by this client: it owns its character's physics, and the
	-- server checks the result (ClimbService watchdog).
	local attachment = Instance.new("Attachment")
	attachment.Name = "ClimbBody"
	attachment.Parent = newRoot
	local position = Instance.new("AlignPosition")
	position.Name = "ClimbAlignPosition"
	position.Mode = Enum.PositionAlignmentMode.OneAttachment
	position.Attachment0 = attachment
	position.MaxForce = CLIMB.AlignMaxForce
	position.MaxVelocity = CLIMB.AlignMaxVelocity
	position.Responsiveness = CLIMB.AlignResponsiveness
	position.ApplyAtCenterOfMass = true -- pull the body without tipping it
	position.Enabled = false
	position.Parent = newRoot
	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "ClimbAlignOrientation"
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.MaxTorque = CLIMB.AlignMaxForce
	orientation.Responsiveness = CLIMB.AlignResponsiveness * 1.5
	orientation.Enabled = false
	orientation.Parent = newRoot

	local newTips: { [string]: Attachment } = {}
	local count, twoBone = 0, 0
	for limb, chain in rig.chains do
		local tip = Instance.new("Attachment")
		tip.Name = `ClimbTip_{limb}`
		tip.Position = chain.tipOffset
		tip.Parent = chain.tipPart
		newTips[limb] = tip
		count += 1
		if chain.lower then
			twoBone += 1
		end
	end

	character, humanoid, root = newCharacter, newHumanoid, newRoot
	alignPosition, alignOrientation = position, orientation
	tips = newTips
	local jointKind = "Motor6D"
	for _, chain in rig.chains do
		jointKind = chain.upper.instance.ClassName
		break
	end
	print(`[ClimbController] ready: {newHumanoid.RigType.Name} rig ({jointKind} joints), {count}/4 limbs, {twoBone} with elbows/knees`)

	table.insert(characterConnections, newCharacter.AttributeChanged:Connect(function(name)
		local limb = string.match(name, "^Climb_(.+)$")
		local p = limb and pending[limb]
		if limb and p then
			local value = newCharacter:GetAttribute(name)
			if value == p.holdId then
				pending[limb] = nil -- the server agreed
			end
		end
	end))
	-- Ragdoll (RagdollService): go limp, then get back up.
	local function onRagdollChanged()
		if isDown(newCharacter) then
			if climbing then
				exitClimb()
			end
			drag, selected, dynoCharge = nil, nil, nil
			newHumanoid:ChangeState(Enum.HumanoidStateType.Physics)
			local reason = newCharacter:GetAttribute("FellReason")
			if newHumanoid.Health > 0 then
				if reason == "Exhausted" then
					ClimbOverlay.toast("Too tired - you peeled off the wall!")
				elseif reason == "MissedDyno" then
					ClimbOverlay.toast("Missed the dyno!")
				end
			end
		elseif newHumanoid.Health > 0 then
			newHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			local fall = newCharacter:GetAttribute("LastFall")
			if type(fall) == "number" and fall > 0 then
				ClimbOverlay.toast(`Ouch! {fall} m fall`)
			end
		end
	end
	table.insert(characterConnections, newCharacter:GetAttributeChangedSignal("Ragdolled"):Connect(onRagdollChanged))
	if isDown(newCharacter) then
		onRagdollChanged()
	end

	table.insert(characterConnections, newHumanoid.Died:Connect(function()
		local fall = newCharacter:GetAttribute("FallDeath")
		local reason = newCharacter:GetAttribute("FellReason")
		local subtitle = if reason == "Exhausted" then "You ran out of grip." else "Respawning..."
		if type(fall) == "number" then
			ClimbOverlay.showDeath(`You fell {fall} m`, subtitle)
		else
			ClimbOverlay.showDeath("You died", "Respawning...")
		end
		clearCharacter()
	end))
end

---------------------------------------------------------------------------------------

function ClimbController.Init()
	requestEvent = Remotes.event("ClimbRequest")
	ClimbOverlay.init()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.RespectCanCollide = true

	local ok, playerModule = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
	end)
	if ok and playerModule then
		controls = playerModule:GetControls()
	else
		warn("[ClimbController] PlayerModule not found; WASD weight shift disabled")
	end
end

function ClimbController.Start()
	CollectionService:GetInstanceAddedSignal(Tags.Hold):Connect(indexHold)
	CollectionService:GetInstanceRemovedSignal(Tags.Hold):Connect(unindexHold)
	for _, hold in CollectionService:GetTagged(Tags.Hold) do
		indexHold(hold)
	end

	Remotes.event("ClimbRejected").OnClientEvent:Connect(function(limb: string, reason: string)
		pending[limb] = nil
		ClimbOverlay.toast(`Can't grab: {reason}`)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginPointer(input)
			return
		end
		for _, limb in Config.LimbOrder do
			if input.KeyCode == Config.Limbs[limb].Key and (climbing or nearWall()) then
				selected = if selected == limb then nil else limb
				return
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			pointer = UserInputService:GetMouseLocation()
		elseif input.UserInputType == Enum.UserInputType.Touch and drag ~= nil and drag.input == (input :: InputObject?) then
			pointer = viewportPoint(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			endPointer(input)
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RunService.RenderStepped:Connect(step)
	RunService.PreSimulation:Connect(animateAll)
end

return ClimbController
