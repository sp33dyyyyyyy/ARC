-- Client climbing: "Hand-over-Hand" wall climbing, stamina, blackouts, ragdoll
-- falls, chalk and wind.
--
-- Hand-over-Hand:
--   * Walk or jump into a tower (anything tagged "Climbable") to grab on. SPACE
--     facing a tower grabs too, and SPACE while falling catches the wall (if
--     you're not falling too fast).
--   * W/S climb up/down in hand-over-hand pulls; A/D shuffle sideways.
--     (Touch / gamepad: push toward the wall to climb.)
--   * SPACE while climbing leaps up the wall: fast, but costs extra stamina.
--   * Q lets go.
--   * Hang still with your hands on a yellow rest bar to recover stamina; that
--     also saves a checkpoint. At the top you climb straight over onto the summit.
--
-- The body is held on the wall with AlignPosition/AlignOrientation on the
-- HumanoidRootPart (the client owns its character's physics, so this
-- replicates). ClimbAnimator draws the procedural climbing animation.
--
-- Stamina runs on the client because only the owning client knows its exact
-- climbing state every frame. That is safe: stamina only limits the player
-- themselves. Everything that has value (cash, climbs, purchases, fall damage)
-- is decided on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClimbAnimator = require(script.Parent.ClimbAnimator)
local Effects = require(script.Parent.Effects)
local Weather = require(script.Parent.Weather)

local ClimbController = {}

type Mode = "normal" | "fall" | "blackout" | "ragdoll"

local CC = Config.Climb
local ROOT_HEIGHT = 3 -- HumanoidRootPart centre above the floor when standing
local HAND_HEIGHT = 2.5 -- hands above the root while climbing
local PULSE_AVERAGE = 0.35 + 0.65 / math.pi -- mean of the pull curve below

local player = Players.LocalPlayer
local ragdollRemote = Remotes.get("Ragdoll")
local restRemote = Remotes.get("RestCheckpoint")
local poseRemote = Remotes.get("ClimbPose")
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
local phase = 0 -- hand-over-hand cycle
local lungeLeft = 0
local lungeReadyAt = 0
local climbMoving = false
local resting = false
local restLevel: number? = nil
local checkpointLevel: number? = nil
local regrabAt = 0
local autoGripUntil = 0
local sentPose = ""
local alignPos: AlignPosition? = nil
local alignOri: AlignOrientation? = nil
local climbAttachment: Attachment? = nil

local ui: any = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function boosts(): Rules.Boosts
	local b = {}
	for _, def in Config.Boosts do
		b[def.Id] = player:GetAttribute("Boost_" .. def.Id) or 0
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

local function horizontal(v: Vector3): Vector3
	local h = Vector3.new(v.X, 0, v.Z)
	return if h.Magnitude > 1e-3 then h.Unit else Vector3.zAxis
end

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
	}
end

-- Climbable wall straight "into" the wall from `origin`, or nil.
local function probeWall(origin: Vector3, normal: Vector3): RaycastResult?
	local result = Workspace:Raycast(origin + normal, -normal * (CC.WallOffset + 3), rayParams)
	if result and result.Instance:HasTag("Climbable") and math.abs(result.Normal.Y) < 0.7 then
		return result
	end
	return nil
end

-- Somewhere to stand at or just above the hold (top of the wall), or nil.
-- Uses rays (exact geometry) rather than bounding boxes, which are far larger
-- than the slanted lattice panels and wrongly reported "no room".
local function findMantle(): Vector3?
	local inward = -wallNormal
	for _, offset in { 0, 1.5, 3, 4.5, 6 } do
		local p = anchor + inward * offset
		local top = Vector3.new(p.X, anchor.Y + CC.MantleReach, p.Z)
		local hit = Workspace:Raycast(top, Vector3.new(0, -(CC.MantleReach + 4), 0), rayParams)
		if
			hit
			and hit.Normal.Y > 0.7
			and hit.Instance.CanCollide
			and not hit.Instance:HasTag("Climbable") -- stand on floors, not on trim like the parapet
			and hit.Position.Y > anchor.Y - ROOT_HEIGHT + 0.5
		then
			local stand = hit.Position + Vector3.new(0, ROOT_HEIGHT, 0)
			local headroom = Workspace:Raycast(hit.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, 5, 0), rayParams)
			local from = Vector3.new(anchor.X, stand.Y, anchor.Z)
			local path = if (stand - from).Magnitude > 0.05 then Workspace:Raycast(from, stand - from, rayParams) else nil
			if not (headroom and headroom.Instance.CanCollide) and not (path and path.Instance.CanCollide) then
				return stand
			end
		end
	end
	return nil
