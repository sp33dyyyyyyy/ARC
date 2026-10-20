-- Client climbing: rock climbing, stamina, blackouts, ragdoll falls, chalk, wind.
--
-- Rock climbing:
--   * Walk or jump into a tower to grab on. Skyscraper glass ("Climbable") can
--     be gripped anywhere; telecom towers only on their actual members (legs,
--     braces and girts, tagged "ClimbHold" - see WallClimb's lattice mode). SPACE
--     facing a tower grabs too, and SPACE while falling catches the wall (if
--     you're not falling too fast).
--   * You climb in discrete moves. Each move, one hand reaches for the next hold
--     while your body stays put, then you pull up as the opposite leg pushes.
--     Hands alternate; holding W/S chains moves, A/D traverse sideways.
--     (Touch / gamepad: push toward the wall to climb.)
--   * SPACE while climbing is a dyno: both hands fling up and you catch a hold
--     much higher. Fast, but costs extra stamina.
--   * Q lets go.
--   * Hang still with your hands on a yellow rest bar to recover stamina; that
--     also saves a checkpoint. At the top you climb straight over onto the summit.
--   * F clips your rope in: a carabiner on a telecom tower's beam, or a suction
--     cup on skyscraper glass. The rope is Config.Rope.Length long, so clip in
--     again higher as you go. Clipped, wind can't knock you off, you can rest
--     hanging on the rope, and the rope catches you if you fall. X unclips.
--   * V rappels you down to the ground (needs the Rappel Kit power-up).
--
-- The body is held on the wall with AlignPosition/AlignOrientation on the
-- HumanoidRootPart (the client owns its character's physics, so this
-- replicates). Limbs stop colliding while you climb so they can't snag the wall.
-- ClimbAnimator plays Roblox's standard climb animation to match.
--
-- Stamina runs on the client because only the owning client knows its exact
-- climbing state every frame. That is safe: stamina only limits the player
-- themselves. Everything that has value (cash, climbs, purchases, fall damage)
-- is decided on the server.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Lattice = require(ReplicatedStorage.Shared.Lattice)
local ClimbAnimator = require(script.Parent.ClimbAnimator)
local Effects = require(script.Parent.Effects)
local Weather = require(script.Parent.Weather)
local WallClimb = require(script.Parent.WallClimb)

local ClimbController = {}

type Mode = "normal" | "fall" | "blackout" | "ragdoll"

local CC = Config.Climb
local HAND_HEIGHT = WallClimb.HAND_HEIGHT

local player = Players.LocalPlayer
local ragdollRemote = Remotes.get("Ragdoll")
local restRemote = Remotes.get("RestCheckpoint")
local ropeRemote = Remotes.get("Rope")
local rng = Random.new()

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local stamina = Config.Stamina.Base
local mode: Mode = "normal"
local ragdollTime, settleTime = 0, 0
local airPeakY: number? = nil
local freefallTime = 0
local cooldownUntil = 0
local gustUntil = 0
local gustDir = Vector3.zero
local lastGrounded = true
local lastJumpRequest = 0

-- Climb state
local climbing = false
local anchor = Vector3.zero -- where the root is held
local wallNormal = Vector3.zAxis -- horizontal, pointing out of the wall
type Move = WallClimb.Move
local move: Move? = nil
local moveCount = 0 -- drives which hand leads (and the animation cycle)
local lungeReadyAt = 0
local climbMoving = false
local savedCollisions: { [BasePart]: boolean } = {}
local ropeTaut = false -- last move was blocked by the rope's length
local noHold = false -- nothing on the lattice within reach above
local nextClipScan, clipInReach = 0, false
local groundedSince = 0
-- Rappel (Rappel Kit power-up)
local rappelling = false
local rappelVisual: Instance? = nil
local resting = false
local restLevel: number? = nil
local checkpointLevel: number? = nil
local regrabAt = 0
local autoGripUntil = 0
local alignPos: AlignPosition? = nil
local alignOri: AlignOrientation? = nil
local climbAttachment: Attachment? = nil

local ui: any = nil

-- Lattice climbing: the telecom tower you're on (or reaching for), and each
-- tower's members as segments (built once per tower).
local holdTower: Model? = nil
local segmentCache: { [Model]: { Lattice.Segment } } = {}
local clipBarCache: { [Model]: { Lattice.Segment } } = {}

local function towerSegments(maybeTower: Model?): { Lattice.Segment }
	if not maybeTower then
		return {}
	end
	local tower = maybeTower :: Model
	local cached = segmentCache[tower]
	if cached then
		return cached
	end
	local list = {}
	for _, part in tower:GetDescendants() do
		if part:IsA("BasePart") and part:HasTag("ClimbHold") then
			table.insert(list, Lattice.segment(part))
		end
	end
	if #list > 0 then
		segmentCache[tower] = list -- (empty means it hasn't replicated yet)
	end
	return list
end

local function isLattice(tower: Model?): boolean
	return tower ~= nil and tower:GetAttribute("Kind") == "Telecom"
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- decorations you can walk through aren't walls

local world: WallClimb.World = {
	cast = function(origin, direction)
		return Workspace:Raycast(origin, direction, rayParams)
	end,
	climbable = function(instance)
		return instance:HasTag("Climbable")
	end,
	solid = function(instance)
		return instance.CanCollide
	end,
	noStand = function(instance)
		return instance:HasTag("NoStand")
	end,
	holds = function()
		return towerSegments(holdTower)
	end,
	faceNormal = function(point)
		local tower = holdTower
		return if tower then Lattice.faceNormal(tower.WorldPivot, point) else wallNormal
	end,
}

local function boosts(): Rules.Boosts
	local b = {}
	for _, def in Config.Boosts do
		b[def.Id] = player:GetAttribute("Boost_" .. def.Id) or 0
	end
	for _, pass in Config.GamePasses do
		if player:GetAttribute("Pass_" .. pass.Id) == true then
			b["Pass_" .. pass.Id] = 1
		end
	end
	return b
end

local function currentTower(pos: Vector3): Model?
	local towers = Workspace:FindFirstChild("Towers")
	if not towers then
		return nil
	end
	for _, tower in towers:GetChildren() do
		local radius = tower:GetAttribute("Radius")
		if radius and tower:IsA("Model") then
			local p = tower.WorldPivot.Position
			if math.abs(pos.X - p.X) <= radius and math.abs(pos.Z - p.Z) <= radius then
				return tower
			end
		end
	end
	return nil
end

-- The rest bar your hands are on (its height), if any.
local function restBarAt(tower: Model?, handY: number): number?
	if not tower then
		return nil
	end
	local levels = tostring((tower :: Model):GetAttribute("RestLevels") or "")
	for value in string.gmatch(levels, "[^,]+") do
		local y = tonumber(value)
		if y and math.abs(handY - y) <= CC.RestBarReach then
			return y
		end
	end
	return nil
end

local function chalkRemaining(): number
	return math.max(0, (player:GetAttribute("ChalkUntil") or 0) - Workspace:GetServerTimeNow())
end

local horizontal = WallClimb.horizontal

local function drainContext(tower: Model?, moving: boolean, now: number, y: number): Rules.DrainContext
	return {
		climbing = climbing,
		moving = moving,
		towerMultiplier = if tower then tower:GetAttribute("DrainMultiplier") or 1 else 1,
		slippery = if tower then tower:GetAttribute("Slippery") == true else false,
		chalk = chalkRemaining() > 0,
		gust = now < gustUntil and y > Config.Wind.MinHeight,
		weatherMultiplier = Weather.drainMultiplier(),
		resting = resting,
		roped = rappelling or player:GetAttribute("RopeAnchor") ~= nil,
	}
end

local function probeWall(origin: Vector3, normal: Vector3): WallClimb.Hit?
	return WallClimb.probe(world, CC, origin, normal)
end

local function findMantle(): Vector3?
	return WallClimb.findMantle(world, CC, anchor, wallNormal)
end

local function release(push: boolean)
	if not climbing then
		return
	end
	climbing = false
	climbMoving = false
	noHold = false
	resting = false
	restLevel = nil
	move = nil
	regrabAt = os.clock() + CC.RegrabDelay
	for part, canCollide in savedCollisions do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
	savedCollisions = {}
	if alignPos then
		alignPos:Destroy()
		alignPos = nil
	end
	if alignOri then
		alignOri:Destroy()
		alignOri = nil
	end
	if climbAttachment then
		climbAttachment:Destroy()
		climbAttachment = nil
	end
	ClimbAnimator.set("")
	rappelling = false
	if rappelVisual then
		rappelVisual:Destroy()
		rappelVisual = nil
	end
	local hum, rootPart = humanoid, root
	if hum then
		hum.PlatformStand = false
	end
	if rootPart then
		airPeakY = rootPart.Position.Y
		if push then
			rootPart.AssemblyLinearVelocity = wallNormal * 10
		end
	end
	cooldownUntil = os.clock() + 0.3
end

local attachToWall: (Vector3, Vector3) -> boolean

-- Grab the climbable wall along `dir` within `range`, if any.
local function grab(dir: Vector3, range: number, quiet: boolean?): boolean
	local hum, rootPart = humanoid, root
	if climbing or mode ~= "normal" or not hum or not rootPart or hum.Health <= 0 then
		return false
	end
	if rootPart.AssemblyLinearVelocity.Y < -CC.CatchMaxFallSpeed then
		if not quiet then
			ui.overlay:toast("Falling too fast to grab!", "bad")
		end
		return false
	end
	local tower = currentTower(rootPart.Position)
	local hold, normal
	holdTower = if isLattice(tower) then tower else nil
	if holdTower then
		hold, normal = WallClimb.latticeGrab(world, CC, rootPart.Position, dir, range)
	else
		hold, normal = WallClimb.grab(world, CC, rootPart.Position, dir, range)
	end
	if not hold or not normal then
		return false
	end
	return attachToWall(hold, normal)
end

-- Hold the body on the wall at `hold`, facing it.
function attachToWall(hold: Vector3, normal: Vector3): boolean
	local hum, rootPart = humanoid, root
	if climbing or not hum or not rootPart then
		return false
	end
	wallNormal = normal
	anchor = hold

	local att = Instance.new("Attachment")
	att.Name = "ClimbAttachment"
	att.Parent = rootPart
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.MaxForce = 200000
	ap.Responsiveness = 60
	ap.Position = anchor
	ap.Parent = rootPart
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 200000
	ao.Responsiveness = 50
	ao.CFrame = CFrame.lookAt(anchor, anchor - wallNormal)
	ao.Parent = rootPart
	climbAttachment, alignPos, alignOri = att, ap, ao

	hum.PlatformStand = true
	rootPart.AssemblyLinearVelocity = Vector3.zero
	-- Limbs reach toward the wall; stop them colliding so they can't snag it.
	local character = rootPart.Parent
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part ~= rootPart then
				savedCollisions[part] = part.CanCollide
				part.CanCollide = false
			end
		end
	end
	climbing = true
	move = nil
	autoGripUntil = 0
	airPeakY, freefallTime = nil, 0
	Effects.sound(Config.Sounds.Grab, 0.5, 1.3)
	return true
end

local function mantle(stand: Vector3)
	local rootPart = root
	release(false)
	if player:GetAttribute("RopeAnchor") ~= nil then
		ropeRemote:FireServer("unclip")
	end
	if rootPart then
		rootPart.CFrame = CFrame.lookAt(stand, stand - wallNormal)
		rootPart.AssemblyLinearVelocity = Vector3.zero
	end
	local hum = humanoid
	if hum then
		hum:ChangeState(Enum.HumanoidStateType.Landed)
	end
	Effects.sound(Config.Sounds.Click, 0.35, 1.2)
end

local function enterRagdoll(kind: Mode, startY: number?)
	release(false)
	local hum, rootPart = humanoid, root
	if mode ~= "normal" or not hum or not rootPart or hum.Health <= 0 then
		return
	end
	mode = kind
	ragdollTime, settleTime = 0, 0
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	ragdollRemote:FireServer(true, startY or rootPart.Position.Y)
	-- A little tumble so it reads as a limp body, not a statue.
	rootPart:ApplyAngularImpulse(
		Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-1, 1)) * rootPart.AssemblyMass * 6
	)
	if kind == "blackout" then
		ui.overlay:blackout(true)
		Effects.sound(Config.Sounds.Bonk, 0.8)
	elseif kind == "fall" then
		Effects.sound(Config.Sounds.Fall, 0.7)
	end
end

local function exitRagdoll()
	if mode == "normal" then
		return
	end
	local wasBlackout = mode == "blackout"
	mode = "normal"
	cooldownUntil = os.clock() + 0.8
	airPeakY, freefallTime = nil, 0
	ragdollRemote:FireServer(false)
	local hum = humanoid
	if hum and hum.Health > 0 then
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		Effects.sound(Config.Sounds.GetUp, 0.6)
	end
	if player:GetAttribute("RopeAnchor") ~= nil then
		-- The rope caught you: grab the wall again straight away.
		ClimbController.regrip()
	end
	if wasBlackout then
		local max = Rules.maxStamina(Config.Stamina, Config.Boosts, boosts(), Config.GamePasses)
		stamina = math.max(stamina, max * Config.Stamina.WakeFraction)
		ui.overlay:blackout(false)
	end
end

function ClimbController.toggleRagdoll()
	if mode == "ragdoll" and ragdollTime > 0.4 then
		exitRagdoll()
	elseif mode == "normal" and root then
		enterRagdoll("ragdoll", (root :: BasePart).Position.Y)
	end
end

function ClimbController.letGo()
	release(true)
end

function ClimbController.isClimbing(): boolean
	return climbing
end

-- The best rope clip point within reach of your hands, and what it is.
local function findClipPoint(): (Vector3?, string?)
	local rootPart = root
	if not rootPart then
		return nil, nil
	end
	local tower = currentTower(rootPart.Position)
	if not tower then
		return nil, nil
	end
	local hands = if climbing then anchor + Vector3.new(0, HAND_HEIGHT, 0) else rootPart.Position + Vector3.new(0, 1.5, 0)
	if isLattice(tower) then
		-- Carabiner onto the nearest horizontal beam (the server checks it with
		-- the same Lattice maths, so they always agree).
		local bars = clipBarCache[tower]
		if not bars then
			bars = {}
			for _, bar in CollectionService:GetTagged("ClipBar") do
				if bar:IsA("BasePart") and bar:IsDescendantOf(tower) then
					table.insert(bars, Lattice.segment(bar))
				end
			end
			if #bars > 0 then
				clipBarCache[tower] = bars
			end
		end
		local best = Lattice.nearest(bars, hands, Config.Rope.Reach)
		return best, if best then "carabiner" else nil
	end
	-- Suction cup straight onto the glass in front of your hands.
	if not climbing then
		return nil, nil
	end
	local hit = probeWall(hands, wallNormal)
	if hit then
		return hit.Position + hit.Normal * 0.3, "suction"
	end
	return nil, nil
end

function ClimbController.clip()
	if not climbing then
		ui.overlay:toast("Grab onto a tower first, then clip in (F).", "bad")
		return
	end
	local point, kind = findClipPoint()
	if not point then
		ui.overlay:toast("Nothing to clip into here - climb closer to a beam.", "bad")
		return
	end
	ropeRemote:FireServer("clip", point)
	ropeTaut = false
	-- Reach up and clip it in (the server flies the gear onto the beam).
	ClimbAnimator.gesture("point", 0.5, 1.6)
	Effects.sound(Config.Sounds.Grab, 0.4, if kind == "suction" then 0.7 else 1.6)
end

-- The server's answer to a clip request (see RopeService).
function ClimbController.onRopeResult(ok: boolean, text: string, kind: string?)
	if ok then
		Effects.sound(Config.Sounds.Click, 0.6, if kind == "suction" then 0.6 else 2.2)
		ui.overlay:toast(text, "good")
		nextClipScan = 0
	else
		ui.overlay:toast(text, "bad")
	end
end

function ClimbController.unclip()
	if player:GetAttribute("RopeAnchor") ~= nil then
		ropeRemote:FireServer("unclip")
		ClimbAnimator.gesture("point", 0.35, 2)
		Effects.sound(Config.Sounds.Click, 0.4, 1.4)
	end
end

-- Rappel Kit: slide down the wall to the ground. Works while on a wall, or
-- standing on a summit (you go over the nearest edge).
function ClimbController.rappel()
	local rootPart = root
	if not rootPart or mode ~= "normal" then
		return
	end
	if (player:GetAttribute("Boost_Rappel") or 0) < 1 then
		ui.overlay:toast("You need the Rappel Kit (Power Up Shop) to rappel.", "bad")
		return
	end
	if rappelling then
		rappelling = false -- stop and hang where you are
		if rappelVisual then
			rappelVisual:Destroy()
			rappelVisual = nil
		end
		return
	end
	if not climbing then
		-- On a summit: go over the edge nearest to you.
		local tower = currentTower(rootPart.Position)
		local height = tower and tower:GetAttribute("Height")
		if not tower or not height or rootPart.Position.Y < height then
			ui.overlay:toast("Rappel from a tower wall or a summit.", "bad")
			return
		end
		local pivot = tower.WorldPivot
		local rel = pivot:PointToObjectSpace(rootPart.Position)
		local axis = if math.abs(rel.X) > math.abs(rel.Z)
			then Vector3.new(math.sign(rel.X), 0, 0)
			else Vector3.new(0, 0, if rel.Z == 0 then 1 else math.sign(rel.Z))
		local out = pivot:VectorToWorldSpace(axis)
		local radius = tower:GetAttribute("Radius") or 60
		local origin = Vector3.new(pivot.X, height - 4, pivot.Z) + out * radius
		local hold, normal
		if isLattice(tower) then
			-- The outermost member on that face, just below the top.
			holdTower = tower
			local q = Lattice.nearest(towerSegments(tower), Vector3.new(pivot.X, height - 4, pivot.Z) + out * 200, 260, function(p)
				return p.Y < height - 2 and Lattice.faceNormal(pivot, p):Dot(out) > 0.9
			end)
			if q then
				normal = out
				hold = q + out * CC.WallOffset - Vector3.new(0, HAND_HEIGHT, 0)
			end
		else
			holdTower = nil
			hold, normal = WallClimb.grab(world, CC, origin, -out, radius + 5)
		end
		if not hold or not normal then
			return
		end
		rootPart.CFrame = CFrame.lookAt(hold, hold - normal)
		if not attachToWall(hold, normal) then
			return
		end
	end
	ClimbController.unclip()
	rappelling = true
	move = nil
	-- A rope from where you started down to your harness (just for show).
	local top = Instance.new("Part")
	top.Anchored = true
	top.CanCollide = false
	top.CanQuery = false
	top.CanTouch = false
	top.Transparency = 1
	top.Size = Vector3.one * 0.2
	top.CFrame = CFrame.new(anchor + Vector3.new(0, 4, 0) - wallNormal * 1)
	local a0 = Instance.new("Attachment")
	a0.Parent = top
	local a1 = Instance.new("Attachment")
	a1.Parent = rootPart
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0, beam.Width1 = 0.15, 0.15
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40))
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = top
	top.Parent = Workspace
	a1.AncestryChanged:Connect(function()
		if not a1.Parent and top.Parent then
			top:Destroy()
		end
	end)
	top.Destroying:Connect(function()
		a1:Destroy()
	end)
	rappelVisual = top
	Effects.sound(Config.Sounds.Grab, 0.6, 0.6)
