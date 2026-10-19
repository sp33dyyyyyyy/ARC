--[[
	GameConfig  (ModuleScript, ReplicatedStorage/Shared)
	Every tuning number that is not bike-specific lives here.
]]

local GameConfig = {}

GameConfig.StudsPerKmh = 0.99 -- 1 stud ~ 0.28 m
GameConfig.MassScale = 0.1 -- Roblox mass units per kg (arbitrary, only ratios matter)

GameConfig.Economy = {
	StartingMoney = 500,
	FuelPricePerLitre = 6, -- euro
	-- repairs: VehicleData.repairCostPerPoint(vehicle) * missing health
}

GameConfig.Fuel = {
	LitresToKg = 0.74, -- petrol weighs something; matters when pushing
	CarbBowlSeconds = 4, -- engine keeps running this long after the tap is shut
	ChokeRichBurnMultiplier = 1.8, -- choke left on while running wastes fuel
	ChokePowerMultiplier = 0.65, -- ...and costs power
}

GameConfig.Engine = {
	WarmUpSeconds = 60, -- 0 -> 1 warmth while running
	CoolDownSeconds = 180, -- 1 -> 0 warmth while off
	ColdThreshold = 0.30, -- below this the engine counts as cold
	KickCooldown = 0.65, -- seconds between kicks
	FloodLimit = 3, -- this much flooding blocks all starts
	FloodDecaySeconds = 8, -- seconds per flood point to dry out
	StarterBatteryDrain = 0.14, -- per electric start attempt
	StarterBatteryRecharge = 0.010, -- per second while running
	ChokeOffAdvice = 10, -- seconds running on choke before the HUD nags
}

-- Crash detection runs on the server by watching speed loss between ticks.
GameConfig.Crash = {
	MinSpeedLoss = 26, -- studs/s lost in one tick before it counts as a crash
	DamagePerStud = 0.9,
	BaseDamage = 4,
	MaxDamage = 60,
	EjectDamage = 24, -- rider is thrown off above this
	StallDamage = 12, -- engine stalls above this
	TipOverSeconds = 1.2, -- upside-down this long = fall off
	TipOverDamage = 6,
	SpeedSanityMultiplier = 1.7, -- server clamps speed above top*this
}

-- Pushing a bike by hand ("Anschieben").
GameConfig.Push = {
	GripDistance = 2.4, -- studs in front of the player's root where the hands are
	FreeWalkSpeed = 16, -- normal Roblox walk speed
	MinFraction = 0.25, -- never slower than this fraction of walk speed
	MaxFraction = 0.90, -- lightest bike barely slows you
	Force = 1300, -- how hard a player can shove (accel = Force / effectiveKg)
	AutoReleaseDistance = 9, -- let go if the player strays this far from the bars
	LeashSlack = 3.0, -- studs the arm can stretch before you get dragged
	CoastParkSeconds = 6, -- coast-to-park timeout after letting go
	ParkSpeed = 1.0,
}

-- Constants for the raycast-wheel bike solver (see BikePhysics).
GameConfig.Physics = {
	SuspensionTravel = 0.7,
	SpringK = 400,
	SpringD = 28,
	MaxSuspensionAccel = 590, -- 3 g
	GyrationSq = 3.0, -- rotational inertia ~ mass * this (studs^2); lower = twitchier pitch
	GripRate = 10, -- how fast sideways slip is removed (1/s)
	RollingDecel = 1.2, -- studs/s^2 when coasting
	EngineBrake = 4.0,
	TiltGain = 14,
	MaxTiltRate = 8,
	WheelieUpRate = 1.4, -- rad/s
	WheelieDownRate = 2.6,
}

GameConfig.Missions = {
	PickupRadius = 14,
	CheckpointRadius = 16,
	DestinationRadius = 16,
	PollInterval = 0.2,
}

GameConfig.Data = {
	StoreName = "MopedDays_v1",
	MaxAttempts = 5,
	AutosaveSeconds = 90,
}

-- Builds the bundled village at start. Set false (or add your own Workspace/Town
-- folder) to use your own map.
GameConfig.GenerateTown = true

return GameConfig
