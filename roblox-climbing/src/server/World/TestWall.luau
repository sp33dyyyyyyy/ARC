--!strict
-- TestWall: builds the Stage 1 practice wall at Workspace.Routes.TestWall.
--
-- Runs automatically on server start if the wall is missing. To build it in edit mode
-- (so it is saved in the place and you can tweak it by hand), run in the command bar:
--     require(game.ServerScriptService.Server.World.TestWall).Rebuild()
--
-- Result:
--   Workspace.Routes.TestWall           Folder (RouteName, Grade, HeightStuds, HeightMeters, Indoor)
--     Wall        Part, tagged Climbable
--     Holds/      20 Parts tagged Hold (HoldType, Quality, HandOK, FootOK, HoldId, Role)
--     CrashMat    Part
--     StartPad    Part, tagged RouteStart
--     TopLedge    Part to stand on after topping out
--     Summit      invisible Part, tagged RouteSummit
--     Legend      sign listing the hold colours
--   Workspace.TestFloor / Workspace.TestSpawn   only if the place has no floor / spawn

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HoldTypes = require(Shared.HoldTypes)
local Tags = require(Shared.Tags)
local Layout = require(script.Parent.TestWallLayout)

local WALL = Config.TestWall

-- Look of each hold type on the test wall. Colour-coded by type so testers can tell
-- them apart; real routes (Stage 8) colour by problem instead.
type HoldLook = { size: Vector3, color: Color3, ellipsoid: boolean, embed: number }
local LOOKS: { [string]: HoldLook } = {
	Jug = { size = Vector3.new(1.3, 0.9, 0.8), color = Color3.fromRGB(60, 200, 90), ellipsoid = true, embed = 0.2 },
	Edge = { size = Vector3.new(1.4, 0.35, 0.45), color = Color3.fromRGB(250, 215, 50), ellipsoid = false, embed = 0 },
	Crimp = { size = Vector3.new(0.9, 0.28, 0.32), color = Color3.fromRGB(230, 60, 60), ellipsoid = false, embed = 0 },
	Sloper = { size = Vector3.new(1.5, 1.1, 0.6), color = Color3.fromRGB(60, 130, 240), ellipsoid = true, embed = 0.15 },
	Pinch = { size = Vector3.new(0.5, 1.2, 0.6), color = Color3.fromRGB(220, 60, 200), ellipsoid = true, embed = 0.1 },
	Pocket = { size = Vector3.new(0.8, 0.8, 0.5), color = Color3.fromRGB(245, 150, 40), ellipsoid = true, embed = 0.1 },
	Foothold = { size = Vector3.new(0.6, 0.4, 0.4), color = Color3.fromRGB(70, 70, 80), ellipsoid = false, embed = 0 },
	Crack = { size = Vector3.new(0.35, 2.4, 0.3), color = Color3.fromRGB(30, 30, 35), ellipsoid = false, embed = 0 },
}

local MAT_THICKNESS = 0.8

local TestWall = {}

export type WallFrame = {
	origin: Vector3, -- bottom-centre of the climbing face
	right: Vector3, -- climber's right when facing the wall
	up: Vector3, -- up along the (possibly tilted) face
	normal: Vector3, -- out of the face, towards the climber
	flatNormal: Vector3, -- horizontal facing direction (ignores tilt)
}

function TestWall.getFrame(): WallFrame
	local flatNormal = Vector3.new(WALL.Facing.X, 0, WALL.Facing.Z).Unit
	local angle = math.rad(WALL.AngleDegrees)
	local worldUp = Vector3.yAxis
	-- Positive angle leans the top towards the climber (overhang).
	local up = worldUp * math.cos(angle) + flatNormal * math.sin(angle)
	local normal = flatNormal * math.cos(angle) - worldUp * math.sin(angle)
	return {
		origin = WALL.Origin,
		right = up:Cross(normal),
		up = up,
		normal = normal,
		flatNormal = flatNormal,
	}
end

