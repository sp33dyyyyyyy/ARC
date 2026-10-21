--!strict
-- ClimbAnimator (client): procedural climbing animation for every climber on screen.
-- No animation assets needed; it works on R6 and R15 with either kind of joint.
--
--   * Hands and feet are placed on their holds with two-bone IK (elbows bend down and out,
--     knees out to the side), so limbs really touch the holds.
--   * When a limb moves to a new hold it reaches for it: it lifts off the wall and arcs
--     across, faster for short moves.
--   * Free limbs are on damped springs: they hang, lag behind when the body moves and
--     swing a little before settling (floppy, but not rag-doll floppy). Mid-dyno the hands
--     reach for the target hold.
--   * Tired climbers (low stamina) get shaky hands and heavier breathing.
--   * The torso leans into the wall, breathes, twists towards a reaching hand, and coils
--     back while a dyno charges. The head looks where you're reaching or aiming.
--   * Everything eases in and out, and hands control back to the normal animations when
--     you stop climbing.
--
-- ClimbController calls animate() for each character every frame from
-- RunService.PreSimulation (after Roblox's animations, so this pose wins).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClimbMath = require(Shared:WaitForChild("ClimbMath"))
local LimbRig = require(Shared:WaitForChild("LimbRig"))

export type Intent = {
	climbing: boolean, -- full climbing pose (false = only pose the limbs that have targets)
	normal: Vector3, -- the wall faces this way
	targets: { [string]: Vector3? }, -- where each hand/foot should be (nil = free)
	direct: { [string]: boolean }?, -- limbs that follow their target exactly (being dragged)
	look: Vector3?, -- where the head looks
	charge: number, -- dyno charge 0..1 (coils the body)
	fatigue: number?, -- 0 = fresh, 1 = about to fall off (shaky hands, heavy breathing)
}

type Reach = { from: Vector3, to: Vector3, t: number, duration: number }
type Spring = { position: Vector3, velocity: Vector3 }
type State = {
	rig: LimbRig.Rig,
	poses: { [Instance]: CFrame }, -- the Transforms this module has written
	reach: { [string]: Reach }, -- limbs currently moving to a new hold
	settled: { [string]: Vector3 }, -- the target each limb last went for
	springs: { [string]: Spring }, -- free limbs swinging
	phase: number, -- per-character offset so climbers don't sway in sync
}

local SIDE = { LeftHand = -1, RightHand = 1, LeftFoot = -1, RightFoot = 1 }
local HANDS = { LeftHand = true, RightHand = true }
local POSE_RATE = 22 -- how quickly joints ease towards their pose
local BLEND_OUT_RATE = 9 -- how quickly they go back to the normal animations
local REACH_LIFT = 0.55 -- how far a reaching hand/foot lifts off the wall mid-move
local MAX_HEAD_TURN = math.rad(50)
-- Free-limb spring: stiffness and damping (about half critical damping, so a limb swings
-- past its rest point once or twice and settles).
local SPRING_STIFFNESS = 40
local SPRING_DAMPING = 6.5
local SHAKE_AMOUNT = 0.08 -- studs of hand tremor at full fatigue

local ClimbAnimator = {}

local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

local function stillValid(rig: LimbRig.Rig): boolean
	for _, chain in rig.chains do
		if chain.upper.instance.Parent == nil or (chain.lower and chain.lower.instance.Parent == nil) then
			return false
		end
	end
	return true
end

local function stateFor(character: Model): State
	local state = states[character]
	if state == nil or not stillValid(state.rig) then
		state = {
			rig = LimbRig.find(character),
			poses = {},
			reach = {},
			settled = {},
			springs = {},
			phase = math.random() * 10,
		}
		states[character] = state
	end
	return state :: State
end

-- The rig this module uses for `character` (the controller uses it for the hand rings).
function ClimbAnimator.rigFor(character: Model): LimbRig.Rig
	return stateFor(character).rig
end

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

-- Where a limb should be this frame: its hold (reaching along an arc after a change),
-- the drag point, or a relaxed hang when it holds nothing.
local function limbAim(state: State, chain: LimbRig.Chain, intent: Intent, dt: number, now: number): Vector3?
	local limb = chain.name
	local target = intent.targets[limb]
	local normal = intent.normal
	if target then
		state.springs[limb] = nil
		local fatigue = intent.fatigue or 0
		if fatigue > 0 and HANDS[limb] then
			-- Tired hands tremble on their holds.
			local seed = (SIDE[limb] or 0) * 7.3 + state.phase
			local t = now * 11
			target += Vector3.new(math.noise(t, seed), math.noise(seed, t), math.noise(t + 3.1, seed)) * (SHAKE_AMOUNT * fatigue * 2)
		end
		if intent.direct and intent.direct[limb] then
			state.reach[limb] = nil
			state.settled[limb] = target
			return target
		end
		local settled: Vector3? = state.settled[limb]
		if settled == nil or (settled - target).Magnitude > 0.25 then
			local from = LimbRig.tipPosition(chain)
			local distance = (target - from).Magnitude
			state.reach[limb] = { from = from, to = target, t = 0, duration = math.clamp(0.12 + distance * 0.035, 0.12, 0.38) }
			state.settled[limb] = target
		end
		local reach = state.reach[limb]
		if reach == nil then
			return target
		end
		reach.to = target
		reach.t = math.min(1, reach.t + dt / reach.duration)
		local position = reach.from:Lerp(reach.to, smoothstep(reach.t)) + normal * (REACH_LIFT * math.sin(math.pi * reach.t))
		if reach.t >= 1 then
			state.reach[limb] = nil
		end
		return position
	end

	state.reach[limb] = nil
	state.settled[limb] = nil
	if not intent.climbing then
		return nil -- not ours to pose
	end
	-- Free limb: a damped spring pulls the hand/foot towards a relaxed hang below the
	-- shoulder/hip. Because the rest point moves with the body, the limb lags and swings.
	local right, up = ClimbMath.wallAxes(normal)
	local side = SIDE[limb] or 0
	local start = LimbRig.frame(chain.upper).Position
	local length = chain.upperLength + chain.lowerLength
	local out = if HANDS[limb] then 0.35 else 0.5
	local rest = start - up * (length * 0.85) + normal * out + right * (side * 0.3)

	local spring = state.springs[limb]
	if spring == nil then
		spring = { position = LimbRig.tipPosition(chain), velocity = Vector3.zero }
		state.springs[limb] = spring
	end
	spring.position, spring.velocity = ClimbMath.springStep(spring.position, spring.velocity, rest, dt, SPRING_STIFFNESS, SPRING_DAMPING)
	-- A hand can't hang further from the shoulder than the arm is long.
	local offset = spring.position - start
	if offset.Magnitude > length then
		local direction = offset.Unit
		spring.position = start + direction * length
		spring.velocity -= direction * math.max(0, spring.velocity:Dot(direction))
	end
	return spring.position
end

local function limbPole(limb: string, normal: Vector3): Vector3
	local right, up = ClimbMath.wallAxes(normal)
	local side = SIDE[limb] or 0
	if HANDS[limb] then
		return -up + normal * 0.7 + right * (side * 0.8) -- elbows down, out and away from the wall
	end
	return right * side + normal * 0.6 + up * 0.3 -- knees out to the side ("frog" legs)
end

-- Pose `character` for this frame. `intent` nil = not climbing (ease back to normal).
function ClimbAnimator.animate(character: Model, intent: Intent?, dt: number)
	local state = stateFor(character)
	local rig = state.rig
	local goals: { [Instance]: CFrame } = {}
	local now = os.clock()

	if intent then
		local right = ClimbMath.wallAxes(intent.normal)

		-- Torso (R15): lean into the wall, breathe, twist towards a reaching hand, and coil
		-- back while a dyno charges. Negative X rotation tips the top forward.
		if intent.climbing and rig.waist then
			local twist = 0
			for limb, reach in state.reach do
				if HANDS[limb] then
					twist -= (reach.to - reach.from):Dot(right) * 4
				end
			end
			local fatigue = intent.fatigue or 0
			local breath = math.sin(now * (2.4 + fatigue * 3) + state.phase) * (1.2 + fatigue * 2.5)
			local lean = -8 + intent.charge * 16 + breath
			goals[rig.waist.instance] = CFrame.Angles(math.rad(lean), math.rad(math.clamp(twist, -12, 12)), 0)
		end
		if intent.climbing and rig.root then
			goals[rig.root.instance] = CFrame.Angles(0, 0, math.rad(math.sin(now * 1.3 + state.phase) * 2))
		end

		for limb, chain in rig.chains do
			local aim = limbAim(state, chain, intent, dt, now)
			if aim then
				local upperT, lowerT = LimbRig.solve(chain, aim, limbPole(limb, intent.normal))
				goals[chain.upper.instance] = upperT
				local lower = chain.lower
				if lower and lowerT then
					goals[lower.instance] = lowerT
				end
			end
		end

		-- Head looks where you're reaching or aiming, within a natural range.
		local neck = rig.neck
		if intent.look and neck then
			local turn = LimbRig.aimTransform(neck, Vector3.new(0, 0, -1), intent.look - neck.part1.Position)
			local axis, angle = turn:ToAxisAngle()
			goals[neck.instance] = if angle > 1e-3 then CFrame.fromAxisAngle(axis, math.min(angle, MAX_HEAD_TURN)) else CFrame.identity
		end
	else
		table.clear(state.reach)
		table.clear(state.settled)
		table.clear(state.springs)
	end

	-- Ease every posed joint towards its goal; joints without a goal ease back to rest and
	-- are handed back to the normal animations once there.
	local alpha = 1 - math.exp(-POSE_RATE * dt)
	for instance, goal in goals do
		local current = state.poses[instance] or (instance :: any).Transform
		current = current:Lerp(goal, alpha)
		state.poses[instance] = current;
		(instance :: any).Transform = current
	end
	local out = 1 - math.exp(-BLEND_OUT_RATE * dt)
	for instance, current in state.poses do
		local goal: CFrame? = goals[instance]
		if goal == nil then
			local nextPose = current:Lerp(CFrame.identity, out)
			local _, angle = nextPose:ToAxisAngle()
			if angle < 0.01 and nextPose.Position.Magnitude < 1e-3 then
				state.poses[instance] = nil;
				(instance :: any).Transform = CFrame.identity
			else
				state.poses[instance] = nextPose;
				(instance :: any).Transform = nextPose
			end
		end
	end
end

return ClimbAnimator
