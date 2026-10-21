--!strict
-- Face: a climbing face made of segments stacked bottom to top, each with its own angle
-- (0 = vertical, positive = overhang leaning towards the climber, negative = slab). A point
-- on the face is (x, s, out): x studs to the climber's right of the centre line, s studs up
-- the face measured along its surface, `out` studs in front of it.

local BuildUtil = require(script.Parent.BuildUtil)

export type SegmentSpec = { length: number, angle: number }

export type Segment = {
	start: Vector3, -- centre-line point where this segment begins
	startS: number, -- distance along the face where it begins
	length: number,
	angle: number,
	up: Vector3, -- up the surface
	normal: Vector3, -- out of the surface
}

export type Face = {
	origin: Vector3,
	flatNormal: Vector3, -- horizontal facing direction
	right: Vector3, -- climber's right
	segments: { Segment },
	height: number, -- total length along the surface
}

local Face = {}

function Face.new(origin: Vector3, facing: Vector3, specs: { SegmentSpec }): Face
	local flatNormal = Vector3.new(facing.X, 0, facing.Z).Unit
	local right = Vector3.yAxis:Cross(flatNormal)
	local segments: { Segment } = {}
	local point, s = origin, 0
	for _, spec in specs do
		local angle = math.rad(spec.angle)
		local up = Vector3.yAxis * math.cos(angle) + flatNormal * math.sin(angle)
		local normal = flatNormal * math.cos(angle) - Vector3.yAxis * math.sin(angle)
		table.insert(segments, { start = point, startS = s, length = spec.length, angle = spec.angle, up = up, normal = normal })
		point += up * spec.length
		s += spec.length
	end
	return { origin = origin, flatNormal = flatNormal, right = right, segments = segments, height = s }
end

function Face.segmentAt(face: Face, s: number): Segment
	for _, segment in face.segments do
		if s < segment.startS + segment.length then
			return segment
		end
	end
	return face.segments[#face.segments]
end

-- World point at (x, s, out).
function Face.point(face: Face, x: number, s: number, out: number?): Vector3
	local segment = Face.segmentAt(face, s)
	return segment.start + face.right * x + segment.up * (s - segment.startS) + segment.normal * (out or 0)
end

-- Surface CFrame at (x, s): LookVector out of the wall, UpVector up the surface (what
-- HoldModels expects).
function Face.frame(face: Face, x: number, s: number): CFrame
	local segment = Face.segmentAt(face, s)
	return BuildUtil.frameAt(Face.point(face, x, s, 0), segment.normal, segment.up)
end

-- Centre-line point at the very top of the face.
function Face.top(face: Face): Vector3
	return Face.point(face, 0, face.height, 0)
end

-- How far above the face's bottom the top is, in world height (for progress bars).
function Face.rise(face: Face): number
	return Face.top(face).Y - face.origin.Y
end

return table.freeze(Face)
