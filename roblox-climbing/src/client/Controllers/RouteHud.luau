--!strict
-- RouteHud (client): everything on screen about routes and progress. No game logic here;
-- the server (RouteService, RopeService, DataService) decides, this shows it.
--   * profile chip (top left): gems, level with an XP bar, chalk
--   * run card (top right): route, grade, live timer and a progress bar while on a run
--   * summit card: time, best, rewards, leaderboard rank, Retry / Close
--   * rope badge while tied in: "Tied in" / "Auto-belay" (tap to untie); no reminders
--   * routes menu (button or M): every route with your best time and a "Go" button
--   * short notices (failed runs, other players' big summits)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local MENU_KEY = Enum.KeyCode.M
local NAVY = Color3.fromRGB(16, 24, 42)
local GOLD = Color3.fromRGB(255, 214, 64)
local GREEN = Color3.fromRGB(110, 235, 160)
local GREY = Color3.fromRGB(150, 160, 180)

local RouteHud = {}

local player = Players.LocalPlayer
local requestRemote: RemoteEvent
local screen: ScreenGui
local gemsLabel: TextLabel
local levelLabel: TextLabel
local xpFill: Frame
local chalkLabel: TextLabel
local profileChip: Frame
local runCard: Frame
local runTitle: TextLabel
local runTimer: TextLabel
local runFill: Frame
local runHeight: TextLabel
local ropeBadge: TextButton
local noticeLabel: TextLabel
local summitCard: Frame
local summitTitle: TextLabel
local summitRoute: TextLabel
local summitTime: TextLabel
local summitBest: TextLabel
local summitRewards: TextLabel
local menu: Frame
local menuList: ScrollingFrame
local noticeTween: Tween?
local summitToken = 0

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
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(12, 18, 30)
	b.Text = label
	corner(b, 8)
	b.Parent = parent
	return b
end

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
end

local function routesFolder(): Instance?
	return Workspace:FindFirstChild("Routes")
end

local function sortedRoutes(): { Instance }
	local list = {}
	local routes = routesFolder()
	local children: { Instance } = if routes then routes:GetChildren() else {}
	for _, route in children do
		if route:GetAttribute("RouteName") ~= nil then
			table.insert(list, route)
		end
	end
	table.sort(list, function(a, b)
		return (tonumber(a:GetAttribute("Order")) or 99) < (tonumber(b:GetAttribute("Order")) or 99)
	end)
	return list
end

---------------------------------------------------------------------------------------
-- Building the UI

local function buildProfile()
	local chip = Instance.new("Frame")
	chip.Name = "Profile"
	chip.Position = UDim2.fromOffset(12, 8)
	chip.Size = UDim2.fromOffset(190, 58)
	chip.BackgroundColor3 = NAVY
	chip.BackgroundTransparency = 0.15
	corner(chip, 12)
	chip.Parent = screen
	profileChip = chip
	gemsLabel = text(chip, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(120, 230, 255), Text = "💎 0" })
	levelLabel = text(chip, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(70, 22), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = GOLD, Text = "Lv 1" })
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(12, 34)
	bar.Size = UDim2.new(1, -24, 0, 8)
	bar.BackgroundColor3 = Color3.fromRGB(40, 50, 72)
	corner(bar, 4)
	bar.Parent = chip
	xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = GOLD
	corner(xpFill, 4)
	xpFill.Parent = bar
	chalkLabel = text(chip, { Position = UDim2.fromOffset(12, 60), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = Color3.fromRGB(235, 235, 228), Text = "", Visible = false })
end

local function buildRunCard()
	runCard = Instance.new("Frame")
	runCard.Name = "Run"
	runCard.AnchorPoint = Vector2.new(1, 0)
	runCard.Position = UDim2.new(1, -12, 0, 8)
	runCard.Size = UDim2.fromOffset(230, 92)
	runCard.BackgroundColor3 = NAVY
	runCard.BackgroundTransparency = 0.12
	runCard.Visible = false
	corner(runCard, 12)
	runCard.Parent = screen
	runTitle = text(runCard, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, TextSize = 15 })
	runTimer = text(runCard, { Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Michroma, TextSize = 25, TextColor3 = GREEN, Text = "0:00.00" })
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(12, 66)
	bar.Size = UDim2.new(1, -90, 0, 10)
	bar.BackgroundColor3 = Color3.fromRGB(40, 50, 72)
	corner(bar, 5)
	bar.Parent = runCard
	runFill = Instance.new("Frame")
	runFill.Size = UDim2.fromScale(0, 1)
	runFill.BackgroundColor3 = GREEN
	corner(runFill, 5)
	runFill.Parent = bar
	runHeight = text(runCard, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 60), Size = UDim2.fromOffset(74, 22), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 14, TextColor3 = GREY })
