--!strict
-- RockWall: a natural granite crag. The face is built from big faceted rock blocks along a
-- Face profile (vertical sections, slabs, overhangs, roofs), with flat ledges to stand and
-- rest on, a summit plateau, and procedurally generated routes (RouteGenerator) that carry
-- rope bags, chalk buckets and leaderboard signs at their base (RouteKit).
--
-- The rock itself streams as one persistent model, so big walls stay on the skyline from
-- far away; holds stream in as you get close.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Tags = require(ReplicatedStorage:WaitForChild("Shared").Tags)

local BuildUtil = require(script.Parent.BuildUtil)
local Face = require(script.Parent.Face)
local RouteGenerator = require(script.Parent.RouteGenerator)
local RouteKit = require(script.Parent.RouteKit)

local part = BuildUtil.part
local frameAt = BuildUtil.frameAt

export type RouteDef = {
	id: string,
	name: string,
	grade: string,
	order: number,
	lineX: number,
	difficulty: number,
	seed: number,
	drift: number?,
	wander: number?,
}

export type WallDef = {
	id: string,
	origin: Vector3, -- bottom-centre of the face (a little below the ground)
	facing: Vector3,
	width: number,
	segments: { Face.SegmentSpec },
	ledges: { number }?, -- heights along the face with a ledge across it
	ledgeDepth: number?,
	block: number?, -- rock block size
	groundY: number,
	tint: Color3?,
	routes: { RouteDef },
}

local RockWall = {}

-- Small deterministic noise for block jitter (same wall every time).
local function hash(a: number, b: number, c: number): number
	local n = math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
	return n - math.floor(n)
end

local function cragsFolder(): Folder
	local crags = Workspace:FindFirstChild("Crags")
	if crags == nil then
		crags = Instance.new("Folder")
		crags.Name = "Crags"
		crags.Parent = Workspace
	end
	return crags :: Folder
end

function RockWall.build(def: WallDef): Model
	local existing = cragsFolder():FindFirstChild(def.id)
	if existing then
		existing:Destroy()
	end
	local face = Face.new(def.origin, def.facing, def.segments)
	local model = Instance.new("Model")
	model.Name = def.id
	local rock = Instance.new("Model")
	rock.Name = "Rock"
	rock.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local tint = def.tint or Color3.fromRGB(116, 113, 108)
	local size = def.block or 12
	local depth = 10

	-- Faceted face: a grid of rock blocks along every segment, each nudged and tilted a
	-- little so the face catches the light like real granite.
	local columns = math.max(1, math.ceil(def.width / size))
	local cell = def.width / columns
	for si, segment in face.segments do
		local rows = math.max(1, math.ceil(segment.length / size))
		local rowHeight = segment.length / rows
		for row = 0, rows - 1 do
			for column = 0, columns - 1 do
				local x = -def.width / 2 + (column + 0.5) * cell
				local s = segment.startS + (row + 0.5) * rowHeight
				local r1, r2, r3 = hash(si, row, column), hash(column, si, row), hash(row, column, si)
				local inset = r1 * 0.3
				local tilt = CFrame.Angles(math.rad((r2 - 0.5) * 4), math.rad((r3 - 0.5) * 4), math.rad((r1 - 0.5) * 6))
				local block = part({
					name = "RockFace",
					size = Vector3.new(cell + 0.8, rowHeight + 0.8, depth),
					cframe = frameAt(Face.point(face, x, s, -depth / 2 - inset), segment.normal, segment.up) * tilt,
					surface = "RockFace",
					color = tint:Lerp(Color3.new(r2, r2, r2), 0.08),
					collide = true,
					query = true,
					parent = rock,
				})
				CollectionService:AddTag(block, Tags.Climbable)
			end
		end
	end

	-- Summit plateau behind the top edge.
	local top = Face.top(face)
	local flat = face.flatNormal
	part({
		name = "Plateau",
		size = Vector3.new(def.width + 16, 4, 60),
		cframe = frameAt(top - flat * 30 - Vector3.yAxis * 2, flat, Vector3.yAxis),
		surface = "Ledge",
		color = tint,
		collide = true,
		query = true,
		parent = rock,
	})

	-- Ledges to stand and rest on (belay stances on big walls). Each client turns its own
	-- ledges non-solid while it climbs (ClimbController), so the body slides past them on
	-- the way up; let go above one and you land on it. Holds hug both sides of it.
	local ledgeDepth = def.ledgeDepth or 4.5
	local skip: { { number } } = {}
	local ledges: { number } = def.ledges or {}
	for _, s in ledges do
		local edge = Face.point(face, 0, s, 0)
		local ledge = part({
			name = "Ledge",
			size = Vector3.new(def.width, 0.8, ledgeDepth + 2),
			cframe = frameAt(edge + flat * (ledgeDepth / 2 - 1) - Vector3.yAxis * 0.4, flat, Vector3.yAxis),
			surface = "Ledge",
			color = tint,
			collide = true,
			query = true,
			parent = rock,
		})
		CollectionService:AddTag(ledge, Tags.Ledge)
		table.insert(skip, { s - 1.2, s + 0.6 })
	end
	rock.Parent = model

	for _, route in def.routes do
		local holds = RouteGenerator.generate({
			seed = route.seed,
			height = face.height,
			lineX = route.lineX,
			drift = route.drift,
			wander = route.wander or 1.6,
			difficulty = route.difficulty,
			skip = skip,
			startY = 2.6 + (def.groundY - def.origin.Y),
		})
		RouteKit.buildRoute({
			id = route.id,
			name = route.name,
			grade = route.grade,
			order = route.order,
			face = face,
			lineX = route.lineX,
			holds = holds,
			style = "rock",
			baseY = def.groundY,
			rope = true,
			leaderboard = true,
			chalk = true,
		})
	end

	model.Parent = cragsFolder()
	return model
end

return RockWall
