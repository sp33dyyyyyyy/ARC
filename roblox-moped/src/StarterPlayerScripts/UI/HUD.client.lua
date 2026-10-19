--[[
	HUD  (LocalScript, StarterPlayerScripts/UI)

	Speed, gear, fuel, health, money, the START-UP PANEL (tap / ignition /
	choke / engine / battery lights), a pushing-effort meter, and toast messages.
	Pure presentation: it only reads bike Attributes + ClientState.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehicleData = require(Shared:WaitForChild("VehicleData"))
local PartsData = require(Shared:WaitForChild("PartsData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local T = UIKit.theme
local make, label = UIKit.make, UIKit.label
local player = Players.LocalPlayer

local gui = UIKit.screenGui("HUD", 1)

----------------------------------------------------------------------------
-- Money (top right)
----------------------------------------------------------------------------
local moneyLabel = label({
	Parent = gui, Position = UDim2.new(1, -16, 0, 8), AnchorPoint = Vector2.new(1, 0),
	Size = UDim2.fromOffset(220, 30), TextXAlignment = Enum.TextXAlignment.Right,
	Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = T.accent, Text = "EUR 0",
})
local jobsLabel = label({
	Parent = gui, Position = UDim2.new(1, -16, 0, 36), AnchorPoint = Vector2.new(1, 0),
	Size = UDim2.fromOffset(220, 20), TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 14, TextColor3 = T.muted, Text = "",
})

Remotes.event("DataChanged").OnClientEvent:Connect(function(view)
	ClientState.data = view
	moneyLabel.Text = ("EUR %d"):format(view.money)
	jobsLabel.Text = ("%d jobs done"):format(view.jobs)
end)

----------------------------------------------------------------------------
-- Gauge panel (bottom right)
----------------------------------------------------------------------------
local gauge = make("Frame", {
	Parent = gui, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(250, 150), BackgroundColor3 = T.bg, BackgroundTransparency = 0.25,
	Visible = false,
}, { UIKit.corner(14), UIKit.padding(12) })

local speedText = label({
	Parent = gauge, Size = UDim2.fromOffset(150, 56), Font = Enum.Font.GothamBlack, TextSize = 52, Text = "0",
})
label({ Parent = gauge, Position = UDim2.fromOffset(2, 54), Size = UDim2.fromOffset(60, 16), TextSize = 13, TextColor3 = T.muted, Text = "km/h" })
local gearText = label({
	Parent = gauge, Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0),
	Size = UDim2.fromOffset(80, 40), TextXAlignment = Enum.TextXAlignment.Right,
	Font = Enum.Font.GothamBold, TextSize = 28, TextColor3 = T.accent, Text = "1",
})

label({ Parent = gauge, Position = UDim2.fromOffset(0, 82), Size = UDim2.fromOffset(50, 14), TextSize = 12, TextColor3 = T.muted, Text = "FUEL" })
local _, setFuel = UIKit.bar({ Parent = gauge, Position = UDim2.fromOffset(50, 84), Size = UDim2.new(1, -50, 0, 10) }, T.accent)
label({ Parent = gauge, Position = UDim2.fromOffset(0, 104), Size = UDim2.fromOffset(50, 14), TextSize = 12, TextColor3 = T.muted, Text = "HEALTH" })
local _, setHealth = UIKit.bar({ Parent = gauge, Position = UDim2.fromOffset(50, 106), Size = UDim2.new(1, -50, 0, 10) }, T.good)

----------------------------------------------------------------------------
-- Start-up panel (bottom left): the real controls, with their keys
----------------------------------------------------------------------------
local panel = make("Frame", {
	Parent = gui, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(250, 172), BackgroundColor3 = T.bg, BackgroundTransparency = 0.25,
	Visible = false,
}, { UIKit.corner(14), UIKit.padding(12) })

label({ Parent = panel, Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = T.muted, Text = "START-UP  -  CLICK THE PARTS ON THE BIKE" })

local rows = {}
local function row(index: number, key: string, name: string)
	local y = 20 + (index - 1) * 24
	local dot = make("Frame", { Parent = panel, Position = UDim2.fromOffset(0, y + 5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = T.muted }, { UIKit.corner(6) })
	label({ Parent = panel, Position = UDim2.fromOffset(22, y), Size = UDim2.fromOffset(120, 22), Text = name })
	local value = label({
		Parent = panel, Position = UDim2.new(1, 0, 0, y), AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(90, 22), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, Text = "",
	})
	rows[name] = { dot = dot, value = value }
end
row(1, "", "Fuel tap")
row(2, "", "Ignition")
row(3, "", "Choke")
row(4, "", "Kickstart")
row(5, "", "Starter")
row(6, "", "Engine")

local function setRow(name: string, text: string, color: Color3)
	local r = rows[name]
	r.value.Text = text
	r.value.TextColor3 = color
	r.dot.BackgroundColor3 = color
end

----------------------------------------------------------------------------
-- Context hint + push effort meter (bottom centre)
----------------------------------------------------------------------------
local hint = label({
	Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(520, 28), TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 16, TextColor3 = T.text, TextStrokeTransparency = 0.5, Text = "",
})
local pushFrame = make("Frame", {
	Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -60),
	Size = UDim2.fromOffset(240, 30), BackgroundTransparency = 1, Visible = false,
})
label({ Parent = pushFrame, Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, TextColor3 = T.muted, Text = "PUSHING EFFORT" })
local _, setEffort = UIKit.bar({ Parent = pushFrame, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 10) }, T.accent)

----------------------------------------------------------------------------
-- Toasts
----------------------------------------------------------------------------
local toastHolder = make("Frame", {
	Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(460, 200), BackgroundTransparency = 1,
}, { make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })

local function toast(text: string, kind: string?)
	local color = ({ good = T.good, warn = T.warn, hint = T.accent })[kind or "info"] or T.info
	local frame = make("Frame", {
		Parent = toastHolder, Size = UDim2.fromOffset(440, 34), BackgroundColor3 = T.bg, BackgroundTransparency = 0.15,
	}, { UIKit.corner(8) })
	make("Frame", { Parent = frame, Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 })
	label({ Parent = frame, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 15, TextWrapped = true, Text = text })
	task.delay(4.5, function()
		frame:Destroy()
	end)
end
Remotes.event("Notify").OnClientEvent:Connect(toast)

----------------------------------------------------------------------------
-- Frame update
----------------------------------------------------------------------------
local myBike: Model? = nil
local lastSearch = 0
local lastToast = nil

-- The bike you're controlling, otherwise the nearest of yours (test mode has several).
local function findMyBike(): Model?
	local folder = Workspace:FindFirstChild("Bikes")
	if not folder then
		return nil
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local best, bestDistance = nil, math.huge
	for _, m in ipairs(folder:GetChildren()) do
		if m:GetAttribute("Owner") == player.UserId then
			if m:GetAttribute("Controller") == player.UserId then
				return m
			end
			local root = m:IsA("Model") and m.PrimaryPart
			local d = (hrp and root) and (hrp.Position - root.Position).Magnitude or math.huge
			if best == nil or d < bestDistance then
				best, bestDistance = m, d
			end
		end
	end
	return best
end

local TAP_COLOR = { Off = T.warn, On = T.good, Reserve = T.accent }

RunService.RenderStepped:Connect(function()
	if ClientState.toast and ClientState.toast ~= lastToast then
		lastToast = ClientState.toast
		toast(ClientState.toast, "hint")
		ClientState.toast = nil
		lastToast = nil
	end

	if os.clock() - lastSearch > 0.25 then
		lastSearch = os.clock()
		myBike = findMyBike()
	end
	local m = myBike
	if not (m and m.Parent) then
		gauge.Visible, panel.Visible, pushFrame.Visible = false, false, false
		hint.Text = "B: bring your bike out   P: phone (parts, garage)"
		return
	end

	local vehicle = VehicleData.byId[m:GetAttribute("VehicleId")]
	if not vehicle then
		return
	end
	vehicle = PartsData.effective(vehicle, m:GetAttribute("Mods"))
	local mode = m:GetAttribute("Mode")
	gauge.Visible, panel.Visible = true, true

	-- gauges
	local fuel = m:GetAttribute("Fuel")
	local health = m:GetAttribute("Health")
	speedText.Text = tostring(math.floor(ClientState.mode == "None" and 0 or ClientState.speedKmh + 0.5))
	gearText.Text = vehicle.drivetrain.transmission == "cvt" and "A" or tostring(m:GetAttribute("Gear"))
	local fuelFrac = fuel / vehicle.stats.fuelCapacityL
	setFuel(fuelFrac, fuel <= vehicle.fuel.reserveL and T.warn or T.accent)
	setHealth(health / 100, health < 35 and T.warn or T.good)

	-- start-up rows
	local tap = m:GetAttribute("FuelTap")
	setRow("Fuel tap", string.upper(tap), TAP_COLOR[tap])
	local ign = m:GetAttribute("Ignition")
	setRow("Ignition", ign and "ON" or "OFF", ign and T.good or T.muted)
	local choke = m:GetAttribute("Choke")
	setRow("Choke", choke and "ON" or "OFF", choke and T.accent or T.muted)
	setRow("Kickstart", "kick lever", T.muted)
	if vehicle.starting.electric then
		local battery = m:GetAttribute("Battery")
		setRow("Starter", ("%d%%"):format(battery * 100 + 0.5), battery > 0.2 and T.good or T.warn)
	else
		setRow("Starter", "none", T.muted)
	end
	local running = m:GetAttribute("EngineRunning")
	local flooded = m:GetAttribute("Flooded") >= 2.5
	if m:GetAttribute("Wrecked") then
		setRow("Engine", "WRECKED", T.warn)
	elseif flooded then
		setRow("Engine", "FLOODED", T.warn)
	else
		setRow("Engine", running and "RUNNING" or "OFF", running and T.good or T.muted)
	end

	-- context hint + push meter
	pushFrame.Visible = mode == "Push"
	if mode == "Push" then
		setEffort(ClientState.pushStrain * 0.6 + ClientState.pushLeash * 0.4, Color3.fromHSV(0.12 - 0.12 * ClientState.pushStrain, 0.85, 0.95))
		hint.Text = "Walk to push. Heavy bikes are slower and drag you back. Click the handlebars to let go."
	elseif mode == "Ride" then
		if not running then
			hint.Text = "Click: fuel tap > ignition key > choke (if cold) > kick lever"
		elseif choke and m:GetAttribute("Warm") > 0.5 then
			hint.Text = "Engine is warm - click the choke lever to turn it off"
		else
			hint.Text = ""
		end
	else
		hint.Text = "Click the SEAT to ride, the HANDLEBARS to push. Fuel tap, key, choke and kick lever are clickable too."
	end
end)
