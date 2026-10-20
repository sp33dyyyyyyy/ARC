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

-- Gamepass ownership rides along in the boosts table as "Pass_<Id>" = 1.
local function passPerks(passDefs: { any }?, boosts: Boosts, field: string): { number }
	local values = {}
	for _, pass in (passDefs or {}) :: { any } do
		if pass[field] ~= nil and level(boosts, "Pass_" .. pass.Id) > 0 then
			table.insert(values, pass[field])
		end
	end
	return values
end

-- Copy of `boosts` with owned gamepasses added as "Pass_<Id>" = 1.
function Rules.withPasses(boosts: Boosts, owned: { [string]: boolean }): Boosts
	local merged = table.clone(boosts)
	for id, has in owned do
		if has then
			merged["Pass_" .. id] = 1
		end
	end
	return merged
end

function Rules.maxStamina(staminaCfg: any, boostDefs: { any }, boosts: Boosts, passDefs: { any }?): number
	local def = boostDef(boostDefs, "Endurance")
	local bonus = 0
	for _, v in passPerks(passDefs, boosts, "StaminaBonus") do
		bonus += v
	end
	return staminaCfg.Base + (def and def.PerLevel or 0) * level(boosts, "Endurance") + bonus
end

-- Summit payout after gamepass multipliers (VIP doubles it).
function Rules.payout(base: number, passDefs: { any }?, boosts: Boosts): number
	local amount = base
	for _, v in passPerks(passDefs, boosts, "CashMultiplier") do
		amount *= v
	end
	return math.floor(amount)
end

