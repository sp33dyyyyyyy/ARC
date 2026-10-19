--[[
	VehicleData  (ModuleScript, ReplicatedStorage/Shared)

	THE one file you edit to add or tweak bikes. Everything else (garage UI,
	physics, fuel, starting procedure, prices) reads from the tables below.

	Rules enforced at load time (see validate()):
	  * 50cc <= cc <= 200cc
	  * exactly two colour options per bike
	  * unique ids

	Units
	  topSpeedKmh   real-world feel. 1 km/h ~= 0.99 studs/s (GameConfig.StudsPerKmh)
	  acceleration  0-100 stat (higher = punchier)
	  braking       0-100 stat
	  handling      0-100 stat (turn-in speed, steering angle)
	  weightKg      dry weight. Fuel adds 0.74 kg per litre. Also sets how hard
	                the bike is to PUSH (see BikePhysics.pushLimits)
	  fuelCapacityL tank size in litres
]]

local VehicleData = {}

----------------------------------------------------------------------------
-- Price scales with engine size: price = k * cc^1.5, rounded to nearest 100.
----------------------------------------------------------------------------
local PRICE_K = 3.0
function VehicleData.priceFor(cc: number): number
	return math.floor((PRICE_K * cc ^ 1.5) / 100 + 0.5) * 100
end

-- Repairs scale with engine size too (euro per health point).
function VehicleData.repairCostPerPoint(vehicle): number
	return math.max(1, math.floor(vehicle.cc * 0.04 + 0.5))
end

----------------------------------------------------------------------------
-- The roster. Order here = order in the garage list.
----------------------------------------------------------------------------
local list = {

	-- MOPED A ---------------------------------------------------------------
	{
		id = "spatz50",
		displayName = "Spatz 50",
		class = "Moped",
		cc = 50,
		engineType = "Two-stroke",
		description = "Rattly, cheerful and thirsty. Smells of premix and freedom.",

		stats = {
			topSpeedKmh = 45,
			acceleration = 35,
			braking = 30,
			handling = 55,
			weightKg = 85,
			fuelCapacityL = 4.0,
		},

		price = 0, -- the free starter
		unlock = {}, -- no requirement

		colours = {
			{ name = "Butter Yellow", body = Color3.fromRGB(240, 205, 70), accent = Color3.fromRGB(235, 235, 225) },
			{ name = "Fern Green", body = Color3.fromRGB(88, 140, 84), accent = Color3.fromRGB(240, 225, 190) },
		},

		-- Gearing: each entry = fraction of top speed reachable in that gear.
		-- "manual" bikes use Z / X to shift (auto-clutch, forgiving).
		-- "cvt" bikes have one fixed ratio (twist and go).
		drivetrain = {
			transmission = "manual",
			gears = { 0.50, 1.00 },
			-- Two-stroke power band: weak low down, snaps awake near `peak`.
			powerband = { peak = 0.68, width = 0.36, floor = 0.30 },
		},

		-- Starting procedure tuning (see VehicleService)
		starting = {
			kickChance = 0.42, -- base chance per kick when conditions are right
			electric = false,
		},

		fuel = {
			burnIdle = 0.0020, -- litres / second with engine idling
			burnFull = 0.0160, -- litres / second at full throttle
			reserveL = 0.5, -- litres you only reach with the tap on RESERVE
		},

		geometry = { wheelbase = 4.0, wheelRadius = 0.85, maxLeanDeg = 20, wheelie = 0.10 },
	},

	-- MOPED B ---------------------------------------------------------------
	{
		id = "kuckuck100",
		displayName = "Kuckuck 100",
		class = "Moped",
		cc = 100,
		engineType = "Four-stroke",
		description = "Calm, stable and quiet-ish. The sensible choice. Allegedly.",

		stats = {
			topSpeedKmh = 70,
			acceleration = 50,
			braking = 45,
			handling = 70,
			weightKg = 105,
			fuelCapacityL = 6.0,
		},

		price = VehicleData.priceFor(100),
		unlock = { jobs = 5, owns = "spatz50" },

		colours = {
			{ name = "Brick Red", body = Color3.fromRGB(176, 58, 46), accent = Color3.fromRGB(230, 225, 210) },
			{ name = "Alpine White", body = Color3.fromRGB(235, 237, 240), accent = Color3.fromRGB(60, 100, 160) },
		},

		drivetrain = {
			transmission = "cvt", -- twist-and-go variomatic
			gears = { 1.00 },
			powerband = { peak = 0.60, width = 0.70, floor = 0.55 }, -- broad and friendly
		},

		starting = { kickChance = 0.60, electric = false },

		fuel = { burnIdle = 0.0010, burnFull = 0.0100, reserveL = 0.8 },

		geometry = { wheelbase = 4.4, wheelRadius = 0.90, maxLeanDeg = 24, wheelie = 0.15 },
	},

	-- SUPERMOTO A -----------------------------------------------------------
	{
		id = "wiesel125",
		displayName = "Wiesel 125",
		class = "Supermoto",
		cc = 125,
		engineType = "Two-stroke",
		description = "Light, angry and nimble. Front wheel optional.",

		stats = {
			topSpeedKmh = 105,
			acceleration = 75,
			braking = 80,
			handling = 85,
			weightKg = 95,
			fuelCapacityL = 7.0,
		},

		price = VehicleData.priceFor(125),
		unlock = { earned = 4000 }, -- lifetime earnings

		colours = {
			{ name = "Signal Orange", body = Color3.fromRGB(240, 120, 30), accent = Color3.fromRGB(30, 30, 34) },
			{ name = "Slate Blue", body = Color3.fromRGB(70, 96, 140), accent = Color3.fromRGB(240, 240, 240) },
		},

		drivetrain = {
			transmission = "manual",
			gears = { 0.22, 0.40, 0.60, 0.80, 1.00 },
			powerband = { peak = 0.72, width = 0.30, floor = 0.22 }, -- peaky!
		},

		starting = { kickChance = 0.38, electric = false },

		fuel = { burnIdle = 0.0025, burnFull = 0.0220, reserveL = 0.8 },

		geometry = { wheelbase = 4.6, wheelRadius = 1.00, maxLeanDeg = 36, wheelie = 0.90 },
	},

	-- SUPERMOTO B -----------------------------------------------------------
	{
		id = "dachs200",
		displayName = "Dachs 200",
		class = "Supermoto",
		cc = 200,
		engineType = "Four-stroke",
		description = "Heavy, fast, brakes like a wall. Has an electric starter. Posh.",

		stats = {
			topSpeedKmh = 135,
			acceleration = 85,
			braking = 95,
			handling = 70,
			weightKg = 135,
			fuelCapacityL = 9.5,
		},

		price = VehicleData.priceFor(200),
		unlock = { owns = "wiesel125", jobs = 20 },

		colours = {
			{ name = "Racing Black", body = Color3.fromRGB(32, 33, 38), accent = Color3.fromRGB(215, 40, 40) },
			{ name = "Rapeseed Yellow", body = Color3.fromRGB(238, 196, 36), accent = Color3.fromRGB(40, 40, 44) },
		},

		drivetrain = {
			transmission = "manual",
			gears = { 0.20, 0.38, 0.56, 0.78, 1.00 },
			powerband = { peak = 0.62, width = 0.60, floor = 0.45 }, -- torquey
		},

		starting = {
			kickChance = 0.50,
			electric = true, -- also has a starter button (battery drains on failed tries)
			starterChance = 0.88,
		},

		fuel = { burnIdle = 0.0015, burnFull = 0.0200, reserveL = 1.2 },

		geometry = { wheelbase = 5.0, wheelRadius = 1.05, maxLeanDeg = 32, wheelie = 0.45 },
	},
}

