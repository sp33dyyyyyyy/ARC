--!strict
-- Beam maths shared by client and server, so they always agree on where a
-- hand can grab and where a carabiner can clip.
--
-- Every telecom tower member (legs, diagonal braces, horizontal girts) is a
-- thin box whose length runs along its local Z axis (see Build.beam). A beam is
-- treated as the line segment through its middle.

local Lattice = {}

export type Segment = { a: Vector3, b: Vector3, part: any, minY: number, maxY: number }

-- Segment through the middle of a beam part.
function Lattice.segment(part: any): Segment
	local cf = part.CFrame
	local half = part.Size.Z / 2
	local along = cf.LookVector
	local a, b = cf.Position - along * half, cf.Position + along * half
	return { a = a, b = b, part = part, minY = math.min(a.Y, b.Y), maxY = math.max(a.Y, b.Y) }
end

-- Closest point to `p` on segment a-b.
function Lattice.closest(seg: Segment, p: Vector3): Vector3
	local ab = seg.b - seg.a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-9 then
		return seg.a
	end
	local t = math.clamp((p - seg.a):Dot(ab) / lengthSq, 0, 1)
	return seg.a + ab * t
end

-- The closest point on any segment to `p` within `radius` that passes `accept`
-- (if given). Returns point, segment.
function Lattice.nearest(
	segments: { Segment },
	p: Vector3,
	radius: number,
	accept: ((point: Vector3) -> boolean)?
): (Vector3?, Segment?)
	local best, bestSeg, bestDist = nil, nil, radius
	for _, seg in segments do
		-- Cheap height filter before the exact check.
		if p.Y >= seg.minY - radius and p.Y <= seg.maxY + radius then
			local q = Lattice.closest(seg, p)
			local d = (q - p).Magnitude
			if d <= bestDist and (accept == nil or accept(q)) then
				best, bestSeg, bestDist = q, seg, d
			end
		end
	end
	return best, bestSeg
end

-- Outward normal of the tower face a point is on: the tower-frame axis the
-- point sticks out along most (corners pick either neighbouring face).
function Lattice.faceNormal(pivot: CFrame, p: Vector3): Vector3
	local rel = pivot:PointToObjectSpace(p)
	local axis = if math.abs(rel.X) >= math.abs(rel.Z)
		then Vector3.new(if rel.X >= 0 then 1 else -1, 0, 0)
		else Vector3.new(0, 0, if rel.Z >= 0 then 1 else -1)
	return pivot:VectorToWorldSpace(axis)
end

return Lattice
