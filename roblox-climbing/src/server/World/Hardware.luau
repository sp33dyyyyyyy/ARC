--!strict
-- Hardware: climbing metalwork built from parts, so it hangs exactly the right way on any
-- wall: D-shaped carabiners (spine, gate, locking sleeve), quickdraws (two carabiners on a
-- dogbone sling), bolt hangers, and the two-bolt top anchor with chains and a locking
-- carabiner that every top rope runs through.
--
-- Every builder takes a CFrame whose LookVector points out of the wall and whose UpVector
-- is up; parts are anchored, non-colliding and not queryable.

local BuildUtil = require(script.Parent.BuildUtil)

local Hardware = {}

Hardware.STEEL = Color3.fromRGB(196, 198, 204)
Hardware.DARK_STEEL = Color3.fromRGB(120, 122, 128)
Hardware.GOLD = Color3.fromRGB(214, 170, 72)

local function rod(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, parent: Instance): BasePart
	-- Overlap the ends a little so the joints between segments look solid.
	local direction = (b - a).Unit
	local piece = BuildUtil.pipe(name, a - direction * thickness * 0.3, b + direction * thickness * 0.3, thickness, "BoltHead", parent)
	piece.Material = Enum.Material.Metal
	piece.Color = color
	piece.Reflectance = 0.08
	piece.CastShadow = false
	return piece
end

-- The outline of a D carabiner, from its top (0, 0) down to its bottom (0, -1) in unit
-- height; x is sideways (spine on the left, gate on the right). Narrow at the top, wide
-- and round at the bottom, with a flat spine.
local OUTLINE: { Vector2 } = {}
do
	local count = 20
	for i = 0, count - 1 do
		local theta = i / count * math.pi * 2
		local y = -0.5 + 0.5 * math.cos(theta) -- 0 at the top, -1 at the bottom
		local width = 0.42 + 0.16 * -y
		local s = math.sin(theta)
		local x = if s >= 0 then s * width else -(math.abs(s) ^ 0.45) * width * 0.85
		table.insert(OUTLINE, Vector2.new(x, y))
	end
end

export type Carabiner = { model: Model, top: Vector3, bottom: Vector3 }

