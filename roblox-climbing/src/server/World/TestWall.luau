--!strict
-- TestWall: builds the Stage 1 practice wall at Workspace.Routes.TestWall, styled like a
-- real gym training wall.
--
-- Runs automatically on server start if the wall is missing. To build it in edit mode
-- (so it is saved in the place and you can tweak it by hand), run in the command bar:
--     require(game.ServerScriptService.Server.World.TestWall).Rebuild()
--
-- Result:
--   Workspace.Routes.TestWall          Folder (RouteName, Grade, HeightStuds, HeightMeters, Indoor)
--     Wall         painted face plate, tagged Climbable
--     WallCore     birch plywood behind it (visible on the edges)
--     Panels/      panel seams          TNuts/   bolt-on hole grid
--     Holds/       20 holds tagged Hold (HoldType, Quality, HandOK, FootOK, HoldId, Role)
--     Frame/       steel posts, beams and braces behind the wall
--     CrashMat     Model: vinyl mat segments, seam covers, front bevel
--     StartMarker  taped start box on the mat     StartPad  invisible volume, tagged RouteStart
--     TopOut/      TopLedge deck + safety rail     Summit    invisible volume, tagged RouteSummit
--     LightRig/    arms, bar and LED floodlights (SpotLights)
--     Legend       sign on posts listing the hold colours
--   Workspace.TestFloor / Workspace.TestSpawn   only if the place has no floor / spawn

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HoldTypes = require(Shared.HoldTypes)
local Tags = require(Shared.Tags)

local BuildUtil = require(script.Parent.BuildUtil)
local HoldModels = require(script.Parent.HoldModels)
local RouteKit = require(script.Parent.RouteKit)
local Layout = require(script.Parent.TestWallLayout)

local WALL = Config.TestWall
local part = BuildUtil.part
local frameAt = BuildUtil.frameAt

local FACE_THICKNESS = 0.2 -- painted face plate; the rest of Layout.Thickness is plywood
local PANEL_WIDTH = 4 -- real walls use 1.22 m x 2.44 m sheets (about 4 x 8 studs)
local PANEL_HEIGHT = 8
local TNUT_SPACING = 0.8 -- about 22 cm, like a real bolt-on grid
local MAT_THICKNESS = 0.8
local MAT_DEPTH = 8
local MAT_SEGMENTS = 3
local START_TAPE_COLOR = Color3.fromRGB(70, 200, 120)

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

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Point on the climbing face: `x` right, `y` up, `out` studs in front of it.
local function facePoint(frame: WallFrame, x: number, y: number, out: number): Vector3
	return frame.origin + frame.right * x + frame.up * y + frame.normal * out
end

local function buildWallBody(frame: WallFrame, route: Instance): BasePart
	local width, height = Layout.Width, Layout.Height
	local coreThickness = Layout.Thickness - FACE_THICKNESS

	local wall = part({
		name = "Wall",
		size = Vector3.new(width, height, FACE_THICKNESS),
		cframe = frameAt(facePoint(frame, 0, height / 2, -FACE_THICKNESS / 2), frame.normal, frame.up),
		surface = "WallPaint",
		collide = true,
		query = true,
		parent = route,
	})
	wall:SetAttribute("WallAngle", WALL.AngleDegrees)
	CollectionService:AddTag(wall, Tags.Climbable)

	part({
		name = "WallCore",
		size = Vector3.new(width, height, coreThickness),
		cframe = frameAt(facePoint(frame, 0, height / 2, -FACE_THICKNESS - coreThickness / 2), frame.normal, frame.up),
		surface = "Plywood",
		collide = true,
		query = true,
		parent = route,
	})

	-- Panel seams: very shallow so nothing else on the face shares their depth. Horizontal
	-- seams are shallower than vertical ones so the crossings don't flicker.
	local panels = folder("Panels", route)
	local seamDepth = 0.006
	local seamDepthH = 0.004
	for x = -width / 2 + PANEL_WIDTH, width / 2 - PANEL_WIDTH, PANEL_WIDTH do
		part({
			name = "SeamV",
			size = Vector3.new(0.05, height, seamDepth),
			cframe = frameAt(facePoint(frame, x, height / 2, seamDepth / 2), frame.normal, frame.up),
			surface = "PanelSeam",
			shadow = false,
			parent = panels,
		})
	end
	for y = PANEL_HEIGHT, height - PANEL_HEIGHT, PANEL_HEIGHT do
		part({
			name = "SeamH",
			size = Vector3.new(width, 0.05, seamDepthH),
			cframe = frameAt(facePoint(frame, 0, y, seamDepthH / 2), frame.normal, frame.up),
			surface = "PanelSeam",
			shadow = false,
			parent = panels,
		})
	end
	return wall
