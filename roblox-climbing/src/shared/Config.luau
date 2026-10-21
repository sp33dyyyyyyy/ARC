--!strict
-- Config: tuning values shared by server and client.
-- Distances are in studs unless the name says otherwise. Roblox's physics convention is
-- 1 stud = 0.28 m, so every height shown to the player goes through studsToMeters().

local Config = {}

Config.GameName = "Ascent"
Config.Version = "0.7.0"

Config.METERS_PER_STUD = 0.28

function Config.studsToMeters(studs: number): number
	return studs * Config.METERS_PER_STUD
end

function Config.metersToStuds(meters: number): number
	return meters / Config.METERS_PER_STUD
end

export type LimbKind = "Hand" | "Foot"
export type LimbDef = {
	Kind: LimbKind,
	Key: Enum.KeyCode, -- selects the limb (then click a hold); dragging the limb works too
	-- Max distance from the HumanoidRootPart to a hold's grip point. About an arm/leg at
	-- full stretch, so a limb can always reach a hold the game lets you take.
	Reach: number,
}

Config.Limbs = {
	LeftHand = { Kind = "Hand", Key = Enum.KeyCode.Q, Reach = 3.7 } :: LimbDef,
	RightHand = { Kind = "Hand", Key = Enum.KeyCode.E, Reach = 3.7 } :: LimbDef,
	LeftFoot = { Kind = "Foot", Key = Enum.KeyCode.Z, Reach = 3.1 } :: LimbDef,
	RightFoot = { Kind = "Foot", Key = Enum.KeyCode.C, Reach = 3.1 } :: LimbDef,
}
Config.LimbOrder = { "LeftHand", "RightHand", "LeftFoot", "RightFoot" }

-- Climbing (Stage 2). Distances in studs.
Config.Climb = {
	-- Body placement around the attached holds (see ClimbMath.solveBody).
	BodyOffset = 1.1, -- HumanoidRootPart distance out from the wall
	MinWallGap = 0.9, -- never closer than this (torso would clip the wall)
	HangBelowHands = 2.6, -- hands only: hang this far below them
	StandAboveFeet = 2.3, -- feet only: stand this far above them (legs slightly bent)
	HandBias = 0.45, -- hands + feet: body sits this fraction of the way from feet to hands
	ShiftRange = Vector2.new(1.5, 1.5), -- WASD weight shift, right/left and up/down
	ShiftSpeed = 2.2, -- how fast holding WASD moves the (sticky) shift, full range per second
	ReachSlack = 0.95, -- body keeps every attached limb within Reach * this

	-- Body constraints (AlignPosition / AlignOrientation on the HumanoidRootPart).
	AlignResponsiveness = 14,
	AlignMaxVelocity = 18,
	AlignMaxForce = 60000,

	-- Input and feedback.
	PickRadiusPx = 42, -- how close (pixels) to a hand/foot a click must be to grab it
	ClickMovePx = 8, -- a press that moves less than this is a click (select), not a drag
	SnapRadius = 1.2, -- dropping this close to a hold snaps onto it
	MarkerRange = 16, -- show hold markers within this distance while placing a limb
	PendingTimeout = 2, -- seconds to wait for the server before undoing a prediction

	-- Server rules.
	ReachTolerance = 1.5, -- extra reach allowed for latency
	RequestsPerSecond = 20,
	RequestBurst = 30,
	WatchdogExtra = 4, -- body further than Reach + this from a held hold...
	WatchdogSeconds = 1, -- ...for this long is forced off the wall
	GroundCrouch = 0.4, -- near the floor the body may crouch this much below standing height
	-- Arms and legs go in this collision group, which doesn't collide with the world, so IK
	-- can press hands and feet onto holds without the wall shoving the body around.
	LimbCollisionGroup = "ClimberLimbs",

	-- Dyno: hold Space to charge, aim at a hold with the mouse, release to jump for it.
	-- The jump follows a real ballistic arc under Roblox gravity (ClimbMath.planDyno).
	Dyno = {
		ChargeTime = 0.9, -- seconds to full charge
		MinCharge = 0.15, -- releasing below this cancels
		MinDistance = 2, -- how far the body can travel at minimum charge...
		MaxDistance = 10, -- ...and at full charge; too little charge falls short
		CatchBelow = 1.6, -- the body aims this far below the target hold
		FlightTimeBase = 0.2, -- flight time = base + per stud * distance
		FlightTimePerStud = 0.035,
		CatchGrace = 0.35, -- extra seconds after arriving to still catch a hold
		CatchRadius = 1.4, -- a free hand this close to any hand hold grabs it
		ServerGrace = 2, -- seconds after a dyno the server allows extra reach for catches...
		ServerExtraTolerance = 4, -- ...of this many studs (its view of you lags in flight)
	},

	Keys = {
		LetGo = Enum.KeyCode.V,
		CentreWeight = Enum.KeyCode.X, -- puts the sticky weight shift back in the middle
		Lower = Enum.KeyCode.R, -- tied in: sit back on the rope and get lowered
		Dyno = Enum.KeyCode.Space,
	},

	-- Colours from the reference video: green = hands, teal = feet.
	Colors = {
		Hand = Color3.fromRGB(92, 230, 92),
		Foot = Color3.fromRGB(63, 209, 201),
		OutOfReach = Color3.fromRGB(235, 80, 80),
		Selected = Color3.fromRGB(255, 214, 64),
		Attached = Color3.fromRGB(255, 255, 255),
		Free = Color3.fromRGB(160, 168, 184),
	},
}

