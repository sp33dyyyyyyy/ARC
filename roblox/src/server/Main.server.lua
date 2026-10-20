-- Server entry point: builds the world and starts every service.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local Remotes = require(Shared.Remotes)

Remotes.create()

local WorldBuilder = require(script.Parent.WorldBuilder)
local DataService = require(script.Parent.DataService)
local ClimbService = require(script.Parent.ClimbService)
local RagdollService = require(script.Parent.RagdollService)
local ShopService = require(script.Parent.ShopService)
local EnvironmentService = require(script.Parent.EnvironmentService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local AdminService = require(script.Parent.AdminService)

local world, towers = WorldBuilder.build()

-- Keep the spawn pad on the plaza even if someone moved it in Studio.
local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
local spawnCFrame = if spawn then spawn.CFrame + Vector3.new(0, 4, 0) else WorldBuilder.PlazaSpawn

DataService.start()
ClimbService.start(towers, spawnCFrame)
RagdollService.start()
ShopService.start()
EnvironmentService.start()
LeaderboardService.start(world:FindFirstChild("Leaderboard") :: BasePart)
AdminService.start()

local notify = Remotes.get("Notify")

local function onPlayer(player: Player)
	local data = DataService.load(player)
	if not data then
		return
	end
	ClimbService.equipTrail(player)
	if not player:GetAttribute("DataPersistent") then
		notify:FireClient(player, "Toast", {
			text = "Saving is off here (publish the place and enable API access to keep progress).",
			style = "bad",
		})
	end

	local today = math.floor(os.time() / 86400)
	local streak, reward, claimed = Rules.dailyReward(Config.Daily, data.LastDaily, data.Streak, today)
	if not claimed then
		DataService.update(player, function(d)
			d.LastDaily = today
			d.Streak = streak
			d.Cash += reward
		end)
		notify:FireClient(player, "Daily", { streak = streak, reward = reward })
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
