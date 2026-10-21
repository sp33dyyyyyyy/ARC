--!strict
-- HoldTypes: gameplay data for every hold type. Pure data with no Roblox APIs, so it can be
-- unit tested outside Studio (tests/unit.luau).
--
-- DrainMultiplier: hand stamina drain relative to an average hold (1.0). Used from Stage 3.
-- SlipFactor:      multiplier on the per-limb slip chance. Used from Stage 7b.
-- DefaultQuality:  grip given (0..1) when a hold has no Quality attribute.

export type HoldTypeDef = {
	Name: string,
	Description: string,
	HandOK: boolean,
	FootOK: boolean,
	DefaultQuality: number,
	DrainMultiplier: number,
	SlipFactor: number,
}

local DEFS: { HoldTypeDef } = {
	{
		Name = "Jug",
		Description = "Big positive bucket. Easy to hold, good for resting.",
		HandOK = true,
		FootOK = true,
		DefaultQuality = 0.9,
		DrainMultiplier = 0.45,
		SlipFactor = 0.3,
	},
	{
		Name = "Edge",
		Description = "Flat positive ledge, about a finger pad deep.",
		HandOK = true,
		FootOK = true,
		DefaultQuality = 0.65,
		DrainMultiplier = 0.85,
		SlipFactor = 0.8,
	},
	{
		Name = "Crimp",
		Description = "Thin edge for the fingertips. Pumpy.",
		HandOK = true,
		FootOK = true,
		DefaultQuality = 0.4,
		DrainMultiplier = 1.35,
		SlipFactor = 1.3,
	},
	{
		Name = "Sloper",
		Description = "Rounded hold that relies on friction. Slips easily.",
		HandOK = true,
		FootOK = true,
		DefaultQuality = 0.35,
		DrainMultiplier = 1.5,
		SlipFactor = 1.6,
	},
	{
		Name = "Pinch",
		Description = "Squeezed between thumb and fingers.",
		HandOK = true,
		FootOK = false,
		DefaultQuality = 0.5,
		DrainMultiplier = 1.15,
		SlipFactor = 1.0,
	},
	{
		Name = "Pocket",
		Description = "Hole for one to three fingers.",
		HandOK = true,
		FootOK = true,
		DefaultQuality = 0.5,
		DrainMultiplier = 1.2,
		SlipFactor = 0.9,
	},
	{
		Name = "Foothold",
		Description = "Small chip or screw-on for feet only.",
		HandOK = false,
		FootOK = true,
		DefaultQuality = 0.6,
		DrainMultiplier = 1.0,
		SlipFactor = 0.7,
	},
	{
		Name = "Crack",
		Description = "Jam hands or feet into the crack.",
		HandOK = true,
		FootOK = true,
		DefaultQuality = 0.6,
		DrainMultiplier = 0.9,
		SlipFactor = 0.8,
	},
}

local HoldTypes = {}

HoldTypes.DEFAULT_TYPE = "Edge"

-- Ordered list of type names (stable order for UI and tests).
HoldTypes.Names = {} :: { string }

local byName: { [string]: HoldTypeDef } = {}
for _, def in DEFS do
	table.freeze(def)
	byName[def.Name] = def
	table.insert(HoldTypes.Names, def.Name)
end
table.freeze(HoldTypes.Names)

function HoldTypes.get(name: string?): HoldTypeDef?
	if name == nil then
		return nil
	end
	return byName[name]
end

function HoldTypes.isValid(name: any): boolean
	return type(name) == "string" and byName[name] ~= nil
end

return table.freeze(HoldTypes)
