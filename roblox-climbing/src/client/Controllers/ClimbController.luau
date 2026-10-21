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
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))

local ClimbOverlay = require(script.Parent:WaitForChild("ClimbOverlay"))

local CLIMB = Config.Climb
local DYNO = CLIMB.Dyno
local COLORS = CLIMB.Colors
local ACTION_DYNO = "ClimbDyno"
local ACTION_LET_GO = "ClimbLetGo"
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
local groundParams = RaycastParams.new()

-- Character
local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local limbParts: { [string]: BasePart } = {}
local ik: { [string]: IKControl } = {}
local alignPosition: AlignPosition? = nil
local alignOrientation: AlignOrientation? = nil
local characterConnections: { RBXScriptConnection } = {}

-- Holds by HoldId (only the ones streamed in near this player)
local holdsById: { [string]: BasePart } = {}

-- Climb state
local pending: { [string]: Pending } = {}
local climbing = false
local selected: string? = nil
local drag: Drag? = nil
local pointer: Vector2? = nil -- viewport coordinates
local dragTargets: { [string]: Attachment } = {}
local dynoCharge: number? = nil
local flightUntil: number? = nil
local flightHold: BasePart? = nil -- the hold a dyno is aimed at
local wallNormal = Vector3.zAxis

---------------------------------------------------------------------------------------
-- Holds

local function indexHold(instance: Instance)
	local id = instance:GetAttribute("HoldId")
	if instance:IsA("BasePart") and type(id) == "string" then
		holdsById[id] = instance
	end
end

local function unindexHold(instance: Instance)
	local id = instance:GetAttribute("HoldId")
	if type(id) == "string" and holdsById[id] == instance then
		holdsById[id] = nil
	end
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
end

local function enterClimb()
	if climbing or humanoid == nil then
		return
	end
	climbing = true
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
	for limb, part in limbParts do
		local screen, onScreen = camera:WorldToViewportPoint(part.Position)
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
	for _, hold in holdsById do
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
		local part = limbParts[limb]
		if part and accepts(limb, hold) and inReach(limb, hold) and heldId(limb) ~= holdId(hold) then
			local score = (part.Position - gripPosition(hold)).Magnitude + (if heldId(limb) then 100 else 0)
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
		local hand = limbParts[limb]
		if hand and heldId(limb) == nil then
			local distance = (hand.Position - gripPosition(hold)).Magnitude
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
		local hand = limbParts[limb]
		if hand and heldId(limb) == nil then
			local hold = nearestHold(hand.Position, DYNO.CatchRadius, function(h)
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
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
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
		dragTargets[current.limb].WorldPosition = target
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
	for _, hold in holdsById do
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
		ClimbOverlay.setLimbRing(limb, if show then limbParts[limb] else nil, color, active)
	end
end

local function updateIK()
	for limb, control in ik do
		local target: Instance? = nil
		if drag and drag.limb == limb and drag.moved then
			target = dragTargets[limb]
		elseif flightUntil == nil then
			local hold = heldHold(limb)
			target = hold and hold:FindFirstChild(HoldUtil.GRIP_ATTACHMENT)
		elseif flightHold and limbKind(limb) == "Hand" then
			-- Mid-dyno both hands reach for the target hold.
			target = flightHold:FindFirstChild(HoldUtil.GRIP_ATTACHMENT)
		end
		-- Written every frame: the server also sets these, and this client's view of its own
		-- character must follow its predictions.
		if control.Target ~= target then
			control.Target = target :: any
		end
		local enabled = target ~= nil
		if control.Enabled ~= enabled then
			control.Enabled = enabled
		end
	end
end

-- Height of the floor under `position` (collidable parts only, so holds are ignored).
local function groundBelow(position: Vector3): number?
	groundParams.FilterDescendantsInstances = if character then { character } else {}
	local result = Workspace:Raycast(position + Vector3.yAxis, Vector3.yAxis * -12, groundParams)
	return if result then result.Position.Y else nil
end

local function updateBody(grips: { ClimbMath.Grip })
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

	local shift = Vector2.zero
	if controls then
		local move: Vector3 = controls:GetMoveVector()
		shift = Vector2.new(move.X, -move.Z)
		if shift.Magnitude > 1 then
			shift = shift.Unit
		end
	end
	local body = ClimbMath.solveBody(grips, wallNormal, shift, CLIMB)
	if root and humanoid then
		-- Hanging low from the start holds: stand on the mat instead of sinking into it.
		local standingHeight = humanoid.HipHeight + root.Size.Y / 2
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
	local standingHeight = humanoid.HipHeight + root.Size.Y / 2
	ClimbOverlay.setHeight(Config.studsToMeters(math.max(0, root.Position.Y - baseY - standingHeight)))
end

local function step(dt: number)
	if character == nil or root == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	for limb, p in pending do
		if now - p.at > CLIMB.PendingTimeout then
			pending[limb] = nil -- the server never answered: show its state again
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
		updateBody(grips)
	end
	if dynoCharge then
		dynoCharge = math.min(1, dynoCharge + dt / DYNO.ChargeTime)
		local aim, hold = dynoAim()
		local _, _, _, reaches = planDyno(dynoCharge)
		-- Aim dot: green once the charge is enough to reach the hold under the cursor.
		ClimbOverlay.setDyno(root, dynoCharge, aim, if reaches then COLORS.Hand elseif hold then COLORS.Selected else nil)
	end

	updateDrag()
	updateIK()
	updateMarkers()
	updateRings()
	updateHeight()
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
	character, humanoid, root = nil, nil, nil
	alignPosition, alignOrientation = nil, nil
	table.clear(limbParts)
	table.clear(ik)
	table.clear(pending)
	selected, drag = nil, nil
	for _, limb in Config.LimbOrder do
		ClimbOverlay.setLimbRing(limb, nil)
	end
	ClimbOverlay.setMarkers({})
	ClimbOverlay.setDragDot(nil)
end

local function onCharacter(newCharacter: Model)
	clearCharacter()
	local newHumanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if newHumanoid == nil or newRoot == nil or newHumanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end

	local parts: { [string]: BasePart } = {}
	local controlsByLimb: { [string]: IKControl } = {}
	for _, limb in Config.LimbOrder do
		local def = Config.Limbs[limb]
		local part = newCharacter:WaitForChild(def.EndEffector, 10)
		local control = newHumanoid:WaitForChild(`Climb_{limb}`, 10) -- made by ClimbService
		if not (part and part:IsA("BasePart") and control and control:IsA("IKControl")) then
			warn(`[ClimbController] {limb} is missing its part or IKControl; climbing disabled`)
			return
		end
		parts[limb] = part
		controlsByLimb[limb] = control
	end
	if newCharacter ~= player.Character then
		return -- respawned while we were waiting; the newer call sets things up
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

	character, humanoid, root = newCharacter, newHumanoid, newRoot
	alignPosition, alignOrientation = position, orientation
	limbParts, ik = parts, controlsByLimb

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
	table.insert(characterConnections, newHumanoid.Died:Connect(clearCharacter))
end

---------------------------------------------------------------------------------------

function ClimbController.Init()
	requestEvent = Remotes.event("ClimbRequest")
	ClimbOverlay.init()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.RespectCanCollide = true

	for _, limb in Config.LimbOrder do
		local target = Instance.new("Attachment")
		target.Name = `ClimbDragTarget_{limb}`
		target.Parent = Workspace.Terrain
		dragTargets[limb] = target
	end

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
end

return ClimbController
