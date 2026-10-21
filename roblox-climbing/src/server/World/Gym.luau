--!strict
-- Gym: the Ascent climbing gym everyone spawns in (design doc 1b and 5.1). A modern,
-- bright gym: glass front, white walls with charcoal and white oak, exposed steel trusses
-- and soft linear pendant lights (no neon glare).
--
--   * Lobby: spawn on the Ascent logo, reception desk, freestanding leaderboard screen.
--   * Rope walls (back): the tutorial wall plus two tall walls with two routes each. Every
--     rope route has an auto-belay you must clip into ("Clip in" at its base).
--   * Bouldering (left): four monoliths, two colour-coded problems each, wall-to-wall
--     padded flooring.
--   * Kilter room (back right): a 40-degree LED board behind glass, with a kiosk.
--   * Pro shop (right): gear shelves and the counter ("Browse gear", ShopService).
--   * Lockers (front left): change your bag and its colours ("Customise bag").
--   * Lounge and cafe (front right), a training corner, plants and wayfinding signs.
--
-- Built once at server start if Workspace.Gym is missing (or saved by an older version),
-- or in edit mode from the command bar:
--     require(game.ServerScriptService.Server.World.Gym).Rebuild()

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Gear = require(Shared.Gear)
local Tags = require(Shared.Tags)

local BuildUtil = require(script.Parent.BuildUtil)
local Face = require(script.Parent.Face)
local PanelWall = require(script.Parent.PanelWall)
local Npc = require(script.Parent.Npc)
local Props = require(script.Parent.Props)
local RouteGenerator = require(script.Parent.RouteGenerator)
local RouteKit = require(script.Parent.RouteKit)

local part = BuildUtil.part
local frameAt = BuildUtil.frameAt

-- Building footprint (floor top at y = 0; the tutorial wall sits at z = -24 facing +Z).
local X0, X1, Z0, Z1, HEIGHT = -64, 64, -40, 44, 36
local DOOR_HALF, DOOR_HEIGHT = 7, 14
local GLASS_TOP = 22 -- the front is glass up to here
local SPAWN = Vector3.new(0, 0, 30)
local PENDANT_Y = 27

local WHITE = Color3.new(1, 1, 1)
local ORANGE = Color3.fromRGB(255, 122, 48)

local Gym = {}

local function box(name: string, size: Vector3, position: Vector3, surface: string, parent: Instance, collide: boolean?, color: Color3?): BasePart
	return part({ name = name, size = size, cframe = CFrame.new(position), surface = surface, color = color, collide = collide ~= false, query = collide ~= false, parent = parent })
end

-- A box standing on the floor: `position` is the centre of its bottom face.
local function standing(name: string, size: Vector3, position: Vector3, surface: string, parent: Instance, collide: boolean?, color: Color3?): BasePart
	return box(name, size, position + Vector3.yAxis * (size.Y / 2), surface, parent, collide, color)
end

