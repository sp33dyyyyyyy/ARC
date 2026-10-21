--!strict
-- Ragdoll (server): turns a character into a limp physics body and back.
--
-- Every joint except the root (HumanoidRootPart -> torso) is swapped for a
-- BallSocketConstraint with natural limits, so the body flops but no limb bends backwards.
-- Works with classic Motor6D rigs and Roblox's newer AnimationConstraint avatar joints.
-- Done on the server so every player sees it; the owning client switches its Humanoid into
-- the Physics state when it sees the "Ragdolled" attribute (ClimbController).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LimbRig = require(ReplicatedStorage:WaitForChild("Shared").LimbRig)

local FOLDER_NAME = "RagdollConstraints"
local DISABLED_ATTRIBUTE = "RagdollDisabledJoint"
local SAVED_GROUP_ATTRIBUTE = "RagdollSavedGroup"
local SAVED_COLLIDE_ATTRIBUTE = "RagdollSavedCollide"

-- How far each joint may swing, by the part it moves (degrees).
local LIMITS: { [string]: number } = {
	Head = 35,
	UpperTorso = 25,
	LeftUpperArm = 85, RightUpperArm = 85, ["Left Arm"] = 85, ["Right Arm"] = 85,
	LeftLowerArm = 95, RightLowerArm = 95,
	LeftHand = 30, RightHand = 30,
	LeftUpperLeg = 60, RightUpperLeg = 60, ["Left Leg"] = 60, ["Right Leg"] = 60,
	LeftLowerLeg = 95, RightLowerLeg = 95,
	LeftFoot = 25, RightFoot = 25,
}

local Ragdoll = {}

function Ragdoll.isRagdolled(character: Model): boolean
	return character:GetAttribute("Ragdolled") == true
end

function Ragdoll.enable(character: Model)
	if Ragdoll.isRagdolled(character) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for _, joint in LimbRig.allJoints(character) do
		if joint.part0.Name == "HumanoidRootPart" then
			continue -- keep the root part riding with the torso (the camera follows it)
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "RagdollA0"
		a0.CFrame = LimbRig.c0(joint)
		a0.Parent = joint.part0
		local a1 = Instance.new("Attachment")
		a1.Name = "RagdollA1"
		a1.CFrame = LimbRig.c1(joint)
		a1.Parent = joint.part1

		local limit = LIMITS[joint.part1.Name] or 45
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = `Ragdoll_{joint.part1.Name}`
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = limit
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -limit * 0.5
		socket.TwistUpperAngle = limit * 0.5
		socket.Parent = folder

		-- Neighbouring body parts overlap; without this they'd push each other apart.
		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Part0 = joint.part0
		noCollide.Part1 = joint.part1
		noCollide.Parent = folder

		joint.instance:SetAttribute(DISABLED_ATTRIBUTE, true);
		(joint.instance :: any).Enabled = false
	end

	-- A limp body must hit the floor with every part (climbing puts limbs in a group that
	-- ignores the world), but the invisible root part must not prop it up.
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Parent == character then
			part:SetAttribute(SAVED_GROUP_ATTRIBUTE, part.CollisionGroup)
			part:SetAttribute(SAVED_COLLIDE_ATTRIBUTE, part.CanCollide)
			part.CollisionGroup = "Default"
			part.CanCollide = part.Name ~= "HumanoidRootPart"
		end
	end

	folder.Parent = character
	character:SetAttribute("Ragdolled", true)
end

function Ragdoll.disable(character: Model)
	if not Ragdoll.isRagdolled(character) then
		return
	end
	for _, d in character:GetDescendants() do
		if d:GetAttribute(DISABLED_ATTRIBUTE) then
			d:SetAttribute(DISABLED_ATTRIBUTE, nil);
			(d :: any).Enabled = true
		elseif d:IsA("Attachment") and (d.Name == "RagdollA0" or d.Name == "RagdollA1") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			local group = d:GetAttribute(SAVED_GROUP_ATTRIBUTE)
			local collide = d:GetAttribute(SAVED_COLLIDE_ATTRIBUTE)
			if type(group) == "string" then
				d.CollisionGroup = group
			end
			if type(collide) == "boolean" then
				d.CanCollide = collide
			end
			d:SetAttribute(SAVED_GROUP_ATTRIBUTE, nil)
			d:SetAttribute(SAVED_COLLIDE_ATTRIBUTE, nil)
		end
	end
	local folder = character:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
	character:SetAttribute("Ragdolled", false)
end

return Ragdoll
