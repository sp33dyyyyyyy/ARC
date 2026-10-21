--!strict
-- GearUI (client): the pro shop and locker screens. No game logic here: ShopService
-- checks and saves everything; this shows what you own (the Player's Owned / Equip_* /
-- PackColor / ChalkColor attributes) and sends requests.
--   * Pro shop ("Browse gear" at the shop counter): tabs per slot, a card per item with
--     what it does, its price and Buy / Equip / Equipped.
--   * Lockers ("Customise bag"): pick an owned pack, its colour, your chalk bag and your
--     helmet's colour, from catalog pictures of the real items.
-- Both close with the X, Escape, or by walking away.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Gear)
local Remotes = require(Shared.Remotes)

local NAVY = Color3.fromRGB(20, 22, 28)
local CARD = Color3.fromRGB(36, 39, 48)
local ORANGE = Color3.fromRGB(255, 122, 48)
local GREEN = Color3.fromRGB(110, 235, 160)
local GREY = Color3.fromRGB(150, 160, 180)
local CLOSE_DISTANCE = 16

local GearUI = {}

local player = Players.LocalPlayer
local requestRemote: RemoteEvent
local screen: ScreenGui
local shopWindow: Frame
local shopTabs: Frame
local shopList: ScrollingFrame
local shopGems: TextLabel
local shopMessage: TextLabel
local lockerWindow: Frame
local lockerPacks: Frame
local lockerPackLooks: Frame
local lockerChalkLooks: Frame
local lockerHelmetLooks: Frame
local preview: ImageLabel
local previewName: TextLabel
local currentSlot: Gear.Slot = "Shoes"
local openedAt: Vector3?

local function corner(instance: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = instance
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Sarpanch
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function button(parent: Instance, label: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.Font = Enum.Font.Sarpanch
	b.TextSize = 15
	b.TextColor3 = Color3.fromRGB(14, 16, 22)
	b.Text = label
	corner(b, 8)
	b.Parent = parent
	return b
end

local function window(name: string, title: string, size: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = NAVY
	frame.BackgroundTransparency = 0.03
	frame.Visible = false
	corner(frame, 16)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
	stroke.Thickness = 1.5
	stroke.Parent = frame
	-- Shrinks to fit small (phone) screens.
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function fit()
		local camera = workspace.CurrentCamera
		if camera then
			local viewport = camera.ViewportSize
			scale.Scale = math.min(1, (viewport.X - 24) / size.X, (viewport.Y - 24) / size.Y)
		end
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	text(frame, { Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -80, 0, 34), Font = Enum.Font.Michroma, TextSize = 28, TextColor3 = ORANGE, Text = title })
	local close = button(frame, "✕", Color3.fromRGB(200, 206, 218))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(36, 36)
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	frame.Parent = screen
	return frame
end

local function ownedSet(): { [string]: boolean }
	local set = {}
	local owned = player:GetAttribute("Owned")
	if type(owned) == "string" then
		for id in string.gmatch(owned, "[^,]+") do
			set[id] = true
		end
	end
	return set
end

local function gems(): number
	local value = player:GetAttribute("Gems")
	return if type(value) == "number" then value else 0
end

-- A catalog picture of asset `assetId`.
local function thumbnail(parent: Instance, assetId: number, position: UDim2, size: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Position = position
	image.Size = UDim2.fromOffset(size, size)
	image.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	image.Image = `rbxthumb://type=Asset&id={assetId}&w=150&h=150`
	image.ScaleType = Enum.ScaleType.Fit
	corner(image, 8)
	image.Parent = parent
	return image
end

---------------------------------------------------------------------------------------
-- Pro shop

function GearUI.refreshShop()
	shopGems.Text = `💎 {gems()}`
	for _, child in shopTabs:GetChildren() do
		if child:IsA("TextButton") then
			child.BackgroundColor3 = if child.Name == currentSlot then ORANGE else CARD
			child.TextColor3 = if child.Name == currentSlot then Color3.fromRGB(14, 16, 22) else Color3.new(1, 1, 1)
		end
	end
	for _, child in shopList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local owned = ownedSet()
	local equipped = player:GetAttribute(`Equip_{currentSlot}`)
	for index, item in Gear.inSlot(currentSlot) do
		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.Size = UDim2.new(1, -8, 0, 76)
		card.BackgroundColor3 = CARD
		corner(card, 10)
		card.Parent = shopList
		-- Items that are real catalog accessories show their picture.
		local look = Gear.variant(item, 1)
		local left = 14
		if look then
			thumbnail(card, look.asset, UDim2.fromOffset(8, 6), 64)
			left = 80
		end
		text(card, { Position = UDim2.fromOffset(left, 8), Size = UDim2.new(1, -156 - left, 0, 22), TextSize = 18, Text = item.name })
		text(card, { Position = UDim2.fromOffset(left, 30), Size = UDim2.new(1, -156 - left, 0, 18), Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = GREY, TextTruncate = Enum.TextTruncate.AtEnd, Text = item.description })
		text(card, { Position = UDim2.fromOffset(left, 50), Size = UDim2.new(1, -156 - left, 0, 18), Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = GREEN, Text = Gear.describeStats(item) })
		local action: TextButton
		if equipped == item.id then
			action = button(card, "Equipped", Color3.fromRGB(80, 86, 100))
			action.AutoButtonColor = false
			action.TextColor3 = Color3.new(1, 1, 1)
		elseif owned[item.id] then
			action = button(card, "Equip", GREEN)
			action.Activated:Connect(function()
				requestRemote:FireServer("Equip", item.id)
			end)
		else
			local affordable = gems() >= item.price
			action = button(card, `Buy  💎 {item.price}`, if affordable then ORANGE else Color3.fromRGB(90, 70, 60))
			action.Activated:Connect(function()
				requestRemote:FireServer("Buy", item.id)
			end)
		end
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, -12, 0.5, 0)
		action.Size = UDim2.fromOffset(140, 40)
	end
end

local function buildShop()
	shopWindow = window("ProShop", "PRO SHOP", Vector2.new(560, 480))
	shopGems = text(shopWindow, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -64, 0, 20), Size = UDim2.fromOffset(140, 26), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(120, 230, 255), TextSize = 20 })
	shopTabs = Instance.new("Frame")
	shopTabs.BackgroundTransparency = 1
	shopTabs.Position = UDim2.fromOffset(16, 60)
	shopTabs.Size = UDim2.new(1, -32, 0, 36)
	shopTabs.Parent = shopWindow
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = shopTabs
	for _, slot in Gear.SLOTS do
		local tab = button(shopTabs, Gear.SLOT_NAMES[slot], CARD)
		tab.Name = slot
		tab.Size = UDim2.new(1 / #Gear.SLOTS, -7, 1, 0)
		tab.Activated:Connect(function()
			currentSlot = slot :: Gear.Slot
			GearUI.refreshShop()
		end)
	end
	shopList = Instance.new("ScrollingFrame")
	shopList.Position = UDim2.fromOffset(16, 106)
	shopList.Size = UDim2.new(1, -32, 1, -150)
	shopList.BackgroundTransparency = 1
	shopList.BorderSizePixel = 0
	shopList.ScrollBarThickness = 6
	shopList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	shopList.CanvasSize = UDim2.new()
	shopList.Parent = shopWindow
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = shopList
	shopMessage = text(shopWindow, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -12), Size = UDim2.new(1, -40, 0, 24), TextColor3 = GREY, Font = Enum.Font.GothamMedium, TextSize = 15, Text = "Earn gems by topping out routes. Better gear makes you last longer." })
