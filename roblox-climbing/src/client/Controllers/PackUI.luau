--!strict
-- PackUI (client): your bag. No game logic: PackService checks and saves; this shows the
-- Player's Pack_* / Have_* / PackWeight / PackCapacity attributes and sends requests.
--   * Packing window ("Pack bag" at the lockers): + / − for each item, the weight against
--     your bag's capacity, Pack to save it.
--   * Hotbar (bottom centre, keys 1-5): what you're carrying.
--       Rope, Crash pad, Chalk bag: pick one and a preview follows the mouse; click to put
--       it down (green = OK), right-click or Esc to cancel.
--       Quickdraws: clip one in beside your top hand (lead routes).
--       Water: drink.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pack = require(Shared.Pack)
local Remotes = require(Shared.Remotes)

local ClimbOverlay = require(script.Parent:WaitForChild("ClimbOverlay"))
local Style = require(script.Parent:WaitForChild("Style"))

local C = Style.Colors
local F = Style.Fonts
local ACTION_PLACE = "PackPlace"
local ACTION_CANCEL = "PackCancel"
local SLOT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
local CLOSE_DISTANCE = 16
local GHOST_SIZE: { [string]: Vector3 } = {
	Rope = Vector3.new(3.4, 1.2, 3.0),
	CrashPad = Vector3.new(4.2, 1.0, 3.3),
	Chalk = Vector3.new(1.2, 1.6, 1.2),
}

local PackUI = {}

local player = Players.LocalPlayer
local requestRemote: RemoteEvent
local screen: ScreenGui
local hotbar: Frame
local slots: { [string]: { frame: TextButton, count: TextLabel, label: TextLabel, key: TextLabel } } = {}
local window: Frame
local rows: { [string]: { count: TextLabel, minus: TextButton, plus: TextButton } } = {}
local weightLabel: TextLabel
local weightFill: Frame
local message: TextLabel
local draft: { [string]: number } = {}
local openedAt: Vector3?

-- Placing
local placing: string? = nil
local ghost: Part? = nil
local ghostOk = false
local ghostAt: Vector3? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function count(prefix: string, id: string): number
	local value = player:GetAttribute(`{prefix}_{id}`)
	return if type(value) == "number" then value else 0
end

---------------------------------------------------------------------------------------
-- Placing things on the ground

local function stopPlacing()
	placing = nil
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	ContextActionService:UnbindAction(ACTION_PLACE)
	ContextActionService:UnbindAction(ACTION_CANCEL)
end