-- A carabiner hanging from `top` (its uppermost point). `height` in studs; the carabiner
-- lies in the plane of top's Right and Up vectors. `locking` adds a screw sleeve on the
-- gate.
function Hardware.carabiner(parent: Instance, top: CFrame, height: number, color: Color3?, locking: boolean?): Carabiner
	local model = Instance.new("Model")
	model.Name = if locking then "LockingCarabiner" else "Carabiner"
	local body = color or Hardware.STEEL
	local thickness = height * 0.11
	local points: { Vector3 } = {}
	for _, p in OUTLINE do
		table.insert(points, top * Vector3.new(p.X * height, p.Y * height, 0))
	end
	for i = 1, #points do
		local a, b = points[i], points[i % #points + 1]
		-- Segments 2..6 (on the right, between the nose and the basket) are the gate.
		local gate = i >= 2 and i <= 6
		rod(if gate then "Gate" else "Frame", a, b, if gate then thickness * 0.8 else thickness, if gate then Hardware.STEEL else body, model)
		if not gate then
			-- Rounded joints, so the bends look like bent bar rather than kinks.
			local joint = BuildUtil.part({ name = "Bend", size = Vector3.one * thickness, cframe = CFrame.new(b), surface = "BoltHead", color = body, shape = Enum.PartType.Ball, shadow = false, parent = model })
			joint.Material = Enum.Material.Metal
			joint.Reflectance = 0.08
		end
	end
	if locking then
		local a, b = points[2], points[5]
		rod("Sleeve", a:Lerp(b, 0.15), a:Lerp(b, 0.75), thickness * 1.55, body:Lerp(Color3.new(0, 0, 0), 0.15), model)
	end
	model.Parent = parent
	return { model = model, top = top.Position, bottom = top * Vector3.new(0, -height * 0.97, 0) }
end

-- A bolt hanger on the wall at `frame` (LookVector out of the rock). Returns where a
-- carabiner clips into its eye.
function Hardware.hanger(parent: Instance, frame: CFrame): Vector3
	local plate = BuildUtil.part({
		name = "Hanger",
		size = Vector3.new(0.3, 0.46, 0.05),
		cframe = frame * CFrame.new(0, -0.08, -0.025),
		surface = "BoltHead",
		color = Hardware.STEEL,
		shadow = false,
		parent = parent,
	})
	plate.Material = Enum.Material.Metal
	plate.Reflectance = 0.08
	local bolt = BuildUtil.part({
		name = "BoltHead",
		size = Vector3.new(0.09, 0.17, 0.17),
		cframe = frame * CFrame.new(0, 0.04, -0.09) * BuildUtil.AXIS_Z,
		surface = "BoltHead",
		color = Hardware.DARK_STEEL,
		shape = Enum.PartType.Cylinder,
		shadow = false,
		parent = parent,
	})
	bolt.Material = Enum.Material.Metal
	-- The eye: a small bent-out tab at the bottom of the plate.
	local eye = BuildUtil.part({
		name = "Eye",
		size = Vector3.new(0.22, 0.06, 0.16),
		cframe = frame * CFrame.new(0, -0.27, -0.09),
		surface = "BoltHead",
		color = Hardware.STEEL,
		shadow = false,
		parent = parent,
	})
	eye.Material = Enum.Material.Metal
	return (frame * CFrame.new(0, -0.27, -0.12)).Position
end

-- A quickdraw clipped to a bolt at `frame`: top carabiner in the hanger, a dogbone sling,
-- bottom carabiner for the rope. Returns the model and the point the rope runs through.
function Hardware.quickdraw(parent: Instance, frame: CFrame, slingColor: Color3?): (Model, Vector3)
	local model = Instance.new("Model")
	model.Name = "Quickdraw"
	local eye = Hardware.hanger(model, frame)
	-- Quickdraws hang across the wall, turned so you still see their shape from below.
	local hang = CFrame.fromMatrix(eye, frame.RightVector, frame.UpVector, -frame.LookVector) * CFrame.Angles(0, math.rad(55), 0)
	local upper = Hardware.carabiner(model, hang, 0.62)
	local slingTop = upper.bottom + Vector3.yAxis * 0.06
	local slingLength = 0.75
	local sling = BuildUtil.part({
		name = "Sling",
		size = Vector3.new(0.17, slingLength, 0.05),
		cframe = hang.Rotation + slingTop - Vector3.yAxis * (slingLength / 2),
		surface = "Tape",
		color = slingColor or Color3.fromRGB(240, 110, 40),
		shadow = false,
		parent = model,
	})
	sling.Material = Enum.Material.Fabric
	local lowerTop = slingTop - Vector3.yAxis * (slingLength - 0.06)
	local lower = Hardware.carabiner(model, hang.Rotation + lowerTop, 0.62, slingColor and slingColor:Lerp(Hardware.STEEL, 0.4) or Hardware.GOLD)
	model.Parent = parent
	return model, lower.bottom + Vector3.yAxis * 0.08
end

-- One chain link (a small oval ring) from `top`, in the plane of top's Right/Up.
local function link(parent: Instance, top: CFrame, size: number): Vector3
	local points: { Vector3 } = {}
	for i = 0, 7 do
		local theta = i / 8 * math.pi * 2
		table.insert(points, top * Vector3.new(math.sin(theta) * size * 0.32, -size * 0.5 + math.cos(theta) * size * 0.5, 0))
	end
	for i = 1, #points do
		rod("Link", points[i], points[i % #points + 1], size * 0.16, Hardware.DARK_STEEL, parent)
	end
	return top * Vector3.new(0, -size * 0.85, 0)
end

-- The top anchor at `frame` (on the rock just under the lip, LookVector out of it): two
-- bolts with hangers, a short chain from each down to a master point, and a locking
-- carabiner hanging there. Builds a TopAnchorPart (what RopeService ties the rope to) with
-- a "Ring" attachment inside the carabiner, and returns that attachment and where it is.
function Hardware.topAnchor(parent: Instance, frame: CFrame): (Attachment, Vector3)
	local model = Instance.new("Model")
	model.Name = "Anchor"
	local master = (frame * CFrame.new(0, -0.95, -0.12)).Position
	for _, side in { -1, 1 } do
		local eye = Hardware.hanger(model, frame * CFrame.new(side * 0.42, 0, 0))
		-- Two links hanging from the eye, angled in towards the master point.
		local down = (master - eye).Unit
		local right = frame.LookVector:Cross(down).Unit
		local linkFrame = CFrame.fromMatrix(eye, right, -down, right:Cross(-down))
		local nextTop = link(model, linkFrame, 0.3)
		-- The next link turned a quarter round the chain.
		local across = (frame.LookVector - down * frame.LookVector:Dot(down)).Unit
		link(model, CFrame.fromMatrix(nextTop, across, -down), 0.3)
	end
	local hang = CFrame.fromMatrix(master, frame.RightVector, frame.UpVector, -frame.LookVector) * CFrame.Angles(0, math.rad(25), 0)
	local locker = Hardware.carabiner(model, hang, 0.78, Hardware.GOLD, true)

	local ringAt = locker.bottom + Vector3.yAxis * 0.1
	local anchor = BuildUtil.part({
		name = "TopAnchorPart",
		size = Vector3.new(0.2, 0.2, 0.2),
		cframe = CFrame.new(ringAt),
		surface = "BoltHead",
		shadow = false,
		parent = model,
	})
	anchor.Transparency = 1
	local ring = Instance.new("Attachment")
	ring.Name = "Ring"
	ring.Parent = anchor
	model.Parent = parent
	return ring, ringAt
end

return table.freeze(Hardware)