-- CFrame whose LookVector is `look` and UpVector is `up` (both unit, perpendicular).
local function frameAt(position: Vector3, look: Vector3, up: Vector3): CFrame
	return CFrame.fromMatrix(position, up:Cross(-look), up, -look)
end

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function buildHold(spec: Layout.HoldSpec, index: number, frame: WallFrame, parent: Instance)
	local def = HoldTypes.get(spec.type)
	local look = LOOKS[spec.type]
	assert(def and look, `TestWallLayout hold {index} has unknown type {spec.type}`)

	local surfacePoint = frame.origin + frame.right * spec.x + frame.up * spec.y
	local center = surfacePoint + frame.normal * (look.size.Z / 2 - look.embed)
	local cframe = frameAt(center, frame.normal, frame.up) * CFrame.Angles(0, 0, math.rad(spec.rotation or 0))

	local part = newPart(string.format("%02d_%s", index, spec.type), look.size, cframe, look.color, Enum.Material.SmoothPlastic)
	part.CanCollide = false -- the climber is held by constraints (Stage 2), not by standing on holds
	if look.ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end

	part:SetAttribute("HoldId", string.format("%s_%02d", WALL.FolderName, index))
	part:SetAttribute("HoldType", def.Name)
	part:SetAttribute("Quality", spec.quality or def.DefaultQuality)
	part:SetAttribute("HandOK", def.HandOK)
	part:SetAttribute("FootOK", def.FootOK)
	if spec.role then
		part:SetAttribute("Role", spec.role)
	end
	CollectionService:AddTag(part, Tags.Hold)
	part.Parent = parent
end

local function buildLegend(frame: WallFrame, parent: Instance)
	local position = frame.origin + frame.right * (Layout.Width / 2 + 3) + Vector3.yAxis * 4.5 + frame.flatNormal * 0.5
	local sign = newPart("Legend", Vector3.new(5, 7, 0.3), frameAt(position, frame.flatNormal, Vector3.yAxis), Color3.fromRGB(20, 28, 48), Enum.Material.SmoothPlastic)
	sign.Parent = parent

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = sign

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 16)
	padding.Parent = gui

	local function label(text: string, order: number, size: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -16, 0, size + 8)
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text
		l.RichText = true
		l.LayoutOrder = order
		l.Parent = gui
	end

	label(string.upper(WALL.RouteName), 0, 30, Color3.new(1, 1, 1))
	label(`{#Layout.Holds} holds · press H to inspect`, 1, 18, Color3.fromRGB(120, 220, 210))
	for i, name in HoldTypes.Names do
		local def = HoldTypes.get(name) :: HoldTypes.HoldTypeDef
		local hex = LOOKS[name].color:ToHex()
		local uses = if def.HandOK and def.FootOK then "hands + feet" elseif def.HandOK then "hands" else "feet"
		label(`<font color="#{hex}">■</font> {name}  <font color="#9aa4b8">{uses}</font>`, 1 + i, 20, Color3.new(1, 1, 1))
	end
end

