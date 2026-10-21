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

	-- The face: flush rows of rock slabs in a staggered (brick) pattern, so there are no
	-- steps or tilted edges to catch on, with gentle colour banding like rock strata. Rows
	-- run the full width; the vertical joints are offset every other row.
	local columns = math.max(1, math.ceil(def.width / (size * 1.5)))
	local cell = def.width / columns
	for si, segment in face.segments do
		local rows = math.max(1, math.ceil(segment.length / size))
		local rowHeight = segment.length / rows
		for row = 0, rows - 1 do
			local s = segment.startS + (row + 0.5) * rowHeight
			local offset = if row % 2 == 1 then cell / 2 else 0
			local band = hash(si, row, 0.5)
			local edges = { -def.width / 2 }
			local x = -def.width / 2 + offset
			while x + cell < def.width / 2 - 0.01 do
				x += cell
				table.insert(edges, x)
			end
			table.insert(edges, def.width / 2)
			for column = 1, #edges - 1 do
				local left, right = edges[column], edges[column + 1]
				if right - left < 0.05 then
					continue
				end
				local shade = hash(si, row, column) * 0.06 + band * 0.08
				local block = part({
					name = "RockFace",
					size = Vector3.new(right - left, rowHeight, depth),
					cframe = frameAt(Face.point(face, (left + right) / 2, s, -depth / 2), segment.normal, segment.up),
					surface = "RockFace",
					color = tint:Lerp(Color3.fromRGB(150, 146, 138), shade),
					collide = true,
					query = true,
					parent = rock,
				})
				CollectionService:AddTag(block, Tags.Climbable)
			end
		end
	end
	-- Where two segments meet at an angle, a rounded rock bulge covers the crease.
	for si = 2, #face.segments do
		local segment = face.segments[si]
		local crease = Face.point(face, 0, segment.startS, -1.2)
		local bulge = part({
			name = "Crease",
			size = Vector3.new(def.width, 2.4, 2.4),
			cframe = CFrame.fromMatrix(crease, face.right, Vector3.yAxis),
			surface = "RockFace",
			color = tint,
			shape = Enum.PartType.Cylinder,
			collide = true,
			query = true,
			parent = rock,
		})
		CollectionService:AddTag(bulge, Tags.Climbable)
	end
	-- Smooth terrain rock around the sides, so the wall's outline is a natural rounded crag
	-- instead of a box (it stays behind the face, clear of every route).
	local terrain = Workspace.Terrain
	local rise = Face.rise(face)
	for _, side in { -1, 1 } do
		local y = 0
		while y < rise do
			local r1, r2 = hash(side, y, 3), hash(y, side, 7)
			local radius = math.clamp(rise * 0.12, 6, 18) * (0.75 + r1 * 0.6)
			local s = math.clamp(y, 0, face.height)
			local edge = Face.point(face, side * (def.width / 2 + radius * (0.3 + r2 * 0.35)), s, -radius * (0.5 + r2 * 0.2))
			terrain:FillBall(edge, radius, Enum.Material.Rock)
			y += radius * (0.6 + r2 * 0.3)
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
