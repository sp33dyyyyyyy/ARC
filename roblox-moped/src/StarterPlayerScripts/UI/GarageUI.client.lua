--[[
	GarageUI  (LocalScript, StarterPlayerScripts/UI)

	Opens when the server fires OpenGarage (walk up to a part tagged
	"GarageDoor"). Browse the roster, spin the bike in a ViewportFrame with an
	orbiting camera, see stats as bars, pick one of two colours, buy / equip.

	The UI only DISPLAYS prices and requirements from VehicleData. All real
	checks (owned? unlocked? enough money?) happen again on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehicleData = require(Shared:WaitForChild("VehicleData"))
local BikeFactory = require(Shared:WaitForChild("BikeFactory"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local T = UIKit.theme
local make, label, button = UIKit.make, UIKit.label, UIKit.button

local gui = UIKit.screenGui("GarageUI", 10)
gui.Enabled = false

local STAT_ROWS = {
	{ key = "topSpeedKmh", name = "Top speed", fmt = "%d km/h" },
	{ key = "acceleration", name = "Acceleration", fmt = "%d" },
	{ key = "braking", name = "Braking", fmt = "%d" },
	{ key = "handling", name = "Handling", fmt = "%d" },
	{ key = "weightKg", name = "Weight", fmt = "%d kg" },
	{ key = "fuelCapacityL", name = "Fuel tank", fmt = "%.1f L" },
}

local state = { selected = VehicleData.list[1].id, paint = 1, view = nil :: any, busy = false }

----------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------
local backdrop = make("Frame", { Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45 })
local window = make("Frame", {
	Parent = backdrop, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.86, 0, 0.82, 0), BackgroundColor3 = T.bg,
}, { UIKit.corner(18), make("UISizeConstraint", { MaxSize = Vector2.new(1100, 640), MinSize = Vector2.new(720, 420) }) })

label({ Parent = window, Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(300, 30), Font = Enum.Font.GothamBlack, TextSize = 24, Text = "WERKSTATT GARAGE" })
local moneyText = label({
	Parent = window, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 14),
	Size = UDim2.fromOffset(240, 28), TextXAlignment = Enum.TextXAlignment.Right,
	Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = T.accent, Text = "",
})
local closeBtn = button({
	Parent = window, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 12),
	Size = UDim2.fromOffset(40, 32), Text = "X", BackgroundColor3 = T.panelLight,
})

-- left: roster list
local list = make("ScrollingFrame", {
	Parent = window, Position = UDim2.fromOffset(16, 56), Size = UDim2.new(0, 210, 1, -72),
	BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
}, { make("UIListLayout", { Padding = UDim.new(0, 8) }) })

-- centre: viewport
local viewport = make("ViewportFrame", {
	Parent = window, Position = UDim2.new(0, 242, 0, 56), Size = UDim2.new(1, -242 - 330, 1, -72),
	BackgroundColor3 = T.panel, Ambient = Color3.fromRGB(150, 150, 160), LightColor = Color3.fromRGB(255, 244, 225),
	LightDirection = Vector3.new(-1, -1.4, -0.6),
}, { UIKit.corner(14) })
local worldModel = make("WorldModel", { Parent = viewport })
local cam = make("Camera", { Parent = viewport, FieldOfView = 35 })
viewport.CurrentCamera = cam

-- right: info
local info = make("Frame", {
	Parent = window, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 56),
	Size = UDim2.new(0, 300, 1, -72), BackgroundColor3 = T.panel,
}, { UIKit.corner(14), UIKit.padding(14) })

local nameText = label({ Parent = info, Size = UDim2.new(1, 0, 0, 28), Font = Enum.Font.GothamBlack, TextSize = 24, Text = "" })
local subText = label({ Parent = info, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = T.muted, Text = "" })
local descText = label({
	Parent = info, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 36), TextSize = 13, TextColor3 = T.muted,
	TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
})

