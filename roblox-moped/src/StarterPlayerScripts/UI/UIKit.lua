--[[
	UIKit  (ModuleScript, StarterPlayerScripts/UI)

	Tiny helpers so the UI scripts can build their interfaces in code.
	Why code and not StarterGui assets? ScreenGuis in StarterGui are re-created
	on every respawn; building them once from a LocalScript with
	ResetOnSpawn = false is simpler and keeps the whole UI in version control.
]]

local Players = game:GetService("Players")

local UIKit = {}

UIKit.theme = {
	bg = Color3.fromRGB(24, 26, 32),
	panel = Color3.fromRGB(36, 39, 47),
	panelLight = Color3.fromRGB(52, 56, 66),
	text = Color3.fromRGB(240, 240, 235),
	muted = Color3.fromRGB(160, 164, 172),
	accent = Color3.fromRGB(244, 184, 60),
	good = Color3.fromRGB(110, 200, 120),
	warn = Color3.fromRGB(235, 90, 80),
	info = Color3.fromRGB(120, 170, 230),
}

function UIKit.make(class: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	inst.Parent = parent
	return inst
end

function UIKit.corner(radius: number): UICorner
	return UIKit.make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function UIKit.padding(px: number): UIPadding
	return UIKit.make("UIPadding", {
		PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px),
	})
end

function UIKit.label(props: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		TextColor3 = UIKit.theme.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return UIKit.make("TextLabel", p)
end

function UIKit.button(props: { [string]: any }): TextButton
	local p = {
		BackgroundColor3 = UIKit.theme.panelLight,
		TextColor3 = UIKit.theme.text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		AutoButtonColor = true,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	local b = UIKit.make("TextButton", p)
	UIKit.corner(8).Parent = b
	return b
end

-- A horizontal bar with a fill. Returns frame, setFraction(f).
function UIKit.bar(props: { [string]: any }, fillColor: Color3)
	local frame = UIKit.make("Frame", {
		BackgroundColor3 = UIKit.theme.bg,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 10),
		Position = props.Position,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	UIKit.corner(5).Parent = frame
	local fill = UIKit.make("Frame", {
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	UIKit.corner(5).Parent = fill
	return frame, function(f: number, color: Color3?)
		fill.Size = UDim2.fromScale(math.clamp(f, 0, 1), 1)
		if color then
			fill.BackgroundColor3 = color
		end
	end
end

function UIKit.screenGui(name: string, order: number?): ScreenGui
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	return UIKit.make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = order or 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = pg,
	})
end

return UIKit
