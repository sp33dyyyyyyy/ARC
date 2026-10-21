--!strict
-- Outdoors: everything outside the gym door (design doc 5.2).
--
--   * Grass terrain, dirt paths from the gym door to each crag, pine forest, snowy
--     mountains on the horizon.
--   * Natural Wall A: a 15 m beginner crag with two easy routes.
--   * Natural Wall B: a 35 m face with a ledge halfway and an overhang above it.
--   * The Colossus: a ~280 m granite wall with ledges about every 30 m, a big roof
--     two thirds up, and a misty summit plateau with a violet glow and a flag.
-- Every route has a rope bag (tie in), a chalk bucket and a leaderboard sign at its base.
--
-- Built at server start if Workspace.Outdoors is missing, or in edit mode:
--     require(game.ServerScriptService.Server.World.Outdoors).Rebuild()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local BuildUtil = require(script.Parent.BuildUtil)
local Face = require(script.Parent.Face)
local RockWall = require(script.Parent.RockWall)

local part = BuildUtil.part
local frameAt = BuildUtil.frameAt

local GROUND_Y = -0.5 -- grass sits just under the gym floor
local FACING = Vector3.new(0, 0, -1) -- every crag faces the gym

local Outdoors = {}

-- The crags, in route order (the gym's routes are 1-10).
local WALLS: { RockWall.WallDef } = {
	{
		id = "WallA",
		origin = Vector3.new(-55, -1, 170),
		facing = FACING,
		width = 44,
		segments = { { length = 56, angle = 3 } },
		groundY = GROUND_Y,
		tint = Color3.fromRGB(128, 122, 112),
		block = 9,
		routes = {
			{ id = "GreywallTraverse", name = "Greywall Traverse", grade = "5a", order = 11, lineX = -12, drift = 20, difficulty = 0.2, seed = 1101 },
			{ id = "MossySteps", name = "Mossy Steps", grade = "4", order = 12, lineX = 12, difficulty = 0.05, seed = 1202 },
		},
	},
	{
		id = "WallB",
		origin = Vector3.new(65, -1, 215),
		facing = FACING,
		width = 50,
		segments = { { length = 60, angle = 2 }, { length = 30, angle = 22 }, { length = 36, angle = 5 } },
		ledges = { 60 },
		groundY = GROUND_Y,
		tint = Color3.fromRGB(112, 110, 106),
		block = 10,
		routes = {
			{ id = "SentinelProw", name = "Sentinel Prow", grade = "6b", order = 13, lineX = -9, difficulty = 0.5, seed = 1303 },
			{ id = "SplitPillar", name = "Split Pillar", grade = "6c", order = 14, lineX = 11, difficulty = 0.7, seed = 1404 },
		},
	},
	{
		id = "Colossus",
		origin = Vector3.new(0, -1, 520),
		facing = FACING,
		width = 220,
		segments = {
			{ length = 120, angle = 4 },
			{ length = 110, angle = 0 },
			{ length = 110, angle = -8 },
			{ length = 110, angle = 6 },
			{ length = 110, angle = 0 },
			{ length = 80, angle = 10 },
			{ length = 40, angle = 35 }, -- the big roof
			{ length = 110, angle = 2 },
			{ length = 110, angle = 0 },
			{ length = 90, angle = -5 },
		},
		ledges = { 120, 230, 340, 450, 560, 640, 680, 790, 900 },
		groundY = GROUND_Y,
		tint = Color3.fromRGB(110, 108, 106),
		block = 24,
		routes = {
			{ id = "LongWayUp", name = "The Long Way Up", grade = "6a", order = 15, lineX = -40, difficulty = 0.35, seed = 1505, wander = 2.2 },
			{ id = "SkylineDirect", name = "Skyline Direct", grade = "7a", order = 16, lineX = 40, difficulty = 0.6, seed = 1606, wander = 1.8 },
		},
	},
}
Outdoors.WALLS = WALLS

-- Deterministic pseudo-random numbers for scenery placement.
local function scatter(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

local function buildTerrain()
	local terrain = Workspace.Terrain
	-- Everything around the gym and out to the mountains (the gym floor sits on top).
	terrain:FillBlock(CFrame.new(0, GROUND_Y - 4, 300), Vector3.new(1800, 8, 1800), Enum.Material.LeafyGrass)

	-- Dirt paths from the door to each crag.
	local door = Vector3.new(0, 0, 46)
	local paths = {
		{ door, Vector3.new(0, 0, 100) },
		{ Vector3.new(0, 0, 100), Vector3.new(-48, 0, 158) },
		{ Vector3.new(0, 0, 100), Vector3.new(58, 0, 203) },
		{ Vector3.new(0, 0, 100), Vector3.new(0, 0, 506) },
	}
	for _, segment in paths do
		local a, b = segment[1], segment[2]
		local length = (b - a).Magnitude
		terrain:FillBlock(CFrame.lookAt((a + b) / 2, b) + Vector3.yAxis * (GROUND_Y - 0.45), Vector3.new(7, 1, length + 6), Enum.Material.Ground)
	end
end

local function nearPath(x: number, z: number): boolean
	if math.abs(x) < 12 and z > 40 and z < 506 then
		return true
	end
	return false
end

local function blocked(x: number, z: number): boolean
	if math.abs(x) < 85 and z < 60 then
		return true -- the gym
	end
	if nearPath(x, z) then
		return true
	end
	for _, wall in Outdoors.WALLS do
		local half = wall.width / 2 + 14
		if math.abs(x - wall.origin.X) < half and z > wall.origin.Z - 40 and z < wall.origin.Z + 70 then
			return true -- in front of or under a crag
		end
	end
	return false
end

local function buildTrees(parent: Instance)
	local forest = Instance.new("Model")
	forest.Name = "Forest"
	local rand = scatter(424242)
	local placed = 0
	local attempts = 0
	while placed < 150 and attempts < 2000 do
		attempts += 1
		local x = (rand() - 0.5) * 900
		local z = -260 + rand() * 900
		if blocked(x, z) then
			continue
		end
		placed += 1
		local scale = 0.8 + rand() * 0.7
		local base = Vector3.new(x, GROUND_Y, z)
		local trunkHeight = 6 * scale
		local tree = Instance.new("Model")
		tree.Name = "Pine"
		part({
			name = "Trunk",
			size = Vector3.new(trunkHeight + 2, 1.2 * scale, 1.2 * scale),
			cframe = CFrame.new(base + Vector3.yAxis * (trunkHeight / 2)) * BuildUtil.AXIS_Y,
			surface = "Bark",
			shape = Enum.PartType.Cylinder,
			collide = true,
			parent = tree,
		})
		-- Stacked, shrinking needle tiers.
		for tier = 0, 3 do
			local radius = (5.2 - tier * 1.15) * scale
			local y = trunkHeight + tier * 3.2 * scale
			local needles = part({
				name = "Needles",
				size = Vector3.new(3.4 * scale, radius * 2, radius * 2),
				cframe = CFrame.new(base + Vector3.yAxis * y) * BuildUtil.AXIS_Y * CFrame.Angles(math.rad(rand() * 40), 0, 0),
				surface = "PineNeedles",
				color = Color3.fromRGB(40 + math.floor(rand() * 16), 76 + math.floor(rand() * 20), 48),
				shape = Enum.PartType.Cylinder,
				parent = tree,
			})
			needles.CastShadow = true
		end
		tree.Parent = forest
	end
	forest.Parent = parent
end

local function buildMountains(parent: Instance)
	local range = Instance.new("Model")
	range.Name = "Mountains"
	range.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local rand = scatter(777)
	local spots = {
		{ -700, 1100 }, { -250, 1250 }, { 250, 1200 }, { 700, 1050 }, { 1050, 600 },
		{ -1050, 650 }, { 1100, 100 }, { -1100, 150 }, { 900, -500 }, { -900, -450 }, { 0, -900 },
	}
	for i, spot in spots do
		local center = Vector3.new(spot[1], GROUND_Y - 4, spot[2])
		local width = 500 + rand() * 400
		local height = 320 + rand() * 260
		local depth = 420 + rand() * 240
		local yaw = CFrame.Angles(0, math.atan2(-spot[1], -spot[2]) + (rand() - 0.5) * 0.6, 0)
		local rockColour = Color3.fromRGB(96, 100, 112):Lerp(Color3.fromRGB(130, 132, 140), rand())
		-- A ridge: two wedges back to back, and a snow cap on top.
		for side = 0, 1 do
			local flip = if side == 0 then CFrame.identity else CFrame.Angles(0, math.pi, 0)
			local ridge = part({
				name = `Mountain{i}`,
				size = Vector3.new(width, height, depth / 2),
				cframe = CFrame.new(center) * yaw * flip * CFrame.new(0, height / 2, -depth / 4),
				surface = "RockFace",
				color = rockColour,
				wedge = true,
				parent = range,
			})
			ridge.CastShadow = false
			local capHeight = height * 0.32
			local capDepth = depth / 2 * 0.32
			local cap = part({
				name = "Snow",
				size = Vector3.new(width * 0.98, capHeight, capDepth + 0.6),
				cframe = CFrame.new(center) * yaw * flip * CFrame.new(0, height - capHeight / 2 + 0.3, -capDepth / 2 - 0.3),
				surface = "Chalk",
				color = Color3.fromRGB(238, 242, 248),
				wedge = true,
				parent = range,
			})
			cap.Material = Enum.Material.Snow
			cap.Transparency = 0
			cap.CastShadow = false
		end
	end
	range.Parent = parent
end

local function buildSignpost(parent: Instance, position: Vector3, lines: string)
	local post = Instance.new("Model")
	post.Name = "Signpost"
	BuildUtil.pipe("Post", position, position + Vector3.yAxis * 7, 0.35, "LightWood", post).CanCollide = true
	local board = part({
		name = "Board",
		size = Vector3.new(6, 2.6, 0.25),
		cframe = frameAt(position + Vector3.yAxis * 5.6 + Vector3.new(0, 0, -0.3), Vector3.new(0, 0, -1), Vector3.yAxis),
		surface = "LightWood",
		collide = true,
		parent = post,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.RichText = true
	text.TextColor3 = Color3.fromRGB(50, 32, 18)
	text.Text = lines
	text.Parent = gui
	post.Parent = parent
end

local function buildSummitDressing(parent: Instance)
	local colossus = Outdoors.WALLS[3]
	local face = Face.new(colossus.origin, colossus.facing, colossus.segments)
	local summit = Instance.new("Model")
	summit.Name = "ColossusSummit"
	summit.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	-- On the plateau, back from the top edge.
	local plateau = Face.top(face) - face.flatNormal * 30
	BuildUtil.pipe("FlagPole", plateau, plateau + Vector3.yAxis * 16, 0.4, "Steel", summit)
	local flag = part({
		name = "Flag",
		size = Vector3.new(6, 3.6, 0.1),
		cframe = CFrame.new(plateau + Vector3.new(3.2, 14, 0)),
		surface = "Tape",
		color = Color3.fromRGB(255, 210, 50),
		parent = summit,
	})
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(150, 110, 255)
	glow.Range = 60
	glow.Brightness = 3
	glow.Parent = flag
	-- Drifting mist banks around the top.
	local rand = scatter(9090)
	for _ = 1, 26 do
		local offset = Vector3.new((rand() - 0.5) * 300, (rand() - 0.3) * 60, (rand() - 0.5) * 160)
		local mist = part({
			name = "Mist",
			size = Vector3.new(40 + rand() * 50, 12 + rand() * 12, 30 + rand() * 40),
			cframe = CFrame.new(plateau + offset),
			surface = "ChalkSmear",
			color = Color3.fromRGB(235, 236, 245),
			ellipsoid = true,
			shadow = false,
			parent = summit,
		})
		mist.Transparency = 0.55
		mist.Material = Enum.Material.SmoothPlastic
	end
	summit.Parent = parent
end

function Outdoors.Find(): Instance?
	return Workspace:FindFirstChild("Outdoors")
end

function Outdoors.Build(): Model
	local model = Instance.new("Model")
	model.Name = "Outdoors"
	buildTerrain()
	buildTrees(model)
	buildMountains(model)
	buildSignpost(model, Vector3.new(6, GROUND_Y, 98), `<b>CRAGS</b>\n← Wall A  ·  Wall B →\n↑ The Colossus`)
	for _, wall in Outdoors.WALLS do
		RockWall.build(wall)
	end
	buildSummitDressing(model)
	model:SetAttribute("Version", Config.Version)
	model.Parent = Workspace
	return model
end

function Outdoors.Ensure(): Instance
	return Outdoors.Find() or Outdoors.Build()
end

function Outdoors.Rebuild(): Model
	local existing = Outdoors.Find()
	if existing then
		existing:Destroy()
	end
	return Outdoors.Build()
end

return Outdoors
