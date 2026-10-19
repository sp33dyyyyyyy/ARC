--[[
	PhoneUI  (LocalScript, StarterPlayerScripts/UI)

	The in-game phone. Tap the phone button on the right edge (or press P).

	  Parts     order aftermarket parts for one of your bikes
	  Orders    what is on its way (with a countdown) and what is waiting in
	            your garage
	  Garage    walk home / bring your bikes to your garage door

	Display only: the server decides prices, stock and delivery. Delivered
	parts arrive in a crate in YOUR garage - click the crate, then put the bike
	on the stand to fit the part (see WorkshopUI).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PartsData = require(Shared:WaitForChild("PartsData"))
local VehicleData = require(Shared:WaitForChild("VehicleData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local T = UIKit.theme
local make, label, button = UIKit.make, UIKit.label, UIKit.button

local gui = UIKit.screenGui("Phone", 6)

local state = {
	open = false,
	page = "home",
	bike = nil :: string?,
	orders = {} :: { any },
	ordersAt = os.clock(),
	data = ClientState.data :: any,
	busy = false,
}

local function toast(text: string)
	ClientState.toast = text
end

----------------------------------------------------------------------------
-- Phone button (right edge)
----------------------------------------------------------------------------
local phoneButton = button({
	Parent = gui, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 20),
	Size = UDim2.fromOffset(52, 78), Text = "", BackgroundColor3 = Color3.fromRGB(18, 20, 26),
})
UIKit.corner(12).Parent = phoneButton
make("UIStroke", { Parent = phoneButton, Color = T.accent, Thickness = 2 })
make("Frame", {
	Parent = phoneButton, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.new(1, -12, 1, -26), BackgroundColor3 = Color3.fromRGB(38, 60, 96),
}, { UIKit.corner(6) })
label({
	Parent = phoneButton, Position = UDim2.fromScale(0, 0.28), Size = UDim2.fromScale(1, 0.3),
	Text = "PHONE", TextSize = 11, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center,
})
local badge = label({
	Parent = phoneButton, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6),
	Size = UDim2.fromOffset(22, 22), Text = "", TextSize = 13, Font = Enum.Font.GothamBlack,
	BackgroundTransparency = 0, BackgroundColor3 = T.warn, TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
}, nil)
UIKit.corner(11).Parent = badge

----------------------------------------------------------------------------
-- The phone itself
----------------------------------------------------------------------------
local phone = make("Frame", {
	Parent = gui, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -78, 0.5, 0),
	Size = UDim2.new(0, 310, 0.88, 0), BackgroundColor3 = Color3.fromRGB(14, 15, 19), Visible = false,
}, {
	UIKit.corner(34),
	make("UISizeConstraint", { MinSize = Vector2.new(270, 420), MaxSize = Vector2.new(330, 640) }),
	make("UIStroke", { Color = Color3.fromRGB(70, 74, 86), Thickness = 3 }),
})
local screen = make("Frame", {
	Parent = phone, Position = UDim2.fromOffset(9, 9), Size = UDim2.new(1, -18, 1, -18),
	BackgroundColor3 = Color3.fromRGB(20, 26, 40), ClipsDescendants = true,
}, { UIKit.corner(26) })

-- status bar
local statusBar = make("Frame", { Parent = screen, Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(12, 16, 26), BorderSizePixel = 0 })
label({ Parent = statusBar, Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(120, 34), Text = "MopedOS", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = T.muted })
local balance = label({
	Parent = statusBar, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.fromOffset(150, 34),
	Text = "", TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Right,
})
local closeBtn = button({
	Parent = screen, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(90, 8), Text = "", BackgroundColor3 = Color3.fromRGB(150, 154, 166),
})

local content = make("Frame", { Parent = screen, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -56), BackgroundTransparency = 1 })

