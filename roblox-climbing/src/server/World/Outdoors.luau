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
local Npc = require(script.Parent.Npc)
local Props = require(script.Parent.Props)
local RockWall = require(script.Parent.RockWall)

local part = BuildUtil.part
local frameAt = BuildUtil.frameAt

-- Ground level outdoors: flush with the gym floor. Terrain is made of 4-stud voxels, so
-- the grass is filled exactly to a voxel boundary (y = 0) to be perfectly flat there;
-- anything off the grid becomes a soft bulge that swallows props standing on it.
local GROUND_Y = 0
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
	-- No grass under the gym (its blades would poke up through the floor): carve its
	-- footprint, which lies on the voxel grid, back to air.
	terrain:FillBlock(CFrame.new(0, GROUND_Y - 2, 2), Vector3.new(128, 4, 84), Enum.Material.Air)

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
		-- The whole top voxel layer, so the path only changes material and stays flat.
		terrain:FillBlock(CFrame.lookAt((a + b) / 2, b) + Vector3.yAxis * (GROUND_Y - 2), Vector3.new(8, 4, length + 6), Enum.Material.Ground)
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

-- Space taken by props outdoors (circles on the ground), so nothing is placed into
-- anything else: camps first, then rocks and bushes, then the forest.
type Spot = { x: number, z: number, r: number }
local taken: { Spot } = {}

local function claim(x: number, z: number, r: number): boolean
	for _, spot in taken do
		local dx, dz = spot.x - x, spot.z - z
		if dx * dx + dz * dz < (spot.r + r) * (spot.r + r) then
			return false
		end
	end
	table.insert(taken, { x = x, z = z, r = r })
	return true
end

local function buildTrees(parent: Instance)
	local forest = Instance.new("Model")
	forest.Name = "Forest"
	local rand = scatter(424242)
	local placed = 0
	local attempts = 0
	while placed < 150 and attempts < 4000 do
		attempts += 1
		local x = (rand() - 0.5) * 900
		local z = -260 + rand() * 900
		local scale = 0.8 + rand() * 0.7
		-- Creator Store trees: pines, with leafy trees mixed in nearer the gym.
		local near = math.abs(x) < 200 and z < 300
		local roll = rand()
		local key = if near and roll < 0.35 then (if roll < 0.18 then "tree_a" else "tree_b") elseif roll < 0.5 then "pine_a" elseif roll < 0.8 then "pine_b" else "pine_c"
		local size = if key == "tree_a" or key == "tree_b" then Vector3.new(16, 22, 16) else Vector3.new(14, 26, 14)
		-- Trees don't grow into each other: keep a canopy's width apart.
		if blocked(x, z) or not claim(x, z, size.X * scale * 0.4) then
			continue
		end
		placed += 1
		local base = Vector3.new(x, GROUND_Y, z)
		local trunkHeight = 6 * scale
		local yaw = rand() * math.pi * 2
		-- The stand-in: a rounded fir.
		local tree = Props.slot(forest, key, Props.at(base, Vector3.new(math.cos(yaw), 0, math.sin(yaw))), size * scale, nil)
		part({
			name = "Trunk",
			size = Vector3.new(trunkHeight + 2, 1.2 * scale, 1.2 * scale),
			cframe = CFrame.new(base + Vector3.yAxis * (trunkHeight / 2)) * BuildUtil.AXIS_Y,
			surface = "Bark",
			shape = Enum.PartType.Cylinder,
			collide = true,
			parent = tree,
		})
		local green = Color3.fromRGB(40 + math.floor(rand() * 16), 76 + math.floor(rand() * 20), 48)
		for tier = 0, 4 do
			local radius = (5.4 - tier * 1.0) * scale
			local y = trunkHeight * 0.8 + tier * 2.6 * scale
			part({
				name = "Needles",
				size = Vector3.new(radius * 2, (3.6 - tier * 0.3) * scale, radius * 2),
				cframe = CFrame.new(base + Vector3.yAxis * y) * CFrame.Angles(0, rand() * math.pi, 0),
				surface = "PineNeedles",
				color = green:Lerp(Color3.fromRGB(70, 110, 64), tier * 0.08),
				ellipsoid = true,
				parent = tree,
			})
		end
	end
	forest.Parent = parent
end

