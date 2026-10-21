--!nocheck
-- Runs the game's real client UI code outside Studio with Lune, puts it through a set of
-- scenes (HUD, phone apps, shop, lockers, pack window, summit card...), and writes every
-- scene's GUI tree to JSON for layout.py, which lays it out, measures the text with the
-- real fonts, renders a picture and reports overflow.
--
--     rojo build default.project.json -o /tmp/place.rbxlx
--     lune run tools/ui/dump.luau /tmp/place.rbxlx /tmp/ui.json

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Enum = roblox.Enum
local Instance = roblox.Instance
local placePath, outPath, viewArg = process.args[1], process.args[2], process.args[3]
local game = roblox.deserializePlace(fs.readFile(placePath))

---------------------------------------------------------------------------------------
-- Signals (Lune instances have no events): one fireable signal per instance + name.

local nextId = 0
local function idOf(instance)
	local id = instance:GetAttribute("__uid")
	if id == nil then
		nextId += 1
		id = nextId
		instance:SetAttribute("__uid", id)
	end
	return id
end

local function newSignal()
	local signal = { handlers = {} }
	function signal:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end, Connected = true }
	end
	signal.Once = signal.Connect
	function signal:Fire(...)
		for _, fn in self.handlers do
			local ok, err = pcall(fn, ...)
			if not ok then
				print("HANDLER ERROR", err)
			end
		end
	end
	function signal:Wait() end
	return signal
end

local signals = {}
local function signalFor(instance, name)
	local key = `{idOf(instance)}:{name}`
	local s = signals[key]
	if s == nil then
		s = newSignal()
		signals[key] = s
	end
	return s
end

local EVENTS = {
	GuiButton = { "Activated", "MouseButton1Click", "MouseButton1Down" },
	GuiObject = { "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" },
	UserInputService = { "InputBegan", "InputEnded", "InputChanged", "TouchStarted" },
	RunService = { "RenderStepped", "Heartbeat", "PreSimulation", "Stepped" },
	RemoteEvent = { "OnClientEvent" },
	ProximityPromptService = { "PromptTriggered", "PromptShown", "PromptHidden" },
	Player = { "CharacterAdded", "CharacterRemoving" },
	Instance = { "AttributeChanged", "ChildAdded", "ChildRemoved", "DescendantAdded", "Changed", "Destroying" },
	Humanoid = { "Died" },
	BindableEvent = { "Event" },
	CollectionService = {},
}
for class, names in EVENTS do
	for _, name in names do
		roblox.implementProperty(class, name, function(instance)
			return signalFor(instance, name)
		end)
	end
end
roblox.implementMethod("BindableEvent", "Fire", function(instance, ...)
	signalFor(instance, "Event"):Fire(...)
end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(instance, name)
	return signalFor(instance, "attr:" .. name)
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(instance, name)
	return signalFor(instance, "prop:" .. name)
end)
roblox.implementMethod("Instance", "WaitForChild", function(instance, name)
	return instance:FindFirstChild(name)
end)
-- SetAttribute fires the attribute's changed signal.
local rawSetAttribute
roblox.implementMethod("Instance", "SetAttributeFire", function(instance, name, value)
	instance:SetAttribute(name, value)
	signalFor(instance, "attr:" .. name):Fire()
	signalFor(instance, "AttributeChanged"):Fire(name)
end)

