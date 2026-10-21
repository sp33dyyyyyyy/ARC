--!strict
-- BuildUtil: small helpers shared by the world builders.

local Surfaces = require(script.Parent.Surfaces)

local BuildUtil = {}

export type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	surface: string,
	color: Color3?, -- overrides the surface colour
	shape: Enum.PartType?, -- Part shapes (Cylinder runs along the part's X axis)
	wedge: boolean?, -- WedgePart: full height at the Back face, sloping down to the Front
	ellipsoid: boolean?, -- stretched sphere (SpecialMesh), for rounded holds
	collide: boolean?, -- default false
	query: boolean?, -- raycasts/mouse can hit it; default false
	shadow: boolean?, -- default true
	parent: Instance?,
}

-- CFrame at `position` whose LookVector is `look` and UpVector is `up` (unit, perpendicular).
function BuildUtil.frameAt(position: Vector3, look: Vector3, up: Vector3): CFrame
	return CFrame.fromMatrix(position, up:Cross(-look), up, -look)
end

-- Rotations that turn a Cylinder part's axis (local X) onto local Z / local Y.
BuildUtil.AXIS_Z = CFrame.Angles(0, math.rad(90), 0)
BuildUtil.AXIS_Y = CFrame.Angles(0, 0, math.rad(90))

-- Anchored, non-colliding, non-touchable part. Builders opt in to collision/queries.
function BuildUtil.part(spec: PartSpec): BasePart
	local part: BasePart
	if spec.wedge then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if spec.shape then
			p.Shape = spec.shape
		end
		part = p
	end
	part.Name = spec.name
	part.Size = spec.size
	part.CFrame = spec.cframe
	Surfaces.apply(part, spec.surface, spec.color)
	part.Anchored = true
	part.CanCollide = spec.collide == true
	part.CanQuery = spec.query == true
	part.CanTouch = false
	part.CastShadow = spec.shadow ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	if spec.parent then
		part.Parent = spec.parent
	end
	return part
end

-- CFrame halfway between `a` and `b`, looking from `a` to `b`. Picks a safe up vector so
-- vertical segments don't degenerate.
local function segmentFrame(a: Vector3, b: Vector3): CFrame
	local direction = (b - a).Unit
	local up = if math.abs(direction.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt((a + b) / 2, b, up)
end

-- A box of square `thickness` running from `a` to `b` (beams, braces, rails).
function BuildUtil.beam(name: string, a: Vector3, b: Vector3, thickness: number, surface: string, parent: Instance): BasePart
	local length = (b - a).Magnitude
	return BuildUtil.part({
		name = name,
		size = Vector3.new(thickness, thickness, length),
		cframe = segmentFrame(a, b),
		surface = surface,
		parent = parent,
	})
end

-- Cylinder (round bar) from `a` to `b`.
function BuildUtil.pipe(name: string, a: Vector3, b: Vector3, diameter: number, surface: string, parent: Instance): BasePart
	local length = (b - a).Magnitude
	return BuildUtil.part({
		name = name,
		size = Vector3.new(length, diameter, diameter),
		cframe = segmentFrame(a, b) * BuildUtil.AXIS_Z,
		surface = surface,
		shape = Enum.PartType.Cylinder,
		parent = parent,
	})
end

return table.freeze(BuildUtil)
