--!strict
-- RouteHud (client): what's on screen about money, routes and the rope. No game logic:
-- the server (RouteService, RopeService, DataService, ChalkService) decides; this shows it.
--   * status strip (top left): money, level and XP, chalk left
--   * run card (top right): route, grade, live timer, progress
--   * rope line under it while tied in (tap to untie)
--   * summit card: time, best, money and XP earned, leaderboard rank, Retry / Close
--   * chalk-up button (bottom right, or G): chalk your hands from your own chalk bag
--   * short notices (failed runs, other players' big summits)
-- The route list lives on the phone (Phone controller).

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
local CHALK_KEY = Enum.KeyCode.G

local RouteHud = {}

local player = Players.LocalPlayer
local requestRemote: RemoteEvent
local screen: ScreenGui
local moneyLabel: TextLabel
local levelLabel: TextLabel
local xpFill: Frame
local chalkLabel: TextLabel
local runCard: Frame
local runRoute: TextLabel
local runGrade: TextLabel
local runTimer: TextLabel
local runFill: Frame
local runHeight: TextLabel
local ropeLine: TextButton
local notice: Frame
local noticeLabel: TextLabel
local noticeTween: Tween?
local summitCard: Frame
local summitTitle: TextLabel
local summitRoute: TextLabel
local summitTime: TextLabel
local summitBest: TextLabel
local summitMoney: TextLabel
local summitXp: TextLabel
local summitToken = 0
local chalkButton: TextButton
local chalkCooldown: Frame
local chalkReadyAt = 0

local function routesFolder(): Instance?
	return Workspace:FindFirstChild("Routes")
end

---------------------------------------------------------------------------------------
-- Building

local function buildStatus()
	local strip = Style.panel(screen, "Status", true)
	strip.Position = UDim2.fromOffset(12, 10)
	strip.Size = UDim2.fromOffset(196, 64)
	moneyLabel = Style.label(strip, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -90, 0, 30), Font = F.Display, TextSize = 22, Text = "£0" })
	levelLabel = Style.label(strip, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(70, 22), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Muted, TextSize = 15, Text = "LV 1" })
	local bar, fill = Style.bar(strip, 3)
	bar.Position = UDim2.new(0, 14, 0, 42)
	bar.Size = UDim2.new(1, -28, 0, 3)
	xpFill = fill
	chalkLabel = Style.label(strip, { Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 0, 14), TextSize = 12, TextColor3 = C.Muted, Text = "" })
end

local function buildRunCard()
	runCard = Style.panel(screen, "Run", true)
	runCard.AnchorPoint = Vector2.new(1, 0)
	runCard.Position = UDim2.new(1, -12, 0, 10)
	runCard.Size = UDim2.fromOffset(240, 86)
	runCard.Visible = false
	runRoute = Style.label(runCard, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -70, 0, 18), TextSize = 14, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd })
	runGrade = Style.label(runCard, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(50, 18), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 14, TextColor3 = C.Accent })
	runTimer = Style.label(runCard, { Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -28, 0, 30), Font = F.Display, TextSize = 24, Text = "0:00.00" })
	local bar, fill = Style.bar(runCard, 3)
	bar.Position = UDim2.new(0, 14, 0, 64)
	bar.Size = UDim2.new(1, -96, 0, 3)
	runFill = fill
	runHeight = Style.label(runCard, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 56), Size = UDim2.fromOffset(76, 18), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 13, TextColor3 = C.Muted })

	ropeLine = Instance.new("TextButton")
	ropeLine.Name = "Rope"
	ropeLine.AnchorPoint = Vector2.new(1, 0)
	ropeLine.Position = UDim2.new(1, -12, 0, 102)
	ropeLine.Size = UDim2.fromOffset(240, 26)
	ropeLine.BackgroundColor3 = C.Panel
	ropeLine.BackgroundTransparency = 0.06
	ropeLine.AutoButtonColor = false
	ropeLine.Font = F.Head
	ropeLine.TextSize = 13
	ropeLine.TextColor3 = C.Text
	ropeLine.RichText = true
	ropeLine.Visible = false
	Style.corner(ropeLine, 3)
	Style.stroke(ropeLine, C.Rope, 0.2)
	ropeLine.Parent = screen
	ropeLine.Activated:Connect(function()
		local character = player.Character
		if character and character:GetAttribute("TiedIn") ~= nil and character:GetAttribute("Climbing") ~= true then
			requestRemote:FireServer("Untie")
		end
	end)
end

local function buildNotice()
	notice = Style.panel(screen, "Notice", true)
	notice.AnchorPoint = Vector2.new(0.5, 0)
	notice.Position = UDim2.new(0.5, 0, 0, 96)
	notice.Size = UDim2.fromOffset(420, 32)
	notice.Visible = false
	noticeLabel = Style.label(notice, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 15, RichText = true })
end

