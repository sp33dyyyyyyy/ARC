--!strict
-- Config: tuning values shared by server and client.
-- Distances are in studs unless the name says otherwise. Roblox's physics convention is
-- 1 stud = 0.28 m, so every height shown to the player goes through studsToMeters().

local Config = {}

Config.GameName = "[YOUR GAME NAME]"
Config.Version = "0.3.0-stage2"

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
	RouteName = "Test Wall",
	Grade = "VB",
	-- Bottom-centre of the wall's climbing face, on the floor.
	Origin = Vector3.new(0, 0, -24),
	-- Direction the climbing face points (towards the spawn).
	Facing = Vector3.new(0, 0, 1),
	-- 0 = vertical, positive = overhang (top leans towards the climber), negative = slab.
	AngleDegrees = 0,
}

return table.freeze(Config)
