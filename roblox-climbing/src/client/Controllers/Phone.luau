--!strict
-- Phone (client): the in-game phone. P (or the button bottom left) takes it out; M opens
-- it straight on Routes; Esc puts it away.
--   Controls  every key and how climbing, ropes and finishing work
--   Routes    every route, your best time, Go to travel to its base
--   Stats     money, level, summits, metres climbed, best times
--   Settings  hints, stamina bar, run timer (ClientSettings)

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))
local Style = require(script.Parent:WaitForChild("Style"))

local C = Style.Colors
local F = Style.Fonts
local PHONE_KEY = Enum.KeyCode.P
local ROUTES_KEY = Enum.KeyCode.M
local WIDTH, HEIGHT = 290, 560
local MIN_HEIGHT = 440 -- on short screens the phone gets shorter (pages scroll) before it shrinks
local homeFooter: TextLabel? = nil -- the home screen hint (hidden on a short phone)

local Phone = {}

local player = Players.LocalPlayer
local requestRemote: RemoteEvent
local screen: ScreenGui
local body: Frame
local display: Frame
local clock: TextLabel
local title: TextLabel
local back: TextButton
local pages: { [string]: Frame } = {}
local refreshers: { [string]: () -> () } = {}
local current = "Home"
local open = false

---------------------------------------------------------------------------------------
-- Pieces

local function page(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromOffset(0, 62)
	frame.Size = UDim2.new(1, 0, 1, -84)
	frame.Visible = false
	frame.Parent = display
	pages[name] = frame
	return frame
end

local function scroller(parent: Instance): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(14, 0)
	list.Size = UDim2.new(1, -20, 1, 0)
	list.ScrollBarThickness = 3
	list.ScrollBarImageColor3 = C.Line
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function heading(list: Instance, text: string)
	Style.label(list, { LayoutOrder = nextOrder(), Size = UDim2.new(1, -8, 0, 24), TextSize = 13, TextColor3 = C.Accent, TextYAlignment = Enum.TextYAlignment.Bottom, Text = string.upper(text) })
end

local function clearList(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- App icons, drawn from plain shapes.
local function icon(kind: string, parent: Instance)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 16)
	holder.Size = UDim2.fromOffset(46, 40)
	holder.Parent = parent
	local function block(x: number, y: number, w: number, h: number, color: Color3?)
		local b = Instance.new("Frame")
		b.BackgroundColor3 = color or C.Text
		b.BorderSizePixel = 0
		b.Position = UDim2.fromOffset(x, y)
		b.Size = UDim2.fromOffset(w, h)
		b.Parent = holder
		Style.corner(b, 2)
	end
	if kind == "Controls" then
		for row = 0, 1 do
			for column = 0, 2 do
				block(2 + column * 15, 6 + row * 15, 12, 12, if row == 1 and column == 1 then C.Accent else nil)
			end
		end
	elseif kind == "Routes" then
		local peak = Style.label(holder, { Size = UDim2.fromScale(1, 1), Font = F.Display, TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Text = "▲" })
		peak.TextColor3 = C.Text
		block(30, 6, 3, 10, C.Accent)
		block(33, 6, 7, 5, C.Accent)
	elseif kind == "Stats" then
		block(4, 22, 9, 16)
		block(18, 10, 9, 28, C.Accent)
		block(32, 16, 9, 22)
	else -- Settings
		block(2, 10, 42, 3)
		block(26, 5, 8, 13, C.Accent)
		block(2, 27, 42, 3)
		block(10, 22, 8, 13)
	end
end

---------------------------------------------------------------------------------------
-- Apps

local function showPage(name: string)
	current = name
	for pageName, frame in pages do
		frame.Visible = pageName == name
	end
	title.Text = if name == "Home" then "" else string.upper(name)
	back.Visible = name ~= "Home"
	local refresh = refreshers[name]
	if refresh then
		refresh()
	end
end
Phone.show = showPage

local function buildHome()
	local home = page("Home")
	Style.label(home, { Position = UDim2.fromOffset(20, 4), Size = UDim2.new(1, -40, 0, 34), Font = F.Display, TextSize = 26, Text = string.upper(Config.GameName) })
	local greeting = Style.label(home, { Position = UDim2.fromOffset(20, 40), Size = UDim2.new(1, -40, 0, 18), Font = F.Body, TextSize = 14, TextColor3 = C.Muted })
	refreshers.Home = function()
		greeting.Text = `{player.DisplayName}  ·  {Style.money(player:GetAttribute("Gems"))}`
	end
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(20, 80)
	grid.Size = UDim2.new(1, -40, 0, 250)
	grid.Parent = home
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -6, 0, 112)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for index, app in { "Controls", "Routes", "Stats", "Settings" } do
		local tile = Instance.new("TextButton")
		tile.Name = app
		tile.LayoutOrder = index
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.BackgroundColor3 = C.Raised
		tile.BorderSizePixel = 0
		Style.corner(tile, 6)
		Style.stroke(tile)
		tile.Parent = grid
		icon(app, tile)
		Style.label(tile, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -16, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, Text = string.upper(app) })
		tile.MouseEnter:Connect(function()
			tile.BackgroundColor3 = C.Raised:Lerp(Color3.new(1, 1, 1), 0.06)
		end)
		tile.MouseLeave:Connect(function()
			tile.BackgroundColor3 = C.Raised
		end)
		tile.Activated:Connect(function()
			showPage(app)
		end)
	end
	local footer = Style.label(home, { Position = UDim2.new(0, 20, 1, -40), Size = UDim2.new(1, -40, 0, 30), Font = F.Body, TextSize = 13, TextColor3 = C.Faint, TextWrapped = true, Text = "P puts the phone away.  M opens Routes." })
	footer.Visible = body.Size.Y.Offset >= 520
	homeFooter = footer
