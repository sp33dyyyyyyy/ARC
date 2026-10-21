--!strict
-- Gym: the indoor bouldering gym everyone spawns in (design doc 1b and 5.1).
--
--   * White building with navy panels, black ceiling, strip lights and magenta/cyan neon;
--     outside: navy cladding with wood slats, the glowing logo and a yellow doorway.
--   * Spawn on a black splat by the reception desk (navy and light wood, with a monitor
--     and a receptionist).
--   * Bouldering hall: four pegboard monoliths, two colour-coded problems each, round
--     crash mats and numbered rubber floor.
--   * Kilter room: a 40-degree LED board with a lit problem ("First Light") and a kiosk.
--   * The cyan LEADERBOARD wall (LeaderboardService writes on it).
--   * The tutorial wall (TestWall) stands at the back of the gym.
--
-- Built once at server start if Workspace.Gym is missing, or in edit mode from the command
-- bar: require(game.ServerScriptService.Server.World.Gym).Rebuild()

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)

local BuildUtil = require(script.Parent.BuildUtil)
local Face = require(script.Parent.Face)
local PanelWall = require(script.Parent.PanelWall)
local RouteGenerator = require(script.Parent.RouteGenerator)
local RouteKit = require(script.Parent.RouteKit)

local part = BuildUtil.part
local frameAt = BuildUtil.frameAt

-- Building footprint (the tutorial wall sits at z = -24 facing +Z).
local X0, X1, Z0, Z1, HEIGHT = -64, 64, -40, 44, 36
local DOOR_HALF, DOOR_HEIGHT = 7, 14
local SPAWN = Vector3.new(0, 0, 30)

local Gym = {}

local function box(name: string, size: Vector3, position: Vector3, surface: string, parent: Instance, collide: boolean?, color: Color3?): BasePart
	return part({ name = name, size = size, cframe = CFrame.new(position), surface = surface, color = color, collide = collide ~= false, query = collide ~= false, parent = parent })
end