end

local function sendPose(pose: string)
	if pose ~= sentPose then
		sentPose = pose
		poseRemote:FireServer(pose)
	end
end

local function release(push: boolean)
	if not climbing then
		return
	end
	climbing = false
	climbMoving = false
	resting = false
	restLevel = nil
	lungeLeft = 0
	regrabAt = os.clock() + CC.RegrabDelay
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
	ClimbAnimator.setLocal("", 0)
	sendPose("")
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
	local hit: RaycastResult? = nil
	for _, height in { 0, 1.5, -1.5 } do
		local result = Workspace:Raycast(rootPart.Position + Vector3.new(0, height, 0), dir * range, rayParams)
		if result and result.Instance:HasTag("Climbable") and math.abs(result.Normal.Y) < 0.7 then
			hit = result
			break
		end
	end
	if not hit then
		return false
	end
	local wall = hit :: RaycastResult

	wallNormal = horizontal(wall.Normal)
	anchor = wall.Position + wall.Normal * CC.WallOffset
	anchor = Vector3.new(anchor.X, rootPart.Position.Y, anchor.Z)

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
	climbing = true
	autoGripUntil = 0
	airPeakY, freefallTime = nil, 0
	Effects.sound(Config.Sounds.Grab, 0.5, 1.3)
	return true
end

local function mantle(stand: Vector3)
	local rootPart = root
	release(false)
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
	if wasBlackout then
		local max = Rules.maxStamina(Config.Stamina, Config.Boosts, boosts())
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

-- After respawning at a checkpoint: grab the wall in front without any input.
function ClimbController.regrip()
	autoGripUntil = os.clock() + 2
	regrabAt = 0
end

-- SPACE / jump button: grab when free, leap when climbing.
local function onJump()
	local now = os.clock()
	if now - lastJumpRequest < 0.2 then
		return
	end
	lastJumpRequest = now
	local rootPart = root
	if climbing and rootPart then
		if now >= lungeReadyAt and lungeLeft <= 0 then
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
			if stamina > cost then
				stamina -= cost
				lungeLeft = CC.LungeDistance
				lungeReadyAt = now + CC.LungeCooldown
				Effects.sound(Config.Sounds.Click, 0.4, 0.7)
			else
				ui.overlay:toast("Too tired to leap!", "bad")
			end
		end
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
		local max = Rules.maxStamina(Config.Stamina, Config.Boosts, boosts())
		if climbing and not resting and stamina < max * Config.Wind.KnockOffFraction then
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

