-- Tiny declarative helpers so the UI code reads as layout, not boilerplate.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)

local C = {}

-- Keyboard click: every button press and every window/tab opening plays it.
-- Played locally (only you hear your own UI), with a little pitch variation
-- so rapid clicks sound like real keys rather than a loop.
local clickSound: Sound? = nil
local lastClick = 0
function C.click(pitch: number?)
	local now = os.clock()
	if now - lastClick < 0.03 then
		return -- one click per press, even when a press opens a window too
	end
	lastClick = now
	if not clickSound then
		local sound = Instance.new("Sound")
		sound.Name = "UIClick"
		sound.SoundId = Config.Sounds.UIClick
		sound.Volume = 0.45
		sound.Parent = SoundService
		clickSound = sound
	end
	local sound = clickSound :: Sound
	sound.PlaybackSpeed = (pitch or 1) * (0.95 + math.random() * 0.1)
	SoundService:PlayLocalSound(sound)
end

-- C.new("Frame", { Size = ... }, { child1, child2 })
function C.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		(inst :: GuiObject).BorderSizePixel = 0
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		(inst :: any).Font = Theme.Body;
		(inst :: any).TextColor3 = Theme.Text;
		(inst :: any).BackgroundTransparency = 1
	end
	local parent = nil
	for key, value in (props or {}) :: { [string]: any } do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	for _, child in (children or {}) :: { Instance } do
		child.Parent = inst
	end
	-- Text can never spill out of its box: labels and buttons shrink their text
	-- to fit (never above their normal size); text boxes clip what you type.
	-- Auto-sized text (toasts, banners) grows its box instead, so it's left alone.
	local p = props or {}
	if (inst:IsA("TextLabel") or inst:IsA("TextButton")) and p.TextScaled == nil and p.AutomaticSize == nil then
		local text = inst :: TextLabel
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = text.TextSize
		fit.MinTextSize = math.min(9, text.TextSize)
		fit.Parent = text
		text.TextScaled = true
	elseif inst:IsA("TextBox") then
		(inst :: TextBox).ClipsDescendants = true
	end
	inst.Parent = parent
	return inst
end

function C.corner(radius: number?): UICorner
	return C.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius) })
end

function C.round(): UICorner
	return C.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function C.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return C.new("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0.85,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function C.padding(x: number, y: number?): UIPadding
	return C.new("UIPadding", {
		PaddingLeft = UDim.new(0, x),
		PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y or x),
		PaddingBottom = UDim.new(0, y or x),
	})
end

function C.gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return C.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

-- Dark glass panel used for every HUD element.
function C.panel(props: { [string]: any }, children: { Instance }?): Frame
	local merged = {
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = Theme.PanelTransparency,
	}
	for k, v in props do
		merged[k] = v
	end
	local kids = { C.corner(), C.gradient(Color3.new(1, 1, 1), Color3.fromRGB(200, 205, 220)) }
	local hasStroke = false
	for _, child in (children or {}) :: { Instance } do
		hasStroke = hasStroke or child:IsA("UIStroke")
		table.insert(kids, child)
	end
	if not hasStroke then
		-- Only one UIStroke per object renders, so a custom one replaces the default.
		table.insert(kids, C.stroke())
	end
	return C.new("Frame", merged, kids)
end

function C.tween(inst: Instance, time: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals)
	tween:Play()
	return tween
end

