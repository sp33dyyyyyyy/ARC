--!strict
-- DataService (server): each player's saved progress.
--
--  * One DataStore entry per player, session-locked so two servers can never overwrite
--    each other's progress (the lock is released on leave and taken over if it goes stale).
--  * Autosaves every few minutes, on leave and on server shutdown, with retries.
--  * Mirrors the numbers the HUD needs onto the Player as attributes: Gems, XP, Level,
--    Summits, TotalClimbed, and Best_<RouteId> for every route with a best time.
--  * In Studio without "Enable Studio Access to API Services" (Game Settings > Security),
--    DataStores are unavailable: it warns once and keeps progress in memory for the session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Pack = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Pack"))

local STORE_NAME = "PlayerData_v1"
local LOCK_STALE_SECONDS = 600 -- a lock older than this belongs to a dead server
local AUTOSAVE_SECONDS = 180
local RETRIES = 4

export type Data = {
	gems: number,
	xp: number,
	summits: number,
	totalClimbed: number, -- studs climbed on routes you finished
	bestTimes: { [string]: number }, -- seconds, per route id
	clears: { [string]: number }, -- summits per route id
	owned: { [string]: boolean }, -- gear bought at the pro shop (Gear item ids)
	equipped: { [string]: string }, -- Gear slot -> item id
	packColor: number, -- the equipped pack's look (Gear variant index)
	chalkColor: number, -- chalk bag look (Gear.CHALK_BAGS index)
	helmetColor: number, -- the equipped helmet's look
	pack: { [string]: number }, -- what's packed in your bag (Pack item id -> count)
}

type Profile = { data: Data, key: string, dirty: boolean, loaded: boolean }

local DataService = {}

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
local memoryOnly = false
local loadedListeners: { (Player, Data) -> () } = {}

local function defaults(): Data
	return { gems = 0, xp = 0, summits = 0, totalClimbed = 0, bestTimes = {}, clears = {}, owned = {}, equipped = {}, packColor = 1, chalkColor = 1, helmetColor = 1, pack = table.clone(Pack.DEFAULT) }
end

-- Fills in anything an older save is missing.
local function reconcile(saved: any): Data
	local data = defaults()
	if type(saved) == "table" then
		for key, value in saved do
			if (data :: any)[key] ~= nil and type(value) == type((data :: any)[key]) then
				(data :: any)[key] = value
			end
		end
	end
	return data
end

function DataService.levelFor(xp: number): number
	return math.floor(math.sqrt(math.max(0, xp) / 100)) + 1
end

local function sync(player: Player, data: Data)
	player:SetAttribute("Gems", data.gems)
	player:SetAttribute("XP", data.xp)
	player:SetAttribute("Level", DataService.levelFor(data.xp))
	player:SetAttribute("Summits", data.summits)
	player:SetAttribute("TotalClimbed", data.totalClimbed)
	for routeId, seconds in data.bestTimes do
		player:SetAttribute(`Best_{routeId}`, seconds)
	end
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataService] {label} failed (try {attempt}/{RETRIES}): {result}`)
		task.wait(attempt * 1.5)
	end
	return false, nil
end

local function save(player: Player, release: boolean)
	local profile = profiles[player]
	if profile == nil or not profile.loaded or profile.key == "" or memoryOnly or store == nil then
		return
	end
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	local data = profile.data
	local ok = withRetries(`saving {player.Name}`, function()
		return (store :: DataStore):UpdateAsync(profile.key, function(old: any)
			old = if type(old) == "table" then old else {}
			local lock = old.lock
			if type(lock) == "table" and lock.job ~= jobId then
				return nil -- someone else owns it now; don't clobber
			end
			old.data = data
			old.lock = if release then nil else { job = jobId, time = os.time() }
			return old
		end)
	end)
	if ok then
		profile.dirty = false
	end
end

local function load(player: Player)
	local key = `u_{player.UserId}`
	local profile: Profile = { data = defaults(), key = key, dirty = false, loaded = false }
	profiles[player] = profile

	if store and not memoryOnly then
		local jobId = if game.JobId ~= "" then game.JobId else "studio"
		local ok, saved = withRetries(`loading {player.Name}`, function()
			return (store :: DataStore):UpdateAsync(key, function(old: any)
				old = if type(old) == "table" then old else {}
				local lock = old.lock
				if type(lock) == "table" and lock.job ~= jobId and os.time() - (lock.time or 0) < LOCK_STALE_SECONDS then
					-- Another live server has this player; wait for it to let go.
					error("session locked by another server")
				end
				old.lock = { job = jobId, time = os.time() }
				return old
			end)
		end)
		if ok and type(saved) == "table" then
			profile.data = reconcile(saved.data)
		elseif not ok then
			warn(`[DataService] couldn't load {player.Name}; progress this session won't save`)
			profile.key = "" -- never overwrite their real save with an empty one
		end
	end

	profile.loaded = true
	if player.Parent == nil then
		-- Left while loading: give the session lock back straight away.
		save(player, true)
		profiles[player] = nil
		return
	end
	sync(player, profile.data)
	for _, listener in loadedListeners do
		task.spawn(listener, player, profile.data)
	end
end

-- The player's data, or nil until it has loaded.
function DataService.Get(player: Player): Data?
	local profile = profiles[player]
	return if profile and profile.loaded then profile.data else nil
end

-- Changes a player's data and refreshes their HUD attributes.
function DataService.Update(player: Player, change: (Data) -> ())
	local profile = profiles[player]
	if profile == nil or not profile.loaded then
		return
	end
	change(profile.data)
	profile.dirty = true
	sync(player, profile.data)
end

function DataService.OnLoaded(listener: (Player, Data) -> ())
	table.insert(loadedListeners, listener)
	for player, profile in profiles do
		if profile.loaded then
			task.spawn(listener, player, profile.data)
		end
	end
end

function DataService.IsPersistent(): boolean
	return store ~= nil and not memoryOnly
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		-- In Studio, check API access up front so we can say so clearly.
		if RunService:IsStudio() then
			local probeOk, err = pcall(function()
				return (store :: DataStore):GetAsync("__probe")
			end)
			if not probeOk then
				memoryOnly = true
				warn(`[DataService] DataStores unavailable in Studio ({err}). Progress is kept in memory this session. Turn on Game Settings > Security > "Enable Studio Access to API Services" to test saving.`)
			end
		end
	else
		memoryOnly = true
		warn(`[DataService] DataStores unavailable ({result}); progress is kept in memory this session`)
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player, true)
		profiles[player] = nil
	end)
	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local waited = 0
		while pending > 0 and waited < 25 do
			waited += task.wait(0.5)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, profile in profiles do
				if profile.dirty then
					task.spawn(save, player, false)
				end
			end
		end
	end)
end

return DataService
