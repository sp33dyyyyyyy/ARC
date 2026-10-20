-- Settings window: name tags, camera shake, and the admin code box.
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Settings = {}
Settings.__index = Settings

export type Handlers = {
	setNameTags: (boolean) -> (),
	setCameraShake: (boolean) -> (),
	submitCode: (string) -> (),
	openAdmin: () -> (),
}

local function row(parent: Instance, order: number, title: string, subtitle: string): Frame
	local frame = C.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Theme.Card,
		Parent = parent,
	}, { C.corner(), C.stroke(nil, 1, 0.9), C.padding(16, 10) })
	C.new("TextLabel", {
		Size = UDim2.new(1, -90, 0, 22),
		Font = Theme.Title,
		Text = title,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	C.new("TextLabel", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, -90, 0, 18),
		Font = Theme.Body,
		Text = subtitle,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	return frame
end

function Settings.new(handlers: Handlers)
	local self = setmetatable({}, Settings)
	local modal = C.modal("Settings", "SETTINGS", Theme.Info, Vector2.new(480, 450), 6)
	self.modal = modal
	local list = C.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = modal.body,
	}, { C.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local tags = row(list, 1, "Name tags", "Show names above other players")
	local _, setTags = C.toggle({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Parent = tags }, true, handlers.setNameTags)
	self.setNameTags = setTags

	local shake = row(list, 2, "Camera shake", "Shake on falls, landings and gusts")
	local _, setShake = C.toggle({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Parent = shake }, true, handlers.setCameraShake)
	self.setCameraShake = setShake

	-- Admin: code box until unlocked, then a button to the panel.
	local admin = C.new("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Theme.Card,
		Parent = list,
	}, { C.corner(), C.stroke(Theme.Bad, 1, 0.6), C.padding(16, 12) })
	C.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.Title,
		Text = "Admin",
		TextSize = 18,
		TextColor3 = Theme.Bad,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = admin,
	})
	self.codeBox = C.textbox({
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, -130, 0, 44),
		PlaceholderText = "Enter admin code",
		Parent = admin,
	})
	self.unlock = C.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 32),
		Size = UDim2.fromOffset(118, 44),
		BackgroundColor3 = Theme.Bad,
		Text = "UNLOCK",
		Parent = admin,
	}, function()
		local code = self.codeBox.Text
		if #code > 0 then
			handlers.submitCode(code)
		end
	end)
	self.codeBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and #self.codeBox.Text > 0 then
			handlers.submitCode(self.codeBox.Text)
		end
	end)
	self.openAdmin = C.button({
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Theme.Bad,
		Text = "OPEN ADMIN PANEL",
		Visible = false,
		Parent = admin,
	}, function()
		modal.close()
		handlers.openAdmin()
	end)
	self.adminStatus = C.new("TextLabel", {
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 36),
		Font = Theme.Body,
		Text = "Admins: enter your code to unlock the admin panel.",
		TextSize = 14,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = admin,
	})
	return self
end

function Settings:setAdmin(isAdmin: boolean)
	self.codeBox.Visible = not isAdmin
	self.unlock.Visible = not isAdmin
	self.openAdmin.Visible = isAdmin
	if isAdmin then
		self.adminStatus.Text = "You're an admin."
		self.adminStatus.TextColor3 = Theme.Good
	end
end

function Settings:showCodeResult(ok: boolean, text: string)
	self.adminStatus.Text = text
	self.adminStatus.TextColor3 = if ok then Theme.Good else Theme.Bad
	if not ok then
		self.codeBox.Text = ""
	end
end

function Settings:toggle()
	if self.modal.isOpen() then
		self.modal.close()
	else
		self.modal.open()
	end
end

return Settings