end

-- After respawning at a checkpoint: grab the wall in front without any input.
function ClimbController.regrip()
	autoGripUntil = os.clock() + 2
	regrabAt = 0
end

-- SPACE / jump button: grab when free, leap when climbing.
local function startLeap(now: number): boolean
	local rootPart = root
	if not rootPart or move ~= nil or now < lungeReadyAt then
		return false
	end
	local tower = currentTower(rootPart.Position)
	local rate = Rules.staminaRate(
		Config.Stamina,
		Config.Chalk,
		Config.Wind,
		Config.Boosts,
		boosts(),
		drainContext(tower, true, now, rootPart.Position.Y),
		false
	)
	local cost = Rules.lungeCost(CC, rate)
	if stamina <= cost then
		ui.overlay:toast("Too tired to leap!", "bad")
		return false
	end
	local leap = if isLattice(holdTower)
		then WallClimb.latticeLeap(world, CC, anchor, wallNormal)
		else WallClimb.planLeap(world, CC, anchor, wallNormal)
	if not leap then
		return false
	end
	local ropeAnchor = player:GetAttribute("RopeAnchor")
	if typeof(ropeAnchor) == "Vector3" and (leap.to - ropeAnchor).Magnitude > Config.Rope.Length - 0.5 then
		ui.overlay:toast("Your rope won't reach - clip in higher first (F)", "bad")
		return false
	end
	stamina -= cost
	lungeReadyAt = now + CC.LungeCooldown
	move = leap
	Effects.sound(Config.Sounds.Click, 0.4, 0.7)
	return true
