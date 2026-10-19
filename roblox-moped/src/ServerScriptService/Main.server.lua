--[[
	Main  (Script, ServerScriptService)

	Boots the server. Every step is wrapped so ONE broken module can never stop
	the rest of the game: the town is built first (it needs nothing else), then
	each service starts independently. Progress and failures go to the Output
	window with a "[MopedDays]" prefix.
]]

local Players = game:GetService("Players")

print("[MopedDays] starting server")

local function safeRequire(container: Instance, name: string): any
	local child = container:FindFirstChild(name)
	if not child then
		warn(("[MopedDays] missing module '%s'"):format(name))
		return nil
	end
	local ok, result = pcall(require, child)
	if not ok then
		warn(("[MopedDays] could not load '%s': %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

local function try(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[MopedDays] %s failed: %s"):format(label, tostring(err)))
	end
	return ok
end

local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Services = script.Parent:WaitForChild("Services")

safeRequire(Shared, "Remotes") -- creates every RemoteEvent/Function

-- 1. the world first: it depends on nothing else
local TownBuilder = safeRequire(Services, "TownBuilder")
if TownBuilder then
	try("TownBuilder", function()
		TownBuilder.build()
	end)
end

-- 2. services
local DataService = safeRequire(Services, "DataService")
local Economy = safeRequire(Services, "EconomyService")
local Vehicles = safeRequire(Services, "VehicleService")
local Garage = safeRequire(Services, "GarageService")
local Stations = safeRequire(Services, "StationService")
local Missions = safeRequire(Services, "MissionService")

if not (DataService and Economy and Vehicles) then
	warn("[MopedDays] core services failed to load - see the errors above. Bikes cannot spawn.")
	return
end

try("DataService.init", function() DataService.init() end)
try("Economy.init", function() Economy.init(DataService) end)
try("Vehicles.init", function() Vehicles.init(DataService, Economy) end)
if Garage then try("Garage.init", function() Garage.init(DataService, Economy, Vehicles) end) end
if Stations then try("Stations.init", function() Stations.init(Economy, Vehicles, Garage) end) end
if Missions then try("Missions.init", function() Missions.init(Economy, Vehicles) end) end
print("[MopedDays] services ready")

-- 3. players
local function onPlayerAdded(player: Player)
	print(("[MopedDays] %s joined"):format(player.Name))
	local okLoad, profile = pcall(DataService.load, player) -- yields
	if not okLoad or not profile then
		warn(("[MopedDays] could not load a profile for %s: %s"):format(player.Name, tostring(profile)))
		return
	end
	try("leaderstats", function() Economy.setupPlayer(player) end)

	-- put the bike(s) next to the player once their character exists
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart")
		task.wait(1)
		if not player.Parent then
			return
		end
		local ok, spawned, reason = pcall(Vehicles.spawn, player)
		if ok and spawned then
			print(("[MopedDays] bike(s) spawned for %s"):format(player.Name))
		else
			warn(("[MopedDays] bike spawn failed for %s: %s"):format(player.Name, tostring(ok and reason or spawned)))
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