local function buildSummitCard()
	summitCard = Style.panel(screen, "Summit", true)
	summitCard.AnchorPoint = Vector2.new(0.5, 0.5)
	summitCard.Position = UDim2.fromScale(0.5, 0.42)
	summitCard.Size = UDim2.fromOffset(360, 256)
	summitCard.Visible = false
	summitTitle = Style.label(summitCard, { Position = UDim2.fromOffset(22, 16), Size = UDim2.new(1, -44, 0, 32), Font = F.Display, TextSize = 26, TextColor3 = C.Accent, Text = "SUMMIT" })
	summitRoute = Style.label(summitCard, { Position = UDim2.fromOffset(22, 50), Size = UDim2.new(1, -44, 0, 20), TextSize = 15, TextColor3 = C.Muted, RichText = true })
	summitTime = Style.label(summitCard, { Position = UDim2.fromOffset(22, 76), Size = UDim2.new(1, -44, 0, 40), Font = F.Display, TextSize = 32 })
	summitBest = Style.label(summitCard, { Position = UDim2.fromOffset(22, 118), Size = UDim2.new(1, -44, 0, 18), Font = F.Body, TextSize = 14, TextColor3 = C.Muted, RichText = true })
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = C.Line
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(22, 146)
	divider.Size = UDim2.new(1, -44, 0, 1)
	divider.Parent = summitCard
	summitMoney = Style.label(summitCard, { Position = UDim2.fromOffset(22, 154), Size = UDim2.new(0.5, -22, 0, 30), Font = F.Display, TextSize = 20, TextColor3 = C.Good })
	summitXp = Style.label(summitCard, { Position = UDim2.new(0.5, 0, 0, 154), Size = UDim2.new(0.5, -22, 0, 30), Font = F.Display, TextSize = 20, TextColor3 = C.Text })
	local retry = Style.button(summitCard, "Retry", "primary")
	retry.Position = UDim2.new(0, 22, 1, -56)
	retry.Size = UDim2.new(0.5, -28, 0, 38)
	retry.Activated:Connect(function()
		summitCard.Visible = false
		requestRemote:FireServer("Retry")
	end)
	local close = Style.button(summitCard, "Close", "ghost")
	close.Position = UDim2.new(0.5, 6, 1, -56)
	close.Size = UDim2.new(0.5, -28, 0, 38)
	close.Activated:Connect(function()
		summitCard.Visible = false
	end)
end

local function chalkUp()
	local now = os.clock()
	if now < chalkReadyAt then
		return
	end
	chalkReadyAt = now + Config.Chalk.BagCooldown
	requestRemote:FireServer("Chalk")
end

local function buildChalkButton()
	chalkButton = Style.button(screen, "Chalk up", "ghost")
	chalkButton.Name = "ChalkUp"
	chalkButton.AnchorPoint = Vector2.new(1, 1)
	chalkButton.Position = UDim2.new(1, -12, 1, -12)
	chalkButton.Size = UDim2.fromOffset(146, 38)
	chalkButton.TextXAlignment = Enum.TextXAlignment.Left
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.Parent = chalkButton
	local key = Style.keycap(chalkButton, "G")
	key.AnchorPoint = Vector2.new(1, 0.5)
	key.Position = UDim2.new(1, -8, 0.5, 0)
	-- Cooldown: a fill that drains across the button.
	chalkCooldown = Instance.new("Frame")
	chalkCooldown.Name = "Cooldown"
	chalkCooldown.BackgroundColor3 = C.Accent
	chalkCooldown.BackgroundTransparency = 0.8
	chalkCooldown.BorderSizePixel = 0
	chalkCooldown.Size = UDim2.fromScale(0, 1)
	chalkCooldown.Position = UDim2.fromOffset(-12, 0)
	chalkCooldown.Parent = chalkButton
	chalkButton.Activated:Connect(chalkUp)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == CHALK_KEY then
			chalkUp()
		end
	end)
end

---------------------------------------------------------------------------------------
-- Updating

function RouteHud.notice(message: string, color: Color3?)
	if noticeTween then
		noticeTween:Cancel()
	end
	noticeLabel.Text = message
	noticeLabel.TextColor3 = color or C.Text
	noticeLabel.TextTransparency = 0
	notice.BackgroundTransparency = 0.06
	notice.Visible = true
	notice.Size = UDim2.fromOffset(math.clamp(#message * 8 + 48, 220, 560), 32)
	local tween = TweenService:Create(noticeLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 3), { TextTransparency = 1 })
	noticeTween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			notice.Visible = false
		end
	end)
	tween:Play()
end

