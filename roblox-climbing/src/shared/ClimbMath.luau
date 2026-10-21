--!strict
-- ClimbMath: geometry shared by the client (body placement, previews) and the server
-- (validation), so both apply exactly the same reach rules.

export type Grip = {
	kind: "Hand" | "Foot",
	position: Vector3,
	reach: number,
}

export type BodyTuning = {
	BodyOffset: number,
	MinWallGap: number,
	HangBelowHands: number,
	StandAboveFeet: number,
	HandBias: number,
	ShiftRange: Vector2,
	ReachSlack: number,
}

local ClimbMath = {}

-- Right and up directions along a wall whose face points along `normal`.
function ClimbMath.wallAxes(normal: Vector3): (Vector3, Vector3)
	local right = Vector3.yAxis:Cross(normal)
	if right.Magnitude < 0.1 then
		-- Roof (normal straight down) or floor: any horizontal right will do.
		right = Vector3.xAxis
	end
	right = right.Unit
	return right, normal:Cross(right).Unit
end

function ClimbMath.inReach(rootPosition: Vector3, gripPosition: Vector3, reach: number, tolerance: number?): boolean
	return (gripPosition - rootPosition).Magnitude <= reach + (tolerance or 0)
end

local function average(points: { Vector3 }): Vector3?
	if #points == 0 then
		return nil
	end
	local sum = Vector3.zero
	for _, p in points do
		sum += p
	end
	return sum / #points
end

-- Where the HumanoidRootPart should be for the attached `grips` on a wall facing
-- `normal`, with weight shift `shift` (x = right, y = up, each -1..1).
-- Returns the position and whether every limb could be kept within reach.
function ClimbMath.solveBody(grips: { Grip }, normal: Vector3, shift: Vector2, tuning: BodyTuning): (Vector3, boolean)
	assert(#grips > 0, "solveBody needs at least one grip")
	local right, up = ClimbMath.wallAxes(normal)

	local hands, feet, all = {}, {}, {}
	for _, grip in grips do
		table.insert(if grip.kind == "Hand" then hands else feet, grip.position)
		table.insert(all, grip.position)
	end
	local handsAvg, feetAvg = average(hands), average(feet)
	local planePoint = average(all) :: Vector3

	-- Resting pose for the limbs in use.
	local body: Vector3
	if handsAvg and feetAvg then
		body = feetAvg:Lerp(handsAvg, tuning.HandBias)
	elseif handsAvg then
		body = handsAvg - up * tuning.HangBelowHands
	else
		body = (feetAvg :: Vector3) + up * tuning.StandAboveFeet
	end

	-- Sit a fixed distance out from the wall, then apply the weight shift.
	body -= normal * (body - planePoint):Dot(normal)
	body += normal * tuning.BodyOffset
	body += right * (shift.X * tuning.ShiftRange.X) + up * (shift.Y * tuning.ShiftRange.Y)

	-- Pull the body back until every attached limb is within reach, and keep it off the wall.
	local satisfied = false
	for _ = 1, 10 do
		satisfied = true
		for _, grip in grips do
			local maxDistance = grip.reach * tuning.ReachSlack
			local offset = body - grip.position
			if offset.Magnitude > maxDistance then
				body = grip.position + offset.Unit * maxDistance
				satisfied = false
			end
		end
		local gap = (body - planePoint):Dot(normal)
		if gap < tuning.MinWallGap then
			body += normal * (tuning.MinWallGap - gap)
			satisfied = false
		end
		if satisfied then
			break
		end
	end
	return body, satisfied
end

-- Point where a ray hits the plane through `planePoint` with normal `normal`, if in front.
function ClimbMath.rayPlane(origin: Vector3, direction: Vector3, planePoint: Vector3, normal: Vector3): Vector3?
	local denominator = direction:Dot(normal)
	if math.abs(denominator) < 1e-4 then
		return nil
	end
	local t = (planePoint - origin):Dot(normal) / denominator
	if t < 0 then
		return nil
	end
	return origin + direction * t
end

return table.freeze(ClimbMath)