end

-- SPACE / jump button: grab when free, dyno when climbing.
local function onJump()
	local now = os.clock()
	if now - lastJumpRequest < 0.2 then
		return
	end
	lastJumpRequest = now
	local rootPart = root
	if climbing and rootPart then
		startLeap(now)
	elseif mode == "normal" and rootPart then
		grab(horizontal(rootPart.CFrame.LookVector), CC.GripRange + 1)
	end
end

local function onGust(phase_: string, dir: Vector3, duration: number)
	if typeof(dir) ~= "Vector3" or typeof(duration) ~= "number" then
		return
	end
	if phase_ == "warn" then
		ui.hud:setWind("WIND GUST INCOMING - HOLD ON!")
		task.delay(duration, function()
			if os.clock() >= gustUntil then
				ui.hud:setWind(nil)
			end
		end)
	elseif phase_ == "start" then
		gustUntil = os.clock() + duration
		gustDir = dir
		ui.hud:setWind("GUST! Stamina drains faster")
		task.delay(duration, function()
			if os.clock() >= gustUntil then
				ui.hud:setWind(nil)
			end
		end)
		local hum, rootPart = humanoid, root
		if not rootPart or not hum or mode ~= "normal" or rootPart.Position.Y < Config.Wind.MinHeight then
			return
		end
		Effects.shake(duration * 0.5, 0.2)
		local max = Rules.maxStamina(Config.Stamina, Config.Boosts, boosts(), Config.GamePasses)
		local roped = player:GetAttribute("RopeAnchor") ~= nil
		if roped and climbing then
			ui.overlay:toast("Your rope held you against the wind.", "good")
		elseif climbing and not resting and stamina < max * Config.Wind.KnockOffFraction then
			-- Too tired to hold on: the wind rips you off the wall.
			local y = rootPart.Position.Y
			enterRagdoll("fall", y)
			rootPart:ApplyImpulse((gustDir + Vector3.new(0, 0.3, 0)) * rootPart.AssemblyMass * Config.Wind.AirPush)
			ui.overlay:toast("The wind blew you off!", "bad")
		elseif not climbing and hum.FloorMaterial == Enum.Material.Air then
			rootPart:ApplyImpulse(gustDir * rootPart.AssemblyMass * Config.Wind.AirPush)
		end
	end