local pages: { [string]: Frame } = {}
local function newPage(name: string): Frame
	local f = make("Frame", { Parent = content, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, { UIKit.padding(12) })
	pages[name] = f
	return f
end

local function header(parent: Instance, title: string)
	local back = button({ Parent = parent, Size = UDim2.fromOffset(34, 30), Text = "<", TextSize = 18 })
	back.MouseButton1Click:Connect(function()
		state.page = "home"
		for n, p in pairs(pages) do
			p.Visible = n == "home"
		end
	end)
	label({ Parent = parent, Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -44, 0, 30), Text = title, TextSize = 20, Font = Enum.Font.GothamBlack })
end

local function showPage(name: string)
	state.page = name
	for n, p in pairs(pages) do
		p.Visible = n == name
	end
end

----------------------------------------------------------------------------
-- Home
----------------------------------------------------------------------------
local home = newPage("home")
label({ Parent = home, Size = UDim2.new(1, 0, 0, 26), Text = "Apps", TextSize = 16, Font = Enum.Font.GothamBold, TextColor3 = T.muted })
local grid = make("Frame", { Parent = home, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 280), BackgroundTransparency = 1 }, {
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -8, 0, 120), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local ordersBadge
local function appIcon(order: number, title: string, subtitle: string, color: Color3, target: string)
	local b = button({ Parent = grid, LayoutOrder = order, Text = "", BackgroundColor3 = color })
	label({ Parent = b, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 44), Text = string.sub(title, 1, 1), TextSize = 42, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.new(1, 1, 1) })
	label({ Parent = b, Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 20), Text = title, TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center })
	label({ Parent = b, Position = UDim2.fromOffset(0, 91), Size = UDim2.new(1, 0, 0, 16), Text = subtitle, TextSize = 11, TextColor3 = Color3.fromRGB(230, 235, 245), TextXAlignment = Enum.TextXAlignment.Center })
	b.MouseButton1Click:Connect(function()
		showPage(target)
	end)
	return b
end
appIcon(1, "Parts", "Order upgrades", Color3.fromRGB(190, 120, 30), "shop")
local ordersIcon = appIcon(2, "Orders", "Track deliveries", Color3.fromRGB(46, 100, 170), "orders")
appIcon(3, "Garage", "Go home", Color3.fromRGB(46, 130, 80), "garage")
ordersBadge = label({
	Parent = ordersIcon, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(24, 24),
	Text = "0", TextSize = 14, Font = Enum.Font.GothamBlack, BackgroundTransparency = 0, BackgroundColor3 = T.warn,
	TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
})
UIKit.corner(12).Parent = ordersBadge

