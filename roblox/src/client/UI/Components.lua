-- Tiny declarative helpers so the UI code reads as layout, not boilerplate.
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local C = {}

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
	-- Hover only scales: callers recolour buttons (affordable / maxed) and a
	-- colour tween back to the creation colour would undo that.
	button.MouseEnter:Connect(function()
		C.tween(scale, 0.15, { Scale = 1.05 })
	end)
	button.MouseLeave:Connect(function()
		C.tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		C.tween(scale, 0.08, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(function()
		C.tween(scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(onClick)
	return button
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
