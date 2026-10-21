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

-- Raises `body` so a climber hanging near the floor stands on it instead of sinking in.
-- `groundY` is the floor height under the body (nil = no floor found).
function ClimbMath.clampAboveGround(body: Vector3, groundY: number?, standingHeight: number, crouch: number): Vector3
	if groundY == nil then
		return body
	end
	local lowest = groundY + standingHeight - crouch
	if body.Y < lowest then
		return Vector3.new(body.X, lowest, body.Z)
	end
	return body
end

export type DynoTuning = {
	MinDistance: number,
	MaxDistance: number,
	CatchBelow: number,
	FlightTimeBase: number,
	FlightTimePerStud: number,
}

-- Plans a dyno from `root` towards a hold whose grip is at `grip` on a wall facing
-- `normal`. The body aims for where it would hang from that hold (below it and out from
-- the wall). `charge` (0..1) sets how far the jump can go; a weak jump falls short.
-- Returns where the body will arrive and how long the flight takes.
function ClimbMath.planDyno(root: Vector3, grip: Vector3, normal: Vector3, charge: number, bodyOffset: number, tuning: DynoTuning): (Vector3, number)
	local _, up = ClimbMath.wallAxes(normal)
	local desired = grip - up * tuning.CatchBelow + normal * bodyOffset
	local offset = desired - root
	local maxDistance = tuning.MinDistance + (tuning.MaxDistance - tuning.MinDistance) * math.clamp(charge, 0, 1)
	if offset.Magnitude > maxDistance then
		offset = offset.Unit * maxDistance
	end
	local time = tuning.FlightTimeBase + tuning.FlightTimePerStud * offset.Magnitude
	return root + offset, time
end

-- Roblox steps physics at 240 Hz.
ClimbMath.PHYSICS_STEP = 1 / 240

-- Launch velocity that carries a body from `from` to `to` in `time` seconds under
-- `gravity` (studs/s^2, positive; Roblox's default is 196.2). The extra half step makes up
-- for stepped integration (speed is updated before position each step), which would
-- otherwise land a little low.
function ClimbMath.ballisticVelocity(from: Vector3, to: Vector3, time: number, gravity: number): Vector3
	return (to - from) / time + Vector3.yAxis * (0.5 * gravity * (time + ClimbMath.PHYSICS_STEP))
end

-- Advances a damped spring (a free hand or foot) towards `rest` by `dt` seconds, in small
-- fixed steps so it stays stable at any frame rate. Returns the new position and velocity.
function ClimbMath.springStep(position: Vector3, velocity: Vector3, rest: Vector3, dt: number, stiffness: number, damping: number): (Vector3, Vector3)
	local remaining = math.min(dt, 0.1)
	while remaining > 1e-6 do
		local h = math.min(remaining, 1 / 120)
		local accel = (rest - position) * stiffness - velocity * damping
		velocity += accel * h
		position += velocity * h
		remaining -= h
	end
	return position, velocity
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
