-- Fills the plaza leaderboard with the all-time top climbers. Falls back to the
-- players in this server when the OrderedDataStore isn't available (Studio).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local ROWS = 10
local nameCache: { [number]: string } = {}

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = if ok then name else "Player " .. userId
	nameCache[userId] = result
	return result
end

local function buildBoard(part: BasePart): ({ TextLabel }, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 80)
	title.Font = Enum.Font.GothamBlack
	title.Text = "TOP CLIMBERS"
	title.TextColor3 = Color3.fromRGB(255, 210, 60)
	title.TextScaled = true
	title.Parent = gui
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 80)
	subtitle.Size = UDim2.new(1, 0, 0, 30)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = ""
	subtitle.TextColor3 = Color3.fromRGB(160, 170, 190)
	subtitle.TextScaled = true
	subtitle.Parent = gui
	local rows = {}
	for i = 1, ROWS do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = if i % 2 == 0 then 1 else 0.85
		row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		row.BorderSizePixel = 0
		row.Position = UDim2.new(0, 20, 0, 120 + (i - 1) * 42)
		row.Size = UDim2.new(1, -40, 0, 40)
		row.Font = Enum.Font.GothamBold
		row.TextColor3 = if i == 1 then Color3.fromRGB(255, 215, 80) else Color3.new(1, 1, 1)
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = ""
		row.Parent = gui
		rows[i] = row
	end
	gui.Parent = part
	return rows, subtitle
end

local function render(rows: { TextLabel }, entries: { { name: string, climbs: number } })
	for i, row in rows do
		local entry = entries[i]
		row.Text = if entry then string.format("  #%d  %s  -  %d climbs", i, entry.name, entry.climbs) else ""
	end
end

local function localEntries(): { { name: string, climbs: number } }
	local entries = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			table.insert(entries, { name = player.DisplayName, climbs = data.Climbs })
		end
	end
	table.sort(entries, function(a, b)
		return a.climbs > b.climbs
	end)
	return entries
end

function LeaderboardService.start(board: BasePart)
	local rows, subtitle = buildBoard(board)
	task.spawn(function()
		while true do
			local store = DataService.orderedStore()
			local entries = nil
			if store then
				local ok, pages = pcall(function()
					return store:GetSortedAsync(false, ROWS)
				end)
				if ok then
					entries = {}
					for _, item in pages:GetCurrentPage() do
						local userId = tonumber(item.key)
						if userId then
							table.insert(entries, { name = nameFor(userId), climbs = item.value })
						end
					end
				end
			end
			if entries and #entries > 0 then
				subtitle.Text = "All-time tower climbs"
				render(rows, entries)
			else
				subtitle.Text = "Climbs in this server"
				render(rows, localEntries())
			end
			task.wait(Config.LeaderboardRefresh)
		end
	end)
	-- Keep the local fallback lively between store refreshes.
	DataService.onChanged(function()
		if subtitle.Text == "Climbs in this server" then
			render(rows, localEntries())
		end
	end)
end

return LeaderboardService
