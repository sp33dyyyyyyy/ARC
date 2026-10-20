--!strict
-- Wall logic for rock climbing: finding the wall, planning moves, leaps and
-- climbing over the top. It only uses Vector3 maths and a `World` (raycast +
-- tag checks), so tests run this exact code against real tower geometry.

local WallClimb = {}

export type Hit = { Instance: any, Position: Vector3, Normal: Vector3 }
export type World = {
	cast: (origin: Vector3, direction: Vector3) -> Hit?,
	climbable: (instance: any) -> boolean,
	solid: (instance: any) -> boolean,
	noStand: (instance: any) -> boolean, -- thin trim (roof parapets) you climb over
}
export type Move = {
	kind: string, -- "up" | "down" | "side" | "leap"
	t: number,
	duration: number,
	from: Vector3,
	to: Vector3,
	mantleAfter: boolean,
}

WallClimb.ROOT_HEIGHT = 3 -- HumanoidRootPart centre above the floor when standing
WallClimb.HAND_HEIGHT = 2.5 -- hands above the root while climbing

local function horizontal(v: Vector3): Vector3
	local h = Vector3.new(v.X, 0, v.Z)
	return if h.Magnitude > 1e-3 then h.Unit else Vector3.new(0, 0, 1)
end
WallClimb.horizontal = horizontal

-- Climbable wall straight "into" the wall from `origin`, or nil.
function WallClimb.probe(world: World, cfg: any, origin: Vector3, normal: Vector3): Hit?
	local hit = world.cast(origin + normal, -normal * (cfg.WallOffset + 3))
	if hit and world.climbable(hit.Instance) and math.abs(hit.Normal.Y) < 0.7 then
		return hit
	end
	return nil
end

-- Direction "up the wall" (follows the taper of lattice faces).
function WallClimb.wallUp(n: Vector3): Vector3
	local up = Vector3.new(0, 1, 0)
	return (up - n * n:Dot(up)).Unit
end

-- Grab a wall in front of `position` along `dir`. Returns hold point + normal.
function WallClimb.grab(world: World, cfg: any, position: Vector3, dir: Vector3, range: number): (Vector3?, Vector3?)
	for _, height in { 0, 1.5, -1.5 } do
		local hit = world.cast(position + Vector3.new(0, height, 0), dir * range)
		if hit and world.climbable(hit.Instance) and math.abs(hit.Normal.Y) < 0.7 then
			local hold = hit.Position + hit.Normal * cfg.WallOffset
			return Vector3.new(hold.X, position.Y, hold.Z), horizontal(hit.Normal)
		end
	end
	return nil, nil
end

-- Somewhere to stand at or just above the hold (a ledge or the top of the
-- wall), or nil. Uses rays, i.e. exact geometry.
function WallClimb.findMantle(world: World, cfg: any, anchor: Vector3, wallNormal: Vector3): Vector3?
	local inward = -wallNormal
	local R = WallClimb.ROOT_HEIGHT
	for _, offset in { 0, 1.5, 3, 4.5, 6 } do
		local p = anchor + inward * offset
		local top = Vector3.new(p.X, anchor.Y + cfg.MantleReach, p.Z)
		local hit = world.cast(top, Vector3.new(0, -(cfg.MantleReach + 4), 0))
		if
			hit
			and hit.Normal.Y > 0.7
			and world.solid(hit.Instance)
			and not world.noStand(hit.Instance) -- not on trim like the roof parapet
			and hit.Position.Y > anchor.Y - R + 0.5
		then
			local stand = hit.Position + Vector3.new(0, R, 0)
			local headroom = world.cast(hit.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, 5, 0))
			local from = Vector3.new(anchor.X, stand.Y, anchor.Z)
			local path = if (stand - from).Magnitude > 0.05 then world.cast(from, stand - from) else nil
			local blocked = (headroom and world.solid(headroom.Instance)) or (path and world.solid(path.Instance))
			if not blocked then
				return stand
			end
		end
	end
	return nil
end

