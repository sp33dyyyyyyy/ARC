--[[
	TownBuilder  (ModuleScript, ServerScriptService/Services)

	Builds a complete, ORIGINAL low-poly German country map at server start,
	so the game is playable and good-looking with zero manual building.
	Layout, names and look are made up for this project.

	Zones (x east, z south, 1 stud ~ 0.28 m; a moped does ~45 studs/s)
	  Kleindorf     main street z=0, x -300..300: houses, bakery, general
	                store, garage, Werkstatt, petrol station Sued, church
	  Marktplatz    cobbled square (0,-150) with fountain, Gasthof, job board
	  Schnellstrasse highway east along z=0 to x=2400, then north to z=-1900;
	                petrol station Nord at x=1500
	  Hofweg        farm lane south from the highway at x=1200 (barn, silos)
	  Waldweg loop  narrow lanes west/north: (-1500,0) (-1500,-1200) (0,-1200),
	                pine forest, used by the checkpoint run
	  Huegeldorf    hill hamlet on a 36-stud plateau at the top of a ramp road

	It only runs when GameConfig.GenerateTown is true AND Workspace has no
	"Town" folder. To use your own map: put it in a Folder named "Town", tag
	the props (see README) and add the MissionSpots.

	Tags created: GarageDoor, Workshop, PetrolStation, MissionBoard
	Spots created (Workspace/MissionSpots): everything MissionData asks for.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)

local TownBuilder = {}

local rng = Random.new(1204)
local rects = {} -- obstacles for scattering trees/props: {x1, z1, x2, z2}
local town: Folder
local roads: Folder
local scenery: Folder

local C = {
	grass = Color3.fromRGB(104, 146, 74),
	asphalt = Color3.fromRGB(64, 66, 72),
	lane = Color3.fromRGB(86, 86, 88),
	cobble = Color3.fromRGB(150, 138, 120),
	marking = Color3.fromRGB(235, 235, 225),
	timber = Color3.fromRGB(86, 58, 40),
	brick = Color3.fromRGB(150, 84, 66),
	glass = Color3.fromRGB(170, 205, 225),
	door = Color3.fromRGB(94, 58, 40),
	leaf = Color3.fromRGB(70, 120, 56),
	pine = Color3.fromRGB(40, 86, 58),
	trunk = Color3.fromRGB(96, 70, 48),
	water = Color3.fromRGB(100, 160, 205),
}
local WALLS = {
	Color3.fromRGB(236, 226, 202), Color3.fromRGB(224, 198, 152), Color3.fromRGB(202, 215, 198),
	Color3.fromRGB(238, 208, 192), Color3.fromRGB(206, 216, 230), Color3.fromRGB(242, 240, 234),
}
local ROOFS = { Color3.fromRGB(150, 70, 55), Color3.fromRGB(112, 72, 62), Color3.fromRGB(82, 86, 94) }

----------------------------------------------------------------------------
-- Primitive helpers
----------------------------------------------------------------------------
local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
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
	gui.StudsOffset = Vector3.new(0, (lift or part.Size.Y / 2 + 3), 0)
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

-- axis-aligned road. level = top surface height.
local function road(x1: number, z1: number, x2: number, z2: number, width: number, level: number, dashed: boolean?, color: Color3?)
	local horizontal = z1 == z2
	local len = horizontal and math.abs(x2 - x1) or math.abs(z2 - z1)
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local size = horizontal and Vector3.new(len, 0.4, width) or Vector3.new(width, 0.4, len)
	mk(roads, "Road", size, CFrame.new(cx, level - 0.2, cz), color or C.asphalt, Enum.Material.Asphalt)
	addRect(cx - size.X / 2, cz - size.Z / 2, cx + size.X / 2, cz + size.Z / 2)
	if dashed then
		local period, dash = 26, 9
		local start = (horizontal and math.min(x1, x2) or math.min(z1, z2)) + 6
		local pos = start
		local stop = start + len - 12
		while pos < stop do
			local mid = pos + dash / 2
			local dsize = horizontal and Vector3.new(dash, 0.12, 0.6) or Vector3.new(0.6, 0.12, dash)
			local at = horizontal and Vector3.new(mid, level + 0.03, cz) or Vector3.new(cx, level + 0.03, mid)
			local p = mk(roads, "Dash", dsize, CFrame.new(at), C.marking, Enum.Material.SmoothPlastic)
			p.CanCollide = false
			pos += period
		end
	end
end

----------------------------------------------------------------------------
-- Buildings
----------------------------------------------------------------------------
-- Half-timbered house. Front faces local +Z; yaw rotates it.
local function house(name: string, cx: number, cz: number, w: number, d: number, h: number, yaw: number, wall: Color3, roof: Color3, baseY: number?)
	local base = CFrame.new(cx, baseY or 0, cz) * CFrame.Angles(0, yaw, 0)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = scenery
	local function box(n, size, offset, color, material)
		return mk(model, n, size, base * offset, color, material)
	end
	local body = box("Walls", Vector3.new(w, h, d), CFrame.new(0, h / 2, 0), wall, Enum.Material.Plaster)
	-- timber frame
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = box("Post", Vector3.new(0.8, h, 0.8), CFrame.new(sx * w / 2, h / 2, sz * d / 2), C.timber, Enum.Material.Wood)
			p.CanCollide = false
		end
	end
	for _, sz in ipairs({ -1, 1 }) do
		local beam = box("Beam", Vector3.new(w, 0.7, 0.5), CFrame.new(0, h * 0.52, sz * d / 2), C.timber, Enum.Material.Wood)
		beam.CanCollide = false
		local post = box("Post", Vector3.new(0.7, h * 0.5, 0.5), CFrame.new(0, h * 0.27, sz * d / 2), C.timber, Enum.Material.Wood)
		post.CanCollide = false
	end
	-- stepped gable roof (ridge along X)
	for i = 1, 4 do
		local depth = (d + 3) * (1 - (i - 1) * 0.24)
		local step = box("Roof", Vector3.new(w + 3, 1.5, depth), CFrame.new(0, h + (i - 0.5) * 1.5, 0), roof, Enum.Material.Slate)
		step.CanCollide = i == 1
	end
	local chimney = box("Chimney", Vector3.new(2, 6, 2), CFrame.new(w * 0.28, h + 5, -d * 0.12), C.brick, Enum.Material.Brick)
	chimney.CanCollide = false
	-- door + windows on the front
	local door = box("Door", Vector3.new(3.4, 6.4, 0.5), CFrame.new(0, 3.2, d / 2 + 0.15), C.door, Enum.Material.Wood)
	door.CanCollide = false
	for _, wx in ipairs({ -w * 0.3, w * 0.3 }) do
		for _, wy in ipairs({ h * 0.28, h * 0.78 }) do
			local win = box("Window", Vector3.new(3.4, 3.4, 0.4), CFrame.new(wx, wy, d / 2 + 0.15), C.glass, Enum.Material.Glass)
			win.CanCollide = false
		end
	end
	model.PrimaryPart = body

	local r = math.max(w, d) / 2 + 3
	addRect(cx - r, cz - r, cx + r, cz + r)
	return body
end

local function randomHouse(name: string, x: number, z: number, yaw: number, baseY: number?)
	local w = rng:NextInteger(24, 38)
	local d = rng:NextInteger(20, 28)
	local h = rng:NextInteger(16, 22)
	return house(name, x, z, w, d, h, yaw, WALLS[rng:NextInteger(1, #WALLS)], ROOFS[rng:NextInteger(1, #ROOFS)], baseY)
end

local function tree(x: number, z: number, y: number?, pine: boolean?)
	local g = y or 0
	local h = rng:NextNumber(7, 11)
	local s = rng:NextNumber(10, 15)
	local trunk = mk(scenery, "Trunk", Vector3.new(h, 1.5, 1.5), CFrame.new(x, g + h / 2, z) * CFrame.Angles(0, 0, math.pi / 2), C.trunk, Enum.Material.Wood, Enum.PartType.Cylinder)
	trunk.CanCollide = true
	local top = mk(scenery, "Crown", Vector3.new(s, s, s), CFrame.new(x, g + h + s * 0.25, z), pine and C.pine or C.leaf, Enum.Material.Grass, Enum.PartType.Ball)
	top.CanCollide = false
	top.CanQuery = false
end

local function scatterTrees(count: number, x1: number, z1: number, x2: number, z2: number, pine: boolean?, clearance: number?)
	local placed, tries = 0, 0
	while placed < count and tries < count * 8 do
		tries += 1
		local x, z = rng:NextNumber(x1, x2), rng:NextNumber(z1, z2)
		if not blocked(x, z, clearance or 10) then
			tree(x, z, 0, pine)
			placed += 1
		end
	end
end

local function lamp(x: number, z: number, y: number?)
	local g = y or 0
	local pole = mk(scenery, "LampPole", Vector3.new(11, 0.7, 0.7), CFrame.new(x, g + 5.5, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(50, 52, 56), Enum.Material.Metal, Enum.PartType.Cylinder)
	pole.CanCollide = false
	local bulb = mk(scenery, "LampBulb", Vector3.new(1.6, 1.6, 1.6), CFrame.new(x, g + 11.4, z), Color3.fromRGB(255, 240, 190), Enum.Material.Neon, Enum.PartType.Ball)
	bulb.CanCollide = false
end

local function fenceLine(x1: number, z1: number, x2: number, z2: number, y: number?)
	local g = y or 0
	local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	local n = math.floor(len / 9)
	for i = 0, n do
		local t = i / math.max(n, 1)
		local p = mk(scenery, "FencePost", Vector3.new(0.8, 3.4, 0.8), CFrame.new(x1 + (x2 - x1) * t, g + 1.7, z1 + (z2 - z1) * t), C.timber, Enum.Material.Wood)
		p.CanCollide = false
	end
	local mid = Vector3.new((x1 + x2) / 2, g + 2.4, (z1 + z2) / 2)
	local rail = mk(scenery, "FenceRail", Vector3.new(0.4, 0.4, len), CFrame.lookAt(mid, mid + Vector3.new(x2 - x1, 0, z2 - z1)), C.timber, Enum.Material.Wood)
	rail.CanCollide = false
end

local function progress(stage: string)
	print(("[TownBuilder] %s done (%d descendants so far)"):format(stage, #town:GetDescendants()))
end

local function tag(part: Instance, name: string)
	CollectionService:AddTag(part, name)
end

local function cylinderUpright(parent: Instance, name: string, radius: number, height: number, pos: Vector3, color: Color3, material: Enum.Material?)
	return mk(parent, name, Vector3.new(height, radius * 2, radius * 2), CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
end

----------------------------------------------------------------------------
-- Special places
----------------------------------------------------------------------------
local function shop(name: string, text: string, x: number, z: number, yaw: number, w: number, d: number, h: number, wall: Color3, roof: Color3)
	local body = house(name, x, z, w, d, h, yaw, wall, roof)
	label(body, text, h + 8)
	return body
end

local function petrolStation(name: string, x: number, z: number, yaw: number)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = scenery
	local function box(n, size, offset, color, material)
		return mk(model, n, size, base * offset, color, material)
	end
	box("Island", Vector3.new(30, 0.8, 9), CFrame.new(0, 0.4, 0), Color3.fromRGB(150, 150, 152), Enum.Material.Concrete)
	local canopy = box("Canopy", Vector3.new(38, 1.2, 24), CFrame.new(0, 16, 0), Color3.fromRGB(205, 60, 50), Enum.Material.SmoothPlastic)
	canopy.CanCollide = false
	for _, sx in ipairs({ -14, 14 }) do
		box("Pillar", Vector3.new(1.4, 16, 1.4), CFrame.new(sx, 8, 0), Color3.fromRGB(235, 235, 235), Enum.Material.Metal).CanCollide = false
	end
	local middle
	for i, px in ipairs({ -8, 0, 8 }) do
		local pump = box("Pump", Vector3.new(2.6, 5.4, 1.8), CFrame.new(px, 3.5, 0), Color3.fromRGB(220, 220, 215), Enum.Material.SmoothPlastic)
		box("PumpScreen", Vector3.new(1.6, 1.2, 0.3), CFrame.new(px, 4.8, 1.0), Color3.fromRGB(60, 200, 120), Enum.Material.Neon).CanCollide = false
		if i == 2 then
			middle = pump
		end
	end
	tag(middle, "PetrolStation")
	label(middle, "TANKSTELLE", 8)
	addRect(x - 22, z - 16, x + 22, z + 16)
end

local function fountain(x: number, z: number)
	local base = Vector3.new(x, 0.3, z)
	cylinderUpright(scenery, "FountainBasin", 10, 1.8, base, Color3.fromRGB(170, 168, 160), Enum.Material.Concrete)
	local water = cylinderUpright(scenery, "FountainWater", 8.6, 1.9, base + Vector3.new(0, 0.05, 0), C.water, Enum.Material.Glass)
	water.Transparency = 0.35
	water.CanCollide = false
	cylinderUpright(scenery, "FountainColumn", 1.4, 8, base, Color3.fromRGB(175, 172, 165), Enum.Material.Concrete)
	local top = mk(scenery, "FountainTop", Vector3.new(4, 4, 4), CFrame.new(x, 10.5, z), C.water, Enum.Material.Glass, Enum.PartType.Ball)
	top.CanCollide = false
	top.Transparency = 0.3
	addRect(x - 12, z - 12, x + 12, z + 12)
end

local function church(x: number, z: number, yaw: number)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	local model = Instance.new("Model")
	model.Name = "Kirche"
	model.Parent = scenery
	local function box(n, size, offset, color, material)
		return mk(model, n, size, base * offset, color, material)
	end
	local nave = box("Nave", Vector3.new(26, 22, 44), CFrame.new(0, 11, 0), Color3.fromRGB(238, 232, 214), Enum.Material.Plaster)
	for i = 1, 4 do
		box("NaveRoof", Vector3.new(30, 1.5, 48 * (1 - (i - 1) * 0.0)), CFrame.new(0, 22 + (i - 0.5) * 1.5, 0), Color3.fromRGB(96, 80, 74), Enum.Material.Slate).Size = Vector3.new(30 - (i - 1) * 7, 1.5, 48)
	end
	box("Tower", Vector3.new(12, 46, 12), CFrame.new(0, 23, 28), Color3.fromRGB(232, 226, 208), Enum.Material.Plaster)
	for i = 1, 6 do
		box("Spire", Vector3.new(13 - (i - 1) * 2.2, 3, 13 - (i - 1) * 2.2), CFrame.new(0, 46 + (i - 0.5) * 3, 28), Color3.fromRGB(80, 100, 96), Enum.Material.Slate)
	end
	box("Clock", Vector3.new(5, 5, 0.5), CFrame.new(0, 38, 34.2), Color3.fromRGB(250, 248, 240), Enum.Material.SmoothPlastic).CanCollide = false
	box("Door", Vector3.new(5, 9, 0.5), CFrame.new(0, 4.5, 34.2), C.door, Enum.Material.Wood).CanCollide = false
	model.PrimaryPart = nave
	addRect(x - 24, z - 36, x + 24, z + 50)
	label(nave, "KIRCHE", 40)
end

local function barn(x: number, z: number, yaw: number)
	local body = house("Scheune", x, z, 46, 32, 20, yaw, Color3.fromRGB(150, 62, 52), Color3.fromRGB(90, 80, 76))
	label(body, "HOF", 36)
	cylinderUpright(scenery, "Silo", 6.5, 36, Vector3.new(x + 40, 0, z - 6), Color3.fromRGB(180, 182, 186), Enum.Material.Metal)
	cylinderUpright(scenery, "Silo", 6.5, 30, Vector3.new(x + 40, 0, z + 12), Color3.fromRGB(180, 182, 186), Enum.Material.Metal)
	addRect(x + 32, z - 16, x + 50, z + 20)
	for i = 1, 5 do
		cylinderUpright(scenery, "Haystack", 4, 5, Vector3.new(x - 60 + i * 9, 0, z + 34), Color3.fromRGB(214, 190, 100), Enum.Material.Grass)
	end
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------
local function step(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		progress(name)
	else
		warn(("[TownBuilder] step '%s' FAILED: %s"):format(name, tostring(err)))
	end
end

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

	-- sky / light
	Lighting.ClockTime = 15
	Lighting.Brightness = 2.4
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 124, 130)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(200, 215, 235)
	atmosphere.Parent = Lighting


	local z0, z1, rise = -1900, -2200, 36 -- hill ramp: start z, end z, height

	step('ground', function()
		-- ground tiles (parts max 2048 studs)
		for _, cx in ipairs({ -1300, 500, 2300 }) do
			for _, cz in ipairs({ -2500, -700, 1100 }) do
				mk(town, "Ground", Vector3.new(1800, 4, 1800), CFrame.new(cx, -2, cz), C.grass, Enum.Material.Grass)
			end
		end
	end)

	step("Roads (highest level drawn last so junctions don't z-fight)", function()
		road(300, 0, 2400, 0, 32, 0.20, true) -- Schnellstrasse east
		road(2400, 0, 2400, -1900, 32, 0.20, true) -- ...north
		road(1200, 0, 1200, 640, 18, 0.22) -- Hofweg to the farm
		road(-1500, 0, -300, 0, 16, 0.24, false, C.lane) -- Landstrasse west
		road(-1500, -1200, -1500, 0, 16, 0.24, false, C.lane) -- Waldweg north
		road(-1500, -1200, 0, -1200, 16, 0.24, false, C.lane)
		road(0, -1200, 0, 0, 16, 0.24, false, C.lane) -- Marktstrasse back to the village
		road(-300, 0, 300, 0, 24, 0.26, true) -- Hauptstrasse (village main street)

		-- Marktplatz
		mk(town, "Marktplatz", Vector3.new(150, 0.5, 130), CFrame.new(0, 0.05, -150), C.cobble, Enum.Material.Cobblestone)
		addRect(-75, -215, 75, -85)
		fountain(0, -150)
	end)

	step('Hill ramp to Huegeldorf: a thick slab so there is no hollow underneath', function()
		
		local a, b = Vector3.new(2400, 0, z0), Vector3.new(2400, rise, z1)
		local dir = (b - a)
		local len = dir.Magnitude
		local lookCF = CFrame.lookAt((a + b) / 2, (a + b) / 2 + dir)
		local slab = mk(town, "RampSlab", Vector3.new(44, 40, len), lookCF * CFrame.new(0, -20, 0), C.grass, Enum.Material.Grass)
		slab.Name = "RampSlab"
		mk(roads, "RampRoad", Vector3.new(18, 0.4, len), lookCF * CFrame.new(0, 0.2, 0), C.asphalt, Enum.Material.Asphalt)
		addRect(2370, z1, 2430, z0)
		-- plateau
		mk(town, "Plateau", Vector3.new(500, rise, 520), CFrame.new(2400, rise / 2, z1 - 260), C.grass, Enum.Material.Grass)
		mk(roads, "HamletRoad", Vector3.new(18, 0.4, 500), CFrame.new(2400, rise + 0.2, z1 - 250), C.lane, Enum.Material.Asphalt)
		addRect(2150, z1 - 520, 2650, z1)
	end)

	step('Kleindorf: houses along the main street', function()
		local reserved = { -200, -80, 80, 200 } -- shop / garage slots on each side
		local function isReserved(x: number): boolean
			for _, r in ipairs(reserved) do
				if math.abs(x - r) < 36 then
					return true
				end
			end
			return false
		end
		for x = -270, 270, 46 do
			if not isReserved(x) and math.abs(x) > 14 then
				randomHouse("Haus", x + rng:NextInteger(-4, 4), -40, 0) -- north side faces south
				randomHouse("Haus", x + rng:NextInteger(-4, 4), 40, math.pi) -- south side faces north
			end
		end

		-- named buildings
		shop("Baeckerei", "BAECKEREI", -200, -40, 0, 34, 26, 18, Color3.fromRGB(240, 214, 160), ROOFS[1])
		shop("Dorfladen", "DORFLADEN", 200, -40, 0, 34, 26, 18, Color3.fromRGB(200, 222, 200), ROOFS[2])
		local garage = shop("Garage", "GARAGE", -80, 40, math.pi, 34, 26, 16, Color3.fromRGB(205, 175, 130), ROOFS[3])
		tag(garage, "GarageDoor")
		local werkstatt = shop("Werkstatt", "WERKSTATT (repair)", 80, 40, math.pi, 34, 26, 16, Color3.fromRGB(150, 170, 200), ROOFS[3])
		tag(werkstatt, "Workshop")
		petrolStation("TankstelleSued", -200, 36, math.pi)

		-- lamps down the main street
		for x = -270, 270, 60 do
			lamp(x, -15, 0)
			lamp(x + 30, 15, 0)
		end

		-- job board next to the spawn
		local board = mk(scenery, "JobBoard", Vector3.new(10, 8, 1.2), CFrame.new(34, 4.8, -20), Color3.fromRGB(110, 80, 52), Enum.Material.Wood)
		mk(scenery, "BoardPost", Vector3.new(1.2, 6, 1.2), CFrame.new(29, 3, -20), C.timber, Enum.Material.Wood)
		mk(scenery, "BoardPost", Vector3.new(1.2, 6, 1.2), CFrame.new(39, 3, -20), C.timber, Enum.Material.Wood)
		tag(board, "MissionBoard")
		label(board, "JOBS", 7)
		addRect(24, -24, 44, -16)
	end)

	step('Marktplatz buildings', function()
		shop("Gasthof", "GASTHOF ZUR LINDE", 62, -240, 0, 52, 30, 24, Color3.fromRGB(238, 222, 190), ROOFS[1])
		church(-140, -150, math.pi / 2)
		randomHouse("Haus", 135, -150, -math.pi / 2)
		randomHouse("Haus", 135, -200, -math.pi / 2)
		lamp(-60, -95, 0)
		lamp(60, -95, 0)
		lamp(-60, -205, 0)
		lamp(60, -205, 0)
	end)

	step('Highway: second petrol station, signs of life', function()
		petrolStation("TankstelleNord", 1500, 40, math.pi)
		for x = 400, 2300, 120 do
			lamp(x, -20, 0)
		end
		scatterTrees(120, 350, -500, 2300, -40, false, 14)
		scatterTrees(80, 350, 40, 2300, 520, false, 14)
	end)

	step('Hof (farm) at the end of the lane', function()
		fenceLine(1182, 80, 1182, 600)
		fenceLine(1218, 80, 1218, 600)
		barn(1170, 660, 0)
		mk(town, "Field", Vector3.new(220, 0.3, 300), CFrame.new(1420, 0.15, 330), Color3.fromRGB(208, 184, 96), Enum.Material.Grass)
		mk(town, "Field", Vector3.new(220, 0.3, 300), CFrame.new(980, 0.15, 330), Color3.fromRGB(120, 160, 70), Enum.Material.Grass)
		addRect(870, 160, 1530, 500)
	end)

	step('Hamlet on the plateau', function()
		for i = 0, 5 do
			local z = z1 - 60 - i * 72
			randomHouse("HausH", 2400 - 34, z, math.pi / 2, rise)
			randomHouse("HausH", 2400 + 34, z - 30, -math.pi / 2, rise)
		end
		church(2490, z1 - 440, 0)
		for z = z1 - 40, z1 - 480, 80 do
			lamp(2400 - 11, z, rise)
		end
	end)

	step('Forest', function()
		scatterTrees(380, -1480, -1180, -20, -20, true, 18) -- inside the loop
		scatterTrees(260, -1900, -1500, -1520, 200, true, 16)
		scatterTrees(120, -1500, -1500, 100, -1220, true, 16)
		scatterTrees(90, -300, 60, -40, 420, false, 14)
		scatterTrees(60, 300, -400, 1100, -60, false, 14)
	end)

	step('Spawn + mission spots', function()
		local spawn = Instance.new("SpawnLocation")
		spawn.Anchored = true
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.Position = Vector3.new(0, 0.8, 56)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = town
		mk(roads, "SpawnPad", Vector3.new(16, 0.3, 16), CFrame.new(0, 0.3, 56), C.cobble, Enum.Material.Cobblestone).CanCollide = false

		local spots = Instance.new("Folder")
		spots.Name = "MissionSpots"
		spots.Parent = Workspace
		local positions = {
			Spot_Bakery = Vector3.new(-200, 0.6, -10),
			Spot_Dorfladen = Vector3.new(200, 0.6, -10),
			Spot_Gasthof = Vector3.new(0, 0.6, -200),
			Spot_Farm = Vector3.new(1200, 0.6, 570),
			Spot_Huegeldorf = Vector3.new(2400, rise + 0.6, z1 - 250),
			CP_Forest1 = Vector3.new(-900, 0.6, 0),
			CP_Forest2 = Vector3.new(-1500, 0.6, -300),
			CP_Forest3 = Vector3.new(-1500, 0.6, -1000),
			CP_Forest4 = Vector3.new(-900, 0.6, -1200),
			CP_Forest5 = Vector3.new(-300, 0.6, -1200),
		}
		for name, pos in pairs(positions) do
			local size = name:sub(1, 2) == "CP" and 20 or 14
			local p = mk(spots, name, Vector3.new(size, 0.4, size), CFrame.new(pos), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
			p.CanCollide = false
			p.CanQuery = false
			p.Transparency = 0.55
			label(p, (name:gsub("^%a+_", "")), 6)
		end
	end)
end

return TownBuilder
