-- Builds the island map from the top-down design (north = -Z):
--
--   SPAWN / PLAZA (gate, planter, signposts, boards)
--   west column: Skyscraper 1 / 2 / 3      east column: Tutorial / Telecom 1 / 2
--   a dirt path down the middle with branches into each fenced tower lot
--   POWER UP SHOP at the south end
--   all on a fenced, tree-covered cliff island in the sea.
--
-- The island's grass top is at y = 0. Idempotent: if Workspace already has the
-- World/Towers folders (baked into the place), they are reused.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local TowerBuilder = require(script.Parent.TowerBuilder)

local WorldBuilder = {}

local M = Config.Map
local PLAZA = Vector3.new(M.PlazaCenter[1], 0, M.PlazaCenter[2])
local SHOP = Vector3.new(M.ShopCenter[1], 0, M.ShopCenter[2])
local PATH_TOP = PLAZA.Z + 80
local PATH_BOTTOM = SHOP.Z - 80

local DIRT = Color3.fromRGB(196, 140, 86)
local GRASS = Color3.fromRGB(96, 160, 64)
local WOOD = Color3.fromRGB(120, 78, 45)
local DARK_WOOD = Color3.fromRGB(85, 55, 32)
local IRON = Color3.fromRGB(38, 40, 46)
local DIFFICULTY_COLORS = {
	EASY = Color3.fromRGB(90, 230, 110),
	NORMAL = Color3.fromRGB(255, 205, 60),
	HARD = Color3.fromRGB(255, 70, 60),
}

-- Rectangles (x0, z0, x1, z1) that trees and rocks must stay out of.
local keepClear: { { number } } = {}
local function reserve(x0: number, z0: number, x1: number, z1: number)
	table.insert(keepClear, { math.min(x0, x1), math.min(z0, z1), math.max(x0, x1), math.max(z0, z1) })
end
local function isClear(x: number, z: number, margin: number): boolean
	for _, r in keepClear do
		if x > r[1] - margin and x < r[3] + margin and z > r[2] - margin and z < r[4] + margin then
			return false
		end
	end
	return true
end

local function flat(world: Instance, name: string, x0: number, z0: number, x1: number, z1: number, y: number, color: Color3, material: Enum.Material)
	return Build.part(world, {
		Name = name,
		Size = Vector3.new(math.abs(x1 - x0), 0.4, math.abs(z1 - z0)),
		CFrame = CFrame.new((x0 + x1) / 2, y - 0.2, (z0 + z1) / 2),
		Color = color,
		Material = material,
	})
end

-- Props ----------------------------------------------------------------------------

local function lamp(world: Instance, pos: Vector3)
	Build.part(world, {
		Name = "LampPost",
		Size = Vector3.new(0.6, 11, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 5.5, 0)),
		Color = IRON,
		Material = Enum.Material.Metal,
	})
	local head = Build.part(world, {
		Name = "LampHead",
		Size = Vector3.new(1.6, 2, 1.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 12, 0)),
		Color = Color3.fromRGB(255, 200, 120),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "StreetLight" },
	})
	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Enabled = false
	light.Parent = head
end

local function tree(world: Instance, rng: Random, pos: Vector3, scale: number)
	local trunkH = 7 * scale
	Build.cylinder(world, pos + Vector3.new(0, trunkH / 2, 0), trunkH, 1.6 * scale, {
		Name = "Trunk",
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
	})
	-- Low-poly canopy: a few rotated green blocks.
	local greens = { Color3.fromRGB(70, 150, 50), Color3.fromRGB(90, 170, 60), Color3.fromRGB(60, 130, 45) }
	for i = 1, 3 do
		local s = (9 - i * 1.5) * scale
		Build.part(world, {
			Name = "Leaves",
			Size = Vector3.new(s, s * 0.9, s),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1), trunkH + (i - 0.5) * 3 * scale, rng:NextNumber(-1, 1)))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
			Color = greens[rng:NextInteger(1, #greens)],
			Material = Enum.Material.Grass,
			CanQuery = false,
		})
	end
end

