--!strict
-- Pack: what you can carry in your bag, how heavy it is, and how big each bag is.
-- You pack at the gym lockers ("Pack bag"); PackService saves the loadout. Out at the
-- crags you use it from the hotbar (keys 1-5):
--   Rope        drop the rope bag at a route's base, then click it to tie in
--   Crash pad   drop it under a boulder or a start: landings on it are softer
--   Quickdraws  lead routes (the Colossus): clip one into the rock beside your top hand
--   Chalk bag   a spare chalk bag to stand on the ground; anyone can chalk up at it
--   Water       drink for stamina (refilled when you pack at the lockers)
-- A heavier pack makes you tire a little faster on the wall.

local Pack = {}

export type Kind = "place" | "clip" | "drink"

export type Item = {
	id: string,
	name: string,
	short: string, -- hotbar label
	weight: number, -- per one
	max: number,
	kind: Kind,
	description: string,
}

Pack.ITEMS = table.freeze({
	{ id = "Rope", name = "Rope", short = "ROPE", weight = 4, max = 1, kind = "place", description = "A 60 m dynamic rope in its bag. Drop it at a route's base and click it to tie in." },
	{ id = "CrashPad", name = "Crash pad", short = "PAD", weight = 4, max = 2, kind = "place", description = "Drop it under a boulder or a start. Landings on it are softer." },
	{ id = "Quickdraws", name = "Quickdraws", short = "DRAWS", weight = 0.5, max = 12, kind = "clip", description = "For lead routes (the Colossus): clip one into the rock as you climb." },
	{ id = "Chalk", name = "Chalk bag", short = "CHALK", weight = 1, max = 1, kind = "place", description = "A spare chalk bag to stand at the base. Anyone can chalk up at it." },
	{ id = "Water", name = "Water bottle", short = "WATER", weight = 1, max = 3, kind = "drink", description = "Drink for +35 stamina (not mid-climb). Refilled when you pack." },
} :: { Item })

local byId: { [string]: Item } = {}
for _, item in Pack.ITEMS do
	byId[item.id] = item
end

function Pack.item(id: string): Item?
	return byId[id]
end

-- How much each bag (Gear "Pack" item) carries.
Pack.CAPACITY = table.freeze({
	DayPack = 8,
	CragPack = 11,
	Expedition = 14,
	BravoPack = 16,
	HaulBag = 20,
} :: { [string]: number })
Pack.DEFAULT_CAPACITY = 8

Pack.DEFAULT = table.freeze({ Rope = 1, Water = 1 } :: { [string]: number })

Pack.WATER_STAMINA = 35
Pack.DRAIN_PER_WEIGHT = 0.012 -- stamina drains this much faster per unit carried
Pack.PLACE_REACH = 14 -- how far from you things can be put down
Pack.ROUTE_REACH = 25 -- a rope bag ties in to the route whose base is this close

function Pack.capacity(packItemId: string?): number
	return if packItemId then Pack.CAPACITY[packItemId] or Pack.DEFAULT_CAPACITY else Pack.DEFAULT_CAPACITY
end

function Pack.weight(counts: { [string]: number }): number
	local total = 0
	for id, count in counts do
		local item = byId[id]
		if item then
			total += item.weight * count
		end
	end
	return total
end

-- A loadout cleaned up: known items only, whole numbers within each item's limit.
function Pack.sanitize(counts: any): { [string]: number }
	local clean: { [string]: number } = {}
	if type(counts) ~= "table" then
		return clean
	end
	for _, item in Pack.ITEMS do
		local n = counts[item.id]
		if type(n) == "number" and n == n then
			local whole = math.clamp(math.floor(n), 0, item.max)
			if whole > 0 then
				clean[item.id] = whole
			end
		end
	end
	return clean
end

return table.freeze(Pack)
