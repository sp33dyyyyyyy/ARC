--!strict
-- GearUI (client): the pro shop and locker screens. No game logic here: ShopService
-- checks and saves everything; this shows what you own (the Player's Owned / Equip_* /
-- PackColor / ChalkColor attributes) and sends requests.
--   * Pro shop ("Browse gear" at the shop counter): tabs per slot, a card per item with
--     what it does, its price and Buy / Equip / Equipped.
--   * Lockers ("Customise bag"): pick an owned pack and the pack and chalk-bag colours,
--     with a turning 3D preview.
-- Both close with the X, Escape, or by walking away.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Gear)
local GearModels = require(Shared.GearModels)
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
local lockerPackColors: Frame
local lockerChalkColors: Frame
local preview: ViewportFrame
local previewModel: Model?
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
	label.Font = Enum.Font.GothamBold
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
	b.Font = Enum.Font.GothamBold
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
	text(frame, { Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -80, 0, 34), Font = Enum.Font.GothamBlack, TextSize = 28, TextColor3 = ORANGE, Text = title })
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
		text(card, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -170, 0, 22), TextSize = 18, Text = item.name })
		text(card, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -170, 0, 18), Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = GREY, TextTruncate = Enum.TextTruncate.AtEnd, Text = item.description })
		text(card, { Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -170, 0, 18), Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = GREEN, Text = Gear.describeStats(item) })
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
		tab.Size = UDim2.new(0.2, -7, 1, 0)
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

local function updatePreview()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	local packId = player:GetAttribute("Equip_Pack")
	local model = GearModels.pack(if type(packId) == "string" then packId else "DayPack", Gear.color(player:GetAttribute("PackColor")))
	local chalk = GearModels.chalkBag(Gear.color(player:GetAttribute("ChalkColor")))
	chalk:PivotTo(CFrame.new(0.9, -1.1, 0.4))
	for _, d in chalk:GetChildren() do
		d.Parent = model
	end
	chalk:Destroy()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model.Parent = preview
	previewModel = model
end

local function swatches(parent: Frame, slot: string, selected: any)
	for _, child in parent:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for index, color in Gear.COLORS do
		local swatch = Instance.new("TextButton")
		swatch.Text = ""
		swatch.Size = UDim2.fromOffset(30, 30)
		swatch.BackgroundColor3 = color
		corner(swatch, 15)
		if selected == index then
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.new(1, 1, 1)
			stroke.Thickness = 3
			stroke.Parent = swatch
		end
		swatch.Activated:Connect(function()
			requestRemote:FireServer("Colour", slot, index)
		end)
		swatch.Parent = parent
	end
end

function GearUI.refreshLocker()
	for _, child in lockerPacks:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local owned = ownedSet()
	local equipped = player:GetAttribute("Equip_Pack")
	for _, item in Gear.inSlot("Pack") do
		local mine = owned[item.id] == true
		local pick = button(lockerPacks, if mine then item.name else `{item.name} (shop)`, if equipped == item.id then ORANGE elseif mine then CARD else Color3.fromRGB(28, 30, 36))
		pick.TextColor3 = if equipped == item.id then Color3.fromRGB(14, 16, 22) else (if mine then Color3.new(1, 1, 1) else GREY)
		pick.Size = UDim2.new(1, 0, 0, 34)
		pick.Activated:Connect(function()
			if mine then
				requestRemote:FireServer("Equip", item.id)
			end
		end)
	end
	swatches(lockerPackColors, "Pack", player:GetAttribute("PackColor"))
	swatches(lockerChalkColors, "ChalkBag", player:GetAttribute("ChalkColor"))
	updatePreview()
end

local function swatchRow(parent: Instance, y: number, title: string): Frame
	text(parent, { Position = UDim2.fromOffset(250, y), Size = UDim2.fromOffset(280, 20), TextColor3 = GREY, TextSize = 14, Text = title })
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(250, y + 24)
	row.Size = UDim2.fromOffset(290, 70)
	row.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(30, 30)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.Parent = row
	return row
end

local function buildLocker()
	lockerWindow = window("Locker", "YOUR BAG", Vector2.new(560, 420))
	preview = Instance.new("ViewportFrame")
	preview.Position = UDim2.fromOffset(20, 64)
	preview.Size = UDim2.fromOffset(210, 220)
	preview.BackgroundColor3 = CARD
	preview.Ambient = Color3.fromRGB(150, 150, 160)
	preview.LightColor = Color3.fromRGB(255, 250, 240)
	preview.LightDirection = Vector3.new(-1, -1, -1)
	corner(preview, 12)
	preview.Parent = lockerWindow
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = preview
	preview.CurrentCamera = camera
	local angle = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if lockerWindow.Visible then
			angle += dt * 0.8
			local eye = Vector3.new(math.sin(angle) * 6.5, 1.2, math.cos(angle) * 6.5) + Vector3.new(0, 0, 0.6)
			camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, -0.2, 0.6))
		end
	end)
	text(lockerWindow, { Position = UDim2.fromOffset(20, 294), Size = UDim2.fromOffset(210, 20), TextColor3 = GREY, TextSize = 14, Text = "PACK" })
	lockerPacks = Instance.new("Frame")
	lockerPacks.BackgroundTransparency = 1
	lockerPacks.Position = UDim2.fromOffset(20, 316)
	lockerPacks.Size = UDim2.fromOffset(210, 90)
	lockerPacks.Parent = lockerWindow
	local packGrid = Instance.new("UIGridLayout")
	packGrid.CellSize = UDim2.new(0.5, -4, 0, 38)
	packGrid.CellPadding = UDim2.fromOffset(6, 6)
	packGrid.Parent = lockerPacks
	lockerPackColors = swatchRow(lockerWindow, 70, "PACK COLOUR")
	lockerChalkColors = swatchRow(lockerWindow, 180, "CHALK BAG COLOUR")
	text(lockerWindow, { Position = UDim2.fromOffset(250, 294), Size = UDim2.fromOffset(290, 60), TextColor3 = GREY, Font = Enum.Font.GothamMedium, TextSize = 14, TextWrapped = true, Text = "Colours are free. Buy new packs, shoes and other gear at the pro shop." })
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
	for _, name in { "Gems", "Owned", "Equip_Shoes", "Equip_ChalkBag", "Equip_Harness", "Equip_Pack", "Equip_Rope", "PackColor", "ChalkColor" } do
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