end

local function buildRopeBadge()
	ropeBadge = Instance.new("TextButton")
	ropeBadge.Name = "Rope"
	ropeBadge.AnchorPoint = Vector2.new(1, 0)
	ropeBadge.Position = UDim2.new(1, -12, 0, 106)
	ropeBadge.Size = UDim2.fromOffset(230, 30)
	ropeBadge.BackgroundColor3 = NAVY
	ropeBadge.BackgroundTransparency = 0.15
	ropeBadge.Font = Enum.Font.Sarpanch
	ropeBadge.TextSize = 14
	ropeBadge.TextColor3 = Color3.new(1, 1, 1)
	ropeBadge.RichText = true
	ropeBadge.AutoButtonColor = false
	ropeBadge.Visible = false
	corner(ropeBadge, 8)
	ropeBadge.Parent = screen
	ropeBadge.Activated:Connect(function()
		local character = player.Character
		if character and character:GetAttribute("TiedIn") ~= nil and character:GetAttribute("Climbing") ~= true then
			requestRemote:FireServer("Untie")
		end
	end)
end

local function buildNotice()
	noticeLabel = text(screen, {
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(420, 32),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 1,
		TextTransparency = 1,
		TextSize = 17,
		RichText = true,
	})
	corner(noticeLabel, 10)
end

local function buildSummitCard()
	summitCard = Instance.new("Frame")
	summitCard.Name = "Summit"
	summitCard.AnchorPoint = Vector2.new(0.5, 0.5)
	summitCard.Position = UDim2.fromScale(0.5, 0.42)
	summitCard.Size = UDim2.fromOffset(340, 270)
	summitCard.BackgroundColor3 = NAVY
	summitCard.BackgroundTransparency = 0.05
	summitCard.Visible = false
	corner(summitCard, 16)
	summitCard.Parent = screen
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = summitCard
	summitTitle = text(summitCard, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 44), Font = Enum.Font.Michroma, TextSize = 32, TextColor3 = GOLD, Text = "SUMMIT!" })
	summitRoute = text(summitCard, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 22), TextSize = 17, RichText = true })
	summitTime = text(summitCard, { Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 0, 44), Font = Enum.Font.Michroma, TextSize = 32, TextColor3 = GREEN })
	summitBest = text(summitCard, { Position = UDim2.fromOffset(0, 132), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = GREY, RichText = true })
	summitRewards = text(summitCard, { Position = UDim2.fromOffset(0, 160), Size = UDim2.new(1, 0, 0, 24), TextSize = 19, RichText = true })
	local retry = button(summitCard, "Retry", GREEN)
	retry.Position = UDim2.new(0.5, -150, 1, -62)
	retry.Size = UDim2.fromOffset(140, 44)
	retry.Activated:Connect(function()
		summitCard.Visible = false
		requestRemote:FireServer("Retry")
	end)
	local close = button(summitCard, "Close", Color3.fromRGB(200, 210, 226))
	close.Position = UDim2.new(0.5, 10, 1, -62)
	close.Size = UDim2.fromOffset(140, 44)
	close.Activated:Connect(function()
		summitCard.Visible = false
	end)
end

