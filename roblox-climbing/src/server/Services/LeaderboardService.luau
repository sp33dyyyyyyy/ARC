--!strict
-- LeaderboardService (server): fastest times on every route with Leaderboard = true.
--
--  * One OrderedDataStore per route ("Times_<RouteId>"), keyed by UserId, holding the
--    player's best time in milliseconds (lower is better).
--  * Reloads the top Config.Routes.LeaderboardSize every LeaderboardRefresh seconds and
--    writes them on the sign at the route's base (RouteKit.addSign) and on the gym's big
--    leaderboard wall.
--  * Without DataStores (Studio without API access) it keeps the times in memory, so the
--    signs still work while you test.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local DataService = require(script.Parent.DataService)

local ROUTES = Config.Routes

export type Entry = { userId: number, name: string, ms: number }

local LeaderboardService = {}

local stores: { [string]: OrderedDataStore } = {}
local memory: { [string]: { [number]: number } } = {} -- routeId -> userId -> ms
local cached: { [string]: { Entry } } = {}
local names: { [number]: string } = {}

local function formatTime(ms: number): string
	local seconds = ms / 1000
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
end
LeaderboardService.formatTime = formatTime

local function storeFor(routeId: string): OrderedDataStore?
	if not DataService.IsPersistent() then
		return nil
	end
	local store: OrderedDataStore? = stores[routeId]
	if store == nil then
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(`Times_{routeId}`)
		end)
		if not ok then
			return nil
		end
		store = result
		stores[routeId] = result
	end
	return store
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local known = names[userId]
	if known then
		return known
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else `#{userId}`
	names[userId] = name
	return name
end

local function leaderboardRoutes(): { Instance }
	local list = {}
	local routes = Workspace:FindFirstChild("Routes")
	if routes then
		for _, route in routes:GetChildren() do
			if route:GetAttribute("Leaderboard") == true then
				table.insert(list, route)
			end
		end
	end
	table.sort(list, function(a, b)
		return (tonumber(a:GetAttribute("Order")) or 99) < (tonumber(b:GetAttribute("Order")) or 99)
	end)
	return list
end

local function load(routeId: string): { Entry }
	local entries: { Entry } = {}
	local store = storeFor(routeId)
	if store then
		local ok, pages = pcall(function()
			return (store :: OrderedDataStore):GetSortedAsync(true, ROUTES.LeaderboardSize)
		end)
		if ok and pages then
			for _, item in (pages :: DataStorePages):GetCurrentPage() do
				local userId = tonumber(item.key)
				if userId and type(item.value) == "number" and item.value > 0 then
					table.insert(entries, { userId = userId, name = "", ms = item.value })
				end
			end
		else
			return cached[routeId] or {}
		end
	else
		local times: { [number]: number } = memory[routeId] or {}
		for userId, ms in times do
			table.insert(entries, { userId = userId, name = "", ms = ms })
		end
		table.sort(entries, function(a, b)
			return a.ms < b.ms
		end)
		while #entries > ROUTES.LeaderboardSize do
			table.remove(entries)
		end
	end
	for _, entry in entries do
		entry.name = nameOf(entry.userId)
	end
	return entries
end

---------------------------------------------------------------------------------------
-- Drawing on the signs

local function row(parent: Instance, rank: number, entry: Entry, textSize: number, height: number)
	local frame = Instance.new("Frame")
	frame.Name = `Row{rank}`
	frame.LayoutOrder = rank
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = if rank == 1 then Color3.fromRGB(60, 34, 18) else Color3.fromRGB(30, 32, 36)
	frame.BackgroundTransparency = if rank % 2 == 0 then 0.5 else 0.25
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = frame
	local rankLabel = Instance.new("TextLabel")
	rankLabel.BackgroundTransparency = 1
	rankLabel.Size = UDim2.new(0, height * 1.3, 1, 0)
	rankLabel.Font = Enum.Font.Michroma
	rankLabel.TextSize = textSize
	rankLabel.TextColor3 = if rank == 1 then Color3.fromRGB(255, 122, 48) elseif rank <= 3 then Color3.fromRGB(238, 237, 233) else Color3.fromRGB(146, 149, 156)
	rankLabel.Text = string.format("%02d", rank)
	rankLabel.Parent = frame
	local headshot = Instance.new("ImageLabel")
	headshot.BackgroundTransparency = 1
	headshot.Position = UDim2.new(0, height * 1.3, 0, 2)
	headshot.Size = UDim2.fromOffset(height - 4, height - 4)
	headshot.Image = `rbxthumb://type=AvatarHeadShot&id={entry.userId}&w=48&h=48`
	headshot.Parent = frame
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, height * 2.4, 0, 0)
	name.Size = UDim2.new(1, -height * 2.4 - 90, 1, 0)
	name.Font = Enum.Font.GothamMedium
	name.TextSize = textSize
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = entry.name
	name.Parent = frame
	local time = Instance.new("TextLabel")
	time.BackgroundTransparency = 1
	time.AnchorPoint = Vector2.new(1, 0)
	time.Position = UDim2.new(1, -8, 0, 0)
	time.Size = UDim2.new(0, 84, 1, 0)
	time.Font = Enum.Font.Sarpanch
	time.TextSize = textSize
	time.TextXAlignment = Enum.TextXAlignment.Right
	time.TextColor3 = Color3.fromRGB(126, 222, 152)
	time.Text = formatTime(entry.ms)
	time.Parent = frame
	frame.Parent = parent
