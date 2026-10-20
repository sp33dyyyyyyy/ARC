-- RemoteEvents shared by server and client. The server creates them; clients wait.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local NAMES = {
	"BuyBoost", -- client -> server: boostId
	"BuyChalk", -- client -> server
	"BuyEmote", -- client -> server: emoteId
	"EquipEmote", -- client -> server: emoteId (played automatically at summits)
	"UseChalk", -- client -> server
	"Ragdoll", -- client -> server: isRagdolled, fallStartY?
	"RestCheckpoint", -- client -> server: wallNormal (hanging on a rest bar)
	"ClimbPose", -- client -> server: "" | "climb" | "rest" | "leap" (shared climbing animation)
	"ResetToPlaza", -- client -> server
	"SaveSetting", -- client -> server: key, value
	"AdminLogin", -- client -> server: code
	"AdminAction", -- client -> server: action, args (re-checked on the server)
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
