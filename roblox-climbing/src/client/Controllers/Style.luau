--!strict
-- Style (client): the one look every screen uses. Flat, dark and sharp: near-black panels
-- with hairline borders and small corners, one orange accent, no emoji.
--   Display  Michroma          numbers, big titles
--   Head     Sarpanch          labels, buttons, headings (upper case)
--   Body     Builder Sans      descriptions
--   Key      Roboto Mono       key caps

local Style = {}

Style.Colors = table.freeze({
	Ink = Color3.fromRGB(11, 12, 14),
	Panel = Color3.fromRGB(19, 20, 23),
	Raised = Color3.fromRGB(30, 32, 36),
	Line = Color3.fromRGB(58, 61, 68),
	Text = Color3.fromRGB(238, 237, 233),
	Muted = Color3.fromRGB(146, 149, 156),
	Faint = Color3.fromRGB(96, 99, 106),
	Accent = Color3.fromRGB(255, 122, 48),
	Good = Color3.fromRGB(126, 222, 152),
	Bad = Color3.fromRGB(242, 108, 88),
	Rope = Color3.fromRGB(64, 150, 240),
})

Style.Fonts = table.freeze({
	Display = Enum.Font.Michroma,
	Head = Enum.Font.Sarpanch,
	Body = Enum.Font.BuilderSansMedium,
	Key = Enum.Font.RobotoMono,
})

local C = Style.Colors
local F = Style.Fonts

function Style.corner(instance: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 3)
	corner.Parent = instance
end

function Style.stroke(instance: GuiObject, color: Color3?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or C.Line
	stroke.Thickness = 1
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

-- A dark panel with a hairline border; `accent` adds an orange strip down its left edge.
function Style.panel(parent: Instance, name: string, accent: boolean?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = C.Panel
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	Style.corner(frame, 3)
	Style.stroke(frame)
	if accent then
		local strip = Instance.new("Frame")
		strip.Name = "Accent"
		strip.BackgroundColor3 = C.Accent
		strip.BorderSizePixel = 0
		strip.Size = UDim2.new(0, 2, 1, -10)
		strip.Position = UDim2.fromOffset(0, 5)
		strip.Parent = frame
	end
	frame.Parent = parent
	return frame
end

-- A text label. `props` overrides the defaults (Sarpanch, 15, light text, left aligned).
function Style.label(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = F.Head
	label.TextSize = 15
	label.TextColor3 = C.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

-- Never lets a single line of text run out of its box: it keeps its TextSize when it fits
-- and shrinks (down to 9 px) only when it doesn't. For buttons and fixed-width labels.
function Style.fit(object: GuiObject, minSize: number?)
	local text = object :: any
	local limit = object:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = text.TextSize
	limit.MinTextSize = minSize or 9
	limit.Parent = object
	text.TextScaled = true
end

export type ButtonKind = "primary" | "ghost" | "off"

-- A button: "primary" (orange), "ghost" (outlined) or "off" (greyed out).
function Style.button(parent: Instance, text: string, kind: ButtonKind?): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Font = F.Head
	button.TextSize = 15
	button.Text = string.upper(text)
	button.BorderSizePixel = 0
	Style.corner(button, 3)
	local style = kind or "primary"
	local base: Color3, hover: Color3
	if style == "primary" then
		base, hover = C.Accent, C.Accent:Lerp(Color3.new(1, 1, 1), 0.15)
		button.TextColor3 = C.Ink
		button.BackgroundColor3 = base
	elseif style == "ghost" then
		base, hover = C.Raised, C.Raised:Lerp(Color3.new(1, 1, 1), 0.08)
		button.TextColor3 = C.Text
		button.BackgroundColor3 = base
		Style.stroke(button)
	else
		base, hover = C.Raised, C.Raised
		button.TextColor3 = C.Faint
		button.BackgroundColor3 = base
	end
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, 6)
	inset.PaddingRight = UDim.new(0, 6)
	inset.Parent = button
	-- Fit after the caller sets TextSize: it's re-applied whenever TextSize changes.
	Style.fit(button)
	button:GetPropertyChangedSignal("TextSize"):Connect(function()
		if not button.TextScaled then
			return
		end
		local limit = button:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			limit.MaxTextSize = button.TextSize
		end
	end)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = hover
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = base
	end)
	button.Parent = parent
	return button
end

-- A key cap ("P", "SPACE"), for hints and the controls list.
function Style.keycap(parent: Instance, key: string, width: number?): TextLabel
	local cap = Style.label(parent, {
		Name = "Key",
		Size = UDim2.fromOffset(width or math.max(24, #key * 9 + 12), 22),
		Font = F.Key,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Raised,
		Text = key,
	})
	Style.corner(cap, 3)
	Style.stroke(cap)
	return cap
end

-- A thin progress bar; returns the bar and its fill (size the fill's X scale 0..1).
function Style.bar(parent: Instance, height: number?, color: Color3?): (Frame, Frame)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = C.Raised
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 0, height or 4)
	bar.Parent = parent
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color or C.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	return bar, fill
end

function Style.money(amount: any): string
	return `£{if type(amount) == "number" then math.floor(amount + 0.5) else 0}`
end

function Style.time(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
end

return table.freeze(Style)
