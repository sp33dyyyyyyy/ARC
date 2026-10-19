--[[
	VehicleService  (ModuleScript, ServerScriptService/Services)

	Server authority over every bike:
	  * spawning / despawning (one bike per player, built by BikeFactory)
	  * the START PROCEDURE:   fuel tap -> ignition -> (choke) -> kick / starter
	  * fuel burn, carb-bowl stalling, reserve tap, flooding, engine warm-up
	  * crash damage, rider ejection, tip-overs, wrecked bikes
	  * mounting (Seat) and PUSHING the bike by hand (walk speed set from weight)
	  * ProximityPrompts on the bike itself, so you walk around it and use the
	    real controls: tap on the left of the tank, key at the headstock, choke
	    at the carburettor, kick lever on the right...

	Bike state lives in Attributes on the Model, so every client can read it
	(HUD, engine sound, smoke) without any extra remotes:
	  Owner Rider Pusher Controller   userIds (0 = nobody)
	  Mode          "Parked" | "Ride" | "Push" | "Coast"
	  Fuel Health   litres / 0-100
	  FuelTap       "Off" | "On" | "Reserve"
	  Ignition Choke EngineRunning Wrecked   booleans
	  Warm Battery Flooded Throttle Gear     numbers

	Movement itself is simulated by the controlling client (network ownership,
	see BikePhysics / BikeClient). The server watches the result and sanity-
	checks it. Money, fuel, health and unlocks are never client-decided.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local VehicleData = require(Shared.VehicleData)
local Remotes = require(Shared.Remotes)
local BikeFactory = require(Shared.BikeFactory)
local BikePhysics = require(Shared.BikePhysics)

local ENGINE = GameConfig.Engine
local FUEL = GameConfig.Fuel
local CRASH = GameConfig.Crash
local PUSH = GameConfig.Push

local TICK = 0.1
local INTERACT_DISTANCE = 14

local VehicleService = {}

local Data, Economy -- injected in init()
local bikesFolder: Folder
local bikes: { [Player]: any } = {} -- player -> record

local bikeEvent: RemoteEvent
local function fireBikeEvent(rec, kind: string, data: any?)
	bikeEvent:FireAllClients(rec.model, kind, data)
end

local function notify(player: Player, text: string, kind: string?)
	Economy.notify(player, text, kind)
end

local function character(player: Player): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearBike(player: Player, rec, distance: number?): boolean
	local _, _, hrp = character(player)
	if not hrp then
		return false
	end
	return (hrp.Position - rec.chassis.Position).Magnitude <= (distance or INTERACT_DISTANCE)
end

----------------------------------------------------------------------------
-- Fuel helpers
----------------------------------------------------------------------------
local function fuelSupplied(rec): boolean
	local m = rec.model
	local tap = m:GetAttribute("FuelTap")
	local fuel = m:GetAttribute("Fuel")
	if tap == "On" then
		return fuel > rec.vehicle.fuel.reserveL
	elseif tap == "Reserve" then
		return fuel > 0
	end
	return false
end

----------------------------------------------------------------------------
-- Engine control
----------------------------------------------------------------------------
local function stopEngine(rec, reason: string)
	local m = rec.model
	if not m:GetAttribute("EngineRunning") then
		return
	end
	m:SetAttribute("EngineRunning", false)
	fireBikeEvent(rec, "Stall", reason)
end

local function tryStart(rec, player: Player, method: string)
	local m = rec.model
	local st = rec.vehicle.starting
	local now = os.clock()
	if now - rec.lastKick < ENGINE.KickCooldown then
		return
	end
	rec.lastKick = now

	if m:GetAttribute("Wrecked") then
		notify(player, "The bike is wrecked. Take it to a workshop.", "warn")
		return
	end

	-- the lever / button is pressed whether or not the engine catches
	fireBikeEvent(rec, method == "electric" and "Crank" or "Kick")

	if m:GetAttribute("EngineRunning") then
		return
	end
	if not m:GetAttribute("Ignition") then
		notify(player, "Nothing happens. Is the ignition on?", "hint")
		return
	end
	if not fuelSupplied(rec) and rec.bowl <= 0 then
		notify(player, "No fuel reaching the carb. Open the fuel tap (or switch to reserve).", "hint")
		return
	end

	if method == "electric" then
		local battery = m:GetAttribute("Battery")
		if battery < 0.05 then
			notify(player, "Battery flat. Use the kickstart.", "warn")
			return
		end
		m:SetAttribute("Battery", math.max(0, battery - ENGINE.StarterBatteryDrain))
	end

	local flooded = m:GetAttribute("Flooded")
	if flooded >= ENGINE.FloodLimit then
		notify(player, "Flooded! Choke off, wait a moment, then try again.", "warn")
		return
	end

	local choke = m:GetAttribute("Choke")
	local cold = m:GetAttribute("Warm") < ENGINE.ColdThreshold
	local base = method == "electric" and (st.starterChance or 0.8) or st.kickChance
	local chance = base
	if cold then
		chance = choke and base or base * 0.25 -- cold engines want choke
	else
		chance = choke and base * 0.35 or base -- warm engines hate it
	end
	if choke then
		m:SetAttribute("Flooded", flooded + (cold and 0.35 or 1))
	end

	if math.random() < chance then
		m:SetAttribute("EngineRunning", true)
		rec.bowl = FUEL.CarbBowlSeconds
		rec.runningSince = now
		rec.failures = 0
		fireBikeEvent(rec, "Started")
	else
		rec.failures += 1
		fireBikeEvent(rec, "Cough")
		if rec.failures % 3 == 0 then
			if cold and not choke then
				notify(player, "Cold engine. Try the choke.", "hint")
			elseif not cold and choke then
				notify(player, "Warm engine - switch the choke off.", "hint")
			end
		end
	end
end

----------------------------------------------------------------------------
-- Controller state: who is driving the physics?
----------------------------------------------------------------------------
local function takeControl(rec, player: Player, mode: string)
	local chassis = rec.chassis
	chassis.Anchored = false
	chassis:SetNetworkOwner(player)
	rec.model:SetAttribute("Controller", player.UserId)
	rec.model:SetAttribute("Mode", mode)
	rec.coastTimer = 0
end

local function park(rec)
	local chassis = rec.chassis
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.Anchored = true
	rec.throttle = 0
	rec.model:SetAttribute("Throttle", 0)
	rec.model:SetAttribute("Controller", 0)
	rec.model:SetAttribute("Mode", "Parked")
end

local function startCoast(rec)
	rec.model:SetAttribute("Mode", "Coast")
	rec.model:SetAttribute("Rider", 0)
	rec.throttle = 0
	rec.coastTimer = 0
end

----------------------------------------------------------------------------
-- Pushing the bike by hand
----------------------------------------------------------------------------
local function releasePush(rec, reason: string?)
	local m = rec.model
	if m:GetAttribute("Pusher") == 0 then
		return
	end
	local pusher = Players:GetPlayerByUserId(m:GetAttribute("Pusher"))
	m:SetAttribute("Pusher", 0)

	for _, c in ipairs(rec.pushConns) do
		c:Disconnect()
	end
	table.clear(rec.pushConns)
	for _, c in ipairs(rec.noCollide) do
		c:Destroy()
	end
	table.clear(rec.noCollide)

	if pusher then
		local char, hum = character(pusher)
		if char then
			char:SetAttribute("PushSpeed", nil)
		end
		if hum then
			hum.WalkSpeed = rec.savedWalkSpeed or PUSH.FreeWalkSpeed
		end
		if reason then
			notify(pusher, reason, "hint")
		end
	end
	if m:GetAttribute("Mode") == "Push" then
		startCoast(rec)
	end
end

local function startPush(rec, player: Player)
	local m = rec.model
	local mode = m:GetAttribute("Mode")
	if mode == "Ride" then
		return
	end
	local char, hum, hrp = character(player)
	if not (char and hum and hrp) or hum.Health <= 0 then
		return
	end
	local bars = rec.chassis:FindFirstChild("HandlebarPoint") :: Attachment?
	if not bars or (bars.WorldPosition - hrp.Position).Magnitude > 9 then
		return
	end

	local limits = BikePhysics.pushLimits(rec.vehicle, m:GetAttribute("Fuel"))
	rec.savedWalkSpeed = hum.WalkSpeed
	hum.WalkSpeed = limits.walkSpeed -- heavier bike => slower you can walk
	char:SetAttribute("PushSpeed", limits.walkSpeed)
	m:SetAttribute("Pusher", player.UserId)
	takeControl(rec, player, "Push")

	-- the pusher's body must not shove the bike around through collisions
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = rec.chassis
			nc.Part1 = part
			nc.Parent = rec.chassis
			table.insert(rec.noCollide, nc)
		end
	end

	table.insert(rec.pushConns, hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			releasePush(rec, "You let go of the bike.")
		end
	end))
	table.insert(rec.pushConns, hum.Died:Connect(function()
		releasePush(rec)
	end))

	local strain = limits.strain
	if strain > 0.7 then
		notify(player, "Heavy! This one takes real effort to push.", "info")
	elseif strain < 0.3 then
		notify(player, "Light as a feather. Easy to push.", "info")
	end
end

----------------------------------------------------------------------------
-- Mounting
----------------------------------------------------------------------------
local function mount(rec, player: Player)
	local _, hum = character(player)
	if not hum or hum.Health <= 0 or not nearBike(player, rec, 10) then
		return
	end
	if rec.model:GetAttribute("Mode") == "Ride" then
		return
	end
	releasePush(rec)
	takeControl(rec, player, "Ride")
	rec.model:SetAttribute("Rider", player.UserId)
	rec.seat:Sit(hum)
end

----------------------------------------------------------------------------
-- Player actions (shared by ProximityPrompts and key presses)
----------------------------------------------------------------------------
local TAP_NEXT = { Off = "On", On = "Reserve", Reserve = "Off" }

local function handleAction(player: Player, action: string)
	local rec = bikes[player]
	if not rec or not rec.model.Parent then
		return
	end
	local m = rec.model
	local mode = m:GetAttribute("Mode")
	if not nearBike(player, rec) then
		return
	end

	if action == "FuelTap" then
		m:SetAttribute("FuelTap", TAP_NEXT[m:GetAttribute("FuelTap")] or "Off")
		fireBikeEvent(rec, "Click")
	elseif action == "Ignition" then
		local on = not m:GetAttribute("Ignition")
		if on and m:GetAttribute("Wrecked") then
			notify(player, "The bike is wrecked. Take it to a workshop.", "warn")
			return
		end
		m:SetAttribute("Ignition", on)
		fireBikeEvent(rec, "Click")
		if not on then
			stopEngine(rec, "key")
		end
	elseif action == "Choke" then
		m:SetAttribute("Choke", not m:GetAttribute("Choke"))
		fireBikeEvent(rec, "Click")
	elseif action == "Kick" then
		if mode ~= "Push" then
			tryStart(rec, player, "kick")
		end
	elseif action == "Starter" then
		if rec.vehicle.starting.electric and mode ~= "Push" then
			tryStart(rec, player, "electric")
		end
	elseif action == "Grab" then
		if mode == "Push" and m:GetAttribute("Pusher") == player.UserId then
			releasePush(rec, "You let go of the bike.")
		else
			startPush(rec, player)
		end
	elseif action == "Release" then
		if m:GetAttribute("Pusher") == player.UserId then
			releasePush(rec, "You let go of the bike.")
		end
	elseif action == "Ride" then
		mount(rec, player)
	elseif action == "Dismount" then
		if m:GetAttribute("Rider") == player.UserId then
			local _, hum = character(player)
			if hum then
				hum.Sit = false
			end
		end
	end
end

----------------------------------------------------------------------------
-- Prompts on the bike
----------------------------------------------------------------------------
local PROMPT_DEFS = {
	-- name, attachment, action, key, distance
	{ "Ride", "SeatPoint", "Ride", Enum.KeyCode.R, 6 },
	{ "Grab", "HandlebarPoint", "Grab", Enum.KeyCode.G, 5 },
	{ "FuelTap", "FuelTapPoint", "FuelTap", Enum.KeyCode.F, 4 },
	{ "Ignition", "IgnitionPoint", "Ignition", Enum.KeyCode.I, 4 },
	{ "Choke", "ChokePoint", "Choke", Enum.KeyCode.C, 4 },
	{ "Kick", "KickPoint", "Kick", Enum.KeyCode.K, 4 },
	{ "Starter", "StarterPoint", "Starter", Enum.KeyCode.E, 4 },
}

local function buildPrompts(rec)
	for _, def in ipairs(PROMPT_DEFS) do
		local name, attName, action, key, dist = def[1], def[2], def[3], def[4], def[5]
		if name ~= "Starter" or rec.vehicle.starting.electric then
			local att = rec.chassis:FindFirstChild(attName)
			if att then
				local p = Instance.new("ProximityPrompt")
				p.Name = name
				p.ObjectText = rec.vehicle.displayName
				p.ActionText = name
				p.KeyboardKeyCode = key
				p.HoldDuration = 0
				p.MaxActivationDistance = dist
				p.RequiresLineOfSight = false
				p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
				p.Parent = att
				p.Triggered:Connect(function(who)
					if who.UserId ~= rec.model:GetAttribute("Owner") then
						notify(who, "That's not your bike.", "warn")
						return
					end
					handleAction(who, action)
				end)
				rec.prompts[name] = p
			end
		end
	end
end

local function refreshPrompts(rec)
	local m = rec.model
	local mode = m:GetAttribute("Mode")
	local free = mode == "Parked" or mode == "Coast"
	local pushing = mode == "Push"
	local function set(name: string, enabled: boolean, text: string?)
		local p = rec.prompts[name]
		if not p then
			return
		end
		if p.Enabled ~= enabled then
			p.Enabled = enabled
		end
		if text and p.ActionText ~= text then
			p.ActionText = text
		end
	end
	set("Ride", free, "Ride")
	set("Grab", free or pushing, pushing and "Let go" or "Push / grab handlebars")
	set("FuelTap", free, ("Fuel tap [%s]"):format(m:GetAttribute("FuelTap")))
	set("Ignition", free, ("Ignition [%s]"):format(m:GetAttribute("Ignition") and "ON" or "OFF"))
	set("Choke", free, ("Choke [%s]"):format(m:GetAttribute("Choke") and "ON" or "OFF"))
	set("Kick", free, "Kickstart")
	set("Starter", free, "Starter button")
end

----------------------------------------------------------------------------
-- Spawning
----------------------------------------------------------------------------
function VehicleService.despawn(player: Player)
	local rec = bikes[player]
	if not rec then
		return
	end
	bikes[player] = nil
	local profile = Data.get(player)
	if profile and rec.model.Parent then
		profile.bikeState[rec.vehicle.id] = {
			fuel = rec.model:GetAttribute("Fuel"),
			health = rec.model:GetAttribute("Health"),
		}
	end
	releasePush(rec)
	for _, c in ipairs(rec.conns) do
		c:Disconnect()
	end
	rec.model:Destroy()
end

function VehicleService.spawn(player: Player): (boolean, string?)
	local profile = Data.get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	local char, _, hrp = character(player)
	if not (char and hrp) then
		return false, "No character"
	end
	local vehicle = VehicleData.byId[profile.equipped]
	local owned = profile.owned[profile.equipped]
	if not (vehicle and owned) then
		return false, "No bike equipped"
	end

	VehicleService.despawn(player)

	local model = BikeFactory.create(vehicle.id, owned.paint)
	if not model then
		return false, "Model missing"
	end
	BikeFactory.setupPhysics(model, vehicle)
	local chassis = model.PrimaryPart :: BasePart
	local seat = model:FindFirstChildWhichIsA("Seat", true)
	if not seat then
		return false, "Bike model has no Seat"
	end
	(seat :: Seat).CanTouch = false -- no accidental sitting; mounting is via the prompt

	local saved = profile.bikeState[vehicle.id]
	local fuel = saved and saved.fuel or vehicle.stats.fuelCapacityL * 0.5
	local health = saved and saved.health or 100

	local attrs = {
		Owner = player.UserId, VehicleId = vehicle.id, Rider = 0, Pusher = 0, Controller = 0,
		Mode = "Parked", Fuel = fuel, Health = health, FuelTap = "Off", Ignition = false,
		Choke = false, EngineRunning = false, Wrecked = health <= 0, Warm = 0, Battery = 1,
		Flooded = 0, Throttle = 0, Gear = 1,
	}
	for k, v in pairs(attrs) do
		model:SetAttribute(k, v)
	end

	-- drop it on the ground a few studs in front of the player
	local flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local pos = hrp.Position + flat * 7
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char, bikesFolder }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(pos + Vector3.new(0, 25, 0), Vector3.new(0, -80, 0), params)
	local groundY = hit and hit.Position.Y or (hrp.Position.Y - 3)
	local height = vehicle.geometry.wheelRadius + 0.25 + 0.3
	model:PivotTo(CFrame.lookAt(Vector3.new(pos.X, groundY + height, pos.Z), Vector3.new(pos.X, groundY + height, pos.Z) + flat))
	chassis.Anchored = true
	model.Parent = bikesFolder

	local rec = {
		player = player, model = model, chassis = chassis, seat = seat, vehicle = vehicle,
		throttle = 0, brake = 0, bowl = 0, lastKick = 0, failures = 0,
		runningSince = 0, speedHistory = {}, lastCrash = 0, tipTimer = 0, coastTimer = 0,
		lastSave = os.clock(), prompts = {}, conns = {}, pushConns = {}, noCollide = {},
		sputtered = false,
	}
	bikes[player] = rec
	buildPrompts(rec)

	table.insert(rec.conns, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil and model:GetAttribute("Mode") == "Ride" then
			startCoast(rec)
		end
	end))

	return true
