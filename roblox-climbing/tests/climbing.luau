-- Climbing tests: run by tests/run.py, which puts the real Config, HoldTypes, ClimbMath and
-- TestWallLayout modules (plus mocks.luau and the hold GRIPS read from HoldModels) above
-- this file. Not runnable on its own.

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(`PASS  {name}`)
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end
local function expect(condition: boolean, message: string?)
	if not condition then
		error(message or "expectation failed", 2)
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local CLIMB = Config.Climb
local HAND_REACH = Config.Limbs.LeftHand.Reach
local FOOT_REACH = Config.Limbs.LeftFoot.Reach
local NORMAL = Vector3.zAxis -- test wall faces +Z, face at z = 0, floor at y = 0

-- Grip positions of the test wall holds (same maths as HoldModels: surface point + grip).
local holds = {}
for i, spec in Layout.Holds do
	local g = GRIPS[spec.type]
	holds[i] = {
		index = i,
		type = spec.type,
		def = HoldTypes.get(spec.type),
		grip = Vector3.new(spec.x + g.X, spec.y + g.Y, -g.Z),
		finish = spec.role == "Finish",
	}
end

local function grip(kind: string, position: any)
	return { kind = kind, position = position, reach = if kind == "Hand" then HAND_REACH else FOOT_REACH }
end

-- Solver --------------------------------------------------------------------

test("wallAxes: a wall facing +Z has right = +X and up = +Y", function()
	local right, up = ClimbMath.wallAxes(NORMAL)
	expect(near(right.X, 1) and near(right.Y, 0) and near(right.Z, 0), `right {right}`)
	expect(near(up.X, 0) and near(up.Y, 1) and near(up.Z, 0), `up {up}`)
end)

local startGrips = {
	grip("Hand", holds[5].grip),
	grip("Hand", holds[6].grip),
	grip("Foot", holds[1].grip),
	grip("Foot", holds[2].grip),
}

test("start pose: body between feet and hands, off the wall, every limb in reach", function()
	local body, satisfied = ClimbMath.solveBody(startGrips, NORMAL, Vector2.zero, CLIMB)
	expect(satisfied, "constraints not satisfied")
	expect(body.Y > holds[1].grip.Y and body.Y < holds[5].grip.Y, `body y {body.Y}`)
	expect(body.Z >= CLIMB.MinWallGap, `body z {body.Z}`)
	for _, g in startGrips do
		expect((body - g.position).Magnitude <= g.reach * CLIMB.ReachSlack + 1e-6, "a limb is out of reach")
	end
end)

test("hands only: hangs HangBelowHands under them", function()
	local body = ClimbMath.solveBody({ startGrips[1], startGrips[2] }, NORMAL, Vector2.zero, CLIMB)
	local handsY = (holds[5].grip.Y + holds[6].grip.Y) / 2
	expect(near(body.Y, handsY - CLIMB.HangBelowHands, 1e-3), `body y {body.Y}`)
end)

test("feet only: stands over them with both legs in reach", function()
	-- The two lowest footholds are 2.8 studs apart: a wide stance.
	local body, satisfied = ClimbMath.solveBody({ startGrips[3], startGrips[4] }, NORMAL, Vector2.zero, CLIMB)
	local feetY = (holds[1].grip.Y + holds[2].grip.Y) / 2
	expect(satisfied, "the resting stance overstretches the legs")
	expect(near(body.Y, feetY + CLIMB.StandAboveFeet, 1e-3), `body y {body.Y}`)
end)

test("weight shift moves the body the way you press", function()
	local rest = ClimbMath.solveBody(startGrips, NORMAL, Vector2.zero, CLIMB)
	local upRight = ClimbMath.solveBody(startGrips, NORMAL, Vector2.new(1, 1), CLIMB)
	local downLeft = ClimbMath.solveBody(startGrips, NORMAL, Vector2.new(-1, -1), CLIMB)
	expect(upRight.X > rest.X and upRight.Y > rest.Y, "W+D should move up and right")
	expect(downLeft.X < rest.X and downLeft.Y < rest.Y, "S+A should move down and left")
end)

test("the body never leaves an attached limb behind", function()
	-- Feet far below the hands: the body must stay within reach of all four.
	local stretched = {
		grip("Hand", Vector3.new(-1, 9, 0.5)),
		grip("Hand", Vector3.new(1, 9, 0.5)),
		grip("Foot", Vector3.new(-1, 3.5, 0.3)),
		grip("Foot", Vector3.new(1, 3.5, 0.3)),
	}
	for _, shift in { Vector2.zero, Vector2.new(0, 1), Vector2.new(0, -1), Vector2.new(1, 0) } do
		local body = ClimbMath.solveBody(stretched, NORMAL, shift, CLIMB)
		for _, g in stretched do
			expect((body - g.position).Magnitude <= g.reach * CLIMB.ReachSlack + 0.05, `shift {shift}: out of reach`)
		end
	end
end)

test("clampAboveGround lifts a sinking body and leaves others alone", function()
	local lifted = ClimbMath.clampAboveGround(Vector3.new(0, 2, 1), 0.8, 3, 0.4)
	expect(near(lifted.Y, 3.4), `lifted {lifted.Y}`)
	local high = ClimbMath.clampAboveGround(Vector3.new(0, 9, 1), 0.8, 3, 0.4)
	expect(near(high.Y, 9))
	local noGround = ClimbMath.clampAboveGround(Vector3.new(0, -5, 1), nil, 3, 0.4)
	expect(near(noGround.Y, -5))
end)