end

-- Input -> (vertical, lateral) along the wall, each in [-1, 1].
local function climbInput(hum: Humanoid): (number, number)
	local W = UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
	local S = UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down)
	local A = UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left)
	local D = UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right)
	if W or S or A or D then
		return (if W then 1 else 0) - (if S then 1 else 0), (if D then 1 else 0) - (if A then 1 else 0)
	end
	-- Touch / gamepad: push toward the wall to climb.
	local move = hum.MoveDirection
	local right = (-wallNormal):Cross(Vector3.yAxis)
	return math.clamp(move:Dot(-wallNormal), -1, 1), math.clamp(move:Dot(right), -1, 1)
end

local function setHold(position: Vector3)
	anchor = position
	local ap, ao = alignPos, alignOri
	if ap and ao then
		ap.Position = anchor
		ao.CFrame = CFrame.lookAt(anchor, anchor - wallNormal)
	end
end

-- Advance the current move (or start the next one). Returns true if the
-- climber left the wall this frame (mantled onto a ledge or stepped off).
local function stepClimb(hum: Humanoid, dt: number, b: Rules.Boosts, tower: Model?): boolean
	if rappelling then
		-- Slide down the wall on the rope until the ground.
		local floor = Workspace:Raycast(anchor, Vector3.new(0, -(WallClimb.ROOT_HEIGHT + 1), 0), rayParams)
		if floor and floor.Normal.Y > 0.7 then
			release(false)
			ui.overlay:toast("Touched down. Nice rappel!", "good")
			return true
		end
		if isLattice(holdTower) then
			-- Slide down following the lattice's taper.
			local nextPos = WallClimb.latticeSlide(world, CC, anchor, wallNormal, Config.Rope.RappelSpeed * dt)
			if not nextPos then
				release(true)
				return true
			end
			setHold(nextPos)
		else
			local probe = probeWall(anchor, wallNormal)
			local n = if probe then probe.Normal else wallNormal
			local target = anchor - WallClimb.wallUp(n) * (Config.Rope.RappelSpeed * dt)
			local hit = probeWall(target, wallNormal)
			if not hit then
				release(true) -- ran out of wall: drop the last bit
				return true
			end
			setHold(hit.Position + hit.Normal * CC.WallOffset)
		end
		climbMoving = false
		resting = false
		ClimbAnimator.set("rappel")
		return false
	end

	local vert, lat = climbInput(hum)
	local speed = Rules.climbSpeed(CC, Config.Boosts, b)

	if not move and (vert ~= 0 or lat ~= 0) then
		local planned, action
		if isLattice(holdTower) then
			planned, action = WallClimb.latticePlan(world, CC, anchor, wallNormal, vert, lat, speed)
		else
			planned, action = WallClimb.plan(world, CC, anchor, wallNormal, vert, lat, speed)
		end
		noHold = isLattice(holdTower) and planned == nil and vert > 0 and action ~= "stepoff"
		if action == "mantle" then
			local stand = findMantle()
			if stand then
				noHold = false
				mantle(stand)
				return true
			end
		elseif action == "stepoff" then
			release(false)
			return true
		end
		-- The rope only reaches so far above your clip: clip in again higher.
		local ropeAnchor = player:GetAttribute("RopeAnchor")
		ropeTaut = planned ~= nil
			and typeof(ropeAnchor) == "Vector3"
			and (planned.to - ropeAnchor).Magnitude > Config.Rope.Length - 0.5
		if planned and not ropeTaut then
			move = planned
			if planned.kind ~= "side" then
				moveCount += 1 -- the other hand leads this time
			end
		end
	end

	local current = move
	if current then
		current.t += dt
		local f = math.clamp(current.t / current.duration, 0, 1)
		if current.kind == "side" then
			setHold(current.from:Lerp(current.to, f * f * (3 - 2 * f)))
		elseif current.kind == "leap" then
			-- Explosive launch, then hang on the catch.
			local launch = math.clamp(current.t / (current.duration - 0.15), 0, 1)
			setHold(current.from:Lerp(current.to, 1 - (1 - launch) ^ 3))
		else
			-- Reach first (body still), then pull up.
			local pull = math.clamp((f - CC.ReachFraction) / (1 - CC.ReachFraction), 0, 1)
			setHold(current.from:Lerp(current.to, pull * pull * (3 - 2 * pull)))
		end
		if isLattice(holdTower) then
			-- Turn to face whichever face of the tower you're on (corners).
			local n = world.faceNormal(anchor)
			if n:Dot(wallNormal) < 0.99 then
				wallNormal = n
				setHold(anchor)
			end
		else
			local probe = probeWall(anchor, wallNormal)
			if probe then
				wallNormal = horizontal(probe.Normal)
			end
		end
		if f >= 1 then
			move = nil
			if current.mantleAfter then
				local stand = findMantle()
				if stand then
					mantle(stand)
					return true
				end
			end
		end
	end
	climbMoving = move ~= nil

	-- Rest bars: stop with your hands on one to hang there and breathe.
	restLevel = restBarAt(tower, anchor.Y + HAND_HEIGHT)
	resting = restLevel ~= nil and not climbMoving
	if resting and restLevel then
		local targetY = restLevel - HAND_HEIGHT
		setHold(Vector3.new(anchor.X, anchor.Y + (targetY - anchor.Y) * math.min(1, dt * 6), anchor.Z))
		if checkpointLevel ~= restLevel then
			checkpointLevel = restLevel
			restRemote:FireServer(wallNormal)
		end
	end

	local m = move
	if m and m.kind == "leap" then
		ClimbAnimator.set("leap")
	elseif m then
		ClimbAnimator.set("climb", speed / CC.ClimbSpeed)
	else
		ClimbAnimator.set("hold")
	end
	return false