end

type Footprint = { x: number, y: number, halfX: number, halfY: number }

-- Bolt-on hole grid, skipping spots covered by a hold.
local function buildTNuts(frame: WallFrame, route: Instance, covered: { Footprint })
	local tnuts = folder("TNuts", route)
	local half = Layout.Width / 2 - TNUT_SPACING / 2
	-- Grid offset by half a spacing from the panel seams, and starting above the mat.
	for y = MAT_THICKNESS + TNUT_SPACING / 2, Layout.Height - TNUT_SPACING / 2, TNUT_SPACING do
		for x = -half, half + 1e-6, TNUT_SPACING do
			local hidden = false
			for _, f in covered do
				if math.abs(x - f.x) < f.halfX and math.abs(y - f.y) < f.halfY then
					hidden = true
					break
				end
			end
			if not hidden then
				part({
					name = "TNut",
					size = Vector3.new(0.01, 0.12, 0.12),
					cframe = frameAt(facePoint(frame, x, y, 0.005), frame.normal, frame.up) * BuildUtil.AXIS_Z,
					surface = "TNut",
					shape = Enum.PartType.Cylinder,
					shadow = false,
					parent = tnuts,
				})
			end
		end
	end
end

local function buildHolds(frame: WallFrame, route: Instance): { Footprint }
	local holds = folder("Holds", route)
	local covered: { Footprint } = {}
	for index, spec in Layout.Holds do
		local def = HoldTypes.get(spec.type)
		local look = HoldModels.getLook(spec.type)
		assert(def and look, `TestWallLayout hold {index} has unknown type {spec.type}`)

		local surfaceCFrame = frameAt(facePoint(frame, spec.x, spec.y, 0), frame.normal, frame.up)
			* CFrame.Angles(0, 0, math.rad(spec.rotation or 0))
		local hold = HoldModels.build(spec.type, surfaceCFrame, spec.role, START_TAPE_COLOR, index)
		hold.Name = string.format("%02d_%s", index, spec.type)
		hold:SetAttribute("HoldId", string.format("%s_%02d", WALL.FolderName, index))
		hold:SetAttribute("HoldType", def.Name)
		hold:SetAttribute("Quality", spec.quality or def.DefaultQuality)
		hold:SetAttribute("HandOK", def.HandOK)
		hold:SetAttribute("FootOK", def.FootOK)
		if spec.role then
			hold:SetAttribute("Role", spec.role)
		end
		CollectionService:AddTag(hold, Tags.Hold)
		hold.Parent = holds

		table.insert(covered, { x = spec.x, y = spec.y, halfX = look.footprint.X + 0.1, halfY = look.footprint.Y + 0.1 })
	end
	return covered
end

-- Steel posts bolted to the back of the wall, with diagonal braces to the floor.
local function buildFrame(frame: WallFrame, route: Instance)
	local steel = folder("Frame", route)
	local backOffset = -Layout.Thickness
	local postDepth = 0.35
	-- Posts stop below the top-out deck so their tops don't share its surface.
	local postHeight = Layout.Height - 0.6
	for _, x in { -Layout.Width / 2 + 1, 0, Layout.Width / 2 - 1 } do
		part({
			name = "Post",
			size = Vector3.new(0.5, postHeight, postDepth),
			cframe = frameAt(facePoint(frame, x, postHeight / 2, backOffset - postDepth / 2), frame.normal, frame.up),
			surface = "Steel",
			collide = true,
			parent = steel,
		})

		local braceTop = facePoint(frame, x, Layout.Height * 0.7, backOffset - postDepth)
		local braceFoot = Vector3.new(braceTop.X, 0.2, braceTop.Z) - frame.flatNormal * (Layout.Height * 0.45)
		local brace = BuildUtil.beam("Brace", braceTop, braceFoot, 0.35, "Steel", steel)
		brace.CanCollide = true
		part({
			name = "BasePlate",
			size = Vector3.new(1, 0.15, 1),
			cframe = CFrame.new(braceFoot.X, 0.075, braceFoot.Z),
			surface = "Steel",
			parent = steel,
		})
	end
	for _, y in { PANEL_HEIGHT, PANEL_HEIGHT * 2 } do
		part({
			name = "Rail",
			size = Vector3.new(Layout.Width, 0.4, 0.3),
			cframe = frameAt(facePoint(frame, 0, y, backOffset - postDepth - 0.15), frame.normal, frame.up),
			surface = "Steel",
			collide = true,
			parent = steel,
		})
	end