local setBars = {}
local valueTexts = {}
for i, s in ipairs(STAT_ROWS) do
	local y = 94 + (i - 1) * 32
	label({ Parent = info, Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(100, 16), TextSize = 13, TextColor3 = T.muted, Text = s.name })
	valueTexts[s.key] = label({
		Parent = info, Position = UDim2.new(1, 0, 0, y), AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(100, 16),
		TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, Text = "",
	})
	local _, setter = UIKit.bar({ Parent = info, Position = UDim2.fromOffset(0, y + 18), Size = UDim2.new(1, 0, 0, 8) }, T.accent)
	setBars[s.key] = setter
end

label({ Parent = info, Position = UDim2.fromOffset(0, 292), Size = UDim2.fromOffset(60, 16), TextSize = 13, TextColor3 = T.muted, Text = "Colour" })
local swatches = {}
for i = 1, 2 do
	local sw = make("TextButton", {
		Parent = info, Position = UDim2.fromOffset(60 + (i - 1) * 40, 288), Size = UDim2.fromOffset(32, 24), Text = "",
		AutoButtonColor = false, BorderSizePixel = 0,
	}, { UIKit.corner(6), make("UIStroke", { Thickness = 2, Color = T.panel }) })
	sw.MouseButton1Click:Connect(function()
		state.paint = i
		state.refresh()
	end)
	swatches[i] = sw
end
local colourName = label({ Parent = info, Position = UDim2.fromOffset(148, 290), Size = UDim2.new(1, -148, 0, 20), TextSize = 13, Text = "" })

local reqText = label({
	Parent = info, Position = UDim2.fromOffset(0, 318), Size = UDim2.new(1, 0, 0, 34), TextSize = 13, TextColor3 = T.warn,
	TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
})
local actionBtn = button({
	Parent = info, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -42), Size = UDim2.new(1, 0, 0, 38),
	BackgroundColor3 = T.accent, TextColor3 = Color3.fromRGB(30, 26, 12), Text = "",
})
local bringBtn = button({
	Parent = info, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 34),
	Text = "Take it out (B)", TextSize = 14,
})

----------------------------------------------------------------------------
-- Preview model (spinning)
----------------------------------------------------------------------------
local previewModel: Model? = nil
local angle = 0

local function showPreview()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	local m = BikeFactory.create(state.selected, state.paint)
	if not m then
		return
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m:PivotTo(CFrame.new(0, 0, 0))
	m.Parent = worldModel
	previewModel = m
end

RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then
		return
	end
	angle += dt * 0.6
	local radius, height = 11, 3.2
	local target = Vector3.new(0, 0.9, 0)
	cam.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius), target)
end)

----------------------------------------------------------------------------
-- Refresh everything for the current selection
----------------------------------------------------------------------------
local rosterButtons = {}

function state.refresh()
	local view = state.view
	if not view then
		return
	end
	local v = VehicleData.byId[state.selected]
	local owned = view.owned[v.id]
	local equipped = view.equipped == v.id
	moneyText.Text = ("EUR %d"):format(view.money)

	nameText.Text = v.displayName
	subText.Text = ("%s  -  %dcc %s"):format(v.class, v.cc, v.engineType)
	descText.Text = v.description
	for _, s in ipairs(STAT_ROWS) do
		local value = v.stats[s.key]
		valueTexts[s.key].Text = s.fmt:format(value)
		setBars[s.key](value / VehicleData.statMax[s.key])
	end
	for i, sw in ipairs(swatches) do
		sw.BackgroundColor3 = v.colours[i].body
		local stroke = sw:FindFirstChildOfClass("UIStroke")
		stroke.Color = (i == state.paint) and T.accent or T.panel
	end
	colourName.Text = v.colours[state.paint].name

	local unlocked, why = VehicleData.checkUnlock(v, view)
	if owned then
		reqText.Text = ""
		local currentPaint = owned.paint
		if equipped and currentPaint == state.paint then
			actionBtn.Text = "Equipped"
			actionBtn.Active = false
			actionBtn.BackgroundColor3 = T.panelLight
		else
			actionBtn.Text = equipped and "Apply colour" or "Equip"
			actionBtn.Active = true
			actionBtn.BackgroundColor3 = T.accent
		end
	else
		local affordable = view.money >= v.price
		actionBtn.Text = v.price == 0 and "Take for free" or ("Buy  -  EUR %d"):format(v.price)
		actionBtn.Active = unlocked and affordable
		actionBtn.BackgroundColor3 = (unlocked and affordable) and T.accent or T.panelLight
		reqText.Text = not unlocked and ("Locked: " .. why) or (not affordable and ("Need EUR %d more"):format(v.price - view.money) or "")
	end
	bringBtn.Visible = owned ~= nil and equipped

	for id, b in pairs(rosterButtons) do
		local o = view.owned[id]
		local sel = id == state.selected
		b.BackgroundColor3 = sel and T.panelLight or T.panel
		local tag = b:FindFirstChild("Tag") :: TextLabel
		local veh = VehicleData.byId[id]
		if view.equipped == id then
			tag.Text, tag.TextColor3 = "EQUIPPED", T.good
		elseif o then
			tag.Text, tag.TextColor3 = "OWNED", T.info
		elseif not VehicleData.checkUnlock(veh, view) then
			tag.Text, tag.TextColor3 = "LOCKED", T.warn
		else
			tag.Text, tag.TextColor3 = ("EUR %d"):format(veh.price), T.muted
		end
	end
