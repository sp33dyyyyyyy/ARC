-- Shop window: boost cards with level pips and a chalk card.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Shop = {}
Shop.__index = Shop

export type Handlers = {
	buyBoost: (id: string) -> (),
	buyChalk: () -> (),
	buyEmote: (id: string) -> (),
	buyPass: (id: string) -> (),
	equipEmote: (id: string) -> (),
}

local CARD_HEIGHT = 92

function Shop.new(handlers: Handlers)
	local self = setmetatable({}, Shop)
	self.cards = {}
	local player = Players.LocalPlayer

	local gui = C.new("ScreenGui", {
		Name = "Shop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local root = C.autoScale(gui)
	self.gui = gui

	-- Dim the world behind the window; clicking it closes the shop.
	local dim = C.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		Parent = root,
	})
	dim.Activated:Connect(function()
		self:close()
	end)

	local window = C.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 600),
		BackgroundTransparency = 0.04,
		Parent = root,
	}, { C.stroke(Theme.Accent, 2, 0.4) })
	self.windowScale = C.new("UIScale", { Parent = window })
	self.anim = C.animated(gui, window, dim)

	C.new("TextLabel", {
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.new(1, -100, 0, 36),
		Font = Theme.Title,
		Text = "GEAR & BOOSTS",
		TextSize = 30,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})
	self.balance = C.new("TextLabel", {
		Position = UDim2.fromOffset(24, 54),
		Size = UDim2.new(1, -100, 0, 22),
		Font = Theme.Bold,
		Text = "",
		TextSize = 17,
		TextColor3 = Theme.Good,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})
	C.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 18),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Color3.fromRGB(70, 40, 46),
		Text = "X",
		TextSize = 20,
		Parent = window,
	}, function()
		self:close()
	end)

	local list = C.new("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 90),
		Size = UDim2.new(1, -32, 1, -106),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = window,
	}, {
		C.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		C.new("UIPadding", { PaddingRight = UDim.new(0, 10) }),
	})

	local function card(order: number, title: string, desc: string, maxLevel: number?, onBuy: () -> ())
		local frame = C.new("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
			BackgroundColor3 = Theme.Card,
			Parent = list,
		}, { C.corner(), C.stroke(nil, 1, 0.9), C.padding(14, 12) })
		C.new("TextLabel", {
			Size = UDim2.new(1, -150, 0, 24),
			Font = Theme.Title,
			Text = title,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		C.new("TextLabel", {
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.new(1, -150, 0, 20),
			Font = Theme.Body,
			Text = desc,
			TextSize = 14,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Parent = frame,
		})
		local pips = {}
		local levelLabel
		if maxLevel then
			local row = C.new("Frame", {
				Position = UDim2.fromOffset(0, 52),
				Size = UDim2.new(1, -150, 0, 14),
				BackgroundTransparency = 1,
				Parent = frame,
			}, { C.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }) })
			for i = 1, maxLevel do
				pips[i] = C.new("Frame", {
					Size = UDim2.fromOffset(math.floor(220 / maxLevel) - 4, 10),
					BackgroundColor3 = Theme.PanelLight,
					Parent = row,
				}, { C.round() })
			end
		else
			levelLabel = C.new("TextLabel", {
				Position = UDim2.fromOffset(0, 50),
				Size = UDim2.new(1, -150, 0, 18),
				Font = Theme.Bold,
				Text = "",
				TextSize = 14,
				TextColor3 = Theme.Chalk,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = frame,
			})
		end
		local buy = C.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(130, 48),
			BackgroundColor3 = Theme.Good,
			TextColor3 = Color3.fromRGB(15, 30, 20),
			Text = "",
			TextSize = 18,
			Parent = frame,
		}, onBuy)
		return { frame = frame, pips = pips, buy = buy, levelLabel = levelLabel }
	end

	local function header(order: number, text: string)
		C.new("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 26),
			Font = Theme.Title,
			Text = text,
			TextSize = 18,
			TextColor3 = Theme.Accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = list,
		})
	end

	header(0, "BOOSTS")
	for i, def in Config.Boosts do
		self.cards[def.Id] = card(i, def.Name, def.Description, def.MaxLevel, function()
			handlers.buyBoost(def.Id)
		end)
	end
	header(100, "GEAR")
	self.chalkCard = card(101, "Climbing Chalk", "Use with C: halves stamina drain for 12s.", nil, handlers.buyChalk)

	-- Gamepasses (Robux).
	header(150, "GAMEPASSES")
	self.passCards = {}
	for i, pass in Config.GamePasses do
		self.passCards[pass.Id] = card(150 + i, pass.Name, pass.Description, nil, function()
			handlers.buyPass(pass.Id)
		end)
	end

	-- Emotes: buy, then pick which one plays automatically at every summit.
	header(200, "EMOTES  (G to use · the starred one plays at every summit)")
	self.emoteCards = {}
	self._owned = {}
	self._summit = ""
	for i, def in Config.Emotes do
		self.emoteCards[def.Id] = card(200 + i, def.Name, "Emote. Play it any time with G.", nil, function()
			if not self._owned[def.Id] then
				handlers.buyEmote(def.Id)
			elseif self._summit ~= def.Id then
				handlers.equipEmote(def.Id)
			end
		end)
	end
	return self
