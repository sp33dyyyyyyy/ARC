--!strict
-- Gear: everything you can buy at the pro shop, and what it does. Shared so the server
-- (ShopService, StaminaService, RopeService) and the shop UI agree.
--
-- Slots: one item equipped per slot. The free item in each slot is owned from the start.
--   Shoes     less stamina drain while a foot is on a hold
--   ChalkBag  chalk lasts longer and helps more
--   Harness   dynos cost less stamina
--   Helmet    falls from higher up are survivable
--   Pack      the bag on your back: bigger bags carry more (Shared/Pack); colour at the lockers
--   Rope      your rope's colour outdoors (looks only)
--
-- Packs, helmets and chalk bags are real avatar accessories from the Roblox catalog (any
-- game may load accessories), worn by players and the gym's NPCs; each pack and helmet
-- comes in several colours ("variants"). If one can't be loaded, a built-in stand-in
-- (GearModels) is worn instead.

export type Slot = "Shoes" | "ChalkBag" | "Harness" | "Helmet" | "Pack" | "Rope"

export type Variant = { name: string, asset: number, color: Color3 }

export type Stats = {
	footDrain: number?, -- multiplies stamina drain while at least one foot is on
	chalkRate: number?, -- chalk used per second on the wall
	chalkReduction: number?, -- how much slower stamina drains with full chalk
	dynoCost: number?, -- stamina per dyno
	ropeColor: Color3?,
	fallBonus: number?, -- multiplies the height of a fatal fall
}

export type Item = {
	id: string,
	slot: Slot,
	name: string,
	description: string,
	price: number, -- pounds; 0 = owned from the start
	order: number,
	stats: Stats,
	variants: { Variant }?, -- looks to pick from at the lockers (packs, helmets)
}

local Pack = require(script.Parent:WaitForChild("Pack"))

local Gear = {}

local SLOTS: { Slot } = { "Shoes", "ChalkBag", "Harness", "Helmet", "Pack", "Rope" }
Gear.SLOTS = table.freeze(SLOTS)
Gear.SLOT_NAMES = table.freeze({ Shoes = "Shoes", ChalkBag = "Chalk", Harness = "Harness", Helmet = "Helmets", Pack = "Bags", Rope = "Ropes" })

local function v(name: string, asset: number, r: number, g: number, b: number): Variant
	return { name = name, asset = asset, color = Color3.fromRGB(r, g, b) }
