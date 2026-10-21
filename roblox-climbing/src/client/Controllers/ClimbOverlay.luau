--!strict
-- ClimbOverlay (client): all on-screen feedback for climbing. No game logic here.
--   * hold markers while placing a limb (green = hands, teal = feet, red = out of reach)
--   * a ring on each hand/foot (white = holding, grey = free, yellow = selected/dragging)
--   * the drag dot under the cursor
--   * the dyno charge ellipse around the body and the aim marker
--   * the height pill (top centre) and short messages ("Out of reach")
-- Uses only built-in UI and adornments, so no uploaded images are needed.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClimbOverlay = {}

export type Marker = { position: Vector3, color: Color3, radius: number, transparency: number }

local folder: Folder
local screen: ScreenGui
local markerPool: { SphereHandleAdornment } = {}
local rings: { [string]: { gui: BillboardGui, stroke: UIStroke } } = {}
local dragDot: SphereHandleAdornment
local aimDot: SphereHandleAdornment
local dynoGui: BillboardGui
local dynoStroke: UIStroke
local heightPill: Frame
local heightLabel: TextLabel
local toastLabel: TextLabel
local hintLabel: TextLabel
local toastTween: Tween?

local function sphere(name: string): SphereHandleAdornment
	local s = Instance.new("SphereHandleAdornment")
	s.Name = name
	s.Adornee = Workspace.Terrain
	s.AlwaysOnTop = true
	s.ZIndex = 2
	s.Visible = false
	s.Parent = folder
	return s
end