end

function Shop:refresh(cash: number, boosts: { [string]: number }, chalk: number, ownedEmotes: { string }, summitEmote: string, ownedPasses: { [string]: boolean })
	self.balance.Text = "Balance: $" .. Theme.formatNumber(cash)
	for _, def in Config.Boosts do
		local cardRef = self.cards[def.Id]
		local level = boosts[def.Id] or 0
		for i, pip in cardRef.pips do
			pip.BackgroundColor3 = if i <= level then Theme.Accent else Theme.PanelLight
		end
		local cost = Rules.boostCost(Config.Boosts, def.Id, level)
		if cost == nil then
			cardRef.buy.Text = "MAXED"
			cardRef.buy.BackgroundColor3 = Theme.PanelLight
			cardRef.buy.TextColor3 = Theme.Muted
		else
			cardRef.buy.Text = "$" .. Theme.formatNumber(cost)
			local affordable = cash >= cost
			cardRef.buy.BackgroundColor3 = if affordable then Theme.Good else Theme.PanelLight
			cardRef.buy.TextColor3 = if affordable then Color3.fromRGB(15, 30, 20) else Theme.Muted
		end
	end
	local full = chalk >= Config.Chalk.MaxHeld
	self.chalkCard.levelLabel.Text = string.format("In bag: %d / %d", chalk, Config.Chalk.MaxHeld)
	self.chalkCard.buy.Text = if full then "BAG FULL" else "$" .. Config.Chalk.Price
	local ok = not full and cash >= Config.Chalk.Price
	self.chalkCard.buy.BackgroundColor3 = if ok then Theme.Good else Theme.PanelLight
	self.chalkCard.buy.TextColor3 = if ok then Color3.fromRGB(15, 30, 20) else Theme.Muted

	for _, pass in Config.GamePasses do
		local cardRef = self.passCards[pass.Id]
		local owned = ownedPasses[pass.Id] == true
		cardRef.levelLabel.Text = if owned then "Owned" else "Gamepass"
		cardRef.levelLabel.TextColor3 = if owned then Theme.Good else Theme.Muted
		cardRef.buy.Text = if owned then "OWNED" else "R$ " .. pass.Robux
		cardRef.buy.BackgroundColor3 = if owned then Theme.PanelLight else Color3.fromRGB(0, 176, 111)
		cardRef.buy.TextColor3 = if owned then Theme.Good else Color3.new(1, 1, 1)
	end

	self._owned, self._summit = {}, summitEmote
	for _, id in ownedEmotes do
		self._owned[id] = true
	end
	for _, def in Config.Emotes do
		local cardRef = self.emoteCards[def.Id]
		local owned = self._owned[def.Id] == true
		local summit = owned and summitEmote == def.Id
		cardRef.levelLabel.Text = if summit then "★ Summit emote" elseif owned then "Owned" else (if def.Price == 0 then "Free" else "Not owned")
		cardRef.levelLabel.TextColor3 = if summit then Theme.Gold elseif owned then Theme.Good else Theme.Muted
		if summit then
			cardRef.buy.Text = "EQUIPPED"
			cardRef.buy.BackgroundColor3 = Theme.PanelLight
			cardRef.buy.TextColor3 = Theme.Gold
		elseif owned then
			cardRef.buy.Text = "SET SUMMIT"
			cardRef.buy.BackgroundColor3 = Theme.Info
			cardRef.buy.TextColor3 = Color3.fromRGB(10, 20, 40)
		else
			local affordable = cash >= def.Price
			cardRef.buy.Text = "$" .. Theme.formatNumber(def.Price)
			cardRef.buy.BackgroundColor3 = if affordable then Theme.Good else Theme.PanelLight
			cardRef.buy.TextColor3 = if affordable then Color3.fromRGB(15, 30, 20) else Theme.Muted
		end
	end
end

function Shop:isOpen(): boolean
	return self.anim.isOpen()
end

function Shop:open()
	self.anim.open()
end

function Shop:close()
	self.anim.close()
end

function Shop:toggle()
	if self:isOpen() then
		self:close()
	else
		self:open()
	end
end

return Shop
