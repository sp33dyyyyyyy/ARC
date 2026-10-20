-- Builds the plaza, roads, street lamps, shop stall, boards and every tower.
--
-- Idempotent: if Workspace already has the folders (because someone baked the
-- world into the place by running WorldBuilder.build() from the Studio command
-- bar), they are reused instead of rebuilt.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local TowerBuilder = require(script.Parent.TowerBuilder)

local WorldBuilder = {}

local PLAZA_RADIUS = 70
local PLAZA_CENTER = Vector3.new(0, 0, 0)

local function towerCFrame(entry: any): CFrame
	local angle = math.rad(entry.Angle)
	local pos = PLAZA_CENTER + Vector3.new(math.cos(angle), 0, math.sin(angle)) * entry.Radius
	-- Face 0 (local -Z) looks back at the plaza.
	return CFrame.lookAt(pos, Vector3.new(PLAZA_CENTER.X, pos.Y, PLAZA_CENTER.Z))
end

local function streetLamp(parent: Instance, position: Vector3)
	Build.part(parent, {
		Name = "LampPost",
		Size = Vector3.new(0.6, 14, 0.6),
		Position = position + Vector3.new(0, 7, 0),
		Color = Color3.fromRGB(45, 48, 55),
		Material = Enum.Material.Metal,
	})
	local head = Build.part(parent, {
		Name = "LampHead",
		Size = Vector3.new(2, 0.6, 2),
		Position = position + Vector3.new(0, 14.2, 0),
		Color = Color3.fromRGB(255, 230, 180),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "StreetLight" },
	})
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 110
	light.Range = 32
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Enabled = false
	light.Parent = head
end

local function buildRoads(world: Instance)
	for _, entry in Config.Layout do
		local def = Config.TowerTypes[entry.Type]
		local cf = towerCFrame(entry)
		local baseHalf = if def.Kind == "Telecom" then def.BaseHalfWidth + 12 else def.HalfWidths[1] + 14
		local dir = (cf.Position - PLAZA_CENTER).Unit
		local from = PLAZA_CENTER + dir * (PLAZA_RADIUS - 4)
		local to = cf.Position - dir * (baseHalf - 2)
		local length = (to - from).Magnitude
		local mid = (from + to) / 2
		Build.part(world, {
			Name = "Road",
			Size = Vector3.new(14, 0.4, length),
			CFrame = CFrame.lookAt(mid, to) * CFrame.new(0, -0.3, 0),
			Color = Color3.fromRGB(52, 54, 58),
			Material = Enum.Material.Asphalt,
		})
		Build.part(world, {
			Name = "RoadLine",
			Size = Vector3.new(0.5, 0.05, length - 4),
			CFrame = CFrame.lookAt(mid, to) * CFrame.new(0, -0.08, 0),
			Color = Color3.fromRGB(240, 210, 90),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
		})
		local side = dir:Cross(Vector3.yAxis)
		for d = 20, length - 10, 45 do
			streetLamp(world, from + dir * d + side * 9)
		end
	end
end

