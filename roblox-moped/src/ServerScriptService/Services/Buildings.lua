--[[
	Buildings  (ModuleScript, ServerScriptService/Services)

	Detailed German village architecture, built from parts with ModelKit:

	  house      half-timbered (Fachwerk), plastered (Putz), brick, stone;
	             jettied upper floor, gabled tile roof, chimney, shutters,
	             window boxes, door with step and lantern
	  church     nave + arched windows + clock tower + spire
	  barn       red plank barn with hay door, silos
	  shop       ground-floor shop with awning, hanging sign, display windows
	  garage     workshop with roller doors, tyre stacks, sign
	  petrolStation   canopy, pumps with displays, price pylon, kiosk
	  gasthof    inn with hanging sign and beer garden

	Every builder is   Buildings.xxx(parent, worldCFrame, options) -> Model, radius
	and first looks for YOUR OWN model in ReplicatedStorage/TownModels:
	  TownModels/Fachwerkhaus1, Fachwerkhaus2 ...   (any name starting with the
	  builder's template prefix) - one is picked at random and used instead.
	Local axes of a building: front door faces +Z, origin at ground level centre.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local ModelKit = require(ReplicatedStorage.Shared.ModelKit)

local Buildings = {}

local V3, CF = Vector3.new, CFrame.new
local rgb = Color3.fromRGB
local M = Enum.Material

Buildings.palette = {
	walls = { rgb(238, 228, 204), rgb(226, 200, 156), rgb(206, 218, 200), rgb(240, 212, 196), rgb(208, 218, 232), rgb(244, 242, 236), rgb(232, 214, 170) },
	-- { colour, material }
	roofs = { { rgb(168, 72, 54), M.ClayRoofTiles }, { rgb(146, 62, 48), M.ClayRoofTiles }, { rgb(118, 76, 64), M.ClayRoofTiles }, { rgb(92, 96, 104), M.Slate } },
	timber = { rgb(78, 52, 38), rgb(60, 42, 34), rgb(96, 62, 44) },
	shutters = { rgb(56, 108, 70), rgb(150, 44, 40), rgb(50, 82, 130), rgb(104, 72, 48), rgb(230, 226, 214) },
	flowers = { rgb(224, 70, 96), rgb(240, 200, 60), rgb(240, 120, 60), rgb(250, 250, 245), rgb(170, 90, 200) },
	brick = rgb(158, 84, 66),
	stone = rgb(150, 148, 142),
	glass = rgb(150, 188, 212),
	door = { rgb(94, 58, 40), rgb(60, 92, 70), rgb(120, 46, 40), rgb(50, 70, 110) },
}

local function pick(list, rng)
	return list[rng:NextInteger(1, #list)]
end

----------------------------------------------------------------------------
-- user-supplied replacement models
----------------------------------------------------------------------------
local function template(prefix: string, parent: Instance, cf: CFrame, rng): Model?
	local store = ReplicatedStorage:FindFirstChild("TownModels")
	if not store then
		return nil
	end
	local options = {}
	for _, c in ipairs(store:GetChildren()) do
		if c:IsA("Model") and c.Name:sub(1, #prefix) == prefix then
			table.insert(options, c)
		end
	end
	if #options == 0 then
		return nil
	end
	local m = options[rng:NextInteger(1, #options)]:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

local function newModel(parent: Instance, name: string, cf: CFrame)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m, ModelKit.new(m, nil, cf, true)
end

local function faceCF(w: number, d: number, side: string, ext: number): CFrame
	if side == "front" then
		return CF(0, 0, d / 2 + ext)
	elseif side == "back" then
		return CF(0, 0, -(d / 2 + ext)) * CFrame.Angles(0, math.pi, 0)
	elseif side == "right" then
		return CF(w / 2 + ext, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	end
	return CF(-(w / 2 + ext), 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
end

----------------------------------------------------------------------------
-- reusable parts
----------------------------------------------------------------------------
local function window(kit, face: CFrame, x: number, y: number, ww: number, wh: number, o)
	local frameColor = o.frame or rgb(240, 238, 230)
	kit:box("WindowFrame", V3(ww + 0.7, wh + 0.7, 0.3), face * CF(x, y, 0.1), frameColor, M.Wood)
	kit:box("WindowGlass", V3(ww - 0.1, wh - 0.1, 0.1), face * CF(x, y, 0.26), rgb(70, 92, 112), M.Glass, { transparency = 0.2, reflectance = 0.2 })
	kit:box("MullionV", V3(0.16, wh, 0.12), face * CF(x, y, 0.36), frameColor, M.Wood)
	kit:box("MullionH", V3(ww, 0.16, 0.12), face * CF(x, y, 0.36), frameColor, M.Wood)
	if o.shutters or o.flowers then
		kit:box("Sill", V3(ww + 1.0, 0.3, 0.7), face * CF(x, y - wh / 2 - 0.4, 0.3), Buildings.palette.stone, M.Concrete)
	end
	if o.shutters then
		for _, s in ipairs({ -1, 1 }) do
			kit:box("Shutter", V3(ww * 0.5, wh, 0.14), face * CF(x + s * (ww / 2 + ww * 0.25 + 0.38), y, 0.12), o.shutters, M.Wood)
		end
	end
	if o.flowers then
		kit:box("FlowerBox", V3(ww + 0.4, 0.55, 0.6), face * CF(x, y - wh / 2 - 0.6, 0.62), rgb(92, 62, 44), M.Wood)
		for i = -1, 1, 2 do
			kit:ball("Flower", 0.8, face * CF(x + i * ww * 0.28, y - wh / 2 - 0.1, 0.62), o.flowers, M.Grass)
		end
	end
end

local function timberFace(kit, face: CFrame, len: number, y0: number, y1: number, color, braces: boolean)
	local n = math.max(2, math.floor(len / 8))
	local h = y1 - y0
	kit:box("Sill", V3(len, 0.5, 0.4), face * CF(0, y0 + 0.25, 0.1), color, M.Wood)
	kit:box("Header", V3(len, 0.5, 0.4), face * CF(0, y1 - 0.25, 0.1), color, M.Wood)
	for i = 0, n do
		local x = -len / 2 + len * i / n
		kit:box("Post", V3(0.5, h, 0.4), face * CF(x, y0 + h / 2, 0.1), color, M.Wood)
	end
	if braces then
		for i = 0, n - 1, 2 do
			local xa, xb = -len / 2 + len * i / n, -len / 2 + len * (i + 1) / n
			local a = face * V3(xa, y0 + 0.5, 0.1)
			local b = face * V3(xb, y1 - 0.5, 0.1)
			kit:strut("Brace", a, b, 0.4, color, M.Wood)
		end
	end
end

local function doorway(kit, face: CFrame, x: number, doorColor, o)
	kit:box("DoorFrame", V3(4.2, 7.3, 0.45), face * CF(x, 1.4 + 3.65, 0.12), o.frame or Buildings.palette.timber[1], M.Wood)
	kit:box("Door", V3(3.4, 6.6, 0.3), face * CF(x, 1.4 + 3.3, 0.3), doorColor, M.WoodPlanks)
	kit:box("DoorGlass", V3(1.4, 1.8, 0.1), face * CF(x, 1.4 + 4.9, 0.47), Buildings.palette.glass, M.Glass, { transparency = 0.3 })
	kit:ball("DoorKnob", 0.3, face * CF(x + 1.2, 1.4 + 3.3, 0.55), rgb(206, 170, 80), M.Metal)
	kit:box("DoorStep", V3(4.8, 0.6, 1.9), face * CF(x, 0.3, 1.0), Buildings.palette.stone, M.Granite, { collide = true })
	for _, s in ipairs({ -1, 1 }) do
		kit:box("LanternArm", V3(0.12, 0.12, 0.6), face * CF(x + s * 2.9, 1.4 + 5.6, 0.5), rgb(30, 30, 30), M.Metal)
		kit:box("Lantern", V3(0.5, 0.8, 0.5), face * CF(x + s * 2.9, 1.4 + 5.1, 0.8), rgb(255, 224, 150), M.Neon)
	end
end

local function chimney(kit, x: number, y: number, z: number)
	kit:box("Chimney", V3(2.2, 7, 2.2), CF(x, y + 3.5, z), Buildings.palette.brick, M.Brick)
	kit:box("ChimneyCap", V3(2.8, 0.5, 2.8), CF(x, y + 7.2, z), rgb(110, 108, 104), M.Concrete)
	kit:box("ChimneyPot", V3(1.0, 1.2, 1.0), CF(x, y + 8.0, z), rgb(150, 70, 50), M.Brick)
end

-- gable roof over a rectangle w x d (ridge along X) with stepped gable ends
local function gableRoof(kit, w: number, d: number, y0: number, color, material, pitchDeg: number?)
	local p = math.rad(pitchDeg or 38)
	local over = 1.0
	local half = d / 2 + over
	local rise = half * math.tan(p)
	local slope = half / math.cos(p)
	local zmid = half / 2
	local len = w + 2.6
	for _, s in ipairs({ -1, 1 }) do
		kit:box("RoofPlane", V3(len, 0.5, slope), CF(0, y0 + rise / 2 + 0.28, s * zmid) * CFrame.Angles(s * p, 0, 0), color, material, { collide = true })
		kit:box("RoofEdge", V3(len + 0.2, 0.3, 0.3), CF(0, y0 + 0.1, s * (half - 0.05)), rgb(80, 56, 44), M.Wood)
	end
	kit:box("RidgeCap", V3(len + 0.1, 0.45, 0.9), CF(0, y0 + rise + 0.45, 0), rgb(90, 52, 44), M.Slate)
	-- gable ends: filled with plaster steps, topped by a bargeboard look
	local gh = (d / 2) * math.tan(p)
	local steps = 5
	for _, sx in ipairs({ -1, 1 }) do
		for j = 1, steps do
			local depth = d * (1 - (j - 0.5) / steps)
			kit:box("GableFill", V3(0.6, gh / steps + 0.05, depth), CF(sx * (w / 2 - 0.1), y0 + (j - 0.5) * gh / steps, 0), rgb(236, 228, 208), M.Plaster)
		end
		kit:cyl("AtticWindow", 0.3, 2.2, 2.2, CF(sx * (w / 2 + 0.1), y0 + gh * 0.35, 0) * CFrame.Angles(0, 0, 0), rgb(240, 238, 230), M.Wood)
		kit:cyl("AtticGlass", 0.2, 1.7, 1.7, CF(sx * (w / 2 + 0.2), y0 + gh * 0.35, 0), Buildings.palette.glass, M.Glass, { transparency = 0.3 })
	end
	return rise
end

----------------------------------------------------------------------------
-- HOUSE
----------------------------------------------------------------------------
function Buildings.house(parent: Instance, cf: CFrame, o)
	o = o or {}
	local rng = o.rng or Random.new(1)
	local t = template("Fachwerkhaus", parent, cf, rng)
	if t then
		return t, 20
	end
	local P = Buildings.palette
	local style = o.style or "putz"
	local w, d = o.w or rng:NextInteger(24, 34), o.d or rng:NextInteger(20, 26)
	local h1, h2 = o.h1 or 9, o.h2 or 8
	local floors = o.floors or 2
	local wall = o.wall or pick(P.walls, rng)
	local timber = o.timber or pick(P.timber, rng)
	local roof, roofMat
	if o.roof then
		roof, roofMat = o.roof, o.roofMat or M.ClayRoofTiles
	else
		local pair = pick(P.roofs, rng)
		roof, roofMat = pair[1], pair[2]
	end
	local shutter = o.shutter or pick(P.shutters, rng)
	local flower = pick(P.flowers, rng)
	local door = pick(P.door, rng)
	local fancy = o.fancy ~= false
	local wallMat = style == "brick" and M.Brick or (style == "stone" and M.Limestone or M.Plaster)
	if style == "brick" then
		wall = P.brick
	elseif style == "stone" then
		wall = rgb(190, 184, 170)
	end

	local model, kit = newModel(parent, o.name or "Haus", cf)
	local top = 1.4 + h1 + (floors == 2 and h2 or 0)

	-- foundation + walls
	kit:box("Plinth", V3(w + 0.8, 1.4, d + 0.8), CF(0, 0.7, 0), P.stone, M.Granite, { collide = true })
	local body = kit:box("Walls", V3(w, h1, d), CF(0, 1.4 + h1 / 2, 0), wall, wallMat, { collide = true })
	local jet = (floors == 2 and style == "fachwerk") and 0.6 or 0
	if floors == 2 then
		kit:box("UpperWalls", V3(w + jet * 2, h2, d + jet * 2), CF(0, 1.4 + h1 + h2 / 2, 0), wall, wallMat, { collide = true })
		if jet > 0 then
			kit:box("JettyBand", V3(w + 1.4, 0.6, d + 1.4), CF(0, 1.4 + h1 + 0.3, 0), timber, M.Wood)
		elseif style ~= "brick" then
			kit:box("FloorBand", V3(w + 0.3, 0.45, d + 0.3), CF(0, 1.4 + h1, 0), rgb(246, 244, 238), M.Plaster)
		end
	end
	if style ~= "fachwerk" then
		-- corner quoins
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				kit:box("Quoin", V3(0.9, top - 1.4, 0.9), CF(sx * w / 2, 1.4 + (top - 1.4) / 2, sz * d / 2), style == "brick" and rgb(208, 196, 176) or rgb(246, 244, 238), M.Concrete)
			end
		end
	end

	-- timber frame (Fachwerk)
	if style == "fachwerk" then
		for _, side in ipairs({ "front", "back", "right", "left" }) do
			local len = (side == "front" or side == "back") and w or d
			timberFace(kit, faceCF(w, d, side, 0), len, 1.4, 1.4 + h1, timber, fancy)
			if floors == 2 then
				timberFace(kit, faceCF(w, d, side, jet), len + jet * 2, 1.4 + h1 + 0.6, top, timber, true)
			end
		end
	end

	-- windows
	local frame = (style == "fachwerk") and rgb(246, 244, 238) or rgb(246, 244, 238)
	local function row(side: string, floor: number, withDoor: boolean)
		local len = (side == "front" or side == "back") and w or d
		local ext = floor == 2 and jet or 0
		len += ext * 2
		local face = faceCF(w, d, side, ext)
		local n = math.max(1, math.floor((len - 5) / 8))
		local y = floor == 1 and (1.4 + h1 * 0.55) or (1.4 + h1 + h2 * 0.5)
		local doorX = -len * 0.2
		for i = 1, n do
			local x = -len / 2 + (i - 0.5) * len / n
			if not (withDoor and math.abs(x - doorX) < 5.2) then
				local opts = { frame = frame }
				if side == "front" and fancy then
					opts.shutters = shutter
					opts.flowers = (floor == 2 or rng:NextNumber() < 0.5) and flower or nil
				end
				window(kit, face, x, y, 3.0, 3.8, opts)
			end
		end
		return doorX
	end
	for _, side in ipairs({ "front", "back", "right", "left" }) do
		row(side, 1, side == "front")
		if floors == 2 then
			row(side, 2, false)
		end
	end
	doorway(kit, faceCF(w, d, "front", 0), -w * 0.2, door, { frame = (style == "fachwerk") and timber or rgb(246, 244, 238) })

	-- roof
	local rise = gableRoof(kit, w, d, top, roof, roofMat, o.pitch or 38)
	chimney(kit, w * 0.28, top + rise * 0.5, -d * 0.12)
	if floors == 2 and fancy and rng:NextNumber() < 0.6 then
		-- dormer on the front slope
		local zD = d / 4
		local dy = top + (d / 2 + 1.0 - zD) * math.tan(math.rad(o.pitch or 38)) * 0.9
		kit:box("DormerWalls", V3(4.2, 3.4, 2.6), CF(-w * 0.2, dy + 1.2, zD + 0.4), wall, M.Plaster)
		window(kit, CF(-w * 0.2, dy + 1.2, zD + 1.7), 0, 0.1, 2.4, 2.2, { frame = frame })
		kit:box("DormerRoof", V3(5.0, 0.4, 3.4), CF(-w * 0.2, dy + 3.15, zD + 0.6) * CFrame.Angles(math.rad(-10), 0, 0), roof, M.Slate)
	end

	-- little garden bits
	if o.garden ~= false then
		kit:box("Path", V3(3.6, 0.12, 9), CF(-w * 0.2, 0.08, d / 2 + 5.4), rgb(176, 168, 152), M.Pavement)
		for _, sx in ipairs({ -1, 1 }) do
			kit:box("Hedge", V3(w * 0.35, 1.8, 1.4), CF(-w * 0.2 + sx * (w * 0.2 + 2.6), 0.9, d / 2 + 2.2), rgb(62, 112, 50), M.Grass, { collide = true })
		end
	end

	local r = math.max(w, d) / 2 + 6
	return model, r, body
end

----------------------------------------------------------------------------
-- CHURCH
----------------------------------------------------------------------------
function Buildings.church(parent: Instance, cf: CFrame, o)
	o = o or {}
	local rng = o.rng or Random.new(2)
	local t = template("Kirche", parent, cf, rng)
	if t then
		return t, 40
	end
	local model, kit = newModel(parent, "Kirche", cf)
	local stone = rgb(228, 222, 206)
	local slate = rgb(78, 84, 92)
	local w, d, h = 24, 46, 22
	kit:box("Plinth", V3(w + 1, 1.4, d + 1), CF(0, 0.7, 0), Buildings.palette.stone, M.Granite, { collide = true })
	local nave = kit:box("Nave", V3(w, h, d), CF(0, 1.4 + h / 2, 0), stone, M.Plaster, { collide = true })
	local top = 1.4 + h
	local rise = gableRoof(kit, w, d, top, slate, M.Slate, 40)
	-- buttresses + arched windows along both sides
	for _, side in ipairs({ -1, 1 }) do
		for i = -2, 2 do
			local z = i * 8
			kit:box("Buttress", V3(1.2, h * 0.9, 1.6), CF(side * (w / 2 + 0.6), 1.4 + h * 0.45, z + 4), stone, M.Concrete)
			local face = CF(side * (w / 2), 0, z) * CFrame.Angles(0, side * math.pi / 2, 0)
			kit:box("WindowFrame", V3(3.4, 7, 0.4), face * CF(0, 1.4 + h * 0.5, 0.15), rgb(236, 232, 220), M.Concrete)
			kit:box("WindowGlass", V3(2.8, 6.4, 0.2), face * CF(0, 1.4 + h * 0.5, 0.3), rgb(110, 140, 190), M.Glass, { transparency = 0.25 })
			kit:cyl("WindowArch", 0.4, 3.4, 3.4, face * CF(0, 1.4 + h * 0.5 + 3.5, 0.15) * CFrame.Angles(0, math.pi / 2, 0), rgb(236, 232, 220), M.Concrete)
			kit:cyl("WindowArchGlass", 0.2, 2.8, 2.8, face * CF(0, 1.4 + h * 0.5 + 3.5, 0.3) * CFrame.Angles(0, math.pi / 2, 0), rgb(110, 140, 190), M.Glass, { transparency = 0.25 })
		end
	end
	-- tower at the front (+Z)
	local tz = d / 2 + 4
	local tw, th = 12, 44
	kit:box("Tower", V3(tw, th, tw), CF(0, 1.4 + th / 2, tz), stone, M.Plaster, { collide = true })
	kit:box("TowerBase", V3(tw + 1.2, 3, tw + 1.2), CF(0, 2.5, tz), rgb(170, 166, 156), M.Granite)
	-- belfry openings + clock faces on all four sides
	local belfry = 1.4 + th - 8
	for k = 0, 3 do
		local face = CF(0, 0, tz) * CFrame.Angles(0, k * math.pi / 2, 0) * CF(0, 0, tw / 2)
		kit:box("BelfryOpening", V3(3, 6, 0.4), face * CF(0, belfry, 0.1), rgb(30, 28, 30), M.SmoothPlastic)
		kit:cyl("BelfryArch", 0.4, 3, 3, face * CF(0, belfry + 3, 0.1) * CFrame.Angles(0, math.pi / 2, 0), rgb(30, 28, 30), M.SmoothPlastic)
		kit:cyl("ClockFace", 0.4, 5, 5, face * CF(0, belfry - 11, 0.2) * CFrame.Angles(0, math.pi / 2, 0), rgb(250, 248, 240), M.SmoothPlastic)
		kit:box("ClockHandH", V3(0.2, 1.8, 0.1), face * CF(0, belfry - 11.6, 0.5), rgb(20, 20, 20), M.Metal)
		kit:box("ClockHandM", V3(1.2, 0.2, 0.1), face * CF(0.5, belfry - 11, 0.5), rgb(20, 20, 20), M.Metal)
	end
	kit:box("TowerCornice", V3(tw + 1.4, 1, tw + 1.4), CF(0, 1.4 + th, tz), rgb(190, 184, 170), M.Concrete)
	-- spire: tapered stack
	kit:cone("Spire", V3(0, 1.4 + th + 0.5, tz), V3(0, 1.4 + th + 26, tz), 10, 0.6, 9, slate, M.Slate)
	kit:tube("CrossPole", V3(0, 1.4 + th + 26, tz), V3(0, 1.4 + th + 31, tz), 0.35, rgb(214, 170, 70), M.Metal)
	kit:strut("CrossBar", V3(-1.4, 1.4 + th + 29, tz), V3(1.4, 1.4 + th + 29, tz), 0.35, rgb(214, 170, 70), M.Metal)
	kit:ball("Weathercock", 0.9, CF(0, 1.4 + th + 31.4, tz), rgb(214, 170, 70), M.Metal)
	-- portal
	local pf = CF(0, 0, tz + tw / 2)
	kit:box("PortalFrame", V3(6.4, 10.4, 0.6), pf * CF(0, 6.6, 0.1), rgb(210, 204, 190), M.Concrete)
	kit:box("PortalDoor", V3(5.4, 9.4, 0.4), pf * CF(0, 6.1, 0.4), rgb(84, 56, 40), M.WoodPlanks)
	kit:cyl("PortalArch", 0.5, 6.4, 6.4, pf * CF(0, 11.8, 0.1) * CFrame.Angles(0, math.pi / 2, 0), rgb(210, 204, 190), M.Concrete)
	kit:box("PortalSteps", V3(8, 0.6, 3), pf * CF(0, 0.3, 2), rgb(170, 166, 156), M.Granite, { collide = true })
	-- apse (rear) + low sacristy
	kit:cyl("Apse", h, 14, 14, CF(0, 1.4 + h / 2, -d / 2 - 3) * CFrame.Angles(0, 0, math.pi / 2), stone, M.Plaster, { collide = true })
	kit:cyl("ApseRoof", 6, 14.6, 14.6, CF(0, 1.4 + h + 3, -d / 2 - 3) * CFrame.Angles(0, 0, math.pi / 2), slate, M.Slate)
	-- graveyard wall
	kit:box("WallL", V3(1, 3, d + 24), CF(-w / 2 - 9, 1.5, 0), rgb(168, 164, 154), M.Limestone, { collide = true })
	kit:box("WallR", V3(1, 3, d + 24), CF(w / 2 + 9, 1.5, 0), rgb(168, 164, 154), M.Limestone, { collide = true })
	kit:box("WallBack", V3(w + 19, 3, 1), CF(0, 1.5, -d / 2 - 12), rgb(168, 164, 154), M.Limestone, { collide = true })
	for i = 1, 8 do
		local gx = (i % 2 == 0 and -1 or 1) * (w / 2 + 3 + (i % 3) * 2)
		local gz = -d / 2 + 6 + i * 3.4
		kit:box("Gravestone", V3(1.6, 3, 0.5), CF(gx, 1.5, gz), rgb(150, 150, 150), M.Granite)
	end
	return model, d / 2 + 14, nave
end

----------------------------------------------------------------------------
-- BARN + SILOS
----------------------------------------------------------------------------
function Buildings.barn(parent: Instance, cf: CFrame, o)
	o = o or {}
	local rng = o.rng or Random.new(3)
	local t = template("Scheune", parent, cf, rng)
	if t then
		return t, 40
	end
	local model, kit = newModel(parent, "Scheune", cf)
	local w, d, h = 46, 34, 17
	local red = rgb(142, 52, 44)
	local body = kit:box("Walls", V3(w, h, d), CF(0, h / 2 + 0.6, 0), red, M.WoodPlanks, { collide = true })
	kit:box("Foundation", V3(w + 0.6, 1.2, d + 0.6), CF(0, 0.6, 0), Buildings.palette.stone, M.Concrete)
	-- vertical trim boards
	for _, sz in ipairs({ -1, 1 }) do
		for i = -4, 4 do
			kit:box("Batten", V3(0.5, h, 0.3), CF(i * (w / 9), h / 2 + 0.6, sz * (d / 2 + 0.15)), rgb(120, 42, 36), M.WoodPlanks)
		end
	end
	local rise = gableRoof(kit, w, d, h + 0.6, rgb(86, 80, 78), M.CorrodedMetal, 30)
	-- big double door on the front with white X braces
	local face = CF(0, 0, d / 2)
	kit:box("DoorFrame", V3(14.4, 13.4, 0.5), face * CF(0, 7.3, 0.2), rgb(238, 234, 224), M.Wood)
	kit:box("DoorDark", V3(13.4, 12.4, 0.4), face * CF(0, 6.8, 0.35), rgb(98, 40, 34), M.WoodPlanks)
	kit:strut("DoorX1", face * V3(-6.4, 1.2, 0.7), face * V3(-0.2, 12.4, 0.7), 0.5, rgb(238, 234, 224), M.Wood)
	kit:strut("DoorX2", face * V3(-0.2, 1.2, 0.7), face * V3(-6.4, 12.4, 0.7), 0.5, rgb(238, 234, 224), M.Wood)
	kit:strut("DoorX3", face * V3(0.2, 1.2, 0.7), face * V3(6.4, 12.4, 0.7), 0.5, rgb(238, 234, 224), M.Wood)
	kit:strut("DoorX4", face * V3(6.4, 1.2, 0.7), face * V3(0.2, 12.4, 0.7), 0.5, rgb(238, 234, 224), M.Wood)
	-- hay loft hatch
	kit:box("LoftHatch", V3(4, 4.4, 0.4), face * CF(0, h + 3.2, 0.2), rgb(98, 40, 34), M.WoodPlanks)
	kit:box("LoftFrame", V3(4.8, 5.2, 0.3), face * CF(0, h + 3.2, 0.1), rgb(238, 234, 224), M.Wood)
	kit:tube("HoistBeam", face * V3(0, h + 6.6, 0.2), face * V3(0, h + 6.6, 3.6), 0.4, rgb(70, 52, 40), M.Wood)
	-- silos
	for i, z in ipairs({ -8, 10 }) do
		local sx = w / 2 + 8
		kit:cyl("Silo", 30 - i * 3, 9, 9, CF(sx, (30 - i * 3) / 2, z) * CFrame.Angles(0, 0, math.pi / 2), rgb(176, 180, 184), M.Metal, { collide = true })
		kit:ball("SiloDome", 9, CF(sx, 30 - i * 3, z), rgb(150, 154, 160), M.Metal)
		for k = 1, 4 do
			kit:cyl("SiloRing", 9.3, 0.3, 0.3, CF(sx, k * 5.5, z), rgb(120, 124, 130), M.Metal)
		end
	end
	return model, 46, body
end

----------------------------------------------------------------------------
-- SHOP (ground floor shop with awning, sign) - Bakery / general store
----------------------------------------------------------------------------
function Buildings.shop(parent: Instance, cf: CFrame, o)
	o = o or {}
	local rng = o.rng or Random.new(4)
	local model, r, body = Buildings.house(parent, cf, { name = o.name or "Laden", rng = rng, style = o.style or "putz", w = 36, d = 24, wall = o.wall, roof = o.roof, roofMat = o.roofMat, fancy = true, garden = false })
	local kit = ModelKit.new(model, nil, cf, true)
	local w, d = 36, 24
	local face = CF(0, 0, d / 2)
	-- display window + shop door replace the front look
	kit:box("ShopWindowFrame", V3(15, 6.4, 0.5), face * CF(7, 4.8, 0.45), rgb(50, 50, 56), M.Metal)
	kit:box("ShopWindowGlass", V3(14.2, 5.6, 0.3), face * CF(7, 4.8, 0.62), Buildings.palette.glass, M.Glass, { transparency = 0.45, reflectance = 0.2 })
	for i = -2, 2 do
		kit:box("DisplayItem", V3(1.6, 1.2, 1.2), face * CF(7 + i * 2.6, 2.3, 0.2), o.itemColor or rgb(214, 170, 90), M.Wood)
	end
	-- awning: alternating stripes, tilted
	local colors = o.awning or { rgb(188, 40, 44), rgb(246, 244, 238) }
	local aw = 22
	for i = 0, 10 do
		local x = -aw / 2 + (i + 0.5) * aw / 11 - 2
		kit:box("AwningStripe", V3(aw / 11, 0.25, 4.6), face * CF(x + 0, 8.6, 2.2) * CFrame.Angles(math.rad(14), 0, 0), colors[i % 2 + 1], M.Fabric)
	end
	kit:box("AwningValance", V3(aw, 0.9, 0.2), face * CF(-2, 7.55, 4.1), colors[1], M.Fabric)
	-- hanging sign + wall sign
	local sign = kit:box("SignBoard", V3(14, 2.6, 0.5), face * CF(-2, 11.6, 0.5), rgb(46, 40, 38), M.Wood)
	ModelKit.signText(sign, o.text or "LADEN", Enum.NormalId.Back, rgb(245, 220, 150))
	kit:box("HangSignArm", V3(0.2, 0.2, 3), face * CF(w / 2 - 1, 9.6, 1.5), rgb(30, 30, 30), M.Metal)
	local hang = kit:box("HangSign", V3(0.3, 3, 3), face * CF(w / 2 - 1, 8.1, 2.4), o.hangColor or rgb(214, 170, 70), M.Wood)
	ModelKit.signText(hang, o.hangText or "Laden", Enum.NormalId.Right, rgb(40, 30, 20))
	return model, r + 2, body
end

----------------------------------------------------------------------------
-- GASTHOF (inn) with beer garden
----------------------------------------------------------------------------
function Buildings.gasthof(parent: Instance, cf: CFrame, o)
	o = o or {}
	local rng = o.rng or Random.new(5)
	local model, r, body = Buildings.house(parent, cf, { name = "Gasthof", rng = rng, style = "fachwerk", w = 50, d = 28, h1 = 10, h2 = 9, wall = rgb(240, 232, 208), timber = rgb(70, 46, 36), roof = rgb(150, 62, 48), garden = false })
	local kit = ModelKit.new(model, nil, cf, true)
	local w, d = 50, 28
	local face = CF(0, 0, d / 2)
	local board = kit:box("InnSign", V3(18, 2.8, 0.5), face * CF(0, 12.8, 1.0), rgb(52, 36, 30), M.Wood)
	ModelKit.signText(board, "GASTHOF ZUR LINDE", Enum.NormalId.Back, rgb(240, 210, 140))
	-- wrought-iron bracket with hanging sign
	kit:box("Bracket", V3(0.25, 0.25, 5), face * CF(w / 2 - 4, 9.6, 3.2), rgb(30, 30, 32), M.Metal)
	kit:box("BracketBrace", V3(0.2, 0.2, 3.2), face * CF(w / 2 - 4, 8.5, 2.2) * CFrame.Angles(math.rad(-35), 0, 0), rgb(30, 30, 32), M.Metal)
	local hang = kit:box("HangSign", V3(0.4, 3.2, 3.6), face * CF(w / 2 - 4, 7.6, 4.6), rgb(210, 170, 60), M.Wood)
	ModelKit.signText(hang, "LINDE", Enum.NormalId.Right, rgb(50, 30, 20))
	-- beer garden: tables, benches, umbrellas
	for ix = -1, 1 do
		for iz = 0, 1 do
			local tx, tz = ix * 12, d / 2 + 11 + iz * 8
			local umb = rgb(200, 52, 48)
			if (ix + iz) % 2 == 0 then
				umb = rgb(246, 244, 238)
			end
			kit:box("TableTop", V3(4.4, 0.25, 4.4), CF(tx, 3.2, tz), rgb(140, 100, 70), M.WoodPlanks)
			kit:tube("TableLeg", V3(tx, 0.2, tz), V3(tx, 3.2, tz), 0.4, rgb(60, 60, 64), M.Metal)
			kit:tube("UmbrellaPole", V3(tx, 3.2, tz), V3(tx, 9.4, tz), 0.2, rgb(220, 220, 220), M.Metal)
			kit:cone("Umbrella", V3(tx, 8.2, tz), V3(tx, 10.2, tz), 8.4, 0.5, 4, umb, M.Fabric)
			for _, bz in ipairs({ -3, 3 }) do
				kit:box("Bench", V3(4.6, 0.25, 1.4), CF(tx, 1.9, tz + bz), rgb(120, 86, 60), M.WoodPlanks)
				kit:box("BenchLeg", V3(0.3, 1.8, 1.1), CF(tx - 1.8, 0.95, tz + bz), rgb(60, 60, 64), M.Metal)
				kit:box("BenchLeg", V3(0.3, 1.8, 1.1), CF(tx + 1.8, 0.95, tz + bz), rgb(60, 60, 64), M.Metal)
			end
		end
	end
	-- flag pole with Bavarian-style blue/white flag
	kit:tube("FlagPole", V3(-w / 2 - 3, 0, d / 2 + 1), V3(-w / 2 - 3, 24, d / 2 + 1), 0.4, rgb(220, 220, 220), M.Metal)
	for i = 0, 5 do
		kit:box("Flag", V3(0.1, 1.1, 1.2), CF(-w / 2 - 3, 22.4 - 0, d / 2 + 1.8 + i * 1.2) * CFrame.Angles(0, 0, 0), (i % 2 == 0) and rgb(40, 100, 190) or rgb(246, 246, 246), M.Fabric)
	end
	return model, r + 18, body
end

----------------------------------------------------------------------------
-- GARAGE / WORKSHOP (brick, roller doors)
----------------------------------------------------------------------------
function Buildings.garage(parent: Instance, cf: CFrame, o)
	o = o or {}
	local rng = o.rng or Random.new(6)
	local t = template("Werkstatt", parent, cf, rng)
	if t then
		return t, 30
	end
	local model, kit = newModel(parent, o.name or "Werkstatt", cf)
	local w, d, h = 40, 26, 14
	local wall = o.wall or rgb(170, 92, 72)
	local body = kit:box("Walls", V3(w, h, d), CF(0, h / 2 + 0.5, 0), wall, M.Brick, { collide = true })
	kit:box("Foundation", V3(w + 0.6, 1, d + 0.6), CF(0, 0.5, 0), rgb(130, 128, 124), M.Concrete)
	kit:box("FlatRoof", V3(w + 1.4, 0.8, d + 1.4), CF(0, h + 0.9, 0), rgb(96, 98, 104), M.Concrete, { collide = true })
	kit:box("RoofEdge", V3(w + 1.6, 1.2, d + 1.6), CF(0, h + 0.4, 0), rgb(214, 214, 208), M.Concrete)
	local face = CF(0, 0, d / 2)
	-- two roller doors
	for i, x in ipairs({ -9, 9 }) do
		kit:box("DoorSurround", V3(12, 10.6, 0.6), face * CF(x, 5.8, 0.15), rgb(240, 240, 232), M.Concrete)
		for k = 0, 8 do
			kit:box("RollerSlat", V3(11, 1.0, 0.3), face * CF(x, 1.4 + k * 1.1, 0.5), (k % 2 == 0) and rgb(206, 208, 212) or rgb(190, 192, 198), M.Metal)
		end
		kit:box("DoorLight", V3(1.2, 0.3, 0.3), face * CF(x, 11.4, 0.6), rgb(255, 230, 160), M.Neon)
	end
	-- office door + window
	kit:box("OfficeDoor", V3(3.2, 6.6, 0.3), face * CF(0, 3.8, 0.4), rgb(50, 70, 110), M.Metal)
	kit:box("OfficeWindow", V3(5.6, 3.4, 0.3), face * CF(15.5, 6.0, 0.45), rgb(170, 205, 225), M.Glass, { transparency = 0.35 })
	-- sign
	local sign = kit:box("Sign", V3(22, 3.4, 0.6), face * CF(0, h - 1.5, 0.5), rgb(30, 60, 120), M.SmoothPlastic)
	ModelKit.signText(sign, o.text or "KFZ-WERKSTATT", Enum.NormalId.Back, rgb(250, 250, 250))
	-- tyre stacks and oil drums beside the building
	for s = 0, 2 do
		for k = 0, 3 do
			kit:cyl("Tyre", 1.3, 3.2, 3.2, CF(w / 2 + 3.5 + s * 3.4, 0.7 + k * 1.3, d / 2 - 3) * CFrame.Angles(0, 0, math.pi / 2), rgb(26, 26, 28), M.Rubber)
		end
	end
	for i = 0, 2 do
		kit:cyl("OilDrum", 3.6, 2.6, 2.6, CF(-w / 2 - 3, 1.8, d / 2 - 2 - i * 3) * CFrame.Angles(0, 0, math.pi / 2), (i % 2 == 0) and rgb(40, 90, 170) or rgb(180, 50, 40), M.Metal, { collide = true })
	end
	return model, 32, body
end

----------------------------------------------------------------------------
-- PETROL STATION
----------------------------------------------------------------------------
function Buildings.petrolStation(parent: Instance, cf: CFrame, o)
	o = o or {}
	local rng = o.rng or Random.new(7)
	local t = template("Tankstelle", parent, cf, rng)
	if t then
		return t, 30
	end
	local model, kit = newModel(parent, o.name or "Tankstelle", cf)
	local brand = o.color or rgb(214, 54, 44)
	kit:box("Forecourt", V3(44, 0.3, 30), CF(0, 0.15, 0), rgb(118, 120, 124), M.Concrete)
	kit:box("Island", V3(28, 0.9, 5), CF(0, 0.6, 0), rgb(176, 176, 172), M.Concrete, { collide = true })
	-- canopy
	kit:box("Canopy", V3(40, 1.4, 22), CF(0, 15.5, 0), rgb(240, 240, 236), M.Metal)
	kit:box("CanopyFascia", V3(40.4, 2.6, 22.4), CF(0, 15.2, 0), brand, M.SmoothPlastic)
	kit:box("CanopyLight", V3(36, 0.2, 18), CF(0, 14.7, 0), rgb(255, 250, 235), M.Neon)
	for _, sx in ipairs({ -14, 14 }) do
		kit:box("Pillar", V3(1.6, 15, 1.6), CF(sx, 7.5, 0), rgb(236, 236, 232), M.Metal, { collide = true })
	end
	-- pumps
	local middle
	for i, px in ipairs({ -8, 0, 8 }) do
		local pump = kit:box("Pump", V3(2.6, 5.6, 1.9), CF(px, 3.7, 0), rgb(232, 232, 228), M.SmoothPlastic, { collide = true })
		kit:box("PumpHead", V3(2.8, 1.4, 2.1), CF(px, 6.0, 0), brand, M.SmoothPlastic)
		kit:box("PumpScreen", V3(1.7, 0.9, 0.2), CF(px, 4.7, 1.0), rgb(70, 220, 130), M.Neon)
		for _, s in ipairs({ -1, 1 }) do
			kit:tube("Hose", V3(px + s * 1.2, 4.2, 0.9 * s), V3(px + s * 1.6, 2.4, 1.1 * s), 0.14, rgb(30, 30, 32), M.Rubber)
			kit:box("Nozzle", V3(0.3, 0.9, 0.3), CF(px + s * 1.6, 2.0, 1.1 * s), rgb(60, 60, 64), M.Metal)
		end
		if i == 2 then
			middle = pump
		end
	end
	CollectionService:AddTag(middle, "PetrolStation")
	-- kiosk
	local kioskCF = CF(0, 0, -17)
	kit:box("Kiosk", V3(22, 9, 10), kioskCF * CF(0, 4.9, 0), rgb(242, 240, 232), M.Plaster, { collide = true })
	kit:box("KioskRoof", V3(24, 0.8, 12), kioskCF * CF(0, 9.8, 0), brand, M.SmoothPlastic, { collide = true })
	kit:box("KioskWindow", V3(14, 4.4, 0.3), kioskCF * CF(2, 5.3, 5.1), rgb(160, 200, 225), M.Glass, { transparency = 0.4 })
	kit:box("KioskDoor", V3(3.4, 6.4, 0.3), kioskCF * CF(-7, 3.9, 5.1), rgb(60, 60, 66), M.Metal)
	local ks = kit:box("KioskSign", V3(12, 2, 0.4), kioskCF * CF(2, 9.0, 5.2), brand, M.SmoothPlastic)
	ModelKit.signText(ks, o.text or "TANKSTELLE", Enum.NormalId.Back, rgb(255, 255, 255))
	-- price pylon by the road
	kit:box("PylonPole", V3(1.2, 24, 1.2), CF(-22, 12, 14), rgb(60, 60, 64), M.Metal)
	local pylon = kit:box("PylonBoard", V3(7, 8, 0.8), CF(-22, 21, 14), brand, M.SmoothPlastic)
	ModelKit.signText(pylon, "SUPER 1,89\nDIESEL 1,79", Enum.NormalId.Back, rgb(255, 255, 255))
	-- air pump + bin + oil can stand
	kit:box("AirPump", V3(1.2, 3.6, 1.2), CF(16, 1.8, -8), rgb(60, 110, 190), M.Metal, { collide = true })
	return model, 34, middle
end

return Buildings
