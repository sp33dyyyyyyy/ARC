--!strict
-- Wall logic for rock climbing: finding the wall, planning moves, leaps and
-- climbing over the top. It only uses Vector3 maths and a `World` (raycast,
-- tag checks, lattice holds), so tests run this exact code against real tower
-- geometry.
--
-- Two kinds of wall:
--   surface  skyscraper glass: you can grip anywhere on it (raycasts).
--   lattice  telecom towers: your hands must be on an actual member (a leg,
--            brace or girt). Every move reaches for the nearest real beam.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lattice = require(ReplicatedStorage.Shared.Lattice)

local WallClimb = {}

export type Hit = { Instance: any, Position: Vector3, Normal: Vector3 }
export type World = {
	cast: (origin: Vector3, direction: Vector3) -> Hit?,
	climbable: (instance: any) -> boolean,
	solid: (instance: any) -> boolean,
	noStand: (instance: any) -> boolean, -- thin trim (roof parapets) you climb over
	holds: () -> { Lattice.Segment }, -- lattice members of the tower you're on
	faceNormal: (point: Vector3) -> Vector3, -- outward normal of that tower's face
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

-- Lattice climbing (telecom towers) -------------------------------------------

-- Hands must be on a member within this distance of where they reach.
WallClimb.HOLD_REACH = 2.6

local function anchorFor(cfg: any, hold: Vector3, n: Vector3): Vector3
	return hold + n * cfg.WallOffset - Vector3.new(0, WallClimb.HAND_HEIGHT, 0)
end

-- Where the hands are for a body held at `anchor` on a face with normal `n`.
function WallClimb.handFor(cfg: any, anchor: Vector3, n: Vector3): Vector3
	return anchor - n * cfg.WallOffset + Vector3.new(0, WallClimb.HAND_HEIGHT, 0)
end

-- Grab the nearest member in front of you. Returns hold point + normal.
function WallClimb.latticeGrab(world: World, cfg: any, position: Vector3, dir: Vector3, range: number): (Vector3?, Vector3?)
	local reach = position + Vector3.new(0, WallClimb.HAND_HEIGHT, 0) + dir * 1.5
	local found = Lattice.nearest(world.holds(), reach, range)
	if not found then
		return nil, nil
	end
	local hold = found :: Vector3
	local n = world.faceNormal(hold)
	return anchorFor(cfg, hold, n), n
end

-- Plan the next move on a lattice. Same contract as WallClimb.plan.
function WallClimb.latticePlan(
	world: World,
	cfg: any,
	anchor: Vector3,
	wallNormal: Vector3,
	vert: number,
	lat: number,
	speed: number
): (Move?, string?)
	local hand = WallClimb.handFor(cfg, anchor, wallNormal)
	local up = Vector3.new(0, 1, 0)
	local segments = world.holds()
	local kind, hold = nil, nil
	if vert > 0 then
		kind = "up"
		hold = Lattice.nearest(segments, hand + up * cfg.ReachLength, WallClimb.HOLD_REACH, function(q)
			return q.Y > hand.Y + 0.75
		end)
		if not hold then
			return nil, "mantle" -- nothing above in reach: the top, or a gap
		end
	elseif vert < 0 then
		local floor = world.cast(anchor, Vector3.new(0, -(WallClimb.ROOT_HEIGHT + cfg.ReachLength), 0))
		if floor and floor.Normal.Y > 0.7 then
			return nil, "stepoff"
		end
		kind = "down"
		hold = Lattice.nearest(segments, hand - up * cfg.ReachLength, WallClimb.HOLD_REACH, function(q)
			return q.Y < hand.Y - 0.75
		end)
	elseif lat ~= 0 then
		kind = "side"
		local side = (-wallNormal):Cross(up) * math.sign(lat)
		hold = Lattice.nearest(segments, hand + side * cfg.SideStep, WallClimb.HOLD_REACH, function(q)
			return (q - hand):Dot(side) > 0.75
		end)
		if not hold then
			-- At a corner leg: swing round onto the next face (it runs back
			-- into the tower, and faces out along `side`).
			hold = Lattice.nearest(segments, hand - wallNormal * cfg.SideStep, WallClimb.HOLD_REACH, function(q)
				return (hand - q):Dot(wallNormal) > 0.75 and world.faceNormal(q):Dot(side) > 0.9
			end)
		end
	end
	if not hold or not kind then
		return nil, nil
	end
	local target = hold :: Vector3
	local n = world.faceNormal(target) -- may be the next face round a corner
	local to = anchorFor(cfg, target, n)
	local distance = (to - anchor).Magnitude
	return {
		kind = kind,
		t = 0,
		duration = math.max(0.15, distance / (if kind == "side" then cfg.SideSpeed else speed)),
		from = anchor,
		to = to,
		mantleAfter = false,
	}, nil
end

-- A dyno on a lattice: the highest member you can catch.
function WallClimb.latticeLeap(world: World, cfg: any, anchor: Vector3, wallNormal: Vector3): Move?
	local hand = WallClimb.handFor(cfg, anchor, wallNormal)
	local segments = world.holds()
	for d = cfg.LungeDistance, cfg.ReachLength + 1, -1 do
		local hold = Lattice.nearest(segments, hand + Vector3.new(0, d, 0), WallClimb.HOLD_REACH, function(q)
			return q.Y > hand.Y + cfg.ReachLength
		end)
		if hold then
			local n = world.faceNormal(hold)
			local to = anchorFor(cfg, hold, n)
			return {
				kind = "leap",
				t = 0,
				duration = math.max(0.22, (to - anchor).Magnitude / cfg.LungeSpeed) + 0.15,
				from = anchor,
				to = to,
				mantleAfter = false,
			}
		end
	end
	return nil
end

-- Where a rappel down a lattice face puts you after dropping `drop` studs
-- (following the taper), or nil when there's no member to follow.
function WallClimb.latticeSlide(world: World, cfg: any, anchor: Vector3, wallNormal: Vector3, drop: number): Vector3?
	local hand = WallClimb.handFor(cfg, anchor, wallNormal) - Vector3.new(0, drop, 0)
	local found = Lattice.nearest(world.holds(), hand, 6)
	if not found then
		return nil
	end
	local hold = found :: Vector3
	local n = world.faceNormal(hold)
	local outward = hold + n * cfg.WallOffset
	-- Stay straight below (only correct the distance from the face).
	local fromFace = (outward - hand):Dot(n)
	local position = hand + n * fromFace - Vector3.new(0, WallClimb.HAND_HEIGHT, 0)
	return position
end

return WallClimb
