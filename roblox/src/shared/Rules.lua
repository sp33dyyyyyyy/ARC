--!strict
-- Pure game rules shared by server and client. No Roblox APIs and no requires:
-- every function takes the config tables it needs, so tests can run them in
-- plain Luau.

local Rules = {}

export type Boosts = { [string]: number }

local function boostDef(boostDefs: { any }, id: string): any?
	for _, def in boostDefs do
		if def.Id == id then
			return def
		end
	end
	return nil
end
Rules.boostDef = boostDef

local function level(boosts: Boosts, id: string): number
	return boosts[id] or 0
end

-- Stamina ---------------------------------------------------------------

function Rules.maxStamina(staminaCfg: any, boostDefs: { any }, boosts: Boosts): number
	local def = boostDef(boostDefs, "Endurance")
	return staminaCfg.Base + (def and def.PerLevel or 0) * level(boosts, "Endurance")
end

export type DrainContext = {
	climbing: boolean,
	moving: boolean,
	towerMultiplier: number,
	slippery: boolean,
	chalk: boolean,
	gust: boolean,
}

-- Stamina change per second for the given situation. Negative = draining.
function Rules.staminaRate(
	staminaCfg: any,
	chalkCfg: any,
	windCfg: any,
	boostDefs: { any },
	boosts: Boosts,
	ctx: DrainContext,
	grounded: boolean
): number
	if ctx.climbing then
		local rate = staminaCfg.DrainPerSecond * ctx.towerMultiplier
		if not ctx.moving then
			rate *= staminaCfg.HangDrainFraction
		end
		if ctx.slippery then
			local grip = boostDef(boostDefs, "Grip")
			rate *= math.max(0.2, 1 - (grip and grip.PerLevel or 0) * level(boosts, "Grip"))
		end
		if ctx.chalk then
			rate *= chalkCfg.DrainMultiplier
		end
		if ctx.gust then
			rate *= windCfg.DrainMultiplier
		end
		return -rate
	elseif grounded then
		local rec = boostDef(boostDefs, "Recovery")
		return staminaCfg.RecoverPerSecond * (1 + (rec and rec.PerLevel or 0) * level(boosts, "Recovery"))
	end
	return 0
end

function Rules.stepStamina(current: number, rate: number, dt: number, max: number): number
	return math.clamp(current + rate * dt, 0, max)
end

function Rules.climbWalkSpeed(climbCfg: any, boostDefs: { any }, boosts: Boosts): number
	local def = boostDef(boostDefs, "ClimbSpeed")
	return climbCfg.BaseWalkSpeed * (1 + (def and def.PerLevel or 0) * level(boosts, "ClimbSpeed"))
end

-- Shop ------------------------------------------------------------------

-- Cost to buy the next level, or nil when already maxed / unknown.
function Rules.boostCost(boostDefs: { any }, id: string, currentLevel: number): number?
	local def = boostDef(boostDefs, id)
	if not def or currentLevel >= def.MaxLevel or currentLevel < 0 then
		return nil
	end
	return math.floor(def.BaseCost * def.Growth ^ currentLevel + 0.5)
end

export type PurchaseResult = { ok: boolean, reason: string?, cost: number? }

function Rules.canBuyBoost(boostDefs: { any }, id: string, currentLevel: number, cash: number): PurchaseResult
	local maybeCost = Rules.boostCost(boostDefs, id, currentLevel)
	if not maybeCost then
		if boostDef(boostDefs, id) == nil then
			return { ok = false, reason = "Unknown boost" }
		end
		return { ok = false, reason = "Already maxed" }
	end
	local cost = maybeCost :: number
	if cash < cost then
		return { ok = false, reason = "Not enough cash", cost = cost }
	end
	return { ok = true, cost = cost }
end

function Rules.canBuyChalk(chalkCfg: any, held: number, cash: number): PurchaseResult
	if held >= chalkCfg.MaxHeld then
		return { ok = false, reason = "Chalk bag is full" }
	end
	if cash < chalkCfg.Price then
		return { ok = false, reason = "Not enough cash", cost = chalkCfg.Price }
	end
	return { ok = true, cost = chalkCfg.Price }
end

-- Falls -----------------------------------------------------------------

function Rules.fallDamage(fallCfg: any, boostDefs: { any }, boosts: Boosts, drop: number): number
	if drop ~= drop or drop <= fallCfg.SafeDrop then -- drop ~= drop catches NaN
		return 0
	end
	local def = boostDef(boostDefs, "SoftLanding")
	local reduction = math.min(0.75, (def and def.PerLevel or 0) * level(boosts, "SoftLanding"))
	return (drop - fallCfg.SafeDrop) * fallCfg.DamagePerStud * (1 - reduction)
end

-- Climb validation --------------------------------------------------------

export type ActiveClimb = { tower: string, startTime: number, paid: boolean }

-- Whether reaching the peak of `tower` at `now` earns a payout.
function Rules.validatePeak(climbCfg: any, active: ActiveClimb?, tower: string, height: number, now: number): (boolean, string?)
	if not active then
		return false, "Start the climb from the bottom of the tower"
	end
	local climb = active :: ActiveClimb
	if climb.tower ~= tower then
		return false, "Start the climb from the bottom of this tower"
	end
	if climb.paid then
		return false, "Already paid - head back down to climb again"
	end
	if now - climb.startTime < height / climbCfg.MaxPlausibleSpeed then
		return false, "Too fast to be real"
	end
	return true, nil
end

-- Daily reward ------------------------------------------------------------

-- Returns newStreak, reward, alreadyClaimed.
function Rules.dailyReward(dailyCfg: any, lastDay: number, streak: number, today: number): (number, number, boolean)
	if lastDay == today then
		return streak, 0, true
	end
	local newStreak = if lastDay == today - 1 then streak + 1 else 1
	local reward = dailyCfg.BaseReward * math.min(newStreak, dailyCfg.MaxStreakMultiplier)
	return newStreak, reward, false
end

-- Trails ------------------------------------------------------------------

function Rules.bestTrail(trails: { any }, climbs: number): any?
	local best = nil
	for _, t in trails do
		if climbs >= t.Climbs then
			best = t
		end
	end
	return best
end

-- Profiles ----------------------------------------------------------------

function Rules.defaultProfile(boostDefs: { any }): any
	local boosts = {}
	for _, def in boostDefs do
		boosts[def.Id] = 0
	end
	return {
		Version = 1,
		Cash = 0,
		Climbs = 0,
		Chalk = 0,
		Boosts = boosts,
		LastDaily = 0,
		Streak = 0,
		BestHeight = 0,
	}
end

-- Fill in anything missing from saved data (new fields added in updates) and
-- clamp values back into range so corrupt saves can't break the game.
function Rules.reconcileProfile(boostDefs: { any }, chalkCfg: any, saved: any): any
	local profile = Rules.defaultProfile(boostDefs)
	if type(saved) ~= "table" then
		return profile
	end
	for key, value in profile do
		if key ~= "Boosts" and type(saved[key]) == type(value) then
			profile[key] = saved[key]
		end
	end
	if type(saved.Boosts) == "table" then
		for _, def in boostDefs do
			local v = saved.Boosts[def.Id]
			if type(v) == "number" then
				profile.Boosts[def.Id] = math.clamp(math.floor(v), 0, def.MaxLevel)
			end
		end
	end
	profile.Cash = math.max(0, math.floor(profile.Cash))
	profile.Climbs = math.max(0, math.floor(profile.Climbs))
	profile.Chalk = math.clamp(math.floor(profile.Chalk), 0, chalkCfg.MaxHeld)
	return profile
end

return Rules
