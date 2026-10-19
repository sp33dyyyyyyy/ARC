--[[
	MissionService  (ModuleScript, ServerScriptService/Services)

	Three mission types, all judged by the server from the bike's real position:

	  Delivery    pickup -> dropoff. Parcel payout shrinks if the bike takes
	              damage while carrying it; a time bonus rewards a quick run.
	  Checkpoint  ordered gates against the clock. Par time = bonus.
	  Cruise      ride to a destination; arrive undamaged for a bonus.

	The client gets MissionUpdate(state) with positions and a server-time
	deadline, draws markers/timers, and can only ask to START or ABANDON.
	Rewards are paid through EconomyService.

	Spots are parts inside Workspace/MissionSpots, looked up by the names in
	MissionData. Tag a part "MissionBoard" to place the board that lists jobs.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local MissionData = require(Shared.MissionData)
local Remotes = require(Shared.Remotes)

local CFG = GameConfig.Missions

local MissionService = {}
local Economy, Vehicles

local active: { [Player]: any } = {}

----------------------------------------------------------------------------
local function spotPosition(name: string): Vector3?
	local folder = Workspace:FindFirstChild("MissionSpots")
	local part = folder and folder:FindFirstChild(name, true)
	if part and part:IsA("BasePart") then
		return part.Position
	end
	return nil
end

local function defById(id: string)
	for _, def in ipairs(MissionData) do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- A mission is only offered if every spot it needs exists in the map.
local function isAvailable(def): boolean
	if def.type == "Delivery" then
		return spotPosition(def.pickup) ~= nil and spotPosition(def.dropoff) ~= nil
	elseif def.type == "Checkpoint" then
		for _, n in ipairs(def.checkpoints) do
			if not spotPosition(n) then
				return false
			end
		end
		return true
	elseif def.type == "Cruise" then
		return spotPosition(def.destination) ~= nil
	end
	return false
end

local function offers()
	local list = {}
	for _, def in ipairs(MissionData) do
		if isAvailable(def) then
			table.insert(list, {
				id = def.id, type = def.type, title = def.title, description = def.description,
				basePay = def.basePay, timeLimit = def.timeLimit,
			})
		end
	end
	return list
end

----------------------------------------------------------------------------
-- Client sync
----------------------------------------------------------------------------
local function push(player: Player, m)
	if not m then
		Remotes.event("MissionUpdate"):FireClient(player, nil)
		return
	end
	local target
	if m.def.type == "Delivery" then
		target = (m.stage == 1) and spotPosition(m.def.pickup) or spotPosition(m.def.dropoff)
	elseif m.def.type == "Checkpoint" then
		target = spotPosition(m.def.checkpoints[m.index])
	else
		target = spotPosition(m.def.destination)
	end
	local nextTarget
	if m.def.type == "Checkpoint" and m.def.checkpoints[m.index + 1] then
		nextTarget = spotPosition(m.def.checkpoints[m.index + 1])
	end
	Remotes.event("MissionUpdate"):FireClient(player, {
		id = m.def.id,
		type = m.def.type,
		title = m.def.title,
		stage = m.stage,
		index = m.index,
		total = m.def.type == "Checkpoint" and #m.def.checkpoints or nil,
		target = target,
		nextTarget = nextTarget,
		deadline = m.deadline, -- workspace:GetServerTimeNow() based; nil = no clock
		hint = m.hint,
	})
end

local function finish(player: Player, m, success: boolean, pay: number?, message: string)
	active[player] = nil
	if success and pay then
		Economy.pay(player, pay, m.def.id)
		Economy.recordJobDone(player)
		Economy.notify(player, ("%s  +EUR %d"):format(message, pay), "good")
	else
		Economy.notify(player, message, "warn")
	end
	push(player, nil)
end

----------------------------------------------------------------------------
-- Per-type progression. Called every PollInterval with the bike position.
----------------------------------------------------------------------------
local function health(rec): number
	return rec.model:GetAttribute("Health")
end

local function checkDelivery(player, m, pos: Vector3, rec)
	local def = m.def
	if m.stage == 1 then
		local p = spotPosition(def.pickup)
		if p and (pos - p).Magnitude <= CFG.PickupRadius then
			m.stage = 2
			m.healthAtPickup = health(rec)
			m.hint = "Parcel on board - take it easy."
			Economy.notify(player, "Parcel loaded!", "info")
			push(player, m)
		end
	else
		local p = spotPosition(def.dropoff)
		if p and (pos - p).Magnitude <= CFG.DestinationRadius then
			local lost = math.max(0, m.healthAtPickup - health(rec))
			local damageFactor = math.clamp(1 - lost / 120, 0.4, 1)
			local timeLeft = (m.deadline - Workspace:GetServerTimeNow()) / def.timeLimit
			local timeBonus = timeLeft > 0.5 and 1.25 or 1
			local pay = def.basePay * damageFactor * timeBonus
			local msg = lost > 5 and "Delivered (a bit shaken)" or "Delivered, good as new"
			finish(player, m, true, pay, msg)
		end
	end
end

local function checkCheckpoints(player, m, pos: Vector3)
	local def = m.def
	local p = spotPosition(def.checkpoints[m.index])
	if p and (pos - p).Magnitude <= CFG.CheckpointRadius then
		if m.index >= #def.checkpoints then
			local elapsed = Workspace:GetServerTimeNow() - m.startedAt
			local pay = def.basePay * (elapsed <= def.parTime and 1.4 or 1)
			finish(player, m, true, pay, elapsed <= def.parTime and "Under par time!" or "Run complete")
		else
			m.index += 1
			push(player, m)
		end
	end
end

local function checkCruise(player, m, pos: Vector3, rec)
	local def = m.def
	local p = spotPosition(def.destination)
	if p and (pos - p).Magnitude <= CFG.DestinationRadius then
		local lost = math.max(0, m.healthAtStart - health(rec))
		local pay = def.basePay * (lost < 1 and 1.3 or 1)
		finish(player, m, true, pay, lost < 1 and "Arrived without a scratch" or "You made it")
	end
end

----------------------------------------------------------------------------
-- Start / abandon
----------------------------------------------------------------------------
local function start(player: Player, id)
	if typeof(id) ~= "string" then
		return { ok = false, reason = "Bad request" }
	end
	if active[player] then
		return { ok = false, reason = "Finish or abandon your current job first" }
	end
	local def = defById(id)
	if not (def and isAvailable(def)) then
		return { ok = false, reason = "That job isn't available" }
	end
	local rec = Vehicles.getBike(player)
	if not rec then
		return { ok = false, reason = "You need your bike for jobs (press B)" }
	end

	local now = Workspace:GetServerTimeNow()
	local m = {
		def = def, stage = 1, index = 1, startedAt = now,
		healthAtStart = health(rec), healthAtPickup = health(rec),
		deadline = def.timeLimit and (now + def.timeLimit) or nil,
		hint = nil,
	}
	if def.type == "Delivery" then
		m.hint = "Pick up the parcel."
	elseif def.type == "Checkpoint" then
		m.hint = "Hit every gate in order."
	else
		m.hint = "Ride to the marker."
	end
	active[player] = m
	push(player, m)
	Economy.notify(player, "Job started: " .. def.title, "info")
	return { ok = true }
end

local function abandon(player: Player)
	local m = active[player]
	if m then
		finish(player, m, false, nil, "Job abandoned.")
	end
end

----------------------------------------------------------------------------
function MissionService.init(economyService, vehicleService)
	Economy, Vehicles = economyService, vehicleService

	Remotes.func("MissionStart").OnServerInvoke = start
	Remotes.event("MissionAbandon").OnServerEvent:Connect(abandon)

	-- mission board prompt
	local function setupBoard(inst: Instance)
		if not inst:IsA("BasePart") or inst:FindFirstChild("BoardPrompt") then
			return
		end
		local p = Instance.new("ProximityPrompt")
		p.Name = "BoardPrompt"
		p.ActionText = "Read job board"
		p.ObjectText = "Schwarzes Brett"
		p.HoldDuration = 0
		p.MaxActivationDistance = 12
		p.RequiresLineOfSight = false
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.Parent = inst
		p.Triggered:Connect(function(player)
			Remotes.event("OpenMissionBoard"):FireClient(player, offers(), active[player] ~= nil)
		end)
	end
	for _, inst in ipairs(CollectionService:GetTagged("MissionBoard")) do
		setupBoard(inst)
	end
	CollectionService:GetInstanceAddedSignal("MissionBoard"):Connect(setupBoard)

	Players.PlayerRemoving:Connect(function(p)
		active[p] = nil
	end)

	-- poll progress
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < CFG.PollInterval then
			return
		end
		acc = 0
		for player, m in pairs(active) do
			local rec = Vehicles.getBike(player)
			if not rec then
				finish(player, m, false, nil, "Job failed: you lost your bike.")
			elseif m.deadline and Workspace:GetServerTimeNow() > m.deadline then
				finish(player, m, false, nil, "Job failed: out of time.")
			else
				local pos = rec.chassis.Position
				if Vehicles.warpedRecently(rec) then
					-- the bike was moved impossibly fast: no progress counts
				elseif m.def.type == "Delivery" then
					checkDelivery(player, m, pos, rec)
				elseif m.def.type == "Checkpoint" then
					checkCheckpoints(player, m, pos)
				else
					checkCruise(player, m, pos, rec)
				end
			end
		end
	end)
end

return MissionService