local function label(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?, glow: boolean?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	-- A canvas sized to the face (not the default 800x600 stretched over it), so text
	-- keeps its proportions on long, thin signs.
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = if glow then 0 else 0.6
	gui.Brightness = 1
	gui.Parent = parent
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.fromScale(1, 1)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = textLabel
	textLabel.Font = font or Enum.Font.Michroma
	textLabel.TextScaled = true
	textLabel.RichText = true
	textLabel.TextColor3 = color
	textLabel.Text = text
	textLabel.Parent = gui
	return gui
end

-- A hanging wayfinding sign: charcoal panel on two cables, white text, orange underline.
local function hangingSign(parent: Instance, text: string, center: Vector3, facing: Vector3, width: number)
	local cframe = frameAt(center, facing, Vector3.yAxis)
	local sign = part({ name = "Sign", size = Vector3.new(width, 2.4, 0.3), cframe = cframe, surface = "Charcoal", parent = parent })
	label(sign, Enum.NormalId.Front, text, WHITE, Enum.Font.Sarpanch, false).Name = "Text"
	label(sign, Enum.NormalId.Back, text, WHITE, Enum.Font.Sarpanch, false).Name = "TextBack"
	part({ name = "Underline", size = Vector3.new(width, 0.16, 0.32), cframe = cframe * CFrame.new(0, -1.28, 0), surface = "Accent", shadow = false, parent = parent })
	for _, x in { -width / 2 + 0.6, width / 2 - 0.6 } do
		local top = (cframe * CFrame.new(x, 1.2, 0)).Position
		BuildUtil.pipe("Cable", top, Vector3.new(top.X, HEIGHT, top.Z), 0.05, "BlackSteel", parent)
	end
end

-- A Creator Store prop (see Props), with `fallback` building the stand-in.
local function prop(parent: Instance, key: string, position: Vector3, facing: Vector3, size: Vector3, fallback: (Model) -> ()): Model
	return Props.slot(parent, key, Props.at(position, facing), size, fallback)
end

-- A potted plant (three kinds, in turn). Stand-in: a concrete planter with a rounded shrub.
local PLANTS = { "plant_palm", "plant_floor", "plant_fig" }
local plantCount = 0
local function plant(parent: Instance, position: Vector3, scale: number?)
	local s = scale or 1
	plantCount += 1
	prop(parent, PLANTS[(plantCount - 1) % #PLANTS + 1], position, Vector3.new(0, 0, 1), Vector3.new(3.6, 7, 3.6) * s, function(model)
		part({
			name = "Planter",
			size = Vector3.new(2.4 * s, 2.2 * s, 2.2 * s),
			cframe = CFrame.new(position + Vector3.yAxis * (1.2 * s)) * BuildUtil.AXIS_Y,
			surface = "Planter",
			shape = Enum.PartType.Cylinder,
			collide = true,
			query = true,
			parent = model,
		})
		for i, offset in { Vector3.new(0, 3.6, 0), Vector3.new(0.6, 4.6, 0.3), Vector3.new(-0.5, 5.2, -0.3), Vector3.new(0.1, 6.0, 0.1) } do
			part({
				name = "Leaves",
				size = Vector3.new(3.2 - i * 0.35, 2.6 - i * 0.2, 3.0 - i * 0.3) * s,
				cframe = CFrame.new(position + offset * s) * CFrame.Angles(0, i * 1.3, 0),
				surface = "Leaves",
				color = Color3.fromRGB(52 + i * 6, 104 + i * 8, 58),
				ellipsoid = true,
				parent = model,
			})
		end
	end)
end

---------------------------------------------------------------------------------------
-- Shell

local function pendant(parent: Instance, center: Vector3)
	local housing = box("Pendant", Vector3.new(14, 0.35, 0.9), center, "BlackSteel", parent, false)
	housing.CastShadow = false
	local diffuser = box("Diffuser", Vector3.new(13.6, 0.06, 0.7), center - Vector3.yAxis * 0.2, "Diffuser", parent, false)
	diffuser.CastShadow = false
	for _, x in { -6, 6 } do
		BuildUtil.pipe("Cable", center + Vector3.new(x, 0.17, 0), Vector3.new(center.X + x, HEIGHT, center.Z), 0.05, "BlackSteel", parent)
	end
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 30
	light.Angle = 120
	light.Brightness = 0.45
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 247, 236)
	light.Parent = diffuser
end

local function buildShell(model: Model)
	local shell = Instance.new("Model")
	shell.Name = "Shell"
	shell.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- seen from the crags
	local midX, midZ = (X0 + X1) / 2, (Z0 + Z1) / 2
	local w, d = X1 - X0, Z1 - Z0

	box("Floor", Vector3.new(w, 1, d), Vector3.new(midX, -0.5, midZ), "GymFloor", shell)
	box("Ceiling", Vector3.new(w + 2, 1, d + 2), Vector3.new(midX, HEIGHT + 0.5, midZ), "Charcoal", shell)
	box("WallBack", Vector3.new(w + 2, HEIGHT, 1), Vector3.new(midX, HEIGHT / 2, Z0 - 0.5), "SoftWhite", shell)
	box("WallLeft", Vector3.new(1, HEIGHT, d), Vector3.new(X0 - 0.5, HEIGHT / 2, midZ), "SoftWhite", shell)
	box("WallRight", Vector3.new(1, HEIGHT, d), Vector3.new(X1 + 0.5, HEIGHT / 2, midZ), "SoftWhite", shell)

	-- Front: a glass curtain wall either side of the entrance, solid above it.
	local sideWidth = w / 2 - DOOR_HALF
	for _, sign in { -1, 1 } do
		local cx = sign * (DOOR_HALF + sideWidth / 2)
		box("FrontUpper", Vector3.new(sideWidth + 1, HEIGHT - GLASS_TOP, 1), Vector3.new(cx + sign * 0.5, (HEIGHT + GLASS_TOP) / 2, Z1 + 0.5), "SoftWhite", shell)
		-- Plinth from the door frame to the corner (not under the frame).
		box("Plinth", Vector3.new(sideWidth - 0.6 + 1, 0.6, 1.2), Vector3.new(cx + sign * 0.8, 0.3, Z1 + 0.5), "Charcoal", shell)
		local glass = box("Glass", Vector3.new(sideWidth, GLASS_TOP - 0.6, 0.2), Vector3.new(cx, 0.6 + (GLASS_TOP - 0.6) / 2, Z1 + 0.5), "ClearGlass", shell)
		glass.CastShadow = false
		local x = DOOR_HALF + 8
		while x < w / 2 - 0.5 do
			standing("Mullion", Vector3.new(0.4, GLASS_TOP - 0.6, 1.2), Vector3.new(sign * x, 0.6, Z1 + 0.5), "BlackSteel", shell)
			x += 8
		end
		box("Transom", Vector3.new(sideWidth, 0.4, 1.2), Vector3.new(cx, GLASS_TOP - 0.2, Z1 + 0.5), "BlackSteel", shell)
	end
	box("Lintel", Vector3.new(DOOR_HALF * 2, HEIGHT - DOOR_HEIGHT - 0.6, 1), Vector3.new(0, (HEIGHT + DOOR_HEIGHT + 0.6) / 2, Z1 + 0.5), "SoftWhite", shell)
	-- Entrance: black steel frame, a canopy and a downlight.
	for _, x in { -DOOR_HALF - 0.3, DOOR_HALF + 0.3 } do
		standing("DoorFrame", Vector3.new(0.6, DOOR_HEIGHT, 1.6), Vector3.new(x, 0, Z1 + 0.5), "BlackSteel", shell)
	end
	box("DoorHeader", Vector3.new(DOOR_HALF * 2 + 1.2, 0.6, 1.6), Vector3.new(0, DOOR_HEIGHT + 0.3, Z1 + 0.5), "BlackSteel", shell)
	local canopy = box("Canopy", Vector3.new(22, 0.6, 7), Vector3.new(0, DOOR_HEIGHT + 1.3, Z1 + 4.5), "Charcoal", shell)
	local canopyLight = Instance.new("SurfaceLight")
	canopyLight.Face = Enum.NormalId.Bottom
	canopyLight.Range = 14
	canopyLight.Brightness = 0.6
	canopyLight.Shadows = false
	canopyLight.Parent = canopy
	box("Doormat", Vector3.new(12, 0.04, 6), Vector3.new(0, 0.02, Z1 - 3), "RubberTile", shell, false)

	-- Skirting and an orange accent line along the inside walls.
	box("SkirtBack", Vector3.new(w, 0.8, 0.1), Vector3.new(midX, 0.4, Z0 + 0.05), "Charcoal", shell, false)
	box("SkirtLeft", Vector3.new(0.1, 0.8, d), Vector3.new(X0 + 0.05, 0.4, midZ), "Charcoal", shell, false)
	box("SkirtRight", Vector3.new(0.1, 0.8, d), Vector3.new(X1 - 0.05, 0.4, midZ), "Charcoal", shell, false)
	box("AccentLeft", Vector3.new(0.06, 0.3, d), Vector3.new(X0 + 0.03, 24, midZ), "Accent", shell, false).CastShadow = false
	box("AccentRight", Vector3.new(0.06, 0.3, d), Vector3.new(X1 - 0.03, 24, midZ), "Accent", shell, false).CastShadow = false

	-- Outside: charcoal skin, white-oak slats across the top of the front, the logo.
	local skin = 0.6
	box("CladBack", Vector3.new(w + 2 + skin * 2, HEIGHT, skin), Vector3.new(midX, HEIGHT / 2, Z0 - 1 - skin / 2), "Charcoal", shell)
	box("CladLeft", Vector3.new(skin, HEIGHT, d + 2), Vector3.new(X0 - 1 - skin / 2, HEIGHT / 2, midZ), "Charcoal", shell)
	box("CladRight", Vector3.new(skin, HEIGHT, d + 2), Vector3.new(X1 + 1 + skin / 2, HEIGHT / 2, midZ), "Charcoal", shell)
	box("CladFront", Vector3.new(w + 2 + skin * 2, HEIGHT - GLASS_TOP, skin), Vector3.new(midX, (HEIGHT + GLASS_TOP) / 2, Z1 + 1 + skin / 2), "Charcoal", shell)
	local slatZ = Z1 + 1 + skin + 0.15
	local x = X0 + 1
	while x <= X1 - 1 do
		if math.abs(x) > 19 then
			box("Slat", Vector3.new(0.5, HEIGHT - GLASS_TOP - 2, 0.3), Vector3.new(x, (HEIGHT + GLASS_TOP) / 2, slatZ), "WhiteOak", shell, false)
		end
		x += 1.6
	end
	local logo = box("Logo", Vector3.new(34, 8, 0.3), Vector3.new(0, (HEIGHT + GLASS_TOP) / 2, slatZ), "Charcoal", shell, false)
	label(logo, Enum.NormalId.Back, `{string.upper(Config.GameName)}`, WHITE, Enum.Font.Michroma, true).Name = "LogoText"
	box("LogoAccent", Vector3.new(26, 0.4, 0.32), Vector3.new(0, (HEIGHT + GLASS_TOP) / 2 - 3.6, slatZ + 0.01), "Accent", shell, false)

	-- Exposed steel trusses under the ceiling.
	for _, z in { -32, -16, 0, 16, 32 } do
		box("Truss", Vector3.new(w, 1.4, 0.5), Vector3.new(midX, HEIGHT - 0.7, z), "BlackSteel", shell, false).CastShadow = false
	end
	-- Soft linear pendants (no neon: neon blooms into a glare).
	for _, lz in { -12, 4, 20, 34 } do
		for _, lx in { -44, -22, 0, 22, 44 } do
			pendant(shell, Vector3.new(lx, PENDANT_Y, lz))
		end
	end
	-- Wall washers over the rope walls.
	for _, lx in { -25, 0, 25 } do
		local washer = box("Washer", Vector3.new(3, 0.6, 1), Vector3.new(lx, HEIGHT - 0.3, -14), "BlackSteel", shell, false)
		washer.CastShadow = false
		washer.CFrame = CFrame.lookAt(washer.Position, Vector3.new(lx, 12, -36))
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 70
		spot.Range = 40
		spot.Brightness = 0.6
		spot.Shadows = false
		spot.Color = Color3.fromRGB(255, 248, 238)
		spot.Parent = washer
	end
	shell.Parent = model
end

---------------------------------------------------------------------------------------
-- Lobby: spawn, reception, leaderboard

local function buildSpawn(model: Model)
	local logo = Instance.new("Model")
	logo.Name = "SpawnLogo"
	local ring = part({
		name = "Ring",
		size = Vector3.new(0.03, 10.6, 10.6),
		cframe = CFrame.new(SPAWN + Vector3.yAxis * 0.015) * BuildUtil.AXIS_Y,
		surface = "Accent",
		shape = Enum.PartType.Cylinder,
		shadow = false,
		parent = logo,
	})
	ring.CanQuery = false
	local disc = part({
		name = "Disc",
		size = Vector3.new(0.04, 10, 10),
		cframe = CFrame.new(SPAWN + Vector3.yAxis * 0.02) * BuildUtil.AXIS_Y,
		surface = "Charcoal",
		shape = Enum.PartType.Cylinder,
		shadow = false,
		parent = logo,
	})
	disc.CanQuery = false
	local face = part({ name = "LogoFace", size = Vector3.new(7, 0.02, 7), cframe = CFrame.new(SPAWN + Vector3.yAxis * 0.05) * CFrame.Angles(0, math.pi, 0), surface = "Charcoal", shadow = false, parent = logo })
	face.Transparency = 1
	label(face, Enum.NormalId.Top, `▲\n{string.upper(Config.GameName)}`, WHITE, Enum.Font.Michroma, false)
	logo.Parent = model

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "GymSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = frameAt(SPAWN + Vector3.yAxis * 0.5, Vector3.new(0, 0, -1), Vector3.yAxis)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = model
	for _, d in spawn:GetChildren() do
		if d:IsA("Decal") then
			d:Destroy()
		end
	end
end

-- Gym staff and climbers, some in real climbing gear from the catalog.
local GEAR = {
	climber = { hat = 92040460524357, waist = 12765457067 }, -- Roc helmet, orange chalk bag
	shop = { hat = 133255040917706, back = 119212407294452, waist = 12765420893 }, -- Aurora, Bravo pack, blue chalk bag
	desk = { waist = 12765476571 },
}
local function npc(name: string, position: Vector3, facing: Vector3, parent: Instance, shirt: Color3, gear: Npc.Gear?)
	Npc.spawn(name, position, facing, parent, shirt, gear)
end

-- A counter: charcoal body, white-oak top, a thin orange line at the toe.
local function counter(parent: Instance, name: string, center: Vector3, length: number, facing: Vector3): CFrame
	local cframe = frameAt(center + Vector3.yAxis * 1.7, facing, Vector3.yAxis)
	part({ name = name, size = Vector3.new(length, 3.4, 2.4), cframe = cframe, surface = "Charcoal", collide = true, query = true, parent = parent })
	part({ name = "Top", size = Vector3.new(length + 0.4, 0.2, 2.8), cframe = cframe * CFrame.new(0, 1.8, 0), surface = "WhiteOak", collide = true, query = true, parent = parent })
	part({ name = "Toe", size = Vector3.new(length, 0.12, 0.02), cframe = cframe * CFrame.new(0, -1.35, -1.21), surface = "Accent", shadow = false, parent = parent })
	return cframe
end

local function buildReception(model: Model)
	local desk = Instance.new("Model")
	desk.Name = "Reception"
	local center = Vector3.new(22, 0, 34)
	local cframe = counter(desk, "Desk", center, 11, Vector3.new(0, 0, -1))
	part({ name = "MonitorStand", size = Vector3.new(0.3, 0.8, 0.3), cframe = cframe * CFrame.new(-2, 2.3, 0.5), surface = "BlackSteel", parent = desk })
	local screen = part({ name = "Monitor", size = Vector3.new(2.6, 1.6, 0.12), cframe = cframe * CFrame.new(-2, 3.4, 0.4), surface = "Charcoal", parent = desk })
	label(screen, Enum.NormalId.Front, `<font color="#FF7A30">WELCOME</font>\nto {Config.GameName}`, WHITE, Enum.Font.Sarpanch, true)
	npc("Front desk", center + Vector3.new(0, 0, 3), Vector3.new(0, 0, -1), desk, ORANGE, GEAR.desk)
	RouteKit.addChalkBucket(desk, center + Vector3.new(-8, 0, -1))
	plant(desk, center + Vector3.new(8, 0, 2))
	desk.Parent = model
end

local function buildLeaderboardWall(model: Model)
	local wall = Instance.new("Model")
	wall.Name = "LeaderboardWall"
	local width, height, bottom = 30, 16, 3
	local center = Vector3.new(-24, bottom + height / 2, 22)
	local cframe = frameAt(center, Vector3.new(0, 0, 1), Vector3.yAxis)
	local board = part({ name = "Board", size = Vector3.new(width, height, 0.4), cframe = cframe, surface = "Charcoal", collide = true, query = true, parent = wall })
	part({ name = "Accent", size = Vector3.new(width, 0.25, 0.42), cframe = cframe * CFrame.new(0, -height / 2 + 0.125, 0), surface = "Accent", shadow = false, parent = wall })
	for _, x in { -width / 2 - 0.3, width / 2 + 0.3 } do
		local foot = (cframe * CFrame.new(x, 0, 0)).Position
		standing("Post", Vector3.new(0.6, bottom + height, 0.6), Vector3.new(foot.X, 0, foot.Z), "BlackSteel", wall)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "GymLeaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 12)
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Font = Enum.Font.Michroma
	title.TextSize = 52
	title.TextColor3 = WHITE
	title.RichText = true
	title.Text = `{string.upper(Config.GameName)} <font color="#FF7A30">LEADERBOARD</font>`
	title.Parent = gui
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(20, 84)
	grid.Size = UDim2.new(1, -40, 1, -100)
	grid.Parent = gui
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.25, -10, 1 / 3, -10)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	wall.Parent = model
end

