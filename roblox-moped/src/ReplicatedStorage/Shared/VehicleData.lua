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

	-- SCOOTER ---------------------------------------------------------------
	-- Model: assets/models/aerox50.glb  (import it as ReplicatedStorage/VehicleModels/aerox50)
	{
		id = "aerox50",
		displayName = "Aerox 50",
		class = "Scooter",
		cc = 50,
		engineType = "Two-stroke",
		description = "Fast for a fifty. Twist, go, and mind the corners.",

		stats = {
			topSpeedKmh = 62,
			acceleration = 52,
			braking = 48,
			handling = 66,
			weightKg = 98,
			fuelCapacityL = 5.5,
		},

		price = 0, -- the free starter
		unlock = {}, -- no requirement

		colours = {
			{ name = "Cobalt Blue", body = Color3.fromRGB(41, 87, 172), accent = Color3.fromRGB(56, 123, 220) },
			{ name = "Signal Red", body = Color3.fromRGB(184, 38, 38), accent = Color3.fromRGB(232, 104, 92) },
		},

		-- Gearing: each entry = fraction of top speed reachable in that gear.
		-- "manual" bikes use Z / X to shift (auto-clutch, forgiving).
		-- "cvt" bikes have one fixed ratio (twist and go).
		drivetrain = {
			transmission = "cvt",
			gears = { 1.00 },
			powerband = { peak = 0.62, width = 0.70, floor = 0.50 }, -- broad and friendly
		},

		-- Starting procedure tuning (see VehicleService): kick lever AND a button
		starting = {
			kickChance = 0.60,
			electric = true,
			starterChance = 0.90,
		},

		fuel = {
			burnIdle = 0.0015, -- litres / second with engine idling
			burnFull = 0.0130, -- litres / second at full throttle
			reserveL = 0.7, -- litres you only reach with the tap on RESERVE
		},

		-- measured from the model: 1.28 m wheelbase, 0.268 m tyre radius, x 3.5 studs/m
		geometry = { wheelbase = 4.48, wheelRadius = 0.938, maxLeanDeg = 26, wheelie = 0.12 },
	},

	-- SUPERMOTO -------------------------------------------------------------
	-- Model: assets/models/supermoto80.glb  (-> VehicleModels/supermoto80)
	{
		id = "supermoto80",
		displayName = "Supermoto 80",
		class = "Supermoto",
		cc = 80,
		engineType = "Two-stroke",
		description = "Light, angry and nimble. Kick it, keep it on the pipe.",

		stats = {
			topSpeedKmh = 98,
			acceleration = 74,
			braking = 78,
			handling = 88,
			weightKg = 88,
			fuelCapacityL = 6.5,
		},

		price = VehicleData.priceFor(80),
		unlock = { owns = "aerox50", jobs = 4 },

		colours = {
			{ name = "Satin Black", body = Color3.fromRGB(26, 29, 36), accent = Color3.fromRGB(196, 203, 216) },
			{ name = "Safety Orange", body = Color3.fromRGB(232, 112, 28), accent = Color3.fromRGB(24, 26, 32) },
		},

		drivetrain = {
			transmission = "manual",
			gears = { 0.30, 0.52, 0.76, 1.00 },
			powerband = { peak = 0.72, width = 0.30, floor = 0.22 }, -- peaky!
		},

		starting = { kickChance = 0.40, electric = false },

		fuel = { burnIdle = 0.0022, burnFull = 0.0185, reserveL = 0.8 },

		-- measured from the model: 1.33 m wheelbase, 0.29 m tyre radius, x 3.5 studs/m
		geometry = { wheelbase = 4.655, wheelRadius = 1.015, maxLeanDeg = 36, wheelie = 0.80 },
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
	topSpeedKmh = 120,
	acceleration = 100,
	braking = 100,
	handling = 100,
	weightKg = 120,
	fuelCapacityL = 8,
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