end

----------------------------------------------------------------------------
-- Accessors for other services
----------------------------------------------------------------------------
function VehicleService.getBike(player: Player)
	local rec = bikes[player]
	if rec and rec.model.Parent then
		return rec
	end
	return nil
end

function VehicleService.fuelMissing(rec): number
	return rec.vehicle.stats.fuelCapacityL - rec.model:GetAttribute("Fuel")
end

function VehicleService.addFuel(rec, litres: number)
	local cap = rec.vehicle.stats.fuelCapacityL
	local fuel = math.min(cap, rec.model:GetAttribute("Fuel") + litres)
	rec.model:SetAttribute("Fuel", fuel)
end

function VehicleService.healthMissing(rec): number
	return 100 - rec.model:GetAttribute("Health")
end

function VehicleService.repairFully(rec)
	rec.model:SetAttribute("Health", 100)
	rec.model:SetAttribute("Wrecked", false)
end

function VehicleService.isEngineRunning(rec): boolean
	return rec.model:GetAttribute("EngineRunning") == true
end

----------------------------------------------------------------------------
-- Damage
----------------------------------------------------------------------------
local function applyDamage(rec, amount: number, cause: string)
	local m = rec.model
	local health = math.max(0, m:GetAttribute("Health") - amount)
	m:SetAttribute("Health", health)
	fireBikeEvent(rec, "Crash", { amount = amount, cause = cause })

	local rider = Players:GetPlayerByUserId(m:GetAttribute("Rider"))
	if amount >= CRASH.StallDamage then
		stopEngine(rec, "crash")
	end
	if rider and amount >= CRASH.EjectDamage then
		local _, hum, hrp = character(rider)
		if hum and hrp then
			hum.Sit = false
			hum:ChangeState(Enum.HumanoidStateType.FallingDown)
			hrp.AssemblyLinearVelocity = rec.chassis.AssemblyLinearVelocity * 0.6 + Vector3.new(0, 22, 0)
		end
		notify(rider, "You came off!", "warn")
	end
	if health <= 0 and not m:GetAttribute("Wrecked") then
		m:SetAttribute("Wrecked", true)
		m:SetAttribute("Ignition", false)
		stopEngine(rec, "wrecked")
		local owner = Players:GetPlayerByUserId(m:GetAttribute("Owner"))
		if owner then
			notify(owner, "Bike wrecked! A workshop can fix it (for a price).", "warn")
		end
	end
