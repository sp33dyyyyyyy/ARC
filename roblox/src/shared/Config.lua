--!strict
-- Every tunable number in the game lives here. Pure data: no Roblox APIs, so the
-- unit tests can load it outside Studio.

local Config = {}

Config.Stamina = {
	Base = 100,
	DrainPerSecond = 8, -- while actively climbing, before the tower multiplier
	HangDrainFraction = 0.25, -- hanging still on a ladder drains at 25% of climbing
	RecoverPerSecond = 22, -- standing on solid ground
	DangerFraction = 0.2, -- HUD pulses red below this
	WakeFraction = 0.4, -- stamina you wake up with after a blackout
}

Config.Fall = {
	SafeDrop = 40, -- studs you can fall without damage
	DamagePerStud = 0.9,
	AutoRagdollAfter = 0.6, -- seconds of freefall before you go limp
	MinRagdollTime = 1.2,
	MinBlackoutTime = 2.5,
	MaxRagdollTime = 8,
	SettleSpeed = 2.5, -- body counts as landed below this speed
	SettleTime = 0.6,
}

Config.Climb = {
	BaseWalkSpeed = 16,
	-- Anti-cheat: nobody legitimately climbs faster than this (studs/second),
	-- so a peak touched sooner than height / this after the base is rejected.
	MaxPlausibleSpeed = 40,
	CheckpointRespawnLift = 3,
}

Config.Chalk = {
	Price = 75,
	MaxHeld = 10,
	Duration = 12,
	DrainMultiplier = 0.5,
}

Config.Wind = {
	MinInterval = 25,
	MaxInterval = 45,
	WarningTime = 3,
	Duration = 4,
	MinHeight = 60, -- gusts only matter above this height
	DrainMultiplier = 1.6,
	KnockOffFraction = 0.25, -- climbers below this stamina get blown off
	AirPush = 45,
}

Config.DayLengthSeconds = 600

Config.Daily = {
	BaseReward = 100,
	MaxStreakMultiplier = 7,
}

-- Boost definitions. Order here is the order shown in the shop.
Config.Boosts = {
	{
		Id = "Endurance",
		Name = "Endurance",
		Description = "+25 max stamina per level.",
		BaseCost = 100,
		Growth = 1.6,
		MaxLevel = 10,
		PerLevel = 25,
	},
	{
		Id = "Recovery",
		Name = "Deep Breaths",
		Description = "+25% stamina recovery per level.",
		BaseCost = 150,
		Growth = 1.7,
		MaxLevel = 5,
		PerLevel = 0.25,
	},
	{
		Id = "ClimbSpeed",
		Name = "Quick Hands",
		Description = "+10% climbing speed per level.",
		BaseCost = 250,
		Growth = 1.8,
		MaxLevel = 5,
		PerLevel = 0.1,
	},
	{
		Id = "Grip",
		Name = "Sticky Gloves",
		Description = "-8% drain on slippery glass per level.",
		BaseCost = 400,
		Growth = 1.8,
		MaxLevel = 5,
		PerLevel = 0.08,
	},
	{
		Id = "SoftLanding",
		Name = "Rubber Bones",
		Description = "-15% fall damage per level.",
		BaseCost = 200,
		Growth = 1.7,
		MaxLevel = 5,
		PerLevel = 0.15,
	},
}

-- Tower archetypes. Section heights must be even (TrussPart lengths snap to 2).
Config.TowerTypes = {
	Mast = {
		Kind = "Telecom",
		DisplayName = "Small Mast",
		SectionHeight = 20,
		Sections = 4,
		BaseHalfWidth = 9,
		TopHalfWidth = 2,
		DrainMultiplier = 1,
		Slippery = false,
		Payout = 50,
		Color = { 200, 60, 50 },
	},
	Lattice = {
		Kind = "Telecom",
		DisplayName = "Lattice Tower",
		SectionHeight = 40,
		Sections = 5,
		BaseHalfWidth = 16,
		TopHalfWidth = 4,
		DrainMultiplier = 1.5,
		Slippery = false,
		Payout = 200,
		Color = { 225, 225, 225 },
	},
	Skyscraper = {
		Kind = "Skyscraper",
		DisplayName = "Skyscraper",
		SectionHeight = 100,
		HalfWidths = { 40, 33, 26, 19 },
		DrainMultiplier = 2.5,
		Slippery = true,
		Payout = 1000,
		Color = { 90, 140, 170 },
	},
	Supertall = {
		Kind = "Skyscraper",
		DisplayName = "Supertall",
		SectionHeight = 100,
		HalfWidths = { 52, 46, 40, 34, 28, 22, 17, 12 },
		DrainMultiplier = 4,
		Slippery = true,
		Payout = 5000,
		Spire = 120,
		Color = { 150, 175, 195 },
	},
}

-- Where each tower stands: type, distance from the plaza, angle in degrees.
Config.Layout = {
	{ Type = "Mast", Name = "Old Relay", Radius = 150, Angle = 20 },
	{ Type = "Mast", Name = "Hilltop Mast", Radius = 150, Angle = 200 },
	{ Type = "Lattice", Name = "Signal Spire", Radius = 230, Angle = 95 },
	{ Type = "Lattice", Name = "Radio Ridge", Radius = 230, Angle = 275 },
	{ Type = "Skyscraper", Name = "Glasshouse", Radius = 330, Angle = 140 },
	{ Type = "Skyscraper", Name = "Meridian Tower", Radius = 330, Angle = 320 },
	{ Type = "Supertall", Name = "The Needle", Radius = 470, Angle = 230 },
}

-- Cosmetic trails, unlocked by total climbs. Highest unlocked one is worn.
Config.Trails = {
	{ Climbs = 5, Name = "Bronze", Color = { 205, 127, 50 } },
	{ Climbs = 15, Name = "Silver", Color = { 200, 210, 225 } },
	{ Climbs = 40, Name = "Gold", Color = { 255, 205, 60 } },
	{ Climbs = 100, Name = "Neon", Color = { 80, 255, 220 } },
}

-- Built-in Roblox content sounds, so the place needs no uploaded assets.
Config.Sounds = {
	Summit = "rbxasset://sounds/electronicpingshort.wav",
	Fall = "rbxasset://sounds/action_falling.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Bonk = "rbxasset://sounds/uuhhh.mp3",
	Click = "rbxasset://sounds/action_jump.mp3",
}

Config.DataStoreName = "SkyClimbers_v1"
Config.LeaderboardStoreName = "SkyClimbers_Climbs_v1"
Config.AutosaveInterval = 120
Config.LeaderboardRefresh = 60

return Config