local function rock(world: Instance, rng: Random, pos: Vector3, size: number)
	Build.part(world, {
		Name = "Rock",
		Size = Vector3.new(size, size * rng:NextNumber(0.6, 1), size * rng:NextNumber(0.8, 1.2)),
		CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
		Color = Color3.fromRGB(120, 124, 132):Lerp(Color3.fromRGB(90, 92, 100), rng:NextNumber()),
		Material = Enum.Material.Slate,
	})
end

local function bench(world: Instance, cf: CFrame)
	Build.part(world, { Name = "BenchSeat", Size = Vector3.new(6, 0.5, 2), CFrame = cf * CFrame.new(0, 1.8, 0), Color = WOOD, Material = Enum.Material.WoodPlanks })
	Build.part(world, { Name = "BenchBack", Size = Vector3.new(6, 2, 0.4), CFrame = cf * CFrame.new(0, 3, 0.9), Color = WOOD, Material = Enum.Material.WoodPlanks })
	for _, x in { -2.5, 2.5 } do
		Build.part(world, { Name = "BenchLeg", Size = Vector3.new(0.4, 1.8, 1.8), CFrame = cf * CFrame.new(x, 0.9, 0), Color = IRON, Material = Enum.Material.Metal })
	end
end

-- Straight fence between two points. Gaps are left where `gaps` (positions
-- along the fence, in studs from `a`, with half-widths) say so.
local function fence(world: Instance, a: Vector3, b: Vector3, style: string, gaps: { { number } }?)
	local dir = (b - a).Unit
	local length = (b - a).Magnitude
	local wood = style == "wood"
	local color = if wood then WOOD else IRON
	local material = if wood then Enum.Material.Wood else Enum.Material.Metal
	local step = if wood then 10 else 8
	local function inGap(d: number): boolean
		for _, g in (gaps or {}) :: { { number } } do
			if math.abs(d - g[1]) < g[2] then
				return true
			end
		end
		return false
	end
	local segStart: number? = nil
	local function rail(d0: number, d1: number)
		if d1 - d0 < 0.5 then
			return
		end
		local heights: { number } = if wood then { 1.6, 3.2 } else { 1, 3.6 }
		for _, h in heights do
			Build.part(world, {
				Name = "FenceRail",
				Size = Vector3.new(if wood then 0.5 else 0.25, if wood then 0.6 else 0.25, d1 - d0),
				CFrame = CFrame.lookAt(a + dir * ((d0 + d1) / 2), b) * CFrame.new(0, h, 0),
				Color = color,
				Material = material,
			})
		end
		if not wood then
			-- iron fences get thin pickets
			for d = d0 + 2, d1 - 1, 4 do
				Build.part(world, {
					Name = "Picket",
					Size = Vector3.new(0.15, 4, 0.15),
					CFrame = CFrame.new(a + dir * d + Vector3.new(0, 2, 0)),
					Color = color,
					Material = material,
					CanCollide = false,
					CanQuery = false,
				})
			end
		end
	end
	local d = 0
	while d <= length do
		local gap = inGap(d)
		if not gap then
			Build.part(world, {
				Name = "FencePost",
				Size = Vector3.new(if wood then 1 else 0.5, if wood then 4.2 else 4.6, if wood then 1 else 0.5),
				CFrame = CFrame.new(a + dir * d + Vector3.new(0, if wood then 2.1 else 2.3, 0)),
				Color = color,
				Material = material,
			})
			segStart = segStart or d
		elseif segStart then
			rail(segStart, d - step)
			segStart = nil
		end
		local nextD = d + step
		if not gap and segStart and (nextD > length or inGap(nextD)) then
			rail(segStart, d)
			segStart = nil
		end
		d = nextD
	end
end

local function sign(world: Instance, cf: CFrame, width: number, height: number, lines: { any }, color: Color3?)
	local board = Build.part(world, {
		Name = "Sign",
		Size = Vector3.new(width, height, 0.5),
		CFrame = cf,
		Color = color or Color3.fromRGB(25, 28, 36),
		Material = if color then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic,
	})
	Build.surfaceText(board, lines)
	return board
end