end

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

	{ id = "NoHelmet", slot = "Helmet", name = "No Helmet", description = "Living dangerously.", price = 0, order = 1, stats = { fallBonus = 1 } },
	{ id = "LecrinRoc", slot = "Helmet", name = "Roc Helmet", description = "A tough, simple climbing helmet.", price = 80, order = 2, stats = { fallBonus = 1.1 }, variants = { v("White", 92040460524357, 236, 236, 232), v("Yellow", 117772364185840, 240, 200, 50), v("Red", 113915587208256, 210, 60, 50) } },
	{ id = "Aurora", slot = "Helmet", name = "Aurora Helmet", description = "Light, vented and comfy all day.", price = 150, order = 3, stats = { fallBonus = 1.15 }, variants = { v("Black", 133255040917706, 40, 40, 44), v("Red", 72372066631368, 200, 40, 40), v("White", 131199201138008, 236, 236, 232) } },
	{ id = "BlackMountain", slot = "Helmet", name = "Vapor Helmet", description = "Pro-level protection, barely there.", price = 220, order = 4, stats = { fallBonus = 1.2 }, variants = { v("Black", 91166163405976, 40, 40, 44), v("White", 86458819326502, 236, 236, 232), v("Red", 110614599925052, 180, 50, 50) } },

	{ id = "DayPack", slot = "Pack", name = "Climbing Pack", description = "A lightweight pack with an axe loop.", price = 0, order = 1, stats = {}, variants = { v("Black", 80637156175895, 40, 40, 44), v("Blue", 122440357794609, 60, 90, 140), v("White", 84639929385903, 220, 220, 216), v("Green", 107151537044410, 70, 90, 60) } },
	{ id = "CragPack", slot = "Pack", name = "Crag Pack", description = "A bright alpine pack with lace-up lid.", price = 50, order = 2, stats = {}, variants = { v("Orange", 128795521464166, 240, 120, 40), v("White", 78858430300558, 230, 230, 226), v("Red", 115859440802120, 210, 50, 50), v("Green", 106838146148140, 40, 140, 60) } },
	{ id = "Expedition", slot = "Pack", name = "Expedition Pack", description = "Big, strappy, ready for days on the wall.", price = 90, order = 3, stats = {}, variants = { v("Grey", 17817042724, 110, 110, 110), v("Brown", 17817037993, 130, 90, 60), v("Slate", 17817049389, 80, 90, 100), v("Green", 17817045771, 80, 100, 70), v("Red", 17817033951, 150, 60, 50) } },
	{ id = "HaulBag", slot = "Pack", name = "Big Wall Pack", description = "Built to haul a big rack up the Colossus.", price = 150, order = 4, stats = {}, variants = { v("Black", 88149022073624, 40, 40, 44), v("White", 125700856406959, 220, 220, 216), v("Green", 122154442304706, 80, 100, 60) } },
	{ id = "BravoPack", slot = "Pack", name = "Bravo DL 30", description = "Rope and axes strapped to the outside.", price = 220, order = 5, stats = {}, variants = { v("Rope", 119212407294452, 40, 40, 44), v("Clean", 81739000932940, 30, 30, 34) } },

	{ id = "YellowRope", slot = "Rope", name = "Classic Yellow", description = "The standard dynamic rope.", price = 0, order = 1, stats = { ropeColor = Color3.fromRGB(245, 205, 40) } },
	{ id = "OceanRope", slot = "Rope", name = "Ocean Blue", description = "A blue rope with a dry coating.", price = 30, order = 2, stats = { ropeColor = Color3.fromRGB(40, 140, 240) } },
	{ id = "NeonRope", slot = "Rope", name = "Hot Pink", description = "Easy to spot on any crag.", price = 30, order = 3, stats = { ropeColor = Color3.fromRGB(250, 80, 170) } },
	{ id = "StealthRope", slot = "Rope", name = "Stealth Black", description = "A sleek, skinny black line.", price = 60, order = 4, stats = { ropeColor = Color3.fromRGB(32, 32, 36) } },
}

-- Chalk bag looks (free, picked at the lockers): catalog waist accessories.
Gear.CHALK_BAGS = table.freeze({
	v("Orange", 12765457067, 230, 120, 50),
	v("Blue", 12765420893, 70, 110, 160),
	v("Green", 12765447418, 60, 140, 70),
	v("Purple", 12765465213, 110, 80, 150),
	v("Pink", 12765459982, 200, 110, 140),
	v("White knit", 12765476571, 220, 220, 216),
	v("Plaid", 12765462493, 50, 70, 60),
	v("Leopard", 12765451822, 170, 130, 90),
	v("Red squares", 12765470708, 190, 70, 50),
	v("Striped", 12765473510, 40, 50, 50),
	v("80s knit", 12765417405, 180, 80, 60),
}) :: { Variant }

-- Colours for stand-ins (GearModels) when a catalog accessory can't be loaded.
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

-- The look `index` of an item with variants (clamped, 1 = first).
function Gear.variant(item: Item, index: any): Variant?
	local variants = item.variants
	if variants == nil or #variants == 0 then
		return nil
	end
	local i = if type(index) == "number" then math.clamp(math.floor(index), 1, #variants) else 1
	return variants[i]
end

function Gear.chalkBag(index: any): Variant
	local i = if type(index) == "number" then math.clamp(math.floor(index), 1, #Gear.CHALK_BAGS) else 1
	return Gear.CHALK_BAGS[i]
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
	elseif stats.fallBonus and stats.fallBonus > 1 then
		return `survive falls {math.floor((stats.fallBonus - 1) * 100 + 0.5)}% higher · {#(item.variants or {})} colours`
	elseif item.slot == "Pack" then
		return `carries {Pack.capacity(item.id)} · {#(item.variants or {})} colours`
	end
	return ""
end

Gear.ITEMS = table.freeze(ITEMS)

return table.freeze(Gear)