end

local CONTROLS: { { string } } = {
	{ "#", "Climbing" },
	{ "CLICK", "Click a hold to grab it with the nearest limb" },
	{ "DRAG", "Drag a hand or foot onto a hold" },
	{ "Q E Z C", "Pick a limb (left hand, right hand, left foot, right foot)" },
	{ "W A S D", "Shift your weight. It stays where you leave it" },
	{ "X", "Centre your weight again" },
	{ "SPACE", "Hold to charge a dyno, aim, let go to jump" },
	{ "V", "Let go of the wall" },
	{ "F", "Climb up onto a ledge or the top" },
	{ "G", "Chalk up from your chalk bag" },
	{ "#", "Ropes" },
	{ "1", "Outside: drop your rope bag at a route's base, then click it to tie in" },
	{ "CLICK", "Indoors: click an orange auto-belay carabiner to clip in. Click again to unclip" },
	{ "T / Y", "Take rope in / pay rope out. Hanging: T hauls you up, Y lowers faster" },
	{ "R", "Lower off. Standing on top while roped: back over the edge and rappel" },
	{ "3", "Lead (the Colossus): clip a quickdraw beside your top hand. No gear in, no catch" },
	{ "#", "Your bag" },
	{ "F", "At the lockers: pack your bag (rope, pads, quickdraws, chalk, water)" },
	{ "1 - 5", "Use what you packed: put it down where the preview is green, click" },
	{ "X", "Near something you put down: pack it back up" },
	{ "5", "Drink water for stamina (not mid-climb)" },
	{ "#", "Finishing a route" },
	{ "TOP", "Outside: climb onto the top, walk to the summit button and click it" },
	{ "BTN", "Inside: click the button at the top of the wall" },
	{ "#", "Around" },
	{ "P", "Phone" },
	{ "M", "Routes (travel to any route)" },
	{ "H", "Show what a hold is (inspector)" },
}

local function buildControls()
	local list = scroller(page("Controls"))
	for _, entry in CONTROLS do
		if entry[1] == "#" then
			heading(list, entry[2])
		else
			local row = Instance.new("Frame")
			row.LayoutOrder = nextOrder()
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, -8, 0, 0)
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.Parent = list
			local cap = Style.keycap(row, entry[1], 64)
			cap.Position = UDim2.fromOffset(0, 2)
			Style.label(row, { Position = UDim2.fromOffset(74, 0), Size = UDim2.new(1, -74, 0, 26), AutomaticSize = Enum.AutomaticSize.Y, Font = F.Body, TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = entry[2] })
		end
	end
