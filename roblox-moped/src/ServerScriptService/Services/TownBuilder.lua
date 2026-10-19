--[[
	TownBuilder  (ModuleScript, ServerScriptService/Services)

	Builds the whole map at server start from the detailed pieces in
	Buildings.lua and Props.lua. The CORE (ground, roads, spawn, mission
	spots) is built before the game starts; the scenery is then built in the
	background in small steps so the server never stalls.

	Zones (x east, z south; 1 stud ~ 0.28 m, a moped does ~45 studs/s)
	  Kleindorf       main street z=0, x -300..300: Fachwerk and plaster
	                  houses, bakery, general store, garage, Werkstatt,
	                  petrol station Sued, bus stop, parked cars, lamps
	  Marktplatz      cobbled square (0,-150): fountain, maypole, church,
	                  Gasthof with beer garden, advertising column
	  Schnellstrasse  highway east along z=0 to x=2400, then north to z=-1900:
	                  power poles, reflector posts, petrol station Nord (x=1500)
	  Hofweg          farm lane south from the highway at x=1200: barn, silos,
	                  tractor, hay bales, fields, orchard
	  Waldweg loop    narrow lanes west/north: (-1500,0) (-1500,-1200) (0,-1200)
	                  through fir forest (the checkpoint run)
	  Huegeldorf      hill hamlet on a 36-stud plateau up a ramp road

	It only runs when GameConfig.GenerateTown is true AND Workspace has no
	"Town" folder. To use your own map: put it in a Folder named "Town", tag
	the props (see README) and add the MissionSpots.
	Replace any building with your own model via ReplicatedStorage/TownModels
	(see Buildings.lua).

	Tags created: GarageDoor, Workshop, PetrolStation, MissionBoard
	Spots created (Workspace/MissionSpots): everything MissionData asks for.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local ModelKit = require(Shared.ModelKit)
local Buildings = require(script.Parent.Buildings)
local Props = require(script.Parent.Props)

local TownBuilder = {}

local V3, CF = Vector3.new, CFrame.new
local rgb = Color3.fromRGB
local M = Enum.Material

local rng = Random.new(1204)
local rects = {} -- obstacles for scattering: {x1, z1, x2, z2}
local town: Folder
local roads: Folder
local scenery: Folder
local houses: Folder

local C = {
	grass = rgb(104, 146, 74),
	asphalt = rgb(62, 64, 70),
	lane = rgb(84, 84, 86),
	cobble = rgb(150, 138, 120),
	marking = rgb(236, 236, 228),
	yellow = rgb(240, 200, 60),
}

----------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------
local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function addRect(x1: number, z1: number, x2: number, z2: number)
	table.insert(rects, { math.min(x1, x2), math.min(z1, z2), math.max(x1, x2), math.max(z1, z2) })
end

local function blocked(x: number, z: number, r: number): boolean
	for _, q in ipairs(rects) do
		if x > q[1] - r and x < q[3] + r and z > q[2] - r and z < q[4] + r then
			return true
		end
	end
	return false
end

local function label(part: BasePart, text: string, lift: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 36)
	gui.StudsOffset = V3(0, lift or (part.Size.Y / 2 + 3), 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 350
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.25
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Parent = gui
end

local function tag(inst: Instance, name: string)
	CollectionService:AddTag(inst, name)
end

local function yield()
	task.wait()
end

local function step(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		print(("[TownBuilder] %s done"):format(name))
	else
		warn(("[TownBuilder] step '%s' FAILED: %s"):format(name, tostring(err)))
	end
	yield()
end

-- axis-aligned road. level = top surface height.
local function road(x1: number, z1: number, x2: number, z2: number, width: number, level: number, o: { [string]: any }?)
	o = o or {}
	local horizontal = z1 == z2
	local len = horizontal and math.abs(x2 - x1) or math.abs(z2 - z1)
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local size = horizontal and V3(len, 0.4, width) or V3(width, 0.4, len)
	mk(roads, "Road", size, CF(cx, level - 0.2, cz), o.color or C.asphalt, M.Asphalt)
	addRect(cx - size.X / 2, cz - size.Z / 2, cx + size.X / 2, cz + size.Z / 2)
	local function strip(offset: number, w: number, color: Color3)
		local sz = horizontal and V3(len - 2, 0.1, w) or V3(w, 0.1, len - 2)
		local at = horizontal and V3(cx, level + 0.03, cz + offset) or V3(cx + offset, level + 0.03, cz)
		local p = mk(roads, "Line", sz, CF(at), color, M.SmoothPlastic)
		p.CanCollide = false
		p.CanQuery = false
	end
	if o.edge then
		strip(width / 2 - 1.2, 0.45, C.marking)
		strip(-(width / 2 - 1.2), 0.45, C.marking)
	end
	if o.dashed then
		local period, dash = 26, 9
		local start = (horizontal and math.min(x1, x2) or math.min(z1, z2)) + 6
		local pos = start
		local stop = start + len - 12
		while pos < stop do
			local mid = pos + dash / 2
			local dsize = horizontal and V3(dash, 0.1, 0.6) or V3(0.6, 0.1, dash)
			local at = horizontal and V3(mid, level + 0.03, cz) or V3(cx, level + 0.03, mid)
			local p = mk(roads, "Dash", dsize, CF(at), C.marking, M.SmoothPlastic)
			p.CanCollide = false
			p.CanQuery = false
			pos += period
		end
	end
end

local ROOF_STYLES = {
	{ rgb(168, 72, 54), M.ClayRoofTiles },
	{ rgb(146, 62, 48), M.ClayRoofTiles },
	{ rgb(118, 76, 64), M.ClayRoofTiles },
	{ rgb(92, 96, 104), M.Slate },
}

-- a village house with its footprint registered so trees keep clear
local function placeHouse(x: number, z: number, yaw: number, style: string, y: number?, extra: { [string]: any }?)
	local o = { rng = rng, style = style }
	for k, v in pairs(extra or {}) do
		o[k] = v
	end
	local model, r, body = Buildings.house(houses, CF(x, y or 0, z) * CFrame.Angles(0, yaw, 0), o)
	addRect(x - r, z - r, x + r, z + r)
	return model, body
end

local function scatterTrees(count: number, x1: number, z1: number, x2: number, z2: number, kinds: { string }, clearance: number)
	local placed, tries = 0, 0
	local n = math.floor(count * (GameConfig.TownDetail or 1))
	while placed < n and tries < n * 6 do
		tries += 1
		local x, z = rng:NextNumber(x1, x2), rng:NextNumber(z1, z2)
		if not blocked(x, z, clearance) then
			Props.tree(scenery, V3(x, 0, z), rng, kinds[rng:NextInteger(1, #kinds)])
			placed += 1
			if placed % 25 == 0 then
				yield()
			end
		end
	end
end

----------------------------------------------------------------------------
-- BUILD
----------------------------------------------------------------------------
function TownBuilder.build()
	if not GameConfig.GenerateTown or Workspace:FindFirstChild("Town") then
		return
	end

	town = Instance.new("Folder")
	town.Name = "Town"
	town.Parent = Workspace
	roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = town
	scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = town
	houses = Instance.new("Folder")
	houses.Name = "Buildings"
	houses.Parent = town

	local z0, z1, rise = -1900, -2200, 36 -- hill ramp: start z, end z, plateau height

	----------------------------------------------------------------------
	-- CORE (synchronous): light, ground, roads, ramp, spawn, mission spots
	----------------------------------------------------------------------
	step("light", function()
		Lighting.ClockTime = 15.2
		Lighting.Brightness = 2.6
		Lighting.OutdoorAmbient = rgb(128, 132, 140)
		Lighting.ColorShift_Top = rgb(255, 244, 224)
		Lighting.EnvironmentDiffuseScale = 0.6
		Lighting.EnvironmentSpecularScale = 0.5
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
		atmosphere.Density = 0.3
		atmosphere.Offset = 0.25
		atmosphere.Color = rgb(196, 214, 236)
		atmosphere.Decay = rgb(240, 214, 190)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 1.4
		atmosphere.Parent = Lighting
		local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
		cc.Saturation = 0.12
		cc.Contrast = 0.06
		cc.Parent = Lighting
		local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
		bloom.Intensity = 0.25
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
		local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
		rays.Intensity = 0.06
		rays.Parent = Lighting
	end)

	step("ground", function()
		for _, cx in ipairs({ -1300, 500, 2300 }) do
			for _, cz in ipairs({ -2500, -700, 1100 }) do
				mk(town, "Ground", V3(1800, 4, 1800), CF(cx, -2, cz), C.grass, M.Grass)
			end
		end
	end)

	step("roads", function()
		road(300, 0, 2400, 0, 32, 0.20, { dashed = true, edge = true }) -- Schnellstrasse east
		road(2400, 0, 2400, -1900, 32, 0.20, { dashed = true, edge = true }) -- ...north
		road(1200, 0, 1200, 640, 18, 0.22, { edge = true }) -- Hofweg to the farm
		road(-1500, 0, -300, 0, 16, 0.24, { color = C.lane }) -- Landstrasse west
		road(-1500, -1200, -1500, 0, 16, 0.24, { color = C.lane }) -- Waldweg north
		road(-1500, -1200, 0, -1200, 16, 0.24, { color = C.lane })
		road(0, -1200, 0, 0, 16, 0.24, { color = C.lane }) -- Marktstrasse back to the village
		road(-300, 0, 300, 0, 24, 0.26, { dashed = true }) -- Hauptstrasse (village main street)

		-- Marktplatz
		mk(town, "Marktplatz", V3(150, 0.5, 130), CF(0, 0.05, -150), C.cobble, M.Cobblestone)
		mk(town, "MarktplatzRim", V3(154, 0.4, 134), CF(0, 0.02, -150), rgb(120, 114, 104), M.Granite)
		addRect(-75, -215, 75, -85)

		-- hill ramp to Huegeldorf: a thick slab so there is no hollow underneath
		local a, b = V3(2400, 0, z0), V3(2400, rise, z1)
		local dir = b - a
		local len = dir.Magnitude
		local lookCF = CFrame.lookAt((a + b) / 2, (a + b) / 2 + dir)
		mk(town, "RampSlab", V3(44, 40, len), lookCF * CF(0, -20, 0), C.grass, M.Grass)
		mk(roads, "RampRoad", V3(18, 0.4, len), lookCF * CF(0, 0.2, 0), C.asphalt, M.Asphalt)
		addRect(2370, z1, 2430, z0)
		mk(town, "Plateau", V3(500, rise, 520), CF(2400, rise / 2, z1 - 260), C.grass, M.Grass)
		mk(roads, "HamletRoad", V3(18, 0.4, 500), CF(2400, rise + 0.2, z1 - 250), C.lane, M.Asphalt)
		addRect(2150, z1 - 520, 2650, z1)
	end)

	step("spawn + spots", function()
		local spawn = Instance.new("SpawnLocation")
		spawn.Anchored = true
		spawn.Size = V3(12, 1, 12)
		spawn.Position = V3(0, 0.8, 56)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = town
		mk(roads, "SpawnPad", V3(16, 0.3, 16), CF(0, 0.3, 56), C.cobble, M.Cobblestone).CanCollide = false

		local spots = Instance.new("Folder")
		spots.Name = "MissionSpots"
		spots.Parent = Workspace
		local positions = {
			Spot_Bakery = V3(-200, 0.6, -10),
			Spot_Dorfladen = V3(200, 0.6, -10),
			Spot_Gasthof = V3(0, 0.6, -200),
			Spot_Farm = V3(1200, 0.6, 570),
			Spot_Huegeldorf = V3(2400, rise + 0.6, z1 - 250),
			CP_Forest1 = V3(-900, 0.6, 0),
			CP_Forest2 = V3(-1500, 0.6, -300),
			CP_Forest3 = V3(-1500, 0.6, -1000),
			CP_Forest4 = V3(-900, 0.6, -1200),
			CP_Forest5 = V3(-300, 0.6, -1200),
		}
		for name, pos in pairs(positions) do
			local size = name:sub(1, 2) == "CP" and 20 or 14
			local p = mk(spots, name, V3(size, 0.4, size), CF(pos), rgb(255, 220, 60), M.Neon)
			p.CanCollide = false
			p.CanQuery = false
			p.Transparency = 0.55
			label(p, (name:gsub("^%a+_", "")), 6)
		end
	end)

	----------------------------------------------------------------------
	-- SCENERY (background, in small steps)
	----------------------------------------------------------------------
	task.spawn(function()
		TownBuilder.buildScenery(z0, z1, rise)
		print("[TownBuilder] scenery complete")
	end)
end

function TownBuilder.buildScenery(z0: number, z1: number, rise: number)
	----------------------------------------------------------------------
	-- Kleindorf
	----------------------------------------------------------------------
	step("Kleindorf houses", function()
		-- pavements, kerbs and zebra crossings on the main street
		for _, s in ipairs({ -1, 1 }) do
			Props.sidewalk(roads, V3(-300, 0, s * 15), V3(-12, 0, s * 15), 6, -s) -- kerb on the street side
			Props.sidewalk(roads, V3(12, 0, s * 15), V3(300, 0, s * 15), 6, -s)
		end
		for _, x in ipairs({ -120, 120 }) do
			Props.crosswalk(roads, CF(x, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 24)
		end

		local reserved = { -200, -80, 80, 200 }
		local function isReserved(x: number): boolean
			for _, r in ipairs(reserved) do
				if math.abs(x - r) < 38 then
					return true
				end
			end
			return false
		end
		local styles = { "putz", "brick", "stone", "putz", "fachwerk" }
		for x = -270, 270, 46 do
			if not isReserved(x) and math.abs(x) > 16 then
				local centre = math.abs(x) < 130
				local sN = centre and "fachwerk" or styles[rng:NextInteger(1, #styles)]
				local sS = centre and "fachwerk" or styles[rng:NextInteger(1, #styles)]
				placeHouse(x + rng:NextInteger(-4, 4), -42, 0, sN)
				placeHouse(x + rng:NextInteger(-4, 4), 42, math.pi, sS)
				yield()
			end
		end

		-- second row behind the main street houses for a denser village
		for _, x in ipairs({ -262, -214, -166, 166, 214, 262 }) do
			for _, side in ipairs({ -1, 1 }) do
				local z = side * 92
				if not blocked(x, z, 24) then
					placeHouse(x + rng:NextInteger(-5, 5), z, side == -1 and 0 or math.pi, styles[rng:NextInteger(1, #styles)], 0, { fancy = false })
				end
			end
			yield()
		end

		-- shops
		local bakery, bakeryBody = Buildings.shop(houses, CF(-200, 0, -42), { rng = rng, name = "Baeckerei", text = "BAECKEREI", wall = rgb(240, 214, 160), roof = ROOF_STYLES[1][1], hangText = "Brezel" })
		addRect(-224, -66, -176, -18)
		local store = Buildings.shop(houses, CF(200, 0, -42), { rng = rng, name = "Dorfladen", text = "DORFLADEN", wall = rgb(200, 222, 200), roof = ROOF_STYLES[3][1], awning = { rgb(40, 110, 70), rgb(246, 244, 238) }, hangText = "Laden" })
		addRect(176, -66, 224, -18)

		-- garage + workshop on the south side facing the street
		local garage, gr, gbody = Buildings.garage(houses, CF(-80, 0, 40) * CFrame.Angles(0, math.pi, 0), { rng = rng, name = "Garage", text = "GARAGE", wall = rgb(190, 160, 120) })
		tag(gbody, "GarageDoor")
		addRect(-80 - gr, 40 - gr, -80 + gr, 40 + gr)
		local werk, wr, wbody = Buildings.garage(houses, CF(80, 0, 40) * CFrame.Angles(0, math.pi, 0), { rng = rng, name = "Werkstatt", text = "KFZ-WERKSTATT" })
		tag(wbody, "Workshop")
		addRect(80 - wr, 40 - wr, 80 + wr, 40 + wr)
		local _, pr = Buildings.petrolStation(houses, CF(-200, 0, 46) * CFrame.Angles(0, math.pi, 0), { rng = rng, name = "TankstelleSued", color = rgb(214, 54, 44) })
		addRect(-200 - pr, 46 - pr, -200 + pr, 46 + pr)
	end)

	step("village streetscape", function()
		-- lamps, street trees, parked cars, bus stop, post box
		for x = -270, 270, 45 do
			Props.lamp(scenery, CF(x, 0, -19) * CFrame.Angles(0, math.pi, 0))
			Props.lamp(scenery, CF(x + 22, 0, 19))
		end
		for x = -260, 260, 52 do
			if math.abs(x) > 20 then
				Props.tree(scenery, V3(x + rng:NextNumber(-5, 5), 0, -21), rng, "oak")
				Props.tree(scenery, V3(x + 26 + rng:NextNumber(-5, 5), 0, 21), rng, "oak")
			end
		end
		local carColors = { rgb(60, 110, 170), rgb(190, 60, 52), rgb(230, 200, 70), rgb(240, 238, 230), rgb(70, 120, 84), rgb(90, 96, 104) }
		for i, x in ipairs({ -250, -160, -40, 30, 150, 240, 120, -120 }) do
			local side = (i % 2 == 0) and 1 or -1
			Props.car(scenery, CF(x, 0, side * 9.6) * CFrame.Angles(0, side * math.pi / 2, 0), (i % 3 == 0) and "bubble" or "estate", carColors[(i - 1) % #carColors + 1])
		end
		Props.busStop(scenery, CF(-40, 0, 20) * CFrame.Angles(0, math.pi, 0), "Kleindorf Mitte")
		Props.busStop(scenery, CF(60, 0, -20), "Kleindorf Mitte")
		Props.postBox(scenery, CF(-6, 0, -17))
		Props.litfass(scenery, CF(-16, 0, -17))
		Props.bench(scenery, CF(30, 0, 18) * CFrame.Angles(0, math.pi, 0))

		-- village entrance signs
		Props.roadSign(scenery, CF(305, 0, -19) * CFrame.Angles(0, math.pi / 2, 0), "ortsschild", "KLEINDORF")
		Props.roadSign(scenery, CF(-305, 0, 19) * CFrame.Angles(0, -math.pi / 2, 0), "ortsschild", "KLEINDORF")
		Props.roadSign(scenery, CF(318, 0, -19) * CFrame.Angles(0, math.pi / 2, 0), "limit", "50")
		Props.roadSign(scenery, CF(-318, 0, 19) * CFrame.Angles(0, -math.pi / 2, 0), "limit", "50")
		Props.roadSign(scenery, CF(-20, 0, -20), "limit", "30")
		Props.roadSign(scenery, CF(20, 0, 20) * CFrame.Angles(0, math.pi, 0), "limit", "30")
		Props.roadSign(scenery, CF(14, 0, -14) * CFrame.Angles(0, math.pi, 0), "stop")

		-- job board next to the spawn
		local board = mk(scenery, "JobBoard", V3(12, 8, 1.2), CF(34, 6.4, -23), rgb(110, 80, 52), M.WoodPlanks)
		for _, sx in ipairs({ -5, 5 }) do
			mk(scenery, "BoardPost", V3(1.2, 7, 1.2), CF(34 + sx, 3.5, -23), rgb(86, 58, 40), M.Wood)
		end
		mk(scenery, "BoardRoof", V3(14, 0.6, 3.2), CF(34, 10.8, -23.4) * CFrame.Angles(math.rad(-12), 0, 0), rgb(120, 70, 54), M.WoodPlanks)
		for i = 0, 4 do
			local paper = mk(scenery, "Notice", V3(1.8, 2.4, 0.1), CF(29.8 + i * 2.1, 6.6 + (i % 2) * 0.8, -22.35), rgb(246, 240, 220), M.SmoothPlastic)
			paper.CanCollide = false
		end
		local head = mk(scenery, "BoardHead", V3(10, 1.6, 0.2), CF(34, 9.4, -22.35), rgb(40, 34, 30), M.Wood)
		ModelKit.signText(head, "AUFTRAEGE", Enum.NormalId.Back, rgb(240, 214, 140))
		tag(board, "MissionBoard")
		addRect(24, -28, 44, -18)
	end)

	----------------------------------------------------------------------
	-- Marktplatz
	----------------------------------------------------------------------
	step("Marktplatz", function()
		Props.fountain(scenery, CF(0, 0.3, -150))
		Props.maibaum(scenery, CF(-45, 0.3, -120))
		Props.litfass(scenery, CF(48, 0.3, -112))
		for i = -3, 3 do
			Props.lamp(scenery, CF(i * 20, 0.3, -214))
			Props.lamp(scenery, CF(i * 20, 0.3, -86) * CFrame.Angles(0, math.pi, 0))
		end
		for _, x in ipairs({ -52, 52 }) do
			for _, z in ipairs({ -130, -170 }) do
				Props.bench(scenery, CF(x, 0.3, z) * CFrame.Angles(0, x > 0 and math.pi / 2 or -math.pi / 2, 0))
			end
		end
		-- market stalls along the north and south edges of the square
		for i, x in ipairs({ -60, -34, -8, 18, 44 }) do
			Props.marketStall(scenery, CF(x, 0.3, -96) * CFrame.Angles(0, math.pi, 0), i)
		end
		for i, x in ipairs({ -60, -34 }) do
			Props.marketStall(scenery, CF(x, 0.3, -206), i + 1)
		end
		-- the church on the west side faces the square
		local _, cr = Buildings.church(houses, CF(-150, 0, -150) * CFrame.Angles(0, math.pi / 2, 0), { rng = rng })
		addRect(-150 - 40, -150 - 30, -150 + 40, -150 + 30)
		-- Gasthof on the north side
		Buildings.gasthof(houses, CF(62, 0, -246), { rng = rng })
		addRect(30, -280, 100, -225)
		-- houses on the east side
		placeHouse(140, -150, -math.pi / 2, "fachwerk")
		placeHouse(140, -200, -math.pi / 2, "putz")
		placeHouse(-62, -246, 0, "fachwerk")
		Props.car(scenery, CF(-30, 0.3, -96) * CFrame.Angles(0, math.pi / 2, 0), "bubble", rgb(230, 200, 70))
	end)

	----------------------------------------------------------------------
	-- Schnellstrasse
	----------------------------------------------------------------------
	step("highway", function()
		local _, pr = Buildings.petrolStation(houses, CF(1500, 0, 46) * CFrame.Angles(0, math.pi, 0), { rng = rng, name = "TankstelleNord", color = rgb(40, 110, 190), text = "AUTOHOF" })
		addRect(1500 - pr, 46 - pr, 1500 + pr, 46 + pr)
		-- power poles with wires, reflector posts, bus stop, signs
		local prevX
		for x = 360, 2380, 90 do
			Props.powerPole(scenery, CF(x, 0, -26) * CFrame.Angles(0, math.pi / 2, 0)) -- crossarm runs across the road
			if prevX then
				for _, dz in ipairs({ -4, 0, 4 }) do
					Props.wire(scenery, V3(prevX, 25.4, -26 + dz), V3(x, 25.4, -26 + dz), 2.2)
				end
			end
			prevX = x
			if x % 270 == 0 then
				yield()
			end
		end
		for x = 340, 2380, 60 do
			Props.reflectorPost(scenery, CF(x, 0, -18) * CFrame.Angles(0, math.pi, 0))
			Props.reflectorPost(scenery, CF(x, 0, 18))
		end
		for z = -60, -1880, -60 do
			Props.reflectorPost(scenery, CF(2382, 0, z) * CFrame.Angles(0, -math.pi / 2, 0))
			Props.reflectorPost(scenery, CF(2418, 0, z) * CFrame.Angles(0, math.pi / 2, 0))
		end
		Props.roadSign(scenery, CF(700, 0, 20), "limit", "100")
		Props.roadSign(scenery, CF(1300, 0, 22), "vorfahrt")
		Props.roadSign(scenery, CF(2370, 0, 22) * CFrame.Angles(0, math.pi, 0), "curve")
		Props.busStop(scenery, CF(900, 0, 24) * CFrame.Angles(0, math.pi, 0), "Autohof")
		-- trees along the road
		scatterTrees(110, 340, -520, 2300, -44, { "oak", "birch", "fir" }, 18)
		scatterTrees(70, 340, 44, 2300, 540, { "oak", "birch", "orchard" }, 18)
	end)

	----------------------------------------------------------------------
	-- Farm
	----------------------------------------------------------------------
	step("farm", function()
		Props.fenceRun(scenery, V3(1184, 0, 70), V3(1184, 0, 600))
		Props.fenceRun(scenery, V3(1216, 0, 70), V3(1216, 0, 600))
		local barn, _, bbody = Buildings.barn(houses, CF(1170, 0, 690), { rng = rng })
		addRect(1100, 650, 1260, 740)
		placeHouse(1250, 640, -math.pi / 2, "stone", 0, { name = "Bauernhaus", w = 34, d = 26 })
		Props.tractor(scenery, CF(1215, 0, 580) * CFrame.Angles(0, math.pi * 0.8, 0), rgb(52, 112, 64))
		for i = 0, 4 do
			Props.haybale(scenery, CF(1096 + i * 6, 0, 735 - (i % 2) * 4.5))
		end
		Props.haybale(scenery, CF(1102, 4.4, 735))
		Props.haybale(scenery, CF(1108, 4.4, 731))
		-- fields with crop rows
		local fields = { { 1420, 330, 206, 182, 92 }, { 980, 330, 112, 152, 64 }, { 1420, 90, 150, 170, 80 } }
		for _, f in ipairs(fields) do
			mk(town, "Field", V3(220, 0.3, 240), CF(f[1], 0.15, f[2]), rgb(f[3], f[4], f[5]), M.Grass)
			for k = -4, 4 do
				local row = mk(scenery, "CropRow", V3(220, 0.5, 1.4), CF(f[1], 0.45, f[2] + k * 26), rgb(f[3] * 0.82, f[4] * 0.82, f[5] * 0.78), M.Grass)
				row.CanCollide = false
			end
		end
		addRect(870, 20, 1530, 470)
		-- orchard + pond
		for i = 0, 3 do
			for j = 0, 2 do
				Props.tree(scenery, V3(1320 + i * 22, 0, 560 + j * 24), rng, "orchard")
			end
		end
		local pond = mk(town, "Pond", V3(0.5, 70, 70), CF(1060, 0.1, 560) * CFrame.Angles(0, 0, math.pi / 2), rgb(88, 142, 176), M.Glass, Enum.PartType.Cylinder)
		pond.Transparency = 0.25
		pond.CanCollide = false
		for k = 1, 14 do
			local a = k / 14 * math.pi * 2
			local rock = mk(scenery, "PondRock", V3(rng:NextNumber(3, 6), 2, rng:NextNumber(3, 6)), CF(1060 + math.cos(a) * 36, 0.8, 560 + math.sin(a) * 36) * CFrame.Angles(0, a, 0), rgb(140, 138, 132), M.Granite)
			rock.CanCollide = false
		end
		Props.wayCross(scenery, CF(1230, 0, 40))
	end)

	----------------------------------------------------------------------
	-- Hamlet on the plateau
	----------------------------------------------------------------------
	step("Huegeldorf", function()
		for i = 0, 5 do
			local z = z1 - 70 - i * 70
			placeHouse(2400 - 36, z, math.pi / 2, (i % 2 == 0) and "fachwerk" or "putz", rise)
			placeHouse(2400 + 36, z - 30, -math.pi / 2, (i % 2 == 0) and "putz" or "fachwerk", rise)
			yield()
		end
		Buildings.church(houses, CF(2520, rise, z1 - 330) * CFrame.Angles(0, -math.pi / 2, 0), { rng = rng })
		Props.fountain(scenery, CF(2400, rise, z1 - 510))
		for z = z1 - 40, z1 - 480, 80 do
			Props.lamp(scenery, CF(2400 - 13, rise, z))
			Props.lamp(scenery, CF(2400 + 13, rise, z - 40) * CFrame.Angles(0, math.pi, 0))
		end
		for i = 0, 4 do
			Props.turbine(scenery, CF(2250 + i * 90, rise, z1 - 640 - (i % 2) * 60))
		end
		Props.roadSign(scenery, CF(2420, 0, z0 + 40) * CFrame.Angles(0, math.pi, 0), "ortsschild", "HUEGELDORF")
	end)

	----------------------------------------------------------------------
	-- Forest + Waldweg
	----------------------------------------------------------------------
	step("forest", function()
		scatterTrees(300, -1480, -1180, -20, -24, { "fir", "fir", "fir", "birch" }, 16)
		yield()
		scatterTrees(200, -1760, -1500, -1520, 200, { "fir", "fir", "oak" }, 16)
		scatterTrees(110, -1500, -1500, 100, -1220, { "fir", "fir", "birch" }, 16)
		scatterTrees(100, -300, 60, -40, 460, { "oak", "orchard" }, 14)
		Props.wayCross(scenery, CF(-700, 0, 20))
		Props.wayCross(scenery, CF(-1480, 0, -600))
		Props.busStop(scenery, CF(-1000, 0, 22) * CFrame.Angles(0, math.pi, 0), "Waldrand")
		Props.roadSign(scenery, CF(-700, 0, 14), "curve")
		Props.roadSign(scenery, CF(-1488, 0, -1180) * CFrame.Angles(0, math.pi / 2, 0), "curve")
	end)

	----------------------------------------------------------------------
	-- Backdrop ridges: low-poly mountains far outside the playable area
	----------------------------------------------------------------------
	step("backdrop", function()
		local ridges = {
			{ -400, -3000, 1800, 520, 0 },
			{ 1600, -3700, 2000, 600, 0.1 },
			{ -2700, -900, 1700, 460, math.pi / 2 },
			{ 3500, -1200, 1800, 540, math.pi / 2 },
			{ 800, 1900, 2200, 380, 0.05 },
		}
		for _, r in ipairs(ridges) do
			local cx, cz, len, ht, yaw = r[1], r[2], r[3], r[4], r[5]
			local half = ht * 1.6
			local pitch = math.atan(ht / half)
			local base = CF(cx, 0, cz) * CFrame.Angles(0, yaw, 0)
			for _, s in ipairs({ -1, 1 }) do
				local slope = half / math.cos(pitch)
				local slab = mk(town, "Ridge", V3(len, 20, slope), base * CF(0, ht / 2 - 8, s * half / 2) * CFrame.Angles(s * pitch, 0, 0), rgb(112, 130, 104), M.Grass)
				slab.CanCollide = false
				slab.CanQuery = false
				local cap = mk(town, "RidgeRock", V3(len * 0.6, 10, slope * 0.35), base * CF(0, ht * 0.8 - 4, s * half * 0.2) * CFrame.Angles(s * pitch, 0, 0), rgb(150, 150, 154), M.Rock)
				cap.CanCollide = false
				cap.CanQuery = false
			end
			yield()
		end
	end)
end

return TownBuilder