end

local function statusFor(grounded: boolean, frac: number, nearWall: boolean): (string, Color3?)
	if mode == "blackout" then
		return "Blacked out...", Color3.fromRGB(255, 86, 86)
	elseif mode == "fall" then
		return "Falling! (SPACE to catch the wall)", Color3.fromRGB(255, 86, 86)
	elseif mode == "ragdoll" then
		return "Ragdolling (press R to get up)", Color3.fromRGB(255, 196, 46)
	elseif rappelling then
		return "Rappelling down...  (V: stop, Q: let go)", Color3.fromRGB(110, 200, 255)
	elseif climbing and noHold and not climbMoving then
		return "No beam within reach above - move sideways (A/D) or dyno", Color3.fromRGB(255, 200, 60)
	elseif climbing and ropeTaut then
		return "Rope's at full length - clip in higher (F)", Color3.fromRGB(255, 200, 60)
	elseif climbing and resting then
		return "Resting on a rest bar...", Color3.fromRGB(88, 224, 132)
	elseif climbing and frac < Config.Stamina.DangerFraction then
		return "Out of breath! Get to a rest bar!", Color3.fromRGB(255, 86, 86)
	elseif climbing and climbMoving then
		return "Climbing...  (SPACE: dyno, Q: let go)", nil
	elseif climbing and player:GetAttribute("RopeAnchor") ~= nil then
		return "Hanging on your rope (resting)", Color3.fromRGB(88, 224, 132)
	elseif climbing and restLevel == nil then
		return "Holding on (still draining)  (F: clip rope)", Color3.fromRGB(255, 200, 60)
	elseif nearWall then
		return "Walk into the tower to climb", Color3.fromRGB(255, 196, 46)
	elseif grounded and frac < 0.999 then
		return "Catching your breath...", Color3.fromRGB(88, 224, 132)
	end
	return "Ready to climb", nil