local function label(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?, glow: boolean?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = if glow then 0 else 0.5
	gui.Brightness = if glow then 2 else 1
	gui.Parent = parent
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Font = font or Enum.Font.GothamBlack
	textLabel.TextScaled = true
	textLabel.RichText = true
	textLabel.TextColor3 = color
	textLabel.Text = text
	textLabel.Parent = gui
	return gui
end

---------------------------------------------------------------------------------------
-- Shell

local function buildShell(model: Model)
	local shell = Instance.new("Model")
	shell.Name = "Shell"
	shell.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- seen from the crags
	local midX, midZ = (X0 + X1) / 2, (Z0 + Z1) / 2
	local w, d = X1 - X0, Z1 - Z0

	box("Floor", Vector3.new(w, 1, d), Vector3.new(midX, -0.5, midZ), "GymFloor", shell)
	box("Ceiling", Vector3.new(w + 2, 1, d + 2), Vector3.new(midX, HEIGHT + 0.5, midZ), "Ceiling", shell)
	box("WallBack", Vector3.new(w + 2, HEIGHT, 1), Vector3.new(midX, HEIGHT / 2, Z0 - 0.5), "GymWall", shell)
	box("WallLeft", Vector3.new(1, HEIGHT, d), Vector3.new(X0 - 0.5, HEIGHT / 2, midZ), "GymWall", shell)
	box("WallRight", Vector3.new(1, HEIGHT, d), Vector3.new(X1 + 0.5, HEIGHT / 2, midZ), "GymWall", shell)
	local sideWidth = (X1 - X0) / 2 - DOOR_HALF
	box("WallFrontL", Vector3.new(sideWidth + 1, HEIGHT, 1), Vector3.new(X0 + sideWidth / 2 - 0.5, HEIGHT / 2, Z1 + 0.5), "GymWall", shell)
	box("WallFrontR", Vector3.new(sideWidth + 1, HEIGHT, 1), Vector3.new(X1 - sideWidth / 2 + 0.5, HEIGHT / 2, Z1 + 0.5), "GymWall", shell)
	box("Lintel", Vector3.new(DOOR_HALF * 2, HEIGHT - DOOR_HEIGHT, 1), Vector3.new(0, (HEIGHT + DOOR_HEIGHT) / 2, Z1 + 0.5), "GymWall", shell)

	-- Navy band along the bottom of the inside walls (just in front of them).
	local band = 4
	box("BandBack", Vector3.new(w, band, 0.1), Vector3.new(midX, band / 2, Z0 + 0.05), "NavyPanel", shell, false)
	box("BandLeft", Vector3.new(0.1, band, d), Vector3.new(X0 + 0.05, band / 2, midZ), "NavyPanel", shell, false)
	box("BandRight", Vector3.new(0.1, band, d), Vector3.new(X1 - 0.05, band / 2, midZ), "NavyPanel", shell, false)
	box("BandFrontL", Vector3.new(sideWidth, band, 0.1), Vector3.new(X0 + sideWidth / 2, band / 2, Z1 - 0.05), "NavyPanel", shell, false)
	box("BandFrontR", Vector3.new(sideWidth, band, 0.1), Vector3.new(X1 - sideWidth / 2, band / 2, Z1 - 0.05), "NavyPanel", shell, false)

	-- Outside: navy cladding with vertical wood slats, a yellow-framed door and the logo.
	local skin = 0.6
	box("CladBack", Vector3.new(w + 2 + skin * 2, HEIGHT, skin), Vector3.new(midX, HEIGHT / 2, Z0 - 1 - skin / 2), "NavyPanel", shell)
	box("CladLeft", Vector3.new(skin, HEIGHT, d + 2), Vector3.new(X0 - 1 - skin / 2, HEIGHT / 2, midZ), "NavyPanel", shell)
	box("CladRight", Vector3.new(skin, HEIGHT, d + 2), Vector3.new(X1 + 1 + skin / 2, HEIGHT / 2, midZ), "NavyPanel", shell)
	box("CladFrontL", Vector3.new(sideWidth + 1 + skin, HEIGHT, skin), Vector3.new(X0 + sideWidth / 2 - 0.5 - skin / 2, HEIGHT / 2, Z1 + 1 + skin / 2), "NavyPanel", shell)
	box("CladFrontR", Vector3.new(sideWidth + 1 + skin, HEIGHT, skin), Vector3.new(X1 - sideWidth / 2 + 0.5 + skin / 2, HEIGHT / 2, Z1 + 1 + skin / 2), "NavyPanel", shell)
	box("CladLintel", Vector3.new(DOOR_HALF * 2, HEIGHT - DOOR_HEIGHT, skin), Vector3.new(0, (HEIGHT + DOOR_HEIGHT) / 2, Z1 + 1 + skin / 2), "NavyPanel", shell)
	local slatZ = Z1 + 1 + skin + 0.15
	local x = X0
	while x <= X1 do
		if math.abs(x) > DOOR_HALF + 1 then
			box("Slat", Vector3.new(0.6, HEIGHT - 2, 0.3), Vector3.new(x, HEIGHT / 2, slatZ), "LightWood", shell, false)
		end
		x += 2.5
	end
	for _, spec in { { -DOOR_HALF - 0.4, DOOR_HEIGHT / 2, 0.8, DOOR_HEIGHT + 1.6 }, { DOOR_HALF + 0.4, DOOR_HEIGHT / 2, 0.8, DOOR_HEIGHT + 1.6 }, { 0, DOOR_HEIGHT + 0.4, DOOR_HALF * 2 + 1.6, 0.8 } } do
		local frame = box("DoorFrame", Vector3.new(spec[3], spec[4], 0.6), Vector3.new(spec[1], spec[2], Z1 + 1.9), "Neon", shell, false, Color3.fromRGB(255, 200, 40))
		frame.CanQuery = false
	end
	local logo = box("Logo", Vector3.new(34, 7, 0.4), Vector3.new(0, DOOR_HEIGHT + 7, slatZ + 0.4), "NavyPanel", shell, false)
	label(logo, Enum.NormalId.Back, `<font color="#FFD23F">{string.upper(Config.GameName)}</font><font color="#FF3DA5">!</font>`, Color3.new(1, 1, 1), Enum.Font.GothamBlack, true)
	local logoLight = Instance.new("PointLight")
	logoLight.Color = Color3.fromRGB(255, 220, 90)
	logoLight.Range = 24
	logoLight.Brightness = 1.5
	logoLight.Parent = logo
	-- A column of coloured holds down the building's corner.
	local colours = { Color3.fromRGB(250, 215, 50), Color3.fromRGB(230, 60, 60), Color3.fromRGB(70, 200, 90), Color3.fromRGB(60, 130, 240), Color3.fromRGB(220, 60, 200) }
	for i = 0, 11 do
		local hold = part({
			name = "CornerHold",
			size = Vector3.new(1.4, 1, 0.8),
			cframe = CFrame.new(X1 + 1.6 + skin, 3 + i * 2.6, Z1 + 1.6 + skin) * CFrame.Angles(0, math.rad(45), math.rad(i * 37)),
			surface = "HoldUrethane",
			color = colours[i % #colours + 1],
			ellipsoid = true,
			parent = shell,
		})
		hold.CastShadow = false
	end

	-- Ceiling strip lights.
	for _, lx in { -44, -16, 16, 44 } do
		for _, lz in { -26, -6, 14, 34 } do
			local strip = box("StripLight", Vector3.new(18, 0.3, 1.2), Vector3.new(lx, HEIGHT - 0.25, lz), "Neon", shell, false, Color3.fromRGB(255, 250, 240))
			strip.CastShadow = false
			local light = Instance.new("SurfaceLight")
			light.Face = Enum.NormalId.Bottom
			light.Range = 40
			light.Angle = 150
			light.Brightness = 1.4
			light.Color = Color3.fromRGB(255, 246, 232)
			light.Parent = strip
		end
	end
	-- Neon accents along the side walls.
	box("NeonMagenta", Vector3.new(0.3, 0.4, d - 8), Vector3.new(X0 + 0.3, 26, midZ), "Neon", shell, false, Color3.fromRGB(255, 60, 170)).CastShadow = false
	box("NeonCyan", Vector3.new(0.3, 0.4, d - 8), Vector3.new(X1 - 0.3, 26, midZ), "Neon", shell, false, Color3.fromRGB(40, 220, 230)).CastShadow = false

	shell.Parent = model
end

---------------------------------------------------------------------------------------
-- Spawn and reception

local function buildSpawn(model: Model)
	-- Black starburst splat on the floor.
	local splat = Instance.new("Model")
	splat.Name = "SpawnSplat"
	part({ name = "Disc", size = Vector3.new(0.06, 5, 5), cframe = CFrame.new(SPAWN + Vector3.yAxis * 0.03) * BuildUtil.AXIS_Y, surface = "Ceiling", shape = Enum.PartType.Cylinder, shadow = false, parent = splat })
	for i = 0, 11 do
		local angle = i * math.pi / 6 + (i % 2) * 0.12
		local length = if i % 2 == 0 then 3.4 else 2.4
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		part({
			name = "Spike",
			size = Vector3.new(0.7, 0.04, length),
			cframe = CFrame.lookAt(SPAWN + direction * (1.8 + length / 2) + Vector3.yAxis * 0.02, SPAWN + direction * 10 + Vector3.yAxis * 0.02),
			surface = "Ceiling",
			shadow = false,
			parent = splat,
		})
	end
	splat.Parent = model

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "GymSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = frameAt(SPAWN + Vector3.yAxis * 0.5, Vector3.new(0, 0, -1), Vector3.yAxis)
	spawn.Anchored = true
	spawn.CanCollide = false
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

local function npc(name: string, position: Vector3, facing: Vector3, parent: Instance, shirt: Color3)
	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		description.HeadColor = Color3.fromRGB(234, 184, 146)
		description.LeftArmColor = shirt
		description.RightArmColor = shirt
		description.TorsoColor = shirt
		description.LeftLegColor = Color3.fromRGB(30, 36, 60)
		description.RightLegColor = Color3.fromRGB(30, 36, 60)
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or model == nil then
		return
	end
	model.Name = name
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root and humanoid then
		root.Anchored = true
		model:PivotTo(CFrame.lookAt(position + Vector3.yAxis * (humanoid.HipHeight + root.Size.Y / 2), position + Vector3.yAxis * (humanoid.HipHeight + root.Size.Y / 2) + facing))
		humanoid.DisplayName = name
		humanoid.NameDisplayDistance = 30
	end
	model.Parent = parent
end

local function buildReception(model: Model)
	local desk = Instance.new("Model")
	desk.Name = "Reception"
	local deskCenter = Vector3.new(22, 0, 34)
	box("Desk", Vector3.new(11, 3.6, 3), deskCenter + Vector3.yAxis * 1.8, "NavyPanel", desk)
	box("Counter", Vector3.new(11.6, 0.25, 3.6), deskCenter + Vector3.yAxis * 3.725, "LightWood", desk)
	box("MonitorStand", Vector3.new(0.3, 0.8, 0.3), deskCenter + Vector3.new(-2, 4.25, 0.6), "Steel", desk)
	local screen = box("Monitor", Vector3.new(2.6, 1.6, 0.15), deskCenter + Vector3.new(-2, 5.3, 0.6), "Ceiling", desk)
	label(screen, Enum.NormalId.Front, `<font color="#78DCD2">WELCOME</font>`, Color3.new(1, 1, 1), Enum.Font.GothamBold, true)
	npc("Front desk", deskCenter + Vector3.new(0, 0, 3), Vector3.new(0, 0, -1), desk, Color3.fromRGB(26, 36, 70))

	-- Logo sign on the wall behind the desk.
	local sign = box("LogoSign", Vector3.new(20, 6, 0.4), Vector3.new(22, 15, Z1 - 0.4), "NavyPanel", desk, false)
	label(sign, Enum.NormalId.Front, `<font color="#FFD23F">{string.upper(Config.GameName)}</font><font color="#FF3DA5">!</font>`, Color3.new(1, 1, 1), Enum.Font.GothamBlack, true)
	RouteKit.addChalkBucket(desk, deskCenter + Vector3.new(-8, 0, -1))
	desk.Parent = model
end

---------------------------------------------------------------------------------------
-- Leaderboard wall

local function buildLeaderboardWall(model: Model)
	local wall = Instance.new("Model")
	wall.Name = "LeaderboardWall"
	local center = Vector3.new(-24, 11, Z1 - 0.3)
	local board = part({ name = "Board", size = Vector3.new(26, 13, 0.3), cframe = frameAt(center, Vector3.new(0, 0, -1), Vector3.yAxis), surface = "NavyPanel", collide = true, parent = wall })
	for _, spec in { { 0, 6.7, 26.6, 0.3 }, { 0, -6.7, 26.6, 0.3 }, { -13.15, 0, 0.3, 13.6 }, { 13.15, 0, 0.3, 13.6 } } do
		local bar = part({
			name = "Neon",
			size = Vector3.new(spec[3], spec[4], 0.3),
			cframe = board.CFrame * CFrame.new(spec[1], spec[2], -0.1),
			surface = "Neon",
			color = Color3.fromRGB(40, 220, 230),
			shadow = false,
			parent = wall,
		})
		bar.CastShadow = false
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "GymLeaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 12)
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 54
	title.TextColor3 = Color3.fromRGB(120, 240, 245)
	title.Text = "LEADERBOARD"
	title.Parent = gui
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(20, 84)
	grid.Size = UDim2.new(1, -40, 1, -100)
	grid.Parent = gui
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.25, -10, 0.5, -10)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	wall.Parent = model
end

---------------------------------------------------------------------------------------
-- Bouldering hall

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

local function buildBoulders(model: Model)
	local hall = Instance.new("Model")
	hall.Name = "BoulderingHall"
	box("RubberFloor", Vector3.new(46, 0.1, 58), Vector3.new(-39, 0.05, -7), "RubberFloor", hall, false)

	local monoliths = { Vector3.new(-50, 0, -22), Vector3.new(-28, 0, -22), Vector3.new(-50, 0, 8), Vector3.new(-28, 0, 8) }
	local height, width, depth = 14, 8, 8
	for m, center in monoliths do
		local monolith = Instance.new("Model")
		monolith.Name = `Monolith{m}`
		box("Core", Vector3.new(width, height, depth - 2), center + Vector3.yAxis * (height / 2), "NavyPanel", monolith)
		box("Cap", Vector3.new(width + 0.4, 0.4, depth - 1.6), center + Vector3.yAxis * (height + 0.2), "NavyPanel", monolith)

		for side = 0, 1 do
			local index = (m - 1) * 2 + side + 1
			local problem = PROBLEMS[index]
			local facing = if side == 0 then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
			local angle = if side == 0 then 12 else -6
			local origin = center + facing * (depth / 2)
			local face = Face.new(origin, facing, { { length = height, angle = angle } })
			local holds = RouteGenerator.generate({ seed = index * 1013, height = height, lineX = 0, wander = 0.8, difficulty = problem.difficulty })
			PanelWall.build(face, monolith, { width = width, holds = holds, tnutSpacing = 1.1 })
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
				baseY = 0,
				indoor = true,
			})
			-- Round crash mat and a painted number on the floor.
			local mat = part({
				name = "CrashMat",
				size = Vector3.new(0.8, 12, 12),
				cframe = CFrame.new(origin + facing * 4.5 + Vector3.yAxis * 0.4) * BuildUtil.AXIS_Y,
				surface = "MatVinyl",
				color = Color3.fromRGB(176, 186, 198),
				shape = Enum.PartType.Cylinder,
				collide = true,
				query = true,
				parent = monolith,
			})
			CollectionService:AddTag(mat, Tags.CrashMat)
			local number = part({
				name = "Number",
				size = Vector3.new(2.4, 0.02, 2.4),
				cframe = frameAt(origin + facing * 11.5 + Vector3.yAxis * 0.11, -facing, Vector3.yAxis),
				surface = "RubberFloor",
				shadow = false,
				parent = monolith,
			})
			number.Transparency = 1
			label(number, Enum.NormalId.Top, tostring(index), problem.color, Enum.Font.GothamBlack, false)
		end
		monolith.Parent = hall
	end
	RouteKit.addChalkBucket(hall, Vector3.new(-39, 0, -7))
	npc("Climber", Vector3.new(-39, 0, 2), Vector3.new(-1, 0, 0), hall, Color3.fromRGB(240, 200, 40))
	hall.Parent = model
