--!strict
-- ShopService (server): the pro shop and the lockers.
--
--  * Buy gear with gems ("Buy"), equip what you own ("Equip"), and pick your pack and
--    chalk-bag colours ("Colour"). Everything is checked here and saved by DataService.
--  * Publishes on the Player, for the UI and the other services:
--      Owned        comma-separated item ids you own
--      Equip_<Slot> the item equipped in each slot
--      PackColor, ChalkColor  colour indices (Gear.COLORS)
--      GearFootDrain, GearChalkRate, GearChalkReduction, GearDynoCost, GearRopeColor
--  * Dresses every character in its pack and chalk bag (GearModels), welded on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Gear)
local GearModels = require(Shared.GearModels)
local RateLimiter = require(Shared.RateLimiter)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local ShopService = {}

local resultRemote: RemoteEvent
local limiter = RateLimiter.new(4, 8)

local function equippedItem(data: DataService.Data, slot: Gear.Slot): Gear.Item
	local item = Gear.get(data.equipped[slot])
	if item and item.slot == slot and (item.price == 0 or data.owned[item.id]) then
		return item
	end
	return Gear.default(slot)
end

local function owns(data: DataService.Data, item: Gear.Item): boolean
	return item.price == 0 or data.owned[item.id] == true
end

local GEAR_PART = "AscentGear"

local function dress(player: Player)
	local character = player.Character
	local data = DataService.Get(player)
	if character == nil or data == nil then
		return
	end
	local old = character:FindFirstChild(GEAR_PART)
	if old then
		old:Destroy()
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local hips = character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso")
	if torso == nil or not torso:IsA("BasePart") or hips == nil or not hips:IsA("BasePart") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = GEAR_PART
	local pack = GearModels.pack(equippedItem(data, "Pack").id, Gear.color(data.packColor))
	-- Behind the upper back (the torso's back is +Z).
	GearModels.attach(pack, torso, CFrame.new(0, 0.1, torso.Size.Z / 2 - 0.5))
	pack.Parent = folder
	local chalk = GearModels.chalkBag(Gear.color(data.chalkColor))
	GearModels.attach(chalk, hips, CFrame.new(0.35, -0.1, hips.Size.Z / 2 - 0.25))
	chalk.Parent = folder
	folder.Parent = character
end

-- Publishes what the player owns/equips and the gear stats the other services read.
local function publish(player: Player)
	local data = DataService.Get(player)
	if data == nil then
		return
	end
	local owned = {}
	for _, item in Gear.ITEMS do
		if owns(data, item) then
			table.insert(owned, item.id)
		end
	end
	player:SetAttribute("Owned", table.concat(owned, ","))
	for _, slot in Gear.SLOTS do
		player:SetAttribute(`Equip_{slot}`, equippedItem(data, slot :: Gear.Slot).id)
	end
	player:SetAttribute("PackColor", data.packColor)
	player:SetAttribute("ChalkColor", data.chalkColor)
	local shoes = equippedItem(data, "Shoes").stats
	local chalk = equippedItem(data, "ChalkBag").stats
	local harness = equippedItem(data, "Harness").stats
	local rope = equippedItem(data, "Rope").stats
	player:SetAttribute("GearFootDrain", shoes.footDrain or 1)
	player:SetAttribute("GearChalkRate", chalk.chalkRate)
	player:SetAttribute("GearChalkReduction", chalk.chalkReduction)
	player:SetAttribute("GearDynoCost", harness.dynoCost)
	player:SetAttribute("GearRopeColor", rope.ropeColor)
end

local function reply(player: Player, ok: boolean, message: string)
	resultRemote:FireClient(player, ok, message)
end

local function onRequest(player: Player, action: any, a: any, b: any)
	if not limiter:allow(player) then
		return
	end
	local data = DataService.Get(player)
	if data == nil then
		reply(player, false, "Still loading your profile")
		return
	end
	if action == "Buy" then
		local item = Gear.get(a)
		if item == nil then
			return
		end
		if owns(data, item) then
			reply(player, false, `You already own {item.name}`)
			return
		end
		if data.gems < item.price then
			reply(player, false, `Not enough gems: {item.name} costs {item.price} 💎`)
			return
		end
		DataService.Update(player, function(d)
			d.gems -= item.price
			d.owned[item.id] = true
			d.equipped[item.slot] = item.id
		end)
		publish(player)
		dress(player)
		reply(player, true, `Bought and equipped {item.name}!`)
	elseif action == "Equip" then
		local item = Gear.get(a)
		if item == nil or not owns(data, item) then
			return
		end
		DataService.Update(player, function(d)
			d.equipped[item.slot] = item.id
		end)
		publish(player)
		dress(player)
		reply(player, true, `Equipped {item.name}`)
	elseif action == "Colour" and (a == "Pack" or a == "ChalkBag") and type(b) == "number" then
		local index = math.floor(b)
		if index < 1 or index > #Gear.COLORS then
			return
		end
		DataService.Update(player, function(d)
			if a == "Pack" then
				d.packColor = index
			else
				d.chalkColor = index
			end
		end)
		publish(player)
		dress(player)
	end
end

function ShopService.Init()
	resultRemote = Remotes.event("ShopResult")
	Remotes.event("ShopRequest").OnServerEvent:Connect(onRequest)
end

function ShopService.Start()
	DataService.OnLoaded(function(player)
		publish(player)
		dress(player)
	end)
	local function watch(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			dress(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
	end)
end

return ShopService