---------------------------------------------------------------------------------------
-- Shared bits for walls

-- Covers the open sides of an overhanging single-segment face: a wedge on each end from
-- the vertical line under the face's base out to the overhang, plus a strip behind it.
local function overhangCheeks(face: Face.Face, width: number, parent: Instance)
	local segment = face.segments[1]
	if segment.angle <= 0.5 then
		return
	end
	local angle = math.rad(segment.angle)
	local h = segment.length * math.cos(angle)
	local d = segment.length * math.sin(angle)
	local flat = face.flatNormal
	for _, x in { -width / 2 - 0.2, width / 2 + 0.2 } do
		local base = face.origin + face.right * x
		-- Wedge: local +Z towards the wall, local +Y down, so its right angle is at the top
		-- against the wall and its slope follows the panel.
		local vY = -Vector3.yAxis
		local vZ = -flat
		local vX = vY:Cross(vZ)
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Cheek"
		wedge.Size = Vector3.new(0.4, h, d)
		wedge.CFrame = CFrame.fromMatrix(base + Vector3.yAxis * (h / 2) + flat * (d / 2), vX, vY)
		wedge.Anchored = true
		wedge.CanCollide = true
		wedge.CanTouch = false
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.Color = Color3.fromRGB(232, 233, 235)
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		wedge.Parent = parent
		part({
			name = "CheekStrip",
			size = Vector3.new(0.4, h, 1.2),
			cframe = frameAt(base + Vector3.yAxis * (h / 2) - flat * 0.6, flat, Vector3.yAxis),
			surface = "SoftWhite",
			collide = true,
			parent = parent,
		})
	end