-- Grip stamina (StaminaMath). Climb without resting and you get tired and fall off.
Config.Stamina = {
	Max = 100,
	DrainByLimbs = { 18, 9, 4 }, -- per second with 1 / 2 / 3 limbs on (x hold type x quality)
	FeetOnlyDrain = 1.5,
	RestDelay = 0.6, -- all four limbs on, unmoved, this long before recovery starts
	RestRecover = 22, -- per second while resting (more on jugs)
	GroundRecover = 35,
	DynoCost = 15, -- every dyno costs this much
	LowWarning = 25, -- below this the hands shake and the bar turns red
	TickSeconds = 0.1, -- server update rate
}

-- Falls, ragdoll and death (RagdollService). Heights are of the feet above the landing
-- spot, in studs (1 stud = 0.28 m).
Config.Falls = {
	SafeHeight = 9, -- falls up to this are shrugged off (a normal jump is about 7)
	LethalHeight = 15, -- falls from this high are fatal (about 4.2 m)...
	CrashMatFactor = 1.2, -- ...landing on a crash mat raises that by 20%
	RagdollOnLetGoAbove = 6, -- letting go higher than this above the ground ragdolls you
	KnockdownSeconds = 2.2, -- lying on the floor after a hard (non-fatal) landing
	DynoGrace = 1.6, -- after a missed dyno, how long before you go limp
	RespawnSeconds = 4,
}

-- Routes (RouteService): timing, rewards and the leaderboards.
Config.Routes = {
	StartBand = 9, -- a run only starts if your first hold is this low (studs above the base)
	FailGroundSeconds = 1.2, -- off the wall and standing on the ground this long ends the run
	ProgressTick = 0.2,
	RetryCooldown = 2,
	-- Rewards for a summit: gems = base + per metre climbed, double the first time.
	GemsBase = 5,
	GemsPerMeter = 1.2,
	FirstClearBonus = 2,
	XPPerMeter = 6,
	LeaderboardSize = 10,
	LeaderboardRefresh = 60, -- seconds between leaderboard reloads
}

-- Ropes (RopeService): top-rope outdoors (tie in at the rope bag), auto-belay indoors.
Config.Rope = {
	Slack = 2.2, -- studs of slack the belayer keeps while you climb (you fall this far)
	TakeInSpeed = 40, -- studs/s the belayer takes in or pays out to follow you
	Stretch = 0.18, -- bounce when the rope comes tight (RopeConstraint.Restitution)
	CaughtSeconds = 0.9, -- the jolt and flail right after a catch
	HangSeconds = 1.2, -- dangle this long before being lowered
	LowerSpeed = 7, -- studs per second
	TakeSpeed = 12, -- how fast the belayer takes in when you ask to be lowered (R)
	UntieDistance = 30, -- walking this far from the route's base unties you
	Color = Color3.fromRGB(245, 205, 40),
	AutoBelayColor = Color3.fromRGB(40, 150, 240),
}

-- Chalk (ChalkService): chalk up at a bucket for drier hands and less stamina drain.
Config.Chalk = {
	Max = 100,
	DrainPerSecond = 1.4, -- while on the wall
	DrainReduction = 0.25, -- full chalk drains stamina this much slower
}

Config.Debug = {
	-- Hover a hold with the mouse to see its type/quality. Toggle in game with H.
	HoldInspectorKey = Enum.KeyCode.H,
	HoldInspectorStartsOn = false,
	-- Run the Diagnostics checks when you press Play in Studio (never on live servers).
	RunSelfChecksInStudio = true,
}

-- Where the Stage 1 practice wall stands. Its size and holds are in
-- ServerScriptService.Server.World.TestWallLayout. Built at runtime if
-- Workspace.Routes.TestWall is missing, or in edit mode from the command bar (see README).
Config.TestWall = {
	FolderName = "TestWall",
	RouteName = "Tutorial Wall",
	Grade = "VB",
	-- Bottom-centre of the wall's climbing face, on the floor.
	Origin = Vector3.new(0, 0, -24),
	-- Direction the climbing face points (towards the spawn).
	Facing = Vector3.new(0, 0, 1),
	-- 0 = vertical, positive = overhang (top leans towards the climber), negative = slab.
	AngleDegrees = 0,
}

return table.freeze(Config)
