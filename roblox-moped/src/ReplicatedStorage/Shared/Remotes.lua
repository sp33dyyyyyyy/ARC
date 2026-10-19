--[[
	Remotes  (ModuleScript, ReplicatedStorage/Shared)

	One place that declares every RemoteEvent / RemoteFunction.
	The server creates them on first require; clients wait for them.

	Client -> server
	  BikeInput(throttle, brake, gear)   10 Hz while controlling a bike
	  BikeAction(action, bikeModel)      a click on a control: "FuelTap" "Ignition"
	                                     "Choke" "Kick" "Starter" "Ride" "Grab"
	  GarageAction(action, garageModel, extra)   click on the garage door / light
	                                     switch / stand / workbench / parcel
	  PartsOrder(partId, bikeId) / PartsInstall(bikeId, partId) /
	  PartsRemove(bikeId, slot) / GarageTeleport()   (RemoteFunctions)
	  MissionAbandon()
	  GarageBuy / GarageEquip / GarageSpawn / MissionStart   (RemoteFunctions)

	Server -> client
	  DataChanged(view)                  money / owned bikes / unlock counters
	  OpenGarage(view) / OpenMissionBoard(offers)
	  MissionUpdate(state | nil)
	  BikeEvent(model, kind, data?)      one-shot cosmetics: Kick, Started, Sputter,
	                                     Stall, Crash, Click
	  OrdersChanged(list)                phone: parts orders and their ETA
	  OpenWorkshop(info)                 the workbench UI for the bike on the stand
	  Notify(text, kind)                 toast messages
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	"BikeInput",
	"BikeAction",
	"MissionAbandon",
	"DataChanged",
	"OpenGarage",
	"OpenMissionBoard",
	"MissionUpdate",
	"BikeEvent",
	"Notify",
	"GarageAction",
	"OrdersChanged",
	"OpenWorkshop",
}

local FUNCTIONS = {
	"GarageBuy",
	"GarageEquip",
	"GarageSpawn",
	"MissionStart",
	"PartsOrder",
	"PartsInstall",
	"PartsRemove",
	"GarageTeleport",
}

local Remotes = {}
local folder: Folder

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(EVENTS) do
		if not folder:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
	end
	for _, name in ipairs(FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local f = Instance.new("RemoteFunction")
			f.Name = name
			f.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