end

---------------------------------------------------------------------------------------
-- Lockers

-- A tile showing look `variant` (its catalog picture), outlined when it's the one worn.
local function lookTile(parent: Instance, variant: Gear.Variant, selected: boolean, onPick: () -> ())
	local tile = Instance.new("ImageButton")
	tile.Size = UDim2.fromOffset(52, 52)
	tile.BackgroundColor3 = CARD
	tile.Image = `rbxthumb://type=Asset&id={variant.asset}&w=150&h=150`
	tile.ScaleType = Enum.ScaleType.Fit
	corner(tile, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = if selected then ORANGE else variant.color
	stroke.Thickness = if selected then 3 else 1
	stroke.Parent = tile
	tile.Activated:Connect(onPick)
	tile.Parent = parent
end

local function clearTiles(row: Instance)
	for _, child in row:GetChildren() do
		if child:IsA("GuiButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

function GearUI.refreshLocker()
	clearTiles(lockerPacks)
	local owned = ownedSet()
	local equippedPack = Gear.get(player:GetAttribute("Equip_Pack")) or Gear.default("Pack")
	for _, item in Gear.inSlot("Pack") do
		local mine = owned[item.id] == true
		local worn = equippedPack.id == item.id
		local pick = button(lockerPacks, if mine then item.name else `{item.name} (shop)`, if worn then ORANGE elseif mine then CARD else Color3.fromRGB(28, 30, 36))
		pick.TextColor3 = if worn then Color3.fromRGB(14, 16, 22) else (if mine then Color3.new(1, 1, 1) else GREY)
		pick.TextSize = 13
		pick.Activated:Connect(function()
			if mine then
				requestRemote:FireServer("Equip", item.id)
			end
		end)
	end
	clearTiles(lockerPackLooks)
	local packIndex = player:GetAttribute("PackColor")
	local packLooks: { Gear.Variant } = equippedPack.variants or {}
	for index, variant in packLooks do
		lookTile(lockerPackLooks, variant, packIndex == index, function()
			requestRemote:FireServer("Colour", "Pack", index)
		end)
	end
	clearTiles(lockerChalkLooks)
	local chalkIndex = player:GetAttribute("ChalkColor")
	for index, variant in Gear.CHALK_BAGS do
		lookTile(lockerChalkLooks, variant, chalkIndex == index, function()
			requestRemote:FireServer("Colour", "ChalkBag", index)
		end)
	end
	clearTiles(lockerHelmetLooks)
	local helmet = Gear.get(player:GetAttribute("Equip_Helmet")) or Gear.default("Helmet")
	local helmetIndex = player:GetAttribute("HelmetColor")
	if helmet.variants then
		for index, variant in helmet.variants do
			lookTile(lockerHelmetLooks, variant, helmetIndex == index, function()
				requestRemote:FireServer("Colour", "Helmet", index)
			end)
		end
	else
		text(lockerHelmetLooks, { Size = UDim2.new(1, 0, 0, 40), Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = GREY, TextWrapped = true, Text = "No helmet yet: they're at the pro shop." })
	end
	-- The big picture: the pack you're wearing.
	local look = Gear.variant(equippedPack, packIndex)
	preview.Image = if look then `rbxthumb://type=Asset&id={look.asset}&w=420&h=420` else ""
	previewName.Text = if look then `{equippedPack.name} · {look.name}` else equippedPack.name
end

local function tileRow(parent: Instance, y: number, title: string, height: number): Frame
	text(parent, { Position = UDim2.fromOffset(270, y), Size = UDim2.fromOffset(310, 18), TextColor3 = GREY, TextSize = 14, Text = title })
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(270, y + 22)
	row.Size = UDim2.fromOffset(316, height)
	row.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(52, 52)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = row
	return row
end

local function buildLocker()
	lockerWindow = window("Locker", "YOUR KIT", Vector2.new(600, 470))
	preview = Instance.new("ImageLabel")
	preview.Position = UDim2.fromOffset(20, 64)
	preview.Size = UDim2.fromOffset(230, 230)
	preview.BackgroundColor3 = CARD
	preview.ScaleType = Enum.ScaleType.Fit
	corner(preview, 12)
	preview.Parent = lockerWindow
	previewName = text(lockerWindow, { Position = UDim2.fromOffset(20, 298), Size = UDim2.fromOffset(230, 20), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
	text(lockerWindow, { Position = UDim2.fromOffset(20, 324), Size = UDim2.fromOffset(230, 18), TextColor3 = GREY, TextSize = 14, Text = "PACK" })
	lockerPacks = Instance.new("Frame")
	lockerPacks.BackgroundTransparency = 1
	lockerPacks.Position = UDim2.fromOffset(20, 346)
	lockerPacks.Size = UDim2.fromOffset(230, 110)
	lockerPacks.Parent = lockerWindow
	local packGrid = Instance.new("UIGridLayout")
	packGrid.CellSize = UDim2.new(0.5, -4, 0, 30)
	packGrid.CellPadding = UDim2.fromOffset(6, 6)
	packGrid.Parent = lockerPacks
	lockerPackLooks = tileRow(lockerWindow, 64, "PACK COLOUR", 60)
	lockerChalkLooks = tileRow(lockerWindow, 150, "CHALK BAG", 116)
	lockerHelmetLooks = tileRow(lockerWindow, 294, "HELMET", 60)
	text(lockerWindow, { Position = UDim2.fromOffset(270, 384), Size = UDim2.fromOffset(310, 60), TextColor3 = GREY, Font = Enum.Font.GothamMedium, TextSize = 14, TextWrapped = true, Text = "Looks are free. New packs, helmets, shoes and other gear are at the pro shop." })
end

---------------------------------------------------------------------------------------

local function open(which: Frame)
	shopWindow.Visible = which == shopWindow
	lockerWindow.Visible = which == lockerWindow
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	openedAt = if root and root:IsA("BasePart") then root.Position else nil
	if which == shopWindow then
		GearUI.refreshShop()
	else
		GearUI.refreshLocker()
	end
end

function GearUI.Init()
	screen = Instance.new("ScreenGui")
	screen.Name = "GearUI"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	buildShop()
	buildLocker()
end

function GearUI.Start()
	requestRemote = Remotes.event("ShopRequest")
	Remotes.event("ShopResult").OnClientEvent:Connect(function(ok, message)
		if type(message) == "string" then
			shopMessage.Text = message
			shopMessage.TextColor3 = if ok then GREEN else Color3.fromRGB(255, 150, 120)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player then
			return
		end
		if prompt.Name == "OpenShop" then
			open(shopWindow)
		elseif prompt.Name == "OpenLocker" then
			open(lockerWindow)
		end
	end)
	for _, name in { "Gems", "Owned", "Equip_Shoes", "Equip_ChalkBag", "Equip_Harness", "Equip_Helmet", "Equip_Pack", "Equip_Rope", "PackColor", "ChalkColor", "HelmetColor" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if shopWindow.Visible then
				GearUI.refreshShop()
			end
			if lockerWindow.Visible then
				GearUI.refreshLocker()
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			shopWindow.Visible = false
			lockerWindow.Visible = false
		end
	end)
	-- Walking away closes the windows.
	RunService.Heartbeat:Connect(function()
		if openedAt and (shopWindow.Visible or lockerWindow.Visible) then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - openedAt).Magnitude > CLOSE_DISTANCE then
				shopWindow.Visible = false
				lockerWindow.Visible = false
			end
		end
	end)
end

return GearUI