-- Services and engine bits.
local Players = game:GetService("Players")
local player = Instance.new("Player")
player.Name = "Climber"
player.Parent = Players
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = player
Instance.new("Folder").Name = "PlayerScripts"
roblox.implementProperty("Players", "LocalPlayer", function()
	return player
end)
roblox.implementProperty("Player", "Character", function()
	return nil
end, function() end)
roblox.implementProperty("Player", "DisplayName", function()
	return "Climber"
end)
roblox.implementProperty("Player", "UserId", function()
	return 1
end)
local viewW, viewH = string.match(viewArg or "1280x720", "(%d+)x(%d+)")
local VIEW = roblox.Vector2.new(tonumber(viewW), tonumber(viewH))
local camera = Instance.new("Camera")
camera.Parent = game:GetService("Workspace")
roblox.implementProperty("Workspace", "CurrentCamera", function()
	return camera
end)
roblox.implementProperty("Camera", "ViewportSize", function()
	return VIEW
end)
roblox.implementMethod("Camera", "ViewportPointToRay", function(_, x, y)
	return roblox.Ray.new(roblox.Vector3.zero, roblox.Vector3.new(0, 0, -1))
end)
roblox.implementMethod("Camera", "WorldToViewportPoint", function()
	return roblox.Vector3.new(640, 360, 10), true
end)
roblox.implementProperty("UserInputService", "TouchEnabled", function()
	return false
end)
roblox.implementProperty("UserInputService", "MouseEnabled", function()
	return true
end)
roblox.implementProperty("UserInputService", "KeyboardEnabled", function()
	return true
end)
roblox.implementProperty("UserInputService", "GamepadEnabled", function()
	return false
end)
roblox.implementMethod("UserInputService", "GetMouseLocation", function()
	return roblox.Vector2.new(640, 360)
end)
roblox.implementMethod("UserInputService", "GetFocusedTextBox", function()
	return nil
end)
roblox.implementMethod("UserInputService", "IsKeyDown", function()
	return false
end)
roblox.implementMethod("GuiService", "GetGuiInset", function()
	return roblox.Vector2.new(0, 58), roblox.Vector2.zero
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)
roblox.implementMethod("RunService", "IsServer", function()
	return false
end)
roblox.implementMethod("RunService", "IsClient", function()
	return true
end)
roblox.implementMethod("TweenService", "Create", function(_, instance, _, goals)
	local tween = { Completed = newSignal() }
	function tween:Play()
		for k, v in goals do
			pcall(function()
				instance[k] = v
			end)
		end
		self.Completed:Fire(Enum.PlaybackState.Completed)
	end
	function tween:Cancel() end
	function tween:Pause() end
	return tween
end)
for _, method in { "BindAction", "BindActionAtPriority", "UnbindAction", "SetTitle", "SetImage", "SetPosition" } do
	roblox.implementMethod("ContextActionService", method, function() end)
end
roblox.implementMethod("RemoteEvent", "FireServer", function(remote, ...)
	print("FireServer", remote.Name, ...)
end)
local collection = {
	GetTagged = function()
		return {}
	end,
	GetInstanceAddedSignal = function()
		return newSignal()
	end,
	GetInstanceRemovedSignal = function()
		return newSignal()
	end,
	HasTag = function()
		return false
	end,
	AddTag = function() end,
}

-- Roblox's Instance.new defaults that Lune's reflection data leaves at zero.
local DEFAULT_SIZE = { Frame = 100, ImageLabel = 100, ImageButton = 100, ScrollingFrame = 100, TextLabel = 200, TextButton = 200, TextBox = 200 }
local function newInstance(class, parent)
	local instance = Instance.new(class)
	if DEFAULT_SIZE[class] then
		instance.Size = if string.find(class, "Text") then roblox.UDim2.fromOffset(200, 50) else roblox.UDim2.fromOffset(100, 100)
		instance.BackgroundColor3 = roblox.Color3.fromRGB(163, 162, 165)
		instance.BorderColor3 = roblox.Color3.fromRGB(27, 42, 53)
	end
	if string.find(class, "^Text") then
		instance.TextSize = 14
		instance.TextColor3 = roblox.Color3.new(0, 0, 0)
	end
	if class == "UIListLayout" or class == "UIGridLayout" then
		instance.SortOrder = Enum.SortOrder.LayoutOrder
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Remotes, as the server would make them.
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = game:GetService("ReplicatedStorage")

---------------------------------------------------------------------------------------
-- require() for the place's ModuleScripts.

local cache = {}
local env
local function requireModule(module)
	if cache[module:GetFullName()] ~= nil then
		return cache[module:GetFullName()]
	end
	local moduleEnv = table.clone(env)
	moduleEnv.script = module
	local source = module.Source:gsub("CollectionService:(%a+)%(", "__collection.%1(")
	source = source:gsub(":SetAttribute%(", ":SetAttributeFire(")
	-- Real properties Lune can't override.
	source = source:gsub("Players%.LocalPlayer", "__player")
	source = source:gsub("%.DisplayName", ".Name")
	source = source:gsub("%.UserId", ":GetAttribute('__userId')")
	source = source:gsub("[%w_]+%.CurrentCamera", "__camera")
	source = source:gsub("([%w_%.]+)%.ViewportSize", "__VIEW")
	local chunk = luau.load(source, { debugName = module:GetFullName(), environment = moduleEnv })
	local result = chunk()
	cache[module:GetFullName()] = result
	return result