local function ensureFloorAndSpawn(frame: WallFrame, route: Instance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { route }
	local probe = frame.origin + frame.flatNormal * 12
	if Workspace:Raycast(probe + Vector3.yAxis * 5, Vector3.yAxis * -20, params) == nil then
		local floor = newPart("TestFloor", Vector3.new(80, 2, 80), CFrame.new(probe - Vector3.yAxis), Color3.fromRGB(120, 124, 132), Enum.Material.Concrete)
		floor.Parent = Workspace
	end

	if Workspace:FindFirstChildWhichIsA("SpawnLocation", true) == nil then
		local position = frame.origin + frame.flatNormal * 22 + Vector3.yAxis * 0.5
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "TestSpawn"
		spawn.Size = Vector3.new(6, 1, 6)
		-- Face the wall so players spawn looking at it.
		spawn.CFrame = frameAt(position, -frame.flatNormal, Vector3.yAxis)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Color = Color3.fromRGB(20, 20, 24)
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.Parent = Workspace
	end
end

function TestWall.Find(): Instance?
	local routes = Workspace:FindFirstChild("Routes")
	return routes and routes:FindFirstChild(WALL.FolderName)
end

function TestWall.Build(): Folder
	assert(TestWall.Find() == nil, "TestWall already exists; use TestWall.Rebuild()")
	local frame = TestWall.getFrame()

	local routes = Workspace:FindFirstChild("Routes")
	if routes == nil then
		routes = Instance.new("Folder")
		routes.Name = "Routes"
		routes.Parent = Workspace
	end

	local route = Instance.new("Folder")
	route.Name = WALL.FolderName
	route:SetAttribute("RouteName", WALL.RouteName)
	route:SetAttribute("Grade", WALL.Grade)
	route:SetAttribute("HeightStuds", Layout.Height)
	route:SetAttribute("HeightMeters", math.round(Config.studsToMeters(Layout.Height) * 100) / 100)
	route:SetAttribute("Indoor", true)

	-- Wall: Front face (LookVector) is the climbing face.
	local wallCenter = frame.origin + frame.up * (Layout.Height / 2) - frame.normal * (Layout.Thickness / 2)
	local wall = newPart("Wall", Vector3.new(Layout.Width, Layout.Height, Layout.Thickness), frameAt(wallCenter, frame.normal, frame.up), Color3.fromRGB(242, 243, 245), Enum.Material.SmoothPlastic)
	wall:SetAttribute("WallAngle", WALL.AngleDegrees)
	CollectionService:AddTag(wall, Tags.Climbable)
	wall.Parent = route

	local holds = Instance.new("Folder")
	holds.Name = "Holds"
	holds.Parent = route
	for index, spec in Layout.Holds do
		buildHold(spec, index, frame, holds)
	end

	local matDepth = 8
	local matCenter = frame.origin + frame.flatNormal * (matDepth / 2) + Vector3.yAxis * (MAT_THICKNESS / 2)
	local mat = newPart("CrashMat", Vector3.new(Layout.Width + 4, MAT_THICKNESS, matDepth), frameAt(matCenter, frame.flatNormal, Vector3.yAxis), Color3.fromRGB(36, 62, 140), Enum.Material.Fabric)
	mat.Parent = route

	local padCenter = frame.origin + frame.flatNormal * 2.5 + Vector3.yAxis * (MAT_THICKNESS + 0.06)
	local pad = newPart("StartPad", Vector3.new(6, 0.1, 3), frameAt(padCenter, frame.flatNormal, Vector3.yAxis), Color3.fromRGB(70, 230, 140), Enum.Material.Neon)
	pad.CanCollide = false
	pad.CanTouch = true
	pad.Transparency = 0.35
	CollectionService:AddTag(pad, Tags.RouteStart)
	pad.Parent = route

	local top = frame.origin + frame.up * Layout.Height
	local ledgeCenter = top - frame.flatNormal * 3.5 + Vector3.yAxis * 0.5
	local ledge = newPart("TopLedge", Vector3.new(Layout.Width, 1, 6), frameAt(ledgeCenter, frame.flatNormal, Vector3.yAxis), Color3.fromRGB(28, 40, 72), Enum.Material.SmoothPlastic)
	ledge.Parent = route

	local summitCenter = top + Vector3.yAxis * 2.5 - frame.flatNormal * 1.5
	local summit = newPart("Summit", Vector3.new(Layout.Width, 4, 5), frameAt(summitCenter, frame.flatNormal, Vector3.yAxis), Color3.fromRGB(150, 110, 255), Enum.Material.ForceField)
	summit.Transparency = 1
	summit.CanCollide = false
	summit.CanQuery = false
	summit.CanTouch = true
	CollectionService:AddTag(summit, Tags.RouteSummit)
	summit.Parent = route

	buildLegend(frame, route)

	route.Parent = routes
	ensureFloorAndSpawn(frame, route)
	return route
end

function TestWall.Ensure(): Instance
	return TestWall.Find() or TestWall.Build()
end

function TestWall.Rebuild(): Folder
	local existing = TestWall.Find()
	if existing then
		existing:Destroy()
	end
	return TestWall.Build()
end

return TestWall
