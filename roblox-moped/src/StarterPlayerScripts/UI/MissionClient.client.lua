--[[
	MissionClient  (LocalScript, StarterPlayerScripts/UI)

	* Job board window (server fires OpenMissionBoard with the offers)
	* Mission tracker (title, objective, countdown) + abandon button
	* In-world markers: a glowing pillar at the current target (client-only
	  parts), a smaller ghost pillar at the next checkpoint, distance label.

	The deadline arrives as a Workspace:GetServerTimeNow() timestamp so the
	countdown is correct no matter what the player's clock says.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local T = UIKit.theme
local make, label, button = UIKit.make, UIKit.label, UIKit.button

local gui = UIKit.screenGui("Missions", 5)

----------------------------------------------------------------------------
-- Tracker (top left)
----------------------------------------------------------------------------
local tracker = make("Frame", {
	Parent = gui, Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(300, 92),
	BackgroundColor3 = T.bg, BackgroundTransparency = 0.2, Visible = false,
}, { UIKit.corner(12), UIKit.padding(10) })
local trackTitle = label({ Parent = tracker, Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBold, TextSize = 16, Text = "" })
local trackHint = label({ Parent = tracker, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = T.muted, Text = "" })
local trackTimer = label({ Parent = tracker, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(0, 120, 0, 28), Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = T.accent, Text = "" })
local trackDist = label({ Parent = tracker, Position = UDim2.fromOffset(120, 46), Size = UDim2.new(0, 100, 0, 20), TextSize = 14, Text = "" })
local abandonBtn = button({
	Parent = tracker, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0),
	Size = UDim2.fromOffset(74, 24), Text = "Abandon", TextSize = 12,
})
abandonBtn.MouseButton1Click:Connect(function()
	Remotes.event("MissionAbandon"):FireServer()
end)

----------------------------------------------------------------------------
-- Markers (client-only parts)
----------------------------------------------------------------------------
local markerFolder = make("Folder", { Name = "MissionMarkers", Parent = Workspace })
local function pillar(size: number, transparency: number): Part
	return make("Part", {
		Parent = markerFolder, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Size = Vector3.new(90, size, size), Material = Enum.Material.Neon, Color = T.accent,
		Transparency = transparency, Shape = Enum.PartType.Cylinder,
	})
end
local mainMarker, nextMarker = pillar(16, 0.55), pillar(9, 0.8)
mainMarker.Parent, nextMarker.Parent = nil, nil

local current: any = nil

local function placeMarker(marker: Part, pos: Vector3?)
	if pos then
		-- cylinders lie along X by default; stand it up
		marker.CFrame = CFrame.new(pos + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90))
		marker.Parent = markerFolder
	else
		marker.Parent = nil
	end
end

Remotes.event("MissionUpdate").OnClientEvent:Connect(function(state)
	current = state
	tracker.Visible = state ~= nil
	if not state then
		placeMarker(mainMarker, nil)
		placeMarker(nextMarker, nil)
		return
	end
	trackTitle.Text = state.title
	local step = state.total and ("  (%d/%d)"):format(state.index, state.total) or ""
	trackHint.Text = (state.hint or "") .. step
	placeMarker(mainMarker, state.target)
	placeMarker(nextMarker, state.nextTarget)
end)

RunService.RenderStepped:Connect(function()
	if not current then
		return
	end
	if current.deadline then
		local left = math.max(0, current.deadline - Workspace:GetServerTimeNow())
		trackTimer.Text = ("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60))
		trackTimer.TextColor3 = left < 20 and T.warn or T.accent
	else
		trackTimer.Text = "no limit"
		trackTimer.TextColor3 = T.good
	end
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and current.target then
		trackDist.Text = ("%d m"):format(math.floor((hrp.Position - current.target).Magnitude * 0.28))
	end
end)

----------------------------------------------------------------------------
-- Job board
----------------------------------------------------------------------------
local board = make("Frame", {
	Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(520, 420), BackgroundColor3 = T.bg, Visible = false,
}, { UIKit.corner(16), UIKit.padding(16), make("UISizeConstraint", { MaxSize = Vector2.new(520, 440) }) })
label({ Parent = board, Size = UDim2.new(1, -50, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 22, Text = "SCHWARZES BRETT - JOBS" })
local boardClose = button({
	Parent = board, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(36, 30), Text = "X",
})
boardClose.MouseButton1Click:Connect(function()
	board.Visible = false
end)
local boardList = make("ScrollingFrame", {
	Parent = board, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42), BackgroundTransparency = 1,
	BorderSizePixel = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 4,
}, { make("UIListLayout", { Padding = UDim.new(0, 8) }) })

local TYPE_COLOR = { Delivery = T.info, Checkpoint = T.warn, Cruise = T.good }

Remotes.event("OpenMissionBoard").OnClientEvent:Connect(function(offers, hasActive)
	for _, c in ipairs(boardList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for _, o in ipairs(offers) do
		local card = make("Frame", { Parent = boardList, Size = UDim2.new(1, -8, 0, 96), BackgroundColor3 = T.panel }, { UIKit.corner(12), UIKit.padding(10) })
		label({ Parent = card, Size = UDim2.new(1, -120, 0, 20), Font = Enum.Font.GothamBold, TextSize = 16, Text = o.title })
		label({ Parent = card, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, -120, 0, 14), TextSize = 12, Font = Enum.Font.GothamBold,
			TextColor3 = TYPE_COLOR[o.type] or T.muted, Text = o.type:upper() .. (o.timeLimit and ("  -  " .. o.timeLimit .. " s") or "") })
		label({ Parent = card, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, -120, 0, 44), TextSize = 12, TextColor3 = T.muted,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = o.description })
		label({ Parent = card, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(100, 22),
			TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = T.accent, Text = ("EUR %d"):format(o.basePay) })
		local accept = button({
			Parent = card, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(96, 30),
			Text = hasActive and "Busy" or "Accept", BackgroundColor3 = hasActive and T.panelLight or T.accent,
			TextColor3 = hasActive and T.muted or Color3.fromRGB(30, 26, 12), TextSize = 14,
		})
		accept.MouseButton1Click:Connect(function()
			local res = Remotes.func("MissionStart"):InvokeServer(o.id)
			if res.ok then
				board.Visible = false
			else
				ClientState.toast = res.reason
			end
		end)
	end
	if #offers == 0 then
		label({ Parent = boardList, Size = UDim2.new(1, 0, 0, 30), Text = "No jobs posted. (Are the MissionSpots in the map?)", TextColor3 = T.muted })
	end
	board.Visible = true
end)
