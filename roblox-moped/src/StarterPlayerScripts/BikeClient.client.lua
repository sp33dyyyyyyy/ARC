--[[
	BikeClient  (LocalScript, StarterPlayerScripts)

	Drives the bike this player currently controls. The server marks a bike
	with Controller = our UserId when we ride it, push it, or it is coasting
	to a stop after we let go. While that is true, WE own its physics
	(network ownership) and step BikePhysics every Heartbeat.

	Controls (riding)
	  W / Up        throttle         S / Down     brake (front + rear)
	  A D / arrows  steer + lean     Space        rear brake (skid)
	  Left Shift    wheelie (throttle + low gear)
	  Z / X         shift down / up  (manual bikes; CVT mopeds ignore it)

	Start procedure: CLICK the parts on the bike (handled by BikeControls)
	  fuel tap lever, ignition key, choke lever, kick lever, starter button.
	  Click the seat to ride / get off, the handlebars to push / let go.

	Other
	  B  bring your bike(s) to you
	Pushing: click the handlebars, then just WALK. Heavier bike = slower.
	Gamepad: left stick steer, R2 throttle, L2 brake, A rear brake,
	         X wheelie, bumpers shift.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehicleData = require(Shared:WaitForChild("VehicleData"))
local PartsData = require(Shared:WaitForChild("PartsData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BikePhysics = require(Shared:WaitForChild("BikePhysics"))
local ClientState = require(Shared:WaitForChild("ClientState"))

print("[MopedDays] client scripts running")

local player = Players.LocalPlayer
local PUSH = GameConfig.Push

local bikeInput = Remotes.event("BikeInput")

local sim: any = nil
local simModel: Model? = nil
local lastSend = 0
local lastIgnoreRefresh = 0

-- smoothed rider inputs (twist-grip feel, forgiving)
local throttle, brake, steer = 0, 0, 0

local function approach(x: number, target: number, step: number): number
	if x < target then
		return math.min(x + step, target)
	end
	return math.max(x - step, target)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

----------------------------------------------------------------------------
-- Finding the bike we control
----------------------------------------------------------------------------
local function findControlled(): Model?
	local folder = Workspace:FindFirstChild("Bikes")
	if not folder then
		return nil
	end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("Controller") == player.UserId and m.PrimaryPart then
			return m
		end
	end
	return nil
end

local function refreshIgnoreList()
	if not sim then
		return
	end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	sim:setIgnore(list)
end

----------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------
local function gamepadAxis(): (number, number, number)
	-- returns steerX, throttle(R2), brake(L2)
	if not UserInputService.GamepadEnabled then
		return 0, 0, 0
	end
	local sx, r2, l2 = 0, 0, 0
	for _, s in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if s.KeyCode == Enum.KeyCode.Thumbstick1 then
			sx = math.abs(s.Position.X) > 0.15 and s.Position.X or 0
		elseif s.KeyCode == Enum.KeyCode.ButtonR2 then
			r2 = s.Position.Z
		elseif s.KeyCode == Enum.KeyCode.ButtonL2 then
			l2 = s.Position.Z
		end
	end
	return sx, r2, l2
end

local function readRideInput(dt: number)
	local ui = UserInputService
	local gx, gr2, gl2 = gamepadAxis()

	local tTarget = math.max((ui:IsKeyDown(Enum.KeyCode.W) or ui:IsKeyDown(Enum.KeyCode.Up)) and 1 or 0, gr2)
	local bTarget = math.max((ui:IsKeyDown(Enum.KeyCode.S) or ui:IsKeyDown(Enum.KeyCode.Down)) and 1 or 0, gl2)
	local sTarget = gx
	if ui:IsKeyDown(Enum.KeyCode.D) or ui:IsKeyDown(Enum.KeyCode.Right) then
		sTarget += 1
	end
	if ui:IsKeyDown(Enum.KeyCode.A) or ui:IsKeyDown(Enum.KeyCode.Left) then
		sTarget -= 1
	end
	sTarget = math.clamp(sTarget, -1, 1)

	throttle = approach(throttle, tTarget, (tTarget > throttle and 3.5 or 8) * dt)
	brake = approach(brake, bTarget, (bTarget > brake and 6 or 10) * dt)
	steer = approach(steer, sTarget, (sTarget == 0 and 7 or 4.5) * dt)

	local rear = ui:IsKeyDown(Enum.KeyCode.Space) or ui:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
	local wheelie = ui:IsKeyDown(Enum.KeyCode.LeftShift) or ui:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonX)
	return rear, wheelie
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local key = input.KeyCode

	if key == Enum.KeyCode.B then
		-- call the bike (server rate-limits and refuses while you are riding)
		if ClientState.mode ~= "Ride" then
			task.spawn(function()
				local res = Remotes.func("GarageSpawn"):InvokeServer()
				if res and not res.ok and res.reason then
					ClientState.toast = res.reason
				end
			end)
		end
		return
	end

	if ClientState.mode ~= "Ride" then
		return
	end

	if key == Enum.KeyCode.X or key == Enum.KeyCode.ButtonR1 then
		if sim then
			sim:shift(1)
		end
	elseif key == Enum.KeyCode.Z or key == Enum.KeyCode.ButtonL1 then
		if sim then
			sim:shift(-1)
		end
	end
end)

----------------------------------------------------------------------------
-- Per-frame simulation
----------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 1 / 30) -- don't explode after a lag spike

	local model = findControlled()
	if model ~= simModel then
		simModel = model
		sim = nil
		throttle, brake, steer = 0, 0, 0
		if model then
			local vehicle = VehicleData.byId[model:GetAttribute("VehicleId")]
			if vehicle then
				-- installed upgrades change the stat block the physics runs on
				vehicle = PartsData.effective(vehicle, model:GetAttribute("Mods"))
				sim = BikePhysics.new(model, vehicle)
				refreshIgnoreList()
			end
		end
		ClientState.controlling = sim and model or nil
	end

	if not sim or not model then
		ClientState.mode = "None"
		ClientState.pushStrain = 0
		ClientState.pushLeash = 0
		return
	end

	if os.clock() - lastIgnoreRefresh > 1 then
		lastIgnoreRefresh = os.clock()
		refreshIgnoreList()
	end

	local mode = model:GetAttribute("Mode")
	ClientState.mode = mode

	local input = {
		throttle = 0, brake = 0, steer = 0, rearBrake = false, wheelie = false,
		engineOn = model:GetAttribute("EngineRunning") == true,
		choke = model:GetAttribute("Choke") == true,
	}

	if mode == "Ride" then
		local rear, wheelie = readRideInput(dt)
		input.throttle, input.brake, input.steer = throttle, brake, steer
		input.rearBrake, input.wheelie = rear, wheelie
		ClientState.pushStrain, ClientState.pushLeash = 0, 0

	elseif mode == "Push" then
		-- Hands on the bars: the bike follows a grip point in front of us.
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local bars = sim.chassis:FindFirstChild("HandlebarPoint") :: Attachment?
		if hrp and hum and bars then
			local limits = BikePhysics.pushLimits(sim.vehicle, model:GetAttribute("Fuel"))
			local grip = hrp.Position + flat(hrp.CFrame.LookVector).Unit * PUSH.GripDistance
			local d = flat(grip - bars.WorldPosition)

			local cf = sim.chassis.CFrame
			local f = flat(cf.LookVector)
			f = f.Magnitude > 0.05 and f.Unit or Vector3.new(0, 0, -1)
			local r = flat(cf.RightVector)
			r = r.Magnitude > 0.05 and r.Unit or Vector3.new(1, 0, 0)
			local along, across = d:Dot(f), d:Dot(r)

			-- point the front wheel at the hands (flipped when backing up)
			input.steer = math.clamp(across / math.max(math.abs(along), 2) * 1.5, -1, 1) * (along >= -0.2 and 1 or -1)
			input.pivot = 1.0 * math.clamp(110 / limits.effectiveKg, 0.5, 1)
			input.push = { pull = d, maxAccel = limits.maxAccel, maxSpeed = limits.walkSpeed * 1.05 }

			-- if the bike lags behind, your arms stretch and you get dragged back
			local leash = math.clamp((d.Magnitude - PUSH.LeashSlack) / 3, 0, 1)
			hum.WalkSpeed = limits.walkSpeed * (1 - 0.75 * leash)
			ClientState.pushStrain = limits.strain
			ClientState.pushLeash = leash
		end
		throttle, brake, steer = 0, 0, 0

	else -- Coast: nobody holding it, let friction park it
		input.brake = 0.08
		ClientState.pushStrain, ClientState.pushLeash = 0, 0
		throttle, brake, steer = 0, 0, 0
	end

	local t = sim:step(input, dt)

	ClientState.speedKmh = t.speedKmh
	ClientState.rpm = t.rpm
	ClientState.gear = t.gear
	ClientState.gearCount = t.gearCount
	ClientState.wheelie = t.wheelie
	ClientState.skidding = t.skidding
	ClientState.grounded = t.grounded
	ClientState.throttle = input.throttle
	ClientState.brake = input.brake

	-- 10 Hz: tell the server throttle/brake/gear (fuel burn + engine sound)
	if os.clock() - lastSend > 0.1 then
		lastSend = os.clock()
		bikeInput:FireServer(input.throttle, input.brake, sim.gear)
	end
end)
