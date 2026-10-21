--!strict
-- ShopService (server): the pro shop and the lockers.
--
--  * Buy gear with gems ("Buy"), equip what you own ("Equip"), and pick your pack and
--    chalk-bag and helmet looks ("Colour"). Everything is checked here and saved by
--    DataService.
--  * Publishes on the Player, for the UI and the other services:
--      Owned        comma-separated item ids you own
--      Equip_<Slot> the item equipped in each slot
--      PackColor, ChalkColor, HelmetColor  look indices (Gear variants)
--      GearFootDrain, GearChalkRate, GearChalkReduction, GearDynoCost, GearRopeColor,
--      GearFallBonus
--  * Dresses every character in its pack, chalk bag and helmet: real catalog accessories
--    (Humanoid:AddAccessory), or GearModels stand-ins when one can't be loaded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Gear)
local GearModels = require(Shared.GearModels)
local RateLimiter = require(Shared.RateLimiter)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

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
local GEAR_ATTRIBUTE = "AscentGear"

-- Catalog accessories, loaded once each (InsertService may load any accessory).
local accessoryTemplates: { [number]: Accessory | false } = {}
local accessoryStore: Folder? = nil

local function loadAccessory(assetId: number): Accessory?
	local cached = accessoryTemplates[assetId]
	if cached == false then
		return nil
	elseif cached then
		return (cached :: any):Clone()
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	local accessory = if ok and result then (result :: Instance):FindFirstChildWhichIsA("Accessory", true) else nil
	if accessory == nil then
		accessoryTemplates[assetId] = false
		warn(`[ShopService] couldn't load accessory {assetId}; using the built-in look`)
		return nil
	end
	for _, d in accessory:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	if accessoryStore == nil then
		local folder = Instance.new("Folder")
		folder.Name = "GearAccessories"
		folder.Parent = ServerStorage
		accessoryStore = folder
	end
	accessory.Parent = accessoryStore
	accessoryTemplates[assetId] = accessory
	return accessory:Clone()
end
ShopService.loadAccessory = loadAccessory

-- Wears catalog accessory `assetId` (replacing the avatar's own accessory of `kind`), or
-- the stand-in from `fallback` welded to `bodyPart` when it can't be loaded.
local function wear(character: Model, humanoid: Humanoid, assetId: number?, kind: Enum.AccessoryType, fallback: (() -> (Model, BasePart?, CFrame))?)
	local accessory = if assetId then loadAccessory(assetId) else nil
	if accessory then
		for _, other in character:GetChildren() do
			if other:IsA("Accessory") and other.AccessoryType == kind and not other:GetAttribute(GEAR_ATTRIBUTE) then
				other:Destroy() -- the avatar's own backpack/belt/hat would clash with the gear
			end
		end
		accessory:SetAttribute(GEAR_ATTRIBUTE, true)
		humanoid:AddAccessory(accessory)
		for _, d in accessory:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
			end
		end
	elseif fallback then
		local model, bodyPart, offset = fallback()
		if bodyPart then
			GearModels.attach(model, bodyPart, offset)
			local folder: Instance? = character:FindFirstChild(GEAR_PART)
			if folder == nil then
				local created = Instance.new("Folder")
				created.Name = GEAR_PART
				created.Parent = character
				folder = created
			end
			model.Parent = folder
		else
			model:Destroy()
		end
	end
end

local function dress(player: Player)
	local character = player.Character
	local data = DataService.Get(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or data == nil or humanoid == nil then
		return
	end
	local old = character:FindFirstChild(GEAR_PART)
	if old then
		old:Destroy()
	end
	for _, other in character:GetChildren() do
		if other:IsA("Accessory") and other:GetAttribute(GEAR_ATTRIBUTE) then
			other:Destroy()
		end
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local hips = character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso")
	local torsoPart = if torso and torso:IsA("BasePart") then torso else nil
	local hipsPart = if hips and hips:IsA("BasePart") then hips else nil

	local pack = equippedItem(data, "Pack")
	local packLook = Gear.variant(pack, data.packColor)
	wear(character, humanoid, if packLook then packLook.asset else nil, Enum.AccessoryType.Back, function()
		-- Behind the upper back (the torso's back is +Z).
		return GearModels.pack(pack.id, if packLook then packLook.color else Gear.color(1)), torsoPart, CFrame.new(0, 0.1, if torsoPart then torsoPart.Size.Z / 2 - 0.5 else 0)
	end)
	local chalk = Gear.chalkBag(data.chalkColor)
	wear(character, humanoid, chalk.asset, Enum.AccessoryType.Waist, function()
		return GearModels.chalkBag(chalk.color), hipsPart, CFrame.new(0.35, -0.1, if hipsPart then hipsPart.Size.Z / 2 - 0.25 else 0)
	end)
	local helmet = equippedItem(data, "Helmet")
	local helmetLook = Gear.variant(helmet, data.helmetColor)
	if helmetLook then
		wear(character, humanoid, helmetLook.asset, Enum.AccessoryType.Hat, nil)
	end
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
	player:SetAttribute("HelmetColor", data.helmetColor)
	player:SetAttribute("GearFallBonus", equippedItem(data, "Helmet").stats.fallBonus or 1)
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
			if item.slot == "Pack" then
				d.packColor = 1
			elseif item.slot == "Helmet" then
				d.helmetColor = 1
			end
		end)
		publish(player)
		dress(player)
		reply(player, true, `Equipped {item.name}`)
	elseif action == "Colour" and (a == "Pack" or a == "ChalkBag" or a == "Helmet") and type(b) == "number" then
		local index = math.floor(b)
		local count = if a == "ChalkBag" then #Gear.CHALK_BAGS else #(equippedItem(data, a :: Gear.Slot).variants or {})
		if index < 1 or index > count then
			return
		end
		DataService.Update(player, function(d)
			if a == "Pack" then
				d.packColor = index
			elseif a == "Helmet" then
				d.helmetColor = index
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

-- Shelves and stands showing real gear (World/Gym gearDisplay): the accessory's handle,
-- anchored, fitted into the stand's size and stood on it.
local function showDisplay(display: Instance)
	local assetId = display:GetAttribute("DisplayAsset")
	local base = display:GetAttribute("Base")
	local fit = display:GetAttribute("FitSize")
	if type(assetId) ~= "number" or typeof(base) ~= "CFrame" or typeof(fit) ~= "Vector3" then
		return
	end
	local accessory = loadAccessory(assetId)
	local handle = accessory and accessory:FindFirstChild("Handle")
	if accessory == nil or handle == nil or not handle:IsA("BasePart") then
		return
	end
	for _, d in handle:GetDescendants() do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Attachment") then
			d:Destroy()
		end
	end
	local size = handle.Size
	local mesh = handle:FindFirstChildOfClass("SpecialMesh")
	local visual = if mesh then size * mesh.Scale else size
	local factor = math.min(fit.X / visual.X, fit.Y / visual.Y, fit.Z / visual.Z)
	if mesh then
		mesh.Scale *= factor
		handle.Size = size * factor
	else
		handle.Size = size * factor
	end
	handle.Anchored = true
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.CFrame = base * CFrame.new(0, visual.Y * factor / 2, 0)
	for _, child in display:GetChildren() do
		child:Destroy()
	end
	handle.Parent = display
	accessory:Destroy()
end

function ShopService.Start()
	task.spawn(function()
		for _, display in CollectionService:GetTagged("GearDisplay") do
			task.spawn(showDisplay, display)
		end
	end)
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