-- Wooden signpost board at `pos`, readable from the north (spawn side), with a
-- diamond tip pointing the real direction: "west", "east" or "south".
local function arrowBoard(world: Instance, pos: Vector3, text: string, direction: string)
	local cf = CFrame.new(pos) -- Front face (-Z) looks north
	sign(world, cf, 16, 2.6, { { text = text, size = 80, color = Color3.fromRGB(255, 240, 210), font = Enum.Font.GothamBlack } }, WOOD)
	local tip = if direction == "west" then CFrame.new(-8.6, 0, 0) elseif direction == "east" then CFrame.new(8.6, 0, 0) else CFrame.new(0, -1.9, 0)
	Build.part(world, {
		Name = "ArrowTip",
		Size = Vector3.new(1.84, 1.84, 0.5),
		CFrame = cf * tip * CFrame.Angles(0, 0, math.rad(45)),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
	})
end

-- Island --------------------------------------------------------------------------

local function buildIsland(world: Instance, rng: Random)
	local hx, hz = M.IslandHalfX, M.IslandHalfZ
	Build.part(world, {
		Name = "Water",
		Size = Vector3.new(2000, 1, 2000),
		CFrame = CFrame.new(0, M.WaterLevel, 0),
		Color = Color3.fromRGB(40, 140, 210),
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.2,
		Locked = true,
	})
	Build.part(world, {
		Name = "IslandTop",
		Size = Vector3.new(hx * 2, 10, hz * 2),
		CFrame = CFrame.new(0, -5, 0),
		Color = GRASS,
		Material = Enum.Material.Grass,
		Locked = true,
	})
	local depth = -M.WaterLevel + 10
	Build.part(world, {
		Name = "IslandCliff",
		Size = Vector3.new(hx * 2 - 6, depth, hz * 2 - 6),
		CFrame = CFrame.new(0, -10 - depth / 2, 0),
		Color = Color3.fromRGB(110, 100, 92),
		Material = Enum.Material.Slate,
		Locked = true,
	})
	-- Rocky cliff chunks around the shore.
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local alongZ = side[1] ~= 0
		local span = if alongZ then hz else hx
		for t = -span, span, 26 do
			local pos = if alongZ
				then Vector3.new(side[1] * (hx + rng:NextNumber(-2, 8)), rng:NextNumber(-60, -6), t + rng:NextNumber(-8, 8))
				else Vector3.new(t + rng:NextNumber(-8, 8), rng:NextNumber(-60, -6), side[2] * (hz + rng:NextNumber(-2, 8)))
			rock(world, rng, pos, rng:NextNumber(22, 40))
		end
	end
	-- Wooden perimeter fence, open at the north gate.
	local inset = 6
	fence(world, Vector3.new(-hx + inset, 0, -hz + inset), Vector3.new(hx - inset, 0, -hz + inset), "wood", { { hx - inset, 12 } })
	fence(world, Vector3.new(hx - inset, 0, -hz + inset), Vector3.new(hx - inset, 0, hz - inset), "wood")
	fence(world, Vector3.new(hx - inset, 0, hz - inset), Vector3.new(-hx + inset, 0, hz - inset), "wood", { { hx - inset, 12 } })
	fence(world, Vector3.new(-hx + inset, 0, hz - inset), Vector3.new(-hx + inset, 0, -hz + inset), "wood")
end

-- Plaza ------------------------------------------------------------------------------