export type DrainContext = {
	climbing: boolean,
	moving: boolean,
	towerMultiplier: number,
	slippery: boolean,
	chalk: boolean,
	gust: boolean,
	weatherMultiplier: number?, -- rain soaks the walls
	resting: boolean?, -- hands on a rest bar
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
	local rec = boostDef(boostDefs, "Recovery")
	local recovery = staminaCfg.RecoverPerSecond * (1 + (rec and rec.PerLevel or 0) * level(boosts, "Recovery"))
	if ctx.climbing and ctx.resting and not ctx.moving then
		return recovery * staminaCfg.RestBarRecoveryFraction
	end
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
		rate *= ctx.weatherMultiplier or 1
		return -rate
	elseif grounded then
		return recovery
	end
	return 0
end

function Rules.stepStamina(current: number, rate: number, dt: number, max: number): number
	return math.clamp(current + rate * dt, 0, max)
end

-- Wall crawl speed (studs/second) with the Quick Hands boost.
function Rules.climbSpeed(climbCfg: any, boostDefs: { any }, boosts: Boosts): number
	local def = boostDef(boostDefs, "ClimbSpeed")
	return climbCfg.ClimbSpeed * (1 + (def and def.PerLevel or 0) * level(boosts, "ClimbSpeed"))
end

-- Stamina a leap costs, given the (negative) stamina rate of climbing right now:
-- the same as crawling LungeDistance at base speed, times LungeCostFactor.
function Rules.lungeCost(climbCfg: any, climbingRate: number): number
	return math.abs(climbingRate) * (climbCfg.LungeDistance / climbCfg.ClimbSpeed) * climbCfg.LungeCostFactor
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

-- Emotes ----------------------------------------------------------------

function Rules.emoteDef(emoteDefs: { any }, id: string): any?
	for _, def in emoteDefs do
		if def.Id == id then
			return def
		end
	end
	return nil
end

function Rules.canBuyEmote(emoteDefs: { any }, owned: { [string]: boolean }, id: string, cash: number): PurchaseResult
	local def = Rules.emoteDef(emoteDefs, id)
	if not def then
		return { ok = false, reason = "Unknown emote" }
	end
	if owned[id] then
		return { ok = false, reason = "You already own " .. def.Name }
	end
	if cash < def.Price then
		return { ok = false, reason = "Not enough cash", cost = def.Price }
	end
	return { ok = true, cost = def.Price }
end

-- Free emotes are always owned.
function Rules.ownsEmote(emoteDefs: { any }, owned: { [string]: boolean }, id: string): boolean
	local def = Rules.emoteDef(emoteDefs, id)
	return def ~= nil and (def.Price == 0 or owned[id] == true)
end

-- Falls -----------------------------------------------------------------

function Rules.fallDamage(fallCfg: any, boostDefs: { any }, boosts: Boosts, drop: number, passDefs: { any }?): number
	if drop ~= drop or drop <= fallCfg.SafeDrop then -- drop ~= drop catches NaN
		return 0
	end
	local def = boostDef(boostDefs, "SoftLanding")
	local reduction = math.min(0.75, (def and def.PerLevel or 0) * level(boosts, "SoftLanding"))
	local damage = (drop - fallCfg.SafeDrop) * fallCfg.DamagePerStud * (1 - reduction)
	for _, v in passPerks(passDefs, boosts, "FallDamageMultiplier") do
		damage *= v
	end
	return damage
end

-- Admin ---------------------------------------------------------------------

-- Roblox usernames: 3-20 letters, digits or underscores.
function Rules.isValidUsername(name: any): boolean
	return type(name) == "string" and #name >= 3 and #name <= 20 and string.match(name, "^[%w_]+$") ~= nil
end

-- Whether `code` unlocks admin. An empty configured code never matches.
function Rules.adminCodeMatches(configured: any, code: any): boolean
	if type(configured) ~= "string" or type(code) ~= "string" then
		return false
	end
	if #configured < 6 or #code ~= #configured then
		return false
	end
	-- Compare every character so timing doesn't leak how much matched.
	local diff = 0
	for i = 1, #configured do
		diff += if string.byte(configured, i) == string.byte(code, i) then 0 else 1
	end
	return diff == 0
end

-- Rate limit for code attempts: returns allowed, newAttemptTimes.
function Rules.allowAttempt(adminCfg: any, attempts: { number }, now: number): (boolean, { number })
	local recent = {}
	for _, t in attempts do
		if now - t < adminCfg.AttemptWindow then
			table.insert(recent, t)
		end
	end
	if #recent >= adminCfg.MaxCodeAttempts then
		return false, recent
	end
	table.insert(recent, now)
	return true, recent
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

function Rules.defaultProfile(boostDefs: { any }, emoteDefs: { any }?): any
	local boosts = {}
	for _, def in boostDefs do
		boosts[def.Id] = 0
	end
	local emotes = {}
	for _, def in (emoteDefs or {}) :: { any } do
		if def.Price == 0 then
			emotes[def.Id] = true
		end
	end
	local first = emoteDefs and emoteDefs[1]
	return {
		GrantedPasses = {},
		Settings = { NameTags = true, CameraShake = true },
		Emotes = emotes,
		SummitEmote = if first then first.Id else "",
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
function Rules.reconcileProfile(boostDefs: { any }, chalkCfg: any, saved: any, emoteDefs: { any }?): any
	local profile = Rules.defaultProfile(boostDefs, emoteDefs)
	if type(saved) ~= "table" then
		return profile
	end
	for key, value in profile do
		if key ~= "Boosts" and key ~= "Emotes" and key ~= "GrantedPasses" and key ~= "Settings" and type(saved[key]) == type(value) then
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
	if type(saved.Emotes) == "table" then
		for _, def in (emoteDefs or {}) :: { any } do
			if saved.Emotes[def.Id] == true then
				profile.Emotes[def.Id] = true
			end
		end
	end
	if type(saved.GrantedPasses) == "table" then
		for id, has in saved.GrantedPasses do
			if type(id) == "string" and has == true and #id <= 32 then
				profile.GrantedPasses[id] = true
			end
		end
	end
	if type(saved.Settings) == "table" then
		for key, default in profile.Settings do
			if type(saved.Settings[key]) == type(default) then
				profile.Settings[key] = saved.Settings[key]
			end
		end
	end
	if emoteDefs and not Rules.ownsEmote(emoteDefs, profile.Emotes, profile.SummitEmote) then
		profile.SummitEmote = emoteDefs[1].Id
	end
	profile.Cash = math.max(0, math.floor(profile.Cash))
	profile.Climbs = math.max(0, math.floor(profile.Climbs))
	profile.Chalk = math.clamp(math.floor(profile.Chalk), 0, chalkCfg.MaxHeld)
	return profile
end

return Rules