local function buildPlaza(world: Instance)
	Build.cylinder(world, PLAZA_CENTER + Vector3.new(0, -0.5, 0), 1, PLAZA_RADIUS * 2, {
		Name = "Plaza",
		Color = Color3.fromRGB(190, 186, 176),
		Material = Enum.Material.Pavement,
	})
	Build.cylinder(world, PLAZA_CENTER + Vector3.new(0, 0.6, 0), 1.2, 22, {
		Name = "FountainRim",
		Color = Color3.fromRGB(150, 146, 140),
		Material = Enum.Material.Marble,
	})
	Build.cylinder(world, PLAZA_CENTER + Vector3.new(0, 0.9, 0), 0.4, 19, {
		Name = "FountainWater",
		Color = Color3.fromRGB(70, 150, 200),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Reflectance = 0.3,
		CanCollide = false,
	})

	-- Shop stall: opening the shop is handled on the client via the prompt.
	local stallCF = CFrame.lookAt(Vector3.new(-30, 0, 30), PLAZA_CENTER)
	local counter = Build.part(world, {
		Name = "ShopStall",
		Size = Vector3.new(14, 4, 4),
		CFrame = stallCF * CFrame.new(0, 2, 0),
		Color = Color3.fromRGB(120, 80, 50),
		Material = Enum.Material.WoodPlanks,
	})
	Build.part(world, {
		Name = "ShopAwning",
		Size = Vector3.new(16, 0.6, 7),
		CFrame = stallCF * CFrame.new(0, 9, -1) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = Color3.fromRGB(230, 70, 70),
		Material = Enum.Material.Fabric,
	})
	for _, x in { -7.5, 7.5 } do
		Build.part(world, {
			Name = "ShopPole",
			Size = Vector3.new(0.6, 9, 0.6),
			CFrame = stallCF * CFrame.new(x, 4.5, 1.5),
			Color = Color3.fromRGB(80, 55, 35),
			Material = Enum.Material.Wood,
		})
	end
	local shopSign = Build.part(world, {
		Name = "ShopSign",
		Size = Vector3.new(12, 2.5, 0.4),
		CFrame = stallCF * CFrame.new(0, 6.5, -2.4),
		Color = Color3.fromRGB(30, 30, 36),
		Material = Enum.Material.SmoothPlastic,
	})
	Build.surfaceText(shopSign, {
		{ text = "GEAR & BOOSTS", size = 70, color = Color3.fromRGB(255, 210, 60) },
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open shop"
	prompt.ObjectText = "Gear & Boosts"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	-- How-to-play board.
	local helpCF = CFrame.lookAt(Vector3.new(30, 0, 30), PLAZA_CENTER)
	local help = Build.part(world, {
		Name = "HowToPlay",
		Size = Vector3.new(16, 10, 0.5),
		CFrame = helpCF * CFrame.new(0, 6, 0),
		Color = Color3.fromRGB(25, 28, 36),
		Material = Enum.Material.SmoothPlastic,
	})
	Build.surfaceText(help, {
		{ text = "HOW TO CLIMB", size = 64, color = Color3.fromRGB(255, 210, 60) },
		{ text = "Walk into a yellow ladder to climb.", size = 34, color = Color3.new(1, 1, 1), font = Enum.Font.GothamMedium },
		{ text = "Climbing burns stamina. Stand on a platform to breathe.", size = 34, color = Color3.new(1, 1, 1), font = Enum.Font.GothamMedium },
		{ text = "Run out and you BLACK OUT and fall.", size = 34, color = Color3.fromRGB(255, 120, 120), font = Enum.Font.GothamMedium },
		{ text = "Skyscrapers are harder but pay way more.", size = 34, color = Color3.fromRGB(110, 230, 140), font = Enum.Font.GothamMedium },
		{ text = "C chalk · R ragdoll · B shop", size = 34, color = Color3.fromRGB(160, 200, 255), font = Enum.Font.GothamBold },
	})
	for _, x in { -7, 7 } do
		Build.part(world, {
			Name = "BoardLeg",
			Size = Vector3.new(0.6, 6, 0.6),
			CFrame = helpCF * CFrame.new(x, 0.5, 0.3),
			Color = Color3.fromRGB(45, 48, 55),
			Material = Enum.Material.Metal,
		})
	end

	-- Leaderboard board (filled in by LeaderboardService).
	local lbCF = CFrame.lookAt(Vector3.new(0, 0, 55), PLAZA_CENTER)
	Build.part(world, {
		Name = "Leaderboard",
		Size = Vector3.new(16, 14, 0.5),
		CFrame = lbCF * CFrame.new(0, 8, 0),
		Color = Color3.fromRGB(20, 22, 30),
		Material = Enum.Material.SmoothPlastic,
	})
	for _, x in { -7, 7 } do
		Build.part(world, {
			Name = "BoardLeg",
			Size = Vector3.new(0.6, 2, 0.6),
			CFrame = lbCF * CFrame.new(x, 0.5, 0.3),
			Color = Color3.fromRGB(45, 48, 55),
			Material = Enum.Material.Metal,
		})
	end

	for i = 0, 15 do
		local deg = i * 22.5
		local clearOfRoads = true
		for _, entry in Config.Layout do
			local diff = math.abs((deg - entry.Angle + 180) % 360 - 180)
			if diff < 14 then
				clearOfRoads = false
			end
		end
		if clearOfRoads then
			local a = math.rad(deg)
			streetLamp(world, PLAZA_CENTER + Vector3.new(math.cos(a), 0, math.sin(a)) * (PLAZA_RADIUS - 6))
		end
	end
end

function WorldBuilder.build()
	local world = Workspace:FindFirstChild("World")
	if not world then
		world = Instance.new("Folder")
		world.Name = "World"
		buildPlaza(world)
		buildRoads(world)
		world.Parent = Workspace
	end

	local towers = Workspace:FindFirstChild("Towers")
	if not towers then
		towers = Instance.new("Folder")
		towers.Name = "Towers"
		for _, entry in Config.Layout do
			TowerBuilder.build(towers, entry, Config.TowerTypes[entry.Type], towerCFrame(entry))
		end
		towers.Parent = Workspace
	end
	return world, towers
end

WorldBuilder.PlazaSpawn = CFrame.new(0, 4, 24)

return WorldBuilder