local function buildPlaza(world: Instance)
	local x0, x1, z0, z1 = PLAZA.X - 160, PLAZA.X + 160, PLAZA.Z - 120, PLAZA.Z + 80
	reserve(x0, z0, x1, z1)
	flat(world, "Plaza", x0, z0, x1, z1, 0.4, Color3.fromRGB(214, 196, 160), Enum.Material.Pavement)
	-- Path out of the north gate to the island edge.
	flat(world, "GatePath", -12, -M.IslandHalfZ, 12, z0, 0.35, Color3.fromRGB(190, 175, 150), Enum.Material.Cobblestone)
	reserve(-14, -M.IslandHalfZ, 14, z0)

	-- "SPAWN / PLAZA" wooden arch over the north entrance.
	local gateZ = z0 + 4
	for _, x in { -14, 14 } do
		Build.part(world, { Name = "GatePost", Size = Vector3.new(2.5, 20, 2.5), CFrame = CFrame.new(x, 10, gateZ), Color = DARK_WOOD, Material = Enum.Material.Wood })
	end
	Build.part(world, { Name = "GateBeam", Size = Vector3.new(34, 2, 2.5), CFrame = CFrame.new(0, 20, gateZ), Color = DARK_WOOD, Material = Enum.Material.Wood })
	sign(world, CFrame.new(0, 17, gateZ + 1.5) * CFrame.Angles(0, math.pi, 0), 24, 4.5, {
		{ text = "SPAWN / PLAZA", size = 120, color = Color3.fromRGB(255, 240, 210) },
	}, WOOD)

	-- Central planter with a tree, benches around it.
	local planter = PLAZA + Vector3.new(0, 0, 10)
	Build.cylinder(world, planter + Vector3.new(0, 1, 0), 2, 26, { Name = "Planter", Color = Color3.fromRGB(150, 146, 140), Material = Enum.Material.Cobblestone })
	Build.cylinder(world, planter + Vector3.new(0, 2.05, 0), 0.2, 23, { Name = "PlanterSoil", Color = Color3.fromRGB(90, 140, 60), Material = Enum.Material.Grass })
	tree(world, Random.new(7), planter + Vector3.new(0, 2, 0), 1.2)
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local p = planter + Vector3.new(math.cos(a), 0, math.sin(a)) * 19
		bench(world, CFrame.lookAt(p, planter) * CFrame.Angles(0, math.pi, 0))
	end

	-- Signposts: west and east.
	local westPost = PLAZA + Vector3.new(-70, 0, 40)
	Build.part(world, { Name = "SignPole", Size = Vector3.new(1.2, 14, 1.2), CFrame = CFrame.new(westPost + Vector3.new(0, 7, 0)), Color = DARK_WOOD, Material = Enum.Material.Wood })
	arrowBoard(world, westPost + Vector3.new(0, 12.5, -0.9), "SKYSCRAPERS", "west")
	arrowBoard(world, westPost + Vector3.new(0, 8.5, -0.9), "POWER UPS", "south")
	local eastPost = PLAZA + Vector3.new(70, 0, 40)
	Build.part(world, { Name = "SignPole", Size = Vector3.new(1.2, 14, 1.2), CFrame = CFrame.new(eastPost + Vector3.new(0, 7, 0)), Color = DARK_WOOD, Material = Enum.Material.Wood })
	arrowBoard(world, eastPost + Vector3.new(0, 12.5, -0.9), "TELECOM TOWERS", "east")
	arrowBoard(world, eastPost + Vector3.new(0, 8.5, -0.9), "TUTORIAL TOWER", "east")

	-- How-to-play and leaderboard boards along the north side, facing south.
	local face = CFrame.Angles(0, math.pi, 0)
	sign(world, CFrame.new(PLAZA + Vector3.new(-105, 7, -70)) * face, 18, 11, {
		{ text = "HOW TO CLIMB", size = 64, color = Color3.fromRGB(255, 210, 60) },
		{ text = "SPACE at a tower: grab on", size = 34, color = Color3.new(1, 1, 1), font = Enum.Font.GothamMedium },
		{ text = "WASD: crawl  ·  SPACE: lunge up  ·  Q: let go", size = 34, color = Color3.new(1, 1, 1), font = Enum.Font.GothamMedium },
		{ text = "Climbing burns stamina. Mantle onto platforms to breathe.", size = 34, color = Color3.new(1, 1, 1), font = Enum.Font.GothamMedium },
		{ text = "Run out and you BLACK OUT and fall.", size = 34, color = Color3.fromRGB(255, 120, 120), font = Enum.Font.GothamMedium },
		{ text = "SPACE while falling: catch the wall!", size = 34, color = Color3.fromRGB(110, 230, 140), font = Enum.Font.GothamBold },
	})
	Build.part(world, {
		Name = "Leaderboard",
		Size = Vector3.new(16, 14, 0.5),
		CFrame = CFrame.new(PLAZA + Vector3.new(105, 8, -70)) * face,
		Color = Color3.fromRGB(20, 22, 30),
		Material = Enum.Material.SmoothPlastic,
	})
	for _, x in { -6, 6 } do
		for _, board in { { -105, 1.2 }, { 105, 1 } } do
			Build.part(world, {
				Name = "BoardLeg",
				Size = Vector3.new(0.6, 2, 0.6),
				CFrame = CFrame.new(PLAZA + Vector3.new(board[1] + x, 1, -69.6)),
				Color = IRON,
				Material = Enum.Material.Metal,
			})
		end
	end

	for _, p in { { -140, -100 }, { 140, -100 }, { -140, 60 }, { 140, 60 }, { -40, -40 }, { 40, -40 } } do
		lamp(world, PLAZA + Vector3.new(p[1], 0.4, p[2]))
	end
