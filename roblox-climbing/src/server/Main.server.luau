--!strict
-- Server entry point. The only Script on the server; everything else is a ModuleScript.
-- Order: rig check -> lighting + missing world pieces -> Init every service -> Start every service.
-- Later stages add their services to SERVICE_ORDER (ClimbService, StaminaService, ...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Server = script.Parent
local SERVICE_ORDER = {
	"HoldService",
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
buildStep("TestWall.Ensure", function()
	require(Server.World.TestWall).Ensure()
end)

type Service = { Init: (() -> ())?, Start: (() -> ())? }
local services: { Service } = {}
for _, name in SERVICE_ORDER do
	local module = Server.Services:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `missing service module {name}`)
	table.insert(services, require(module) :: any)
end
for _, service in services do
	if service.Init then
		service.Init()
	end
end
for _, service in services do
	if service.Start then
		task.spawn(service.Start)
	end
end

if Config.Debug.RunSelfChecksInStudio and RunService:IsStudio() then
	task.defer(function()
		require(Server.Diagnostics.Stage1Check).Run()
	end)
end
