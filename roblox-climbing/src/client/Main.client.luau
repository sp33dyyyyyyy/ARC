--!strict
-- Client entry point. The only LocalScript; everything else is a ModuleScript controller.
-- Order: Init every controller -> Start every controller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Client = script.Parent
local CONTROLLER_ORDER = {
	"HoldInspector",
	"ClimbController",
	"RouteHud",
	"GearUI",
	"PackUI",
	"Phone",
}

print(`[{Config.GameName}] client v{Config.Version}`)

type Controller = { Init: (() -> ())?, Start: (() -> ())? }
local controllers: { Controller } = {}
for _, name in CONTROLLER_ORDER do
	local module = Client.Controllers:WaitForChild(name)
	assert(module:IsA("ModuleScript"), `controller {name} must be a ModuleScript`)
	table.insert(controllers, require(module) :: any)
end
for _, controller in controllers do
	if controller.Init then
		controller.Init()
	end
end
for _, controller in controllers do
	if controller.Start then
		task.spawn(controller.Start)
	end
end