end

local function selectBike(id: string)
	state.selected = id
	local owned = state.view and state.view.owned[id]
	state.paint = owned and owned.paint or 1
	showPreview()
	state.refresh()
end

for _, v in ipairs(VehicleData.list) do
	local b = make("TextButton", {
		Parent = list, Size = UDim2.new(1, -6, 0, 62), BackgroundColor3 = T.panel, AutoButtonColor = true, Text = "",
	}, { UIKit.corner(12) })
	label({ Parent = b, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22), Font = Enum.Font.GothamBold, TextSize = 17, Text = v.displayName })
	label({ Parent = b, Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 14), TextSize = 12, TextColor3 = T.muted, Text = ("%s %dcc"):format(v.class, v.cc) })
	label({ Name = "Tag", Parent = b, Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 0, 14), TextSize = 11, Font = Enum.Font.GothamBold, Text = "" })
	b.MouseButton1Click:Connect(function()
		selectBike(v.id)
	end)
	rosterButtons[v.id] = b
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------
local function run(fn)
	if state.busy then
		return
	end
	state.busy = true
	task.spawn(function()
		fn()
		state.busy = false
	end)
end

actionBtn.MouseButton1Click:Connect(function()
	if not actionBtn.Active then
		return
	end
	run(function()
		local view = state.view
		local owned = view.owned[state.selected]
		local res
		if not owned then
			res = Remotes.func("GarageBuy"):InvokeServer(state.selected, state.paint)
			if res.ok then
				res = Remotes.func("GarageEquip"):InvokeServer(state.selected, state.paint)
			end
		else
			res = Remotes.func("GarageEquip"):InvokeServer(state.selected, state.paint)
		end
		if not res.ok then
			reqText.Text = res.reason or "Something went wrong"
		end
	end)
end)

bringBtn.MouseButton1Click:Connect(function()
	run(function()
		Remotes.func("GarageSpawn"):InvokeServer()
		gui.Enabled = false
	end)
end)

closeBtn.MouseButton1Click:Connect(function()
	gui.Enabled = false
end)

-- walk away = garage closes
task.spawn(function()
	while true do
		task.wait(0.5)
		if gui.Enabled and ClientState.mode == "Ride" then
			gui.Enabled = false
		end
	end
end)

----------------------------------------------------------------------------
-- Server events
----------------------------------------------------------------------------
Remotes.event("DataChanged").OnClientEvent:Connect(function(view)
	state.view = view
	if gui.Enabled then
		state.refresh()
	end
end)

Remotes.event("OpenGarage").OnClientEvent:Connect(function(view)
	state.view = view
	gui.Enabled = true
	selectBike(view.equipped)
end)
