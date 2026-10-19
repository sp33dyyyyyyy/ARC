--[[
	PartsData  (ModuleScript, ReplicatedStorage/Shared)

	The aftermarket parts catalogue. One slot holds one part. Every part
	changes the bike's stat block a little; PartsData.apply() returns a COPY of
	a vehicle with its installed parts applied. Both the server (fuel, weight,
	crashes) and the client (physics) use that effective vehicle, so the upgrades
	really change how the bike rides.

	Add a part by adding a table to `list`:
	  id, slot, name, desc, base (price at 100cc), fits (optional), mods
	mods keys:
	  topPct      +/- % top speed         accel       +/- acceleration points
	  braking     +/- braking points      handling    +/- handling points
	  weightKg    +/- kg                  fuelPct     +/- % tank size
	  burnPct     +/- % fuel burn at full throttle
	fits keys:  twoStroke = true | fourStroke = true | class = "Moped"/"Supermoto"
]]

local PartsData = {}

PartsData.slots = {
	{ id = "exhaust", name = "Exhaust" },
	{ id = "intake", name = "Intake / carb" },
	{ id = "gearing", name = "Gearing" },
	{ id = "tyres", name = "Tyres" },
	{ id = "brakes", name = "Brakes" },
	{ id = "suspension", name = "Suspension" },
	{ id = "tank", name = "Fuel tank" },
	{ id = "frame", name = "Frame kit" },
}

PartsData.list = {
	-- exhaust
	{ id = "sport_exhaust", slot = "exhaust", name = "Sport exhaust", desc = "Free-flowing silencer. More punch up top.", base = 180, mods = { topPct = 6, accel = 6, weightKg = -1 } },
	{ id = "race_pipe", slot = "exhaust", name = "Expansion chamber", desc = "Two-stroke only. Loud, narrow, fast.", base = 420, fits = { twoStroke = true }, mods = { topPct = 10, accel = 12, weightKg = -1.5, burnPct = 12 } },
	{ id = "titan_exhaust", slot = "exhaust", name = "Titanium system", desc = "Four-stroke only. Light and strong.", base = 380, fits = { fourStroke = true }, mods = { topPct = 9, accel = 8, weightKg = -3 } },
	-- intake
	{ id = "air_kit", slot = "intake", name = "Air filter + jet kit", desc = "Breathes better. Small but cheap gain.", base = 120, mods = { accel = 4, topPct = 2 } },
	{ id = "big_carb", slot = "intake", name = "Big carburettor", desc = "Much more power, much thirstier.", base = 210, mods = { accel = 8, topPct = 3, burnPct = 18 } },
	-- gearing
	{ id = "short_gear", slot = "gearing", name = "Short gearing", desc = "Snappy off the line, lower top speed.", base = 90, mods = { accel = 9, topPct = -5 } },
	{ id = "long_gear", slot = "gearing", name = "Long gearing", desc = "Higher top speed, lazier launch.", base = 90, mods = { accel = -5, topPct = 6 } },
	-- tyres
	{ id = "road_tyres", slot = "tyres", name = "Road tyres", desc = "Better grip than the old rubber.", base = 90, mods = { handling = 6, braking = 3 } },
	{ id = "sport_tyres", slot = "tyres", name = "Sport tyres", desc = "Sticky. Red-ribbed tread.", base = 160, mods = { handling = 11, braking = 7 } },
	-- brakes
	{ id = "steel_lines", slot = "brakes", name = "Braided lines + pads", desc = "Firm lever, shorter stops.", base = 140, mods = { braking = 10 } },
	{ id = "big_disc", slot = "brakes", name = "Big disc kit", desc = "Huge rotor, red caliper.", base = 260, mods = { braking = 17, weightKg = 1.2 } },
	-- suspension
	{ id = "fork_springs", slot = "suspension", name = "Stiffer fork springs", desc = "Less dive, sharper turn-in.", base = 150, mods = { handling = 8 } },
	{ id = "race_suspension", slot = "suspension", name = "Race suspension", desc = "Supermoto only. Gold forks.", base = 340, fits = { class = "Supermoto" }, mods = { handling = 15, weightKg = 0.5 } },
	-- tank
	{ id = "big_tank", slot = "tank", name = "Big tank", desc = "+30% fuel. Heavier.", base = 170, mods = { fuelPct = 30, weightKg = 2 } },
	-- frame
	{ id = "light_frame", slot = "frame", name = "Lightweight kit", desc = "Alloy bits everywhere.", base = 300, mods = { weightKg = -5, accel = 2, handling = 3 } },
}