local function buildMenu()
	local open = button(screen, "🧗 Routes  (M)", GOLD)
	open.Name = "RoutesButton"
	open.AnchorPoint = Vector2.new(0, 1)
	open.Position = UDim2.new(0, 12, 1, -12)
	open.Size = UDim2.fromOffset(150, 40)

	menu = Instance.new("Frame")
	menu.Name = "RoutesMenu"
	menu.AnchorPoint = Vector2.new(0.5, 0.5)
	menu.Position = UDim2.fromScale(0.5, 0.5)
	menu.Size = UDim2.new(0, 460, 0.7, 0)
	menu.BackgroundColor3 = NAVY
	menu.BackgroundTransparency = 0.04
	menu.Visible = false
	corner(menu, 16)
	menu.Parent = screen
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(math.huge, 560)
	constraint.Parent = menu
	text(menu, { Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -80, 0, 34), Font = Enum.Font.Michroma, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD, Text = "ROUTES" })
	local close = button(menu, "✕", Color3.fromRGB(200, 210, 226))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(36, 36)
	close.Activated:Connect(function()
		menu.Visible = false
	end)
	menuList = Instance.new("ScrollingFrame")
	menuList.Position = UDim2.fromOffset(12, 58)
	menuList.Size = UDim2.new(1, -24, 1, -70)
	menuList.BackgroundTransparency = 1
	menuList.BorderSizePixel = 0
	menuList.ScrollBarThickness = 6
	menuList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	menuList.CanvasSize = UDim2.new()
	menuList.Parent = menu
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = menuList

	local function toggle()
		menu.Visible = not menu.Visible
		if menu.Visible then
			RouteHud.refreshMenu()
		end
	end
	open.Activated:Connect(toggle)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == MENU_KEY then
			toggle()
		end
	end)
end

function RouteHud.refreshMenu()
	for _, child in menuList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, route in sortedRoutes() do
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, 54)
		row.BackgroundColor3 = Color3.fromRGB(28, 38, 62)
		corner(row, 10)
		row.Parent = menuList
		local where = if route:GetAttribute("Indoor") == true then "Gym" else "Outdoors"
		text(row, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -110, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			RichText = true,
			Text = `{route:GetAttribute("RouteName")}  <font color="#FFD640">{route:GetAttribute("Grade")}</font>`,
		})
		local best = player:GetAttribute(`Best_{route.Name}`)
		local rope = if route:GetAttribute("AutoBelay") == true then "auto-belay" elseif route:GetAttribute("Rope") == true then "rope" else "boulder"
		text(row, {
			Position = UDim2.fromOffset(12, 28),
			Size = UDim2.new(1, -110, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextColor3 = GREY,
			RichText = true,
			Text = `{where} · {route:GetAttribute("HeightMeters")} m · {rope}` .. (if type(best) == "number" then `  ·  <font color="#6EEBA0">best {formatTime(best)}</font>` else ""),
		})
		local go = button(row, "Go", GREEN)
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -10, 0.5, 0)
		go.Size = UDim2.fromOffset(80, 36)
		go.Activated:Connect(function()
			menu.Visible = false
			requestRemote:FireServer("Travel", route.Name)
		end)
	end
end

---------------------------------------------------------------------------------------
-- Updating

function RouteHud.notice(message: string, color: Color3?)
	if noticeTween then
		noticeTween:Cancel()
	end
	noticeLabel.Text = message
	noticeLabel.TextColor3 = color or Color3.new(1, 1, 1)
	noticeLabel.TextTransparency = 0
	noticeLabel.BackgroundTransparency = 0.2
	local width = math.max(200, #message * 9 + 40)
	noticeLabel.Size = UDim2.fromOffset(math.min(width, 560), 32)
	local tween = TweenService:Create(noticeLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 3), { TextTransparency = 1, BackgroundTransparency = 1 })
	noticeTween = tween
	tween:Play()
end

local function updateProfile()
	local gems = player:GetAttribute("Gems")
	local xp = player:GetAttribute("XP")
	local level = player:GetAttribute("Level")
	gemsLabel.Text = `💎 {if type(gems) == "number" then gems else 0}`
	local lv = if type(level) == "number" then level else 1
	levelLabel.Text = `Lv {lv}`
	-- XP for level n starts at 100 * (n-1)^2 (DataService.levelFor).
	local from, to = 100 * (lv - 1) ^ 2, 100 * lv ^ 2
	local value = if type(xp) == "number" then xp else 0
	xpFill.Size = UDim2.fromScale(math.clamp((value - from) / (to - from), 0, 1), 1)
end

local function showSummit(result: any)
	if type(result) ~= "table" then
		return
	end
	summitToken += 1
	local token = summitToken
	summitTitle.Text = if result.newBest and result.best then "NEW BEST!" else "SUMMIT!"
	summitRoute.Text = `{result.routeName}  <font color="#FFD640">{result.grade}</font>  ·  {result.meters} m`
	summitTime.Text = formatTime(result.seconds)
	local lines = {}
	if result.best then
		table.insert(lines, `previous best {formatTime(result.best)}`)
	elseif result.firstClear then
		table.insert(lines, "first ascent!")
	end
	if result.rank then
		table.insert(lines, `<font color="#FFD640">#{result.rank} on the leaderboard</font>`)
	end
	summitBest.Text = table.concat(lines, "  ·  ")
	summitRewards.Text = `<font color="#78E6FF">+{result.gems} 💎</font>    <font color="#FFD640">+{result.xp} XP</font>`
	summitCard.Visible = true
	summitCard.Size = UDim2.fromOffset(300, 240)
	TweenService:Create(summitCard, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(340, 270) }):Play()
	task.delay(12, function()
		if summitToken == token then
			summitCard.Visible = false
		end
	end)
