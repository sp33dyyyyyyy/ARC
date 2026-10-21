--!strict
-- Remotes: every RemoteEvent the game uses, declared in one place.
-- The server calls Remotes.setup() once at start-up; both sides get events with
-- Remotes.event(name), which waits for the server to create them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	-- client -> server: ("Place", limb, holdId) | ("Release", limb) | ("LetGo") | ("Dyno")
	--                   | ("Mantle", standPosition)
	"ClimbRequest",
	-- server -> client: (limb, reason) when a request was refused
	"ClimbRejected",
	-- server -> client: ("Started", routeId) | ("Summit", result) | ("Failed", routeId, reason)
	--                   | ("Notice", text)
	"RouteEvent",
	-- client -> server: ("Retry") | ("Travel", routeId) | ("Untie") | ("Lower")
	"RouteRequest",
	-- client -> server: ("Buy", itemId) | ("Equip", itemId) | ("Colour", "Pack" | "ChalkBag", index)
	"ShopRequest",
	-- server -> client: (ok, message)
	"ShopResult",
}

local Remotes = {}

Remotes.Names = table.freeze(EVENTS)

function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup() is server only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if folder:FindFirstChild(name) == nil then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end
end

function Remotes.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), `unknown remote {name}`)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

return table.freeze(Remotes)