end

---------------------------------------------------------------------------------------
-- Rope walls (back of the gym)

type RopeRoute = { id: string, name: string, grade: string, order: number, lineX: number, difficulty: number, color: Color3 }
type RopeWallDef = { x: number, width: number, segments: { Face.SegmentSpec }, plate: Color3, routes: { RopeRoute } }

local ROPE_WALLS: { RopeWallDef } = {
	{
		x = -25,
		width = 18,
		segments = { { length = 20, angle = 0 }, { length = 12, angle = 14 } },
		plate = Color3.fromRGB(214, 220, 228),
		routes = {
			{ id = "LimeLine", name = "Lime Line", grade = "5b", order = 17, lineX = -4.5, difficulty = 0.15, color = Color3.fromRGB(150, 220, 60) },
			{ id = "OrangeArete", name = "Orange Arete", grade = "5c", order = 18, lineX = 4.5, difficulty = 0.3, color = Color3.fromRGB(255, 140, 40) },
		},
	},
	{
		x = 25,
		width = 18,
		segments = { { length = 14, angle = 6 }, { length = 10, angle = 22 }, { length = 7, angle = 0 } },
		plate = Color3.fromRGB(58, 64, 76),
		routes = {
			{ id = "TealTower", name = "Teal Tower", grade = "6a", order = 19, lineX = -4.5, difficulty = 0.45, color = Color3.fromRGB(40, 200, 200) },
			{ id = "CrimsonRoof", name = "Crimson Roof", grade = "6b", order = 20, lineX = 4.5, difficulty = 0.6, color = Color3.fromRGB(220, 50, 70) },
		},
	},
}

local function buildRopeWalls(model: Model)
	local area = Instance.new("Model")
	area.Name = "RopeWalls"
	for index, def in ROPE_WALLS do
		local wall = Instance.new("Model")
		wall.Name = `RopeWall{index}`
		local origin = Vector3.new(def.x, 0, -34)
		local face = Face.new(origin, Vector3.new(0, 0, 1), def.segments)
		local allHolds = {}
		local generated = {}
		for r, route in def.routes do
			local holds = RouteGenerator.generate({ seed = 7000 + index * 100 + r, height = face.height, lineX = route.lineX, wander = 0.9, difficulty = route.difficulty })
			generated[r] = holds
			for _, h in holds do
				table.insert(allHolds, h)
			end
		end
		PanelWall.build(face, wall, { width = def.width, holds = allHolds, plateColor = def.plate, tnutSpacing = 1.1 })
		-- Side fins from the back wall to the furthest-out point of the face.
		local reach = 0
		for _, segment in face.segments do
			reach = math.max(reach, (Face.point(face, 0, segment.startS + segment.length, 0) - origin):Dot(face.flatNormal))
		end
		local finDepth = (origin.Z - Z0) + reach + 0.6
		local rise = Face.rise(face)
		for _, side in { -1, 1 } do
			standing("Fin", Vector3.new(0.6, rise + 0.6, finDepth), Vector3.new(def.x + side * (def.width / 2 + 0.3), 0, Z0 + finDepth / 2), "SoftWhite", wall)
		end
		box("Cap", Vector3.new(def.width + 1.2, 0.4, finDepth), Vector3.new(def.x, rise + 0.8, Z0 + finDepth / 2), "SoftWhite", wall)
		standing("Tiles", Vector3.new(def.width, 0.06, 12), Vector3.new(def.x, 0, origin.Z + 7 + reach), "RubberTile", wall, false)
		for r, route in def.routes do
			RouteKit.buildRoute({
				id = route.id,
				name = route.name,
				grade = route.grade,
				order = route.order,
				face = face,
				lineX = route.lineX,
				holds = generated[r],
				style = "plastic",
				color = route.color,
				baseY = 0,
				indoor = true,
				autoBelay = true,
				leaderboard = true,
				chalk = r == 1,
				signSide = if route.lineX < 0 then -1 else 1,
			})
		end
		wall.Parent = area
	end
	hangingSign(area, "ROPES  ·  CLIP IN TO CLIMB", Vector3.new(0, 30, -8), Vector3.new(0, 0, 1), 22)
	area.Parent = model
end

---------------------------------------------------------------------------------------
-- Bouldering (left side)

type Problem = { id: string, name: string, grade: string, color: Color3, difficulty: number }
local PROBLEMS: { Problem } = {
	{ id = "BlueMonday", name = "Blue Monday", grade = "V1", color = Color3.fromRGB(60, 130, 240), difficulty = 0.15 },
	{ id = "GreenMachine", name = "Green Machine", grade = "V0", color = Color3.fromRGB(70, 200, 90), difficulty = 0.0 },
	{ id = "PurpleHaze", name = "Purple Haze", grade = "V3", color = Color3.fromRGB(150, 80, 220), difficulty = 0.45 },
	{ id = "PinkPanther", name = "Pink Panther", grade = "V2", color = Color3.fromRGB(240, 90, 170), difficulty = 0.3 },
	{ id = "OrangeCrush", name = "Orange Crush", grade = "V4", color = Color3.fromRGB(245, 150, 40), difficulty = 0.6 },
	{ id = "CyanLadder", name = "Cyan Ladder", grade = "V1", color = Color3.fromRGB(40, 200, 220), difficulty = 0.2 },
	{ id = "YellowBrick", name = "Yellow Brick", grade = "V2", color = Color3.fromRGB(250, 215, 50), difficulty = 0.35 },
	{ id = "RedLine", name = "Red Line", grade = "V5", color = Color3.fromRGB(230, 60, 60), difficulty = 0.75 },
}

local MAT_TOP = 1
local BOULDER_OVERHANG = 12 -- degrees, the east faces

