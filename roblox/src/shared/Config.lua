--!strict
-- Every tunable number in the game lives here. Pure data: no Roblox APIs, so the
-- unit tests can load it outside Studio.

local Config = {}

Config.Stamina = {
	Base = 100,
	DrainPerSecond = 8, -- while actively climbing, before the tower multiplier
	HangDrainFraction = 0.25, -- gripping a wall without moving drains at 25% of climbing
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
	-- Grip & Lunge climbing
	ClimbSpeed = 10, -- studs/second crawling up a wall
	SideSpeed = 7, -- studs/second sideways
	GripRange = 3.5, -- how close a wall must be to grab it
	WallOffset = 1.6, -- distance kept between the body and the wall
	LungeDistance = 8, -- a lunge throws you this far up the wall
	LungeSpeed = 40,
	LungeCooldown = 0.7,
	LungeCostFactor = 1.3, -- lunging costs 30% more than crawling the same distance
	CatchMaxFallSpeed = 70, -- you can only catch the wall if falling slower than this
	MantleReach = 7, -- ledges up to this far above your waist can be climbed onto
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

-- Tower archetypes. Telecom towers are tapered lattice towers with a rest
-- platform on top of every section; skyscrapers are glass boxes with a
-- maintenance balcony every `BalconyEvery` studs. Platforms and balconies are
-- the only places to catch your breath.
Config.TowerTypes = {
	Tutorial = {
		Kind = "Telecom",
		DisplayName = "Tutorial Tower",
		SectionHeight = 20,
		Sections = 4, -- 80 studs
		BaseHalfWidth = 9,
		TopHalfWidth = 3,
		DrainMultiplier = 1,
		Slippery = false,
		Payout = 50,
		Color = { 200, 45, 40 },
	},
	TelecomMedium = {
		Kind = "Telecom",
		DisplayName = "Telecom Tower",
		SectionHeight = 50,
		Sections = 14, -- 700 studs
		BaseHalfWidth = 28,
		TopHalfWidth = 5,
		DrainMultiplier = 1.3,
		Slippery = false,
		Payout = 600,
		Color = { 205, 40, 35 },
	},
	TelecomTall = {
		Kind = "Telecom",
		DisplayName = "Telecom Tower",
		SectionHeight = 70,
		Sections = 15, -- 1050 studs
		BaseHalfWidth = 36,
		TopHalfWidth = 6,
		DrainMultiplier = 1.8,
		Slippery = false,
		Payout = 2000,
		Color = { 210, 35, 30 },
	},
	SkySmall = {
		Kind = "Skyscraper",
		DisplayName = "Skyscraper",
		Height = 1400,
		HalfWidth = 32,
		BalconyEvery = 100,
		DrainMultiplier = 1.6,
		Slippery = true,
		Payout = 1500,
		Color = { 175, 195, 215 },
		Frame = { 225, 225, 220 },
	},
	SkyMedium = {
		Kind = "Skyscraper",
		DisplayName = "Skyscraper",
		Height = 2100,
		HalfWidth = 38,
		BalconyEvery = 150,
		DrainMultiplier = 2.2,
		Slippery = true,
		Payout = 4000,
		Color = { 60, 95, 150 },
		Frame = { 200, 200, 205 },
	},
	SkyLarge = {
		Kind = "Skyscraper",
		DisplayName = "Skyscraper",
		Height = 2800,
		HalfWidth = 46,
		BalconyEvery = 200,
		DrainMultiplier = 3,
		Slippery = true,
		Payout = 10000,
		Helipad = true,
		Color = { 35, 45, 75 },
		Frame = { 70, 75, 90 },
	},
}

-- Map (top-down, north = -Z): plaza at the north end, a path runs south to the
-- Power Up Shop, skyscrapers down the west side, telecom towers down the east.
Config.Layout = {
	{ Type = "SkySmall", Name = "Skyscraper 1", Size = "SMALL", Difficulty = "EASY", X = -190, Z = -300 },
	{ Type = "SkyMedium", Name = "Skyscraper 2", Size = "MEDIUM", Difficulty = "NORMAL", X = -190, Z = -20 },
	{ Type = "SkyLarge", Name = "Skyscraper 3", Size = "LARGE", Difficulty = "HARD", X = -190, Z = 260 },
	{ Type = "Tutorial", Name = "Tutorial Tower", Size = "SMALL", Difficulty = "EASY", X = 190, Z = -300 },
	{ Type = "TelecomMedium", Name = "Telecom Tower 1", Size = "MEDIUM", Difficulty = "NORMAL", X = 190, Z = -20 },
	{ Type = "TelecomTall", Name = "Telecom Tower 2", Size = "TALL", Difficulty = "HARD", X = 190, Z = 260 },
}

Config.Map = {
	IslandHalfX = 330,
	IslandHalfZ = 680,
	LotHalf = 75,
	PathHalfWidth = 14,
	PlazaCenter = { 0, -540 },
	ShopCenter = { 0, 560 },
	WaterLevel = -90,
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
	Grab = "rbxasset://sounds/action_get_up.mp3",
}

Config.DataStoreName = "SkyClimbers_v1"
Config.LeaderboardStoreName = "SkyClimbers_Climbs_v1"
Config.AutosaveInterval = 120
Config.LeaderboardRefresh = 60

return Config