----------------------------------------------------------------------------
-- Validation + lookup tables
----------------------------------------------------------------------------
local MIN_CC, MAX_CC = 50, 200

local function validate(vehicles)
	local seen = {}
	for _, v in ipairs(vehicles) do
		assert(type(v.id) == "string" and not seen[v.id], "VehicleData: duplicate or missing id")
		seen[v.id] = true
		assert(v.cc >= MIN_CC and v.cc <= MAX_CC, ("VehicleData: %s is %dcc, must be %d-%dcc"):format(v.id, v.cc, MIN_CC, MAX_CC))
		assert(#v.colours == 2, "VehicleData: " .. v.id .. " needs exactly 2 colours")
		assert(#v.drivetrain.gears >= 1, "VehicleData: " .. v.id .. " needs at least one gear")
		assert(v.stats.weightKg > 0 and v.stats.fuelCapacityL > 0, "VehicleData: bad stats for " .. v.id)
	end
end
validate(list)

VehicleData.list = list
VehicleData.byId = {}
for _, v in ipairs(list) do
	VehicleData.byId[v.id] = v
end

-- Largest value of each bar stat, so the garage can draw proportional bars.
VehicleData.statMax = {
	topSpeedKmh = 140,
	acceleration = 100,
	braking = 100,
	handling = 100,
	weightKg = 140,
	fuelCapacityL = 10,
}

function VehicleData.get(id: string)
	return VehicleData.byId[id]
end

----------------------------------------------------------------------------
-- Unlock check shared by client (to show text) and server (to enforce).
-- `profile` needs: owned (dict), jobs (number), earned (number)
-- Returns ok, reasonText
----------------------------------------------------------------------------
function VehicleData.checkUnlock(vehicle, profile): (boolean, string)
	local u = vehicle.unlock
	if u.owns and not profile.owned[u.owns] then
		local need = VehicleData.byId[u.owns]
		return false, "Own the " .. (need and need.displayName or u.owns) .. " first"
	end
	if u.jobs and (profile.jobs or 0) < u.jobs then
		return false, ("Complete %d jobs (%d/%d)"):format(u.jobs, profile.jobs or 0, u.jobs)
	end
	if u.earned and (profile.earned or 0) < u.earned then
		return false, ("Earn EUR %d in total (%d so far)"):format(u.earned, profile.earned or 0)
	end
	return true, ""
end

return VehicleData