local function buildBoulders(model: Model)
	local hall = Instance.new("Model")
	hall.Name = "BoulderingHall"
	-- Wall-to-wall padded flooring (the monoliths stand on the concrete, through the pads).
	local mat = box("Padding", Vector3.new(24, MAT_TOP, 56), Vector3.new(-52, MAT_TOP / 2, -11), "PaddedMat", hall)
	CollectionService:AddTag(mat, Tags.CrashMat)
	for z = -36, 14, 8 do
		box("MatSeam", Vector3.new(24, 0.02, 0.15), Vector3.new(-52, MAT_TOP + 0.01, z + 3), "MatSeamCover", hall, false).CastShadow = false
	end
	box("MatEdge", Vector3.new(0.4, MAT_TOP + 0.02, 56), Vector3.new(-39.8, MAT_TOP / 2 + 0.01, -11), "Accent", hall)

	local centers = { -31, -17, -3, 11 }
	local height, width, depth = 14, 8, 8
	for m, z in centers do
		local center = Vector3.new(-52, 0, z)
		local monolith = Instance.new("Model")
		monolith.Name = `Monolith{m}`
		standing("Core", Vector3.new(depth - 2, MAT_TOP + height, width), center, "Charcoal", monolith)
		for side = 0, 1 do
			local index = (m - 1) * 2 + side + 1
			local problem = PROBLEMS[index]
			local facing = if side == 0 then Vector3.new(1, 0, 0) else Vector3.new(-1, 0, 0)
			local angle = if side == 0 then BOULDER_OVERHANG else 0
			local origin = center + facing * (depth / 2) + Vector3.yAxis * MAT_TOP
			local face = Face.new(origin, facing, { { length = height, angle = angle } })
			local holds = RouteGenerator.generate({ seed = index * 1013, height = height, lineX = 0, wander = 0.8, difficulty = problem.difficulty })
			PanelWall.build(face, monolith, { width = width, holds = holds, tnutSpacing = 1.1, plateColor = Color3.fromRGB(238, 238, 236) })
			overhangCheeks(face, width, monolith)
			RouteKit.buildRoute({
				id = problem.id,
				name = problem.name,
				grade = problem.grade,
				order = 1 + index,
				face = face,
				lineX = 0,
				holds = holds,
				style = "plastic",
				color = problem.color,
				baseY = MAT_TOP,
				indoor = true,
			})
			-- Problem number on the pad in front of the face.
			local number = part({
				name = "Number",
				size = Vector3.new(2, 0.02, 2),
				cframe = frameAt(origin + facing * 5 + Vector3.yAxis * 0.02, -facing, Vector3.yAxis),
				surface = "PaddedMat",
				shadow = false,
				parent = monolith,
			})
			number.Transparency = 1
			label(number, Enum.NormalId.Top, tostring(index), problem.color, Enum.Font.Michroma, false)
		end
		-- Cap over the top, wide enough to cover the overhanging face.
		local overhang = height * math.sin(math.rad(BOULDER_OVERHANG))
		local capY = MAT_TOP + height * math.cos(math.rad(BOULDER_OVERHANG))
		box("Cap", Vector3.new(depth + overhang + 0.6, 0.4, width + 0.8), center + Vector3.new(overhang / 2, capY + 0.2, 0), "Charcoal", monolith)
		monolith.Parent = hall
	end
	RouteKit.addChalkBucket(hall, Vector3.new(-37, 0, -11))
	hangingSign(hall, "BOULDERING", Vector3.new(-40, 24, 4), Vector3.new(1, 0, 0), 14)
	npc("Climber", Vector3.new(-36, 0, 6), Vector3.new(-1, 0, 0), hall, Color3.fromRGB(40, 200, 200), GEAR.climber)
	hall.Parent = model
end

---------------------------------------------------------------------------------------
-- Kilter room (back right)

local LED = {
	Start = Color3.fromRGB(70, 230, 110),
	Hand = Color3.fromRGB(60, 210, 240),
	Foot = Color3.fromRGB(255, 160, 40),
	Finish = Color3.fromRGB(240, 70, 200),
}

