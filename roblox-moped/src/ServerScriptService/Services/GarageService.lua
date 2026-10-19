--[[
	GarageService  (ModuleScript, ServerScriptService/Services)

	Server side of the garage UI. The client only ever sends WHICH bike and
	WHICH colour; the server checks ownership, unlock requirements and money.

	GarageBuy(id, paint)    -> { ok, reason? }
	GarageEquip(id, paint)  -> { ok, reason? }   (also respawns the bike)
	GarageSpawn()           -> { ok, reason? }   (call your bike to you)
]]

local Shared = game.ReplicatedStorage.Shared
local VehicleData = require(Shared.VehicleData)
local Remotes = require(Shared.Remotes)

local GarageService = {}
local Data, Economy, Vehicles

local lastCall: { [Player]: { [string]: number } } = {}

local function rateLimited(player: Player, key: string, seconds: number): boolean
	local now = os.clock()
	lastCall[player] = lastCall[player] or {}
	local last = lastCall[player][key]
	if last and now - last < seconds then
		return true
	end
	lastCall[player][key] = now
	return false
end

local function validPaint(vehicle, paint): number?
	if typeof(paint) == "number" and paint >= 1 and paint <= #vehicle.colours and paint % 1 == 0 then
		return paint
	end
	return nil
end

local function buy(player: Player, id, paint)
	if rateLimited(player, "buy", 0.4) then
		return { ok = false, reason = "Slow down" }
	end
	local profile = Data.get(player)
	local vehicle = typeof(id) == "string" and VehicleData.byId[id]
	if not (profile and vehicle) then
		return { ok = false, reason = "Unknown bike" }
	end
	local paintIdx = validPaint(vehicle, paint)
	if not paintIdx then
		return { ok = false, reason = "Bad colour" }
	end
	if profile.owned[id] then
		return { ok = false, reason = "You already own this bike" }
	end
	local unlocked, why = VehicleData.checkUnlock(vehicle, profile)
	if not unlocked then
		return { ok = false, reason = why }
	end
	-- price comes from the data table - never from the client
	if not Economy.spend(player, vehicle.price, "buy " .. id) then
		return { ok = false, reason = "Not enough money" }
	end
	profile.owned[id] = { paint = paintIdx }
	Data.push(player)
	Economy.notify(player, "Bought the " .. vehicle.displayName .. "!", "good")
	return { ok = true }
end

local function equip(player: Player, id, paint)
	if rateLimited(player, "equip", 1.5) then
		return { ok = false, reason = "Slow down" }
	end
	local profile = Data.get(player)
	local vehicle = typeof(id) == "string" and VehicleData.byId[id]
	if not (profile and vehicle and profile.owned[id]) then
		return { ok = false, reason = "You don't own that bike" }
	end
	local paintIdx = validPaint(vehicle, paint) or profile.owned[id].paint
	profile.owned[id].paint = paintIdx
	profile.equipped = id
	Data.push(player)
	-- bring the newly equipped bike out
	Vehicles.spawn(player)
	return { ok = true }
end

local function spawnBike(player: Player)
	if rateLimited(player, "spawn", 3) then
		return { ok = false, reason = "Wait a moment" }
	end
	local ok, reason = Vehicles.spawn(player)
	return { ok = ok, reason = reason }
end

function GarageService.openFor(player: Player)
	local profile = Data.get(player)
	if profile then
		Remotes.event("OpenGarage"):FireClient(player, Data.view(profile))
	end
end

function GarageService.init(dataService, economyService, vehicleService)
	Data, Economy, Vehicles = dataService, economyService, vehicleService
	Remotes.func("GarageBuy").OnServerInvoke = buy
	Remotes.func("GarageEquip").OnServerInvoke = equip
	Remotes.func("GarageSpawn").OnServerInvoke = spawnBike
	game.Players.PlayerRemoving:Connect(function(p)
		lastCall[p] = nil
	end)
end

return GarageService
