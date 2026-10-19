--[[
	Props  (ModuleScript, ServerScriptService/Services)

	Street furniture and landscape details, built from parts with ModelKit.
	Everything is   Props.xxx(parent, CFrame, ...)   and drops its parts
	straight into `parent` (a Folder) to keep the instance count low.

	trees (oak, birch, fir, orchard), street lamps, benches, bus stop,
	road signs (Ortsschild, speed limits, priority road, stop, bus stop),
	advertising column, maypole, fountain, cars, tractor, hay bales,
	fences, hedges, stone walls, power poles + wires, wind turbine,
	wayside cross, post box, crosswalk, kerbs and pavements.

	Local axes: -Z forward, +Y up. A prop with a "face" (signs) faces +Z.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelKit = require(ReplicatedStorage.Shared.ModelKit)

local Props = {}

local V3, CF = Vector3.new, CFrame.new
local rgb = Color3.fromRGB
local M = Enum.Material

local GREENS = {
	rgb(74, 124, 58), rgb(86, 138, 62), rgb(62, 110, 52), rgb(96, 146, 68), rgb(70, 118, 66),
}
local function kitAt(parent: Instance, cf: CFrame)
	return ModelKit.new(parent, nil, cf, true)
end

----------------------------------------------------------------------------
-- TREES
----------------------------------------------------------------------------
function Props.tree(parent: Instance, pos: Vector3, rng, kind: string?)
	kind = kind or "oak"
	local kit = kitAt(parent, CF(pos))
	if kind == "fir" then
		local h = rng:NextNumber(14, 22)
		local dark = (rng:NextInteger(1, 2) == 1) and rgb(38, 82, 56) or rgb(46, 92, 62)
		kit:tube("Trunk", V3(0, 0, 0), V3(0, h * 0.5, 0), 1.2, rgb(88, 64, 46), M.Wood, { collide = true })
		for i = 0, 2 do
			local y = h * 0.2 + i * h * 0.26
			local d = (10.5 - i * 3.4) * (h / 18)
			kit:cyl("Tier", 5.2 - i, d, d, CF(0, y + 1.8, 0) * CFrame.Angles(0, 0, math.pi / 2), dark, M.Grass)
		end
		return
	end
	local h = rng:NextNumber(7, 11)
	local trunkColor = kind == "birch" and rgb(226, 222, 212) or rgb(96, 70, 50)
	kit:tube("Trunk", V3(0, 0, 0), V3(rng:NextNumber(-0.4, 0.4), h, rng:NextNumber(-0.4, 0.4)), kind == "birch" and 0.9 or 1.5, trunkColor, M.Wood, { collide = true })
	local s = kind == "orchard" and 6.5 or (kind == "birch" and 6 or 9)
	local n = (kind == "birch" or kind == "orchard") and 2 or 3
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(0, 1)
		local r = (i == 1) and 0 or s * 0.35
		local col = GREENS[rng:NextInteger(1, #GREENS)]
		if kind == "orchard" and i > 2 then
			col = rgb(110, 160, 70)
		end
		kit:ball("Crown", s * rng:NextNumber(0.85, 1.15), CF(math.cos(a) * r, h + s * 0.35 + (i % 2) * 1.2, math.sin(a) * r), col, M.Grass)
	end
	if kind == "orchard" then
		for i = 1, 2 do
			local a = i * 2.7
			kit:ball("Apple", 0.6, CF(math.cos(a) * s * 0.42, h + s * 0.2, math.sin(a) * s * 0.42), rgb(210, 52, 46), M.SmoothPlastic)
		end
	end
end

----------------------------------------------------------------------------
-- STREET FURNITURE
----------------------------------------------------------------------------
function Props.lamp(parent: Instance, cf: CFrame, height: number?)
	local kit = kitAt(parent, cf)
	local h = height or 12
	local iron = rgb(46, 52, 50)
	kit:cyl("Base", 2.2, 1.6, 1.6, CF(0, 1.1, 0) * CFrame.Angles(0, 0, math.pi / 2), iron, M.Metal)
	kit:tube("Pole", V3(0, 0, 0), V3(0, h, 0), 0.5, iron, M.Metal, { collide = true })
	kit:tube("Arm", V3(0, h, 0), V3(2.6, h + 0.8, 0), 0.3, iron, M.Metal)
	kit:box("LampHousing", V3(2.0, 0.5, 1.1), CF(3.0, h + 0.9, 0), iron, M.Metal)
	kit:box("LampGlow", V3(1.7, 0.2, 0.8), CF(3.0, h + 0.55, 0), rgb(255, 232, 170), M.Neon)
end

function Props.bench(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	local wood, iron = rgb(126, 90, 62), rgb(46, 50, 50)
	for i = 0, 2 do
		kit:box("Seat", V3(4.8, 0.2, 0.5), CF(0, 1.5, i * 0.58 - 0.58), wood, M.WoodPlanks)
	end
	for i = 0, 2 do
		kit:box("Back", V3(4.8, 0.45, 0.2), CF(0, 2.2 + i * 0.55, -0.95 - i * 0.12), wood, M.WoodPlanks)
	end
	for _, sx in ipairs({ -2.1, 2.1 }) do
		kit:box("Leg", V3(0.25, 1.5, 1.8), CF(sx, 0.75, -0.2), iron, M.Metal, { collide = true })
		kit:box("BackLeg", V3(0.25, 1.6, 0.25), CF(sx, 2.3, -0.9), iron, M.Metal)
	end
end

function Props.busStop(parent: Instance, cf: CFrame, name: string?)
	local kit = kitAt(parent, cf)
	local frame = rgb(60, 110, 70)
	kit:box("Roof", V3(9, 0.4, 4.4), CF(0, 8, 0), frame, M.Metal, { collide = true })
	for _, sx in ipairs({ -4.2, 4.2 }) do
		kit:box("Post", V3(0.4, 8, 0.4), CF(sx, 4, -1.6), frame, M.Metal, { collide = true })
	end
	kit:box("BackGlass", V3(8.4, 5.2, 0.2), CF(0, 4.4, -2), rgb(176, 210, 226), M.Glass, { transparency = 0.5, collide = true })
	kit:box("SideGlass", V3(0.2, 5.2, 3.6), CF(-4.2, 4.4, 0.2), rgb(176, 210, 226), M.Glass, { transparency = 0.5 })
	kit:box("Bench", V3(5.6, 0.3, 1.2), CF(0, 1.9, -1.2), rgb(150, 110, 80), M.WoodPlanks)
	kit:box("BenchLeg", V3(0.3, 1.9, 1), CF(-2.4, 0.95, -1.2), rgb(46, 50, 50), M.Metal)
	kit:box("BenchLeg", V3(0.3, 1.9, 1), CF(2.4, 0.95, -1.2), rgb(46, 50, 50), M.Metal)
	local board = kit:box("Timetable", V3(2.6, 3.4, 0.2), CF(3.0, 4.6, -1.85), rgb(250, 250, 246), M.SmoothPlastic)
	ModelKit.signText(board, "Fahrplan", Enum.NormalId.Back, rgb(40, 40, 40))
	-- H sign
	kit:tube("SignPole", V3(5.4, 0, 1.5), V3(5.4, 10, 1.5), 0.3, rgb(120, 124, 128), M.Metal)
	kit:cyl("SignDisc", 0.2, 3, 3, CF(5.4, 10.4, 1.5) * CFrame.Angles(0, math.pi / 2, 0), rgb(40, 140, 70), M.SmoothPlastic)
	local h = kit:box("SignFace", V3(2.2, 2.2, 0.12), CF(5.4, 10.4, 1.62), rgb(40, 140, 70), M.SmoothPlastic)
	ModelKit.signText(h, "H", Enum.NormalId.Back, rgb(250, 220, 40))
	if name then
		local n = kit:box("NameBoard", V3(4.6, 1.1, 0.12), CF(5.4, 8.3, 1.62), rgb(250, 250, 246), M.SmoothPlastic)
		ModelKit.signText(n, name, Enum.NormalId.Back, rgb(30, 30, 30))
	end
end

function Props.postBox(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	kit:tube("Post", V3(0, 0, 0), V3(0, 3.2, 0), 0.3, rgb(60, 60, 64), M.Metal)
	kit:box("Box", V3(1.6, 2.2, 1.2), CF(0, 4.3, 0), rgb(250, 205, 30), M.SmoothPlastic, { collide = true })
	kit:cyl("Roof", 1.2, 1.6, 1.6, CF(0, 5.4, 0) * CFrame.Angles(0, math.pi / 2, 0), rgb(250, 205, 30), M.SmoothPlastic)
	kit:box("Slot", V3(1.0, 0.12, 0.1), CF(0, 4.9, 0.62), rgb(30, 30, 30), M.SmoothPlastic)
end

function Props.litfass(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	kit:cyl("Base", 1, 5.2, 5.2, CF(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(70, 74, 72), M.Concrete)
	kit:cyl("Drum", 8.4, 4.4, 4.4, CF(0, 5.2, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(64, 108, 80), M.Metal, { collide = true })
	local posters = { rgb(240, 200, 70), rgb(220, 90, 80), rgb(80, 150, 210), rgb(244, 240, 230), rgb(150, 190, 110), rgb(230, 130, 60) }
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local pcf = CF(0, 5.2, 0) * CFrame.Angles(0, a, 0) * CF(0, 0, 2.25)
		kit:box("Poster", V3(2.6, 5.6, 0.1), pcf, posters[i + 1], M.SmoothPlastic)
		kit:box("PosterBand", V3(2.6, 1.0, 0.12), pcf * CF(0, 1.9, 0.01), rgb(30, 30, 34), M.SmoothPlastic)
	end
	kit:cone("Cap", V3(0, 9.4, 0), V3(0, 11.4, 0), 5.2, 1.0, 4, rgb(60, 62, 66), M.Metal)
	kit:ball("Finial", 0.8, CF(0, 11.8, 0), rgb(60, 62, 66), M.Metal)
end

function Props.maibaum(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	local height = 42
	for i = 0, 13 do
		kit:tube("Segment", V3(0, i * 3, 0), V3(0, i * 3 + 3.02, 0), 1.0, (i % 2 == 0) and rgb(246, 246, 246) or rgb(60, 130, 210), M.Wood, { collide = i == 0 })
	end
	kit:cyl("TopWreath", 0.8, 6, 6, CF(0, height - 3, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(70, 140, 70), M.Grass)
	kit:cyl("TopWreath", 0.8, 4.4, 4.4, CF(0, height - 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(70, 140, 70), M.Grass)
	kit:ball("Crown", 1.6, CF(0, height + 1, 0), rgb(240, 200, 60), M.Metal)
	-- crafts hanging from a crossbar
	kit:strut("Crossbar", V3(-3.2, height - 8, 0), V3(3.2, height - 8, 0), 0.3, rgb(120, 90, 60), M.Wood)
	kit:strut("Crossbar", V3(0, height - 14, -3.2), V3(0, height - 14, 3.2), 0.3, rgb(120, 90, 60), M.Wood)
	local symbols = { rgb(214, 160, 70), rgb(200, 70, 60), rgb(80, 130, 200), rgb(110, 170, 90) }
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2
		local x, z = math.cos(a) * 3.0, math.sin(a) * 3.0
		kit:strut("Rope", V3(x, height - 8 - (i % 2) * 6, z), V3(x, height - 10.5 - (i % 2) * 6, z), 0.08, rgb(160, 130, 90), M.Fabric)
		kit:box("Symbol", V3(1.6, 1.8, 0.4), CF(x, height - 11.3 - (i % 2) * 6, z), symbols[i], M.WoodPlanks)
	end
	-- ribbons down to a ring on the ground
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local top = V3(math.cos(a) * 0.6, height - 4, math.sin(a) * 0.6)
		local bottom = V3(math.cos(a) * 9, 2.5, math.sin(a) * 9)
		kit:strut("Ribbon", top, bottom, 0.14, (i % 2 == 0) and rgb(246, 246, 246) or rgb(60, 130, 210), M.Fabric)
	end
	kit:cyl("Base", 1.6, 3, 3, CF(0, 0.8, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(120, 118, 112), M.Concrete, { collide = true })
end

function Props.fountain(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	local stone = rgb(176, 172, 162)
	local water = rgb(96, 160, 206)
	kit:cyl("PlinthRing", 1.0, 22, 22, CF(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(150, 146, 138), M.Granite, { collide = true })
	kit:cyl("BasinRim", 2.2, 19, 19, CF(0, 2.1, 0) * CFrame.Angles(0, 0, math.pi / 2), stone, M.Limestone, { collide = true })
	kit:cyl("Water", 0.6, 17, 17, CF(0, 3.0, 0) * CFrame.Angles(0, 0, math.pi / 2), water, M.Glass, { transparency = 0.35 })
	kit:tube("Column", V3(0, 1, 0), V3(0, 9, 0), 1.8, stone, M.Limestone, { collide = true })
	kit:cyl("Dish1", 0.8, 8.6, 8.6, CF(0, 5.2, 0) * CFrame.Angles(0, 0, math.pi / 2), stone, M.Limestone)
	kit:cyl("DishWater1", 0.3, 7.6, 7.6, CF(0, 5.7, 0) * CFrame.Angles(0, 0, math.pi / 2), water, M.Glass, { transparency = 0.35 })
	kit:tube("Column2", V3(0, 5.5, 0), V3(0, 12.5, 0), 1.0, stone, M.Limestone)
	kit:cyl("Dish2", 0.6, 4.6, 4.6, CF(0, 9.4, 0) * CFrame.Angles(0, 0, math.pi / 2), stone, M.Limestone)
	kit:ball("Finial", 2.0, CF(0, 13.2, 0), stone, M.Limestone)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		kit:tube("Jet", V3(math.cos(a) * 3.4, 5.8, math.sin(a) * 3.4), V3(math.cos(a) * 6.6, 3.4, math.sin(a) * 6.6), 0.16, rgb(190, 225, 245), M.Glass, { transparency = 0.45 })
	end
end

function Props.marketStall(parent: Instance, cf: CFrame, variant: number?)
	local kit = kitAt(parent, cf)
	local a = (variant or 1) % 3
	local stripe = ({ { rgb(196, 44, 44), rgb(246, 244, 238) }, { rgb(44, 110, 70), rgb(246, 244, 238) }, { rgb(46, 90, 170), rgb(246, 244, 238) } })[a + 1]
	local wood = rgb(130, 94, 66)
	kit:box("Counter", V3(7.6, 2.8, 2.6), CF(0, 1.4, 0), wood, M.WoodPlanks, { collide = true })
	for _, sx in ipairs({ -3.6, 3.6 }) do
		for _, sz in ipairs({ -1.2, 1.2 }) do
			kit:box("StallPost", V3(0.3, 7.4, 0.3), CF(sx, 3.7, sz), wood, M.Wood)
		end
	end
	for i = 0, 5 do
		kit:box("AwningStripe", V3(1.34, 0.2, 4.2), CF(-3.35 + i * 1.34, 7.7, 0.2) * CFrame.Angles(math.rad(8), 0, 0), stripe[i % 2 + 1], M.Fabric)
	end
	local goods = { rgb(214, 70, 60), rgb(240, 190, 60), rgb(120, 170, 70), rgb(230, 130, 60) }
	for i = 0, 3 do
		kit:box("Goods", V3(1.4, 0.9, 1.1), CF(-2.7 + i * 1.8, 3.25, 0.1), goods[(i + a) % 4 + 1], M.SmoothPlastic)
	end
end

function Props.wayCross(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	local wood = rgb(92, 64, 44)
	kit:box("Post", V3(0.9, 9, 0.9), CF(0, 4.5, 0), wood, M.Wood, { collide = true })
	kit:box("Arm", V3(4, 0.9, 0.9), CF(0, 6.8, 0), wood, M.Wood)
	kit:box("Roof", V3(5.6, 0.3, 2.4), CF(0, 8.6, 0) * CFrame.Angles(0, 0, math.rad(2)), rgb(120, 70, 54), M.WoodPlanks)
	kit:box("Figure", V3(0.5, 2.2, 0.4), CF(0, 5.6, 0.55), rgb(210, 205, 190), M.Wood)
	kit:box("Plinth", V3(3, 0.8, 3), CF(0, 0.4, 0), rgb(140, 138, 132), M.Granite)
end

----------------------------------------------------------------------------
-- ROAD SIGNS (face +Z)
----------------------------------------------------------------------------
function Props.roadSign(parent: Instance, cf: CFrame, kind: string, text: string?)
	local kit = kitAt(parent, cf)
	local pole = rgb(130, 134, 138)
	if kind == "ortsschild" then
		kit:tube("Pole", V3(-3, 0, 0), V3(-3, 6.2, 0), 0.3, pole, M.Metal)
		kit:tube("Pole", V3(3, 0, 0), V3(3, 6.2, 0), 0.3, pole, M.Metal)
		kit:box("Board", V3(8.6, 3.2, 0.2), CF(0, 6.0, 0.1), rgb(40, 40, 40), M.SmoothPlastic)
		local face = kit:box("Face", V3(8.2, 2.8, 0.12), CF(0, 6.0, 0.22), rgb(250, 214, 40), M.SmoothPlastic)
		ModelKit.signText(face, text or "ORT", Enum.NormalId.Back, rgb(20, 20, 20))
		return
	end
	kit:tube("Pole", V3(0, 0, 0), V3(0, 7.2, 0), 0.3, pole, M.Metal)
	if kind == "limit" then
		kit:cyl("Rim", 0.15, 3.0, 3.0, CF(0, 8.2, 0.1) * CFrame.Angles(0, math.pi / 2, 0), rgb(200, 30, 30), M.SmoothPlastic)
		kit:cyl("Face", 0.15, 2.2, 2.2, CF(0, 8.2, 0.2) * CFrame.Angles(0, math.pi / 2, 0), rgb(250, 250, 250), M.SmoothPlastic)
		local t = kit:box("Text", V3(1.8, 1.4, 0.05), CF(0, 8.2, 0.3), rgb(250, 250, 250), M.SmoothPlastic, { transparency = 1 })
		ModelKit.signText(t, text or "50", Enum.NormalId.Back, rgb(20, 20, 20))
	elseif kind == "vorfahrt" then
		kit:box("Border", V3(2.8, 2.8, 0.15), CF(0, 8.2, 0.1) * CFrame.Angles(0, 0, math.pi / 4), rgb(30, 30, 30), M.SmoothPlastic)
		kit:box("White", V3(2.5, 2.5, 0.15), CF(0, 8.2, 0.18) * CFrame.Angles(0, 0, math.pi / 4), rgb(250, 250, 250), M.SmoothPlastic)
		kit:box("Yellow", V3(1.9, 1.9, 0.15), CF(0, 8.2, 0.26) * CFrame.Angles(0, 0, math.pi / 4), rgb(250, 205, 30), M.SmoothPlastic)
	elseif kind == "stop" then
		kit:cyl("Octagon", 0.15, 3.0, 3.0, CF(0, 8.2, 0.1) * CFrame.Angles(0, math.pi / 2, 0), rgb(250, 250, 250), M.SmoothPlastic)
		kit:cyl("Red", 0.15, 2.7, 2.7, CF(0, 8.2, 0.2) * CFrame.Angles(0, math.pi / 2, 0), rgb(200, 28, 30), M.SmoothPlastic)
		local t = kit:box("Text", V3(2.2, 0.8, 0.05), CF(0, 8.2, 0.3), rgb(200, 28, 30), M.SmoothPlastic, { transparency = 1 })
		ModelKit.signText(t, "STOP", Enum.NormalId.Back, rgb(250, 250, 250))
	elseif kind == "curve" then
		kit:box("Border", V3(3.0, 3.0, 0.15), CF(0, 8.2, 0.1), rgb(200, 30, 30), M.SmoothPlastic)
		kit:box("White", V3(2.4, 2.4, 0.15), CF(0, 8.2, 0.18), rgb(250, 250, 250), M.SmoothPlastic)
		local t = kit:box("Text", V3(2.2, 2.2, 0.05), CF(0, 8.2, 0.28), rgb(250, 250, 250), M.SmoothPlastic, { transparency = 1 })
		ModelKit.signText(t, ">>", Enum.NormalId.Back, rgb(20, 20, 20))
	end
end

function Props.reflectorPost(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	kit:box("Post", V3(0.5, 3.4, 0.3), CF(0, 1.7, 0), rgb(246, 246, 242), M.SmoothPlastic)
	kit:box("Band", V3(0.52, 0.8, 0.32), CF(0, 2.5, 0), rgb(30, 30, 34), M.SmoothPlastic)
	kit:box("Reflector", V3(0.3, 0.3, 0.1), CF(0, 2.5, 0.2), rgb(255, 160, 40), M.Neon)
end

function Props.crosswalk(parent: Instance, cf: CFrame, roadWidth: number)
	local kit = kitAt(parent, cf)
	local n = math.floor(roadWidth / 2.2)
	for i = 0, n - 1 do
		kit:box("Zebra", V3(1.2, 0.06, 6), CF(-roadWidth / 2 + 1.2 + i * 2.2, 0.32, 0), rgb(240, 240, 236), M.SmoothPlastic)
	end
end

----------------------------------------------------------------------------
-- RUNS: fences, hedges, walls, kerbs, wires
----------------------------------------------------------------------------
function Props.fenceRun(parent: Instance, a: Vector3, b: Vector3, style: string?)
	local kit = kitAt(parent, CF())
	local dir = b - a
	local len = dir.Magnitude
	local n = math.max(1, math.floor(len / 6))
	local wood = rgb(120, 86, 60)
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		kit:box("Post", V3(0.6, 3.6, 0.6), CF(p + V3(0, 1.8, 0)), wood, M.Wood)
	end
	for _, y in ipairs({ 1.2, 2.6 }) do
		kit:strut("Rail", a + V3(0, y, 0), b + V3(0, y, 0), 0.35, wood, M.Wood)
	end
	if style == "picket" then
		local pn = math.floor(len / 1.1)
		for i = 0, pn do
			local p = a:Lerp(b, i / pn)
			kit:box("Picket", V3(0.4, 3.0, 0.2), CFrame.lookAt(p + V3(0, 1.6, 0), b + V3(0, 1.6, 0)), rgb(240, 238, 230), M.Wood)
		end
	end
end

function Props.hedgeRun(parent: Instance, a: Vector3, b: Vector3, rng, height: number?)
	local kit = kitAt(parent, CF())
	local h = height or 3.6
	local len = (b - a).Magnitude
	kit:strut("HedgeCore", a + V3(0, h / 2, 0), b + V3(0, h / 2, 0), 2.2, rgb(58, 104, 48), M.Grass, { collide = true })
	local n = math.max(2, math.floor(len / 3.2))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		kit:ball("Bush", 3.2 + rng:NextNumber(0, 0.8), CF(p + V3(0, h, 0)), GREENS[rng:NextInteger(1, #GREENS)], M.Grass)
	end
end

function Props.stoneWall(parent: Instance, a: Vector3, b: Vector3, h: number?, thick: number?)
	local kit = kitAt(parent, CF())
	local height = h or 3
	local t = thick or 1.2
	kit:strip("Wall", a + V3(0, height / 2, 0), b + V3(0, height / 2, 0), t, height, rgb(164, 158, 146), M.Limestone, { collide = true })
	kit:strip("Cap", a + V3(0, height + 0.15, 0), b + V3(0, height + 0.15, 0), t + 0.3, 0.3, rgb(190, 184, 172), M.Concrete)
end

-- continuous kerb + pavement beside a straight road (side = -1 or 1 of the road's right)
function Props.sidewalk(parent: Instance, a: Vector3, b: Vector3, width: number, kerbSide: number?)
	local kit = kitAt(parent, CF())
	local len = (b - a).Magnitude
	kit:strip("Pavement", a + V3(0, 0.22, 0), b + V3(0, 0.22, 0), width, 0.44, rgb(178, 174, 166), M.Pavement, { collide = true })
	local dir = (b - a).Unit
	local right = dir:Cross(V3(0, 1, 0))
	local edge = right * (kerbSide or 1) * (width / 2 + 0.3)
	kit:strip("Kerb", a + edge + V3(0, 0.25, 0), b + edge + V3(0, 0.25, 0), 0.6, 0.5, rgb(140, 138, 134), M.Granite, { collide = true })
end

function Props.wire(parent: Instance, a: Vector3, b: Vector3, sag: number?)
	local kit = kitAt(parent, CF())
	local pts = ModelKit.bezier(a, (a + b) / 2 - V3(0, sag or 2.4, 0) * 2, b, 4)
	for i = 1, #pts - 1 do
		kit:strut("Wire", pts[i], pts[i + 1], 0.12, rgb(30, 30, 32), M.Metal)
	end
end

function Props.powerPole(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	local wood = rgb(96, 70, 50)
	kit:tube("Pole", V3(0, 0, 0), V3(0, 26, 0), 1.1, wood, M.Wood, { collide = true })
	kit:box("Crossarm", V3(10, 0.7, 0.9), CF(0, 24.2, 0), wood, M.Wood)
	for _, x in ipairs({ -4, 0, 4 }) do
		kit:cyl("Insulator", 1.0, 0.7, 0.7, CF(x, 25.0, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(220, 224, 226), M.Glass)
	end
	for _, s in ipairs({ -1, 1 }) do
		kit:strut("Brace", V3(0, 22.4, 0), V3(s * 3.4, 24.0, 0), 0.4, wood, M.Wood)
	end
end

----------------------------------------------------------------------------
-- VEHICLES (parked cars, tractor)
----------------------------------------------------------------------------
function Props.car(parent: Instance, cf: CFrame, kind: string?, color: Color3?)
	local kit = kitAt(parent, cf)
	local c = color or rgb(190, 60, 52)
	local glass = rgb(150, 190, 214)
	local chrome = rgb(210, 212, 216)
	local len, wid = 14.4, 6.0
	if kind == "bubble" then
		-- small rounded 60s-style saloon
		kit:stadium("Body", len, 2.6, wid, CF(0, 2.2, 0), c, M.SmoothPlastic, { collide = true })
		kit:stadium("Cabin", 7.2, 2.3, wid - 0.9, CF(0, 4.4, 0.6), c, M.SmoothPlastic)
		kit:stadium("Windows", 6.6, 1.8, wid - 0.6, CF(0, 4.5, 0.6), glass, M.Glass, { transparency = 0.2 })
		kit:stadium("Roof", 6.4, 0.4, wid - 1.0, CF(0, 5.7, 0.6), c, M.SmoothPlastic)
	else
		-- boxy estate
		kit:box("Body", V3(wid, 2.6, len), CF(0, 2.2, 0), c, M.SmoothPlastic, { collide = true })
		kit:box("Bonnet", V3(wid - 0.4, 0.5, 4.4), CF(0, 3.65, -4.6), c, M.SmoothPlastic)
		kit:box("Cabin", V3(wid - 0.6, 2.4, 8.4), CF(0, 4.9, 1.4), c, M.SmoothPlastic)
		kit:box("Windows", V3(wid - 0.4, 1.7, 8.0), CF(0, 5.0, 1.4), glass, M.Glass, { transparency = 0.2 })
		kit:box("Roof", V3(wid - 0.8, 0.4, 8.6), CF(0, 6.3, 1.4), c, M.SmoothPlastic)
		for _, sz in ipairs({ -1.4, 1.4, 4.2 }) do
			kit:box("Pillar", V3(wid - 0.3, 1.8, 0.35), CF(0, 5.0, sz), c, M.SmoothPlastic)
		end
	end
	kit:box("FrontBumper", V3(wid + 0.2, 0.55, 0.7), CF(0, 1.4, -len / 2 - 0.1), chrome, M.Metal)
	kit:box("RearBumper", V3(wid + 0.2, 0.55, 0.7), CF(0, 1.4, len / 2 + 0.1), chrome, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		kit:ball("Headlight", 1.1, CF(sx * 2.0, 2.6, -len / 2 + 0.1), rgb(255, 246, 214), M.Neon)
		kit:box("Taillight", V3(0.8, 0.6, 0.3), CF(sx * 2.2, 2.7, len / 2 + 0.05), rgb(210, 30, 30), M.Neon)
		kit:box("Mirror", V3(0.5, 0.5, 0.3), CF(sx * (wid / 2 + 0.4), 4.6, -2.2), rgb(40, 40, 44), M.Metal)
		for _, sz in ipairs({ -4.4, 4.4 }) do
			kit:cyl("Tyre", 1.2, 3.0, 3.0, CF(sx * (wid / 2 - 0.1), 1.5, sz), rgb(26, 26, 28), M.Rubber)
			kit:cyl("Hubcap", 1.3, 1.7, 1.7, CF(sx * (wid / 2 - 0.05), 1.5, sz), chrome, M.Metal)
		end
	end
	kit:box("Grille", V3(2.6, 0.8, 0.2), CF(0, 2.2, -len / 2 - 0.05), rgb(40, 40, 44), M.Metal)
	kit:box("Plate", V3(1.8, 0.7, 0.1), CF(0, 1.7, len / 2 + 0.15), rgb(240, 240, 232), M.SmoothPlastic)
end

function Props.tractor(parent: Instance, cf: CFrame, color: Color3?)
	local kit = kitAt(parent, cf)
	local c = color or rgb(52, 112, 64)
	local dark = rgb(30, 30, 34)
	kit:box("Hood", V3(3.4, 3, 6.6), CF(0, 4.2, -3.6), c, M.SmoothPlastic, { collide = true })
	kit:box("Grille", V3(3.0, 2.2, 0.3), CF(0, 4.2, -7.0), dark, M.Metal)
	kit:box("Chassis", V3(3.2, 1.6, 12), CF(0, 2.6, 0), rgb(70, 70, 74), M.Metal, { collide = true })
	kit:box("CabFloor", V3(5.4, 0.5, 5.4), CF(0, 4.4, 3.2), c, M.SmoothPlastic)
	kit:box("Cab", V3(5.0, 5.6, 4.8), CF(0, 7.3, 3.2), rgb(150, 190, 212), M.Glass, { transparency = 0.45 })
	kit:box("CabRoof", V3(5.6, 0.5, 5.6), CF(0, 10.3, 3.2), c, M.SmoothPlastic)
	for _, sx in ipairs({ -2.4, 2.4 }) do
		for _, sz in ipairs({ 0.8, 5.6 }) do
			kit:box("CabPost", V3(0.35, 5.6, 0.35), CF(sx, 7.3, sz), c, M.SmoothPlastic)
		end
		kit:cyl("RearTyre", 2.4, 8, 8, CF(sx * 1.55, 4, 4.5), dark, M.Rubber)
		kit:cyl("RearRim", 2.5, 4.4, 4.4, CF(sx * 1.55, 4, 4.5), rgb(200, 190, 60), M.Metal)
		kit:cyl("FrontTyre", 1.4, 4.4, 4.4, CF(sx * 1.55, 2.2, -6), dark, M.Rubber)
		kit:cyl("FrontRim", 1.5, 2.4, 2.4, CF(sx * 1.55, 2.2, -6), rgb(200, 190, 60), M.Metal)
	end
	kit:tube("Exhaust", V3(1.1, 5.6, -5.6), V3(1.1, 9.4, -5.6), 0.5, dark, M.Metal)
	kit:ball("Beacon", 0.9, CF(0, 10.9, 3.2), rgb(255, 160, 30), M.Neon)
	kit:box("Seat", V3(1.6, 0.4, 1.6), CF(0, 5.2, 3.6), dark, M.Fabric)
end

function Props.haybale(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	kit:cyl("Bale", 4, 4.4, 4.4, CF(0, 2.2, 0), rgb(216, 192, 100), M.Grass, { collide = true })
	kit:cyl("Wrap", 4.02, 4.5, 4.5, CF(0, 2.2, 0), rgb(235, 230, 215), M.Fabric, { transparency = 0.7 })
end

function Props.turbine(parent: Instance, cf: CFrame)
	local kit = kitAt(parent, cf)
	kit:cone("Tower", V3(0, 0, 0), V3(0, 60, 0), 4.2, 2.2, 8, rgb(238, 238, 236), M.Metal, { collide = true })
	kit:box("Nacelle", V3(3.4, 3.4, 9), CF(0, 61.5, 1.5), rgb(238, 238, 236), M.Metal)
	kit:ball("Hub", 3, CF(0, 61.5, -3.4), rgb(228, 228, 226), M.Metal)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.4
		local tip = V3(math.sin(a) * 28, 61.5 + math.cos(a) * 28, -3.6)
		kit:strip("Blade", V3(0, 61.5, -3.6), tip, 1.6, 0.4, rgb(244, 244, 242), M.SmoothPlastic)
	end
end

return Props
