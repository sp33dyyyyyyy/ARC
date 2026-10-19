--[[
	PartsService  (ModuleScript, ServerScriptService/Services)

	The rules of the parts business. The phone only ASKS; every price, stock
	check and money movement happens here.

	  order      phone > parts shop. Takes the money, creates an order that is
	             delivered after GameConfig.Garage.DeliverySeconds. Orders are
	             saved in the profile, so a parcel ordered right before leaving
	             is waiting in the garage next time.
	  deliver    a van brings the crate to the player's garage (PlayerGarage)
	  unpack     click the crate: the part goes into the bike's inventory
	  install    only for the bike that is on the raised stand
	  remove     takes a part off again (kept in the inventory, free)

	Saved shape:  profile.parts[bikeId] = { owned = {[partId]=true}, installed = {[slot]=partId} }
	              profile.orders = { {id, partId, bikeId, deliverAt, arrived} }
]]

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local PartsData = require(Shared.PartsData)
local VehicleData = require(Shared.VehicleData)
local Remotes = require(Shared.Remotes)

local CFG = GameConfig.Garage
local MAX_PENDING = 8

local PartsService = {}
local Data, Economy, Vehicles, Garage

local counter = 0
local lastCall: { [Player]: { [string]: number } } = {}
local inFlight: { [string]: boolean } = {} -- order ids currently being delivered

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

local function entry(profile, bikeId: string)
	profile.parts[bikeId] = profile.parts[bikeId] or { owned = {}, installed = {} }
	local e = profile.parts[bikeId]
	e.owned = e.owned or {}
	e.installed = e.installed or {}
	return e
end

-- You may buy parts for bikes you own (everything in TestFleet mode).
local function usableBike(profile, bikeId): any
	local vehicle = typeof(bikeId) == "string" and VehicleData.byId[bikeId]
	if vehicle and (profile.owned[bikeId] or GameConfig.TestFleet) then
		return vehicle
	end
	return nil
end