end
local delayed = {}
env = {
	__collection = collection,
	__player = player,
	__camera = camera,
	__VIEW = VIEW,
	game = game,
	workspace = game:GetService("Workspace"),
	require = requireModule,
	Instance = { new = newInstance },
	RaycastParams = { new = function()
		return {}
	end },
	task = {
		wait = function() end,
		spawn = function(f, ...)
			local ok, err = pcall(f, ...)
			if not ok then
				print("SPAWN ERROR", err)
			end
		end,
		defer = function(f, ...)
			pcall(f, ...)
		end,
		delay = function(_, f, ...)
			table.insert(delayed, { f, ... })
		end,
		cancel = function() end,
	},
	warn = function(...)
		print("WARN", ...)
	end,
	tick = os.clock,
	time = os.clock,
}
for _, name in { "Axes", "BrickColor", "CFrame", "Color3", "ColorSequence", "ColorSequenceKeypoint", "Enum", "Faces", "Font", "NumberRange", "NumberSequence", "NumberSequenceKeypoint", "PhysicalProperties", "Ray", "Rect", "Region3", "TweenInfo", "UDim", "UDim2", "Vector2", "Vector3", "DateTime" } do
	env[name] = roblox[name]
end
env.TweenInfo = env.TweenInfo or { new = function()
	return {}
end }
for _, name in { "print", "pcall", "error", "assert", "type", "typeof", "tostring", "tonumber", "pairs", "ipairs", "next", "select", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "table", "string", "math", "os", "utf8", "bit32", "buffer", "coroutine", "unpack", "xpcall" } do
	env[name] = (getfenv(0) :: any)[name]
end

local Remotes = requireModule(game:GetService("ReplicatedStorage").Shared.Remotes)
for _, name in Remotes.Names do
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotesFolder
end

---------------------------------------------------------------------------------------
-- Run the controllers.

local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local CONTROLLERS = { "ClimbController", "RouteHud", "GearUI", "PackUI", "Phone" }
local modules = {}
for _, name in CONTROLLERS do
	local ok, module = pcall(requireModule, client.Controllers[name])
	if ok then
		modules[name] = module
	else
		print("LOAD FAILED", name, module)
	end
end
for _, name in CONTROLLERS do
	local module = modules[name]
	if module and module.Init then
		local ok, err = pcall(module.Init)
		if not ok then
			print("INIT FAILED", name, err)
		end
	end
end
for _, name in CONTROLLERS do
	local module = modules[name]
	if module and module.Start then
		local ok, err = pcall(module.Start)
		if not ok then
			print("START FAILED", name, err)
		end
	end
end

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local function frames(n)
	for _ = 1, n or 3 do
		signalFor(RunService, "RenderStepped"):Fire(1 / 60)
		signalFor(RunService, "Heartbeat"):Fire(1 / 60)
	end
end
local function flushDelays()
	local list = delayed
	delayed = {}
	for _, d in list do
		pcall(table.unpack(d))
	end
end
local function key(code)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard, UserInputState = Enum.UserInputState.Begin, Position = roblox.Vector3.zero }
	signalFor(UserInputService, "InputBegan"):Fire(input, false)
end
local function prompt(name)
	signalFor(game:GetService("ProximityPromptService"), "PromptTriggered"):Fire({ Name = name }, player)
end
local function remote(name, ...)
	signalFor(remotesFolder:FindFirstChild(name), "OnClientEvent"):Fire(...)
end
local function setPlayer(attrs)
	for k, v in attrs do
		player:SetAttributeFire(k, v)
	end
end
local function click(path)
	-- Click a button by its path under PlayerGui ("Phone.Body.Display.Home.Tile_Routes").
	local node = playerGui
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	if node then
		signalFor(node, "Activated"):Fire()
	else
		print("NO BUTTON", path)
	end
end

-- A realistic player.
setPlayer({
	Gems = 12840, XP = 5230, Level = 8, Summits = 37, TotalClimbed = 4210,
	Best_TestWall = 41.37, Best_MossySteps = 96.4, Best_LongWayUp = 2754.2,
	Owned = "RentalShoes,TrailEdge,BasicChalk,DayPack,CragPack,YellowRope",
	Equip_Shoes = "TrailEdge", Equip_ChalkBag = "BasicChalk", Equip_Harness = "RentalHarness", Equip_Helmet = "NoHelmet", Equip_Pack = "CragPack", Equip_Rope = "YellowRope",
	PackColor = 2, ChalkColor = 3, HelmetColor = 1,
	Pack_Rope = 1, Have_Rope = 1, Pack_CrashPad = 1, Have_CrashPad = 0, Pack_Quickdraws = 8, Have_Quickdraws = 5, Pack_Chalk = 0, Have_Chalk = 0, Pack_Water = 2, Have_Water = 1,
	PackWeight = 14, PackCapacity = 11,
})
frames(3)

---------------------------------------------------------------------------------------
-- Scenes