----------------------------------------------------------------------------
-- Parts shop
----------------------------------------------------------------------------
local shop = newPage("shop")
header(shop, "Parts shop")
local bikeRow = make("ScrollingFrame", {
	Parent = shop, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
}, { make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
local shopHint = label({ Parent = shop, Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 30), Text = "", TextSize = 12, TextColor3 = T.muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
local partList = make("ScrollingFrame", {
	Parent = shop, Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 1, -110), BackgroundTransparency = 1,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
}, { make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

local function myBikes(): { any }
	local list = {}
	for _, v in ipairs(VehicleData.list) do
		if GameConfig.TestFleet or (state.data and state.data.owned and state.data.owned[v.id]) then
			table.insert(list, v)
		end
	end
	return list
end

local function partState(partId: string, vehicle)
	local profile = state.data
	local e = profile and profile.parts and profile.parts[vehicle.id]
	local part = PartsData.byId[partId]
	if e and e.installed and e.installed[part.slot] == partId then
		return "fitted"
	elseif e and e.owned and e.owned[partId] then
		return "inventory"
	end
	for _, o in ipairs(state.orders) do
		if o.partId == partId and o.bikeId == vehicle.id then
			return o.arrived and "waiting" or "ordered"
		end
	end
	return "shop"
end

local function order(partId: string, bikeId: string)
	if state.busy then
		return
	end
	state.busy = true
	task.spawn(function()
		local ok, res = pcall(function()
			return Remotes.func("PartsOrder"):InvokeServer(partId, bikeId)
		end)
		state.busy = false
		if ok and res and not res.ok then
			toast(res.reason or "Order failed")
		end
		if not ok then
			toast("Could not reach the shop")
		end
	end)
end

local refreshShop
function refreshShop()
	for _, c in ipairs(bikeRow:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	for _, c in ipairs(partList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local bikes = myBikes()
	if #bikes == 0 then
		shopHint.Text = "You don't own a bike yet."
		return
	end
	if not state.bike or not VehicleData.byId[state.bike] then
		state.bike = bikes[1].id
	end
	for i, v in ipairs(bikes) do
		local selected = v.id == state.bike
		local b = button({
			Parent = bikeRow, LayoutOrder = i, Size = UDim2.fromOffset(104, 34), Text = v.displayName, TextSize = 13,
			BackgroundColor3 = selected and T.accent or T.panelLight, TextColor3 = selected and Color3.new(0.1, 0.1, 0.1) or T.text,
		})
		b.MouseButton1Click:Connect(function()
			state.bike = v.id
			refreshShop()
		end)
	end
	local vehicle = VehicleData.byId[state.bike]
	shopHint.Text = ("Parts for the %s. Delivery to your garage takes about %d s."):format(vehicle.displayName, GameConfig.Garage.DeliverySeconds)

	for i, part in ipairs(PartsData.list) do
		local fits, why = PartsData.fits(part, vehicle)
		local st = partState(part.id, vehicle)
		local price = PartsData.price(part, vehicle)
		local row = make("Frame", { Parent = partList, LayoutOrder = i, Size = UDim2.new(1, -6, 0, 86), BackgroundColor3 = T.panel }, { UIKit.corner(10) })
		label({ Parent = row, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -96, 0, 18), Text = part.name, TextSize = 14, Font = Enum.Font.GothamBold })
		label({ Parent = row, Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -96, 0, 14), Text = PartsData.slotName[part.slot], TextSize = 11, TextColor3 = T.accent })
		label({
			Parent = row, Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -96, 0, 42), TextSize = 11, TextColor3 = T.muted,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
			Text = fits and (part.desc .. "\n" .. PartsData.describe(part)) or ("Doesn't fit: " .. why),
		})
		local btn = button({ Parent = row, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(78, 40), TextSize = 13 })
		if not fits then
			btn.Text, btn.BackgroundColor3, btn.AutoButtonColor = "N/A", T.bg, false
		elseif st == "fitted" then
			btn.Text, btn.BackgroundColor3, btn.AutoButtonColor = "Fitted", Color3.fromRGB(46, 110, 70), false
		elseif st == "inventory" then
			btn.Text, btn.BackgroundColor3, btn.AutoButtonColor = "In garage", Color3.fromRGB(46, 110, 70), false
		elseif st == "waiting" then
			btn.Text, btn.BackgroundColor3, btn.AutoButtonColor = "Delivered", Color3.fromRGB(46, 110, 70), false
		elseif st == "ordered" then
			btn.Text, btn.BackgroundColor3, btn.AutoButtonColor = "On order", T.bg, false
		else
			btn.Text = ("ORDER\nEUR %d"):format(price)
			local money = state.data and state.data.money or 0
			btn.BackgroundColor3 = money >= price and Color3.fromRGB(190, 120, 30) or Color3.fromRGB(110, 60, 56)
			btn.MouseButton1Click:Connect(function()
				order(part.id, vehicle.id)
			end)
		end
	end
end

----------------------------------------------------------------------------
-- Orders
----------------------------------------------------------------------------
local ordersPage = newPage("orders")
header(ordersPage, "Orders")
local orderList = make("ScrollingFrame", {
	Parent = ordersPage, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
}, { make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
local emptyOrders = label({ Parent = ordersPage, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 40), Text = "No parcels. Order something in Parts.", TextSize = 13, TextColor3 = T.muted, TextWrapped = true })

local orderRows: { [string]: TextLabel } = {}
local function refreshOrders()
	for _, c in ipairs(orderList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	table.clear(orderRows)
	emptyOrders.Visible = #state.orders == 0
	local waiting = 0
	for i, o in ipairs(state.orders) do
		if o.arrived then
			waiting += 1
		end
		local part = PartsData.byId[o.partId]
		local bike = VehicleData.byId[o.bikeId]
		local row = make("Frame", { Parent = orderList, LayoutOrder = i, Size = UDim2.new(1, -6, 0, 62), BackgroundColor3 = T.panel }, { UIKit.corner(10) })
		label({ Parent = row, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), Text = part and part.name or o.partId, TextSize = 14, Font = Enum.Font.GothamBold })
		label({ Parent = row, Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 0, 14), Text = "for " .. (bike and bike.displayName or o.bikeId), TextSize = 11, TextColor3 = T.muted })
		orderRows[o.id] = label({ Parent = row, Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 0, 16), Text = "", TextSize = 12, Font = Enum.Font.GothamBold })
	end
	badge.Visible = waiting > 0
	badge.Text = tostring(waiting)
	ordersBadge.Visible = #state.orders > 0
	ordersBadge.Text = tostring(#state.orders)
end

local function tickOrders()
	local elapsed = os.clock() - state.ordersAt
	for _, o in ipairs(state.orders) do
		local l = orderRows[o.id]
		if l then
			if o.arrived then
				l.Text, l.TextColor3 = "Waiting in your garage - click the crate", T.good
			else
				local left = math.max(0, math.ceil(o.remaining - elapsed))
				l.Text = left > 0 and ("On its way: %d:%02d"):format(left // 60, left % 60) or "Van is arriving..."
				l.TextColor3 = T.info
			end
		end
	end
end

----------------------------------------------------------------------------
-- Garage
----------------------------------------------------------------------------
local garagePage = newPage("garage")
header(garagePage, "My garage")
label({
	Parent = garagePage, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 90), TextSize = 13, TextColor3 = T.muted, TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "Your garage is in the row south of the village (follow the green sign). Its door opens when you come near. Click the crates to unpack parts, click the stand to lift a bike and fit them.",
})
local function garageButton(y: number, text: string, kind: string)
	local b = button({ Parent = garagePage, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 46), Text = text, TextSize = 15, BackgroundColor3 = Color3.fromRGB(46, 130, 80) })
	b.MouseButton1Click:Connect(function()
		task.spawn(function()
			local ok, res = pcall(function()
				return Remotes.func("GarageTeleport"):InvokeServer(kind)
			end)
			if ok and res and not res.ok then
				toast(res.reason or "Not possible right now")
			end
		end)
	end)
end
garageButton(142, "Take me to my garage", "go")
garageButton(198, "Bring my bikes to my garage", "bikes")

----------------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------------
local function refreshMoney()
	local m = state.data and state.data.money
	balance.Text = m and ("EUR %d"):format(m) or ""
end

local function setOpen(open: boolean)
	state.open = open
	phone.Visible = open
	if open then
		showPage("home")
		refreshMoney()
		refreshShop()
		refreshOrders()
	end
end

phoneButton.MouseButton1Click:Connect(function()
	setOpen(not state.open)
end)
closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.P then
		setOpen(not state.open)
	end
end)

Remotes.event("DataChanged").OnClientEvent:Connect(function(view)
	state.data = view
	refreshMoney()
	if state.open then
		refreshShop()
	end
end)
Remotes.event("OrdersChanged").OnClientEvent:Connect(function(list)
	state.orders = list
	state.ordersAt = os.clock()
	refreshOrders()
	if state.open then
		refreshShop()
	end
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc >= 0.5 then
		acc = 0
		if state.open then
			tickOrders()
		end
	end
end)

-- ask for the current orders (the server may have sent them before we existed)
Remotes.event("OrdersChanged"):FireServer()
refreshMoney()
