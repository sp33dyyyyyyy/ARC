-- Always-on HUD: climb counter, cash, stamina, height meter, action buttons,
-- wind warning. Setters only touch the UI when a value actually changes.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Hud = {}
Hud.__index = Hud

export type Actions = {
	shop: () -> (),
	chalk: () -> (),
	ragdoll: () -> (),
	plaza: () -> (),
	letGo: () -> (),
	clip: () -> (),
	unclip: () -> (),
	rappel: () -> (),
	emotes: () -> (),
	settings: () -> (),
}

local function label(props: { [string]: any }): TextLabel
	return C.new("TextLabel", props)
end

function Hud.new(actions: Actions)
	local self = setmetatable({}, Hud)
	self._cache = {}

	local gui = C.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = C.autoScale(gui)
	self.gui = gui

	-- Top centre: the climb counter ---------------------------------------------
	local climbsPanel = C.panel({
		Name = "Climbs",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(320, 64),
		Parent = root,
	}, { C.stroke(Theme.Accent, 2, 0.35) })
	self._climbScale = C.new("UIScale", { Parent = climbsPanel })
	self.climbs = label({
		Size = UDim2.new(1, 0, 0, 38),
		Position = UDim2.fromOffset(0, 6),
		Font = Theme.Title,
		Text = "Tower climbs: 0",
		TextSize = 28,
		Parent = climbsPanel,
	})
	self.subline = label({
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 42),
		Font = Theme.Body,
		Text = "Best height 0  ·  Streak 0",
		TextSize = 14,
		TextColor3 = Theme.Muted,
		Parent = climbsPanel,
	})

	-- Wind warning banner, under the counter.
	self.wind = C.panel({
		Name = "Wind",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(300, 36),
		BackgroundColor3 = Color3.fromRGB(40, 70, 120),
		Visible = false,
		Parent = root,
	})
	self.windText = label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Bold,
		TextSize = 17,
		Text = "",
		Parent = self.wind,
	})

	-- Top left: cash -------------------------------------------------------------
	local cashPanel = C.panel({
		Name = "Cash",
		Position = UDim2.fromOffset(16, 70),
		Size = UDim2.fromOffset(190, 48),
		Parent = root,
	})
	label({
		Size = UDim2.fromOffset(40, 48),
		Position = UDim2.fromOffset(6, 0),
		Font = Theme.Title,
		Text = "$",
		TextSize = 30,
		TextColor3 = Theme.Good,
		Parent = cashPanel,
	})
	self.cash = label({
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.fromOffset(40, 0),
		Font = Theme.Title,
		Text = "0",
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cashPanel,
	})
	self._cashScale = C.new("UIScale", { Parent = cashPanel })

	-- Weather pill under the cash.
	self.weatherPanel = C.panel({
		Name = "Weather",
		Position = UDim2.fromOffset(16, 126),
		Size = UDim2.fromOffset(190, 34),
		Parent = root,
	})
	self.weather = label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Bold,
		Text = "Clear skies",
		TextSize = 14,
		Parent = self.weatherPanel,
	})

	-- Settings button, bottom-left.
	C.button({
		Name = "SettingsButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -24),
		Size = UDim2.fromOffset(150, 46),
		BackgroundColor3 = Color3.fromRGB(45, 52, 72),
		Text = if not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then "SETTINGS  [O]" else "SETTINGS",
		TextSize = 16,
		Parent = root,
	}, actions.settings)

	-- Rope status under the weather.
	self.ropePanel = C.panel({
		Name = "Rope",
		Position = UDim2.fromOffset(16, 166),
		Size = UDim2.fromOffset(190, 34),
		Parent = root,
	})
	self.rope = label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Bold,
		Text = "Rope: not clipped",
		TextSize = 14,
		TextColor3 = Theme.Muted,
		Parent = self.ropePanel,
	})

	-- Emote bar above the stamina panel (toggled with G / the EMOTES button).
	self.emoteBar = C.new("Frame", {
		Name = "EmoteBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -114),
		Size = UDim2.fromOffset(640, 46),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	}, {
		C.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Left: altitude meter ---------------------------------------------------------
	local meter = C.panel({
		Name = "Altitude",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(150, 250),
		Parent = root,
	}, { C.padding(12) })
	label({
		Size = UDim2.new(1, 0, 0, 14),
		Font = Theme.Bold,
		Text = "ALTITUDE",
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = meter,
	})
	self.height = label({
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 16),
		Font = Theme.Title,
		Text = "0",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = meter,
	})
	self.towerName = label({
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.fromOffset(0, 54),
		Font = Theme.Bold,
		Text = "Plaza",
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = meter,
	})
	self.towerInfo = label({
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(0, 90),
		Font = Theme.Body,
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = meter,
	})
	local track = C.new("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0, 10, 1, -20),
		BackgroundColor3 = Theme.PanelLight,
		Parent = meter,
	}, { C.round() })
	self.progress = C.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Theme.Accent,
		Parent = track,
	}, { C.round(), C.gradient(Theme.Gold, Theme.AccentDark) })
	self.progressText = label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, 0),
		Size = UDim2.fromOffset(80, 16),
		Font = Theme.Bold,
		Text = "",
		TextSize = 13,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = meter,
	})

	-- Bottom centre: stamina --------------------------------------------------------
	local staminaPanel = C.panel({
		Name = "Stamina",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(480, 78),
		Parent = root,
	}, { C.padding(14, 10) })
	self.status = label({
		Size = UDim2.new(1, -110, 0, 20),
		Font = Theme.Bold,
		Text = "Ready to climb",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = staminaPanel,
	})
	self.staminaText = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(110, 20),
		Font = Theme.Bold,
		Text = "100 / 100",
		TextSize = 15,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = staminaPanel,
	})
	local bar = C.new("Frame", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = Theme.PanelLight,
		ClipsDescendants = true,
		Parent = staminaPanel,
	}, { C.round() })
	self.staminaFill = C.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.StaminaHigh,
		Parent = bar,
	}, { C.round(), C.gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)) })
	self.chalkGlow = C.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Chalk,
		BackgroundTransparency = 1,
		Parent = bar,
	}, { C.round() })
	self._barStroke = C.stroke(Theme.Bad, 2, 1)
	self._barStroke.Parent = bar

	-- Right edge: one CONTROLS tab instead of a column of buttons. It slides
	-- out a panel listing every control; each action row is also a button, so
	-- touch players can tap them. --------------------------------------------
	local keyHints = not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled
	self.controlsTab = C.button({
		Name = "ControlsTab",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(46, 170),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		Text = "",
		Parent = root,
	}, function()
		self:toggleControls()
	end)
	C.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(160, 30),
		Rotation = -90,
		Font = Theme.Title,
		Text = if keyHints then "CONTROLS  [H]" else "CONTROLS",
		TextSize = 17,
		TextColor3 = Theme.Accent,
		Parent = self.controlsTab,
	})
	self._tabStroke = self.controlsTab:FindFirstChildOfClass("UIStroke")

	local PANEL_W = 330
	self.controls = C.panel({
		Name = "Controls",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, PANEL_W + 20, 0.5, 0), -- hidden off-screen
		Size = UDim2.fromOffset(PANEL_W, 600),
		BackgroundTransparency = 0.06,
		Visible = false,
		Parent = root,
	}, { C.stroke(Theme.Accent, 2, 0.45) })
	self._controlsOpen = false
	self._controlsShown = UDim2.new(1, -56, 0.5, 0)
	self._controlsHidden = self.controls.Position
	C.new("Frame", {
		Size = UDim2.new(1, -24, 0, 3),
		Position = UDim2.fromOffset(12, 0),
		BackgroundColor3 = Theme.Accent,
		Parent = self.controls,
	}, { C.round() })
	label({
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -36, 0, 30),
		Font = Theme.Title,
		Text = "CONTROLS",
		TextSize = 24,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.controls,
	})
	label({
		Position = UDim2.fromOffset(18, 42),
		Size = UDim2.new(1, -36, 0, 16),
		Font = Theme.Body,
		Text = "Tap a row to use it.",
		TextSize = 13,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.controls,
	})
	local list = C.new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 66),
		Size = UDim2.new(1, -24, 1, -78),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = self.controls,
	}, {
		C.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		C.padding(2, 2),
	})
	self._rows = {}

	-- A key badge plus a description; with `fn` the whole row is a button.
	local function row(order: number, key: string, text: string, color: Color3?, fn: (() -> ())?): GuiObject
		local frame: GuiObject
		if fn then
			frame = C.button({
				LayoutOrder = order,
				Size = UDim2.new(1, -6, 0, 40),
				BackgroundColor3 = Theme.Card,
				Text = "",
				Parent = list,
			}, fn)
		else
			frame = C.new("Frame", {
				LayoutOrder = order,
				Size = UDim2.new(1, -6, 0, 40),
				BackgroundColor3 = Theme.PanelLight,
				BackgroundTransparency = 0.4,
				Parent = list,
			}, { C.corner(10) })
		end
		local badge = C.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(78, 28),
			BackgroundColor3 = color or Color3.fromRGB(58, 64, 84),
			Parent = frame,
		}, { C.corner(7), C.stroke(Color3.new(1, 1, 1), 1, 0.7) })
		label({
			Size = UDim2.fromScale(1, 1),
			Font = Theme.Title,
			Text = key,
			TextSize = 14,
			Parent = badge,
		})
		local text_ = label({
			Name = "Desc",
			Position = UDim2.fromOffset(94, 0),
			Size = UDim2.new(1, -102, 1, 0),
			Font = Theme.Bold,
			Text = text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		self._rows[order] = text_
		return frame
	end
	local function header(order: number, text: string)
		label({
			LayoutOrder = order,
			Size = UDim2.new(1, -6, 0, 22),
			Font = Theme.Title,
			Text = text,
			TextSize = 13,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = list,
		})
	end
	header(1, "CLIMBING")
	row(2, "W A S D", "Climb up / down, move sideways")
	row(3, "SPACE", "Grab a tower / dyno / catch the wall")
	self.letGoButton = row(4, "Q", "Let go", Color3.fromRGB(70, 80, 110), actions.letGo)
	self.clipButton = row(5, "F", "Clip your rope in", Color3.fromRGB(200, 90, 30), actions.clip)
	row(6, "X", "Unclip your rope", Color3.fromRGB(140, 70, 40), actions.unclip)
	row(7, "V", "Rappel down (Rappel Kit)", Color3.fromRGB(40, 120, 170), actions.rappel)
	self.chalkButton = row(8, "C", "Use chalk (x0)", Color3.fromRGB(150, 155, 175), actions.chalk)
	header(9, "EVERYTHING ELSE")
	row(10, "B", "Shop", Color3.fromRGB(200, 140, 20), actions.shop)
	row(11, "G", "Emotes", Color3.fromRGB(120, 70, 160), actions.emotes)
	row(12, "R", "Ragdoll / get up", Color3.fromRGB(150, 60, 70), actions.ragdoll)
	row(13, "P", "Back to the plaza", Color3.fromRGB(50, 110, 90), actions.plaza)
	row(14, "O", "Settings", Color3.fromRGB(70, 80, 110), actions.settings)
	row(15, "H", "Show / hide this list", Color3.fromRGB(70, 80, 110), function()
		self:toggleControls()
	end)

	-- Touch screens: the three climbing actions you need fast, shown only
	-- while you're on a wall.
	self.touchClimb = C.new("Frame", {
		Name = "TouchClimb",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -70, 1, -130),
		Size = UDim2.fromOffset(130, 156),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	}, { C.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	self._touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	for i, entry in { { "LET GO", Color3.fromRGB(60, 130, 220), actions.letGo }, { "CLIP ROPE", Color3.fromRGB(200, 90, 30), actions.clip }, { "RAPPEL", Color3.fromRGB(40, 120, 170), actions.rappel } } do
		C.button({
			LayoutOrder = i,
			Size = UDim2.fromOffset(130, 46),
			BackgroundColor3 = entry[2],
			Text = entry[1],
			TextSize = 16,
			Parent = self.touchClimb,
		}, entry[3])
	end

	-- A gentle pulse on the tab for the first few seconds so new players find it.
	task.spawn(function()
		for _ = 1, 3 do
			task.wait(1.2)
			local stroke = self._tabStroke :: UIStroke?
			if not stroke or self._controlsOpen then
				break
			end
			stroke.Color = Theme.Accent
			stroke.Transparency = 0.1
			stroke.Thickness = 3
			C.tween(stroke, 0.9, { Transparency = 0.8, Thickness = 1 })
		end
	end)

	return self
end

function Hud:_set(key: string, inst: Instance, prop: string, value: any)
	if self._cache[key] ~= value then
		self._cache[key] = value;
		(inst :: any)[prop] = value
	end
end

local function pop(scale: UIScale, amount: number)
	scale.Scale = amount
	C.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)
end

function Hud:setClimbs(n: number, animate: boolean?)
	self:_set("climbs", self.climbs, "Text", "Tower climbs: " .. Theme.formatNumber(n))
	if animate then
		pop(self._climbScale, 1.3)
	end
end

function Hud:setSubline(best: number, streak: number)
	self:_set("sub", self.subline, "Text", string.format("Best height %s  ·  Daily streak %d", Theme.formatNumber(best), streak))
end

function Hud:setCash(n: number)
	local text = Theme.formatNumber(n)
	if self._cache.cash ~= text then
		local up = (self._cache.cashValue or n) < n
		self._cache.cashValue = n
		self:_set("cash", self.cash, "Text", text)
		if up then
			pop(self._cashScale, 1.2)
		end
	end
end

function Hud:setChalk(count: number, activeFraction: number)
	self:_set("chalkCount", self._rows[8], "Text", string.format("Use chalk (x%d)", count))
	self:_set("chalkGlow", self.chalkGlow, "BackgroundTransparency", 1 - activeFraction * 0.45)
end

-- mode: "normal" | "fall" | "blackout" | "ragdoll"
function Hud:setStamina(current: number, max: number, dangerFraction: number, time: number)
	local frac = if max > 0 then current / max else 0
	self:_set("fill", self.staminaFill, "Size", UDim2.fromScale(math.clamp(frac, 0, 1), 1))
	local color = if frac < dangerFraction
		then Theme.StaminaLow
		elseif frac < 0.5 then Theme.StaminaMid:Lerp(Theme.StaminaLow, 1 - (frac - dangerFraction) / (0.5 - dangerFraction))
		else Theme.StaminaHigh:Lerp(Theme.StaminaMid, 1 - (frac - 0.5) / 0.5)
	self.staminaFill.BackgroundColor3 = color
	self:_set("stext", self.staminaText, "Text", string.format("%d / %d", math.floor(current + 0.5), max))
	-- Pulse the outline red when you're about to black out.
	local pulse = if frac < dangerFraction then 0.5 + 0.5 * math.sin(time * 10) else 1
	self._barStroke.Transparency = pulse
end

function Hud:setStatus(text: string, color: Color3?)
	self:_set("status", self.status, "Text", text)
	self:_set("statusColor", self.status, "TextColor3", color or Theme.Text)
end

function Hud:setAltitude(y: number, towerName: string?, towerInfo: string?, progress: number?)
	self:_set("height", self.height, "Text", Theme.formatNumber(math.max(0, y)) .. " studs")
	self:_set("tower", self.towerName, "Text", towerName or "Plaza")
	self:_set("towerInfo", self.towerInfo, "Text", towerInfo or "Walk to a tower to start a climb.")
	local p = math.clamp(progress or 0, 0, 1)
	self:_set("progress", self.progress, "Size", UDim2.fromScale(1, p))
	self:_set("progressText", self.progressText, "Text", if progress then string.format("%d%%", p * 100) else "")
end

-- kind: "carabiner" | "suction" | nil. canClip: a clip point is in reach.
function Hud:setRope(kind: any, canClip: boolean)
	local text, color
	if kind == "carabiner" then
		text, color = "Rope: clipped to beam", Theme.Good
	elseif kind == "suction" then
		text, color = "Rope: suction cup on", Theme.Good
	elseif canClip then
		text, color = "Rope: press F to clip in", Theme.Accent
	else
		text, color = "Rope: not clipped", Theme.Muted
	end
	self:_set("rope", self.rope, "Text", text)
	self:_set("ropeColor", self.rope, "TextColor3", color)
	self:_set("clipGlow", self.clipButton, "BackgroundColor3", if canClip then Color3.fromRGB(120, 70, 30) else Theme.Card)
end

local WEATHER_TEXT = {
	Clear = { "Clear skies", Color3.fromRGB(255, 220, 120) },
	Rain = { "Rain: walls slippery!", Color3.fromRGB(120, 180, 255) },
}

function Hud:setWeather(name: string)
	local entry = WEATHER_TEXT[name] or WEATHER_TEXT.Clear
	self.weather.Text = entry[1]
	self.weather.TextColor3 = entry[2]
end

-- Rebuild the emote bar from the owned emotes: { { id, name } }.
function Hud:setEmotes(emotes: { { id: string, name: string } }, onPlay: (id: string) -> ())
	for _, child in self.emoteBar:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for i, emote in emotes do
		C.button({
			LayoutOrder = i,
			Size = UDim2.fromOffset(84, 42),
			BackgroundColor3 = Color3.fromRGB(120, 70, 160),
			Text = emote.name,
			TextSize = 15,
			Parent = self.emoteBar,
		}, function()
			onPlay(emote.id)
		end)
	end
end

-- Emote bar: slides up and fades in, slides back down to close.
function Hud:toggleEmoteBar()
	local bar = self.emoteBar
	local home = UDim2.new(0.5, 0, 1, -114)
	self._emoteToken = (self._emoteToken or 0) + 1
	local mine = self._emoteToken
	if bar.Visible and not self._emoteClosing then
		self._emoteClosing = true
		C.click(0.85)
		C.tween(bar, 0.18, { Position = home + UDim2.fromOffset(0, 30) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.19, function()
			if self._emoteToken == mine then
				bar.Visible = false
				self._emoteClosing = false
			end
		end)
	else
		self._emoteClosing = false
		C.click(1.15)
		bar.Visible = true
		bar.Position = home + UDim2.fromOffset(0, 40)
		C.tween(bar, 0.3, { Position = home }, Enum.EasingStyle.Back)
		for i, child in bar:GetChildren() do
			local scale = child:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 0.6
				task.delay(i * 0.03, function()
					C.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				end)
			end
		end
	end
end

-- The CONTROLS panel slides in from the right edge (and back out).
function Hud:toggleControls()
	local panel = self.controls
	self._controlsOpen = not self._controlsOpen
	self._controlsToken = (self._controlsToken or 0) + 1
	local mine = self._controlsToken
	if self._controlsOpen then
		C.click(1.15)
		panel.Visible = true
		C.tween(panel, 0.35, { Position = self._controlsShown }, Enum.EasingStyle.Back)
		C.tween(self.controlsTab, 0.2, { BackgroundColor3 = Theme.AccentDark })
		-- Rows cascade in one after another.
		local rows = {}
		for _, child in panel:GetDescendants() do
			if child:IsA("GuiObject") and child.Parent and child.Parent:IsA("ScrollingFrame") then
				table.insert(rows, child)
			end
		end
		table.sort(rows, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i, rowFrame in rows do
			local scale = rowFrame:FindFirstChildOfClass("UIScale") or C.new("UIScale", { Parent = rowFrame })
			scale.Scale = 0.85
			task.delay(0.04 + i * 0.02, function()
				C.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
	else
		C.click(0.85)
		C.tween(panel, 0.22, { Position = self._controlsHidden }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		C.tween(self.controlsTab, 0.2, { BackgroundColor3 = Theme.Panel })
		task.delay(0.23, function()
			if self._controlsToken == mine then
				panel.Visible = false
			end
		end)
	end
end

-- Highlight the LET GO row while you're on a wall; show the touch climbing
-- buttons on phones/tablets.
function Hud:setClimbing(on: boolean)
	self:_set("climbing", self.letGoButton, "BackgroundColor3", if on then Color3.fromRGB(40, 70, 120) else Theme.Card)
	self:_set("touchClimb", self.touchClimb, "Visible", on and self._touch)
end

function Hud:setWind(text: string?)
	self.wind.Visible = text ~= nil
	if text then
		self.windText.Text = text
	end
end

return Hud
