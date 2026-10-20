-- RemoteEvents shared by server and client. The server creates them; clients wait.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local NAMES = {
	"BuyBoost", -- client -> server: boostId
	"BuyChalk", -- client -> server
	"UseChalk", -- client -> server
	"Ragdoll", -- client -> server: isRagdolled, fallStartY?
	"ResetToPlaza", -- client -> server
	"Notify", -- server -> client: kind, payload
	"Gust", -- server -> all clients: phase, direction, duration
}

function Remotes.create()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

function Remotes.get(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

return Remotes
