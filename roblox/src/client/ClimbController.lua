-- Client half of climbing: stamina, blackouts, ragdoll falls, chalk, wind.
--
-- Stamina runs on the client because only the owning client knows its exact
-- Humanoid state (climbing / hanging / grounded) every frame. That is safe:
-- stamina only limits the player themselves. Everything that has value (cash,
-- climbs, purchases, fall damage) is decided on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Effects = require(script.Parent.Effects)

local ClimbController = {}

type Mode = "normal" | "fall" | "blackout" | "ragdoll"

local player = Players.LocalPlayer
local ragdollRemote = Remotes.get("Ragdoll")
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

local ui: any = nil

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
			if Vector3.new(pos.X - p.X, 0, pos.Z - p.Z).Magnitude <= radius then
				return tower
			end
		end
	end
	return nil
end

local function chalkRemaining(): number
	return math.max(0, (player:GetAttribute("ChalkUntil") or 0) - Workspace:GetServerTimeNow())
end

local function enterRagdoll(kind: Mode, startY: number?)
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
	if humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
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
		enterRagdoll("ragdoll", root.Position.Y)
	end
end

function ClimbController.isClimbing(): boolean
	return humanoid ~= nil and humanoid:GetState() == Enum.HumanoidStateType.Climbing
end

local function onGust(phase: string, dir: Vector3, duration: number)
	if typeof(dir) ~= "Vector3" or typeof(duration) ~= "number" then
		return
	end
	if phase == "warn" then
		ui.hud:setWind("WIND GUST INCOMING - HOLD ON!")
		task.delay(duration, function()
			if os.clock() >= gustUntil then
				ui.hud:setWind(nil)
			end
		end)
	elseif phase == "start" then
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
		Effects.shake(duration * 0.5, 0.25)
		local climbing = hum:GetState() == Enum.HumanoidStateType.Climbing
		local max = Rules.maxStamina(Config.Stamina, Config.Boosts, boosts())
		if climbing and stamina < max * Config.Wind.KnockOffFraction then
			-- Too tired to hold on: the wind rips you off the ladder.
			enterRagdoll("fall", rootPart.Position.Y)
			rootPart:ApplyImpulse((gustDir + Vector3.new(0, 0.3, 0)) * rootPart.AssemblyMass * Config.Wind.AirPush)
			ui.overlay:toast("The wind blew you off!", "bad")
		elseif not climbing and hum.FloorMaterial == Enum.Material.Air then
			rootPart:ApplyImpulse(gustDir * rootPart.AssemblyMass * Config.Wind.AirPush)
		end
	end
end

local function statusFor(climbing: boolean, moving: boolean, grounded: boolean, frac: number): (string, Color3?)
	if mode == "blackout" then
		return "Blacked out...", Color3.fromRGB(255, 86, 86)
	elseif mode == "fall" then
		return "Falling!", Color3.fromRGB(255, 86, 86)
	elseif mode == "ragdoll" then
		return "Ragdolling (press R to get up)", Color3.fromRGB(255, 196, 46)
	elseif climbing and frac < Config.Stamina.DangerFraction then
		return "Out of breath! Get to a platform!", Color3.fromRGB(255, 86, 86)
	elseif climbing and moving then
		return "Climbing...", nil
	elseif climbing then
		return "Hanging on (still draining)", Color3.fromRGB(255, 200, 60)
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
	local pos = rootPart.Position

	if hum.Health <= 0 then
		if mode ~= "normal" then
			mode = "normal"
			ui.overlay:blackout(false)
		end
		return
	end

	local climbing, moving, grounded = false, false, false
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
		local state = hum:GetState()
		climbing = state == Enum.HumanoidStateType.Climbing
		grounded = not climbing and hum.FloorMaterial ~= Enum.Material.Air
		moving = climbing and math.abs(rootPart.AssemblyLinearVelocity.Y) > 1

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
			freefallTime >= Config.Fall.AutoRagdollAfter
			and rootPart.AssemblyLinearVelocity.Y < -25
			and now > cooldownUntil
		then
			enterRagdoll("fall", airPeakY)
		end

		local tower = currentTower(pos)
		local ctx: Rules.DrainContext = {
			climbing = climbing,
			moving = moving,
			towerMultiplier = if tower then tower:GetAttribute("DrainMultiplier") or 1 else 1,
			slippery = if tower then tower:GetAttribute("Slippery") == true else false,
			chalk = chalkRemaining() > 0,
			gust = now < gustUntil and pos.Y > Config.Wind.MinHeight,
		}
		local rate = Rules.staminaRate(Config.Stamina, Config.Chalk, Config.Wind, Config.Boosts, b, ctx, grounded)
		stamina = Rules.stepStamina(stamina, rate, dt, max)

		local walk = if climbing then Rules.climbWalkSpeed(Config.Climb, Config.Boosts, b) else Config.Climb.BaseWalkSpeed
		if hum.WalkSpeed ~= walk then
			hum.WalkSpeed = walk
		end

		if climbing and stamina <= 0 then
			enterRagdoll("blackout", pos.Y)
		end
		if grounded and not lastGrounded and stamina < max then
			Effects.sound(Config.Sounds.Click, 0.25, 0.8)
		end
		lastGrounded = grounded
	end

	-- HUD -----------------------------------------------------------------------
	local frac = stamina / max
	ui.hud:setStamina(stamina, max, Config.Stamina.DangerFraction, now)
	local text, color = statusFor(climbing, moving, grounded, frac)
	ui.hud:setStatus(text, color)
	ui.hud:setChalk(player:GetAttribute("Chalk") or 0, math.clamp(chalkRemaining() / Config.Chalk.Duration, 0, 1))

	local tower = currentTower(pos)
	if tower then
		local height = tower:GetAttribute("Height") or 1
		ui.hud:setAltitude(
			pos.Y,
			tower:GetAttribute("DisplayName"),
			string.format("$%s payout · drain x%s", tostring(tower:GetAttribute("Payout")), tostring(tower:GetAttribute("DrainMultiplier"))),
			pos.Y / height
		)
	else
		ui.hud:setAltitude(pos.Y, nil, nil, nil)
	end

	local breathless = if mode == "blackout" then 1 else math.clamp(1 - frac / 0.35, 0, 1)
	Effects.setBreathless(if climbing or mode == "blackout" then breathless else breathless * 0.4)
end

local function onCharacter(character: Model)
	humanoid, root = nil, nil -- stop stepping the old body while the new one loads
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
	mode = "normal"
	ragdollTime, settleTime, freefallTime = 0, 0, 0
	airPeakY = nil
	cooldownUntil = os.clock() + 1.5 -- respawning at a checkpoint can start mid-air
	stamina = Rules.maxStamina(Config.Stamina, Config.Boosts, boosts())
	ui.overlay:blackout(false)
	Effects.setBreathless(0)
	local hum = humanoid :: Humanoid
	hum.Died:Connect(function()
		if humanoid == hum then
			mode = "normal"
			ui.overlay:blackout(false)
			ui.overlay:toast("You died. Respawning...", "bad")
		end
	end)
end

function ClimbController.start(uiRefs: any)
	ui = uiRefs
	Remotes.get("Gust").OnClientEvent:Connect(onGust)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RunService.Heartbeat:Connect(step)
end

return ClimbController