local function startPlacing(id: string)
	stopPlacing()
	placing = id
	local part = Instance.new("Part")
	part.Name = "PackGhost"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.ForceField
	part.Size = GHOST_SIZE[id] or Vector3.new(2, 1, 2)
	part.Parent = Workspace.CurrentCamera
	ghost = part
	-- Clicks go to placing, not to grabbing holds.
	ContextActionService:BindActionAtPriority(ACTION_PLACE, function(_, state)
		if state == Enum.UserInputState.Begin and placing and ghostOk and ghostAt then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local facing = if root and root:IsA("BasePart") then ghostAt - root.Position else Vector3.zAxis
			requestRemote:FireServer("Place", placing, ghostAt, facing)
			stopPlacing()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority(ACTION_CANCEL, function(_, state)
		if state == Enum.UserInputState.Begin then
			stopPlacing()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.UserInputType.MouseButton2, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
end

local function updateGhost()
	local part = ghost
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if part == nil or placing == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		mouse = camera.ViewportSize / 2 -- touch: aim with the centre of the screen
	end
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local placed = Workspace:FindFirstChild("PlacedGear")
	rayParams.FilterDescendantsInstances = if placed then { character, placed, part } else { character, part }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
	if hit == nil then
		part.Transparency = 1
		ghostOk = false
		return
	end
	local at = hit.Position
	local flat = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.zAxis
	end
	ghostOk = hit.Normal.Y >= 0.75 and (at - root.Position).Magnitude <= Pack.PLACE_REACH and character:GetAttribute("Climbing") ~= true
	ghostAt = at
	part.Transparency = 0.25
	part.Color = if ghostOk then C.Good else C.Bad
	part.CFrame = CFrame.lookAt(at, at + flat.Unit) * CFrame.new(0, part.Size.Y / 2, 0)
end

local function use(id: string)
	local item = Pack.item(id)
	if item == nil then
		return
	end
	if count("Have", id) <= 0 then
		ClimbOverlay.toast(if count("Pack", id) > 0 then `No {string.lower(item.name)} left` else `No {string.lower(item.name)} packed. Pack your bag at the lockers`)
		return
	end
	if item.kind == "place" then
		if placing == id then
			stopPlacing()
		else
			startPlacing(id)
		end
	else
		stopPlacing()
		requestRemote:FireServer("Use", id)
	end
end

---------------------------------------------------------------------------------------
-- Hotbar

local function buildHotbar()
	hotbar = Instance.new("Frame")
	hotbar.Name = "Hotbar"
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.new(0.5, 0, 1, -12)
	hotbar.Size = UDim2.fromOffset(0, 56)
	hotbar.AutomaticSize = Enum.AutomaticSize.X
	hotbar.BackgroundTransparency = 1
	hotbar.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = hotbar
	for i, item in Pack.ITEMS do
		local frame = Instance.new("TextButton")
		frame.Name = item.id
		frame.LayoutOrder = i
		frame.Size = UDim2.fromOffset(64, 56)
		frame.BackgroundColor3 = C.Panel
		frame.BackgroundTransparency = 0.06
		frame.AutoButtonColor = false
		frame.Text = ""
		Style.corner(frame, 3)
		local stroke = Style.stroke(frame)
		stroke.Name = "Edge"
		frame.Parent = hotbar
		local key = Style.label(frame, { Name = "Key", Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(14, 14), Font = F.Key, TextSize = 11, TextColor3 = C.Faint, Text = tostring(i) })
		local countLabel = Style.label(frame, { Name = "Count", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 3), Size = UDim2.fromOffset(30, 16), Font = F.Display, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = "0" })
		local label = Style.label(frame, { Name = "Label", Position = UDim2.new(0, 4, 1, -24), Size = UDim2.new(1, -8, 0, 18), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = item.short })
		frame.Activated:Connect(function()
			use(item.id)
		end)
		slots[item.id] = { frame = frame, count = countLabel, label = label, key = key }
	end
end

local function refreshHotbar()
	local any = false
	for _, item in Pack.ITEMS do
		local slot = slots[item.id]
		local packedCount = count("Pack", item.id)
		local ready = count("Have", item.id)
		slot.frame.Visible = packedCount > 0
		any = any or packedCount > 0
		slot.count.Text = if item.max > 1 then `{ready}` else ""
		local live = ready > 0
		slot.label.TextColor3 = if live then C.Text else C.Faint
		slot.count.TextColor3 = if live then C.Text else C.Faint
		local edge = slot.frame:FindFirstChild("Edge") :: UIStroke?
		if edge then
			edge.Color = if placing == item.id then C.Accent else C.Line
		end
	end
	-- Out of the way while a window (shop, lockers, packing) is open.
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local modal = window.Visible
	if gui and not modal then
		for _, holder in gui:GetChildren() do
			for _, frame in holder:GetChildren() do
				if frame:IsA("GuiObject") and frame.Visible and frame:GetAttribute("Modal") == true then
					modal = true
				end
			end
		end
	end
	hotbar.Visible = any and not modal
end

---------------------------------------------------------------------------------------
-- Packing window

local function draftWeight(): number
	return Pack.weight(draft)
end

local function refreshWindow()
	local capacity = player:GetAttribute("PackCapacity")
	local cap = if type(capacity) == "number" then capacity else Pack.DEFAULT_CAPACITY
	local weight = draftWeight()
	for _, item in Pack.ITEMS do
		local row = rows[item.id]
		local n = draft[item.id] or 0
		row.count.Text = tostring(n)
		row.minus.TextColor3 = if n > 0 then C.Text else C.Faint
		row.plus.TextColor3 = if n < item.max and weight + item.weight <= cap then C.Text else C.Faint
	end
	weightLabel.Text = `WEIGHT  {weight} / {cap}`
	weightLabel.TextColor3 = if weight > cap then C.Bad else C.Muted
	weightFill.Size = UDim2.fromScale(math.clamp(weight / cap, 0, 1), 1)
	weightFill.BackgroundColor3 = if weight > cap then C.Bad else C.Accent
end

local function stepper(parent: Instance, text: string): TextButton
	local button = Style.button(parent, text, "ghost")
	button.Size = UDim2.fromOffset(30, 30)
	button.Font = F.Display
	button.TextSize = 16
	return button
end

local function buildWindow()
	window = Style.panel(screen, "PackWindow", true)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(520, 470)
	window.Visible = false
	-- Shrinks to fit small (phone) screens.
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local function fit()
		local camera = Workspace.CurrentCamera
		if camera then
			local inset = GuiService:GetGuiInset()
			scale.Scale = math.min(1, (camera.ViewportSize.X - 24) / 520, (camera.ViewportSize.Y - inset.Y - 24) / 470)
		end
	end
	fit()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	Style.label(window, { Position = UDim2.fromOffset(22, 14), Size = UDim2.new(1, -80, 0, 30), Font = F.Display, TextSize = 20, Text = "PACK YOUR BAG" })
	Style.label(window, { Position = UDim2.fromOffset(22, 44), Size = UDim2.new(1, -44, 0, 18), Font = F.Body, TextSize = 14, TextColor3 = C.Muted, Text = "Take what you need for the crags. A heavier pack tires you a bit faster." })
	local close = Style.button(window, "X", "ghost")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(30, 30)
	close.Activated:Connect(function()
		window.Visible = false
	end)

	for i, item in Pack.ITEMS do
		local y = 74 + (i - 1) * 64
		local row = Instance.new("Frame")
		row.Name = item.id
		row.Position = UDim2.fromOffset(22, y)
		row.Size = UDim2.new(1, -44, 0, 56)
		row.BackgroundColor3 = C.Raised
		row.BorderSizePixel = 0
		Style.corner(row, 3)
		row.Parent = window
		Style.label(row, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 20), TextSize = 15, Text = string.upper(item.name) })
		Style.label(row, { Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -170, 0, 26), Font = F.Body, TextSize = 12, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = item.description })
		Style.label(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -112, 0, 6), Size = UDim2.fromOffset(46, 20), TextSize = 12, TextColor3 = C.Faint, TextXAlignment = Enum.TextXAlignment.Right, Text = `{item.weight} ea` })
		local minus = stepper(row, "-")
		minus.AnchorPoint = Vector2.new(1, 0.5)
		minus.Position = UDim2.new(1, -74, 0.5, 0)
		local countLabel = Style.label(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.5, 0), Size = UDim2.fromOffset(32, 30), Font = F.Display, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "0" })
		local plus = stepper(row, "+")
		plus.AnchorPoint = Vector2.new(1, 0.5)
		plus.Position = UDim2.new(1, -8, 0.5, 0)
		minus.Activated:Connect(function()
			draft[item.id] = math.max(0, (draft[item.id] or 0) - 1)
			refreshWindow()
		end)
		plus.Activated:Connect(function()
			local capacity = player:GetAttribute("PackCapacity")
			local cap = if type(capacity) == "number" then capacity else Pack.DEFAULT_CAPACITY
			if (draft[item.id] or 0) < item.max and draftWeight() + item.weight <= cap then
				draft[item.id] = (draft[item.id] or 0) + 1
				refreshWindow()
			end
		end)
		rows[item.id] = { count = countLabel, minus = minus, plus = plus }
	end

	local footY = 74 + #Pack.ITEMS * 64 + 6
	weightLabel = Style.label(window, { Position = UDim2.fromOffset(22, footY), Size = UDim2.fromOffset(220, 18), TextSize = 13, TextColor3 = C.Muted, Text = "" })
	local bar, fill = Style.bar(window, 4)
	bar.Position = UDim2.fromOffset(22, footY + 22)
	bar.Size = UDim2.new(1, -184, 0, 4)
	weightFill = fill
	message = Style.label(window, { Position = UDim2.fromOffset(22, footY + 30), Size = UDim2.new(1, -184, 0, 20), Font = F.Body, TextSize = 13, TextColor3 = C.Muted, Text = "" })
	local save = Style.button(window, "Pack", "primary")
	save.AnchorPoint = Vector2.new(1, 0)
	save.Position = UDim2.new(1, -22, 0, footY)
	save.Size = UDim2.fromOffset(130, 40)
	save.Activated:Connect(function()
		message.Text = ""
		requestRemote:FireServer("Set", draft)
	end)