local function updateStatus()
	moneyLabel.Text = Style.money(player:GetAttribute("Gems"))
	local level = player:GetAttribute("Level")
	local lv = if type(level) == "number" then level else 1
	levelLabel.Text = `LV {lv}`
	-- XP for level n starts at 100 * (n-1)^2 (DataService.levelFor).
	local from, to = 100 * (lv - 1) ^ 2, 100 * lv ^ 2
	local xp = player:GetAttribute("XP")
	local value = if type(xp) == "number" then xp else 0
	xpFill.Size = UDim2.fromScale(math.clamp((value - from) / (to - from), 0, 1), 1)
end

local function showSummit(result: any)
	if type(result) ~= "table" then
		return
	end
	summitToken += 1
	local token = summitToken
	summitTitle.Text = if result.newBest and result.best then "NEW BEST" else "SUMMIT"
	summitRoute.Text = `{string.upper(tostring(result.routeName))}  <font color="#FF7A30">{result.grade}</font>  ·  {result.meters} M`
	summitTime.Text = Style.time(result.seconds)
	local lines = {}
	if result.best then
		table.insert(lines, `Previous best {Style.time(result.best)}`)
	elseif result.firstClear then
		table.insert(lines, "First ascent")
	end
	if result.rank then
		table.insert(lines, `<font color="#FF7A30">#{result.rank} on the leaderboard</font>`)
	end
	summitBest.Text = table.concat(lines, "   ·   ")
	summitMoney.Text = `+{Style.money(result.gems)}`
	summitXp.Text = `+{result.xp} XP`
	summitCard.Visible = true
	summitCard.Position = UDim2.fromScale(0.5, 0.46)
	TweenService:Create(summitCard, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.42) }):Play()
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
		RouteHud.notice(`{b}. Run over.`, C.Bad)
	elseif kind == "Notice" and type(a) == "string" then
		RouteHud.notice(a, C.Text)
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
	if route and type(started) == "number" and root and ClientSettings.get("RunTimer") then
		runCard.Visible = true
		runRoute.Text = string.upper(tostring(route:GetAttribute("RouteName")))
		runGrade.Text = tostring(route:GetAttribute("Grade"))
		runTimer.Text = Style.time(math.max(0, Workspace:GetServerTimeNow() - started))
		local baseY = tonumber(route:GetAttribute("BaseY")) or 0
		local rise = tonumber(route:GetAttribute("HeightStuds")) or 1
		local fraction = math.clamp((root.Position.Y - 3 - baseY) / rise, 0, 1)
		runFill.Size = UDim2.fromScale(fraction, 1)
		runHeight.Text = `{math.floor(Config.studsToMeters(fraction * rise))} / {route:GetAttribute("HeightMeters")} M`
	else
		runCard.Visible = false
	end

	-- Rope line, only while tied in.
	local tied = character and character:GetAttribute("TiedIn")
	if character and root and type(tied) == "string" then
		local tiedRoute = routes and routes:FindFirstChild(tied)
		local auto = tiedRoute ~= nil and tiedRoute:GetAttribute("AutoBelay") == true
		local mode = character:GetAttribute("RopeMode")
		local what = if auto then "AUTO-BELAY" else "TIED IN"
		local state = if mode == "Lowering" then "lowering you"
			elseif mode ~= nil then "holding you"
			elseif character:GetAttribute("Climbing") == true then "R to lower off"
			else "tap to unclip"
		ropeLine.Text = `<font color="#4096F0">ROPE</font>   {what}   <font color="#92959C">{state}</font>`
		ropeLine.Position = UDim2.new(1, -12, 0, if runCard.Visible then 102 else 10)
		ropeLine.Visible = true
	else
		ropeLine.Visible = false
	end

	-- Chalk left on your hands, and the chalk button's cooldown.
	local chalk = character and character:GetAttribute("Chalk")
	chalkLabel.Text = if type(chalk) == "number" and chalk > 0 then `CHALK  {math.ceil(chalk / Config.Chalk.Max * 100)}%` else "NO CHALK"
	chalkLabel.TextColor3 = if type(chalk) == "number" and chalk > 25 then C.Muted else C.Faint
	local hasBag = player:GetAttribute("Equip_ChalkBag") ~= nil
	chalkButton.Visible = hasBag and character ~= nil
	local left = math.max(0, chalkReadyAt - os.clock())
	chalkCooldown.Size = UDim2.new(left / Config.Chalk.BagCooldown, 12, 1, 0)
end

function RouteHud.Init()
	screen = Instance.new("ScreenGui")
	screen.Name = "RouteHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 5
	buildStatus()
	buildRunCard()
	buildNotice()
	buildSummitCard()
	buildChalkButton()
	screen.Parent = player:WaitForChild("PlayerGui")
end

function RouteHud.Start()
	requestRemote = Remotes.event("RouteRequest")
	Remotes.event("RouteEvent").OnClientEvent:Connect(onRouteEvent)
	for _, name in { "Gems", "XP", "Level" } do
		player:GetAttributeChangedSignal(name):Connect(updateStatus)
	end
	updateStatus()
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
