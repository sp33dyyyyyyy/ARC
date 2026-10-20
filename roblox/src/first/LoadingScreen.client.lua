-- Loading screen. Lives in ReplicatedFirst so it shows before anything else
-- loads (and replaces Roblox's default one). It shows what's loading with a
-- progress bar, has a SKIP button, and fades out once the world and your save
-- are ready.
--
-- The server publishes world-building progress on Workspace (LoadStage,
-- LoadProgress, WorldReady); your save sets "DataLoaded" on your player.
-- Self-contained on purpose: nothing else is loaded this early.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local ACCENT = Color3.fromRGB(255, 196, 46)
local TIPS = {
	"Walk into a tower to grab on, then hold W to climb.",
	"Press F to clip your rope in - it catches you if you fall.",
	"Hang still on a yellow rest bar to get your breath back.",
	"Skyscrapers are harder, but they pay way more.",
	"Press SPACE while climbing to dyno up to a higher hold.",
	"Rain makes every wall slippery. Chalk up with C!",
}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		-- Text always fits its box.
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = (inst :: TextLabel).TextSize
		fit.Parent = inst;
		(inst :: TextLabel).TextScaled = true
	end
	inst.Parent = parent
	return inst
end

local gui = new("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	DisplayOrder = 100,
	ResetOnSpawn = false,
}, nil)

local background = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(14, 16, 24),
	BorderSizePixel = 0,
}, gui)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(40, 60, 100), Color3.fromRGB(12, 14, 22)),
	Rotation = 90,
}, background)

local center = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.8, 0, 0, 260),
	BackgroundTransparency = 1,
}, background)
new("UISizeConstraint", { MaxSize = Vector2.new(640, 260) }, center)

new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 70),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "SKY CLIMBERS",
	TextSize = 64,
	TextColor3 = ACCENT,
}, center)
local stage = new("TextLabel", {
	Position = UDim2.fromOffset(0, 96),
	Size = UDim2.new(1, -70, 0, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Starting up...",
	TextSize = 20,
	TextColor3 = Color3.fromRGB(240, 242, 248),
	TextXAlignment = Enum.TextXAlignment.Left,
}, center)
local percent = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 96),
	Size = UDim2.fromOffset(70, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "0%",
	TextSize = 20,
	TextColor3 = ACCENT,
	TextXAlignment = Enum.TextXAlignment.Right,
}, center)
local track = new("Frame", {
	Position = UDim2.fromOffset(0, 130),
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundColor3 = Color3.fromRGB(40, 44, 58),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, center)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
local fill = new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = ACCENT,
	BorderSizePixel = 0,
}, track)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(255, 220, 110), Color3.fromRGB(255, 160, 30)),
}, fill)
local tip = new("TextLabel", {
	Position = UDim2.fromOffset(0, 162),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Tip: " .. TIPS[math.random(1, #TIPS)],
	TextSize = 16,
	TextColor3 = Color3.fromRGB(150, 158, 180),
}, center)

local skip = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 204),
	Size = UDim2.fromOffset(150, 44),
	BackgroundColor3 = Color3.fromRGB(45, 52, 72),
	AutoButtonColor = true,
	Font = Enum.Font.GothamBold,
	Text = "SKIP",
	TextSize = 18,
	TextColor3 = Color3.fromRGB(240, 242, 248),
	Visible = false,
}, center)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, skip)
new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.8 }, skip)

gui.Parent = player:WaitForChild("PlayerGui")

-- Close: fade everything out, then remove the screen.
local closed = false
local function close()
	if closed then
		return
	end
	closed = true
	local info = TweenInfo.new(0.6, Enum.EasingStyle.Sine)
	for _, inst in gui:GetDescendants() do
		if inst:IsA("Frame") or inst:IsA("TextButton") then
			TweenService:Create(inst, info, { BackgroundTransparency = 1 }):Play()
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			TweenService:Create(inst, info, { TextTransparency = 1 }):Play()
		end
		if inst:IsA("UIStroke") then
			TweenService:Create(inst, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(0.7, function()
		gui:Destroy()
	end)
end
skip.Activated:Connect(close)

-- The SKIP button appears after a moment (so a quick load just plays through).
task.delay(1.5, function()
	if not closed then
		skip.Visible = true
	end
end)


-- Progress: the world build is 90% of the bar, your save the last 10%.
local shown = 0
local readyAt: number? = nil
local connection
connection = RunService.RenderStepped:Connect(function(dt)
	if closed then
		connection:Disconnect()
		return
	end
	local worldProgress = Workspace:GetAttribute("LoadProgress")
	local worldReady = Workspace:GetAttribute("WorldReady") == true
	local dataReady = player:GetAttribute("DataLoaded") == true
	local target = (if worldReady then 1 elseif typeof(worldProgress) == "number" then worldProgress else 0) * 0.9
		+ (if dataReady then 0.1 else 0)

	local text
	if not worldReady then
		local label = Workspace:GetAttribute("LoadStage")
		text = (if typeof(label) == "string" then label else "Connecting to the server") .. "..."
	elseif not dataReady then
		text = "Loading your save..."
	else
		text = "Ready to climb!"
	end
	stage.Text = text

	-- Ease the bar toward the real progress so it fills smoothly.
	shown += (target - shown) * math.min(1, dt * 6)
	fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	percent.Text = string.format("%d%%", math.floor(shown * 100 + 0.5))

	if worldReady and dataReady then
		readyAt = readyAt or os.clock()
		if os.clock() - (readyAt :: number) > 0.6 then
			close()
		end
	end
end)

-- Rotate tips every few seconds.
task.spawn(function()
	while not closed do
		task.wait(4)
		tip.Text = "Tip: " .. TIPS[math.random(1, #TIPS)]
	end
end)