----------------------------------------------------------------------------
-- Orders -> client
----------------------------------------------------------------------------
function PartsService.pushOrders(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local list = {}
	local now = os.time()
	for _, o in ipairs(profile.orders) do
		table.insert(list, {
			id = o.id, partId = o.partId, bikeId = o.bikeId,
			remaining = math.max(0, o.deliverAt - now), arrived = o.arrived == true,
		})
	end
	Remotes.event("OrdersChanged"):FireClient(player, list)
end

----------------------------------------------------------------------------
-- Phone: order
----------------------------------------------------------------------------
local function order(player: Player, partId, bikeId)
	if rateLimited(player, "order", 0.5) then
		return { ok = false, reason = "Slow down" }
	end
	local profile = Data.get(player)
	if not profile then
		return { ok = false, reason = "Profile not loaded" }
	end
	local part = typeof(partId) == "string" and PartsData.byId[partId]
	local vehicle = usableBike(profile, bikeId)
	if not (part and vehicle) then
		return { ok = false, reason = "Unknown part or bike" }
	end
	local fits, why = PartsData.fits(part, vehicle)
	if not fits then
		return { ok = false, reason = "Doesn't fit: " .. why }
	end
	local e = entry(profile, vehicle.id)
	if e.owned[partId] or e.installed[part.slot] == partId then
		return { ok = false, reason = "You already have that part." }
	end
	local pending = 0
	for _, o in ipairs(profile.orders) do
		pending += 1
		if o.partId == partId and o.bikeId == vehicle.id then
			return { ok = false, reason = "That part is already on order." }
		end
	end
	if pending >= MAX_PENDING then
		return { ok = false, reason = "Too many parcels waiting - unpack some first." }
	end

	local price = PartsData.price(part, vehicle)
	if not Economy.spend(player, price, "parts") then
		return { ok = false, reason = ("Not enough money (EUR %d)."):format(price) }
	end
	counter += 1
	table.insert(profile.orders, {
		id = ("o%d_%d"):format(os.time(), counter),
		partId = partId, bikeId = vehicle.id,
		deliverAt = os.time() + CFG.DeliverySeconds, arrived = false,
	})
	PartsService.pushOrders(player)
	Economy.notify(player, ("Ordered: %s (EUR %d). Delivery to your garage in about %ds."):format(part.name, price, CFG.DeliverySeconds), "good")
	return { ok = true, eta = CFG.DeliverySeconds }
end

----------------------------------------------------------------------------
-- Delivery
----------------------------------------------------------------------------
local function tryDeliver(player: Player)
	local profile = Data.get(player)
	if not (profile and Garage.get(player)) then
		return
	end
	local now = os.time()
	for _, o in ipairs(profile.orders) do
		if not o.arrived and o.deliverAt <= now and not inFlight[o.id] then
			inFlight[o.id] = true
			task.spawn(function()
				local ok, err = pcall(Garage.deliver, player, o)
				if not ok then
					warn("[PartsService] delivery failed: " .. tostring(err))
				end
				inFlight[o.id] = nil
			end)
			return -- one van at a time
		end
	end
end

-- called by PlayerGarage once the crate exists
function PartsService.markArrived(player: Player, orderRecord)
	orderRecord.arrived = true
	PartsService.pushOrders(player)
end

-- A player joined and their garage is built: put waiting crates on the pad.
function PartsService.onJoin(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	for _, o in ipairs(profile.orders) do
		if o.arrived then
			Garage.placeCrate(player, o)
		end
	end
	PartsService.pushOrders(player)
end

----------------------------------------------------------------------------
-- Unpack, install, remove
----------------------------------------------------------------------------
function PartsService.unpack(player: Player, orderId: string)
	local profile = Data.get(player)
	if not profile or rateLimited(player, "unpack", 0.3) then
		return
	end
	for i, o in ipairs(profile.orders) do
		if o.id == orderId and o.arrived then
			local part = PartsData.byId[o.partId]
			local vehicle = VehicleData.byId[o.bikeId]
			table.remove(profile.orders, i)
			entry(profile, o.bikeId).owned[o.partId] = true
			Garage.removeCrate(player, orderId)
			Economy.notify(player, ("Unpacked: %s for the %s. Put the bike on the stand to fit it."):format(part and part.name or o.partId, vehicle and vehicle.displayName or o.bikeId), "good")
			Data.push(player)
			PartsService.pushOrders(player)
			return
		end
	end
end

local function standRecFor(player: Player, bikeId)
	local rec = Garage.standBike(player)
	if rec and rec.vehicle.id == bikeId then
		return rec
	end
	return nil
end

local function install(player: Player, bikeId, partId)
	if rateLimited(player, "install", 0.4) then
		return { ok = false, reason = "Slow down" }
	end
	local profile = Data.get(player)
	local part = typeof(partId) == "string" and PartsData.byId[partId]
	local vehicle = typeof(bikeId) == "string" and VehicleData.byId[bikeId]
	if not (profile and part and vehicle) then
		return { ok = false, reason = "Unknown part" }
	end
	local rec = standRecFor(player, bikeId)
	if not rec then
		return { ok = false, reason = "Put that bike on the raised stand first." }
	end
	local e = entry(profile, bikeId)
	if not e.owned[partId] then
		return { ok = false, reason = "That part isn't in your inventory." }
	end
	local fits, why = PartsData.fits(part, vehicle)
	if not fits then
		return { ok = false, reason = "Doesn't fit: " .. why }
	end
	local old = e.installed[part.slot]
	e.owned[partId] = nil
	e.installed[part.slot] = partId
	if old then
		e.owned[old] = true -- the replaced part goes back in the box
	end
	Vehicles.refit(player, rec)
	Data.push(player)
	Economy.notify(player, ("Fitted: %s."):format(part.name), "good")
	return { ok = true }
end

local function remove(player: Player, bikeId, slot)
	if rateLimited(player, "remove", 0.4) then
		return { ok = false, reason = "Slow down" }
	end
	local profile = Data.get(player)
	if not (profile and typeof(bikeId) == "string" and typeof(slot) == "string") then
		return { ok = false, reason = "Bad request" }
	end
	local rec = standRecFor(player, bikeId)
	if not rec then
		return { ok = false, reason = "Put that bike on the raised stand first." }
	end
	local e = entry(profile, bikeId)
	local id = e.installed[slot]
	if not id then
		return { ok = false, reason = "Nothing fitted there." }
	end
	e.installed[slot] = nil
	e.owned[id] = true
	Vehicles.refit(player, rec)
	Data.push(player)
	return { ok = true }
end

----------------------------------------------------------------------------
-- Phone: garage shortcuts
----------------------------------------------------------------------------
local function garageTeleport(player: Player, kind)
	if rateLimited(player, "teleport", 3) then
		return { ok = false, reason = "Wait a moment" }
	end
	if kind == "go" then
		return { ok = Garage.teleportHome(player) }
	elseif kind == "bikes" then
		local at = Garage.forecourt(player)
		if not at then
			return { ok = false, reason = "No garage yet" }
		end
		-- bikes line up in front of the door, facing the street
		local ok, reason = Vehicles.spawn(player, at)
		return { ok = ok, reason = reason }
	end
	return { ok = false, reason = "Unknown request" }
end

function PartsService.init(dataService, economyService, vehicleService, garageSvc)
	Data, Economy, Vehicles, Garage = dataService, economyService, vehicleService, garageSvc
	Remotes.func("PartsOrder").OnServerInvoke = order
	Remotes.func("PartsInstall").OnServerInvoke = install
	Remotes.func("PartsRemove").OnServerInvoke = remove
	Remotes.func("GarageTeleport").OnServerInvoke = garageTeleport
	Remotes.event("OrdersChanged").OnServerEvent:Connect(function(player)
		Data.push(player) -- the client asks once at start-up; the first push at load is usually missed
		PartsService.pushOrders(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastCall[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(tryDeliver, player)
				if not ok then
					warn("[PartsService] " .. tostring(err))
				end
			end
		end
	end)
end

return PartsService