end

----------------------------------------------------------------------------
-- Main per-bike tick (10 Hz)
----------------------------------------------------------------------------
local function tickBike(rec, dt: number)
	local m, chassis, vehicle = rec.model, rec.chassis, rec.vehicle
	local running = m:GetAttribute("EngineRunning")
	local mode = m:GetAttribute("Mode")

	-- warm-up / cool-down
	local warm = m:GetAttribute("Warm")
	if running then
		warm = math.min(1, warm + dt / ENGINE.WarmUpSeconds)
	else
		warm = math.max(0, warm - dt / ENGINE.CoolDownSeconds)
	end
	m:SetAttribute("Warm", warm)

	-- flooding dries out
	local flooded = m:GetAttribute("Flooded")
	if flooded > 0 then
		m:SetAttribute("Flooded", math.max(0, flooded - dt / ENGINE.FloodDecaySeconds))
	end

	-- fuel flow + carb bowl
	local supplied = fuelSupplied(rec)
	if running then
		if supplied then
			rec.bowl = FUEL.CarbBowlSeconds
			rec.sputtered = false
			local throttle = rec.throttle
			local f = vehicle.fuel
			local rate = f.burnIdle + (f.burnFull - f.burnIdle) * throttle ^ 1.3
			if m:GetAttribute("Choke") then
				rate *= FUEL.ChokeRichBurnMultiplier
			end
			m:SetAttribute("Fuel", math.max(0, m:GetAttribute("Fuel") - rate * dt))
			m:SetAttribute("Battery", math.min(1, m:GetAttribute("Battery") + ENGINE.StarterBatteryRecharge * dt))
		else
			rec.bowl -= dt
			if rec.bowl < 1.6 and not rec.sputtered then
				rec.sputtered = true
				fireBikeEvent(rec, "Sputter")
				local owner = Players:GetPlayerByUserId(m:GetAttribute("Owner"))
				if owner then
					if m:GetAttribute("FuelTap") == "Off" then
						notify(owner, "Engine starving - the fuel tap is off!", "warn")
					elseif m:GetAttribute("FuelTap") == "On" and m:GetAttribute("Fuel") > 0 then
						notify(owner, "Sputtering! Switch the fuel tap to RESERVE.", "warn")
					else
						notify(owner, "Out of fuel! Find a petrol station.", "warn")
					end
				end
			end
			if rec.bowl <= 0 then
				stopEngine(rec, "fuel")
			end
		end
	end

	-- speed bookkeeping
	local vel = chassis.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	m:SetAttribute("Throttle", rec.throttle)

	if mode == "Ride" then
		-- crash = a big speed loss over a short window
		local hist = rec.speedHistory
		table.insert(hist, speed)
		if #hist > 4 then
			table.remove(hist, 1)
		end
		local peak = 0
		for _, s in ipairs(hist) do
			peak = math.max(peak, s)
		end
		local now = os.clock()
		if peak - speed > CRASH.MinSpeedLoss and speed < peak * 0.6 and now - rec.lastCrash > 1 then
			rec.lastCrash = now
			local dmg = math.min(CRASH.MaxDamage, CRASH.BaseDamage + (peak - speed - CRASH.MinSpeedLoss) * CRASH.DamagePerStud)
			table.clear(hist)
			applyDamage(rec, dmg, "impact")
		end

		-- tipped over?
		if chassis.CFrame.UpVector.Y < 0.2 then
			rec.tipTimer += dt
			if rec.tipTimer > CRASH.TipOverSeconds then
				rec.tipTimer = 0
				applyDamage(rec, CRASH.TipOverDamage, "tip")
				local rider = Players:GetPlayerByUserId(m:GetAttribute("Rider"))
				if rider then
					local _, hum = character(rider)
					if hum then
						hum.Sit = false
					end
				end
				local pos = chassis.Position + Vector3.new(0, 2, 0)
				local flat = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
				if flat.Magnitude > 0.05 then
					chassis.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
				end
				chassis.AssemblyAngularVelocity = Vector3.zero
				chassis.AssemblyLinearVelocity = Vector3.zero
			end
		else
			rec.tipTimer = 0
		end

		-- server-side speed sanity (a hacked client can still drive, but not warp)
		local cap = vehicle.stats.topSpeedKmh * GameConfig.StudsPerKmh * CRASH.SpeedSanityMultiplier + 10
		if speed > cap then
			chassis.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y, vel.Z) * (cap / speed)
		end
	else
		table.clear(rec.speedHistory)
	end

	-- coasting bikes park themselves once they've rolled to a stop
	if mode == "Coast" then
		rec.coastTimer += dt
		if speed < PUSH.ParkSpeed or rec.coastTimer > PUSH.CoastParkSeconds then
			park(rec)
		end
	end

	-- pusher wandered off? let go
	if mode == "Push" then
		local pusher = Players:GetPlayerByUserId(m:GetAttribute("Pusher"))
		local hum, hrp
		if pusher then
			local _
			_, hum, hrp = character(pusher)
		end
		local bars = chassis:FindFirstChild("HandlebarPoint") :: Attachment?
		if not (pusher and hum and hrp and bars) or (hrp.Position - bars.WorldPosition).Magnitude > PUSH.AutoReleaseDistance then
			releasePush(rec, "You lost your grip on the bike.")
		else
			-- the client may slow the pusher down (dragging), never speed them up
			local limits = BikePhysics.pushLimits(vehicle, m:GetAttribute("Fuel"))
			if hum.WalkSpeed > limits.walkSpeed + 0.5 then
				hum.WalkSpeed = limits.walkSpeed
			end
		end
	end

	-- persist fuel + health into the profile every ~10 s (saved by DataService)
	if os.clock() - rec.lastSave > 10 then
		rec.lastSave = os.clock()
		local profile = Data.get(rec.player)
		if profile then
			profile.bikeState[vehicle.id] = { fuel = m:GetAttribute("Fuel"), health = m:GetAttribute("Health") }
		end
	end

	refreshPrompts(rec)