end

-- Paths and tower lots ---------------------------------------------------------------

local function towerCFrame(entry: any): CFrame
	local pos = Vector3.new(entry.X, 0, entry.Z)
	-- Face 0 (local -Z) looks at the main path.
	return CFrame.lookAt(pos, Vector3.new(0, 0, entry.Z))
end

local function buildPaths(world: Instance)
	local w = M.PathHalfWidth
	flat(world, "MainPath", -w, PATH_TOP - 4, w, PATH_BOTTOM + 4, 0.3, DIRT, Enum.Material.Ground)
	reserve(-w, PATH_TOP, w, PATH_BOTTOM)
	for z = PATH_TOP + 30, PATH_BOTTOM - 20, 70 do
		lamp(world, Vector3.new(-w - 4, 0, z))
		lamp(world, Vector3.new(w + 4, 0, z + 35))
	end
	for z = PATH_TOP + 120, PATH_BOTTOM - 60, 160 do
		bench(world, CFrame.new(-w - 6, 0, z) * CFrame.Angles(0, -math.pi / 2, 0))
		bench(world, CFrame.new(w + 6, 0, z + 80) * CFrame.Angles(0, math.pi / 2, 0))
	end
	for _, entry in Config.Layout do
		local side = if entry.X < 0 then -1 else 1
		local lotEdge = math.abs(entry.X) - M.LotHalf
		flat(world, "BranchPath", side * w, entry.Z - 9, side * lotEdge, entry.Z + 9, 0.3, DIRT, Enum.Material.Ground)
		reserve(side * w, entry.Z - 10, side * lotEdge, entry.Z + 10)
	end
end

local function buildLot(world: Instance, rng: Random, entry: any, def: any)
	local L = M.LotHalf
	local c = Vector3.new(entry.X, 0, entry.Z)
	reserve(c.X - L, c.Z - L, c.X + L, c.Z + L)
	flat(world, "LotPad", c.X - L, c.Z - L, c.X + L, c.Z + L, 0.2, Color3.fromRGB(150, 140, 128), Enum.Material.Concrete)

	-- Iron fence with a gate facing the path.
	local gateSide = if entry.X < 0 then 1 else -1 -- +1: east edge has the gate
	local corners = {
		Vector3.new(c.X - L, 0, c.Z - L),
		Vector3.new(c.X + L, 0, c.Z - L),
		Vector3.new(c.X + L, 0, c.Z + L),
		Vector3.new(c.X - L, 0, c.Z + L),
	}
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local isGateEdge = (gateSide == 1 and i == 2) or (gateSide == -1 and i == 4)
		fence(world, a, b, "iron", if isGateEdge then { { L, 12 } } else nil)
	end

	-- Utility boxes / equipment shelter.
	local back = -gateSide
	Build.part(world, {
		Name = "Shelter",
		Size = Vector3.new(14, 9, 12),
		CFrame = CFrame.new(c + Vector3.new(back * (L - 12), 4.5, L - 14)),
		Color = Color3.fromRGB(215, 215, 210),
		Material = Enum.Material.Concrete,
	})
	Build.part(world, {
		Name = "UtilityBox",
		Size = Vector3.new(5, 6, 3),
		CFrame = CFrame.new(c + Vector3.new(back * (L - 8), 3, -(L - 10))),
		Color = if entry.Difficulty == "HARD" then Color3.fromRGB(200, 50, 40) else Color3.fromRGB(110, 115, 125),
		Material = Enum.Material.Metal,
	})
	for _, z in { -L + 6, L - 6 } do
		lamp(world, c + Vector3.new(gateSide * (L - 6), 0.2, z))
	end
	rock(world, rng, c + Vector3.new(back * (L - 6), 1, rng:NextNumber(-20, 20)), 5)

	-- Name + difficulty sign by the gate, facing the path.
	local signPos = c + Vector3.new(gateSide * (L + 8), 0, -22)
	local facing = CFrame.lookAt(signPos, Vector3.new(0, 0, signPos.Z))
	for _, x in { -4, 4 } do
		Build.part(world, { Name = "SignLeg", Size = Vector3.new(0.6, 5, 0.6), CFrame = facing * CFrame.new(x, 2.5, 0.3), Color = IRON, Material = Enum.Material.Metal })
	end
	sign(world, facing * CFrame.new(0, 8, 0), 14, 7, {
		{ text = string.upper(entry.Name), size = 70, color = Color3.new(1, 1, 1) },
		{ text = entry.Size .. "  (" .. entry.Difficulty .. ")", size = 56, color = DIFFICULTY_COLORS[entry.Difficulty] or Color3.new(1, 1, 1) },
		{ text = "$" .. def.Payout .. "  ·  drain x" .. def.DrainMultiplier, size = 40, color = Color3.fromRGB(170, 180, 200), font = Enum.Font.GothamBold },
	})
