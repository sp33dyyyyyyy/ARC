-- Admin panel: pick a player, then ban / unban / send to plaza / give or take
-- a gamepass; send everyone to the plaza; send a game-wide announcement.
-- Every button only *asks* the server, which re-checks that you're an admin.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local AdminPanel = {}
AdminPanel.__index = AdminPanel

local RED = Color3.fromRGB(255, 80, 90)

local function section(parent: Instance, order: number, title: string, height: number): Frame
	local frame = C.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Card,
		Parent = parent,
	}, { C.corner(), C.stroke(nil, 1, 0.9), C.padding(14, 10) })
	C.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Title,
		Text = title,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	return frame
end

local function hlist(parent: Instance, y: number, height: number): Frame
	return C.new("Frame", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		C.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
end

function AdminPanel.new(send: (action: string, args: { [string]: any }) -> ())
	local self = setmetatable({}, AdminPanel)
	local modal = C.modal("AdminPanel", "ADMIN PANEL", RED, Vector2.new(600, 640), 7)
	self.modal = modal
	self.selectedPass = nil :: string?

	local list = C.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = RED,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = modal.body,
	}, {
		C.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		C.new("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})

	-- Target player ----------------------------------------------------------------
	local target = section(list, 1, "PLAYER", 132)
	self.username = C.textbox({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 40),
		PlaceholderText = "Username (or tap a player below)",
		Parent = target,
	})
	self.playerChips = C.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = target,
	}, {
		C.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local function username(): string
		return (string.gsub(self.username.Text, "%s", ""))
	end

	-- Player actions -----------------------------------------------------------------
	local moderation = section(list, 2, "MODERATION", 136)
	self.reason = C.textbox({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 36),
		PlaceholderText = "Ban reason (optional)",
		TextSize = 14,
		Parent = moderation,
	})
	local modRow = hlist(moderation, 70, 44)
	C.button({ LayoutOrder = 1, Size = UDim2.fromOffset(160, 42), BackgroundColor3 = Color3.fromRGB(50, 110, 90), Text = "SEND TO PLAZA", TextSize = 14, Parent = modRow }, function()
		send("plaza", { username = username() })
	end)
	-- Ban needs a second click to confirm.
	local banArmedUntil = 0
	local banButton
	banButton = C.button({ LayoutOrder = 2, Size = UDim2.fromOffset(160, 42), BackgroundColor3 = RED, Text = "BAN", TextSize = 14, Parent = modRow }, function()
		local now = os.clock()
		if now < banArmedUntil then
			banArmedUntil = 0
			banButton.Text = "BAN"
			send("ban", { username = username(), reason = self.reason.Text })
		else
			banArmedUntil = now + 3
			banButton.Text = "CONFIRM BAN?"
			task.delay(3, function()
				if os.clock() >= banArmedUntil then
					banButton.Text = "BAN"
				end
			end)
		end
	end)
	C.button({ LayoutOrder = 3, Size = UDim2.fromOffset(160, 42), BackgroundColor3 = Theme.PanelLight, Text = "UNBAN", TextSize = 14, Parent = modRow }, function()
		send("unban", { username = username() })
	end)

	-- Gamepasses ---------------------------------------------------------------------
	local passes = section(list, 3, "GAMEPASSES  (player must be in this server)", 134)
	local passRow = hlist(passes, 24, 40)
	self.passChips = {}
	for i, pass in Config.GamePasses do
		local chip
		chip = C.button({ LayoutOrder = i, Size = UDim2.fromOffset(160, 38), BackgroundColor3 = Theme.PanelLight, Text = pass.Name, TextSize = 14, Parent = passRow }, function()
			self.selectedPass = pass.Id
			for id, other in self.passChips do
				other.BackgroundColor3 = if id == pass.Id then Theme.Accent else Theme.PanelLight
				other.TextColor3 = if id == pass.Id then Color3.fromRGB(30, 20, 0) else Theme.Text
			end
		end)
		self.passChips[pass.Id] = chip
	end
	local giveRow = hlist(passes, 72, 40)
	C.button({ LayoutOrder = 1, Size = UDim2.fromOffset(160, 38), BackgroundColor3 = Theme.Good, TextColor3 = Color3.fromRGB(15, 30, 20), Text = "GIVE FREE", TextSize = 14, Parent = giveRow }, function()
		send("givePass", { username = username(), passId = self.selectedPass })
	end)
	C.button({ LayoutOrder = 2, Size = UDim2.fromOffset(160, 38), BackgroundColor3 = Theme.PanelLight, Text = "TAKE AWAY", TextSize = 14, Parent = giveRow }, function()
		send("takePass", { username = username(), passId = self.selectedPass })
	end)

	-- Everyone -------------------------------------------------------------------------
	local everyone = section(list, 4, "EVERYONE", 184)
	self.announcement = C.textbox({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 70),
		PlaceholderText = "Game-wide announcement (sent to every server)",
		TextSize = 15,
		TextWrapped = true,
		MultiLine = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = everyone,
	})
	local allRow = hlist(everyone, 106, 44)
	C.button({ LayoutOrder = 1, Size = UDim2.fromOffset(200, 42), BackgroundColor3 = Theme.Info, TextColor3 = Color3.fromRGB(10, 20, 40), Text = "SEND ANNOUNCEMENT", TextSize = 14, Parent = allRow }, function()
		local text = self.announcement.Text
		if #text > 0 then
			send("announce", { text = text })
		end
	end)
	C.button({ LayoutOrder = 2, Size = UDim2.fromOffset(200, 42), BackgroundColor3 = Color3.fromRGB(50, 110, 90), Text = "ALL TO PLAZA", TextSize = 14, Parent = allRow }, function()
		send("plaza", { all = true })
	end)

	-- Result line along the bottom.
	self.status = C.new("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Bold,
		Text = "Every action is checked by the server.",
		TextSize = 15,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = modal.body,
	})

	local function refreshPlayers()
		for _, child in self.playerChips:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for i, p in Players:GetPlayers() do
			C.button({
				LayoutOrder = i,
				Size = UDim2.fromOffset(math.max(80, #p.Name * 9 + 24), 32),
				BackgroundColor3 = Theme.PanelLight,
				Text = p.Name,
				TextSize = 13,
				Parent = self.playerChips,
			}, function()
				self.username.Text = p.Name
			end)
		end
	end
	Players.PlayerAdded:Connect(refreshPlayers)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshPlayers)
	end)
	refreshPlayers()
	return self
end

function AdminPanel:showResult(ok: boolean, text: string, action: string?)
	self.status.Text = text
	self.status.TextColor3 = if ok then Theme.Good else Theme.Bad
	if ok and action == "announce" then
		self.announcement.Text = ""
	end
end

function AdminPanel:open()
	self.modal.open()
end

function AdminPanel:close()
	self.modal.close()
end

return AdminPanel
