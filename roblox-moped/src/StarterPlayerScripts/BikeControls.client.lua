--[[
	BikeControls  (LocalScript, StarterPlayerScripts)

	Click the real controls on the bike - no keybinds needed.

	The server puts an invisible hotspot (a Part with Attribute `Action`) on
	each control of YOUR bikes: fuel tap, ignition key, choke lever, kick
	lever, starter button, the seat and the handlebars. Here we
	  * raycast from the mouse (through the bike's own invisible parts and
	    through your character) every frame,
	  * outline the hotspot under the cursor and show what it does and its state,
	  * on click, tell the server: BikeAction(action, bikeModel).

	The server re-checks that the bike is yours and that you are close enough.
	Works with mouse and touch (tap).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local bikeAction = Remotes.event("BikeAction")
local REACH = 20 -- studs from your character to the control

local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------------
-- hover visuals: one outline + one label, reused
----------------------------------------------------------------------------
local outline = Instance.new("SelectionBox")
outline.Name = "BikeControlOutline"
outline.Color3 = Color3.fromRGB(255, 214, 90)
outline.LineThickness = 0.04
outline.SurfaceColor3 = Color3.fromRGB(255, 214, 90)
outline.SurfaceTransparency = 0.8
outline.Parent = playerGui

local tip = Instance.new("BillboardGui")
tip.Name = "BikeControlTip"
tip.Size = UDim2.fromOffset(320, 34)
tip.StudsOffset = Vector3.new(0, 1.6, 0)
tip.AlwaysOnTop = true
tip.Enabled = false
tip.Parent = playerGui
local tipFrame = Instance.new("Frame")
tipFrame.Size = UDim2.fromScale(1, 1)
tipFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
tipFrame.BackgroundTransparency = 0.15
tipFrame.Parent = tip
Instance.new("UICorner", tipFrame).CornerRadius = UDim.new(0, 8)
local tipText = Instance.new("TextLabel")
tipText.Size = UDim2.fromScale(1, 1)
tipText.BackgroundTransparency = 1
tipText.Font = Enum.Font.GothamBold
tipText.TextSize = 15
tipText.TextColor3 = Color3.fromRGB(250, 246, 235)
tipText.Text = ""
tipText.Parent = tipFrame

----------------------------------------------------------------------------
-- what each control says
----------------------------------------------------------------------------
local function describe(action: string, bike: Model): string
	local mode = bike:GetAttribute("Mode")
	if action == "FuelTap" then
		local tap = bike:GetAttribute("FuelTap")
		local nextTap = ({ Off = "ON", On = "RESERVE", Reserve = "OFF" })[tap] or "ON"
		return ("FUEL TAP  [%s]  -  click for %s"):format(string.upper(tap), nextTap)
	elseif action == "Ignition" then
		return ("IGNITION  [%s]  -  click to switch %s"):format(bike:GetAttribute("Ignition") and "ON" or "OFF", bike:GetAttribute("Ignition") and "off" or "on")
	elseif action == "Choke" then
		return ("CHOKE  [%s]  -  click to switch %s"):format(bike:GetAttribute("Choke") and "ON" or "OFF", bike:GetAttribute("Choke") and "off" or "on")
	elseif action == "Kick" then
		return "KICKSTART  -  click (again and again until it catches)"
	elseif action == "Starter" then
		return ("STARTER BUTTON  -  click   (battery %d%%)"):format((bike:GetAttribute("Battery") or 0) * 100 + 0.5)
	elseif action == "Ride" then
		return mode == "Ride" and "SEAT  -  click to get off" or "SEAT  -  click to ride"
	elseif action == "Grab" then
		return mode == "Push" and "HANDLEBARS  -  click to let go" or "HANDLEBARS  -  click to push the bike"
	end
	return action
end

----------------------------------------------------------------------------
-- picking: cast from the mouse, skipping our character and any bike part
-- that is not a hotspot (invisible chassis, seat, imported mesh parts ...)
----------------------------------------------------------------------------
local function pick(screen: Vector2): (BasePart?, Model?)
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local skip = {}
	if player.Character then
		table.insert(skip, player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local bikes = Workspace:FindFirstChild("Bikes")

	for _ = 1, 8 do
		params.FilterDescendantsInstances = skip
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 400, params)
		if not hit then
			return nil, nil
		end
		local part = hit.Instance
		local action = part:GetAttribute("Action")
		if action then
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model:GetAttribute("Owner") == player.UserId then
				return part, model
			end
			return nil, nil -- someone else's bike
		end
		if bikes and part:IsDescendantOf(bikes) then
			table.insert(skip, part) -- look through the bike's other parts
		else
			return nil, nil -- the world is in the way
		end
	end
	return nil, nil
end

local function withinReach(part: BasePart): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp ~= nil and (hrp.Position - part.Position).Magnitude <= REACH
end

----------------------------------------------------------------------------
-- hover every frame
----------------------------------------------------------------------------
local hoveredPart: BasePart? = nil
local hoveredBike: Model? = nil

RunService.RenderStepped:Connect(function()
	local part, bike = pick(UserInputService:GetMouseLocation())
	if part and bike and not withinReach(part) then
		part, bike = nil, nil
	end
	hoveredPart, hoveredBike = part, bike
	if part and bike then
		outline.Adornee = part
		tip.Adornee = part
		tip.Enabled = true
		tipText.Text = describe(part:GetAttribute("Action"), bike)
	else
		outline.Adornee = nil
		tip.Adornee = nil
		tip.Enabled = false
	end
end)

----------------------------------------------------------------------------
-- click / tap
----------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local screen
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		screen = UserInputService:GetMouseLocation()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		screen = Vector2.new(input.Position.X, input.Position.Y + 36) -- touch is below the top bar inset
	else
		return
	end
	local part, bike = hoveredPart, hoveredBike
	if input.UserInputType == Enum.UserInputType.Touch then
		part, bike = pick(screen)
		if part and not withinReach(part) then
			part, bike = nil, nil
		end
	end
	if part and bike then
		bikeAction:FireServer(part:GetAttribute("Action"), bike)
	end
end)