-- Rocks and bushes around the crags and along the paths, and a camp (tent, campfire and
-- a climber) beside each crag. Creator Store models with simple stand-ins.
local function buildScatter(parent: Instance)
	local scatterModel = Instance.new("Model")
	scatterModel.Name = "Scatter"
	local rand = scatter(5150)
	local function rock(position: Vector3, size: number)
		if not claim(position.X, position.Z, size * 0.45) then
			return
		end
		local keys = { "rock_a", "rock_b", "rock_c" }
		local yaw = rand() * math.pi * 2
		Props.slot(scatterModel, keys[math.floor(rand() * 3) + 1], Props.at(position, Vector3.new(math.cos(yaw), 0, math.sin(yaw))), Vector3.new(size, size * 0.7, size), function(m)
			part({ name = "Rock", size = Vector3.new(size, size * 0.6, size * 0.8), cframe = CFrame.new(position + Vector3.yAxis * size * 0.18) * CFrame.Angles(0, yaw, 0), surface = "RockFace", ellipsoid = true, collide = true, query = true, parent = m })
		end)
	end
	local function bush(position: Vector3, size: number)
		if not claim(position.X, position.Z, size * 0.42) then
			return
		end
		local key = if rand() < 0.3 then "flowerbush" else "bush"
		Props.slot(scatterModel, key, Props.at(position, Vector3.new(rand() - 0.5, 0, rand() - 0.5)), Vector3.new(size, size * 0.8, size), function(m)
			part({ name = "Bush", size = Vector3.new(size, size * 0.7, size), cframe = CFrame.new(position + Vector3.yAxis * size * 0.3), surface = "Leaves", ellipsoid = true, parent = m })
		end)
	end
	-- The crags' own ground (the face and the start areas in front of it) is never used.
	for _, wall in WALLS do
		claim(wall.origin.X, wall.origin.Z + 6, wall.width / 2 + 2)
		for _, route in wall.routes do
			claim(wall.origin.X + route.lineX * -1, wall.origin.Z - 6, 9)
		end
	end
	for _, wall in WALLS do
		local half = wall.width / 2
		-- Camp on the left of the crag: a tent, a campfire and a climber in full kit.
		local camp = Vector3.new(wall.origin.X - half - 16, GROUND_Y, wall.origin.Z - 18)
		claim(camp.X, camp.Z, 5)
		Props.slot(scatterModel, "tent", Props.at(camp, Vector3.new(1, 0, -0.4)), Vector3.new(7, 5, 8), function(m)
			part({ name = "Tent", size = Vector3.new(6, 4.5, 7), cframe = frameAt(camp + Vector3.yAxis * 2.25, Vector3.new(1, 0, 0), Vector3.yAxis), surface = "Tape", color = Color3.fromRGB(240, 120, 50), wedge = true, collide = true, query = true, parent = m })
		end)
		local kits = {
			{ hat = 117772364185840, back = 128795521464166, waist = 12765447418 },
			{ hat = 72372066631368, back = 17817037993, waist = 12765462493 },
			{ hat = 86458819326502, back = 88149022073624, waist = 12765451822 },
		}
		local kit = kits[(math.floor(wall.origin.X) % #kits) + 1]
		local climber = camp + Vector3.new(5, 0, -7)
		claim(climber.X, climber.Z, 1.5)
		Npc.spawn("Climber", climber, Vector3.new(0, 0, 1), scatterModel, Color3.fromRGB(70, 110, 160), kit)
		local fire = camp + Vector3.new(7, 0, -3)
		claim(fire.X, fire.Z, 2.2)
		Props.slot(scatterModel, "campfire", Props.at(fire, Vector3.new(0, 0, 1)), Vector3.new(3.4, 2.6, 3.4), function(m)
			for i = 0, 5 do
				local angle = i * math.pi / 3
				part({ name = "Stone", size = Vector3.new(0.9, 0.6, 0.8), cframe = CFrame.new(fire + Vector3.new(math.cos(angle) * 1.4, 0.25, math.sin(angle) * 1.4)), surface = "RockFace", ellipsoid = true, parent = m })
			end
		end)
		for side = -1, 1, 2 do
			-- Boulders tumbled against the foot of the crag, either side of it.
			for _ = 1, 4 do
				local x = wall.origin.X + side * (half + 3 + rand() * 18)
				rock(Vector3.new(x, GROUND_Y, wall.origin.Z - 2 - rand() * 14), 3 + rand() * 6)
			end
			for _ = 1, 3 do
				bush(Vector3.new(wall.origin.X + side * (half + 6 + rand() * 20), GROUND_Y, wall.origin.Z - 8 - rand() * 20), 3 + rand() * 3)
			end
		end
	end
	-- Along the paths (beside them, never on them).
	for _ = 1, 26 do
		local z = 60 + rand() * 440
		local x = (if rand() < 0.5 then -1 else 1) * (7 + rand() * 10)
		if rand() < 0.5 then
			rock(Vector3.new(x, GROUND_Y, z), 1.5 + rand() * 3)
		else
			bush(Vector3.new(x, GROUND_Y, z), 2.5 + rand() * 2.5)
		end
	end
	scatterModel.Parent = parent
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
		-- A massif: a main peak and two shoulders, smooth rounded domes sunk into the
		-- ground, each with a snow cap on its top.
		local peaks = {
			{ x = 0, scale = 1 },
			{ x = -width * 0.42, scale = 0.62 + rand() * 0.15 },
			{ x = width * 0.4, scale = 0.55 + rand() * 0.2 },
		}
		for p, peak in peaks do
			local h = height * peak.scale * 0.85 -- the dome's half-height (its top above the base)
			local wPeak = width * peak.scale
			local dPeak = depth * peak.scale * 1.1
			local frame = CFrame.new(center) * yaw * CFrame.new(peak.x, 0, (p - 2) * 40)
			local dome = part({
				name = `Mountain{i}`,
				size = Vector3.new(wPeak, h * 2, dPeak),
				cframe = frame,
				surface = "RockFace",
				color = rockColour,
				ellipsoid = true,
				parent = range,
			})
			dome.CastShadow = false
			-- Snow: a flatter dome riding over the top, as wide as the mountain at its centre.
			local capCentre = 0.74
			local capWidth = math.sqrt(1 - capCentre * capCentre)
			local cap = part({
				name = "Snow",
				size = Vector3.new(wPeak * capWidth, h * 0.6, dPeak * capWidth),
				cframe = frame * CFrame.new(0, h * capCentre, 0),
				surface = "Chalk",
				color = Color3.fromRGB(238, 242, 248),
				ellipsoid = true,
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
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.Sarpanch
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
	glow.Range = 40
	glow.Brightness = 1
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
	table.clear(taken)
	buildScatter(model)
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
	local existing = Outdoors.Find()
	-- Outdoors saved into the place by an older version is rebuilt with the new layout.
	if existing and existing:GetAttribute("Version") ~= Config.Version then
		existing:Destroy()
		existing = nil
	end
	return existing or Outdoors.Build()
end

function Outdoors.Rebuild(): Model
	local existing = Outdoors.Find()
	if existing then
		existing:Destroy()
	end
	return Outdoors.Build()
end

return Outdoors
