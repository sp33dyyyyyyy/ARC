--!strict
-- Server entry point. The only Script on the server; everything else is a ModuleScript.
-- Order: build missing world pieces -> Init every service -> Start every service.
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

require(Server.World.TestWall).Ensure()

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

-- Limb IK (Stage 2) needs R15. StarterPlayer.GameSettingsAvatar is set to R15 by the
-- Rojo project, but a published game's Avatar settings can override it.
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
			warn(`[{Config.GameName}] {player.Name} spawned as {humanoid.RigType.Name}; set Game Settings > Avatar > Avatar Type to R15`)
		end
	end)
end)

if Config.Debug.RunSelfChecksInStudio and RunService:IsStudio() then
	task.defer(function()
		require(Server.Diagnostics.Stage1Check).Run()
	end)
end