end

local function buildCrashMat(frame: WallFrame, route: Instance)
	local mat = Instance.new("Model")
	mat.Name = "CrashMat"
	local totalWidth = Layout.Width + 4
	local gap = 0.06
	local segmentWidth = (totalWidth - gap * (MAT_SEGMENTS - 1)) / MAT_SEGMENTS
	local flatRight = Vector3.yAxis:Cross(frame.flatNormal)
	local base = frame.origin + frame.flatNormal * (MAT_DEPTH / 2)

	for i = 1, MAT_SEGMENTS do
		local offset = -totalWidth / 2 + segmentWidth / 2 + (i - 1) * (segmentWidth + gap)
		part({
			name = `Segment{i}`,
			size = Vector3.new(segmentWidth, MAT_THICKNESS, MAT_DEPTH),
			cframe = frameAt(base + flatRight * offset + Vector3.yAxis * (MAT_THICKNESS / 2), frame.flatNormal, Vector3.yAxis),
			surface = "MatVinyl",
			collide = true,
			query = true,
			parent = mat,
		})
		if i < MAT_SEGMENTS then
			-- Velcro cover strip over the joint, like real bouldering mats.
			part({
				name = "SeamCover",
				size = Vector3.new(0.5, 0.03, MAT_DEPTH),
				cframe = frameAt(base + flatRight * (offset + segmentWidth / 2 + gap / 2) + Vector3.yAxis * (MAT_THICKNESS + 0.015), frame.flatNormal, Vector3.yAxis),
				surface = "MatSeamCover",
				query = true,
				parent = mat,
			})
		end
	end

	-- Sloped front edge so you don't trip on the mat.
	local bevelDepth = 1.2
	part({
		name = "FrontBevel",
		size = Vector3.new(totalWidth, MAT_THICKNESS, bevelDepth),
		cframe = frameAt(frame.origin + frame.flatNormal * (MAT_DEPTH + bevelDepth / 2) + Vector3.yAxis * (MAT_THICKNESS / 2), frame.flatNormal, Vector3.yAxis),
		surface = "MatVinyl",
		wedge = true,
		collide = true,
		query = true,
		parent = mat,
	})
	for _, piece in mat:GetChildren() do
		CollectionService:AddTag(piece, Tags.CrashMat) -- softens falls (RagdollService)
	end
	mat.Parent = route
end

local function buildStart(frame: WallFrame, route: Instance)
	local center = frame.origin + frame.flatNormal * 2.5 + Vector3.yAxis * MAT_THICKNESS
	local markerCFrame = frameAt(center + Vector3.yAxis * 0.006, frame.flatNormal, Vector3.yAxis)
	local width, depth, tape = 6, 3, 0.15

	-- Taped box on the mat, the way setters mark a start zone.
	local marker = folder("StartMarker", route)
	for i, offset in { Vector3.new(0, 0, depth / 2), Vector3.new(0, 0, -depth / 2), Vector3.new(width / 2, 0, 0), Vector3.new(-width / 2, 0, 0) } do
		-- The side strips stop where the long strips start so no two tapes overlap (z-fighting).
		local alongX = i <= 2
		part({
			name = "Tape",
			size = if alongX then Vector3.new(width + tape, 0.012, tape) else Vector3.new(tape, 0.012, depth - tape),
			cframe = markerCFrame * CFrame.new(offset),
			surface = "Tape",
			color = START_TAPE_COLOR,
			shadow = false,
			parent = marker,
		})
	end

	-- Invisible trigger volume over the box, used from Stage 5 to start the timer.
	local startPad = part({
		name = "StartPad",
		size = Vector3.new(width, 5, depth),
		cframe = frameAt(center + Vector3.yAxis * 2.5, frame.flatNormal, Vector3.yAxis),
		surface = "Tape",
		shadow = false,
		parent = route,
	})
	startPad.Transparency = 1
	startPad.CanTouch = true
	CollectionService:AddTag(startPad, Tags.RouteStart)
