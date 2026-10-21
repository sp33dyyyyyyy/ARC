--!strict
-- StaminaMath: how fast grip stamina drains or recovers. Pure Luau (unit tested offline).
--
-- On the wall stamina drains, faster with fewer limbs on and on worse holds. It only comes
-- back when you REST: all four limbs on holds for a moment. At zero you peel off.
-- Off the wall it refills quickly.

export type Grip = {
	kind: "Hand" | "Foot",
	drain: number, -- the hold type's DrainMultiplier (jug 0.45 ... sloper 1.5)
	quality: number, -- the hold's Quality, 0..1
}

export type Tuning = {
	Max: number,
	DrainByLimbs: { number }, -- per second with 1, 2 or 3 limbs on, before hold factors
	FeetOnlyDrain: number, -- standing on footholds with no hands
	RestDelay: number, -- seconds with all four limbs on before recovery starts
	RestRecover: number, -- per second while resting (scaled by how good the hand holds are)
	GroundRecover: number, -- per second off the wall
}

local StaminaMath = {}

-- Stamina change per second for these grips. Negative drains, positive recovers.
-- `restingFor` is how long all four limbs have been on holds without moving.
function StaminaMath.rate(grips: { Grip }, restingFor: number, tuning: Tuning): number
	local count = #grips
	if count == 0 then
		return tuning.GroundRecover
	end

	local handDrain, handQuality, hands = 0, 0, 0
	for _, grip in grips do
		if grip.kind == "Hand" then
			hands += 1
			handDrain += grip.drain
			handQuality += math.clamp(grip.quality, 0, 1)
		end
	end
	local avgQuality = if hands > 0 then handQuality / hands else 0.6

	if count >= 4 then
		if restingFor < tuning.RestDelay then
			return 0
		end
		-- Resting on jugs recovers faster than hanging off crimps.
		return tuning.RestRecover * (0.6 + 0.4 * avgQuality)
	end
	if hands == 0 then
		return -tuning.FeetOnlyDrain
	end
	local holdFactor = handDrain / hands
	local qualityFactor = 1.3 - 0.6 * avgQuality
	return -(tuning.DrainByLimbs[count] * holdFactor * qualityFactor)
end

function StaminaMath.step(current: number, rate: number, dt: number, max: number): number
	return math.clamp(current + rate * dt, 0, max)
end

-- Seconds until stamina hits zero at `rate` (math.huge if it isn't draining).
function StaminaMath.secondsLeft(current: number, rate: number): number
	if rate >= 0 then
		return math.huge
	end
	return current / -rate
end

return table.freeze(StaminaMath)
