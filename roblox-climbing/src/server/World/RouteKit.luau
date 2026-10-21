--!strict
-- RouteKit: everything a route needs, built the same way on every wall in the game.
--
-- buildRoute() makes Workspace.Routes.<id> with:
--   attributes  RouteName, Grade, Order, HeightStuds (vertical rise), HeightMeters, BaseY,
--               Indoor, AutoBelay, Rope, Leaderboard, StartPosition, TopAnchor
--   Holds/      the route's holds (tagged Hold, HoldId "<id>_<n>")
--   StartPad    invisible volume at the base (RouteStart)
--   Summit      invisible volume at the top (RouteSummit)
--   Sign        leaderboard board at the base (LeaderboardService writes on it)
--   RopeBag     "Tie in" prompt at the base, for walls you rope up on (RopeService)
--   AutoBelay   unit at the top and a "Clip in" carabiner at the base (indoor rope walls)
--   ChalkBucket "Chalk up" prompt at the base (ChalkService)
-- The helpers are also used on their own by TestWall and the gym.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HoldTypes = require(Shared.HoldTypes)
local Tags = require(Shared.Tags)

local BuildUtil = require(script.Parent.BuildUtil)
local Face = require(script.Parent.Face)
local HoldModels = require(script.Parent.HoldModels)

local part = BuildUtil.part
local frameAt = BuildUtil.frameAt

export type HoldSpec = {
	x: number,
	y: number,
	type: string,
	quality: number?,
	role: string?,
	rotation: number?,
}

