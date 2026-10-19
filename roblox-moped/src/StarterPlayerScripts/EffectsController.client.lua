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

	-- Wheels: every spinning part has a Weld; we turn each weld's C0 about the
	-- axle every frame (local, visual only - physics never sees it)
	local wheels = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local group = d:GetAttribute("Wheel")
			local center = d:GetAttribute("WheelCenter")
			local weld = group and d:FindFirstChildOfClass("Weld")
			if weld and center then
				wheels[group] = wheels[group] or { angle = 0, center = center, parts = {} }
				table.insert(wheels[group].parts, { weld = weld, c0 = weld.C0 })
			end
		end
	end
	rig.wheels = wheels

	-- Animated groups built by BikeRig: a pivot part with a Weld "J" whose C0
	-- we turn about the pivot's local Y axis (steering, stand, kick lever, ...)
	local anims = {}
	for _, d in ipairs(model:GetDescendants()) do
		local kind = d:IsA("BasePart") and d:GetAttribute("Anim")
		local joint = kind and d:FindFirstChild("J")
		if joint then
			table.insert(anims, {
				kind = kind, joint = joint, base = joint.C0, a1 = d:GetAttribute("A1") or 0,
				inverted = d:GetAttribute("Inverted") == true, v = 0, applied = 0,
			})
		end
	end
	rig.anims = anims

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

			-- spin the wheels with the real rolling speed (cheap distance cull)
			if camera and next(rig.wheels) and (rig.chassis.Position - camera.CFrame.Position).Magnitude < 260 then
				local rolling = rig.chassis.AssemblyLinearVelocity:Dot(look)
				if math.abs(rolling) > 0.05 or rig.wasRolling then
					rig.wasRolling = math.abs(rolling) > 0.05
					local radius = vehicle.geometry.wheelRadius
					for _, w in pairs(rig.wheels) do
						w.angle = (w.angle - rolling / radius * dt) % (math.pi * 2)
						local c = w.center
						local rot = CFrame.new(c) * CFrame.Angles(w.angle, 0, 0) * CFrame.new(-c)
						for _, p in ipairs(w.parts) do
							p.weld.C0 = rot * p.c0
						end
					end
				end
			end

			-- handlebar steering, stand, kick lever, tap / key / choke
			if camera and #rig.anims > 0 and (rig.chassis.Position - camera.CFrame.Position).Magnitude < 200 then
				local mode = model:GetAttribute("Mode")
				local speed = rig.chassis.AssemblyLinearVelocity:Dot(look)
				if rig.kickT then
					rig.kickT += dt
					if rig.kickT > 0.55 then
						rig.kickT = nil
					end
				end
				for _, a in ipairs(rig.anims) do
					local target, rate = 0, 10
					if a.kind == "Steer" then
						rate = 14
						if ClientState.controlling == model then
							target = (ClientState.steer or 0) * (1 - 0.55 * math.clamp(speed / 60, 0, 1))
						elseif math.abs(speed) > 1.5 then
							-- other players: steering angle from the bike's yaw rate (bicycle model)
							local yaw = rig.chassis.AssemblyAngularVelocity.Y
							target = math.clamp(-math.atan(vehicle.geometry.wheelbase * yaw / speed) / math.max(a.a1, 0.01), -1, 1)
						end
					elseif a.kind == "Stand" then
						rate = 5
						local down = mode == "Parked" and model:GetAttribute("OnStand") ~= true
						target = (down ~= a.inverted) and 1 or 0
					elseif a.kind == "Kick" then
						rate = 60
						local t = rig.kickT
						if t then
							target = t < 0.16 and (t / 0.16) or math.max(0, 1 - (t - 0.16) / 0.39)
						end
					elseif a.kind == "Tap" then
						local tap = model:GetAttribute("FuelTap")
						target = tap == "On" and 0.5 or (tap == "Reserve" and 1 or 0)
					elseif a.kind == "Key" then
						target = model:GetAttribute("Ignition") and 1 or 0
					elseif a.kind == "Choke" then
						target = model:GetAttribute("Choke") and 1 or 0
					end
					a.v += (target - a.v) * math.min(1, dt * rate)
					if math.abs(a.v - a.applied) > 0.002 then
						a.applied = a.v
						local angle = a.v * a.a1
						if a.kind == "Steer" then
							angle = -angle -- +1 = steer right = clockwise seen from above
						end
						a.joint.C0 = a.base * CFrame.Angles(0, angle, 0)
					end
				end
			end

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
		local rig = rigs[model]
		if rig then
			rig.kickT = 0 -- swing the kick lever
		end
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