end

local function openWindow()
	draft = {}
	for _, item in Pack.ITEMS do
		local n = count("Pack", item.id)
		if n > 0 then
			draft[item.id] = n
		end
	end
	message.Text = ""
	refreshWindow()
	window.Visible = true
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	openedAt = if root and root:IsA("BasePart") then root.Position else nil
end

---------------------------------------------------------------------------------------

function PackUI.Init()
	requestRemote = Remotes.event("PackRequest")
	screen = Instance.new("ScreenGui")
	screen.Name = "Pack"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	buildHotbar()
	buildWindow()
	refreshHotbar()
end

function PackUI.Start()
	Remotes.event("PackResult").OnClientEvent:Connect(function(ok: boolean, text: string)
		if window.Visible then
			message.Text = text
			message.TextColor3 = if ok then C.Good else C.Bad
			if ok then
				task.delay(0.6, function()
					window.Visible = false
				end)
			end
		else
			ClimbOverlay.toast(text)
		end
	end)
	for _, item in Pack.ITEMS do
		for _, prefix in { "Pack", "Have" } do
			player:GetAttributeChangedSignal(`{prefix}_{item.id}`):Connect(refreshHotbar)
		end
	end
	player:GetAttributeChangedSignal("PackCapacity"):Connect(function()
		if window.Visible then
			refreshWindow()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "OpenPack" then
			openWindow()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			window.Visible = false
			return
		end
		local index = table.find(SLOT_KEYS, input.KeyCode)
		if index and count("Pack", Pack.ITEMS[index].id) > 0 then
			use(Pack.ITEMS[index].id)
		end
	end)
	player.CharacterAdded:Connect(stopPlacing)
	RunService.RenderStepped:Connect(function()
		if placing then
			if count("Have", placing) <= 0 then
				stopPlacing()
			else
				updateGhost()
			end
		end
		refreshHotbar()
		if window.Visible and openedAt then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - openedAt).Magnitude > CLOSE_DISTANCE then
				window.Visible = false
			end
		end
	end)
end

return PackUI