export type RouteSpec = {
	id: string, -- folder name and HoldId prefix (no spaces)
	name: string,
	grade: string,
	order: number,
	face: Face.Face,
	lineX: number, -- where the route starts along the wall (for its base furniture)
	topX: number?, -- where it finishes (defaults to the last hold)
	holds: { HoldSpec },
	style: ("plastic" | "rock")?,
	color: Color3?, -- one colour for every hold (gym problems)
	baseY: number?, -- ground level (defaults to the face's bottom)
	indoor: boolean?,
	autoBelay: boolean?, -- letting go lowers you gently (gym walls)
	rope: boolean?, -- has a rope bag to tie in (outdoor walls)
	leaderboard: boolean?,
	chalk: boolean?,
	signSide: number?, -- +1 puts the sign right of the route (default), -1 left
}

local RouteKit = {}

function RouteKit.routesFolder(): Folder
	local routes = Workspace:FindFirstChild("Routes")
	if routes == nil then
		routes = Instance.new("Folder")
		routes.Name = "Routes"
		routes.Parent = Workspace
	end
	return routes :: Folder
end

-- Puts holds on `face` from `specs` into `parent`, tagged and with the standard attributes.
function RouteKit.buildHolds(face: Face.Face, specs: { HoldSpec }, parent: Instance, idPrefix: string, options: HoldModels.Options)
	for index, spec in specs do
		local def = HoldTypes.get(spec.type)
		assert(def, `{idPrefix}: hold {index} has unknown type {spec.type}`)
		local surface = Face.frame(face, spec.x, spec.y) * CFrame.Angles(0, 0, math.rad(spec.rotation or 0))
		local hold = HoldModels.buildStyled(spec.type, surface, {
			role = spec.role,
			tapeColor = options.tapeColor or options.color,
			markLayer = index,
			style = options.style,
			color = options.color,
		})
		hold.Name = string.format("%03d_%s", index, spec.type)
		hold:SetAttribute("HoldId", `{idPrefix}_{index}`)
		hold:SetAttribute("HoldType", def.Name)
		hold:SetAttribute("Quality", spec.quality or def.DefaultQuality)
		hold:SetAttribute("HandOK", def.HandOK)
		hold:SetAttribute("FootOK", def.FootOK)
		if spec.role then
			hold:SetAttribute("Role", spec.role)
		end
		CollectionService:AddTag(hold, Tags.Hold)
		hold.Parent = parent
	end
end

-- Leaderboard board on two posts, facing `facing`. LeaderboardService fills in "Rows".
function RouteKit.addSign(route: Instance, position: Vector3, facing: Vector3, title: string)
	local flat = Vector3.new(facing.X, 0, facing.Z).Unit
	local width, height, bottom = 5, 6.5, 1.5
	local cframe = frameAt(position + Vector3.yAxis * (bottom + height / 2), flat, Vector3.yAxis)
	local sign = Instance.new("Model")
	sign.Name = "Sign"
	local board = part({ name = "Board", size = Vector3.new(width, height, 0.2), cframe = cframe, surface = "SignBoard", collide = true, parent = sign })
	part({ name = "Frame", size = Vector3.new(width + 0.4, height + 0.4, 0.15), cframe = cframe * CFrame.new(0, 0, 0.175), surface = "LightWood", parent = sign })
	for _, x in { -width / 2 + 0.5, width / 2 - 0.5 } do
		local foot = (cframe * CFrame.new(x, 0, 0.35)).Position
		BuildUtil.pipe("Post", Vector3.new(foot.X, position.Y, foot.Z), Vector3.new(foot.X, position.Y + bottom + height, foot.Z), 0.22, "LightWood", sign).CanCollide = true
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.2
	gui.Parent = board
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(14, 10)
	titleLabel.Size = UDim2.new(1, -110, 0, 34)
	titleLabel.Font = Enum.Font.Michroma
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Text = title
	titleLabel.Parent = gui
	local pill = Instance.new("TextLabel")
	pill.Name = "Tab"
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.new(1, -12, 0, 14)
	pill.Size = UDim2.fromOffset(84, 26)
	pill.BackgroundColor3 = Color3.fromRGB(70, 200, 120)
	pill.Font = Enum.Font.Sarpanch
	pill.TextSize = 15
	pill.TextColor3 = Color3.fromRGB(10, 30, 16)
	pill.Text = "Fastest"
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(10, 56)
	rows.Size = UDim2.new(1, -20, 1, -66)
	rows.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows
	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Size = UDim2.new(1, 0, 0, 30)
	empty.Font = Enum.Font.GothamMedium
	empty.TextSize = 18
	empty.TextColor3 = Color3.fromRGB(150, 160, 180)
	empty.Text = "No times yet - be the first!"
	empty.Parent = rows

	sign.Parent = route
end

-- A coiled yellow rope on the ground with a "Tie in" prompt (RopeService handles it).
function RouteKit.addRopeBag(route: Instance, position: Vector3)
	local bag = part({
		name = "RopeBag",
		size = Vector3.new(0.6, 2.2, 2.2),
		cframe = CFrame.new(position + Vector3.yAxis * 0.3) * BuildUtil.AXIS_Y,
		surface = "Tape",
		color = Color3.fromRGB(240, 205, 40),
		shape = Enum.PartType.Cylinder,
		collide = false,
		query = true,
		parent = route,
	})
	bag.Material = Enum.Material.Fabric
	for i = 1, 3 do
		local ring = part({
			name = "Coil",
			size = Vector3.new(0.18, 2.2 - i * 0.35, 2.2 - i * 0.35),
			cframe = CFrame.new(position + Vector3.yAxis * (0.62 + i * 0.12)) * BuildUtil.AXIS_Y,
			surface = "Tape",
			color = Color3.fromRGB(250, 220, 60),
			shape = Enum.PartType.Cylinder,
			shadow = false,
			parent = bag,
		})
		ring.Material = Enum.Material.Fabric
	end
	-- Click the rope to tie in (click again to untie). No prompt: it's optional.
	local click = Instance.new("ClickDetector")
	click.Name = "TieIn"
	click.MaxActivationDistance = 14
	click.Parent = bag
end

-- An auto-belay: the orange unit bolted above the top of the wall, its webbing strap, and
-- the carabiner hanging at the base: click it to clip in (RopeService handles it).
-- Clipping in is optional; you can always free solo.
function RouteKit.addAutoBelay(route: Instance, base: Vector3, top: Vector3, facing: Vector3)
	local flat = Vector3.new(facing.X, 0, facing.Z).Unit
	local unit = Instance.new("Model")
	unit.Name = "AutoBelay"
	local housing = part({
		name = "Unit",
		size = Vector3.new(1.6, 1.8, 1.1),
		cframe = frameAt(top + Vector3.yAxis * 0.9 + flat * 0.6, flat, Vector3.yAxis),
		surface = "Accent",
		parent = unit,
	})
	part({ name = "Drum", size = Vector3.new(0.5, 1.2, 1.2), cframe = housing.CFrame * CFrame.new(0, 0, -0.55) * BuildUtil.AXIS_Z, surface = "BlackSteel", shape = Enum.PartType.Cylinder, parent = unit })
	local clipPosition = base + Vector3.yAxis * 3.2 + flat * 0.4
	local clip = part({
		name = "Carabiner",
		size = Vector3.new(0.12, 0.7, 0.4),
		cframe = frameAt(clipPosition, flat, Vector3.yAxis),
		surface = "Accent",
		collide = false,
		query = true,
		parent = unit,
	})
	-- The strap hangs from the unit down to the carabiner at the base.
	local a0 = Instance.new("Attachment")
	a0.Parent = housing
	a0.Position = Vector3.new(0, -0.9, -0.6)
	local a1 = Instance.new("Attachment")
	a1.Parent = clip
	a1.Position = Vector3.new(0, 0.35, 0)
	local strap = Instance.new("Beam")
	strap.Name = "Strap"
	strap.Attachment0 = a0
	strap.Attachment1 = a1
	strap.Width0 = 0.18
	strap.Width1 = 0.18
	strap.FaceCamera = true
	strap.Color = ColorSequence.new(Color3.fromRGB(70, 74, 82))
	strap.Parent = housing
	-- Click the carabiner to clip in (click again to unclip). No prompt: it's optional.
	local click = Instance.new("ClickDetector")
	click.Name = "ClipIn"
	click.MaxActivationDistance = 14
	click.Parent = clip
	unit.Parent = route
end

-- A chalk bucket with a "Chalk up" prompt (ChalkService handles it).
function RouteKit.addChalkBucket(parent: Instance, position: Vector3)
	local bucket = part({
		name = "ChalkBucket",
		size = Vector3.new(1.3, 1.1, 1.1),
		cframe = CFrame.new(position + Vector3.yAxis * 0.65) * BuildUtil.AXIS_Y,
		surface = "LightWood",
		shape = Enum.PartType.Cylinder,
		collide = true,
		query = true,
		parent = parent,
	})
	part({
		name = "Chalk",
		size = Vector3.new(0.05, 0.95, 0.95),
		cframe = CFrame.new(position + Vector3.yAxis * 1.25) * BuildUtil.AXIS_Y,
		surface = "Chalk",
		shape = Enum.PartType.Cylinder,
		shadow = false,
		parent = bucket,
	}).Transparency = 0
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChalkUp"
	prompt.ActionText = "Chalk up"
	prompt.ObjectText = "Chalk bucket"
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = bucket
end

-- The whole route: folder, attributes, holds, start, summit and base furniture.
function RouteKit.buildRoute(spec: RouteSpec): Folder
	local routes = RouteKit.routesFolder()
	local existing = routes:FindFirstChild(spec.id)
	if existing then
		existing:Destroy()
	end
	local face = spec.face
	local baseY = spec.baseY or face.origin.Y
	local flat = face.flatNormal
	local route = Instance.new("Folder")
	route.Name = spec.id

	local holdsFolder = Instance.new("Folder")
	holdsFolder.Name = "Holds"
	holdsFolder.Parent = route
	RouteKit.buildHolds(face, spec.holds, holdsFolder, spec.id, { style = spec.style, color = spec.color })

	local finish = spec.holds[#spec.holds]
	local topX = spec.topX or (if finish then finish.x else spec.lineX)
	local top = Face.point(face, topX, face.height, 0)
	local rise = top.Y - baseY

	route:SetAttribute("RouteName", spec.name)
	route:SetAttribute("Grade", spec.grade)
	route:SetAttribute("Order", spec.order)
	route:SetAttribute("HeightStuds", rise)
	route:SetAttribute("HeightMeters", math.round(Config.studsToMeters(rise) * 10) / 10)
	route:SetAttribute("BaseY", baseY)
	route:SetAttribute("Indoor", spec.indoor == true)
	route:SetAttribute("AutoBelay", spec.autoBelay == true)
	route:SetAttribute("Rope", spec.rope == true)
	route:SetAttribute("Leaderboard", spec.leaderboard == true)

	-- Base: where you start, and where "Retry" puts you.
	local base = Face.point(face, spec.lineX, 0, 0)
	local ground = Vector3.new(base.X, baseY, base.Z) + flat * 4
	route:SetAttribute("StartPosition", ground + Vector3.yAxis * 3)

	local startPad = part({
		name = "StartPad",
		size = Vector3.new(6, 5, 4),
		cframe = frameAt(ground + Vector3.yAxis * 2.5, flat, Vector3.yAxis),
		surface = "Tape",
		shadow = false,
		parent = route,
	})
	startPad.Transparency = 1
	startPad.CanTouch = true
	CollectionService:AddTag(startPad, Tags.RouteStart)

	local summit = part({
		name = "Summit",
		size = Vector3.new(10, 6, 8),
		cframe = frameAt(top + Vector3.yAxis * 2.5 - flat * 2, flat, Vector3.yAxis),
		surface = "Tape",
		shadow = false,
		parent = route,
	})
	summit.Transparency = 1
	summit.CanTouch = true
	CollectionService:AddTag(summit, Tags.RouteSummit)
	route:SetAttribute("TopAnchor", top + Vector3.yAxis * 1.5 - flat * 0.5)

	local side = spec.signSide or 1
	if spec.leaderboard then
		RouteKit.addSign(route, ground + face.right * (side * 6) + flat * 1, flat, string.upper(spec.name))
	end
	if spec.rope then
		RouteKit.addRopeBag(route, ground + face.right * (-side * 3) + flat * 0.5)
	end
	if spec.autoBelay then
		RouteKit.addAutoBelay(route, Vector3.new(base.X, baseY, base.Z), top, flat)
	end
	if spec.chalk then
		RouteKit.addChalkBucket(route, ground + face.right * (-side * 5.5) + flat * 1)
	end

	route.Parent = routes
	return route
end

return RouteKit
