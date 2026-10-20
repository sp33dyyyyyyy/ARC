--!strict
-- Pure pose math for the rock-climbing animation (no Roblox APIs, unit tested).
--
-- A climb is a sequence of moves. `cycle` counts them: the whole part is the
-- move number (even = left hand leads, odd = right hand leads) and the
-- fraction is progress through that move:
--   reach  (first `reachFraction`): the lead hand reaches up to the next hold,
--          the opposite foot steps up high; the body stays put.
--   pull   (the rest): the body is pulled up; the lead arm pulls down a bit,
--          the other arm drops to "low hold", and the stepped-up leg pushes.
-- The pose at the end of one move equals the pose at the start of the next
-- with the hands swapped, so chained moves flow without pops.
--
-- Angles are degrees, "forward/up" positive, per limb { left, right }:
--   shoulder: 0 = arm down, 90 = arm forward, 180 = straight overhead
--   elbow:    bend toward the wall (applied as a negative rotation)
--   hip:      thigh raised toward the wall
--   knee:     lower leg folded back
--   neck:     head tilted up;  lean: torso tilted toward the wall

local ClimbPose = {}

export type Angles = {
	shoulder: { number },
	elbow: { number },
	hip: { number },
	knee: { number },
	neck: number,
	lean: number,
}

local LOW, MID, HIGH = 0.7, 0.85, 1.0 -- arm "raise" levels between holds

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function arm(raise: number): (number, number)
	-- Higher reach = straighter arm.
	return 55 + 120 * raise, 15 + (1 - raise) * 140
end

local function leg(lift: number): (number, number)
	return 15 + 55 * lift, 25 + 70 * lift
end

-- Arm raise for the lead and other hand at progress `f` through a move.
function ClimbPose.armRaise(f: number, reachFraction: number): (number, number)
	local reach = ease(f / reachFraction)
	local pull = ease((f - reachFraction) / (1 - reachFraction))
	local lead = if f < reachFraction then LOW + (HIGH - LOW) * reach else HIGH - (HIGH - MID) * pull
	local other = MID - (MID - LOW) * pull
	return lead, other
end

function ClimbPose.angles(mode: string, cycle: number, t: number, reachFraction: number): Angles
	if mode == "leap" then
		local s1, e1 = arm(1.05)
		return { shoulder = { s1, s1 }, elbow = { e1, e1 }, hip = { 5, 5 }, knee = { 10, 10 }, neck = 28, lean = -4 }
	elseif mode == "rest" then
		-- Both hands hooked over the rest bar, legs hanging with a slow sway.
		local sway = math.sin(t * 1.7) * 6
		local s1, e1 = arm(0.92)
		return {
			shoulder = { s1, s1 },
			elbow = { e1, e1 },
			hip = { 8 + sway, 8 - sway },
			knee = { 15, 15 },
			neck = 5,
			lean = -2,
		}
	end
	local move = math.floor(cycle)
	local f = cycle - move
	local rightLeads = move % 2 == 1
	local lead, other = ClimbPose.armRaise(f, reachFraction)
	-- The foot opposite the lead hand steps up during the reach, then pushes.
	local reach = ease(f / reachFraction)
	local pull = ease((f - reachFraction) / (1 - reachFraction))
	local step = if f < reachFraction then reach else 1 - pull
	local stepLift, plantLift = 0.25 + 0.75 * step, 0.25

	local leadS, leadE = arm(lead)
	local otherS, otherE = arm(other)
	local stepH, stepK = leg(stepLift)
	local plantH, plantK = leg(plantLift)
	local angles: Angles = {
		shoulder = if rightLeads then { otherS, leadS } else { leadS, otherS },
		elbow = if rightLeads then { otherE, leadE } else { leadE, otherE },
		-- left hand leads -> right foot steps
		hip = if rightLeads then { stepH, plantH } else { plantH, stepH },
		knee = if rightLeads then { stepK, plantK } else { plantK, stepK },
		neck = 22,
		lean = -10,
	}
	return angles
end

return ClimbPose