-- Moves the hold point along the wall. Returns true if the climber mantled.
local function stepClimb(hum: Humanoid, dt: number, b: Rules.Boosts, tower: Model?): boolean
	local vert, lat = climbInput(hum)
	local speed = Rules.climbSpeed(CC, Config.Boosts, b)
	local up = 0
	if lungeLeft > 0 then
		up = math.min(lungeLeft, CC.LungeSpeed * dt)
		lungeLeft -= up
		phase += dt * 6
	elseif vert ~= 0 then
		-- Hand-over-hand: you surge on each pull and slow between them.
		phase += dt * (speed / CC.ReachLength) * math.pi * 2 * math.abs(vert)
		local pulse = 0.35 + 0.65 * math.max(0, math.sin(phase * 2))
		up = vert * speed * dt * pulse / PULSE_AVERAGE
	end
	if lat ~= 0 and lungeLeft <= 0 then
		phase += dt * (CC.SideSpeed / CC.ReachLength) * math.pi * math.abs(lat)
	end
	local side = lat * CC.SideSpeed * dt
	climbMoving = math.abs(up) > 1e-3 or math.abs(side) > 1e-3

	local probe = probeWall(anchor, wallNormal)
	local n = if probe then probe.Normal else wallNormal
	local wallUp = (Vector3.yAxis - n * n:Dot(Vector3.yAxis)).Unit
	local right = (-wallNormal):Cross(Vector3.yAxis)

	-- Going up into something solid overhead: climb onto it if there's room.
	if up > 0 then
		local ceiling = Workspace:Raycast(anchor + Vector3.new(0, 2.4, 0), Vector3.new(0, up + 0.6, 0), rayParams)
		if ceiling and ceiling.Instance.CanCollide then
			local stand = findMantle()
			if stand then
				mantle(stand)
				return true
			end
			up = 0
			lungeLeft = 0
		end
	end
	-- Going down: feet reach the ground -> step off.
	if up < 0 then
		local floor = Workspace:Raycast(anchor, Vector3.new(0, -(ROOT_HEIGHT + 0.3 - up), 0), rayParams)
		if floor and floor.Normal.Y > 0.7 then
			release(false)
			return false
		end
	end

	local candidate = anchor + wallUp * up
	if up > 0 and not probeWall(candidate + Vector3.new(0, 1.5, 0), wallNormal) then
		-- The wall ends above us: climb over the top.
		local stand = findMantle()
		if stand then
			mantle(stand)
			return true
		end
		candidate = anchor
		lungeLeft = 0
	end
	local hit = probeWall(candidate, wallNormal)
	if hit then
		candidate = hit.Position + hit.Normal * CC.WallOffset
	else
		candidate = anchor
	end

	if side ~= 0 then
		local sideHit = probeWall(candidate + right * side, wallNormal)
		if sideHit then
			candidate = sideHit.Position + sideHit.Normal * CC.WallOffset
		end
	end

	-- Rest bars: stop with your hands on one to hang there and breathe.
	restLevel = restBarAt(tower, candidate.Y + HAND_HEIGHT)
	resting = restLevel ~= nil and not climbMoving and lungeLeft <= 0
	if resting and restLevel then
		-- Settle the hands onto the bar.
		local targetY = restLevel - HAND_HEIGHT
		candidate = Vector3.new(candidate.X, candidate.Y + (targetY - candidate.Y) * math.min(1, dt * 6), candidate.Z)
		if checkpointLevel ~= restLevel then
			checkpointLevel = restLevel
			restRemote:FireServer(wallNormal)
		end
	end

	if probe then
		wallNormal = horizontal(probe.Normal)
	end
	anchor = candidate
	local ap, ao = alignPos, alignOri
	if ap and ao then
		ap.Position = anchor
		ao.CFrame = CFrame.lookAt(anchor, anchor - wallNormal)
	end

	local pose = if lungeLeft > 0 then "leap" elseif resting then "rest" else "climb"
	ClimbAnimator.setLocal(pose, phase)
	sendPose(pose)
	return false
end

local function statusFor(grounded: boolean, frac: number, nearWall: boolean): (string, Color3?)
	if mode == "blackout" then
		return "Blacked out...", Color3.fromRGB(255, 86, 86)
	elseif mode == "fall" then
		return "Falling! (SPACE to catch the wall)", Color3.fromRGB(255, 86, 86)
	elseif mode == "ragdoll" then
		return "Ragdolling (press R to get up)", Color3.fromRGB(255, 196, 46)
	elseif climbing and resting then
		return "Resting on a rest bar...", Color3.fromRGB(88, 224, 132)
	elseif climbing and frac < Config.Stamina.DangerFraction then
		return "Out of breath! Get to a rest bar!", Color3.fromRGB(255, 86, 86)
	elseif climbing and climbMoving then
		return "Climbing...  (SPACE: leap, Q: let go)", nil
	elseif climbing and restLevel == nil then
		return "Holding on (still draining)", Color3.fromRGB(255, 200, 60)
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
	local max = Rules.maxStamina(Config.Stamina, Config.Boosts, b)
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
				grab(horizontal(rootPart.CFrame.LookVector), CC.GripRange, true)
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

		local ctx = drainContext(tower, climbMoving or lungeLeft > 0, now, pos.Y)
		local rate = Rules.staminaRate(Config.Stamina, Config.Chalk, Config.Wind, Config.Boosts, b, ctx, grounded)
		stamina = Rules.stepStamina(stamina, rate, dt, max)

		if climbing and stamina <= 0 then
			enterRagdoll("blackout", pos.Y)
		end
		if grounded and not lastGrounded and stamina < max then
			Effects.sound(Config.Sounds.Click, 0.25, 0.8)
		end
		lastGrounded = grounded

		if not climbing and tower then
			local look = horizontal(rootPart.CFrame.LookVector)
			local hit = Workspace:Raycast(pos, look * (CC.GripRange + 1), rayParams)
			nearWall = hit ~= nil and hit.Instance:HasTag("Climbable")
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
	sentPose = ""
	cooldownUntil = os.clock() + 1.5 -- respawning at a checkpoint can start mid-air
	stamina = Rules.maxStamina(Config.Stamina, Config.Boosts, boosts())
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
	ClimbAnimator.start()
	Remotes.get("Gust").OnClientEvent:Connect(onGust)
	UserInputService.JumpRequest:Connect(onJump)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RunService.Heartbeat:Connect(step)
end

return ClimbController
