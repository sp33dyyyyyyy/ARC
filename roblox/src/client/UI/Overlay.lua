-- Full-screen moments: blackout, summit celebration, hurt flash, toasts.
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Overlay = {}
Overlay.__index = Overlay

local BLACKOUT_TIPS = {
	"Tip: hang still on a yellow rest bar to get your breath back.",
	"Tip: Endurance boosts let you climb further without resting.",
	"Tip: chalk halves stamina drain for a while. Press C.",
	"Tip: skyscraper glass is slippery. Sticky Gloves help.",
	"Tip: holding on between rest bars still costs stamina.",
	"Tip: press SPACE while falling to catch the wall.",
	"Tip: leaping is fast but costs more stamina than climbing.",
	"Tip: wind gusts can blow tired climbers clean off.",
}

function Overlay.new()
	local self = setmetatable({}, Overlay)
	local gui = C.new("ScreenGui", {
		Name = "Overlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = C.autoScale(gui)
	self.gui = gui

	-- Red edge flash when hurt.
	self.hurtFrame = C.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bad,
		BackgroundTransparency = 1,
		Parent = root,
	})

	-- Blackout.
	self.black = C.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = root,
	})
	self.blackTitle = C.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(700, 70),
		Font = Theme.Title,
		Text = "YOU BLACKED OUT",
		TextSize = 54,
		TextTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})
	self.blackTip = C.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(700, 30),
		Font = Theme.Body,
		Text = "",
		TextSize = 20,
		TextColor3 = Theme.Muted,
		TextTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})

	-- Summit banner.
	self.summit = C.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(520, 150),
		Visible = false,
		ZIndex = 3,
		Parent = root,
	}, { C.stroke(Theme.Gold, 3, 0) })
	self.summitScale = C.new("UIScale", { Parent = self.summit })
	self.summitTitle = C.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.fromOffset(0, 10),
		Font = Theme.Title,
		Text = "SUMMIT!",
		TextSize = 60,
		TextColor3 = Theme.Gold,
		ZIndex = 4,
		Parent = self.summit,
	})
	self.summitSub = C.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 80),
		Font = Theme.Bold,
		Text = "",
		TextSize = 24,
		TextColor3 = Theme.Good,
		ZIndex = 4,
		Parent = self.summit,
	})
	self.summitSub2 = C.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 112),
		Font = Theme.Body,
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.Text,
		ZIndex = 4,
		Parent = self.summit,
	})

	-- Toast stack, top right under the Roblox menu.
	self.toasts = C.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 70),
		Size = UDim2.fromOffset(340, 400),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		C.new("UIListLayout", {
			Padding = UDim.new(0, 8),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- Game-wide announcement banner.
	self.announce = C.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(640, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 8,
		Parent = root,
	}, { C.stroke(Theme.Info, 2, 0.2), C.padding(18, 12) })
	self.announceScale = C.new("UIScale", { Parent = self.announce })
	self.announceFrom = C.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Title,
		Text = "",
		TextSize = 14,
		TextColor3 = Theme.Info,
		ZIndex = 9,
		Parent = self.announce,
	})
	self.announceText = C.new("TextLabel", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Bold,
		Text = "",
		TextSize = 22,
		TextWrapped = true,
		ZIndex = 9,
		Parent = self.announce,
	})
	self._announceToken = 0
	self._toastOrder = 0
	self._summitToken = 0
	return self
end

function Overlay:blackout(on: boolean)
	local t = if on then 0.35 else 0.8
	C.tween(self.black, t, { BackgroundTransparency = if on then 0.05 else 1 }, Enum.EasingStyle.Sine)
	C.tween(self.blackTitle, t, { TextTransparency = if on then 0 else 1 })
	C.tween(self.blackTip, t, { TextTransparency = if on then 0 else 1 })
	if on then
		self.blackTip.Text = BLACKOUT_TIPS[math.random(1, #BLACKOUT_TIPS)]
	end
end

function Overlay:hurtFlash(damage: number)
	self.hurtFrame.BackgroundTransparency = math.clamp(0.9 - damage / 150, 0.45, 0.9)
	C.tween(self.hurtFrame, 0.8, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
end

function Overlay:showSummit(tower: string, payout: number, climbs: number)
	self._summitToken += 1
	local token = self._summitToken
	self.summitSub.Text = string.format("%s conquered  ·  +$%s", tower, Theme.formatNumber(payout))
	self.summitSub2.Text = "Tower climbs: " .. Theme.formatNumber(climbs)
	self.summit.Visible = true
	self.summitScale.Scale = 0.3
	C.tween(self.summitScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3.5, function()
		if self._summitToken == token then
			C.tween(self.summitScale, 0.25, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
			if self._summitToken == token then
				self.summit.Visible = false
			end
		end
	end)
end

function Overlay:announcement(text: string, from: string)
	self._announceToken += 1
	local token = self._announceToken
	self.announceFrom.Text = "ANNOUNCEMENT  ·  " .. string.upper(from)
	self.announceText.Text = text
	self.announce.Visible = true
	self.announceScale.Scale = 0.6
	C.tween(self.announceScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(8, function()
		if self._announceToken == token then
			self.announce.Visible = false
		end
	end)
end

function Overlay:toast(text: string, style: string?)
	self._toastOrder += 1
	local color = Theme.styleColor(style)
	local card = C.panel({
		LayoutOrder = self._toastOrder,
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self.toasts,
	}, { C.padding(14, 10), C.stroke(color, 1.5, 0.3) })
	C.new("Frame", {
		Size = UDim2.new(0, 4, 1, 0),
		Position = UDim2.fromOffset(-8, 0),
		BackgroundColor3 = color,
		Parent = card,
	}, { C.round() })
	local textLabel = C.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Bold,
		Text = text,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local scale = C.new("UIScale", { Scale = 0.6, Parent = card })
	C.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	-- Keep at most five on screen.
	local cards = {}
	for _, child in self.toasts:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #cards - 5 do
		cards[i]:Destroy()
	end
	task.delay(4, function()
		if card.Parent then
			C.tween(card, 0.4, { BackgroundTransparency = 1 })
			C.tween(textLabel, 0.4, { TextTransparency = 1 }).Completed:Wait()
			card:Destroy()
		end
	end)
end

return Overlay
