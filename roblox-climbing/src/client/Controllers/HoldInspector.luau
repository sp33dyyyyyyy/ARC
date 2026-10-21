--!strict
-- HoldInspector (client): authoring/debug tool for Stage 1.
-- Point the mouse at a hold (or tap it on touch) to outline it and show a tooltip with its
-- id, type, quality and which limbs may use it. Press H to toggle.
-- Stage 2 builds the limb hover highlight (valid / out of reach) on the same raycast.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HoldUtil = require(Shared:WaitForChild("HoldUtil"))
local Tags = require(Shared:WaitForChild("Tags"))

local MAX_DISTANCE = 120
local ACCENT = Color3.fromRGB(120, 220, 210)

local HoldInspector = {}

local enabled = Config.Debug.HoldInspectorStartsOn
local highlight: Highlight
local billboard: BillboardGui
local label: TextLabel
local current: BasePart? = nil
local rayParams = RaycastParams.new()

local function buildVisuals()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	highlight = Instance.new("Highlight")
	highlight.Name = "HoldInspectorHighlight"
	highlight.FillTransparency = 0.65
	highlight.FillColor = ACCENT
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	-- Created by this LocalScript, so it only exists for this player.
	highlight.Parent = Workspace

	billboard = Instance.new("BillboardGui")
	billboard.Name = "HoldInspectorTooltip"
	billboard.Size = UDim2.fromOffset(220, 64)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(16, 24, 42)
	frame.BackgroundTransparency = 0.15
	frame.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 1
	stroke.Parent = frame

	label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 1, -8)
	label.Position = UDim2.fromOffset(8, 4)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = true
	label.Parent = frame
end

local function describe(info: HoldUtil.HoldInfo): string
	local function yesNo(ok: boolean): string
		return if ok then `<font color="#78dcd2">yes</font>` else `<font color="#ff6b6b">no</font>`
	end
	local role = if info.Role then `  <font color="#ffd24a">{string.upper(info.Role)}</font>` else ""
	local height = Config.studsToMeters(HoldUtil.getGripCFrame(info.Part).Position.Y)
	return `<b>{info.Type}</b>{role}  <font color="#9aa4b8">{info.Id or "?"}</font>\n`
		.. `Quality {string.format("%.2f", info.Quality)} · Hands {yesNo(info.HandOK)} · Feet {yesNo(info.FootOK)}\n`
		.. `<font color="#9aa4b8">{string.format("%.2f", height)} m up</font>`
end

local function show(part: BasePart?)
	if part == current then
		return
	end
	current = part
	local info = if part then HoldUtil.read(part) else nil
	if part and info then
		highlight.Adornee = part
		billboard.Adornee = part
		label.Text = describe(info)
	end
	highlight.Enabled = info ~= nil
	billboard.Enabled = info ~= nil
end

-- `point` is in viewport space (mouse) or, with `isScreenSpace`, screen space below the
-- top bar inset (touch input positions).
local function holdAtPoint(point: Vector2, isScreenSpace: boolean): BasePart?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local character = Players.LocalPlayer.Character
	rayParams.FilterDescendantsInstances = if character then { character } else {}
	local ray = if isScreenSpace
		then camera:ScreenPointToRay(point.X, point.Y)
		else camera:ViewportPointToRay(point.X, point.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * MAX_DISTANCE, rayParams)
	return if result then HoldUtil.findHold(result.Instance) else nil
end

function HoldInspector.Init()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	buildVisuals()
end

function HoldInspector.Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Config.Debug.HoldInspectorKey then
			enabled = not enabled
			if not enabled then
				show(nil)
			end
		elseif enabled and input.UserInputType == Enum.UserInputType.Touch then
			show(holdAtPoint(Vector2.new(input.Position.X, input.Position.Y), true))
		end
	end)

	RunService.RenderStepped:Connect(function()
		-- Touch-only devices have no hover; they inspect by tapping instead.
		if not enabled or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then
			return
		end
		show(holdAtPoint(UserInputService:GetMouseLocation(), false))
	end)

	-- With StreamingEnabled the hovered hold can stream out; drop it cleanly.
	CollectionService:GetInstanceRemovedSignal(Tags.Hold):Connect(function(instance)
		if instance == current then
			show(nil)
		end
	end)
end

return HoldInspector