test("rayPlane hits a plane in front and ignores one behind", function()
	local hit = ClimbMath.rayPlane(Vector3.new(0, 5, 10), Vector3.new(0, 0, -1), Vector3.zero, NORMAL)
	expect(hit ~= nil and near(hit.Z, 0) and near(hit.Y, 5))
	expect(ClimbMath.rayPlane(Vector3.new(0, 5, 10), Vector3.new(0, 0, 1), Vector3.zero, NORMAL) == nil)
end)

-- Dyno ----------------------------------------------------------------------

local GRAVITY = 196.2

-- Integrates a body launched at `velocity` under gravity for `time` seconds.
local function fly(from: any, velocity: any, time: number): any
	local position, v = from, velocity
	local dt = 1 / 240
	local t = 0
	while t < time - 1e-9 do
		local step = math.min(dt, time - t)
		v = v - Vector3.yAxis * (GRAVITY * step)
		position = position + v * step
		t += step
	end
	return position
end

test("dyno: the ballistic launch lands where it was aimed, under Roblox gravity", function()
	local from = Vector3.new(0, 4, 1.1)
	for _, to in { Vector3.new(0, 11, 1.1), Vector3.new(4, 8, 1.1), Vector3.new(-3, 3, 1.1) } do
		local time = 0.4
		local landed = fly(from, ClimbMath.ballisticVelocity(from, to, time, GRAVITY), time)
		expect((landed - to).Magnitude < 0.05, `aimed {to}, landed {landed}`)
	end
end)

test("dyno: full charge reaches a hold 7 studs up; a weak jump falls short", function()
	local root = Vector3.new(0, 4.5, 1.6)
	local target = Vector3.new(0.5, 12.5, 0.5)
	local arrival = ClimbMath.planDyno(root, target, NORMAL, 1, CLIMB.BodyOffset, CLIMB.Dyno)
	expect(ClimbMath.inReach(arrival, target, HAND_REACH * CLIMB.ReachSlack), `full charge arrives {arrival}`)
	local weak = ClimbMath.planDyno(root, target, NORMAL, 0.15, CLIMB.BodyOffset, CLIMB.Dyno)
	expect(not ClimbMath.inReach(weak, target, HAND_REACH), `weak jump still arrives in reach at {weak}`)
end)

test("dyno: arrival is below the hold and out from the wall, flight time is sane", function()
	local root = Vector3.new(0, 4.5, 1.6)
	local target = Vector3.new(0, 10, 0.5)
	local arrival, time = ClimbMath.planDyno(root, target, NORMAL, 1, CLIMB.BodyOffset, CLIMB.Dyno)
	expect(arrival.Y < target.Y and arrival.Z > target.Z, `arrival {arrival}`)
	expect(time > 0.15 and time < 0.8, `time {time}`)
end)

-- Whole wall ----------------------------------------------------------------

-- Breadth-first search over which hold each limb is on, using the real solver and the
-- real reach rules (plus 9 weight-shift directions). Proves the test wall can be climbed
-- from the mat to the finish without a dyno, and that every hold can be used.
test("the test wall can be climbed from the mat to the finish (real solver and reach)", function()
	local limbs = { "LeftHand", "RightHand", "LeftFoot", "RightFoot" }
	local shifts = {}
	for _, x in { -1, 0, 1 } do
		for _, y in { -1, 0, 1 } do
			table.insert(shifts, Vector2.new(x, y))
		end
	end
	local function usable(limb: string, h): boolean
		local kind = Config.Limbs[limb].Kind
		return if kind == "Hand" then h.def.HandOK else h.def.FootOK
	end
	local function key(state): string
		return table.concat(state, ",")
	end

	-- Start: standing on the mat (root 3 studs above it), anywhere on the start box.
	local queue, seen, used = {}, {}, {}
	for _, x in { -2, -1, 0, 1, 2 } do
		for _, z in { 1.5, 2.5 } do
			local root = Vector3.new(x, 0.8 + 3, z)
			for li, limb in limbs do
				for _, h in holds do
					if usable(limb, h) and ClimbMath.inReach(root, h.grip, Config.Limbs[limb].Reach) then
						local state = { 0, 0, 0, 0 }
						state[li] = h.index
						if not seen[key(state)] then
							seen[key(state)] = true
							table.insert(queue, state)
						end
					end
				end
			end
		end
	end

	local finished = false
	local head = 1
	while head <= #queue do
		local state = queue[head]
		head += 1
		for _, i in state do
			if i > 0 then
				used[i] = true
			end
		end
		if (state[1] > 0 and holds[state[1]].finish) or (state[2] > 0 and holds[state[2]].finish) then
			finished = true
		end
		local grips = {}
		for li, i in state do
			if i > 0 then
				table.insert(grips, grip(Config.Limbs[limbs[li]].Kind, holds[i].grip))
			end
		end
		for _, shift in shifts do
			local body = ClimbMath.solveBody(grips, NORMAL, shift, CLIMB)
			for li, limb in limbs do
				for _, h in holds do
					if h.index ~= state[li] and usable(limb, h) and ClimbMath.inReach(body, h.grip, Config.Limbs[limb].Reach) then
						local nextState = table.clone(state)
						nextState[li] = h.index
						local k = key(nextState)
						if not seen[k] then
							seen[k] = true
							table.insert(queue, nextState)
						end
					end
				end
			end
		end
	end
	expect(finished, `finish never reached ({#queue} positions explored)`)
	local unused = {}
	for _, h in holds do
		if not used[h.index] then
			table.insert(unused, `{h.index}:{h.type}`)
		end
	end
	expect(#unused == 0, "never reachable: " .. table.concat(unused, ", "))
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	error("climbing tests failed")
end