PartsData.byId = {}
for _, p in ipairs(PartsData.list) do
	PartsData.byId[p.id] = p
end
PartsData.slotName = {}
for _, s in ipairs(PartsData.slots) do
	PartsData.slotName[s.id] = s.name
end

-- Can this part go on this vehicle? returns ok, reason
function PartsData.fits(part, vehicle): (boolean, string)
	local f = part.fits
	if not f then
		return true, ""
	end
	local twoStroke = vehicle.engineType == "Two-stroke"
	if f.twoStroke and not twoStroke then
		return false, "two-stroke engines only"
	end
	if f.fourStroke and twoStroke then
		return false, "four-stroke engines only"
	end
	if f.class and vehicle.class ~= f.class then
		return false, f.class .. "s only"
	end
	return true, ""
end

-- Parts cost more for bigger engines.
function PartsData.price(part, vehicle): number
	local scale = 0.7 + 0.3 * vehicle.cc / 100
	return math.ceil(part.base * scale / 5) * 5
end

-- A COPY of `vehicle` with the listed parts applied (stats + fuel burn).
function PartsData.apply(vehicle, mods: { string }?)
	local v = table.clone(vehicle)
	v.stats = table.clone(vehicle.stats)
	v.fuel = table.clone(vehicle.fuel)
	v.baseVehicle = vehicle
	v.mods = mods or {}

	local top, accel, braking, handling, weight, fuelPct, burn = 0, 0, 0, 0, 0, 0, 0
	for _, id in ipairs(mods or {}) do
		local part = PartsData.byId[id]
		if part then
			local m = part.mods
			top += m.topPct or 0
			accel += m.accel or 0
			braking += m.braking or 0
			handling += m.handling or 0
			weight += m.weightKg or 0
			fuelPct += m.fuelPct or 0
			burn += m.burnPct or 0
		end
	end
	local s = v.stats
	s.topSpeedKmh = vehicle.stats.topSpeedKmh * math.clamp(1 + top / 100, 0.8, 1.4)
	s.acceleration = math.clamp(vehicle.stats.acceleration + accel, 5, 100)
	s.braking = math.clamp(vehicle.stats.braking + braking, 5, 100)
	s.handling = math.clamp(vehicle.stats.handling + handling, 5, 100)
	s.weightKg = math.max(40, vehicle.stats.weightKg + weight)
	s.fuelCapacityL = vehicle.stats.fuelCapacityL * (1 + fuelPct / 100)
	v.fuel.burnFull = vehicle.fuel.burnFull * (1 + burn / 100)
	return v
end

-- "Top speed +6% · Accel +6 · -1 kg" for the shop / workshop lists.
function PartsData.describe(part): string
	local m = part.mods
	local out = {}
	local function add(value: number?, label: string, unit: string)
		if value and value ~= 0 then
			table.insert(out, ("%s %s%g%s"):format(label, value > 0 and "+" or "-", math.abs(value), unit))
		end
	end
	add(m.topPct, "Top speed", "%")
	add(m.accel, "Accel", "")
	add(m.braking, "Braking", "")
	add(m.handling, "Handling", "")
	add(m.weightKg, "Weight", " kg")
	add(m.fuelPct, "Tank", "%")
	add(m.burnPct, "Fuel use", "%")
	return table.concat(out, "  ·  ")
end

-- Cached PartsData.apply for a bike model's `Mods` attribute string (the HUD
-- and the physics ask every frame).
local effectiveCache = {}
function PartsData.effective(vehicle, modsText: string?)
	local key = vehicle.id .. "|" .. (modsText or "")
	local v = effectiveCache[key]
	if not v then
		v = PartsData.apply(vehicle, PartsData.decode(modsText))
		effectiveCache[key] = v
	end
	return v
end

-- "sport_exhaust,big_tank" <-> { "sport_exhaust", "big_tank" }
function PartsData.encode(mods: { string }): string
	return table.concat(mods, ",")
end

function PartsData.decode(text: string?): { string }
	local out = {}
	for id in string.gmatch(text or "", "[^,]+") do
		if PartsData.byId[id] then
			table.insert(out, id)
		end
	end
	return out
end

-- profile.parts[bikeId] = { owned = { [partId] = true }, installed = { [slot] = partId } }
function PartsData.installedList(profile, bikeId: string): { string }
	local entry = profile.parts and profile.parts[bikeId]
	local out = {}
	if entry then
		for _, slot in ipairs(PartsData.slots) do
			local id = entry.installed[slot.id]
			if id and PartsData.byId[id] then
				table.insert(out, id)
			end
		end
	end
	return out
end

return PartsData