end

----------------------------------------------------------------------------
function VehicleService.init(dataService, economyService)
	Data, Economy = dataService, economyService
	bikeEvent = Remotes.event("BikeEvent")

	bikesFolder = Workspace:FindFirstChild("Bikes") :: Folder
	if not bikesFolder then
		bikesFolder = Instance.new("Folder")
		bikesFolder.Name = "Bikes"
		bikesFolder.Parent = Workspace
	end

	-- 10 Hz client input: throttle / brake / gear. Only the controlling player counts.
	Remotes.event("BikeInput").OnServerEvent:Connect(function(player, throttle, brake, gear)
		local rec = bikes[player]
		if not rec or rec.model:GetAttribute("Controller") ~= player.UserId then
			return
		end
		if typeof(throttle) ~= "number" or typeof(brake) ~= "number" or typeof(gear) ~= "number" then
			return
		end
		rec.throttle = rec.model:GetAttribute("Mode") == "Ride" and math.clamp(throttle, 0, 1) or 0
		rec.brake = math.clamp(brake, 0, 1)
		rec.model:SetAttribute("Gear", math.clamp(math.floor(gear), 1, #rec.vehicle.drivetrain.gears))
	end)

	Remotes.event("BikeAction").OnServerEvent:Connect(function(player, action)
		if typeof(action) == "string" then
			handleAction(player, action)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		VehicleService.despawn(player)
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK then
			return
		end
		local step = acc
		acc = 0
		for _, rec in pairs(bikes) do
			if rec.model.Parent then
				tickBike(rec, step)
			end
		end
	end)
end

return VehicleService