-- Plan the next move. Returns (move, nil), or (nil, "mantle") to climb over
-- the top, (nil, "stepoff") at the bottom, or (nil, nil) when blocked.
function WallClimb.plan(
	world: World,
	cfg: any,
	anchor: Vector3,
	wallNormal: Vector3,
	vert: number,
	lat: number,
	speed: number
): (Move?, string?)
	local probe = WallClimb.probe(world, cfg, anchor, wallNormal)
	local n = if probe then probe.Normal else wallNormal
	local wallUp = WallClimb.wallUp(n)
	local right = (-wallNormal):Cross(Vector3.new(0, 1, 0))

	local function moveTo(kind: string, hit: Hit, duration: number): Move
		return {
			kind = kind,
			t = 0,
			duration = duration,
			from = anchor,
			to = hit.Position + hit.Normal * cfg.WallOffset,
			mantleAfter = false,
		}
	end

	if vert > 0 then
		local ceiling = world.cast(anchor + Vector3.new(0, 2.4, 0), Vector3.new(0, cfg.ReachLength + 0.6, 0))
		if ceiling and world.solid(ceiling.Instance) then
			return nil, "mantle" -- something overhead: climb onto it if there's room
		end
		local target = anchor + wallUp * cfg.ReachLength
		if not WallClimb.probe(world, cfg, target + Vector3.new(0, 1.5, 0), wallNormal) then
			return nil, "mantle" -- the wall ends: climb over the top
		end
		local hit = WallClimb.probe(world, cfg, target, wallNormal)
		if not hit then
			return nil, nil
		end
		return moveTo("up", hit :: Hit, cfg.ReachLength / speed), nil
	elseif vert < 0 then
		local floor = world.cast(anchor, Vector3.new(0, -(WallClimb.ROOT_HEIGHT + cfg.ReachLength), 0))
		if floor and floor.Normal.Y > 0.7 then
			return nil, "stepoff"
		end
		local hit = WallClimb.probe(world, cfg, anchor - wallUp * cfg.ReachLength, wallNormal)
		if not hit then
			return nil, nil
		end
		return moveTo("down", hit :: Hit, cfg.ReachLength / speed), nil
	elseif lat ~= 0 then
		local hit = WallClimb.probe(world, cfg, anchor + right * (cfg.SideStep * math.sign(lat)), wallNormal)
		if not hit then
			return nil, nil
		end
		return moveTo("side", hit :: Hit, cfg.SideStep / cfg.SideSpeed), nil
	end
	return nil, nil
end

-- A dyno: how far up the wall a leap can go (stopping under anything overhead
-- or at the top, in which case you climb over after landing).
function WallClimb.planLeap(world: World, cfg: any, anchor: Vector3, wallNormal: Vector3): Move?
	local probe = WallClimb.probe(world, cfg, anchor, wallNormal)
	local n = if probe then probe.Normal else wallNormal
	local wallUp = WallClimb.wallUp(n)
	local reached, mantleAfter = 0, false
	for d = 1, cfg.LungeDistance do
		local p = anchor + wallUp * d
		local ceiling = world.cast(anchor + Vector3.new(0, 2.4, 0), Vector3.new(0, d + 0.6, 0))
		if ceiling and world.solid(ceiling.Instance) then
			break
		end
		if not WallClimb.probe(world, cfg, p + Vector3.new(0, 1.5, 0), wallNormal) then
			mantleAfter = true
			reached = d
			break
		end
		if not WallClimb.probe(world, cfg, p, wallNormal) then
			break
		end
		reached = d
	end
	if reached < 1 then
		return nil
	end
	local target = anchor + wallUp * reached
	local hit = WallClimb.probe(world, cfg, target, wallNormal)
	if hit then
		target = hit.Position + hit.Normal * cfg.WallOffset
	end
	return {
		kind = "leap",
		t = 0,
		duration = math.max(0.22, reached / cfg.LungeSpeed) + 0.15, -- + a beat to catch the hold
		from = anchor,
		to = target,
		mantleAfter = mantleAfter,
	}
end

return WallClimb