end

local function drawRows(rows: Instance, entries: { Entry }, count: number, textSize: number, height: number)
	for _, child in rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local empty = rows:FindFirstChild("Empty")
	if empty and empty:IsA("GuiObject") then
		empty.Visible = #entries == 0
	end
	for rank = 1, math.min(count, #entries) do
		row(rows, rank, entries[rank], textSize, height)
	end
end

local function drawSign(route: Instance, entries: { Entry })
	local sign = route:FindFirstChild("Sign")
	local board = sign and sign:FindFirstChild("Board")
	local gui = board and board:FindFirstChild("Leaderboard")
	local rows = gui and gui:FindFirstChild("Rows")
	if rows then
		drawRows(rows, entries, ROUTES.LeaderboardSize, 17, 26)
	end
end

local function gymGrid(): Instance?
	local gym = Workspace:FindFirstChild("Gym")
	local wall = gym and gym:FindFirstChild("LeaderboardWall")
	local board = wall and wall:FindFirstChild("Board")
	local gui = board and board:FindFirstChild("GymLeaderboard")
	return gui and gui:FindFirstChild("Grid")
end

local function drawGymCell(grid: Instance, index: number, route: Instance, entries: { Entry })
	local cell = grid:FindFirstChild(route.Name)
	if cell == nil then
		local frame = Instance.new("Frame")
		frame.Name = route.Name
		frame.LayoutOrder = index
		frame.BackgroundColor3 = Color3.fromRGB(19, 20, 23)
		frame.BackgroundTransparency = 0.2
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = frame
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(10, 6)
		title.Size = UDim2.new(1, -20, 0, 30)
		title.Font = Enum.Font.Michroma
		title.TextSize = 24
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Color3.fromRGB(255, 122, 48)
		title.Text = `{string.upper(tostring(route:GetAttribute("RouteName")))}  <font color="#92959C">{route:GetAttribute("Grade")} · {route:GetAttribute("HeightMeters")}m</font>`
		title.RichText = true
		title.Parent = frame
		local rows = Instance.new("Frame")
		rows.Name = "Rows"
		rows.BackgroundTransparency = 1
		rows.Position = UDim2.fromOffset(8, 42)
		rows.Size = UDim2.new(1, -16, 1, -48)
		rows.Parent = frame
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = rows
		local empty = Instance.new("TextLabel")
		empty.Name = "Empty"
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 28)
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 18
		empty.TextColor3 = Color3.fromRGB(146, 149, 156)
		empty.Text = "No times yet"
		empty.Parent = rows
		frame.Parent = grid
		cell = frame
	end
	local rows = (cell :: Instance):FindFirstChild("Rows")
	if rows then
		drawRows(rows, entries, 4, 16, 28)
	end
end

local function refresh(only: string?)
	local grid = gymGrid()
	for index, route in leaderboardRoutes() do
		if only and route.Name ~= only then
			continue
		end
		local entries = load(route.Name)
		cached[route.Name] = entries
		drawSign(route, entries)
		if grid then
			drawGymCell(grid, index, route, entries)
		end
	end
end

---------------------------------------------------------------------------------------
-- API

-- Records a finished run. Only improvements are written. Returns the player's rank on the
-- cached board (nil if outside it).
function LeaderboardService.Submit(player: Player, routeId: string, seconds: number): number?
	local ms = math.floor(seconds * 1000 + 0.5)
	if ms <= 0 then
		return nil
	end
	local store = storeFor(routeId)
	if store then
		pcall(function()
			-- Returning nil cancels the write (the typings say number, so go through any).
			(store :: any):UpdateAsync(tostring(player.UserId), function(old: any): number?
				if type(old) == "number" and old > 0 and old <= ms then
					return nil -- not an improvement: leave it
				end
				return ms
			end)
		end)
	else
		local times = memory[routeId] or {}
		memory[routeId] = times
		local old: number? = times[player.UserId]
		if old == nil or ms < old then
			times[player.UserId] = ms
		end
	end
	task.spawn(refresh, routeId)
	local board: { Entry } = cached[routeId] or {}
	for rank, entry in board do
		if entry.userId == player.UserId then
			return rank
		end
	end
	return nil
end

function LeaderboardService.Get(routeId: string): { Entry }
	return cached[routeId] or {}
end

function LeaderboardService.Start()
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				refresh(nil)
			end)
			if not ok then
				warn(`[LeaderboardService] refresh failed: {err}`)
			end
			task.wait(ROUTES.LeaderboardRefresh)
		end
	end)
end

return LeaderboardService
