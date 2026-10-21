--!strict
-- LimbRig: finds each limb's shoulder/hip joint on an R6 or R15 character and points the
-- limb at a world position by setting that joint's Motor6D.Transform.
--
-- This replaces IKControl: it needs nothing created by the server, works on both rig types,
-- and a missing limb just isn't posed (climbing still works).
--
-- Set the Transform from RunService.PreSimulation, which runs after animations, so the
-- pose wins (ClimbController does this).

export type Limb = {
	name: string,
	joint: Motor6D, -- shoulder or hip
	endPart: BasePart, -- R15 hand/foot, R6 whole arm/leg
	tipOffset: Vector3, -- the hand/foot point, in endPart space
}

-- Upper segment (moved by the shoulder/hip joint) and the part holding the hand/foot point.
type PartNames = { [string]: { upper: string, tip: string } }
local PARTS: { R15: PartNames, R6: PartNames } = {
	R15 = {
		LeftHand = { upper = "LeftUpperArm", tip = "LeftHand" },
		RightHand = { upper = "RightUpperArm", tip = "RightHand" },
		LeftFoot = { upper = "LeftUpperLeg", tip = "LeftFoot" },
		RightFoot = { upper = "RightUpperLeg", tip = "RightFoot" },
	},
	R6 = {
		LeftHand = { upper = "Left Arm", tip = "Left Arm" },
		RightHand = { upper = "Right Arm", tip = "Right Arm" },
		LeftFoot = { upper = "Left Leg", tip = "Left Leg" },
		RightFoot = { upper = "Right Leg", tip = "Right Leg" },
	},
}

local DOWN = Vector3.new(0, -1, 0)

local LimbRig = {}

-- Every limb found on `character`, plus a list of what's missing (empty when complete).
function LimbRig.find(character: Model): ({ [string]: Limb }, { string })
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
	local names = if isR15 then PARTS.R15 else PARTS.R6

	-- Joints by the part they move, whatever they are called.
	local jointFor: { [Instance]: Motor6D } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			jointFor[d.Part1] = d
		end
	end

	local limbs: { [string]: Limb } = {}
	local missing: { string } = {}
	for limb, parts in names do
		local upper = character:FindFirstChild(parts.upper)
		local tip = character:FindFirstChild(parts.tip)
		local joint = upper and jointFor[upper]
		if upper and tip and tip:IsA("BasePart") and joint and joint.Part0 then
			limbs[limb] = {
				name = limb,
				joint = joint,
				endPart = tip,
				-- R6 limbs are one 2-stud part: the hand/foot is near its bottom.
				tipOffset = if isR15 then Vector3.zero else Vector3.new(0, -tip.Size.Y / 2 + 0.25, 0),
			}
		else
			table.insert(missing, `{limb} ({parts.upper})`)
		end
	end
	return limbs, missing
end

function LimbRig.tipPosition(limb: Limb): Vector3
	return limb.endPart.CFrame:PointToWorldSpace(limb.tipOffset)
end

-- The Transform that points the limb (which hangs along -Y of its part at rest) from its
-- joint straight at `target`.
function LimbRig.aimTransform(limb: Limb, target: Vector3): CFrame
	local joint = limb.joint
	local part0 = joint.Part0 :: BasePart
	local jointFrame = part0.CFrame * joint.C0
	local toTarget = target - jointFrame.Position
	if toTarget.Magnitude < 1e-3 then
		return CFrame.identity
	end
	local wanted = jointFrame:VectorToObjectSpace(toTarget).Unit
	local rest = joint.C1:Inverse():VectorToWorldSpace(DOWN).Unit
	local dot = math.clamp(rest:Dot(wanted), -1, 1)
	if dot > 0.9999 then
		return CFrame.identity
	end
	local axis = rest:Cross(wanted)
	if axis.Magnitude < 1e-4 then
		-- Pointing straight back the way it hangs: any perpendicular axis works.
		axis = if math.abs(rest.X) < 0.9 then rest:Cross(Vector3.xAxis) else rest:Cross(Vector3.zAxis)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Hands the limb back to the animations.
function LimbRig.relax(limb: Limb)
	limb.joint.Transform = CFrame.identity
end

-- Parts that belong to arms and legs, for collision groups (both rig types).
LimbRig.LIMB_PART_NAMES = table.freeze({
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
	"Left Arm", "Right Arm", "Left Leg", "Right Leg",
})

-- Height of the HumanoidRootPart centre above the floor when standing.
function LimbRig.standingHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3 -- R6: 2-stud legs + half the 2-stud torso
end

return table.freeze(LimbRig)
