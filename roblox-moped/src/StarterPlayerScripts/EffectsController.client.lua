--[[
	EffectsController  (LocalScript, StarterPlayerScripts)

	Cosmetic only - nothing here changes any gameplay state.
	  * engine loop sound, pitched by rpm (all bikes, so you hear other players)
	  * exhaust smoke (more when revving, bluish clouds from two-strokes, thick
	    white when the choke is on or the engine is cold)
	  * one-shot sounds / puffs for Kick, Crank, Started, Cough, Sputter, Stall,
	    Click, Crash  (BikeEvent from the server)
	  * crash camera shake + a touch of FOV when going fast

	Sound ids come from Shared/SoundIds. Empty ids are skipped silently.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehicleData = require(Shared:WaitForChild("VehicleData"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SoundIds = require(Shared:WaitForChild("SoundIds"))
local ClientState = require(Shared:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local STUDS = GameConfig.StudsPerKmh

local rigs: { [Model]: any } = {}

local function soundId(model: Model, key: string): string
	local perBike = SoundIds.perBike[model:GetAttribute("VehicleId")]
	return (perBike and perBike[key]) or SoundIds[key] or ""
end

local function oneShot(model: Model, key: string, volume: number?, speed: number?)
	local id = soundId(model, key)
	local chassis = model.PrimaryPart
	if id == "" or not chassis then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.8
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 120
	s.Parent = chassis
	s:Play()
	Debris:AddItem(s, 6)
end

----------------------------------------------------------------------------
-- Per-bike rig: engine sound + smoke emitter
----------------------------------------------------------------------------
local function buildRig(model: Model)
	local vehicle = VehicleData.byId[model:GetAttribute("VehicleId")]
	local chassis = model.PrimaryPart
	if not (vehicle and chassis) then
		return
	end
	local rig = { vehicle = vehicle, chassis = chassis, smooth = 0 }

	local id = soundId(model, "engineLoop")
	if id ~= "" then
		local s = Instance.new("Sound")
		s.Name = "EngineLoop"
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.RollOffMaxDistance = 140
		s.RollOffMinDistance = 8
		s.Parent = chassis
		s:Play()
		rig.engine = s
	end

	local exhaust = chassis:FindFirstChild("ExhaustPoint")
	if exhaust then
		local e = Instance.new("ParticleEmitter")
		e.Name = "Smoke"
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(2, 4)
		e.SpreadAngle = Vector2.new(12, 12)
		e.EmissionDirection = Enum.NormalId.Back
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1.3) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(Color3.fromRGB(200, 205, 215))
		e.LightEmission = 0
		e.Parent = exhaust
		rig.smoke = e
	end

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "CrashSparks"
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(14, 26)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new(0.25, 0)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
	sparks.LightEmission = 1
	sparks.Parent = chassis
	rig.sparks = sparks

	rigs[model] = rig
end

local function watchFolder(folder: Folder)
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			task.spawn(buildRig, m)
		end
	end
	folder.ChildAdded:Connect(function(m)
		if m:IsA("Model") then
			task.wait(0.2) -- let attributes + children replicate
			buildRig(m)
		end
	end)
	folder.ChildRemoved:Connect(function(m)
		rigs[m :: Model] = nil
	end)
end

task.spawn(function()
	watchFolder(Workspace:WaitForChild("Bikes") :: Folder)
end)

----------------------------------------------------------------------------
-- Frame update
----------------------------------------------------------------------------
local camera = Workspace.CurrentCamera
local baseFov = camera and camera.FieldOfView or 70
local shake = 0

RunService.RenderStepped:Connect(function(dt)
	for model, rig in pairs(rigs) do
		if not model.Parent then
			rigs[model] = nil
		else
			local running = model:GetAttribute("EngineRunning") == true
			local vehicle = rig.vehicle
			local gearIndex = math.clamp(model:GetAttribute("Gear") or 1, 1, #vehicle.drivetrain.gears)
			local gearTop = vehicle.stats.topSpeedKmh * STUDS * vehicle.drivetrain.gears[gearIndex]
			local look = rig.chassis.CFrame.LookVector
			local forward = math.max(rig.chassis.AssemblyLinearVelocity:Dot(look), 0)
			local throttle = model:GetAttribute("Throttle") or 0

			local rpm = running and math.clamp(0.2 + 0.8 * forward / gearTop + throttle * 0.2, 0.2, 1.1) or 0
			rig.smooth += (rpm - rig.smooth) * math.min(1, dt * 8)

			if rig.engine then
				rig.engine.Volume = running and (0.35 + 0.4 * rig.smooth) or 0
				rig.engine.PlaybackSpeed = 0.55 + 1.25 * rig.smooth
			end
			if rig.smoke then
				local warm = model:GetAttribute("Warm") or 0
				local rich = model:GetAttribute("Choke") or warm < 0.3
				local twoStroke = vehicle.engineType == "Two-stroke"
				rig.smoke.Rate = running and (4 + throttle * 26 + (twoStroke and 10 or 0) + (rich and 14 or 0)) or 0
				rig.smoke.Color = ColorSequence.new(rich and Color3.fromRGB(235, 235, 240) or (twoStroke and Color3.fromRGB(170, 190, 215) or Color3.fromRGB(150, 150, 155)))
			end
		end
	end

	-- crash shake (decays) + speed FOV for the bike we control
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		if shake > 0.01 then
			shake = math.max(0, shake - dt * 1.6)
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
		elseif hum.CameraOffset ~= Vector3.zero then
			hum.CameraOffset = Vector3.zero
		end
	end
	if camera then
		local target = baseFov
		if ClientState.mode == "Ride" then
			target += math.clamp(ClientState.speedKmh / 140, 0, 1) * 14
		end
		camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 4)
	end
end)

----------------------------------------------------------------------------
-- One-shot events from the server
----------------------------------------------------------------------------
local function puff(model: Model, count: number)
	local rig = rigs[model]
	if rig and rig.smoke then
		rig.smoke:Emit(count)
	end
end

Remotes.event("BikeEvent").OnClientEvent:Connect(function(model: Model, kind: string, data: any)
	if typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	if kind == "Kick" then
		oneShot(model, "kick", 0.8, 0.95 + math.random() * 0.1)
	elseif kind == "Crank" then
		oneShot(model, "crank", 0.7)
	elseif kind == "Started" then
		oneShot(model, "startUp", 0.9)
		puff(model, 14)
	elseif kind == "Cough" then
		oneShot(model, "sputter", 0.5, 1.3)
		puff(model, 6)
	elseif kind == "Sputter" then
		oneShot(model, "sputter", 0.8)
		puff(model, 10)
	elseif kind == "Stall" then
		oneShot(model, "stall", 0.7)
		puff(model, 8)
	elseif kind == "Click" then
		oneShot(model, "click", 0.5, 0.9 + math.random() * 0.2)
	elseif kind == "Crash" then
		oneShot(model, "crash", 1.0)
		local rig = rigs[model]
		if rig then
			rig.sparks:Emit(math.clamp(math.floor((data and data.amount or 10)), 6, 40))
		end
		if model:GetAttribute("Controller") == player.UserId then
			shake = math.clamp((data and data.amount or 10) / 12, 0.3, 2.2)
		end
	end
end)