local function rounded(instance: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = instance
end

function ClimbOverlay.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Adornments and billboards live in Workspace so they always render. This folder is
	-- created by the client, so it exists only for this player.
	folder = Instance.new("Folder")
	folder.Name = "ClimbOverlay"
	folder.Parent = Workspace

	screen = Instance.new("ScreenGui")
	screen.Name = "ClimbHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.Parent = playerGui

	-- Height pill, top centre (like the reference: "4.35").
	heightPill = Instance.new("Frame")
	heightPill.Name = "Height"
	heightPill.AnchorPoint = Vector2.new(0.5, 0)
	heightPill.Position = UDim2.new(0.5, 0, 0, 8)
	heightPill.Size = UDim2.fromOffset(120, 40)
	heightPill.BackgroundColor3 = Color3.fromRGB(230, 244, 240)
	heightPill.BackgroundTransparency = 0.1
	heightPill.Visible = false
	heightPill.Parent = screen
	rounded(heightPill, UDim.new(0, 12))
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(63, 209, 201)
	stroke.Thickness = 1.5
	stroke.Parent = heightPill
	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.Size = UDim2.new(1, 0, 0, 12)
	caption.Position = UDim2.fromOffset(0, 3)
	caption.Font = Enum.Font.GothamMedium
	caption.TextSize = 10
	caption.TextColor3 = Color3.fromRGB(90, 110, 120)
	caption.Text = "HEIGHT"
	caption.Parent = heightPill
	heightLabel = Instance.new("TextLabel")
	heightLabel.BackgroundTransparency = 1
	heightLabel.Size = UDim2.new(1, 0, 1, -14)
	heightLabel.Position = UDim2.fromOffset(0, 13)
	heightLabel.Font = Enum.Font.GothamBold
	heightLabel.TextSize = 18
	heightLabel.TextColor3 = Color3.fromRGB(20, 40, 50)
	heightLabel.Parent = heightPill

	toastLabel = Instance.new("TextLabel")
	toastLabel.Name = "Toast"
	toastLabel.AnchorPoint = Vector2.new(0.5, 0)
	toastLabel.Position = UDim2.new(0.5, 0, 0, 56)
	toastLabel.Size = UDim2.fromOffset(260, 30)
	toastLabel.BackgroundColor3 = Color3.fromRGB(16, 24, 42)
	toastLabel.BackgroundTransparency = 1
	toastLabel.TextTransparency = 1
	toastLabel.Font = Enum.Font.GothamMedium
	toastLabel.TextSize = 15
	toastLabel.TextColor3 = Color3.new(1, 1, 1)
	toastLabel.Parent = screen
	rounded(toastLabel, UDim.new(0, 10))

	-- How-to hint at the bottom of the screen.
	hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.AnchorPoint = Vector2.new(0.5, 1)
	hintLabel.Position = UDim2.new(0.5, 0, 1, -96)
	hintLabel.Size = UDim2.fromOffset(560, 34)
	hintLabel.BackgroundColor3 = Color3.fromRGB(16, 24, 42)
	hintLabel.BackgroundTransparency = 0.3
	hintLabel.Font = Enum.Font.GothamMedium
	hintLabel.TextSize = 15
	hintLabel.TextColor3 = Color3.new(1, 1, 1)
	hintLabel.RichText = true
	hintLabel.Visible = false
	hintLabel.Parent = screen
	rounded(hintLabel, UDim.new(0, 10))

	dragDot = sphere("DragDot")
	aimDot = sphere("AimDot")

	-- Dyno charge ellipse around the body (sized in studs, grows with charge).
	dynoGui = Instance.new("BillboardGui")
	dynoGui.Name = "DynoCharge"
	dynoGui.AlwaysOnTop = true
	dynoGui.LightInfluence = 0
	dynoGui.Enabled = false
	dynoGui.Parent = folder
	local ellipse = Instance.new("Frame")
	ellipse.Size = UDim2.fromScale(1, 1)
	ellipse.BackgroundTransparency = 1
	ellipse.Parent = dynoGui
	rounded(ellipse, UDim.new(1, 0))
	dynoStroke = Instance.new("UIStroke")
	dynoStroke.Thickness = 3
	dynoStroke.Color = Color3.new(1, 1, 1)
	dynoStroke.Parent = ellipse
end

-- Show exactly these markers (reuses adornments).
function ClimbOverlay.setMarkers(markers: { Marker })
	for i, marker in markers do
		if i > #markerPool then
			table.insert(markerPool, sphere("HoldMarker"))
		end
		local s = markerPool[i]
		s.CFrame = CFrame.new(marker.position)
		s.Radius = marker.radius
		s.Color3 = marker.color
		s.Transparency = marker.transparency
		s.Visible = true
	end
	for i = #markers + 1, #markerPool do
		markerPool[i].Visible = false
	end
end

-- Ring on a hand/foot (`at` is the part or attachment). Pass nil `at` (or color) to hide it.
function ClimbOverlay.setLimbRing(limb: string, at: Instance?, color: Color3?, big: boolean?)
	local ring = rings[limb]
	if ring == nil then
		local gui = Instance.new("BillboardGui")
		gui.Name = `Ring_{limb}`
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Parent = folder
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = gui
		rounded(frame, UDim.new(1, 0))
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Parent = frame
		ring = { gui = gui, stroke = stroke }
		rings[limb] = ring
	end
	if at == nil or color == nil then
		ring.gui.Enabled = false
		return
	end
	ring.gui.Adornee = at
	ring.gui.Size = if big then UDim2.fromOffset(40, 40) else UDim2.fromOffset(28, 28)
	ring.stroke.Color = color
	ring.stroke.Thickness = if big then 4 else 2.5
	ring.gui.Enabled = true
end

function ClimbOverlay.setDragDot(position: Vector3?, color: Color3?)
	if position == nil then
		dragDot.Visible = false
		return
	end
	dragDot.CFrame = CFrame.new(position)
	dragDot.Radius = 0.22
	dragDot.Color3 = color or Color3.new(1, 1, 1)
	dragDot.Transparency = 0.1
	dragDot.Visible = true
end

-- Dyno charge 0..1 around `root`, aiming at `aim` (dot in `aimColor`, white if nil).
-- nil root hides it.
function ClimbOverlay.setDyno(root: BasePart?, charge: number?, aim: Vector3?, aimColor: Color3?)
	if root == nil or charge == nil then
		dynoGui.Enabled = false
		aimDot.Visible = false
		return
	end
	dynoGui.Adornee = root
	dynoGui.Size = UDim2.fromScale(2.5 + 3 * charge, 1.2 + 1.5 * charge)
	dynoStroke.Color = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 214, 64), charge)
	dynoGui.Enabled = true
	if aim then
		aimDot.CFrame = CFrame.new(aim)
		aimDot.Radius = 0.3
		aimDot.Color3 = aimColor or Color3.new(1, 1, 1)
		aimDot.Transparency = 0.2
		aimDot.Visible = true
	else
		aimDot.Visible = false
	end
end

function ClimbOverlay.setHeight(meters: number?)
	heightPill.Visible = meters ~= nil
	if meters then
		heightLabel.Text = string.format("%.2f m", meters)
	end
end

-- Bottom-of-screen hint (rich text). nil hides it.
function ClimbOverlay.setHint(text: string?)
	hintLabel.Visible = text ~= nil
	if text and hintLabel.Text ~= text then
		hintLabel.Text = text
	end
end

function ClimbOverlay.toast(text: string)
	if toastTween then
		toastTween:Cancel()
	end
	toastLabel.Text = text
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.25
	local tween = TweenService:Create(toastLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.0), {
		TextTransparency = 1,
		BackgroundTransparency = 1,
	})
	toastTween = tween
	tween:Play()
end

return ClimbOverlay
