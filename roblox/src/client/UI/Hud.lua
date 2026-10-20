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
	emotes: () -> (),
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

	-- Right: action buttons -------------------------------------------------------
	local column = C.new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(150, 380),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		C.new("UIListLayout", {
			Padding = UDim.new(0, 10),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local keyHints = not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled
	local function action(order: number, text: string, key: string, color: Color3, fn: () -> ())
		return C.button({
			LayoutOrder = order,
			Size = UDim2.fromOffset(150, 52),
			BackgroundColor3 = color,
			Text = if keyHints then string.format("%s  [%s]", text, key) else text,
			TextSize = 17,
			Parent = column,
		}, fn)
	end
	action(1, "SHOP", "B", Color3.fromRGB(200, 140, 20), actions.shop)
	self.chalkButton = action(2, "CHALK x0", "C", Color3.fromRGB(70, 80, 110), actions.chalk)
	self.letGoButton = action(3, "LET GO", "Q", Color3.fromRGB(70, 80, 110), actions.letGo)
	action(4, "RAGDOLL", "R", Color3.fromRGB(150, 60, 70), actions.ragdoll)
	action(5, "EMOTES", "G", Color3.fromRGB(120, 70, 160), actions.emotes)
	action(6, "TO PLAZA", "P", Color3.fromRGB(50, 110, 90), actions.plaza)

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
	self:_set("chalkCount", self.chalkButton, "Text", (self.chalkButton.Text:gsub("x%d+", "x" .. count)))
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

local WEATHER_TEXT = {
	Clear = { "Clear skies", Color3.fromRGB(255, 220, 120) },
	Fog = { "Fog rolling in", Color3.fromRGB(190, 200, 215) },
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

function Hud:toggleEmoteBar()
	self.emoteBar.Visible = not self.emoteBar.Visible
end

-- Highlight the LET GO button while you're on a wall.
function Hud:setClimbing(on: boolean)
	self:_set("climbing", self.letGoButton, "BackgroundColor3", if on then Color3.fromRGB(60, 130, 220) else Color3.fromRGB(70, 80, 110))
end

function Hud:setWind(text: string?)
	self.wind.Visible = text ~= nil
	if text then
		self.windText.Text = text
	end
end

return Hud