end

local function sortedRoutes(): { Instance }
	local list = {}
	local routes = Workspace:FindFirstChild("Routes")
	if routes then
		for _, route in routes:GetChildren() do
			if route:GetAttribute("RouteName") ~= nil then
				table.insert(list, route)
			end
		end
	end
	table.sort(list, function(a, b)
		return (tonumber(a:GetAttribute("Order")) or 99) < (tonumber(b:GetAttribute("Order")) or 99)
	end)
	return list
end

local function buildRoutes()
	local list = scroller(page("Routes"))
	refreshers.Routes = function()
		clearList(list)
		local indoor = true
		heading(list, "In the gym")
		for _, route in sortedRoutes() do
			if indoor and route:GetAttribute("Indoor") ~= true then
				indoor = false
				heading(list, "Outside")
			end
			local row = Instance.new("Frame")
			row.LayoutOrder = nextOrder()
			row.Size = UDim2.new(1, -8, 0, 52)
			row.BackgroundColor3 = C.Raised
			row.BorderSizePixel = 0
			Style.corner(row, 3)
			row.Parent = list
			Style.label(row, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -78, 0, 18), TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, Text = `{string.upper(tostring(route:GetAttribute("RouteName")))}  <font color="#FF7A30">{route:GetAttribute("Grade")}</font>` })
			local best = player:GetAttribute(`Best_{route.Name}`)
			local rope = if route:GetAttribute("AutoBelay") == true then "auto-belay" elseif route:GetAttribute("Rope") == true then "rope" else "boulder"
			Style.label(row, { Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -78, 0, 18), Font = F.Body, TextSize = 12, TextColor3 = C.Muted, Text = `{route:GetAttribute("HeightMeters")} m · {rope}` .. (if type(best) == "number" then ` · best {Style.time(best)}` else "") })
			local go = Style.button(row, "Go", "primary")
			go.AnchorPoint = Vector2.new(1, 0.5)
			go.Position = UDim2.new(1, -8, 0.5, 0)
			go.Size = UDim2.fromOffset(54, 32)
			go.Activated:Connect(function()
				requestRemote:FireServer("Travel", route.Name)
				Phone.setOpen(false)
			end)
		end
	end
end

local function buildStats()
	local list = scroller(page("Stats"))
	refreshers.Stats = function()
		clearList(list)
		local function stat(name: string, value: string)
			local row = Instance.new("Frame")
			row.LayoutOrder = nextOrder()
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, -8, 0, 40)
			row.Parent = list
			Style.label(row, { Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = C.Muted, Text = string.upper(name) })
			Style.label(row, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 26), Font = F.Display, TextSize = 19, Text = value })
		end
		stat("Money", Style.money(player:GetAttribute("Gems")))
		local level = player:GetAttribute("Level")
		stat("Level", `{if type(level) == "number" then level else 1}   ({player:GetAttribute("XP") or 0} XP)`)
		stat("Summits", tostring(player:GetAttribute("Summits") or 0))
		local climbed = player:GetAttribute("TotalClimbed")
		stat("Climbed on finished routes", `{if type(climbed) == "number" then climbed else 0} m`)
		heading(list, "Best times")
		local any = false
		for _, route in sortedRoutes() do
			local best = player:GetAttribute(`Best_{route.Name}`)
			if type(best) == "number" then
				any = true
				local row = Instance.new("Frame")
				row.LayoutOrder = nextOrder()
				row.BackgroundTransparency = 1
				row.Size = UDim2.new(1, -8, 0, 22)
				row.Parent = list
				Style.label(row, { Size = UDim2.new(1, -80, 1, 0), Font = F.Body, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, Text = tostring(route:GetAttribute("RouteName")) })
				Style.label(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 80, 1, 0), Font = F.Key, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Good, Text = Style.time(best) })
			end
		end
		if not any then
			Style.label(list, { LayoutOrder = nextOrder(), Size = UDim2.new(1, -8, 0, 22), Font = F.Body, TextSize = 14, TextColor3 = C.Faint, Text = "Top out a route to set a time." })
		end
	end
