-- Plain-Luau test runner for the pure game rules: `luau tests/run.lua`
local Config = require("../src/shared/Config")
local Rules = require("../src/shared/Rules")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. "\n     " .. tostring(err))
	end
end

local function eq(actual, expected, msg: string?)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, msg: string?)
	if math.abs(actual - expected) > 1e-6 then
		error(string.format("%sexpected ~%s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 2)
	end
end

local B = Config.Boosts
local S, C, W, F = Config.Stamina, Config.Chalk, Config.Wind, Config.Fall
local none = {}

local function ctx(over)
	local c = { climbing = false, moving = false, towerMultiplier = 1, slippery = false, chalk = false, gust = false }
	for k, v in over do
		c[k] = v
	end
	return c
end

-- Stamina
test("max stamina scales with endurance", function()
	eq(Rules.maxStamina(S, B, none), 100)
	eq(Rules.maxStamina(S, B, { Endurance = 4 }), 200)
end)

test("climbing drains by tower multiplier", function()
	near(Rules.staminaRate(S, C, W, B, none, ctx({ climbing = true, moving = true, towerMultiplier = 2.5 }), false), -20)
end)

test("hanging still drains at a quarter", function()
	near(Rules.staminaRate(S, C, W, B, none, ctx({ climbing = true, moving = false }), false), -2)
end)

test("grip only helps on slippery towers, chalk and gust stack", function()
	local grip = { Grip = 5 }
	near(Rules.staminaRate(S, C, W, B, grip, ctx({ climbing = true, moving = true }), false), -8)
	near(Rules.staminaRate(S, C, W, B, grip, ctx({ climbing = true, moving = true, slippery = true }), false), -8 * 0.6)
	near(Rules.staminaRate(S, C, W, B, none, ctx({ climbing = true, moving = true, chalk = true, gust = true }), false), -8 * 0.5 * W.DrainMultiplier)
end)

test("grounded recovers, boosted by recovery; airborne is neutral", function()
	near(Rules.staminaRate(S, C, W, B, none, ctx({}), true), 22)
	near(Rules.staminaRate(S, C, W, B, { Recovery = 2 }, ctx({}), true), 33)
	eq(Rules.staminaRate(S, C, W, B, none, ctx({}), false), 0)
end)

test("stamina clamps to [0, max]", function()
	eq(Rules.stepStamina(5, -20, 1, 100), 0)
	eq(Rules.stepStamina(95, 22, 1, 100), 100)
end)

test("climb speed boost", function()
	near(Rules.climbSpeed(Config.Climb, B, none), Config.Climb.ClimbSpeed)
	near(Rules.climbSpeed(Config.Climb, B, { ClimbSpeed = 5 }), Config.Climb.ClimbSpeed * 1.5)
end)

test("lunge costs more than crawling the same distance", function()
	-- a leap costs the same as climbing its distance, times LungeCostFactor
	local seconds = Config.Climb.LungeDistance / Config.Climb.ClimbSpeed
	near(Rules.lungeCost(Config.Climb, -8), 8 * seconds * Config.Climb.LungeCostFactor)
	near(Rules.lungeCost(Config.Climb, -16), 16 * seconds * Config.Climb.LungeCostFactor)
end)

test("hanging still on a rest bar recovers; climbing past one still drains", function()
	near(Rules.staminaRate(S, C, W, B, none, ctx({ climbing = true, resting = true }), false), 22 * 0.7)
	near(Rules.staminaRate(S, C, W, B, { Recovery = 2 }, ctx({ climbing = true, resting = true }), false), 33 * 0.7)
	near(Rules.staminaRate(S, C, W, B, none, ctx({ climbing = true, moving = true, resting = true }), false), -8)
end)

test("hanging still on the clipped rope recovers at half rate", function()
	near(Rules.staminaRate(S, C, W, B, none, ctx({ climbing = true, roped = true }), false), 22 * 0.5)
	near(Rules.staminaRate(S, C, W, B, none, ctx({ climbing = true, moving = true, roped = true }), false), -8)
end)

test("rappel kit is a single purchase", function()
	eq(Rules.boostCost(B, "Rappel", 0), 2500)
	eq(Rules.boostCost(B, "Rappel", 1), nil)
end)

test("rain soaks the walls", function()
	near(Rules.staminaRate(S, C, W, B, none, ctx({ climbing = true, moving = true, weatherMultiplier = 1.25 }), false), -10)
	near(Rules.staminaRate(S, C, W, B, none, ctx({ weatherMultiplier = 1.25 }), true), 22) -- recovery unaffected
end)

-- Shop
test("boost cost grows and caps at max level", function()
	eq(Rules.boostCost(B, "Endurance", 0), 100)
	eq(Rules.boostCost(B, "Endurance", 1), 160)
	eq(Rules.boostCost(B, "Endurance", 10), nil)
	eq(Rules.boostCost(B, "Nope", 0), nil)
	eq(Rules.boostCost(B, "Endurance", -1), nil)
end)

test("purchase validation", function()
	eq(Rules.canBuyBoost(B, "Endurance", 0, 99).reason, "Not enough cash")
	eq(Rules.canBuyBoost(B, "Endurance", 0, 100).ok, true)
	eq(Rules.canBuyBoost(B, "Endurance", 10, 1e9).reason, "Already maxed")
	eq(Rules.canBuyBoost(B, "Hack", 0, 1e9).reason, "Unknown boost")
	eq(Rules.canBuyChalk(C, 10, 1e9).ok, false)
	eq(Rules.canBuyChalk(C, 0, 75).ok, true)
end)

-- Gamepasses
test("gamepass perks: VIP cash, Iron Lungs stamina, Featherweight falls", function()
	local P = Config.GamePasses
	local owned = Rules.withPasses({}, { VIP = true, IronLungs = true, Featherweight = true })
	eq(Rules.payout(1000, P, {}), 1000)
	eq(Rules.payout(1000, P, owned), 2000)
	eq(Rules.maxStamina(S, B, {}, P), 100)
	eq(Rules.maxStamina(S, B, owned, P), 150)
	near(Rules.fallDamage(F, B, owned, 140, P), 45)
	near(Rules.fallDamage(F, B, {}, 140, P), 90)
	eq(Rules.withPasses({ Endurance = 2 }, { VIP = false }).Pass_VIP, nil)
end)

-- Admin
test("admin code: exact match only, empty or short codes never unlock", function()
	eq(Rules.adminCodeMatches("SKY-1234", "SKY-1234"), true)
	eq(Rules.adminCodeMatches("SKY-1234", "SKY-1235"), false)
	eq(Rules.adminCodeMatches("SKY-1234", "SKY-123"), false)
	eq(Rules.adminCodeMatches("", ""), false)
	eq(Rules.adminCodeMatches("abc", "abc"), false)
	eq(Rules.adminCodeMatches("SKY-1234", nil), false)
end)

test("the admin password is Evan123, exactly", function()
	local AdminConfig = require("../src/server/AdminConfig")
	eq(Rules.adminCodeMatches(AdminConfig.Password, "Evan123"), true)
	eq(Rules.adminCodeMatches(AdminConfig.Password, "evan123"), false)
	eq(Rules.adminCodeMatches(AdminConfig.Password, "Evan12"), false)
	eq(Rules.adminCodeMatches(AdminConfig.Password, ""), false)
end)

test("admin code attempts are rate limited", function()
	local A = Config.Admin
	local attempts = {}
	local ok
	for i = 1, A.MaxCodeAttempts do
		ok, attempts = Rules.allowAttempt(A, attempts, i)
		eq(ok, true)
	end
	ok, attempts = Rules.allowAttempt(A, attempts, 10)
	eq(ok, false)
	ok = Rules.allowAttempt(A, attempts, 10 + A.AttemptWindow)
	eq(ok, true)
end)

test("usernames are validated", function()
	eq(Rules.isValidUsername("Builderman"), true)
	eq(Rules.isValidUsername("a_b_c"), true)
	eq(Rules.isValidUsername("ab"), false)
	eq(Rules.isValidUsername("bad name"), false)
	eq(Rules.isValidUsername(string.rep("x", 21)), false)
	eq(Rules.isValidUsername(42), false)
end)

test("profiles keep granted passes and settings", function()
	local p = Rules.reconcileProfile(B, C, { GrantedPasses = { VIP = true, Bad = "yes" }, Settings = { NameTags = false, CameraShake = "no" } }, Config.Emotes)
	eq(p.GrantedPasses.VIP, true)
	eq(p.GrantedPasses.Bad, nil)
	eq(p.Settings.NameTags, false)
	eq(p.Settings.CameraShake, true)
end)

-- Emotes
test("emotes: free ones owned, buying checks cash and ownership", function()
	local E = Config.Emotes
	eq(Rules.ownsEmote(E, {}, "Wave"), true)
	eq(Rules.ownsEmote(E, {}, "Dance"), false)
	eq(Rules.ownsEmote(E, { Dance = true }, "Dance"), true)
	eq(Rules.ownsEmote(E, {}, "Nope"), false)
	eq(Rules.canBuyEmote(E, {}, "Dance", 999).reason, "Not enough cash")
	eq(Rules.canBuyEmote(E, {}, "Dance", 1000).ok, true)
	eq(Rules.canBuyEmote(E, { Dance = true }, "Dance", 1e9).ok, false)
	eq(Rules.canBuyEmote(E, {}, "Hack", 1e9).reason, "Unknown emote")
end)

test("profiles keep owned emotes and fix an unowned summit emote", function()
	local E = Config.Emotes
	local p = Rules.reconcileProfile(B, C, { Emotes = { Cheer = true, Fake = true }, SummitEmote = "Dance3" }, E)
	eq(p.Emotes.Cheer, true)
	eq(p.Emotes.Wave, true)
	eq(p.Emotes.Fake, nil)
	eq(p.SummitEmote, "Wave")
	eq(Rules.reconcileProfile(B, C, { Emotes = { Cheer = true }, SummitEmote = "Cheer" }, E).SummitEmote, "Cheer")
end)

-- Falls
test("fall damage: safe drop, scaling, soft landing cap, NaN", function()
	eq(Rules.fallDamage(F, B, none, 40), 0)
	near(Rules.fallDamage(F, B, none, 140), 90)
	near(Rules.fallDamage(F, B, { SoftLanding = 5 }, 140), 90 * 0.25)
	eq(Rules.fallDamage(F, B, none, 0 / 0), 0)
end)

-- Climb validation
test("peak payout requires a matching, unpaid, plausible climb", function()
	local cc = Config.Climb
	eq((Rules.validatePeak(cc, nil, "A", 200, 100)), false)
	eq((Rules.validatePeak(cc, { tower = "B", startTime = 0, paid = false }, "A", 200, 100)), false)
	eq((Rules.validatePeak(cc, { tower = "A", startTime = 0, paid = true }, "A", 200, 100)), false)
	eq((Rules.validatePeak(cc, { tower = "A", startTime = 99, paid = false }, "A", 200, 100)), false)
	eq((Rules.validatePeak(cc, { tower = "A", startTime = 0, paid = false }, "A", 200, 100)), true)
end)

-- Daily
test("daily reward streaks, resets and caps", function()
	local d = Config.Daily
	local s, r, claimed = Rules.dailyReward(d, 10, 3, 10)
	eq(claimed, true)
	eq(r, 0)
	eq(s, 3)
	s, r = Rules.dailyReward(d, 10, 3, 11)
	eq(s, 4)
	eq(r, 400)
	s, r = Rules.dailyReward(d, 5, 3, 11)
	eq(s, 1)
	eq(r, 100)
	s, r = Rules.dailyReward(d, 10, 20, 11)
	eq(r, 700)
end)

-- Trails
test("best trail", function()
	eq(Rules.bestTrail(Config.Trails, 4), nil)
	eq(Rules.bestTrail(Config.Trails, 15).Name, "Silver")
	eq(Rules.bestTrail(Config.Trails, 1000).Name, "Neon")
end)

-- Profiles
test("reconcile fills defaults and clamps corrupt data", function()
	local p = Rules.reconcileProfile(B, C, { Cash = -5, Climbs = 3.7, Chalk = 99, Boosts = { Endurance = 50, Grip = "x" }, Junk = 1 })
	eq(p.Cash, 0)
	eq(p.Climbs, 3)
	eq(p.Chalk, 10)
	eq(p.Boosts.Endurance, 10)
	eq(p.Boosts.Grip, 0)
	eq(p.Junk, nil)
	eq(Rules.reconcileProfile(B, C, nil).Version, 1)
end)

-- Config sanity: every value the tower builder relies on
test("tower configs are buildable", function()
	for name, t in Config.TowerTypes do
		if t.Kind == "Telecom" then
			assert(t.SectionHeight >= 10, name .. " sections too short")
			assert(t.TopHalfWidth >= 3, name .. " top too narrow to climb")
			assert(t.BaseHalfWidth > t.TopHalfWidth, name .. " must taper")
		else
			eq(t.Height % t.BalconyEvery, 0, name .. " height must be a multiple of the balcony spacing")
		end
	end
	for _, entry in Config.Layout do
		assert(Config.TowerTypes[entry.Type], "unknown tower type " .. entry.Type)
	end
end)

test("towers are at least 3.5x the original heights, except the tutorial", function()
	local function height(t)
		return if t.Kind == "Telecom" then t.SectionHeight * t.Sections else t.Height
	end
	eq(height(Config.TowerTypes.Tutorial), 80)
	-- originals: lattice 200, skyscraper 400, supertall 800
	assert(height(Config.TowerTypes.TelecomMedium) >= 200 * 3.5)
	assert(height(Config.TowerTypes.TelecomTall) >= 200 * 3.5)
	assert(height(Config.TowerTypes.SkySmall) >= 400 * 3.5)
	assert(height(Config.TowerTypes.SkyMedium) >= 400 * 3.5)
	assert(height(Config.TowerTypes.SkyLarge) >= 800 * 3.5)
end)

test("every tower is beatable with maxed boosts, even in the rain", function()
	-- worst rest-to-rest stretch with max endurance, grip, climb speed, no chalk, raining
	local maxed = {}
	for _, def in B do
		maxed[def.Id] = def.MaxLevel
	end
	local maxStamina = Rules.maxStamina(S, B, maxed)
	local speed = Rules.climbSpeed(Config.Climb, B, maxed)
	for name, t in Config.TowerTypes do
		local stretch = if t.Kind == "Telecom" then t.SectionHeight else t.BalconyEvery
		local rate = Rules.staminaRate(S, C, W, B, maxed, ctx({ climbing = true, moving = true, towerMultiplier = t.DrainMultiplier, slippery = t.Slippery, weatherMultiplier = Config.Weather.RainDrainMultiplier }), false)
		local cost = -rate * stretch / speed
		assert(cost < maxStamina * 0.9, string.format("%s needs %.0f stamina per stretch, max is %.0f", name, cost, maxStamina))
	end
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
