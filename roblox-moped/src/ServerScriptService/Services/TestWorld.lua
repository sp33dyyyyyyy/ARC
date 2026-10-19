--[[
	TestWorld  (ModuleScript, ServerScriptService/Services)

	Builds a tiny throw-away test track so every system can be tried the
	moment you press Play - before you have built the real town.

	It only runs when GameConfig.GenerateTestWorld is true AND there is no
	Workspace/Town folder. Once you build your village, put it in a Folder
	called "Town" (or flip the config flag) and this disappears.

	It creates (all anchored, all in Workspace/TestTown):
	  * a flat baseplate + ring road + cross roads
	  * a SpawnLocation
	  * tagged props: GarageDoor, Workshop, PetrolStation, MissionBoard
	  * Workspace/MissionSpots with every spot name MissionData asks for
	Use these as a reference for what YOUR map needs (see README).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)

local TestWorld = {}

local function block(parent, name, size, pos, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function label(part: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 40)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Parent = gui
end

function TestWorld.build()
	if not GameConfig.GenerateTestWorld or Workspace:FindFirstChild("Town") then
		return
	end

	local root = Instance.new("Folder")
	root.Name = "TestTown"
	root.Parent = Workspace

	block(root, "Ground", Vector3.new(1500, 2, 1500), Vector3.new(0, -1, 0), Color3.fromRGB(96, 140, 78), Enum.Material.Grass)

	-- roads: ring at +-300 plus the two axes
	local road = Color3.fromRGB(70, 71, 76)
	local W = 28
	for _, z in ipairs({ -300, 0, 300 }) do
		block(root, "Road", Vector3.new(628, 0.3, W), Vector3.new(0, 0.15, z), road, Enum.Material.Asphalt)
	end
	for _, x in ipairs({ -300, 0, 300 }) do
		block(root, "Road", Vector3.new(W, 0.3, 628), Vector3.new(x, 0.15, 0), road, Enum.Material.Asphalt)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 60)
	spawn.Transparency = 0.5
	spawn.Parent = root

	-- tagged service props (near the middle crossroads)
	local garage = block(root, "Garage", Vector3.new(16, 10, 14), Vector3.new(-45, 5, 40), Color3.fromRGB(190, 160, 120))
	CollectionService:AddTag(garage, "GarageDoor")
	label(garage, "GARAGE")

	local workshop = block(root, "Werkstatt", Vector3.new(16, 10, 14), Vector3.new(-45, 5, -30), Color3.fromRGB(120, 140, 175))
	CollectionService:AddTag(workshop, "Workshop")
	label(workshop, "WERKSTATT (repair)")

	local pump = block(root, "Tankstelle", Vector3.new(5, 7, 5), Vector3.new(50, 3.5, 40), Color3.fromRGB(200, 60, 50))
	CollectionService:AddTag(pump, "PetrolStation")
	label(pump, "TANKSTELLE (fuel)")

	local board = block(root, "JobBoard", Vector3.new(8, 8, 1), Vector3.new(0, 4, -40), Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
	CollectionService:AddTag(board, "MissionBoard")
	label(board, "JOB BOARD")

	-- mission spots (names must match MissionData)
	local spots = Instance.new("Folder")
	spots.Name = "MissionSpots"
	spots.Parent = Workspace
	local positions = {
		Spot_Bakery = Vector3.new(-300, 0.4, -150),
		Spot_Gasthof = Vector3.new(300, 0.4, -150),
		Spot_Farm = Vector3.new(300, 0.4, 150),
		Spot_Dorfladen = Vector3.new(-300, 0.4, 150),
		Spot_Huegeldorf = Vector3.new(300, 0.4, 300),
		CP_Forest1 = Vector3.new(-150, 0.4, -300),
		CP_Forest2 = Vector3.new(150, 0.4, -300),
		CP_Forest3 = Vector3.new(300, 0.4, 0),
		CP_Forest4 = Vector3.new(150, 0.4, 300),
		CP_Forest5 = Vector3.new(-150, 0.4, 300),
	}
	for name, pos in pairs(positions) do
		local p = block(spots, name, Vector3.new(14, 0.4, 14), pos, Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
		p.CanCollide = false
		p.Transparency = 0.5
		label(p, (name:gsub("^%a+_", "")))
	end
end

return TestWorld