local function guiValue(v)
	local t = typeof(v)
	if t == "UDim2" then
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "UDim" then
		return { v.Scale, v.Offset }
	elseif t == "Vector2" then
		return { v.X, v.Y }
	elseif t == "Color3" then
		return { v.R, v.G, v.B }
	elseif t == "EnumItem" then
		return tostring(v):gsub("^Enum%.%w+%.", "")
	end
	return v
end

local PROPS = {
	"Name", "Visible", "Position", "Size", "AnchorPoint", "AutomaticSize", "ZIndex", "LayoutOrder",
	"BackgroundColor3", "BackgroundTransparency", "ClipsDescendants", "Rotation",
	"Text", "TextSize", "TextColor3", "TextTransparency", "TextWrapped", "TextScaled", "RichText", "TextXAlignment", "TextYAlignment", "TextTruncate", "LineHeight",
	"Image", "ImageTransparency", "ImageColor3",
	"CanvasSize", "AutomaticCanvasSize", "ScrollingDirection",
	"FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Wraps",
	"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom",
	"CellSize", "CellPadding", "FillDirectionMaxCells",
	"CornerRadius", "Thickness", "Color", "Transparency", "ApplyStrokeMode",
	"MaxSize", "MinSize", "MaxTextSize", "MinTextSize", "AspectRatio",
	"Enabled", "DisplayOrder", "IgnoreGuiInset", "Scale",
}

local function dumpNode(instance)
	local node = { class = instance.ClassName, children = {} }
	for _, prop in PROPS do
		local ok, value = pcall(function()
			return instance[prop]
		end)
		if ok and value ~= nil and type(value) ~= "table" then
			node[prop] = guiValue(value)
		end
	end
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		local ok, f = pcall(function()
			return instance.Font
		end)
		node.Font = tostring(if ok and f then f else Enum.Font.Legacy):gsub("^Enum%.Font%.", "")
	end
	for _, child in instance:GetChildren() do
		table.insert(node.children, dumpNode(child))
	end
	return node
end

local scenes = {}
local function snapshot(name)
	frames(2)
	local guis = {}
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") then
			table.insert(guis, dumpNode(gui))
		end
	end
	table.insert(scenes, { name = name, guis = guis })
end

snapshot("hud")
local overlay = requireModule(client.Controllers.ClimbOverlay)
overlay.setHint("<b>Drag</b> hands/feet to holds  ·  <b>WASD</b> shift weight (stays)  ·  <b>X</b> centre  ·  <b>Space</b> dyno  ·  <b>V</b> let go  ·  <b>T</b>/<b>Y</b> rope in/out  ·  <b>R</b> lower off")
overlay.toast("Out of reach - shift your weight (W A S D)")
overlay.setHeight(112.4)
snapshot("climbing")
overlay.setHint(nil)
overlay.setHeight(nil)
overlay.showDeath("YOU FELL 38 M", "Free solo. Rope up next time, or climb lower.")
snapshot("death")
overlay.showDeath(nil)
-- The pro shop on each tab.

remote("RouteEvent", "Started", "MossySteps")
remote("RouteEvent", "Notice", "Retry, or M on your phone to travel back down")
snapshot("hud_notice")
remote("RouteEvent", "Summit", { routeId = "MossySteps", routeName = "Mossy Steps", grade = "4", meters = 14.8, seconds = 96.41, best = 101.2, newBest = true, gems = 34, xp = 120, rank = 3, firstClear = false })
snapshot("summit")
flushDelays()

key(Enum.KeyCode.P)
flushDelays()
snapshot("phone_home")
for _, app in { "Controls", "Routes", "Stats", "Settings" } do
	local ok = pcall(function()
		modules.Phone.show(app)
	end)
	if not ok then
		-- Fall back to clicking the home tile.
		click(`Phone.Body.Display.Home.{app}`)
	end
	snapshot("phone_" .. string.lower(app))
end
key(Enum.KeyCode.P)

prompt("OpenShop")
snapshot("shop")
for _, tab in { "ChalkBag", "Harness", "Helmet", "Pack", "Rope" } do
	click(`GearUI.ProShop.Tabs.{tab}`)
	snapshot("shop_" .. string.lower(tab))
end
key(Enum.KeyCode.Escape)
prompt("OpenLocker")
snapshot("locker")
key(Enum.KeyCode.Escape)
prompt("OpenPack")
snapshot("pack")
key(Enum.KeyCode.Escape)

fs.writeFile(outPath, serde.encode("json", { viewport = { VIEW.X, VIEW.Y }, inset = 58, scenes = scenes }))
print(`{#scenes} scenes -> {outPath}`)
