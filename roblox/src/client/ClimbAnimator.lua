-- Procedural climbing animation, no uploaded animation assets.
--
-- Every client animates every climbing character by writing Motor6D.Transform
-- each frame (after the Animator, before physics). Poses:
--   climb: hand-over-hand. Arms reach up in turn, the opposite leg steps up,
--          the body leans into the wall and the head looks up.
--   rest:  both hands hooked on the rest bar, legs dangling with a slow sway.
--   leap:  arms flung overhead, legs straight.
-- Your own pose comes straight from the climbing controller (with its exact
-- hand-over-hand phase). Other players' poses come from their character's
-- "ClimbPose" attribute (set by the server), with the phase driven by how fast
-- they're moving.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local ClimbAnimator = {}

local player = Players.LocalPlayer
local localPose, localPhase = "", 0
local phases: { [Model]: number } = {}
local posed: { [Model]: { Motor6D } } = {}

local R15 = {
	LeftShoulder = "LeftUpperArm",
	RightShoulder = "RightUpperArm",
	LeftElbow = "LeftLowerArm",
	RightElbow = "RightLowerArm",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
	Neck = "Head",
	Waist = "UpperTorso",
}
local R6 = {
	LeftShoulder = "Left Shoulder",
	RightShoulder = "Right Shoulder",
	LeftHip = "Left Hip",
	RightHip = "Right Hip",
}

local function rad(d: number): number
	return math.rad(d)
end

-- Joint angles (degrees, "forward/up" positive) for a pose at a phase.
type Angles = { arm: { number }, elbow: { number }, hip: { number }, knee: { number }, neck: number, lean: number }

local function anglesFor(pose: string, phase: number, t: number): Angles
	if pose == "leap" then
		return { arm = { 172, 172 }, elbow = { 0, 0 }, hip = { -8, -8 }, knee = { 0, 0 }, neck = 25, lean = 4 }
	elseif pose == "rest" then
		local sway = math.sin(t * 1.7) * 6
		return { arm = { 155, 155 }, elbow = { 12, 12 }, hip = { 4 + sway, 4 - sway }, knee = { 10, 10 }, neck = -4, lean = 0 }
	end
	-- climb: left arm reaches while the right leg steps, then swap.
	local s = math.sin(phase)
	local reachL, reachR = math.max(0, s), math.max(0, -s)
	return {
		arm = { 135 + 35 * s, 135 - 35 * s },
		elbow = { 45 - 35 * reachL, 45 - 35 * reachR },
		hip = { 20 + 45 * reachR, 20 + 45 * reachL },
		knee = { 25 + 55 * reachR, 25 + 55 * reachL },
		neck = 18,
		lean = -8,
	}
end

local function motor(character: Model, map: { [string]: string }, joint: string, r15: boolean): Motor6D?
	local name = map[joint]
	if not name then
		return nil
	end
	local m
	if r15 then
		local part = character:FindFirstChild(name)
		m = part and part:FindFirstChild(joint)
	else
		local torso = character:FindFirstChild("Torso")
		m = torso and torso:FindFirstChild(name)
	end
	return if m and m:IsA("Motor6D") then m else nil
end

local function apply(character: Model, pose: string, phase: number, t: number): { Motor6D }
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return {}
	end
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local map = if r15 then R15 else R6
	local a = anglesFor(pose, phase, t)
	local touched = {}
	local function set(joint: string, cf: CFrame)
		local m = motor(character, map, joint, r15)
		if m then
			m.Transform = cf
			table.insert(touched, m)
		end
	end
	if r15 then
		-- R15 joints share the torso's axes: +X rotation swings a limb forward/up.
		set("LeftShoulder", CFrame.Angles(rad(a.arm[1]), 0, 0))
		set("RightShoulder", CFrame.Angles(rad(a.arm[2]), 0, 0))
		set("LeftElbow", CFrame.Angles(rad(a.elbow[1]), 0, 0))
		set("RightElbow", CFrame.Angles(rad(a.elbow[2]), 0, 0))
		set("LeftHip", CFrame.Angles(rad(a.hip[1]), 0, 0))
		set("RightHip", CFrame.Angles(rad(a.hip[2]), 0, 0))
		set("LeftKnee", CFrame.Angles(-rad(a.knee[1]), 0, 0))
		set("RightKnee", CFrame.Angles(-rad(a.knee[2]), 0, 0))
		set("Neck", CFrame.Angles(rad(a.neck), 0, 0))
		set("Waist", CFrame.Angles(rad(a.lean), 0, 0))
	else
		-- R6 joints rotate about Z; left side is mirrored (same as the stock Animate).
		set("RightShoulder", CFrame.Angles(0, 0, rad(a.arm[2])))
		set("LeftShoulder", CFrame.Angles(0, 0, -rad(a.arm[1])))
		set("RightHip", CFrame.Angles(0, 0, rad(a.hip[2])))
		set("LeftHip", CFrame.Angles(0, 0, -rad(a.hip[1])))
		-- (R6's neck joint is rotated oddly, so the head is left to the Animator.)
	end
	return touched
end

-- Called by the climbing controller every frame for the local player.
function ClimbAnimator.setLocal(pose: string, phase: number)
	localPose, localPhase = pose, phase
end

function ClimbAnimator.start()
	local reach = Config.Climb.ReachLength
	RunService.Stepped:Connect(function(t, dt)
		local seen = {}
		for _, other in Players:GetPlayers() do
			local character = other.Character
			if not character then
				continue
			end
			local pose, phase
			if other == player then
				pose, phase = localPose, localPhase
			else
				pose = character:GetAttribute("ClimbPose") or ""
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
				phase = (phases[character] or 0) + speed / reach * math.pi * 2 * dt
				phases[character] = phase
			end
			if pose ~= "" then
				posed[character] = apply(character, pose, phase, t)
				seen[character] = true
			end
		end
		-- Hand joints back to the Animator once a character stops climbing.
		for character, motors in posed do
			if not seen[character] then
				for _, m in motors do
					if m.Parent then
						m.Transform = CFrame.identity
					end
				end
				posed[character] = nil
				phases[character] = nil
			end
		end
	end)
end

return ClimbAnimator
