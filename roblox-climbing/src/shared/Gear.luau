--!strict
-- Gear: everything you can buy at the pro shop, and what it does. Shared so the server
-- (ShopService, StaminaService, RopeService) and the shop UI agree.
--
-- Slots: one item equipped per slot. The free item in each slot is owned from the start.
--   Shoes     less stamina drain while a foot is on a hold
--   ChalkBag  chalk lasts longer and helps more
--   Harness   dynos cost less stamina
--   Pack      the bag on your back (looks only; colour it at the lockers)
--   Rope      your rope's colour outdoors (looks only)

export type Slot = "Shoes" | "ChalkBag" | "Harness" | "Pack" | "Rope"

export type Stats = {
	footDrain: number?, -- multiplies stamina drain while at least one foot is on
	chalkRate: number?, -- chalk used per second on the wall
	chalkReduction: number?, -- how much slower stamina drains with full chalk
	dynoCost: number?, -- stamina per dyno
	ropeColor: Color3?,
}

export type Item = {
	id: string,
	slot: Slot,
	name: string,
	description: string,
	price: number, -- gems; 0 = owned from the start
	order: number,
	stats: Stats,
}

local Gear = {}

local SLOTS: { Slot } = { "Shoes", "ChalkBag", "Harness", "Pack", "Rope" }
Gear.SLOTS = table.freeze(SLOTS)
Gear.SLOT_NAMES = table.freeze({ Shoes = "Shoes", ChalkBag = "Chalk", Harness = "Harness", Pack = "Bags", Rope = "Ropes" })

local ITEMS: { Item } = {
	{ id = "RentalShoes", slot = "Shoes", name = "Rental Shoes", description = "Comfy, flat and a bit slippy.", price = 0, order = 1, stats = { footDrain = 1 } },
	{ id = "TrailEdge", slot = "Shoes", name = "Trail Edge", description = "Stiff all-rounders that stand on small edges.", price = 60, order = 2, stats = { footDrain = 0.92 } },
	{ id = "ProDownturn", slot = "Shoes", name = "Pro Downturn", description = "Aggressive downturned shoes for steep rock.", price = 250, order = 3, stats = { footDrain = 0.85 } },
	{ id = "VelvetSlipper", slot = "Shoes", name = "Velvet Slipper", description = "Soft, sticky slippers that feel every hold.", price = 600, order = 4, stats = { footDrain = 0.78 } },

	{ id = "BasicChalk", slot = "ChalkBag", name = "Basic Chalk Bag", description = "A small bag of loose chalk.", price = 0, order = 1, stats = { chalkRate = 1.4, chalkReduction = 0.25 } },
	{ id = "BigBucket", slot = "ChalkBag", name = "Big Bucket", description = "Holds more, so you chalk up less.", price = 80, order = 2, stats = { chalkRate = 1.0, chalkReduction = 0.28 } },
	{ id = "LiquidPro", slot = "ChalkBag", name = "Liquid Chalk Pro", description = "Liquid base coat plus a pro bag. Lasts ages.", price = 300, order = 3, stats = { chalkRate = 0.7, chalkReduction = 0.33 } },

	{ id = "RentalHarness", slot = "Harness", name = "Rental Harness", description = "Heavy, but it does the job.", price = 0, order = 1, stats = { dynoCost = 15 } },
	{ id = "Featherweight", slot = "Harness", name = "Featherweight", description = "A light harness: dynos cost less.", price = 120, order = 2, stats = { dynoCost = 12 } },
	{ id = "CompHarness", slot = "Harness", name = "Comp Harness", description = "Competition kit. Explosive and light.", price = 400, order = 3, stats = { dynoCost = 9 } },

	{ id = "DayPack", slot = "Pack", name = "Day Pack", description = "A simple everyday pack.", price = 0, order = 1, stats = {} },
	{ id = "CragPack", slot = "Pack", name = "Crag Pack", description = "A tall pack with a rope strapped under the lid.", price = 50, order = 2, stats = {} },
	{ id = "Duffel", slot = "Pack", name = "Gym Duffel", description = "A roll duffel slung across your back.", price = 90, order = 3, stats = {} },
	{ id = "HaulBag", slot = "Pack", name = "Haul Bag", description = "Big-wall haul bag. Serious business.", price = 150, order = 4, stats = {} },

	{ id = "YellowRope", slot = "Rope", name = "Classic Yellow", description = "The standard dynamic rope.", price = 0, order = 1, stats = { ropeColor = Color3.fromRGB(245, 205, 40) } },
	{ id = "OceanRope", slot = "Rope", name = "Ocean Blue", description = "A blue rope with a dry coating.", price = 30, order = 2, stats = { ropeColor = Color3.fromRGB(40, 140, 240) } },
	{ id = "NeonRope", slot = "Rope", name = "Hot Pink", description = "Easy to spot on any crag.", price = 30, order = 3, stats = { ropeColor = Color3.fromRGB(250, 80, 170) } },
	{ id = "StealthRope", slot = "Rope", name = "Stealth Black", description = "A sleek, skinny black line.", price = 60, order = 4, stats = { ropeColor = Color3.fromRGB(32, 32, 36) } },
}

-- Colours for your pack and chalk bag (free, picked at the lockers).
Gear.COLORS = table.freeze({
	Color3.fromRGB(255, 122, 48), -- Ascent orange
	Color3.fromRGB(220, 50, 60),
	Color3.fromRGB(240, 200, 50),
	Color3.fromRGB(70, 190, 90),
	Color3.fromRGB(40, 180, 190),
	Color3.fromRGB(50, 110, 220),
	Color3.fromRGB(140, 80, 210),
	Color3.fromRGB(240, 110, 180),
	Color3.fromRGB(44, 46, 52),
	Color3.fromRGB(236, 236, 232),
})

local byId: { [string]: Item } = {}
for _, item in ITEMS do
	byId[item.id] = item
end

function Gear.get(id: any): Item?
	return if type(id) == "string" then byId[id] else nil
end

-- Items in a slot, cheapest first.
function Gear.inSlot(slot: Slot): { Item }
	local list = {}
	for _, item in ITEMS do
		if item.slot == slot then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- The free item every player starts with in each slot.
function Gear.default(slot: Slot): Item
	return Gear.inSlot(slot)[1]
end

function Gear.color(index: any): Color3
	local i = if type(index) == "number" then math.clamp(math.floor(index), 1, #Gear.COLORS) else 1
	return Gear.COLORS[i]
end

-- A short line describing what an item does, for the shop.
function Gear.describeStats(item: Item): string
	local stats = item.stats
	if stats.footDrain and stats.footDrain < 1 then
		return `−{math.floor((1 - stats.footDrain) * 100 + 0.5)}% stamina drain with feet on`
	elseif stats.chalkRate then
		return `chalk lasts {math.floor(100 / stats.chalkRate + 0.5)} s · −{math.floor(stats.chalkReduction :: number * 100 + 0.5)}% drain`
	elseif stats.dynoCost then
		return `dynos cost {stats.dynoCost} stamina`
	elseif stats.ropeColor then
		return "rope colour"
	elseif item.slot == "Pack" then
		return "colour it at the lockers"
	end
	return ""
end

Gear.ITEMS = table.freeze(ITEMS)

return table.freeze(Gear)
