--!strict
-- LimbRig: the joints of an R6 or R15 character, and the maths to pose them.
--
-- Works with both kinds of character joints Roblox uses:
--   * Motor6D (classic rigs): C0 / C1 offsets on Part0 / Part1
--   * AnimationConstraint (Roblox's newer avatar joints): Attachment0 / Attachment1
-- In both, Part1 = Part0.CFrame * C0 * Transform * C1:Inverse(), and the climbing animator
-- only ever writes Transform (from RunService.PreSimulation, after animations).
--
-- Limbs are solved as two bones on R15 (shoulder + elbow, hip + knee) so elbows and knees
-- bend towards a "pole" direction, and as one bone on R6.

export type Joint = {
	instance: Instance, -- Motor6D or AnimationConstraint
	isMotor: boolean,
	part0: BasePart,
	part1: BasePart,
}

export type Chain = {
	name: string,
	upper: Joint, -- shoulder / hip
	lower: Joint?, -- elbow / knee (R15 only)
	tipPart: BasePart, -- the part the hand/foot point is on
	tipOffset: Vector3, -- hand/foot point in tipPart space
	tipLocal: Vector3, -- hand/foot point in the space of the last solved part (lower, or upper on R6)
	upperLength: number,
	lowerLength: number, -- 0 on R6
	upperAxis: Vector3, -- upper part space: joint pivot -> next pivot (or tip on R6)
	lowerAxis: Vector3, -- lower part space: elbow/knee pivot -> tip (zero on R6)
}

export type Rig = {
	isR15: boolean,
	chains: { [string]: Chain },
	waist: Joint?, -- R15 UpperTorso
	root: Joint?, -- R15 LowerTorso
	neck: Joint?,
	missing: { string },
}

type ChainNames = { upper: string, lower: string?, tip: string }
local R15: { [string]: ChainNames } = {
	LeftHand = { upper = "LeftUpperArm", lower = "LeftLowerArm", tip = "LeftHand" },
	RightHand = { upper = "RightUpperArm", lower = "RightLowerArm", tip = "RightHand" },
	LeftFoot = { upper = "LeftUpperLeg", lower = "LeftLowerLeg", tip = "LeftFoot" },
	RightFoot = { upper = "RightUpperLeg", lower = "RightLowerLeg", tip = "RightFoot" },
}
local R6: { [string]: ChainNames } = {
	LeftHand = { upper = "Left Arm", tip = "Left Arm" },
	RightHand = { upper = "Right Arm", tip = "Right Arm" },
	LeftFoot = { upper = "Left Leg", tip = "Left Leg" },
	RightFoot = { upper = "Right Leg", tip = "Right Leg" },
}

local LimbRig = {}

---------------------------------------------------------------------------------------
-- Joints

function LimbRig.c0(joint: Joint): CFrame
	local instance = joint.instance :: any
	return if joint.isMotor then instance.C0 else instance.Attachment0.CFrame
end

function LimbRig.c1(joint: Joint): CFrame
	local instance = joint.instance :: any
	return if joint.isMotor then instance.C1 else instance.Attachment1.CFrame
end

-- World frame of the joint pivot (Transform applies here). `part0CFrame` overrides
-- part0's current CFrame (used when the parent was just posed this frame).
function LimbRig.frame(joint: Joint, part0CFrame: CFrame?): CFrame
	return (part0CFrame or joint.part0.CFrame) * LimbRig.c0(joint)
end

function LimbRig.setTransform(joint: Joint, transform: CFrame)
	(joint.instance :: any).Transform = transform
end

function LimbRig.getTransform(joint: Joint): CFrame
	return (joint.instance :: any).Transform
end

-- World CFrame of part1 for a given Transform.
function LimbRig.childFrame(joint: Joint, transform: CFrame, part0CFrame: CFrame?): CFrame
	return LimbRig.frame(joint, part0CFrame) * transform * LimbRig.c1(joint):Inverse()
end

-- Every enabled Motor6D / AnimationConstraint in `character`, keyed by the part it moves.
-- If a rig has both for one part (a leftover from the joint upgrade), the enabled one wins,
-- then the Motor6D.
local function jointsByChild(character: Model): { [BasePart]: Joint }
	local result: { [BasePart]: Joint } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			local p0, p1 = d.Part0, d.Part1
			if p0 and p1 and d.Enabled then
				result[p1] = { instance = d, isMotor = true, part0 = p0, part1 = p1 }
			end
		end
	end
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") and d.Enabled then
			local a0, a1 = d.Attachment0, d.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") and result[p1] == nil then
				result[p1] = { instance = d, isMotor = false, part0 = p0, part1 = p1 }
			end
		end
	end
	return result
end

-- Every enabled joint in `character` (ragdolls swap these for ball sockets).
function LimbRig.allJoints(character: Model): { Joint }
	local list = {}
	for _, joint in jointsByChild(character) do
		table.insert(list, joint)
	end
	return list
end

---------------------------------------------------------------------------------------
-- Finding the rig

function LimbRig.find(character: Model): Rig
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
	local joints = jointsByChild(character)
	local function jointFor(name: string?): Joint?
		local part = if name then character:FindFirstChild(name) else nil
		return if part and part:IsA("BasePart") then joints[part] else nil
	end

	local rig: Rig = {
		isR15 = isR15,
		chains = {},
		waist = if isR15 then jointFor("UpperTorso") else nil,
		root = if isR15 then jointFor("LowerTorso") else nil,
		neck = jointFor("Head"),
		missing = {},
	}

	local layout: { [string]: ChainNames } = if isR15 then R15 else R6
	for limb, names in layout do
		local upper = jointFor(names.upper)
		local tipPart = character:FindFirstChild(names.tip)
		if upper == nil or tipPart == nil or not tipPart:IsA("BasePart") then
			table.insert(rig.missing, `{limb} ({names.upper})`)
			continue
		end

		local lower = jointFor(names.lower)
		local wrist = jointFor(names.tip)
		if isR15 and lower and wrist and wrist.part0 == lower.part1 then
			-- Two bones. Pivots in each part's own space come straight from the offsets.
			local shoulderInUpper = LimbRig.c1(upper).Position
			local elbowInUpper = LimbRig.c0(lower).Position
			local elbowInLower = LimbRig.c1(lower).Position
			local wristInLower = LimbRig.c0(wrist).Position
			local forearm = wristInLower - elbowInLower
			-- The hand/foot point is its part centre, a little past the wrist/ankle.
			local handExtent = LimbRig.c1(wrist).Position.Magnitude
			local tipLocal = wristInLower + (if forearm.Magnitude > 1e-4 then forearm.Unit else Vector3.new(0, -1, 0)) * handExtent
			rig.chains[limb] = {
				name = limb,
				upper = upper,
				lower = lower,
				tipPart = tipPart,
				tipOffset = Vector3.zero,
				tipLocal = tipLocal,
				upperLength = (elbowInUpper - shoulderInUpper).Magnitude,
				lowerLength = (tipLocal - elbowInLower).Magnitude,
				upperAxis = elbowInUpper - shoulderInUpper,
				lowerAxis = tipLocal - elbowInLower,
			}
		else
			-- One bone (R6, or an R15 rig missing its elbow/knee): the whole limb pivots.
			local tipOffset = if isR15 then Vector3.zero else Vector3.new(0, -tipPart.Size.Y / 2 + 0.25, 0)
			local tipInUpper = if tipPart == upper.part1
				then tipOffset
				else upper.part1.CFrame:PointToObjectSpace(tipPart.CFrame:PointToWorldSpace(tipOffset))
			local axis = tipInUpper - LimbRig.c1(upper).Position
			rig.chains[limb] = {
				name = limb,
				upper = upper,
				lower = nil,
				tipPart = tipPart,
				tipOffset = tipOffset,
				tipLocal = tipInUpper,
				upperLength = axis.Magnitude,
				lowerLength = 0,
				upperAxis = axis,
				lowerAxis = Vector3.zero,
			}
		end
	end
	return rig
end

---------------------------------------------------------------------------------------
-- Solving

-- Rotation that turns direction `from` onto direction `to` (both unit).
function LimbRig.rotationBetween(from: Vector3, to: Vector3): CFrame
	local dot = math.clamp(from:Dot(to), -1, 1)
	if dot > 0.99999 then
		return CFrame.identity
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-5 then
		axis = if math.abs(from.X) < 0.9 then from:Cross(Vector3.xAxis) else from:Cross(Vector3.zAxis)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Transform for `joint` that points `axis` (a direction in part1 space) along the world
-- direction `want`.
function LimbRig.aimTransform(joint: Joint, axis: Vector3, want: Vector3, part0CFrame: CFrame?): CFrame
	if want.Magnitude < 1e-4 or axis.Magnitude < 1e-4 then
		return CFrame.identity
	end
	local frame = LimbRig.frame(joint, part0CFrame)
	local rest = LimbRig.c1(joint):Inverse():VectorToWorldSpace(axis).Unit
	local wanted = frame:VectorToObjectSpace(want).Unit
	return LimbRig.rotationBetween(rest, wanted)
end

-- Where the middle joint (elbow/knee) goes for a two-bone limb from `start` to `target`,
-- bending towards the world direction `pole`. The target is clamped to what the limb can
-- reach, so a far target gives a straight limb pointing at it.
function LimbRig.bendPoint(start: Vector3, target: Vector3, upperLength: number, lowerLength: number, pole: Vector3): Vector3
	local toTarget = target - start
	local direction = if toTarget.Magnitude > 1e-4 then toTarget.Unit else Vector3.new(0, -1, 0)
	local reach = upperLength + lowerLength
	local distance = math.clamp(toTarget.Magnitude, math.abs(upperLength - lowerLength) + 1e-3, reach - 1e-3)
	local cosA = (upperLength * upperLength + distance * distance - lowerLength * lowerLength) / (2 * upperLength * distance)
	cosA = math.clamp(cosA, -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local bend = pole - direction * pole:Dot(direction)
	if bend.Magnitude < 1e-4 then
		bend = if math.abs(direction.Y) < 0.9 then direction:Cross(Vector3.yAxis) else direction:Cross(Vector3.xAxis)
	end
	return start + direction * (upperLength * cosA) + bend.Unit * (upperLength * sinA)
end

-- Transforms for the upper and lower joints that put the hand/foot at `target`, with the
-- elbow/knee bending towards `pole`. `part0CFrame` overrides the torso's CFrame.
function LimbRig.solve(chain: Chain, target: Vector3, pole: Vector3, part0CFrame: CFrame?): (CFrame, CFrame?)
	local start = LimbRig.frame(chain.upper, part0CFrame).Position
	local lower = chain.lower
	if lower == nil then
		return LimbRig.aimTransform(chain.upper, chain.upperAxis, target - start, part0CFrame), nil
	end
	local elbow = LimbRig.bendPoint(start, target, chain.upperLength, chain.lowerLength, pole)
	local upperT = LimbRig.aimTransform(chain.upper, chain.upperAxis, elbow - start, part0CFrame)
	local upperWorld = LimbRig.childFrame(chain.upper, upperT, part0CFrame)
	local lowerT = LimbRig.aimTransform(lower, chain.lowerAxis, target - LimbRig.frame(lower, upperWorld).Position, upperWorld)
	return upperT, lowerT
end

-- Where the hand/foot ends up for given Transforms (forward kinematics; used by checks).
function LimbRig.forward(chain: Chain, upperT: CFrame, lowerT: CFrame?, part0CFrame: CFrame?): Vector3
	local upperWorld = LimbRig.childFrame(chain.upper, upperT, part0CFrame)
	local lower = chain.lower
	if lower == nil then
		return upperWorld * chain.tipLocal
	end
	return LimbRig.childFrame(lower, lowerT or CFrame.identity, upperWorld) * chain.tipLocal
end

function LimbRig.tipPosition(chain: Chain): Vector3
	return chain.tipPart.CFrame:PointToWorldSpace(chain.tipOffset)
end

---------------------------------------------------------------------------------------

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