end

-- Deck behind the top of the wall (flush with it) with a safety rail, and the summit volume.
local function buildTopOut(frame: WallFrame, route: Instance)
	local topOut = folder("TopOut", route)
	local deckDepth, deckThickness = 6, 0.5
	local topBack = facePoint(frame, 0, Layout.Height, -Layout.Thickness)
	local deckCenter = topBack - frame.flatNormal * (deckDepth / 2) - Vector3.yAxis * (deckThickness / 2)
	part({
		name = "TopLedge",
		size = Vector3.new(Layout.Width, deckThickness, deckDepth),
		cframe = frameAt(deckCenter, frame.flatNormal, Vector3.yAxis),
		surface = "DeckBoards",
		collide = true,
		query = true,
		parent = topOut,
	})

	local flatRight = Vector3.yAxis:Cross(frame.flatNormal)
	local railBack = topBack - frame.flatNormal * (deckDepth - 0.3)
	local postXs = { -Layout.Width / 2 + 0.3, -Layout.Width / 6, Layout.Width / 6, Layout.Width / 2 - 0.3 }
	for _, x in postXs do
		local foot = railBack + flatRight * x
		BuildUtil.pipe("RailPost", foot, foot + Vector3.yAxis * 3.6, 0.2, "Steel", topOut).CanCollide = true
	end
	for _, h in { 1.8, 3.6 } do
		local a = railBack + flatRight * postXs[1] + Vector3.yAxis * h
		local b = railBack + flatRight * postXs[#postXs] + Vector3.yAxis * h
		BuildUtil.pipe("Rail", a, b, 0.18, "Steel", topOut).CanCollide = true
	end

	local top = facePoint(frame, 0, Layout.Height, 0)
	local summit = part({
		name = "Summit",
		size = Vector3.new(Layout.Width, 4, 5),
		cframe = frameAt(top + Vector3.yAxis * 2.5 - frame.flatNormal * 1.5, frame.flatNormal, Vector3.yAxis),
		surface = "Tape",
		shadow = false,
		parent = route,
	})
	summit.Transparency = 1
	summit.CanTouch = true
	CollectionService:AddTag(summit, Tags.RouteSummit)
end

-- Arms off the top of the wall carrying a bar of LED floodlights aimed back at the face.
local function buildLightRig(frame: WallFrame, route: Instance)
	local rig = folder("LightRig", route)
	local reach, rise = 6, 1.5
	local armX = Layout.Width / 2 - 1
	local ends = {}
	for _, x in { -armX, armX } do
		local root = facePoint(frame, x, Layout.Height, -Layout.Thickness / 2)
		local tip = root + frame.flatNormal * reach + Vector3.yAxis * rise
		BuildUtil.beam("Arm", root, tip, 0.3, "Steel", rig)
		table.insert(ends, tip)
	end
	BuildUtil.pipe("Bar", ends[1], ends[2], 0.25, "Steel", rig)

	for _, x in { -5, 0, 5 } do
		local t = (x + armX) / (2 * armX)
		local mount = ends[1]:Lerp(ends[2], t) - Vector3.yAxis * 0.6
		local target = facePoint(frame, x * 0.6, Layout.Height * 0.42, 0)
		local housingCFrame = CFrame.lookAt(mount, target)
		-- No shadow on the housing or lens, or they would block their own SpotLight.
		local housing = part({
			name = "Floodlight",
			size = Vector3.new(1.0, 0.7, 0.35),
			cframe = housingCFrame,
			surface = "LampHousing",
			shadow = false,
			parent = rig,
		})
		part({
			name = "Lens",
			size = Vector3.new(0.86, 0.56, 0.02),
			cframe = housingCFrame * CFrame.new(0, 0, -0.18),
			surface = "LampLens",
			shadow = false,
			parent = housing,
		})
		BuildUtil.pipe("Hanger", mount, mount + Vector3.yAxis * 0.6, 0.08, "Steel", rig)

		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 90
		light.Range = 30
		light.Brightness = 0.7
		light.Color = Color3.fromRGB(255, 244, 226)
		light.Shadows = true
		light.Parent = housing
	end
end

-- Route sign on two posts. Sized so all 10 lines fit (8 studs = 400 px at 50 px/stud).
local function buildLegend(frame: WallFrame, route: Instance)
	local flatRight = Vector3.yAxis:Cross(frame.flatNormal)
	local width, height, bottom = 5, 8, 1.2
	-- Beside the crash mat (it runs 2 studs past each side of the wall), not on it.
	local center = frame.origin + flatRight * (Layout.Width / 2 + 4.6) + frame.flatNormal * 0.8 + Vector3.yAxis * (bottom + height / 2)
	local cframe = frameAt(center, frame.flatNormal, Vector3.yAxis)

	local sign = part({
		name = "Legend",
		size = Vector3.new(width, height, 0.15),
		cframe = cframe,
		surface = "SignBoard",
		collide = true,
		parent = route,
	})
	part({
		name = "Backing",
		size = Vector3.new(width + 0.3, height + 0.3, 0.12),
		cframe = cframe * CFrame.new(0, 0, 0.135),
		surface = "Plywood",
		parent = sign,
	})
	for _, x in { -width / 2 + 0.6, width / 2 - 0.6 } do
		local foot = (cframe * CFrame.new(x, 0, 0.3)).Position
		foot = Vector3.new(foot.X, 0, foot.Z)
		BuildUtil.pipe("SignPost", foot, foot + Vector3.yAxis * (bottom + height), 0.2, "Steel", sign).CanCollide = true
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.3
	gui.Parent = sign

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingTop = UDim.new(0, 18)
	padding.Parent = gui

	local function label(text: string, order: number, size: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -18, 0, size + 8)
		l.Font = Enum.Font.Sarpanch
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text
		l.RichText = true
		l.LayoutOrder = order
		l.Parent = gui
	end

	label(string.upper(WALL.RouteName), 0, 30, Color3.new(1, 1, 1))
	label(`{WALL.Grade} · {#Layout.Holds} holds · press H to inspect`, 1, 18, Color3.fromRGB(120, 220, 210))
	for i, name in HoldTypes.Names do
		local def = HoldTypes.get(name) :: HoldTypes.HoldTypeDef
		local look = HoldModels.getLook(name)
		local hex = if look then look.color:ToHex() else "ffffff"
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
		part({
			name = "TestFloor",
			size = Vector3.new(80, 2, 80),
			cframe = CFrame.new(probe - Vector3.yAxis),
			surface = "Floor",
			collide = true,
			query = true,
			parent = Workspace,
		})
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
		spawn.Material = Enum.Material.Rubber
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
	route:SetAttribute("BaseY", frame.origin.Y) -- floor level; the height counter measures from here
	route:SetAttribute("Order", 1)
	route:SetAttribute("AutoBelay", true) -- clip in at the carabiner; letting go lowers you gently (RopeService)
	route:SetAttribute("Rope", false)
	route:SetAttribute("Leaderboard", true)
	route:SetAttribute("StartPosition", frame.origin + frame.flatNormal * 4 + Vector3.yAxis * (MAT_THICKNESS + 3))
	route:SetAttribute("TopAnchor", facePoint(frame, 0, Layout.Height + 1.5, -0.5))

	buildWallBody(frame, route)
	local covered = buildHolds(frame, route)
	buildTNuts(frame, route, covered)
	buildFrame(frame, route)
	buildCrashMat(frame, route)
	buildStart(frame, route)
	buildTopOut(frame, route)
	buildLightRig(frame, route)
	buildLegend(frame, route)
	-- Sign and chalk bucket stand on the floor beside the crash mat, not half inside it.
	RouteKit.addSign(route, frame.origin - frame.right * (Layout.Width / 2 + 4.6) + frame.flatNormal * 1.5, frame.flatNormal, string.upper(WALL.RouteName))
	RouteKit.addChalkBucket(route, frame.origin - frame.right * (Layout.Width / 2 + 3) + frame.flatNormal * 5)
	RouteKit.addAutoBelay(route, frame.origin + Vector3.yAxis * MAT_THICKNESS, facePoint(frame, 0, Layout.Height, 0), frame.flatNormal)

	-- Parent last so everything replicates and is tagged in one go.
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
