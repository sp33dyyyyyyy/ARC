-- Rock-climbing animation, procedural (no uploaded animation assets).
--
-- Poses come from the pure ClimbPose module. They're applied by offsetting each
-- joint's C0 rather than writing Motor6D.Transform: Roblox's Animator rewrites
-- Transform every frame, which is why the old animation never showed up and
-- climbers looked like they were floating. While someone is posed, their
-- regular animations are stopped (the owner's client does this, and stopping
-- replicates), so nothing fights the pose.
--
-- Every client animates every climbing character: yours from the controller's
-- exact move progress, others' from their "ClimbPose" attribute (set by the
-- server) with move progress estimated from how fast they're moving.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ClimbPose = require(ReplicatedStorage.Shared.ClimbPose)

local ClimbAnimator = {}

local player = Players.LocalPlayer
local localMode, localCycle = "", 0
local cycles: { [Model]: number } = {}
-- Original C0 for every joint we've offset, so it can be put back exactly.
local originals: { [Motor6D]: CFrame } = {}
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

local function findMotor(character: Model, r15: boolean, joint: string): Motor6D?
	local m
	if r15 then
		local partName = R15[joint]
		local part = partName and character:FindFirstChild(partName)
		m = part and part:FindFirstChild(joint)
	else
		local name = R6[joint]
		local torso = character:FindFirstChild("Torso")
		m = name and torso and torso:FindFirstChild(name)
	end
	return if m and m:IsA("Motor6D") then m else nil
end

local function apply(character: Model, mode: string, cycle: number, t: number): { Motor6D }
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return {}
	end
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local a = ClimbPose.angles(mode, cycle, t, Config.Climb.ReachFraction)
	local touched = {}
	local function set(joint: string, rotation: CFrame)
		local m = findMotor(character, r15, joint)
		if not m then
			return
		end
		if not originals[m] then
			originals[m] = m.C0
		end
		m.C0 = originals[m] * rotation
		m.Transform = CFrame.identity
		table.insert(touched, m)
	end
	if r15 then
		-- R15 joints share the torso's axes: +X swings a limb forward/up.
		set("LeftShoulder", CFrame.Angles(rad(a.shoulder[1]), 0, 0))
		set("RightShoulder", CFrame.Angles(rad(a.shoulder[2]), 0, 0))
		set("LeftElbow", CFrame.Angles(-rad(a.elbow[1]), 0, 0)) -- forearm folds toward the wall
		set("RightElbow", CFrame.Angles(-rad(a.elbow[2]), 0, 0))
		set("LeftHip", CFrame.Angles(rad(a.hip[1]), 0, 0))
		set("RightHip", CFrame.Angles(rad(a.hip[2]), 0, 0))
		set("LeftKnee", CFrame.Angles(-rad(a.knee[1]), 0, 0))
		set("RightKnee", CFrame.Angles(-rad(a.knee[2]), 0, 0))
		set("Neck", CFrame.Angles(rad(a.neck), 0, 0))
		set("Waist", CFrame.Angles(rad(a.lean), 0, 0))
	else
		-- R6 joints swing about Z with the left side mirrored (like the stock Animate).
		set("RightShoulder", CFrame.Angles(0, 0, rad(a.shoulder[2])))
		set("LeftShoulder", CFrame.Angles(0, 0, -rad(a.shoulder[1])))
		set("RightHip", CFrame.Angles(0, 0, rad(a.hip[2])))
		set("LeftHip", CFrame.Angles(0, 0, -rad(a.hip[1])))
	end
	return touched
end

local function restore(motors: { Motor6D })
	for _, m in motors do
		local original = originals[m]
		if original and m.Parent then
			m.C0 = original
		end
		originals[m] = nil
	end
end

-- Called by the climbing controller every frame for the local player.
-- mode: "" | "climb" | "rest" | "leap"; cycle: move number + progress.
function ClimbAnimator.setLocal(mode: string, cycle: number)
	localMode, localCycle = mode, cycle
end

function ClimbAnimator.start()
	local reach = Config.Climb.ReachLength
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local seen = {}
		for _, other in Players:GetPlayers() do
			local character = other.Character
			if not character then
				continue
			end
			local mode, cycle
			if other == player then
				mode, cycle = localMode, localCycle
				if mode ~= "" then
					-- Stop our regular animations so they don't fight the pose.
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
					if animator then
						for _, track in animator:GetPlayingAnimationTracks() do
							track:Stop(0.1)
						end
					end
				end
			else
				mode = tostring(character:GetAttribute("ClimbPose") or "")
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
				cycle = (cycles[character] or 0) + math.min(speed, 30) / reach * dt
				cycles[character] = cycle
			end
			if mode ~= "" then
				posed[character] = apply(character, mode, cycle, t)
				seen[character] = true
			end
		end
		-- Put joints back once a character stops climbing (or is gone).
		for character, motors in posed do
			if not seen[character] then
				restore(motors)
				posed[character] = nil
				cycles[character] = nil
			end
		end
	end)
end

return ClimbAnimator