end

local function onRouteEvent(kind: any, a: any, b: any)
	if kind == "Started" then
		summitCard.Visible = false
	elseif kind == "Summit" then
		showSummit(a)
	elseif kind == "Failed" and type(b) == "string" then
		RouteHud.notice(`{b} — run over`, Color3.fromRGB(255, 170, 120))
	elseif kind == "Notice" and type(a) == "string" then
		RouteHud.notice(a, GOLD)
	end
end


local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Run card.
	local routeId = player:GetAttribute("RunRoute")
	local started = player:GetAttribute("RunStart")
	local routes = routesFolder()
	local route = if type(routeId) == "string" and routes then routes:FindFirstChild(routeId) else nil
	if route and type(started) == "number" and root then
		runCard.Visible = true
		runTitle.Text = `{route:GetAttribute("RouteName")}  <font color="#FFD640">{route:GetAttribute("Grade")}</font>`
		runTimer.Text = formatTime(math.max(0, Workspace:GetServerTimeNow() - started))
		local baseY = tonumber(route:GetAttribute("BaseY")) or 0
		local rise = tonumber(route:GetAttribute("HeightStuds")) or 1
		local fraction = math.clamp((root.Position.Y - 3 - baseY) / rise, 0, 1)
		runFill.Size = UDim2.fromScale(fraction, 1)
		runHeight.Text = `{math.floor(Config.studsToMeters(fraction * rise))}/{route:GetAttribute("HeightMeters")} m`
	else
		runCard.Visible = false
	end

	-- Rope badge.
	local tied = character and character:GetAttribute("TiedIn")
	if character and root and type(tied) == "string" then
		local tiedRoute = routes and routes:FindFirstChild(tied)
		local auto = tiedRoute and tiedRoute:GetAttribute("AutoBelay") == true
		ropeBadge.Visible = true
		ropeBadge.BackgroundColor3 = if auto then Color3.fromRGB(20, 70, 130) else Color3.fromRGB(110, 90, 10)
		if character:GetAttribute("RopeCatch") == true then
			ropeBadge.Text = "🪢 Caught — lowering you"
		elseif auto then
			ropeBadge.Text = `🪢 Auto-belay clipped in{if character:GetAttribute("Climbing") ~= true then "  ·  <b>tap to unclip</b>" else ""}`
		else
			ropeBadge.Text = `🪢 Tied in{if character:GetAttribute("Climbing") ~= true then "  ·  <b>tap to untie</b>" else ""}`
		end
	else
		ropeBadge.Visible = false
	end

	-- Chalk.
	local chalk = character and character:GetAttribute("Chalk")
	if type(chalk) == "number" and chalk > 0 then
		chalkLabel.Visible = true
		chalkLabel.Text = `✋ Chalk {math.ceil(chalk / Config.Chalk.Max * 100)}%`
		profileChip.Size = UDim2.fromOffset(190, 80)
	elseif chalkLabel.Visible then
		chalkLabel.Visible = false
		profileChip.Size = UDim2.fromOffset(190, 58)
	end
end

function RouteHud.Init()
	screen = Instance.new("ScreenGui")
	screen.Name = "RouteHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 5
	buildProfile()
	buildRunCard()
	buildRopeBadge()
	buildNotice()
	buildSummitCard()
	buildMenu()
	screen.Parent = player:WaitForChild("PlayerGui")
end

function RouteHud.Start()
	requestRemote = Remotes.event("RouteRequest")
	Remotes.event("RouteEvent").OnClientEvent:Connect(onRouteEvent)
	for _, name in { "Gems", "XP", "Level" } do
		player:GetAttributeChangedSignal(name):Connect(updateProfile)
	end
	updateProfile()
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed >= 1 / 30 then
			elapsed = 0
			update()
		end
	end)
end

return RouteHud
