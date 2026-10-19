--[[
	DataService  (ModuleScript, ServerScriptService/Services)

	Saves and loads each player's profile with DataStoreService.

	Safety rules
	  * Every DataStore call goes through withRetry(): pcall + exponential
	    backoff, so a Roblox hiccup never throws into game code.
	  * If a LOAD still fails after all attempts, the player gets a temporary
	    profile flagged `volatile`. We never SAVE a volatile profile, so a
	    failed read can't overwrite real progress with defaults.
	  * Saves use UpdateAsync, autosave every GameConfig.Data.AutosaveSeconds,
	    on PlayerRemoving, and in BindToClose for server shutdown.
	  * Studio: enable Game Settings > Security > "Enable Studio Access to API
	    Services" or you will get the (harmless) volatile profile.

	Profile shape (saved):
	  { version, money, owned = { [id] = { paint = 1|2 } }, equipped,
	    jobs, earned, bikeState = { [id] = { fuel, health } } }
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local VehicleData = require(game.ReplicatedStorage.Shared.VehicleData)

local CFG = GameConfig.Data
local PROFILE_VERSION = 1

local DataService = {}

-- Created lazily and inside pcall: GetDataStore can throw in an unpublished
-- place, and that must never stop the game from starting.
local store: any = nil
local function getStore()
	if not store then
		store = DataStoreService:GetDataStore(CFG.StoreName)
	end
	return store
end
local profiles: { [Player]: any } = {}
local beforeSave: { (Player) -> () } = {}

-- Other services register here to write their live state (e.g. fuel in the bike
-- you are riding) into the profile right before it is saved.
function DataService.onBeforeSave(fn: (Player) -> ())
	table.insert(beforeSave, fn)
end
local savingInFlight = 0

local function defaultProfile()
	return {
		version = PROFILE_VERSION,
		money = GameConfig.Economy.StartingMoney,
		owned = { aerox50 = { paint = 1 } }, -- the free starter scooter
		equipped = "aerox50",
		jobs = 0,
		earned = 0,
		bikeState = {},
		parts = {}, -- [bikeId] = { owned = {id=true}, installed = {slot=id} }
		orders = {}, -- parts on their way / waiting as crates: {id, partId, bikeId, deliverAt, arrived}
	}
end

-- Fill any keys missing from an older save without clobbering existing values.
local function reconcile(target, template)
	for k, v in pairs(template) do
		if target[k] == nil then
			if type(v) == "table" then
				target[k] = table.clone(v)
			else
				target[k] = v
			end
		end
	end
	return target
end

----------------------------------------------------------------------------
-- pcall + retry with exponential backoff
----------------------------------------------------------------------------
local function withRetry(label: string, fn: () -> any): (boolean, any)
	local lastErr
	-- In Studio the DataStore either works at once or never (API access off,
	-- unpublished place), so don't make the tester wait through retries.
	local attempts = RunService:IsStudio() and 1 or CFG.MaxAttempts
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		local msg = tostring(result)
		-- Studio without API access will never succeed; don't stall the join.
		if msg:find("Studio access to APIs is not allowed") or msg:find("403") then
			warn(("[DataService] %s: no API access (%s) - giving up"):format(label, msg))
			return false, result
		end
		warn(("[DataService] %s failed (attempt %d/%d): %s"):format(label, attempt, attempts, msg))
		if attempt < attempts then
			task.wait(2 ^ (attempt - 1)) -- 1, 2, 4, 8 s
		end
	end
	return false, lastErr
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

----------------------------------------------------------------------------
-- What the client is allowed to see
----------------------------------------------------------------------------
function DataService.view(profile)
	return {
		money = profile.money,
		owned = profile.owned,
		equipped = profile.equipped,
		jobs = profile.jobs,
		earned = profile.earned,
		parts = profile.parts,
		orders = profile.orders,
	}
end

function DataService.push(player: Player)
	local profile = profiles[player]
	if profile then
		Remotes.event("DataChanged"):FireClient(player, DataService.view(profile))
	end
end

----------------------------------------------------------------------------
-- Load / save
----------------------------------------------------------------------------
-- Saves from older versions may mention bikes that no longer exist.
function DataService.sanitize(profile)
	for id in pairs(profile.owned) do
		if not VehicleData.byId[id] then
			profile.owned[id] = nil
		end
	end
	for id in pairs(profile.parts) do
		if not VehicleData.byId[id] then
			profile.parts[id] = nil
		end
	end
	for i = #profile.orders, 1, -1 do
		if not VehicleData.byId[profile.orders[i].bikeId] then
			table.remove(profile.orders, i)
		end
	end
	if not profile.owned.aerox50 and next(profile.owned) == nil then
		profile.owned.aerox50 = { paint = 1 }
	end
	if not (profile.equipped and profile.owned[profile.equipped]) then
		profile.equipped = next(profile.owned)
	end
end

function DataService.load(player: Player)
	local ok, data = withRetry("load " .. player.Name, function()
		return getStore():GetAsync(keyFor(player))
	end)

	local profile
	if ok then
		profile = reconcile(type(data) == "table" and data or {}, defaultProfile())
		DataService.sanitize(profile)
	else
		profile = defaultProfile()
		profile.volatile = true -- never saved
		warn("[DataService] Using a temporary profile for " .. player.Name .. " (progress will NOT be saved)")
	end

	if not player:IsDescendantOf(Players) then
		return nil -- left while loading
	end
	profiles[player] = profile
	DataService.push(player)
	return profile
end

function DataService.save(player: Player, final: boolean?)
	local profile = profiles[player]
	if not profile or profile.volatile then
		return
	end
	for _, fn in ipairs(beforeSave) do
		pcall(fn, player)
	end
	savingInFlight += 1
	local snapshot = table.clone(profile)
	local ok = withRetry("save " .. player.Name, function()
		getStore():UpdateAsync(keyFor(player), function()
			return snapshot -- full overwrite; this server owns the profile
		end)
	end)
	savingInFlight -= 1
	if not ok then
		warn("[DataService] Could not save " .. player.Name)
	end
	if final then
		profiles[player] = nil
	end
end

function DataService.get(player: Player)
	return profiles[player]
end

----------------------------------------------------------------------------
function DataService.init()
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player, true)
	end)

	-- autosave loop
	task.spawn(function()
		while true do
			task.wait(CFG.AutosaveSeconds)
			for player in pairs(profiles) do
				task.spawn(DataService.save, player, false)
				task.wait(0.5) -- spread requests out
			end
		end
	end)

	-- server shutdown: save everyone and wait for the requests to finish
	game:BindToClose(function()
		if RunService:IsStudio() then
			task.wait(0.2)
		end
		for player in pairs(profiles) do
			task.spawn(DataService.save, player, true)
		end
		local deadline = os.clock() + 25
		while savingInFlight > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return DataService