end

local SETTINGS: { { string } } = {
	{ "Hints", "Climbing hints", "The how-to line at the bottom of the screen" },
	{ "StaminaAlways", "Stamina bar always", "Show it even when you're fresh" },
	{ "RunTimer", "Run timer", "The timer card while you're on a route" },
}

local function buildSettings()
	local list = scroller(page("Settings"))
	for _, entry in SETTINGS do
		local name = entry[1]
		local row = Instance.new("TextButton")
		row.LayoutOrder = nextOrder()
		row.Text = ""
		row.AutoButtonColor = false
		row.BackgroundColor3 = C.Raised
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -8, 0, 64)
		Style.corner(row, 3)
		row.Parent = list
		Style.label(row, { Position = UDim2.fromOffset(10, 7), Size = UDim2.new(1, -70, 0, 18), TextSize = 15, Text = string.upper(entry[2]) })
		Style.label(row, { Position = UDim2.fromOffset(10, 27), Size = UDim2.new(1, -70, 0, 32), Font = F.Body, TextSize = 12, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = entry[3] })
		local switch = Instance.new("Frame")
		switch.AnchorPoint = Vector2.new(1, 0.5)
		switch.Position = UDim2.new(1, -10, 0.5, 0)
		switch.Size = UDim2.fromOffset(38, 20)
		switch.BorderSizePixel = 0
		Style.corner(switch, 10)
		switch.Parent = row
		local knob = Instance.new("Frame")
		knob.Size = UDim2.fromOffset(16, 16)
		knob.BackgroundColor3 = C.Text
		knob.BorderSizePixel = 0
		Style.corner(knob, 8)
		knob.Parent = switch
		local function draw()
			local on = ClientSettings.get(name)
			switch.BackgroundColor3 = if on then C.Accent else C.Line
			knob.Position = UDim2.fromOffset(if on then 20 else 2, 2)
		end
		draw()
		row.Activated:Connect(function()
			ClientSettings.set(name, not ClientSettings.get(name))
			draw()
		end)
	end
end

---------------------------------------------------------------------------------------

function Phone.setOpen(value: boolean, pageName: string?)
	if value then
		showPage(pageName or (if open then current else "Home"))
	end
	if value == open then
		return
	end
	open = value
	if value then
		body.Visible = true
		body.Position = UDim2.new(0, 12, 1, HEIGHT)
		TweenService:Create(body, TweenInfo.new(0.28, Enum.EasingStyle.Quint), { Position = UDim2.new(0, 12, 1, -62) }):Play()
	else
		local tween = TweenService:Create(body, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0, 12, 1, HEIGHT) })
		tween.Completed:Connect(function()
			if not open then
				body.Visible = false
			end
		end)
		tween:Play()
	end
end

