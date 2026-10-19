--[[
	Main  (Script, ServerScriptService)

	Boots the server in dependency order and hooks player join/leave.
	Nothing else in ServerScriptService runs by itself - every file in
	Services/ is a ModuleScript that Main requires.
]]

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
require(Shared.Remotes) -- creates all RemoteEvents/Functions before any client asks

local Services = script.Parent.Services
local DataService = require(Services.DataService)
local Economy = require(Services.EconomyService)
local Vehicles = require(Services.VehicleService)
local Garage = require(Services.GarageService)
local Stations = require(Services.StationService)
local Missions = require(Services.MissionService)
local TownBuilder = require(Services.TownBuilder)

TownBuilder.build()

DataService.init()
Economy.init(DataService)
Vehicles.init(DataService, Economy)
Garage.init(DataService, Economy, Vehicles)
Stations.init(Economy, Vehicles, Garage)
Missions.init(Economy, Vehicles)

local function onPlayerAdded(player: Player)
	local profile = DataService.load(player) -- yields (with retries)
	if not profile then
		return
	end
	Economy.setupPlayer(player)

	-- put the starter bike next to the player on first spawn
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart")
		task.wait(1)
		if player.Parent then
			Vehicles.spawn(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