local function buildKilter(model: Model)
	local room = Instance.new("Model")
	room.Name = "KilterRoom"
	local BX, BZ = 54, -30 -- where the board's foot is
	-- Glass partitions (with a doorway on the west side), steel frames.
	local function glassPanel(size: Vector3, position: Vector3)
		local glass = box("Glass", size, position, "ClearGlass", room)
		glass.CastShadow = false
	end
	glassPanel(Vector3.new(0.2, 12, 20), Vector3.new(43, 6, -30))
	glassPanel(Vector3.new(0.2, 12, 4), Vector3.new(43, 6, -12))
	glassPanel(Vector3.new(21, 12, 0.2), Vector3.new(53.5, 6, -10))
	for _, z in { -40, -20, -14, -10 } do
		standing("GlassFrame", Vector3.new(0.4, 12.4, 0.4), Vector3.new(43, 0, z), "BlackSteel", room)
	end
	box("GlassHead", Vector3.new(0.4, 0.4, 30), Vector3.new(43, 12.2, -25), "BlackSteel", room)
	box("GlassHeadNorth", Vector3.new(21, 0.4, 0.4), Vector3.new(53.5, 12.2, -10), "BlackSteel", room)
	hangingSign(room, "KILTER BOARD", Vector3.new(53.5, 15, -10), Vector3.new(0, 0, 1), 12)

	-- The board: black, 40 degrees overhanging, on a steel frame over a big mat.
	local length = 14
	local mat = box("KilterMat", Vector3.new(18, 1, 16), Vector3.new(BX, 0.5, BZ + 8), "PaddedMat", room)
	CollectionService:AddTag(mat, Tags.CrashMat)
	local face = Face.new(Vector3.new(BX, 1.2, BZ), Vector3.new(0, 0, 1), { { length = length, angle = 40 } })
	PanelWall.build(face, room, { width = 12, plate = "Charcoal", tnutSpacing = 0 })
	local top = Face.top(face)
	for _, side in { -1, 1 } do
		local x = BX + side * 6.4
		BuildUtil.beam("FramePost", Vector3.new(x, 0.25, BZ - 1.5), Vector3.new(top.X + side * 6.4, top.Y + 0.5, top.Z - 1.5), 0.5, "BlackSteel", room).CanCollide = true
		BuildUtil.beam("FrameLeg", Vector3.new(x, 0.3, BZ - 6), Vector3.new(top.X + side * 6.4, top.Y + 0.5, top.Z - 1.5), 0.4, "BlackSteel", room).CanCollide = true
		standing("FootPlate", Vector3.new(1, 0.1, 1), Vector3.new(x, 0, BZ - 6), "BlackSteel", room)
		standing("FootPlate", Vector3.new(1, 0.1, 1), Vector3.new(x, 0, BZ - 1.5), "BlackSteel", room)
	end

	-- 12 x 12 grid of small pale holds; the lit problem uses some of them.
	local grid: { RouteKit.HoldSpec } = {}
	local types = { "Edge", "Crimp", "Jug", "Sloper", "Pinch", "Pocket", "Foothold", "Edge", "Crimp" }
	for row = 0, 11 do
		for column = 0, 11 do
			table.insert(grid, {
				x = -5.25 + column * 0.95 + (row % 2) * 0.2,
				y = 1.0 + row * 1.05,
				type = types[(row * 7 + column * 3) % #types + 1],
				rotation = ((row * 13 + column * 29) % 60) - 30,
			})
		end
	end
	local problem = RouteGenerator.generate({ seed = 4040, height = length, lineX = 0, wander = 1.4, difficulty = 0.2, startY = 1.0 })
	local used: { [number]: boolean } = {}
	local lit: { RouteKit.HoldSpec } = {}
	for _, h in problem do
		local best, bestDistance = 0, math.huge
		for i, g in grid do
			local distance = (g.x - h.x) ^ 2 + (g.y - h.y) ^ 2
			if not used[i] and distance < bestDistance then
				best, bestDistance = i, distance
			end
		end
		used[best] = true
		local g = grid[best]
		-- Start and finish must take hands; the rest keep the board's own hold.
		local holdType = if h.role then "Jug" else g.type
		table.insert(lit, { x = g.x, y = g.y, type = holdType, role = h.role, rotation = g.rotation })
	end
	table.sort(lit, function(a, b)
		return a.y < b.y
	end)
	local route = RouteKit.buildRoute({
		id = "KilterFirstLight",
		name = "First Light",
		grade = "V2",
		order = 10,
		face = face,
		lineX = 0,
		holds = lit,
		style = "plastic",
		color = Color3.fromRGB(232, 232, 226),
		baseY = 1,
		indoor = true,
	})
	-- LED rings behind the lit holds (soft: a coloured ring and a small light each).
	for _, hold in (route:FindFirstChild("Holds") :: Folder):GetChildren() do
		if not hold:IsA("BasePart") then
			continue
		end
		local role = hold:GetAttribute("Role")
		local kind = if role == "Start" then "Start" elseif role == "Finish" then "Finish" elseif hold:GetAttribute("HandOK") == false or hold.Position.Y < 4 then "Foot" else "Hand"
		local grip = hold:FindFirstChild("Grip") :: Attachment
		local ring = part({
			name = "Led",
			size = Vector3.new(0.02, 1.1, 1.1),
			cframe = grip.WorldCFrame * CFrame.new(0, 0, (hold.Size.Z - 0.02)) * BuildUtil.AXIS_Z,
			surface = "Neon",
			color = LED[kind],
			shape = Enum.PartType.Cylinder,
			shadow = false,
			parent = hold,
		})
		ring.Transparency = 0.3
		local light = Instance.new("PointLight")
		light.Color = LED[kind]
		light.Range = 2.5
		light.Brightness = 0.6
		light.Shadows = false
		light.Parent = ring
		hold:SetAttribute("Led", kind)
	end
	-- The rest of the board: real holds you can use, just not part of the problem.
	local offRoute = Instance.new("Folder")
	offRoute.Name = "OffRouteHolds"
	local unlit = {}
	for i, g in grid do
		if not used[i] then
			table.insert(unlit, g)
		end
	end
	RouteKit.buildHolds(face, unlit, offRoute, "KilterGrid", { style = "plastic", color = Color3.fromRGB(200, 200, 196) })
	offRoute.Parent = room

	-- Kiosk.
	standing("KioskPost", Vector3.new(0.5, 3.4, 0.5), Vector3.new(44.5, 0, -12), "BlackSteel", room)
	local screen = part({
		name = "KioskScreen",
		size = Vector3.new(2.4, 1.6, 0.15),
		cframe = CFrame.new(44.5, 3.8, -12) * CFrame.Angles(0, math.rad(200), 0) * CFrame.Angles(math.rad(-25), 0, 0),
		surface = "Charcoal",
		collide = true,
		query = true,
		parent = room,
	})
	label(screen, Enum.NormalId.Front, `<font color="#FFFFFF"><b>KILTER</b></font>\nFirst Light  <font color="#5CE65C">V2</font>\n<font color="#3CD2F0">Board 40°</font>`, WHITE, Enum.Font.BuilderSansMedium, true)
	room.Parent = model
end

---------------------------------------------------------------------------------------
-- Pro shop (right), lockers (front left), lounge (front right), training corner

-- A real catalog item (pack, helmet, chalk bag) on display, standing at `position`
-- facing `facing`, fitted into `size`. ShopService swaps the stand-in for the item.
local function gearDisplay(parent: Instance, assetId: number, position: Vector3, facing: Vector3, size: Vector3, fallback: (Model) -> ())
	local model = Instance.new("Model")
	model.Name = "GearDisplay"
	model:SetAttribute("DisplayAsset", assetId)
	model:SetAttribute("Base", Props.at(position, facing))
	model:SetAttribute("FitSize", size)
	fallback(model)
	model.Parent = parent
	CollectionService:AddTag(model, "GearDisplay")
end

-- A little product on a shelf, for the shop's displays.
local function product(parent: Instance, kind: string, position: Vector3, color: Color3)
	if kind == "shoe" then
		for _, dz in { -0.28, 0.28 } do
			part({ name = "Shoe", size = Vector3.new(1.1, 0.42, 0.42), cframe = CFrame.new(position + Vector3.new(0, 0.29, dz)), surface = "Upholstery", color = color, ellipsoid = true, parent = parent })
			part({ name = "Sole", size = Vector3.new(1.12, 0.08, 0.4), cframe = CFrame.new(position + Vector3.new(0, 0.04, dz)), surface = "RubberTile", color = Color3.fromRGB(30, 30, 32), parent = parent })
		end
	elseif kind == "chalkbag" then
		part({ name = "ChalkBag", size = Vector3.new(0.9, 0.7, 0.7), cframe = CFrame.new(position + Vector3.yAxis * 0.45) * BuildUtil.AXIS_Y, surface = "Upholstery", color = color, shape = Enum.PartType.Cylinder, parent = parent })
	elseif kind == "rope" then
		part({ name = "Rope", size = Vector3.new(0.5, 1.5, 1.5), cframe = CFrame.new(position + Vector3.yAxis * 0.75) * CFrame.Angles(0, math.rad(90), 0), surface = "Tape", color = color, shape = Enum.PartType.Cylinder, parent = parent })
	else
		part({ name = "Pack", size = Vector3.new(1.1, 1.4, 0.7), cframe = CFrame.new(position + Vector3.yAxis * 0.7), surface = "Upholstery", color = color, ellipsoid = true, parent = parent })
	end
end

local function buildShop(model: Model)
	local shop = Instance.new("Model")
	shop.Name = "ProShop"
	standing("OakFloor", Vector3.new(22, 0.04, 22), Vector3.new(52, 0, 11), "OakFloor", shop, false)
	-- Shelving along the right wall: an oak back panel and four shelves of gear.
	standing("ShelfBack", Vector3.new(0.3, 12, 20), Vector3.new(63.75, 0, 11), "WhiteOak", shop)
	local colors = { Color3.fromRGB(255, 122, 48), Color3.fromRGB(60, 140, 240), Color3.fromRGB(40, 190, 120), Color3.fromRGB(230, 60, 80), Color3.fromRGB(240, 210, 60), Color3.fromRGB(150, 90, 220) }
	-- The real catalog gear on display: chalk bags, helmets and packs (ShopService puts
	-- the actual items on the shelves; the simple products are stand-ins).
	local chalkLooks = Gear.CHALK_BAGS
	local helmets: { Gear.Variant }, packs: { Gear.Variant } = {}, {}
	for _, item in Gear.ITEMS do
		local looks: { Gear.Variant } = item.variants or {}
		for _, look in looks do
			table.insert(if item.slot == "Helmet" then helmets else packs, look)
		end
	end
	local shelves: { { kind: string, looks: { Gear.Variant } } } = {
		{ kind = "shoe", looks = {} },
		{ kind = "chalkbag", looks = chalkLooks },
		{ kind = "helmet", looks = helmets },
		{ kind = "pack", looks = packs },
	}
	for level, shelf in shelves do
		local y = 1.6 + (level - 1) * 2.6
		box("Shelf", Vector3.new(2, 0.2, 20), Vector3.new(62.6, y, 11), "WhiteOak", shop)
		for i = 0, 6 do
			local spot = Vector3.new(62.6, y + 0.1, 2.5 + i * 2.8)
			local color = colors[(i + level) % #colors + 1]
			local look = shelf.looks[(i % math.max(1, #shelf.looks)) + 1]
			if look then
				gearDisplay(shop, look.asset, spot, Vector3.new(-1, 0, 0), Vector3.new(1.6, if shelf.kind == "pack" then 2.2 else 1.4, 1.6), function(m)
					product(m, if shelf.kind == "helmet" then "chalkbag" else shelf.kind, spot, look.color)
				end)
			else
				product(shop, shelf.kind, spot, color)
			end
		end
	end
	local cframe = counter(shop, "Counter", Vector3.new(48, 0, 11), 9, Vector3.new(-1, 0, 0))
	local till = part({ name = "Till", size = Vector3.new(1.6, 1.1, 0.12), cframe = cframe * CFrame.new(2.5, 2.5, 0.2) * CFrame.Angles(math.rad(-15), 0, 0), surface = "Charcoal", parent = shop })
	label(till, Enum.NormalId.Front, `<font color="#FF7A30">£</font> GEAR`, WHITE, Enum.Font.Sarpanch, true)
	npc("Pro shop", Vector3.new(51, 0, 11), Vector3.new(-1, 0, 0), shop, Color3.fromRGB(42, 44, 50), GEAR.shop)
	local promptPart = part({ name = "ShopPrompt", size = Vector3.new(1, 1, 1), cframe = cframe * CFrame.new(0, 2.4, 0), surface = "Charcoal", parent = shop })
	promptPart.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenShop"
	prompt.ActionText = "Browse gear"
	prompt.ObjectText = "Pro shop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart
	-- A shoe wall by the entrance to the shop.
	standing("ShoeWall", Vector3.new(8, 8, 0.3), Vector3.new(52, 0, 21.8), "WhiteOak", shop)
	for row = 0, 2 do
		for column = 0, 3 do
			local spot = Vector3.new(49 + column * 2, 1.8 + row * 2.2, 21.2)
			box("ShoeShelf", Vector3.new(1.6, 0.12, 0.9), spot - Vector3.yAxis * 0.06, "WhiteOak", shop)
			product(shop, "shoe", spot, colors[(row * 4 + column) % #colors + 1])
		end
	end
	hangingSign(shop, "PRO SHOP", Vector3.new(48, 18, 11), Vector3.new(-1, 0, 0), 12)
	plant(shop, Vector3.new(42, 0, 2))
	shop.Parent = model
end

local function buildLockers(model: Model)
	local room = Instance.new("Model")
	room.Name = "Lockers"
	for i = 0, 9 do
		local z = 23 + i * 1.9
		local paint = if i % 2 == 0 then "LockerPaint" else "Charcoal"
		prop(room, "locker", Vector3.new(-63, 0, z), Vector3.new(1, 0, 0), Vector3.new(1.8, 7.2, 1.8), function(m)
			standing("Locker", Vector3.new(1.8, 7.2, 1.8), Vector3.new(-63, 0, z), paint, m)
			local door = part({ name = "Door", size = Vector3.new(0.04, 6.6, 1.7), cframe = CFrame.new(-62.08, 3.6, z), surface = "WhiteOak", parent = m })
			door.CastShadow = false
			part({ name = "Handle", size = Vector3.new(0.12, 0.6, 0.12), cframe = CFrame.new(-62.0, 3.8, z + 0.6), surface = "BlackSteel", shadow = false, parent = m })
			for v = 0, 2 do
				part({ name = "Vent", size = Vector3.new(0.02, 0.06, 1.1), cframe = CFrame.new(-62.05, 6.2 - v * 0.2, z), surface = "Charcoal", shadow = false, parent = m })
			end
		end)
	end
	-- Bench and the bag station.
	prop(room, "bench", Vector3.new(-57, 0, 32), Vector3.new(1, 0, 0), Vector3.new(10, 2.2, 2.4), function(m)
		box("Bench", Vector3.new(2, 0.3, 12), Vector3.new(-57, 1.6, 32), "WhiteOak", m)
		for _, z in { 27, 37 } do
			standing("BenchLeg", Vector3.new(1.6, 1.45, 0.2), Vector3.new(-57, 0, z), "BlackSteel", m)
		end
	end)
	standing("Mirror", Vector3.new(0.2, 8, 4), Vector3.new(-63.8, 1, 19.5), "Mirror", room)
	local station = standing("BagStation", Vector3.new(2.4, 3.2, 2.4), Vector3.new(-50, 0, 36), "Charcoal", room)
	box("StationTop", Vector3.new(2.8, 0.2, 2.8), Vector3.new(-50, 3.3, 36), "WhiteOak", room)
	gearDisplay(room, 128795521464166, Vector3.new(-50, 3.4, 36), Vector3.new(1, 0, 0), Vector3.new(2, 2.4, 2), function(m)
		product(m, "pack", Vector3.new(-50, 3.4, 36), ORANGE)
	end)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenLocker"
	prompt.ActionText = "Customise bag"
	prompt.ObjectText = "Locker"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = station
	-- Packing your bag for the crags (PackUI / PackService).
	local packPrompt = Instance.new("ProximityPrompt")
	packPrompt.Name = "OpenPack"
	packPrompt.ActionText = "Pack bag"
	packPrompt.ObjectText = "Locker"
	packPrompt.KeyboardKeyCode = Enum.KeyCode.F
	packPrompt.HoldDuration = 0
	packPrompt.MaxActivationDistance = 10
	packPrompt.RequiresLineOfSight = false
	packPrompt.UIOffset = Vector2.new(0, 80)
	packPrompt.Parent = station
	hangingSign(room, "LOCKERS", Vector3.new(-54, 18, 30), Vector3.new(1, 0, 0), 10)
	plant(room, Vector3.new(-44, 0, 41))
	room.Parent = model
end

local function buildLounge(model: Model)
	local lounge = Instance.new("Model")
	lounge.Name = "Lounge"
	-- Sofa against the right wall, facing into the gym.
	prop(lounge, "sofa", Vector3.new(61.9, 0, 34), Vector3.new(-1, 0, 0), Vector3.new(10.8, 3.6, 4), function(m)
		standing("SofaSeat", Vector3.new(3, 1.4, 10), Vector3.new(61.5, 0, 34), "Upholstery", m)
		standing("SofaBack", Vector3.new(1, 3.2, 10), Vector3.new(63.3, 0, 34), "Upholstery", m)
		for _, z in { 28.6, 39.4 } do
			standing("SofaArm", Vector3.new(4, 2.2, 0.8), Vector3.new(61.8, 0, z), "Upholstery", m)
		end
		for i, z in { 31, 34, 37 } do
			part({ name = "Cushion", size = Vector3.new(0.6, 2, 2.2), cframe = CFrame.new(62.4, 2.4, z) * CFrame.Angles(0, 0, math.rad(-10)), surface = "Upholstery", color = if i == 2 then ORANGE else Color3.fromRGB(220, 214, 204), ellipsoid = true, parent = m })
		end
	end)
	standing("CoffeeTable", Vector3.new(3, 1.2, 5), Vector3.new(56.5, 0, 34), "WhiteOak", lounge)
	-- Cafe bar along the front glass.
	local cframe = counter(lounge, "CafeBar", Vector3.new(50, 0, 40.5), 10, Vector3.new(0, 0, -1))
	local barTop = (cframe * CFrame.new(-3, 1.9, 0.3)).Position
	prop(lounge, "coffee", barTop, Vector3.new(0, 0, -1), Vector3.new(1.8, 1.9, 1.3), function(m)
		part({ name = "CoffeeMachine", size = Vector3.new(1.4, 1.6, 1.1), cframe = cframe * CFrame.new(-3, 2.7, 0.3), surface = "BlackSteel", parent = m })
	end)
	for i = 0, 2 do
		part({ name = "Cup", size = Vector3.new(0.35, 0.3, 0.3), cframe = cframe * CFrame.new(1 + i * 0.7, 2.08, 0) * BuildUtil.AXIS_Y, surface = "SoftWhite", shape = Enum.PartType.Cylinder, parent = lounge })
	end
	for _, x in { 46, 50, 54 } do
		prop(lounge, "stool", Vector3.new(x, 0, 37.8), Vector3.new(0, 0, 1), Vector3.new(1.5, 2.8, 1.5), function(m)
			part({ name = "Stool", size = Vector3.new(2.4, 1.2, 1.2), cframe = CFrame.new(x, 1.2, 37.8) * BuildUtil.AXIS_Y, surface = "WhiteOak", shape = Enum.PartType.Cylinder, collide = true, query = true, parent = m })
		end)
	end
	-- Vending machine in the corner and a water cooler by the door.
	prop(lounge, "vending", Vector3.new(62.4, 0, 42.2), Vector3.new(-1, 0, 0), Vector3.new(3.2, 6.6, 2.6), function(m)
		standing("Vending", Vector3.new(2.6, 6.4, 3.2), Vector3.new(62.4, 0, 42.2), "Charcoal", m)
		box("VendingGlass", Vector3.new(0.05, 4.2, 2.2), Vector3.new(61.08, 3.8, 42.2), "ClearGlass", m)
	end)
	prop(lounge, "cooler", Vector3.new(10, 0, 42.4), Vector3.new(0, 0, -1), Vector3.new(1.4, 4.4, 1.4), function(m)
		standing("Cooler", Vector3.new(1.2, 3, 1.2), Vector3.new(10, 0, 42.4), "SoftWhite", m)
		part({ name = "Bottle", size = Vector3.new(1.2, 0.9, 0.9), cframe = CFrame.new(10, 3.6, 42.4) * BuildUtil.AXIS_Y, surface = "ClearGlass", shape = Enum.PartType.Cylinder, parent = m })
	end)
	hangingSign(lounge, "CAFÉ", Vector3.new(50, 18, 36), Vector3.new(0, 0, -1), 8)
	plant(lounge, Vector3.new(42, 0, 42))
	plant(lounge, Vector3.new(62, 0, 25), 1.2)
	lounge.Parent = model
end

local function buildTraining(model: Model)
	local corner = Instance.new("Model")
	corner.Name = "Training"
	standing("Tiles", Vector3.new(14, 0.06, 10), Vector3.new(-26, 0, 6), "RubberTile", corner, false)
	for _, x in { -29.5, -22.5 } do
		standing("FramePost", Vector3.new(0.4, 9, 0.4), Vector3.new(x, 0.06, 2), "BlackSteel", corner)
	end
	box("FrameBar", Vector3.new(7.4, 0.4, 0.4), Vector3.new(-26, 9.26, 2), "BlackSteel", corner)
	box("Hangboard", Vector3.new(5, 1, 0.6), Vector3.new(-26, 7.6, 2.2), "WhiteOak", corner)
	for i = 0, 2 do
		local size = 1 + i * 0.2
		part({ name = "Kettlebell", size = Vector3.one * size, cframe = CFrame.new(-31 + i * 1.6, 0.06 + size / 2, 9), surface = "BlackSteel", shape = Enum.PartType.Ball, collide = true, query = true, parent = corner })
	end
	prop(corner, "benchpress", Vector3.new(-21, 0.06, 6), Vector3.new(-1, 0, 0), Vector3.new(4.5, 3.8, 6), function(m)
		standing("PressBench", Vector3.new(1.2, 1.5, 4), Vector3.new(-21, 0.06, 6), "Upholstery", m)
		for _, z in { 4, 8 } do
			standing("Upright", Vector3.new(0.3, 3.6, 0.3), Vector3.new(-21, 0.06, z), "BlackSteel", m)
		end
		part({ name = "Bar", size = Vector3.new(6, 0.18, 0.18), cframe = CFrame.new(-21, 3.5, 6) * CFrame.Angles(0, math.rad(90), 0), surface = "Steel", shape = Enum.PartType.Cylinder, parent = m })
	end)
	plant(corner, Vector3.new(-18, 0, 10))
	corner.Parent = model
end

---------------------------------------------------------------------------------------

-- Older test builds left a floor/spawn; a template Baseplate would fight the gym floor.
local function hideLegacy()
	for _, name in { "Baseplate", "TestFloor", "TestSpawn" } do
		local legacy = Workspace:FindFirstChild(name)
		if legacy and legacy:IsA("BasePart") then
			legacy.Transparency = 1
			legacy.CanCollide = false
			legacy.CanQuery = false
			if legacy:IsA("SpawnLocation") then
				legacy.Enabled = false
			end
			print(`[Gym] hid the old {name} (the gym and outdoors replace it)`)
		end
	end
end

function Gym.Find(): Instance?
	return Workspace:FindFirstChild("Gym")
end

function Gym.Build(): Model
	hideLegacy()
	local model = Instance.new("Model")
	model.Name = "Gym"
	buildShell(model)
	buildSpawn(model)
	buildReception(model)
	buildLeaderboardWall(model)
	buildRopeWalls(model)
	buildBoulders(model)
	buildKilter(model)
	buildShop(model)
	buildLockers(model)
	buildLounge(model)
	buildTraining(model)
	model:SetAttribute("Version", Config.Version)
	model.Parent = Workspace
	return model
end

function Gym.Ensure(): Instance
	hideLegacy()
	local existing = Gym.Find()
	-- A gym saved into the place by an older version is rebuilt with the new layout.
	if existing and existing:GetAttribute("Version") ~= Config.Version then
		existing:Destroy()
		existing = nil
	end
	return existing or Gym.Build()
end

function Gym.Rebuild(): Model
	local existing = Gym.Find()
	if existing then
		existing:Destroy()
	end
	return Gym.Build()
end

return Gym
