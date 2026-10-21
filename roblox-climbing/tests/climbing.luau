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

-- Limb posing -----------------------------------------------------------------

-- A fake joint, as LimbRig sees one (Motor6D-style offsets).
local function motor(part0CFrame: any, c0: any, c1: any): any
	return { isMotor = true, instance = { C0 = c0, C1 = c1 }, part0 = { CFrame = part0CFrame }, part1 = {} }
end

-- An R15-like arm: shoulder on a torso turned 35 degrees, 1.2-stud upper arm, 1.1-stud forearm
-- (rest pose hanging straight down, like Roblox's).
local torsoCFrame = CFrame.new(3, 4, -2) * CFrame.fromAxisAngle(Vector3.yAxis, math.rad(35))
local shoulder = motor(torsoCFrame, CFrame.new(1.5, 0.5, 0), CFrame.new(0, 0.4, 0))
local elbow = motor(CFrame.identity, CFrame.new(0, -0.8, 0), CFrame.new(0, 0.3, 0))
local twoBone = {
	name = "RightHand",
	upper = shoulder,
	lower = elbow,
	tipLocal = Vector3.new(0, -0.8, 0),
	upperLength = 1.2,
	lowerLength = 1.1,
	upperAxis = Vector3.new(0, -1.2, 0),
	lowerAxis = Vector3.new(0, -1.1, 0),
} :: any

test("two-bone IK puts the hand exactly on reachable targets", function()
	local start = LimbRig.frame(shoulder).Position
	for _, offset in { Vector3.new(0.5, 1.5, -1), Vector3.new(1.2, -0.6, -0.4), Vector3.new(-0.3, 0.2, -1.6), Vector3.new(0, -2.2, 0) } do
		local target = start + offset
		local upperT, lowerT = LimbRig.solve(twoBone, target, Vector3.new(0, -1, 1))
		local tip = LimbRig.forward(twoBone, upperT, lowerT)
		expect((tip - target).Magnitude < 1e-3, `offset {offset}: hand at {tip}, wanted {target}`)
	end
end)

test("two-bone IK bends the elbow towards the pole", function()
	local start = LimbRig.frame(shoulder).Position
	local target = start + Vector3.new(0, 1.2, -1.2)
	for _, pole in { Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } do
		local bend = LimbRig.bendPoint(start, target, 1.2, 1.1, pole)
		-- The elbow sits off the shoulder-hand line, on the pole's side.
		local direction = (target - start).Unit
		local offLine = (bend - start) - direction * (bend - start):Dot(direction)
		expect(offLine:Dot(pole) > 0.1, `pole {pole}: elbow {bend} is on the wrong side`)
	end
end)

test("two-bone IK straightens the arm towards a target out of reach", function()
	local start = LimbRig.frame(shoulder).Position
	local target = start + Vector3.new(0, 6, -2)
	local upperT, lowerT = LimbRig.solve(twoBone, target, Vector3.new(0, -1, 1))
	local tip = LimbRig.forward(twoBone, upperT, lowerT)
	local reach = (tip - start).Magnitude
	expect(math.abs(reach - 2.3) < 0.01, `arm length {reach}, expected about 2.3 (straight)`)
	expect((tip - start).Unit:Dot((target - start).Unit) > 0.999, "the straight arm should point at the target")
end)

test("one-bone limb (R6) points at its target, with Roblox's real R6 shoulder offsets", function()
	local r6Shoulder = motor(torsoCFrame, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	local tipLocal = Vector3.new(0, -0.75, 0)
	local axis = tipLocal - Vector3.new(-0.5, 0.5, 0)
	local chain = { name = "RightHand", upper = r6Shoulder, lower = nil, tipLocal = tipLocal, upperLength = axis.Magnitude, lowerLength = 0, upperAxis = axis, lowerAxis = Vector3.zero } :: any
	local start = LimbRig.frame(r6Shoulder).Position
	for _, direction in { Vector3.new(0, 1, -1), Vector3.new(1, -1, 0.5), Vector3.new(0.01, 1, 0) } do
		local target = start + direction.Unit * axis.Magnitude
		local upperT = LimbRig.solve(chain, target, Vector3.new(0, -1, 0))
		local tip = LimbRig.forward(chain, upperT, nil)
		expect((tip - target).Magnitude < 1e-3, `direction {direction}: tip {tip}, wanted {target}`)
	end
end)

-- Free limbs, stamina ---------------------------------------------------------

test("free-limb spring swings past its rest point a little, then settles", function()
	-- Same stiffness/damping as ClimbAnimator: a hand starts 1 stud to the side of where it hangs.
	local position, velocity = Vector3.new(1, 0, 0), Vector3.zero
	local rest = Vector3.zero
	local overshoot = 0
	for _ = 1, 120 do -- 2 seconds at 60 fps
		position, velocity = ClimbMath.springStep(position, velocity, rest, 1 / 60, 40, 6.5)
		overshoot = math.max(overshoot, -position.X)
	end
	expect(overshoot > 0.05, `no swing at all (overshoot {overshoot}): too stiff`)
	expect(overshoot < 0.35, `overshoot {overshoot}: too floppy`)
	expect(position.Magnitude < 0.01, `still {position.Magnitude} from rest after 2 s`)
end)

test("spring is stable at low frame rates", function()
	local position, velocity = Vector3.new(0, 2, 0), Vector3.zero
	for _ = 1, 40 do
		position, velocity = ClimbMath.springStep(position, velocity, Vector3.zero, 1 / 10, 40, 6.5)
	end
	expect(position.Magnitude < 0.01, `blew up or never settled: {position}`)
end)

local tuning = Config.Stamina
local function grips(count: number, holdType: string, quality: number?): { any }
	local def = HoldTypes.get(holdType)
	local list = {}
	for i = 1, count do
		table.insert(list, { kind = if i <= 2 then "Hand" else "Foot", drain = def.DrainMultiplier, quality = quality or def.DefaultQuality })
	end
	return list
end

test("stamina drains faster with fewer limbs on", function()
	local three = StaminaMath.rate(grips(3, "Edge"), 0, tuning)
	local two = StaminaMath.rate(grips(2, "Edge"), 0, tuning)
	local one = StaminaMath.rate(grips(1, "Edge"), 0, tuning)
	expect(three < 0 and two < three and one < two, `rates 3/2/1 limbs: {three} {two} {one}`)
end)

test("stamina drains faster on crimps and slopers than on jugs", function()
	local jug = StaminaMath.rate(grips(2, "Jug"), 0, tuning)
	local crimp = StaminaMath.rate(grips(2, "Crimp"), 0, tuning)
	local sloper = StaminaMath.rate(grips(2, "Sloper"), 0, tuning)
	expect(crimp < jug and sloper < jug, `jug {jug}, crimp {crimp}, sloper {sloper}`)
end)

test("resting on all four limbs recovers, but only after RestDelay", function()
	expect(StaminaMath.rate(grips(4, "Jug"), 0, tuning) == 0, "recovered before settling")
	expect(StaminaMath.rate(grips(4, "Jug"), tuning.RestDelay + 0.1, tuning) > 0, "no recovery while resting")
	expect(StaminaMath.rate({}, 0, tuning) == tuning.GroundRecover, "should refill off the wall")
end)

test("climbing without resting tires you out in a sensible time", function()
	-- Hanging off two edges with no feet: a full bar lasts about 10-40 seconds.
	local seconds = StaminaMath.secondsLeft(tuning.Max, StaminaMath.rate(grips(2, "Edge"), 0, tuning))
	expect(seconds > 10 and seconds < 40, `lasts {seconds} s on two edges`)
	-- Three limbs on jugs lasts longer than two limbs on crimps.
	local easy = StaminaMath.secondsLeft(tuning.Max, StaminaMath.rate(grips(3, "Jug"), 0, tuning))
	local hard = StaminaMath.secondsLeft(tuning.Max, StaminaMath.rate(grips(2, "Crimp"), 0, tuning))
	expect(easy > hard * 2, `3 jugs {easy} s vs 2 crimps {hard} s`)
	-- And step() never leaves 0..Max.
	expect(StaminaMath.step(5, -100, 1, tuning.Max) == 0 and StaminaMath.step(95, 100, 1, tuning.Max) == tuning.Max)
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