end

local function step(dt: number)
	local hum, rootPart = humanoid, root
	if not hum or not rootPart or not hum.Parent then
		return
	end
	local b = boosts()
	local max = Rules.maxStamina(Config.Stamina, Config.Boosts, b, Config.GamePasses)
	stamina = math.min(stamina, max)
	local now = os.clock()

	if hum.Health <= 0 then
		release(false)
		if mode ~= "normal" then
			mode = "normal"
			ui.overlay:blackout(false)
		end
		return
	end

	local grounded = false
	local nearWall = false
	if mode ~= "normal" then
		ragdollTime += dt
		-- The Humanoid will try to stand up on its own; keep it limp.
		if hum:GetState() ~= Enum.HumanoidStateType.Physics then
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end
		local speed = rootPart.AssemblyLinearVelocity.Magnitude
		settleTime = if speed < Config.Fall.SettleSpeed then settleTime + dt else 0
		local minTime = if mode == "blackout" then Config.Fall.MinBlackoutTime else Config.Fall.MinRagdollTime
		local settled = settleTime >= Config.Fall.SettleTime
		if ragdollTime >= Config.Fall.MaxRagdollTime or (mode ~= "ragdoll" and ragdollTime >= minTime and settled) then
			exitRagdoll()
		end
	else
		local tower = currentTower(rootPart.Position)
		if climbing then
			if stepClimb(hum, dt, b, tower) then
				return -- climbed over the top this frame
			end
		elseif tower and now >= regrabAt then
			-- Auto-grip: walking or jumping into a tower grabs it.
			local move = hum.MoveDirection
			if now < autoGripUntil then
				-- Respawned / caught by the rope: the wall we were on first.
				if not grab(-wallNormal, CC.GripRange + 2, true) then
					grab(horizontal(rootPart.CFrame.LookVector), CC.GripRange, true)
				end
			elseif move.Magnitude > 0.5 then
				grab(horizontal(move), CC.AutoGripRange, true)
			end
		end
		local pos = rootPart.Position
		local state = hum:GetState()
		grounded = not climbing and hum.FloorMaterial ~= Enum.Material.Air

		-- Track how far we've fallen so a big drop turns into a ragdoll.
		if climbing or grounded then
			airPeakY, freefallTime = nil, 0
		else
			airPeakY = math.max(airPeakY or pos.Y, pos.Y)
			if state == Enum.HumanoidStateType.Freefall then
				freefallTime += dt
			end
		end
		if
			not climbing
			and freefallTime >= Config.Fall.AutoRagdollAfter
			and rootPart.AssemblyLinearVelocity.Y < -25
			and now > cooldownUntil
		then
			enterRagdoll("fall", airPeakY)
		end

		local ctx = drainContext(tower, climbMoving, now, pos.Y)
		local rate = Rules.staminaRate(Config.Stamina, Config.Chalk, Config.Wind, Config.Boosts, b, ctx, grounded)
		stamina = Rules.stepStamina(stamina, rate, dt, max)

		if climbing and stamina <= 0 then
			enterRagdoll("blackout", pos.Y)
		end
		-- Back on the ground: take the rope off.
		if grounded and pos.Y < 8 then
			if groundedSince == 0 then
				groundedSince = now
			elseif now - groundedSince > 0.5 and player:GetAttribute("RopeAnchor") ~= nil then
				ropeRemote:FireServer("unclip")
				groundedSince = now + 5
			end
		else
			groundedSince = 0
		end
		if grounded and not lastGrounded and stamina < max then
			Effects.sound(Config.Sounds.Click, 0.25, 0.8)
		end
		lastGrounded = grounded

		if not climbing and tower then
			local look = horizontal(rootPart.CFrame.LookVector)
			if isLattice(tower) then
				local reach = pos + Vector3.new(0, HAND_HEIGHT, 0) + look * 1.5
				nearWall = Lattice.nearest(towerSegments(tower), reach, CC.GripRange) ~= nil
			else
				local hit = Workspace:Raycast(pos, look * (CC.GripRange + 1), rayParams)
				nearWall = hit ~= nil and hit.Instance:HasTag("Climbable")
			end
		end
	end

	-- HUD -----------------------------------------------------------------------
	local pos = rootPart.Position
	local frac = stamina / max
	ui.hud:setStamina(stamina, max, Config.Stamina.DangerFraction, now)
	local text, color = statusFor(grounded, frac, nearWall)
	ui.hud:setStatus(text, color)
	ui.hud:setChalk(player:GetAttribute("Chalk") or 0, math.clamp(chalkRemaining() / Config.Chalk.Duration, 0, 1))
	ui.hud:setClimbing(climbing)
	if now >= nextClipScan then
		nextClipScan = now + 0.25
		clipInReach = climbing and player:GetAttribute("RopeAnchor") == nil and findClipPoint() ~= nil
	end
	ui.hud:setRope(player:GetAttribute("RopeKind"), clipInReach)

	local tower = currentTower(pos)
	if tower then
		local height = tower:GetAttribute("Height") or 1
		ui.hud:setAltitude(
			pos.Y,
			tower:GetAttribute("DisplayName"),
			string.format("%s  ·  $%s  ·  drain x%s", tostring(tower:GetAttribute("Difficulty")), tostring(tower:GetAttribute("Payout")), tostring(tower:GetAttribute("DrainMultiplier"))),
			pos.Y / height
		)
	else
		ui.hud:setAltitude(pos.Y, nil, nil, nil)
	end

	local breathless = if mode == "blackout" then 1 else math.clamp(1 - frac / 0.35, 0, 1)
	Effects.setBreathless(if climbing or mode == "blackout" then breathless else breathless * 0.4)
end

local function onCharacter(char: Model)
	release(false)
	humanoid, root = nil, nil -- stop stepping the old body while the new one loads
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid, root = hum, rootPart
	rayParams.FilterDescendantsInstances = { char }
	mode = "normal"
	ragdollTime, settleTime, freefallTime = 0, 0, 0
	airPeakY = nil
	checkpointLevel = nil
	cooldownUntil = os.clock() + 1.5 -- respawning at a checkpoint can start mid-air
	stamina = Rules.maxStamina(Config.Stamina, Config.Boosts, boosts(), Config.GamePasses)
	ui.overlay:blackout(false)
	Effects.setBreathless(0)
	hum.Died:Connect(function()
		if humanoid == hum then
			release(false)
			mode = "normal"
			ui.overlay:blackout(false)
			ui.overlay:toast("You died. Respawning...", "bad")
		end
	end)
end

function ClimbController.start(uiRefs: any)
	ui = uiRefs
	Remotes.get("Gust").OnClientEvent:Connect(onGust)
	UserInputService.JumpRequest:Connect(onJump)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RunService.Heartbeat:Connect(step)
end

return ClimbController
