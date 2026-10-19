--[[
	PlayerGarage  (ModuleScript, ServerScriptService/Services)

	Every player gets a PERSONAL garage in the "Garagenreihe" south of the
	spawn. It is built when they join and removed when they leave.

	  * roller door - rolls up when its owner (or their bike) comes near and
	    closes again when they leave. Also a keypad outside and a button inside
	    (click them). The slats are animated on each client (GarageClient); the
	    server only flips the `Open` attribute and the collision.
	  * ceiling lights + a lamp outside - on while the door is open. Click the
	    light switch to toggle.
	  * bike stand - click it with a bike nearby: the bike is parked on the
	    stand and lifted. The workshop window opens; install / remove parts.
	  * parcel pad - ordered parts arrive in crates. A delivery van drives up,
	    the crate is carried in; click the crate to unpack it.

	Everything is clickable (ClickDetector); only the owner's clicks count.
	Parts logic (orders, inventory, installing) lives in PartsService.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local ModelKit = require(Shared.ModelKit)
local PartsData = require(Shared.PartsData)
local Remotes = require(Shared.Remotes)
local VehicleData = require(Shared.VehicleData)

local CFG = GameConfig.Garage
local V3, CF = Vector3.new, CFrame.new
local rgb = Color3.fromRGB
local M = Enum.Material

local PlayerGarage = {}
local Data, Economy, Vehicles, Parts

local garages: { [Player]: any } = {}
local slotOwner: { [number]: Player } = {}
local folder: Folder

-- Row layout (world): garages side by side along X, doors facing -Z (the street)
local SLOTS_PER_ROW = 16
local PITCH = 36
local ROW_Z = 130
local ROW_GAP = 90

-- Garage dimensions (local: +Z is deeper into the garage, door at z = 0)
local H = 13 -- inner height
local DOOR_W, DOOR_H = 14, 10
local SLAT_COUNT = 10
local STAND_Z = 16.4
local PLAT_LOW = 0.9 -- platform centre height, lowered
local PLAT_TOP = PLAT_LOW + 0.2

local C = {
	brick = rgb(150, 86, 68),
	brickDark = rgb(120, 66, 54),
	concrete = rgb(128, 128, 126),
	pave = rgb(152, 150, 144),
	roof = rgb(72, 74, 80),
	steel = rgb(98, 104, 114),
	chrome = rgb(206, 210, 216),
	yellow = rgb(240, 200, 60),
	black = rgb(28, 28, 32),
	door = rgb(196, 198, 200),
	card = rgb(178, 136, 86),
	cardLight = rgb(206, 170, 118),
	wood = rgb(150, 112, 70),
	green = rgb(40, 84, 62),
	red = rgb(190, 40, 36),
	blue = rgb(52, 88, 150),
}

local function notify(player: Player, text: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, text, kind or "info")
end

local function slotCF(index: number): CFrame
	local row = (index - 1) // SLOTS_PER_ROW
	local col = (index - 1) % SLOTS_PER_ROW
	return CF((col - (SLOTS_PER_ROW - 1) / 2) * PITCH, 0, ROW_Z + row * ROW_GAP)
end

----------------------------------------------------------------------------
-- Lights and door state
----------------------------------------------------------------------------
local function setLights(g, on: boolean)
	g.lightsOn = on
	g.model:SetAttribute("Lights", on)
	for _, tube in ipairs(g.lightParts) do
		tube.Material = on and M.Neon or M.SmoothPlastic
		tube.Color = on and rgb(255, 246, 226) or rgb(150, 150, 150)
		local light = tube:FindFirstChildOfClass("PointLight") or tube:FindFirstChildOfClass("SpotLight")
		if light then
			TweenService:Create(light, TweenInfo.new(0.4), { Brightness = on and (light:GetAttribute("OnBrightness") or 1.4) or 0 }):Play()
			light.Enabled = true
		end
	end
	g.switchLamp.Color = on and rgb(110, 220, 120) or rgb(200, 70, 60)
end

local function setDoor(g, open: boolean)
	if g.open == open then
		return
	end
	g.open = open
	g.model:SetAttribute("Open", open)
	g.door:SetAttribute("Open", open) -- GarageClient animates the slats from this
	g.blocker.CanCollide = not open
	setLights(g, open)
	if open then
		g.padLamp.Color = rgb(110, 220, 120)
	else
		g.padLamp.Color = rgb(200, 70, 60)
	end
end

-- keep the door up while something is happening (a delivery)
local function holdOpen(g, seconds: number)
	g.busyUntil = math.max(g.busyUntil, os.clock() + seconds)
	setDoor(g, true)
end

----------------------------------------------------------------------------
-- Building the garage
----------------------------------------------------------------------------
local function clickable(part: BasePart, distance: number, handler: (Player) -> ())
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = distance
	cd.Parent = part
	cd.MouseClick:Connect(handler)
	return cd
end

local function billboard(adornee: BasePart, text: string, offset: Vector3, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(150, 28)
	gui.StudsOffset = offset
	gui.AlwaysOnTop = true
	gui.MaxDistance = maxDistance or 26
	gui.Parent = adornee
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(24, 26, 32)
	frame.BackgroundTransparency = 0.25
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = rgb(244, 184, 60)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Parent = frame
	return gui
end

local function ownerOnly(g, fn: (Player) -> ())
	return function(player: Player)
		if player ~= g.player then
			notify(player, ("That's %s's garage."):format(g.player.DisplayName), "hint")
			return
		end
		fn(player)
	end
end

local function buildShell(g, kit)
	local function b(name, sx, sy, sz, x, y, z, color, material, opts)
		return kit:box(name, V3(sx, sy, sz), CF(x, y, z), color, material, opts)
	end
	local solid = { collide = true }

	-- floor, apron, walls, roof
	b("Floor", 30, 0.2, 34, 0, 0.1, 16.8, C.concrete, M.Concrete, solid)
	b("Apron", 34, 0.2, 24, 0, 0.1, -12, C.pave, M.Concrete, solid)
	b("WallL", 0.8, H, 33.6, -14.4, H / 2, 16.8, C.brick, M.Brick, solid)
	b("WallR", 0.8, H, 33.6, 14.4, H / 2, 16.8, C.brick, M.Brick, solid)
	b("WallB", 30, H, 0.8, 0, H / 2, 33.2, C.brick, M.Brick, solid)
	local pw = (29.6 - DOOR_W) / 2
	b("PillarL", pw, H, 0.8, -(DOOR_W / 2 + pw / 2), H / 2, 0.4, C.brick, M.Brick, solid)
	b("PillarR", pw, H, 0.8, DOOR_W / 2 + pw / 2, H / 2, 0.4, C.brick, M.Brick, solid)
	b("Lintel", 29.6, H - DOOR_H, 0.8, 0, DOOR_H + (H - DOOR_H) / 2, 0.4, C.brickDark, M.Brick, solid)
	b("Roof", 31.6, 0.6, 34.6, 0, H + 0.3, 16.8, C.roof, M.Concrete, solid)
	for _, s in ipairs({ -1, 1 }) do
		b("Parapet", 0.5, 0.9, 34.6, s * 15.55, H + 1.05, 16.8, C.brickDark, M.Brick)
	end
	b("Parapet", 31.6, 0.9, 0.5, 0, H + 1.05, -0.25, C.brickDark, M.Brick)
	b("Parapet", 31.6, 0.9, 0.5, 0, H + 1.05, 34.05, C.brickDark, M.Brick)
	-- door frame
	b("FrameL", 0.5, DOOR_H, 1.0, -(DOOR_W / 2 + 0.25), DOOR_H / 2, 0.3, C.steel, M.Metal)
	b("FrameR", 0.5, DOOR_H, 1.0, DOOR_W / 2 + 0.25, DOOR_H / 2, 0.3, C.steel, M.Metal)
	b("FrameTop", DOOR_W + 1, 0.5, 1.0, 0, DOOR_H + 0.25, 0.3, C.steel, M.Metal)
	-- canopy over the door
	b("Canopy", 17, 0.3, 4.6, 0, DOOR_H + 0.4, -2.0, C.roof, M.Metal, solid)
	for _, s in ipairs({ -1, 1 }) do
		kit:strut("CanopyStay", V3(s * 8, DOOR_H + 0.3, -4), V3(s * 8, DOOR_H + 3.2, -0.4), 0.16, C.steel, M.Metal)
	end

	-- name board above the door (faces the street = -Z = the part's Front face)
	local board = b("NameBoard", 12, 1.8, 0.25, 0, H - 1.1, -0.2, C.green, M.SmoothPlastic)
	g.nameLabel = ModelKit.signText(board, "GARAGE " .. string.upper(g.player.DisplayName), Enum.NormalId.Front, rgb(244, 236, 210), Enum.Font.GothamBlack)
	-- house number
	local plate = b("Number", 1.6, 1.6, 0.2, -11.2, 5.5, -0.15, C.black, M.SmoothPlastic)
	ModelKit.signText(plate, tostring(g.index), Enum.NormalId.Front, C.yellow, Enum.Font.GothamBlack)

	-- windows (glass in white frames) on the front pillars and both side walls
	local function window(x, y, z, face)
		local alongX = face == "front"
		local fsz = alongX and V3(3.4, 3.4, 0.2) or V3(0.2, 3.4, 3.4)
		local gsz = alongX and V3(3.0, 3.0, 0.25) or V3(0.25, 3.0, 3.0)
		b("WindowFrame", fsz.X, fsz.Y, fsz.Z, x, y, z, rgb(236, 236, 230), M.SmoothPlastic)
		local glass = b("WindowGlass", gsz.X, gsz.Y, gsz.Z, x, y, z, rgb(150, 190, 214), M.Glass)
		glass.Transparency = 0.35
		b("WindowBar", alongX and 3.0 or 0.3, 0.12, alongX and 0.3 or 3.0, x, y, z, rgb(236, 236, 230), M.SmoothPlastic)
	end
	for _, sx in ipairs({ -1, 1 }) do
		window(sx * 11.2, 6.2, -0.1, "front")
		for _, z in ipairs({ 9, 23 }) do
			window(sx * 14.9, 6.2, z, "side")
		end
	end

	-- skirting and a bit of life on the walls
	for _, s in ipairs({ -1, 1 }) do
		b("Skirt", 0.2, 1.2, 33.6, s * 13.9, 0.8, 16.8, C.brickDark, M.Brick)
	end
	b("Skirt", 29.6, 1.2, 0.2, 0, 0.8, 32.7, C.brickDark, M.Brick)
	local poster = b("Poster", 6, 3.6, 0.1, 0, 7.2, 32.7, rgb(236, 226, 196), M.SmoothPlastic)
	ModelKit.signText(poster, "WERKSTATT\nMOPED DAYS", Enum.NormalId.Front, rgb(150, 40, 36), Enum.Font.GothamBlack)

	-- ground markings
	b("StandPad", 7, 0.03, 12, 0, 0.215, STAND_Z, rgb(70, 72, 78), M.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		b("StandLine", 0.25, 0.03, 12, s * 3.4, 0.23, STAND_Z, C.yellow, M.SmoothPlastic)
	end
	b("ParcelPad", 7, 0.03, 13, 10.4, 0.215, 10.4, rgb(70, 72, 78), M.Concrete)
	for _, z in ipairs({ 3.9, 16.9 }) do
		b("ParcelLine", 7, 0.03, 0.25, 10.4, 0.23, z, C.yellow, M.SmoothPlastic)
	end
	for _, x in ipairs({ 6.9, 13.9 }) do
		b("ParcelLine", 0.25, 0.03, 13, x, 0.23, 10.4, C.yellow, M.SmoothPlastic)
	end
end

local function buildLights(g, kit)
	g.lightParts = {}
	local spots = { { -6, 9 }, { 6, 9 }, { -6, 25 }, { 6, 25 }, { 0, 16.4 } }
	for _, p in ipairs(spots) do
		local tube = kit:box("CeilingLight", V3(0.7, 0.25, 6), CF(p[1], H - 0.2, p[2]), rgb(150, 150, 150), M.SmoothPlastic, { shadow = false })
		kit:box("LightHousing", V3(1.0, 0.18, 6.3), CF(p[1], H - 0.05, p[2]), C.steel, M.Metal)
		local light = Instance.new("PointLight")
		light.Range = 26
		light.Brightness = 0
		light.Color = rgb(255, 244, 224)
		light.Shadows = false
		light:SetAttribute("OnBrightness", 1.5)
		light.Parent = tube
		table.insert(g.lightParts, tube)
	end
	-- lamp outside, over the apron
	local lamp = kit:box("OutsideLamp", V3(1.8, 0.3, 0.8), CF(0, DOOR_H + 0.1, -3.4), rgb(150, 150, 150), M.SmoothPlastic, { shadow = false })
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 120
	spot.Range = 40
	spot.Brightness = 0
	spot.Color = rgb(255, 240, 210)
	spot.Shadows = false
	spot:SetAttribute("OnBrightness", 1.6)
	spot.Parent = lamp
	table.insert(g.lightParts, lamp)
end

local function buildDoor(g, kit)
	local door = Instance.new("Model")
	door.Name = "Door"
	door.Parent = g.model
	local dkit = ModelKit.new(door, nil, g.cf, true)
	local slatH = DOOR_H / SLAT_COUNT
	for i = 0, SLAT_COUNT - 1 do
		local slat = dkit:box("Slat" .. i, V3(DOOR_W, slatH - 0.04, 0.3), CF(0, slatH * (i + 0.5), 0.4), i % 2 == 0 and C.door or rgb(184, 186, 190), M.Metal)
		slat:SetAttribute("OpenDY", (DOOR_H + 0.55 + i * 0.2) - slatH * (i + 0.5))
		slat:SetAttribute("OpenDZ", 1.5)
		slat:SetAttribute("Index", i)
	end
	-- the bottom bar with a handle
	g.bottomBar = dkit:box("BottomBar", V3(DOOR_W, 0.25, 0.4), CF(0, 0.12, 0.4), C.black, M.Metal)
	g.bottomBar:SetAttribute("OpenDY", DOOR_H + 0.35 - 0.12)
	g.bottomBar:SetAttribute("OpenDZ", 1.5)
	g.bottomBar:SetAttribute("Index", -1)
	-- collision (invisible)
	g.blocker = kit:box("DoorBlocker", V3(DOOR_W, DOOR_H, 0.8), CF(0, DOOR_H / 2, 0.4), C.black, M.SmoothPlastic, { collide = true })
	g.blocker.Transparency = 1
	g.blocker.CanQuery = false
	-- clicking the door itself toggles it too
	for _, slat in ipairs(door:GetChildren()) do
		if slat:IsA("BasePart") then
			slat.CanQuery = true
		end
	end
	door:SetAttribute("Open", false)
	CollectionService:AddTag(door, "PlayerGarageDoor")
	g.door = door
end

local function toggleDoorByOwner(g)
	if g.open then
		setDoor(g, false)
		g.autoLock = true -- stay shut until the owner has walked away and come back
	else
		setDoor(g, true)
		g.autoLock = false
	end
end

local function buildControls(g, kit)
	local function b(name, sx, sy, sz, x, y, z, color, material, opts)
		return kit:box(name, V3(sx, sy, sz), CF(x, y, z), color, material, opts)
	end
	-- keypad outside (right pillar, street side)
	local keypad = b("Keypad", 1.1, 1.8, 0.25, 10.5, 4.4, -0.12, C.black, M.Metal, { query = true })
	g.padLamp = b("KeypadLamp", 0.5, 0.18, 0.1, 10.5, 5.1, -0.28, rgb(200, 70, 60), M.Neon, { shadow = false })
	b("KeypadButtons", 0.8, 0.9, 0.08, 10.5, 4.2, -0.28, rgb(60, 62, 70), M.SmoothPlastic)
	billboard(keypad, "Door", V3(0, 2.2, 0), 18)
	clickable(keypad, 14, ownerOnly(g, function() toggleDoorByOwner(g) end))

	-- inside, right wall near the door: big door button and the light switch
	local doorBtn = b("DoorButton", 0.3, 1.4, 1.4, 13.85, 4.2, 4.5, rgb(190, 40, 36), M.SmoothPlastic, { query = true })
	billboard(doorBtn, "Door", V3(-1.5, 1.4, 0), 18)
	clickable(doorBtn, 16, ownerOnly(g, function() toggleDoorByOwner(g) end))

	local plate = b("SwitchPlate", 0.2, 1.4, 1.0, 13.9, 4.2, 7.6, rgb(230, 230, 224), M.SmoothPlastic, { query = true })
	g.switchLamp = b("SwitchLamp", 0.12, 0.2, 0.2, 13.78, 4.7, 7.6, rgb(200, 70, 60), M.Neon, { shadow = false })
	b("SwitchRocker", 0.18, 0.5, 0.5, 13.78, 4.0, 7.6, rgb(250, 250, 246), M.SmoothPlastic)
	billboard(plate, "Lights", V3(-1.5, 1.3, 0), 18)
	clickable(plate, 16, ownerOnly(g, function() setLights(g, not g.lightsOn) end))
end

local function buildFurniture(g, kit)
	local function b(name, sx, sy, sz, x, y, z, color, material, opts)
		return kit:box(name, V3(sx, sy, sz), CF(x, y, z), color, material, opts)
	end
	-- workbench on the left wall
	b("BenchTop", 3, 0.3, 11, -12.2, 3.5, 22, C.wood, M.Wood, { collide = true })
	for _, z in ipairs({ 17, 27 }) do
		for _, x in ipairs({ -13.4, -11 }) do
			b("BenchLeg", 0.3, 3.3, 0.3, x, 1.8, z, C.steel, M.Metal)
		end
	end
	b("BenchShelf", 2.6, 0.2, 10.4, -12.3, 1.2, 22, C.steel, M.Metal)
	b("Vice", 0.7, 0.7, 0.9, -11.3, 4.0, 18, rgb(60, 90, 140), M.Metal)
	b("Anvil", 0.8, 0.5, 1.6, -12.2, 3.95, 25, rgb(50, 52, 58), M.Metal)
	b("Pegboard", 0.2, 4.6, 11, -13.9, 6.8, 22, rgb(170, 140, 96), M.Wood)
	for i = 0, 6 do
		local z = 17.2 + i * 1.5
		b("Tool", 0.18, 1.4 + (i % 3) * 0.4, 0.22, -13.7, 6.6 + (i % 2) * 0.5, z, i % 2 == 0 and C.red or C.chrome, M.Metal)
	end
	-- red toolbox
	b("Toolbox", 2.4, 1.9, 1.8, -12.4, 1.15, 10.5, C.red, M.Metal, { collide = true })
	b("ToolboxTop", 2.5, 0.3, 1.9, -12.4, 2.2, 10.5, rgb(150, 30, 28), M.Metal)
	-- tyre stack and oil drums
	for i = 0, 3 do
		kit:cyl("Tyre", 0.9, 2.5, 2.5, CF(-12, 0.2 + 0.45 + i * 0.9, 30) * CFrame.Angles(0, 0, math.pi / 2), rgb(26, 26, 28), M.Rubber, { collide = i == 0 })
	end
	for i, x in ipairs({ -9.2, -6.8 }) do
		kit:cyl("Drum", 3, 2.1, 2.1, CF(x, 1.7, 31.4) * CFrame.Angles(0, 0, math.pi / 2), i == 1 and C.blue or C.green, M.Metal, { collide = true })
		kit:cyl("DrumBand", 0.2, 2.2, 2.2, CF(x, 2.4, 31.4) * CFrame.Angles(0, 0, math.pi / 2), rgb(30, 32, 38), M.Metal)
	end
	-- shelving on the right wall (parcels live in front, spare stock on the shelves)
	for lvl = 0, 2 do
		b("Shelf", 1.6, 0.2, 9, 13.1, 1.4 + lvl * 2.2, 27, C.steel, M.Metal)
	end
	for _, z in ipairs({ 22.6, 31.4 }) do
		b("ShelfUpright", 0.2, 6.6, 0.2, 13.1, 3.4, z, C.steel, M.Metal)
	end
	for lvl = 0, 2 do
		for i = 0, 2 do
			b("Stock", 1.2, 0.9, 1.6, 13.1, 1.95 + lvl * 2.2, 24 + i * 2.8, i % 2 == 0 and C.cardLight or C.card, M.Cardboard)
		end
	end
	-- signs
	local parcelSign = b("ParcelSign", 0.15, 1.2, 4.4, 13.85, 6.4, 10.4, C.black, M.SmoothPlastic)
	ModelKit.signText(parcelSign, "PARCELS", Enum.NormalId.Left, C.yellow, Enum.Font.GothamBlack)
	local standSign = b("StandSign", 4.4, 1.2, 0.15, 0, 8.8, 32.6, C.black, M.SmoothPlastic)
	ModelKit.signText(standSign, "BIKE STAND", Enum.NormalId.Front, C.yellow, Enum.Font.GothamBlack)
end

local function buildStand(g, kit)
	local function b(k, name, sx, sy, sz, x, y, z, color, material, opts)
		return k:box(name, V3(sx, sy, sz), CF(x, y, z), color, material, opts)
	end
	b(kit, "StandBase", 4.4, 0.3, 10.6, 0, 0.35, STAND_Z, C.steel, M.Metal, { collide = true })
	for _, sx in ipairs({ -2, 2 }) do
		for _, sz in ipairs({ -4.6, 4.6 }) do
			kit:cyl("StandPost", 5.6, 0.55, 0.55, CF(sx, 3.2, STAND_Z + sz) * CFrame.Angles(0, 0, math.pi / 2), C.chrome, M.Metal, { collide = true })
		end
	end
	b(kit, "PumpBox", 1.1, 1.8, 1.3, 3.0, 1.0, STAND_Z - 3.5, C.blue, M.Metal, { collide = true })

	-- the platform is its own model so it can be lifted as one piece
	local platform = Instance.new("Model")
	platform.Name = "Platform"
	platform.Parent = g.model
	local pk = ModelKit.new(platform, nil, g.cf, true)
	local deck = b(pk, "Deck", 3.4, 0.4, 9, 0, PLAT_LOW, STAND_Z, rgb(74, 78, 86), M.Metal, { collide = true, query = true })
	for _, sx in ipairs({ -1.4, 1.4 }) do
		b(pk, "DeckRail", 0.3, 0.25, 9, sx, PLAT_LOW + 0.3, STAND_Z, C.yellow, M.Metal, { collide = true })
	end
	b(pk, "FrontChock", 3.0, 0.45, 0.3, 0, PLAT_LOW + 0.4, STAND_Z - 4.2, C.red, M.Metal)
	b(pk, "RearChock", 3.0, 0.45, 0.3, 0, PLAT_LOW + 0.4, STAND_Z + 4.2, C.red, M.Metal)
	for _, sx in ipairs({ -1.9, 1.9 }) do
		for _, sz in ipairs({ -4.6, 4.6 }) do
			b(pk, "Carriage", 0.9, 0.7, 0.9, sx, PLAT_LOW, STAND_Z + sz, C.black, M.Metal)
		end
	end
	platform.PrimaryPart = deck
	g.platform = platform
	g.platformHome = platform:GetPivot()
	g.platformY = PLAT_LOW
	billboard(deck, "Bike stand", V3(0, 3.2, 0), 30)
	clickable(deck, 26, ownerOnly(g, function(player) PlayerGarage.standClicked(player) end))
end

local function build(g)
	local model = Instance.new("Model")
	model.Name = "Garage_" .. g.player.UserId
	model:SetAttribute("OwnerId", g.player.UserId)
	model:SetAttribute("Open", false)
	model:SetAttribute("Lights", false)
	g.model = model
	local kit = ModelKit.new(model, nil, g.cf, true)
	g.lightParts = {}
	buildShell(g, kit)
	buildDoor(g, kit)
	buildLights(g, kit)
	buildControls(g, kit)
	buildFurniture(g, kit)
	buildStand(g, kit)
	g.open, g.lightsOn = false, false
	g.crates = {}
	g.busyUntil = 0
	g.autoLock = false
	g.standRec = nil
	g.standBusy = false
	model.Parent = folder
	setLights(g, false)
end

----------------------------------------------------------------------------
-- Bike stand
----------------------------------------------------------------------------
local function bikeCFLowered(g, rec): CFrame
	local height = rec.vehicle.geometry.wheelRadius + 0.25 + 0.02 -- tyres rest on the deck
	return g.cf * CF(0, PLAT_TOP + height, STAND_Z)
end

-- Lifts / lowers the platform with whatever is on it.
local function moveStand(g, targetY: number, rec)
	g.standBusy = true
	local y0 = g.platformY
	local home = g.platformHome
	local bikeHome = rec and bikeCFLowered(g, rec)
	local t0 = os.clock()
	local dur = 1.3
	while true do
		local a = math.clamp((os.clock() - t0) / dur, 0, 1)
		local e = a * a * (3 - 2 * a)
		local y = y0 + (targetY - y0) * e
		local lift = CF(0, y - PLAT_LOW, 0)
		g.platform:PivotTo(lift * home)
		if rec and rec.model.Parent then
			rec.model:PivotTo(lift * bikeHome)
		end
		if a >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	g.platformY = targetY
	g.standBusy = false
end

local function standBikeOf(g)
	local rec = g.standRec
	if rec and rec.model.Parent and rec.model:GetAttribute("OnStand") then
		return rec
	end
	if rec then
		-- the bike was removed (respawned): drop the platform, close the window
		g.standRec = nil
		Remotes.event("OpenWorkshop"):FireClient(g.player)
		task.spawn(function()
			moveStand(g, PLAT_LOW, nil)
		end)
	end
	return nil
end

local function openWorkshop(player: Player, rec)
	Remotes.event("OpenWorkshop"):FireClient(player, rec and { bikeId = rec.vehicle.id } or nil)
end

function PlayerGarage.standClicked(player: Player)
	local g = garages[player]
	if not g or g.standBusy then
		return
	end
	local rec = standBikeOf(g)
	if rec then
		openWorkshop(player, rec)
		return
	end
	local standPos = (g.cf * CF(0, PLAT_TOP, STAND_Z)).Position
	rec = Vehicles.getBikeNear(player, standPos, 45)
	if not rec then
		notify(player, "Bring a bike to the stand first (phone > Garage > Bring bikes home).", "hint")
		return
	end
	holdOpen(g, 1)
	g.standRec = rec
	Vehicles.dock(player, rec, bikeCFLowered(g, rec))
	moveStand(g, PLAT_LOW + CFG.StandRaise, rec)
	if rec.model.Parent and g.standRec == rec then
		openWorkshop(player, rec)
	end
end

function PlayerGarage.releaseBike(player: Player)
	local g = garages[player]
	if not g or g.standBusy then
		return
	end
	local rec = standBikeOf(g)
	if not rec then
		openWorkshop(player, nil)
		return
	end
	openWorkshop(player, nil)
	moveStand(g, PLAT_LOW, rec)
	g.standRec = nil
	if rec.model.Parent then
		Vehicles.undock(rec)
		-- roll it off the stand to the floor in front of it
		local height = rec.vehicle.geometry.wheelRadius + 0.25 + 0.3
		rec.model:PivotTo(g.cf * CF(0, 0.2 + height, 5.2))
	end
end

-- The bike that is on the raised stand (nil if none / still moving).
function PlayerGarage.standBike(player: Player)
	local g = garages[player]
	if not g or g.standBusy then
		return nil
	end
	return standBikeOf(g)
end

----------------------------------------------------------------------------
-- Parcels: crates + delivery van
----------------------------------------------------------------------------
local function crateSlot(index: number): Vector3
	local col = (index - 1) % 2
	local row = ((index - 1) // 2) % 5
	local layer = (index - 1) // 10
	return V3(8.6 + col * 3.2, 0.2 + 0.85 + layer * 1.7, 5.6 + row * 2.4)
end

local function firstFreeCrateSlot(g): number
	local used = {}
	for _, c in pairs(g.crates) do
		used[c.slot] = true
	end
	local i = 1
	while used[i] do
		i += 1
	end
	return i
end

local function buildCrate(g, order, cf: CFrame)
	local part = PartsData.byId[order.partId]
	local bike = VehicleData.byId[order.bikeId]
	local crate = Instance.new("Model")
	crate.Name = "Crate_" .. order.id
	crate:SetAttribute("OrderId", order.id)
	local kit = ModelKit.new(crate, nil, cf, true)
	local box = kit:box("Box", V3(2.6, 1.7, 2.2), CF(), C.card, M.Cardboard, { collide = true, query = true })
	kit:box("TapeTop", V3(0.4, 0.04, 2.24), CF(0, 0.86, 0), C.cardLight, M.SmoothPlastic)
	kit:box("TapeSide", V3(0.4, 1.74, 0.04), CF(0, 0, -1.11), C.cardLight, M.SmoothPlastic)
	local label = kit:box("Label", V3(1.7, 0.9, 0.05), CF(0, 0.1, -1.13), rgb(244, 244, 238), M.SmoothPlastic)
	ModelKit.signText(label, ((part and part.name) or "Part") .. "\n" .. ((bike and bike.displayName) or ""), Enum.NormalId.Front, rgb(20, 20, 24), Enum.Font.GothamBold)
	crate.PrimaryPart = box
	crate.Parent = g.model
	clickable(box, 18, ownerOnly(g, function(player)
		Parts.unpack(player, order.id)
	end))
	billboard(box, "Unpack", V3(0, 2, 0), 16)
	return crate
end

-- Put an arrived order's crate straight onto the pad (used when joining).
function PlayerGarage.placeCrate(player: Player, order)
	local g = garages[player]
	if not g or g.crates[order.id] then
		return
	end
	local slot = firstFreeCrateSlot(g)
	local crate = buildCrate(g, order, g.cf * CF(crateSlot(slot)))
	g.crates[order.id] = { model = crate, slot = slot }
end

function PlayerGarage.removeCrate(player: Player, orderId)
	local g = garages[player]
	local c = g and g.crates[orderId]
	if c then
		c.model:Destroy()
		g.crates[orderId] = nil
	end
end

local function buildVan(): Model
	local van = Instance.new("Model")
	van.Name = "DeliveryVan"
	local kit = ModelKit.new(van, nil, CF(0, 0, 0), true)
	local yellow = rgb(250, 204, 20)
	local body = kit:box("Cargo", V3(4.6, 4.2, 6.4), CF(0, 2.9, 1.6), yellow, M.SmoothPlastic)
	kit:box("Cab", V3(4.4, 3.2, 3.0), CF(0, 2.4, -2.9), yellow, M.SmoothPlastic)
	kit:box("Hood", V3(4.4, 1.5, 1.6), CF(0, 1.55, -4.8), yellow, M.SmoothPlastic)
	kit:box("Windscreen", V3(4.0, 1.7, 0.1), CF(0, 3.0, -4.12) * CFrame.Angles(math.rad(-12), 0, 0), rgb(120, 160, 190), M.Glass, { transparency = 0.3 })
	for _, s in ipairs({ -1, 1 }) do
		kit:box("SideWindow", V3(0.08, 1.4, 2.0), CF(s * 2.22, 3.1, -2.9), rgb(120, 160, 190), M.Glass, { transparency = 0.3 })
		local panel = kit:box("SidePanel", V3(0.06, 1.8, 5.2), CF(s * 2.32, 3.2, 1.6), rgb(210, 40, 36), M.SmoothPlastic)
		ModelKit.signText(panel, "MOPED-POST", s > 0 and Enum.NormalId.Right or Enum.NormalId.Left, rgb(255, 240, 200), Enum.Font.GothamBlack)
	end
	kit:box("Bumper", V3(4.6, 0.5, 0.5), CF(0, 0.9, -5.7), C.black, M.Metal)
	kit:box("RearBumper", V3(4.6, 0.5, 0.4), CF(0, 0.9, 4.9), C.black, M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -3.6, 3.4 }) do
			kit:cyl("Wheel", 0.7, 1.9, 1.9, CF(s * 2.1, 1.0, z), rgb(24, 24, 26), M.Rubber)
			kit:cyl("Hub", 0.8, 0.9, 0.9, CF(s * 2.1, 1.0, z), C.chrome, M.Metal)
		end
		kit:cyl("Headlight", 0.2, 0.7, 0.7, CF(s * 1.5, 1.7, -5.66) * CFrame.Angles(0, math.pi / 2, 0), rgb(255, 246, 214), M.Neon)
	end
	van.PrimaryPart = body
	return van
end

PlayerGarage.buildVan = buildVan -- (also used by the offline previewer)

local function driveVan(van: Model, from: Vector3, to: Vector3, seconds: number)
	local dir = (to - from)
	local look = V3(dir.X, 0, dir.Z).Unit
	local t0 = os.clock()
	while true do
		local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
		local e = 1 - (1 - a) * (1 - a) -- ease out
		local pos = from + dir * e
		van:PivotTo(CFrame.lookAt(pos, pos + look))
		if a >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

local function tweenCrate(crate: Model, cf: CFrame, seconds: number)
	local t = TweenService:Create(crate.PrimaryPart, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { CFrame = cf })
	-- the other crate parts are separate anchored parts: move them in lock-step
	local parts = {}
	for _, d in ipairs(crate:GetChildren()) do
		if d:IsA("BasePart") and d ~= crate.PrimaryPart then
			table.insert(parts, { d, crate.PrimaryPart.CFrame:ToObjectSpace(d.CFrame) })
		end
	end
	local conn = RunService.Heartbeat:Connect(function()
		for _, p in ipairs(parts) do
			p[1].CFrame = crate.PrimaryPart.CFrame * p[2]
		end
	end)
	t:Play()
	t.Completed:Wait()
	conn:Disconnect()
	for _, p in ipairs(parts) do
		p[1].CFrame = crate.PrimaryPart.CFrame * p[2]
	end
end

-- The van drives up, drops the crate on the apron, the crate is carried in.
function PlayerGarage.deliver(player: Player, order)
	local g = garages[player]
	if not g or g.crates[order.id] or g.delivering then
		return false
	end
	g.delivering = true
	holdOpen(g, 14)
	local van = buildVan()
	van.Parent = g.model
	local vanX = 9
	local from = (g.cf * CF(vanX, 0, -90)).Position
	local stop = (g.cf * CF(vanX, 0, -16)).Position
	van:PivotTo(CFrame.lookAt(from, from + V3(0, 0, 1)))
	driveVan(van, from, stop, 3.4)

	-- drop the crate behind the van
	local slot = firstFreeCrateSlot(g)
	local dropCF = g.cf * CF(vanX, 0.95, -24.5)
	local crate = buildCrate(g, order, dropCF)
	g.crates[order.id] = { model = crate, slot = slot }
	Parts.markArrived(player, order)
	task.wait(0.8)
	tweenCrate(crate, g.cf * CF(5, 1.1, -24.5), 0.8) -- clear of the van
	tweenCrate(crate, g.cf * CF(5, 1.1, crateSlot(slot).Z), 2.0) -- through the open door

	tweenCrate(crate, g.cf * CF(crateSlot(slot)), 0.8)
	notify(player, "Your parcel is in the garage: click the crate to unpack it.", "good")

	-- van leaves (back the way it came: reverse out, then fade)
	driveVan(van, stop, from, 3.0)
	van:Destroy()
	g.delivering = false
	g.busyUntil = os.clock() + 2
	return true
end

----------------------------------------------------------------------------
-- Allocation and the auto door loop
----------------------------------------------------------------------------
function PlayerGarage.assign(player: Player)
	if garages[player] then
		return garages[player]
	end
	local index = 1
	while slotOwner[index] do
		index += 1
	end
	slotOwner[index] = player
	local g = { player = player, index = index, cf = slotCF(index) }
	garages[player] = g
	build(g)
	return g
end

function PlayerGarage.release(player: Player)
	local g = garages[player]
	if not g then
		return
	end
	garages[player] = nil
	slotOwner[g.index] = nil
	g.model:Destroy()
end

function PlayerGarage.get(player: Player)
	return garages[player]
end

-- A spot in front of the door facing the street, for teleporting / parking.
function PlayerGarage.forecourt(player: Player): CFrame?
	local g = garages[player]
	if not g then
		return nil
	end
	return g.cf * CF(0, 0, -2) -- at the door, looking along -Z (out to the street); bikes line up ahead of it
end

function PlayerGarage.teleportHome(player: Player): boolean
	local g = garages[player]
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (g and hrp) then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Sit = false
	end
	char:PivotTo(g.cf * CF(0, 4, -8) * CFrame.Angles(0, math.pi, 0))
	holdOpen(g, 6)
	return true
end

local function autoDoors()
	for player, g in pairs(garages) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and g.model.Parent then
			local doorPos = (g.cf * CF(0, 4, -3)).Position
			local d = (hrp.Position - doorPos).Magnitude
			local busy = os.clock() < g.busyUntil or g.delivering
			if d > CFG.CloseDistance then
				g.autoLock = false
				if g.open and not busy then
					setDoor(g, false)
				end
			elseif CFG.AutoOpen and d < CFG.OpenDistance and not g.open and not g.autoLock then
				setDoor(g, true)
			end
		end
	end
end

function PlayerGarage.init(dataService, economyService, vehicleService, partsService)
	Data, Economy, Vehicles, Parts = dataService, economyService, vehicleService, partsService
	folder = Workspace:FindFirstChild("Garagenreihe") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Garagenreihe"
		folder.Parent = Workspace
	end

	Remotes.event("GarageAction").OnServerEvent:Connect(function(player, action)
		if action == "Release" then
			PlayerGarage.releaseBike(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerGarage.release(player)
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(autoDoors)
			if not ok then
				warn("[PlayerGarage] door loop: " .. tostring(err))
			end
		end
	end)
end

return PlayerGarage