end

---------------------------------------------------------------------------------------
-- Kilter room

local LED = {
	Start = Color3.fromRGB(70, 230, 110),
	Hand = Color3.fromRGB(60, 210, 240),
	Foot = Color3.fromRGB(255, 160, 40),
	Finish = Color3.fromRGB(240, 70, 200),
}

local function buildKilter(model: Model)
	local room = Instance.new("Model")
	room.Name = "KilterRoom"
	-- Glass partitions with a doorway.
	box("GlassWest", Vector3.new(0.3, 12, 32), Vector3.new(26, 6, -22), "Glass", room)
	box("GlassNorthA", Vector3.new(10, 12, 0.3), Vector3.new(31, 6, -6), "Glass", room)
	box("GlassNorthB", Vector3.new(18, 12, 0.3), Vector3.new(53, 6, -6), "Glass", room)
	local roomSign = box("RoomSign", Vector3.new(12, 2, 0.3), Vector3.new(40, 13, -6), "Ceiling", room, false)
	label(roomSign, Enum.NormalId.Back, `<font color="#3CD2F0">KILTER</font>`, Color3.new(1, 1, 1), Enum.Font.GothamBlack, true)

	-- The board: black, 40 degrees overhanging, on a steel frame over a big mat.
	local angle = 40
	local length = 14
	local face = Face.new(Vector3.new(44, 1.2, -30), Vector3.new(0, 0, 1), { { length = length, angle = angle } })
	PanelWall.build(face, room, { width = 12, plate = "Ceiling", tnutSpacing = 0 })
	local top = Face.top(face)
	for _, side in { -1, 1 } do
		BuildUtil.beam("FramePost", Vector3.new(44 + side * 6.4, 0, -31.5), Vector3.new(top.X + side * 6.4, top.Y + 0.5, top.Z - 1.5), 0.5, "LampHousing", room).CanCollide = true
		BuildUtil.beam("FrameLeg", Vector3.new(44 + side * 6.4, 0, -36), Vector3.new(top.X + side * 6.4, top.Y + 0.5, top.Z - 1.5), 0.4, "LampHousing", room).CanCollide = true
	end
	local mat = box("KilterMat", Vector3.new(18, 1, 16), Vector3.new(44, 0.5, -22), "MatVinyl", room)
	CollectionService:AddTag(mat, Tags.CrashMat)

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
	-- LED rings behind the lit holds.
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
		local light = Instance.new("PointLight")
		light.Color = LED[kind]
		light.Range = 3
		light.Brightness = 1.2
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
	box("KioskPost", Vector3.new(0.5, 3.4, 0.5), Vector3.new(33, 1.7, -14), "LampHousing", room)
	local screen = part({
		name = "KioskScreen",
		size = Vector3.new(2.4, 1.6, 0.15),
		cframe = CFrame.new(33, 3.8, -14) * CFrame.Angles(math.rad(-25), math.rad(200), 0),
		surface = "Ceiling",
		collide = true,
		query = true,
		parent = room,
	})
	label(screen, Enum.NormalId.Front, `<font color="#FFFFFF"><b>KILTER</b></font>\nFirst Light  <font color="#5CE65C">V2</font>\n<font color="#3CD2F0">Board 40°</font>`, Color3.new(1, 1, 1), Enum.Font.GothamMedium, true)
	room.Parent = model
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
	buildBoulders(model)
	buildKilter(model)
	model.Parent = Workspace
	return model
end

function Gym.Ensure(): Instance
	hideLegacy()
	return Gym.Find() or Gym.Build()
end

function Gym.Rebuild(): Model
	local existing = Gym.Find()
	if existing then
		existing:Destroy()
	end
	return Gym.Build()
end

return Gym