-- Button with hover lift and press squash. `onClick` fires on activation.
function C.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local base = props.BackgroundColor3 or Theme.Card
	local merged = {
		BackgroundColor3 = base,
		BackgroundTransparency = 0,
		AutoButtonColor = false,
		Font = Theme.Bold,
		TextSize = 16,
	}
	for k, v in props do
		merged[k] = v
	end
	local scale = C.new("UIScale")
	local button = C.new("TextButton", merged, { C.corner(10), C.stroke(nil, 1, 0.8), scale })
	button.BackgroundTransparency = merged.BackgroundTransparency
	-- Hover lights up the outline. It doesn't grow the button (that pushed it
	-- and its text past panel edges) or recolour it (callers recolour buttons
	-- for affordable / maxed states).
	local outline = button:FindFirstChildOfClass("UIStroke") :: UIStroke
	button.MouseEnter:Connect(function()
		C.tween(outline, 0.15, { Transparency = 0.15, Thickness = 2 })
	end)
	button.MouseLeave:Connect(function()
		C.tween(outline, 0.15, { Transparency = 0.8, Thickness = 1 })
		C.tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		C.tween(scale, 0.08, { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		C.tween(scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		C.click()
		onClick()
	end)
	return button
end

-- Pill toggle switch. Calls onChange(newValue) when clicked; returns a setter.
function C.toggle(props: { [string]: any }, initial: boolean, onChange: (boolean) -> ()): (TextButton, (boolean) -> ())
	local value = initial
	local merged = {
		Size = UDim2.fromOffset(64, 32),
		BackgroundColor3 = Theme.PanelLight,
		AutoButtonColor = false,
		Text = "",
	}
	for k, v in props do
		merged[k] = v
	end
	local track = C.new("TextButton", merged, { C.round(), C.stroke(nil, 1, 0.8) })
	track.BackgroundTransparency = 0
	local knob = C.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	}, { C.round() })
	local function render(animate: boolean)
		local goals = {
			Position = if value then UDim2.new(1, -28, 0.5, 0) else UDim2.new(0, 4, 0.5, 0),
		}
		local color = if value then Theme.Good else Theme.PanelLight
		if animate then
			C.tween(knob, 0.2, goals, Enum.EasingStyle.Back)
			C.tween(track, 0.2, { BackgroundColor3 = color })
		else
			knob.Position = goals.Position
			track.BackgroundColor3 = color
		end
	end
	render(false)
	track.Activated:Connect(function()
		C.click(if value then 0.9 else 1.1)
		value = not value
		render(true)
		onChange(value)
	end)
	return track, function(v: boolean)
		if v ~= value then
			value = v
			render(true)
		end
	end
end

-- Dark rounded text box.
function C.textbox(props: { [string]: any }): TextBox
	local merged = {
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0,
		ClearTextOnFocus = false,
		Font = Theme.Bold,
		PlaceholderColor3 = Theme.Muted,
		Text = "",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		merged[k] = v
	end
	local box = C.new("TextBox", merged, { C.corner(10), C.stroke(nil, 1, 0.8), C.padding(12, 0) })
	box.BackgroundTransparency = merged.BackgroundTransparency
	return box
end

-- Opening / closing animation shared by every window: the backdrop fades in,
-- the window pops up from slightly small and low with a little overshoot, and
-- closing plays it in reverse before the gui is hidden.
export type Animated = { gui: ScreenGui, window: GuiObject, dim: GuiObject?, open: () -> (), close: () -> (), isOpen: () -> boolean }

function C.animated(gui: ScreenGui, window: GuiObject, dim: GuiObject?): Animated
	local scale = window:FindFirstChildOfClass("UIScale") or C.new("UIScale", { Parent = window })
	local home = window.Position
	local dimTarget = if dim then dim.BackgroundTransparency else 1
	local isOpen = false
	local token = 0
	local self: Animated
	local function open()
		if isOpen then
			return
		end
		isOpen = true
		token += 1
		C.click(1.15)
		gui.Enabled = true
		scale.Scale = 0.86
		window.Position = home + UDim2.fromOffset(0, 24)
		C.tween(scale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		C.tween(window, 0.32, { Position = home }, Enum.EasingStyle.Back)
		if dim then
			dim.BackgroundTransparency = 1
			C.tween(dim, 0.25, { BackgroundTransparency = dimTarget })
		end
	end
	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		token += 1
		local mine = token
		C.click(0.85)
		C.tween(scale, 0.16, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		C.tween(window, 0.16, { Position = home + UDim2.fromOffset(0, 16) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if dim then
			C.tween(dim, 0.16, { BackgroundTransparency = 1 })
		end
		task.delay(0.17, function()
			if token == mine then
				gui.Enabled = false
				window.Position = home
			end
		end)
	end
	self = {
		gui = gui,
		window = window,
		dim = dim,
		open = open,
		close = close,
		isOpen = function()
			return isOpen
		end,
	}
	return self
end

export type Modal = { gui: ScreenGui, window: Frame, body: Frame, open: () -> (), close: () -> (), isOpen: () -> boolean }

-- A centred window over a dimmed screen, with a title bar and close button.
-- Put content in `body`.
function C.modal(name: string, title: string, accent: Color3, size: Vector2, displayOrder: number): Modal
	local gui = C.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = displayOrder,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = C.autoScale(gui)
	local dim = C.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		Parent = root,
	})
	local window = C.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 0.04,
		Parent = root,
	}, { C.stroke(accent, 2, 0.35) })
	-- Accent strip along the top edge.
	C.new("Frame", {
		Size = UDim2.new(1, -24, 0, 3),
		Position = UDim2.fromOffset(12, 0),
		BackgroundColor3 = accent,
		Parent = window,
	}, { C.round() })
	C.new("TextLabel", {
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.new(1, -100, 0, 36),
		Font = Theme.Title,
		Text = title,
		TextSize = 28,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})
	local body = C.new("Frame", {
		Position = UDim2.fromOffset(24, 70),
		Size = UDim2.new(1, -48, 1, -88),
		BackgroundTransparency = 1,
		Parent = window,
	})
	local modal: Modal
	local anim = C.animated(gui, window, dim)
	local close, open = anim.close, anim.open
	C.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 16),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.fromRGB(70, 40, 46),
		Text = "X",
		TextSize = 18,
		Parent = window,
	}, close)
	dim.Activated:Connect(close)
	modal = {
		gui = gui,
		window = window,
		body = body,
		open = open,
		close = close,
		isOpen = anim.isOpen,
	}
	return modal
end

-- Returns a full-screen root frame whose contents scale with screen height, so
-- phones and 4K screens get the same layout. The frame is sized 1/scale and
-- then scaled by `scale`, so it always covers exactly the screen and children
-- anchored to its edges stay on the edges. Parent all UI to the returned frame.
function C.autoScale(gui: ScreenGui): Frame
	local root = C.new("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local scale = C.new("UIScale", { Parent = root })
	local camera = workspace.CurrentCamera
	local function update()
		local s = math.clamp(camera.ViewportSize.Y / 900, 0.6, 1.25)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
	return root
end

return C