function Phone.Init()
	screen = Instance.new("ScreenGui")
	screen.Name = "Phone"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 12
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")

	local toggle = Style.button(screen, "Phone", "ghost")
	toggle.Name = "PhoneButton"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 12, 1, -12)
	toggle.Size = UDim2.fromOffset(120, 38)
	toggle.TextXAlignment = Enum.TextXAlignment.Left
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.Parent = toggle
	local key = Style.keycap(toggle, "P")
	key.AnchorPoint = Vector2.new(1, 0.5)
	key.Position = UDim2.new(1, -8, 0.5, 0)
	toggle.Activated:Connect(function()
		Phone.setOpen(not open)
	end)

	-- The phone: a black body with a rounded screen.
	body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0, 1)
	body.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	body.BackgroundColor3 = Color3.fromRGB(6, 6, 7)
	body.BorderSizePixel = 0
	body.Visible = false
	Style.corner(body, 30)
	Style.stroke(body, C.Line)
	body.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Parent = body
	local function fit()
		local camera = Workspace.CurrentCamera
		if camera then
			-- Fit above the phone button (the money strip hides while the phone is out).
			local inset = GuiService:GetGuiInset()
			local room = camera.ViewportSize.Y - inset.Y - 62 - 12
			local height = math.clamp(room, MIN_HEIGHT, HEIGHT)
			body.Size = UDim2.fromOffset(WIDTH, height)
			if homeFooter then
				homeFooter.Visible = height >= 520 -- on a short phone it would sit on the tiles
			end
			scale.Scale = math.min(1, room / height)
		end
	end
	fit()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	display = Instance.new("Frame")
	display.Name = "Screen"
	display.Position = UDim2.fromOffset(8, 8)
	display.Size = UDim2.new(1, -16, 1, -16)
	display.BackgroundColor3 = C.Panel
	display.BorderSizePixel = 0
	display.ClipsDescendants = true
	Style.corner(display, 23)
	display.Parent = body

	-- Status bar: time, the camera notch, signal.
	clock = Style.label(display, { Position = UDim2.fromOffset(22, 10), Size = UDim2.fromOffset(60, 16), Font = F.Key, TextSize = 13, Text = "" })
	local notch = Instance.new("Frame")
	notch.AnchorPoint = Vector2.new(0.5, 0)
	notch.Position = UDim2.new(0.5, 0, 0, 10)
	notch.Size = UDim2.fromOffset(70, 18)
	notch.BackgroundColor3 = Color3.fromRGB(6, 6, 7)
	notch.BorderSizePixel = 0
	Style.corner(notch, 9)
	notch.Parent = display
	for i = 0, 3 do
		local barPiece = Instance.new("Frame")
		barPiece.AnchorPoint = Vector2.new(0, 1)
		barPiece.Position = UDim2.new(1, -46 + i * 6, 0, 24)
		barPiece.Size = UDim2.fromOffset(4, 4 + i * 3)
		barPiece.BackgroundColor3 = if i < 3 then C.Text else C.Faint
		barPiece.BorderSizePixel = 0
		barPiece.Parent = display
	end

	-- Header for apps: back and the app's name.
	back = Style.button(display, "<", "ghost")
	back.Position = UDim2.fromOffset(14, 32)
	back.Size = UDim2.fromOffset(30, 26)
	back.Visible = false
	back.Activated:Connect(function()
		showPage("Home")
	end)
	title = Style.label(display, { Position = UDim2.fromOffset(52, 32), Size = UDim2.new(1, -70, 0, 26), Font = F.Display, TextSize = 16, Text = "" })
	-- Home indicator.
	local indicator = Instance.new("TextButton")
	indicator.Text = ""
	indicator.AnchorPoint = Vector2.new(0.5, 1)
	indicator.Position = UDim2.new(0.5, 0, 1, -8)
	indicator.Size = UDim2.fromOffset(96, 5)
	indicator.BackgroundColor3 = C.Muted
	indicator.BorderSizePixel = 0
	Style.corner(indicator, 3)
	indicator.Parent = display
	indicator.Activated:Connect(function()
		showPage("Home")
	end)

	buildHome()
	buildControls()
	buildRoutes()
	buildStats()
	buildSettings()
	showPage("Home")
end

function Phone.Start()
	requestRemote = Remotes.event("RouteRequest")
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == PHONE_KEY then
			Phone.setOpen(not open)
		elseif input.KeyCode == ROUTES_KEY then
			if open and current == "Routes" then
				Phone.setOpen(false)
			else
				Phone.setOpen(true, "Routes")
			end
		elseif input.KeyCode == Enum.KeyCode.Escape and open then
			Phone.setOpen(false)
		end
	end)
	local elapsed = 1
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 1 and open then
			elapsed = 0
			clock.Text = os.date("%H:%M") :: string
			if current == "Stats" or current == "Home" then
				local refresh = refreshers[current]
				if refresh then
					refresh()
				end
			end
		end
	end)
end

return Phone