end

-- Shop --------------------------------------------------------------------------------

local function buildShop(world: Instance)
	local s = SHOP
	local x0, x1, z0, z1 = s.X - 110, s.X + 110, s.Z - 70, s.Z + 90
	reserve(x0, z0, x1, z1)
	flat(world, "ShopYard", x0, z0, x1, z1, 0.4, Color3.fromRGB(205, 170, 120), Enum.Material.WoodPlanks)

	-- Fence with string lights, open to the north (path) side.
	fence(world, Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0), "wood", { { 110, 16 } })
	fence(world, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), "wood")
	fence(world, Vector3.new(x1, 0, z1), Vector3.new(x0, 0, z1), "wood", { { 110, 12 } })
	fence(world, Vector3.new(x0, 0, z1), Vector3.new(x0, 0, z0), "wood")
	for x = x0 + 5, x1 - 5, 7 do
		for _, z in { z0, z1 } do
			Build.part(world, {
				Name = "StringLight",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.7,
				CFrame = CFrame.new(x, 4.6, z),
				Color = Color3.fromRGB(255, 220, 140),
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
				Tags = { "StreetLight" },
			})
		end
	end

	-- The stall, facing north toward the path.
	local stallCF = CFrame.new(s + Vector3.new(0, 0, 25))
	local counter = Build.part(world, {
		Name = "ShopStall",
		Size = Vector3.new(30, 5, 6),
		CFrame = stallCF * CFrame.new(0, 2.5, -6),
		Color = Color3.fromRGB(150, 100, 60),
		Material = Enum.Material.WoodPlanks,
	})
	Build.part(world, { Name = "StallBack", Size = Vector3.new(32, 16, 2), CFrame = stallCF * CFrame.new(0, 8, 6), Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.WoodPlanks })
	for _, x in { -15, 15 } do
		Build.part(world, { Name = "StallPost", Size = Vector3.new(1.4, 16, 1.4), CFrame = stallCF * CFrame.new(x, 8, -8), Color = DARK_WOOD, Material = Enum.Material.Wood })
	end
	-- Yellow and white striped awning.
	for i = 0, 7 do
		Build.part(world, {
			Name = "Awning",
			Size = Vector3.new(4.2, 0.5, 15),
			CFrame = stallCF * CFrame.new(-14.7 + i * 4.2, 14, -1) * CFrame.Angles(math.rad(14), 0, 0),
			Color = if i % 2 == 0 then Color3.fromRGB(255, 205, 40) else Color3.fromRGB(250, 250, 245),
			Material = Enum.Material.Fabric,
		})
	end
	sign(world, stallCF * CFrame.new(0, 19, 5.5) * CFrame.Angles(0, math.pi, 0), 26, 6, {
		{ text = "POWER UP SHOP", size = 130, color = Color3.fromRGB(255, 215, 50) },
		{ text = "BUY POWER UPS", size = 70, color = Color3.fromRGB(255, 255, 255), font = Enum.Font.GothamBold },
	}, Color3.fromRGB(90, 55, 30))
	-- Giant lemon on the roof.
	Build.part(world, {
		Name = "Lemon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 7,
		CFrame = stallCF * CFrame.new(0, 26, 5),
		Color = Color3.fromRGB(255, 220, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	Build.part(world, {
		Name = "LemonLeaf",
		Size = Vector3.new(3.5, 0.4, 1.6),
		CFrame = stallCF * CFrame.new(2.5, 29.5, 5) * CFrame.Angles(0, 0, math.rad(25)),
		Color = Color3.fromRGB(80, 170, 60),
		Material = Enum.Material.SmoothPlastic,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open shop"
	prompt.ObjectText = "Power Up Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	-- Picnic tables with yellow umbrellas.
	for _, x in { -60, 60 } do
		local t = s + Vector3.new(x, 0, -20)
		Build.part(world, { Name = "Table", Size = Vector3.new(8, 0.6, 5), CFrame = CFrame.new(t + Vector3.new(0, 3, 0)), Color = WOOD, Material = Enum.Material.WoodPlanks })
		Build.part(world, { Name = "TableLeg", Size = Vector3.new(1, 3, 1), CFrame = CFrame.new(t + Vector3.new(0, 1.5, 0)), Color = DARK_WOOD, Material = Enum.Material.Wood })
		for _, dz in { -4.5, 4.5 } do
			Build.part(world, { Name = "TableBench", Size = Vector3.new(8, 0.5, 1.6), CFrame = CFrame.new(t + Vector3.new(0, 1.8, dz)), Color = WOOD, Material = Enum.Material.WoodPlanks })
		end
		Build.part(world, { Name = "UmbrellaPole", Size = Vector3.new(0.4, 11, 0.4), CFrame = CFrame.new(t + Vector3.new(0, 5.5, 0)), Color = Color3.new(1, 1, 1), Material = Enum.Material.Metal, CanCollide = false })
		Build.cylinder(world, t + Vector3.new(0, 11, 0), 0.8, 14, { Name = "Umbrella", Color = Color3.fromRGB(255, 210, 40), Material = Enum.Material.Fabric, CanCollide = false })
	end
	for _, x in { -100, 100 } do
		for _, z in { z0 + 10, z1 - 10 } do
			lamp(world, Vector3.new(x, 0.4, z))
		end
	end
end

-- Scenery ---------------------------------------------------------------------------

local function scatterTrees(world: Instance, rng: Random)
	local hx, hz = M.IslandHalfX - 14, M.IslandHalfZ - 14
	for x = -hx, hx, 34 do
		for z = -hz, hz, 34 do
			local px, pz = x + rng:NextNumber(-9, 9), z + rng:NextNumber(-9, 9)
			if math.abs(px) < hx and math.abs(pz) < hz and isClear(px, pz, 8) then
				if rng:NextNumber() < 0.75 then
					tree(world, rng, Vector3.new(px, 0, pz), rng:NextNumber(0.9, 1.4))
				elseif rng:NextNumber() < 0.5 then
					rock(world, rng, Vector3.new(px, 1, pz), rng:NextNumber(4, 9))
				end
			end
		end
	end
end

-- Public -------------------------------------------------------------------------------

function WorldBuilder.build()
	local world = Workspace:FindFirstChild("World")
	local towers = Workspace:FindFirstChild("Towers")
	if not world then
		world = Instance.new("Folder")
		world.Name = "World"
		local rng = Random.new(2024)
		buildIsland(world, rng)
		buildPlaza(world)
		buildPaths(world)
		for _, entry in Config.Layout do
			buildLot(world, rng, entry, Config.TowerTypes[entry.Type])
		end
		buildShop(world)
		scatterTrees(world, rng)
		world.Parent = Workspace
	end
	if not towers then
		towers = Instance.new("Folder")
		towers.Name = "Towers"
		for _, entry in Config.Layout do
			TowerBuilder.build(towers, entry, Config.TowerTypes[entry.Type], towerCFrame(entry), M.LotHalf)
		end
		towers.Parent = Workspace
	end
	return world, towers
end

WorldBuilder.PlazaSpawn = CFrame.new(PLAZA + Vector3.new(0, 4, -60))

return WorldBuilder
