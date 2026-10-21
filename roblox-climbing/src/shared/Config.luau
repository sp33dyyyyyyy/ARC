--!strict
-- Config: tuning values shared by server and client.
-- Distances are in studs unless the name says otherwise. Roblox's physics convention is
-- 1 stud = 0.28 m, so every height shown to the player goes through studsToMeters().

local Config = {}

Config.GameName = "[YOUR GAME NAME]"
Config.Version = "0.1.0-stage1"

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
	Key: Enum.KeyCode,
	-- Max distance from the HumanoidRootPart to a hold's grip point (used from Stage 2).
	Reach: number,
}

-- Limb keys from the design doc: Q/E hands, Z/C feet.
Config.Limbs = {
	LeftHand = { Kind = "Hand", Key = Enum.KeyCode.Q, Reach = 4.2 } :: LimbDef,
	RightHand = { Kind = "Hand", Key = Enum.KeyCode.E, Reach = 4.2 } :: LimbDef,
	LeftFoot = { Kind = "Foot", Key = Enum.KeyCode.Z, Reach = 3.8 } :: LimbDef,
	RightFoot = { Kind = "Foot", Key = Enum.KeyCode.C, Reach = 3.8 } :: LimbDef,
}
Config.LimbOrder = { "LeftHand", "RightHand", "LeftFoot", "RightFoot" }

Config.Debug = {
	-- Hover a hold with the mouse to see its type/quality. Toggle in game with H.
	HoldInspectorKey = Enum.KeyCode.H,
	HoldInspectorStartsOn = true,
	-- Run Diagnostics/Stage1Check when you press Play in Studio (never on live servers).
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
