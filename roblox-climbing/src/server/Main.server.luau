--!strict
-- Server entry point. The only Script on the server; everything else is a ModuleScript.
-- Order: rig check -> lighting + missing world pieces -> Init every service -> Start every service.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Server = script.Parent
local SERVICE_ORDER = {
	"DataService",
	"HoldService",
	"ClimbService",
	"StaminaService",
	"RagdollService",
	"LeaderboardService",
	"RopeService",
	"RouteService",
	"ChalkService",
	"ShopService",
	"PropService",
}

print(`[{Config.GameName}] server v{Config.Version}`)

-- Limb IK (Stage 2) needs R15. StarterPlayer.GameSettingsAvatar is set to R15 by the
-- Rojo project, but a published game's Avatar settings can override it. Hooked up first,
-- and run for players already in game, so nobody who joins while the world builds is missed.
local function checkRig(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(`[{Config.GameName}] {player.Name} spawned as {humanoid.RigType.Name}; set Game Settings > Avatar > Avatar Type to R15`)
	end
end
local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		checkRig(player, character)
	end)
	if player.Character then
		task.spawn(checkRig, player, player.Character)
	end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

require(ReplicatedStorage.Shared.Remotes).setup()

-- Build missing world pieces. A failure here is reported but doesn't stop the services.
local function buildStep(name: string, run: () -> ())
	local ok, err = pcall(run :: () -> any)
	if not ok then
		warn(`[{Config.GameName}] {name} failed: {err}`)
	end
end
buildStep("Environment.Apply", function()
	require(Server.World.Environment).Apply()
end)
-- Gym first: it provides the floor and spawn the tutorial wall would otherwise make.
buildStep("Gym.Ensure", function()
	require(Server.World.Gym).Ensure()
end)
buildStep("TestWall.Ensure", function()
	require(Server.World.TestWall).Ensure()
end)
buildStep("Outdoors.Ensure", function()
	require(Server.World.Outdoors).Ensure()
end)

-- Each service starts on its own: one failing is reported loudly in Output and the others
-- still run.
type Service = { Init: (() -> ())?, Start: (() -> ())? }
local services: { [string]: Service } = {}
for _, name in SERVICE_ORDER do
	local module = Server.Services:FindFirstChild(name)
	local ok, result = pcall(function()
		assert(module and module:IsA("ModuleScript"), `missing service module {name}`)
		return require(module) :: any
	end)
	if ok then
		services[name] = result
	else
		warn(`[{Config.GameName}] SERVER ERROR loading {name}: {result}`)
	end
end
for _, name in SERVICE_ORDER do
	local service = services[name]
	if service and service.Init then
		local ok, err = pcall(service.Init :: () -> any)
		if not ok then
			warn(`[{Config.GameName}] SERVER ERROR in {name}.Init: {err}`)
			services[name] = nil
		end
	end
end
for _, name in SERVICE_ORDER do
	local service = services[name]
	if service and service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start :: () -> any)
			if not ok then
				warn(`[{Config.GameName}] SERVER ERROR in {name}.Start: {err}`)
			end
		end)
	end
end
print(`[{Config.GameName}] server ready`)

if Config.Debug.RunSelfChecksInStudio and RunService:IsStudio() then
	task.defer(function()
		require(Server.Diagnostics.Stage1Check).Run()
		require(Server.Diagnostics.Stage2Check).Run()
		require(Server.Diagnostics.Stage3Check).Run()
		require(Server.Diagnostics.Stage4Check).Run()
	end)
end
