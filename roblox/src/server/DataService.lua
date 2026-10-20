-- Player save data.
--
-- Safety rules:
--   * Never save a profile that failed to load. Saving defaults over real data
--     would wipe the player.
--   * Session lock: a profile records which server owns it, so two servers can't
--     overwrite each other when a player hops quickly. A stale lock (server
--     crashed) is taken over after LOCK_TIMEOUT.
--   * Retries with backoff, autosave, and a final save on leave / shutdown.
--
-- In an unpublished place, or with Studio API access off, DataStores fail; the
-- game still runs but progress is not saved and the player is told so.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)

local DataService = {}

local LOCK_TIMEOUT = 180
local RETRIES = 3

type Profile = { data: any, persistent: boolean, dirty: boolean }

local profiles: { [Player]: Profile } = {}
local changedCallbacks: { (Player, any) -> () } = {}

local store: DataStore? = nil
local orderedStore: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.DataStoreName)
		orderedStore = DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	if not ok then
		warn("[DataService] DataStores unavailable, progress will not save:", err)
	end
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T | string)
	local lastErr
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[DataService] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		if attempt < RETRIES then
			task.wait(2 ^ attempt)
		end
	end
	return false, lastErr
end

-- Copies the profile onto the player so the client UI can read it.
local function sync(player: Player, data: any)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		(stats:FindFirstChild("Cash") :: IntValue).Value = data.Cash;
		(stats:FindFirstChild("Climbs") :: IntValue).Value = data.Climbs
	end
	for id, lvl in data.Boosts do
		player:SetAttribute("Boost_" .. id, lvl)
	end
	player:SetAttribute("Chalk", data.Chalk)
	player:SetAttribute("Streak", data.Streak)
	player:SetAttribute("BestHeight", math.floor(data.BestHeight))
	for _, cb in changedCallbacks do
		task.spawn(cb, player, data)
	end
end

local function makeLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local climbs = Instance.new("IntValue")
	climbs.Name = "Climbs"
	climbs.Parent = stats
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = stats
	stats.Parent = player
end

function DataService.load(player: Player): any
	makeLeaderstats(player)
	local persistent = false
	local saved = nil

	if store then
		local key = keyFor(player)
		for attempt = 1, RETRIES do
			local lockedElsewhere = false
			local ok, err = withRetries("load " .. key, function()
				return (store :: DataStore):UpdateAsync(key, function(old)
					old = old or {}
					local lock = old._lock
					lockedElsewhere = lock ~= nil
						and lock.job ~= game.JobId
						and os.time() - (lock.time or 0) < LOCK_TIMEOUT
						and attempt < RETRIES -- last attempt takes over the lock
					if lockedElsewhere then
						return nil -- cancel the write; try again shortly
					end
					saved = old
					old._lock = { job = game.JobId, time = os.time() }
					return old
				end)
			end)
			if not ok then
				warn("[DataService] could not load", player.Name, err)
				break
			end
			if not lockedElsewhere then
				persistent = true
				break
			end
			task.wait(5)
		end
	end

	if not player.Parent then
		-- Left while loading: hand the lock back so their next server isn't kept waiting.
		if persistent and store then
			pcall(function()
				(store :: DataStore):UpdateAsync(keyFor(player), function(old)
					if old and old._lock and old._lock.job == game.JobId then
						old._lock = nil
						return old
					end
					return nil
				end)
			end)
		end
		return nil
	end

	local data = Rules.reconcileProfile(Config.Boosts, Config.Chalk, saved)
	profiles[player] = { data = data, persistent = persistent, dirty = false }
	sync(player, data)
	player:SetAttribute("DataLoaded", true)
	player:SetAttribute("DataPersistent", persistent)
	return data
end

function DataService.get(player: Player): any?
	local profile = profiles[player]
	return profile and profile.data
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Mutate a player's data through `fn`; changes are mirrored to the client.
function DataService.update(player: Player, fn: (any) -> ())
	local profile = profiles[player]
	if not profile then
		return false
	end
	fn(profile.data)
	profile.dirty = true
	sync(player, profile.data)
	return true
end

function DataService.onChanged(cb: (Player, any) -> ())
	table.insert(changedCallbacks, cb)
end

function DataService.save(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not profile.persistent or not store then
		return
	end
	if not profile.dirty and not release then
		return
	end
	local key = keyFor(player)
	local snapshot = table.clone(profile.data)
	snapshot.Boosts = table.clone(profile.data.Boosts)
	local ok = withRetries("save " .. key, function()
		return (store :: DataStore):UpdateAsync(key, function(old)
			old = old or {}
			local lock = old._lock
			if lock and lock.job ~= game.JobId and os.time() - (lock.time or 0) < LOCK_TIMEOUT then
				-- Another server took this profile over; don't clobber its data.
				return nil
			end
			snapshot._lock = if release then nil else { job = game.JobId, time = os.time() }
			return snapshot
		end)
	end)
	if ok then
		profile.dirty = false
	end
	if orderedStore then
		pcall(function()
			(orderedStore :: OrderedDataStore):SetAsync(tostring(player.UserId), profile.data.Climbs)
		end)
	end
end

function DataService.release(player: Player)
	DataService.save(player, true)
	profiles[player] = nil
end

function DataService.start()
	Players.PlayerRemoving:Connect(function(player)
		DataService.release(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(DataService.save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

DataService.orderedStore = function()
	return orderedStore
end

return DataService
