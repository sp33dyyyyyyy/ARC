--!strict
-- Stage2Check: automatic acceptance test for Stage 2 (limb climbing). Runs when you press
-- Play in Studio and prints PASS/FAIL lines to Output. Re-run from the server command bar:
--     require(game.ServerScriptService.Server.Diagnostics.Stage2Check).Run()

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClimbMath = require(Shared.ClimbMath)
local Config = require(Shared.Config)
local HoldUtil = require(Shared.HoldUtil)
local LimbRig = require(Shared.LimbRig)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local ClimbService = require(Server.Services.ClimbService)
local HoldService = require(Server.Services.HoldService)
local TestWall = require(Server.World.TestWall)

local Stage2Check = {}

local function grip(id: string): Vector3?
	local hold = HoldService.GetHold(id)
	return if hold then HoldUtil.getGripCFrame(hold).Position else nil
end

function Stage2Check.Run(): boolean
	local passed, failed = 0, 0
	local function check(name: string, ok: boolean, detail: string?)
		if ok then
			passed += 1
			print(`[Stage2Check] PASS  {name}`)
		else
			failed += 1
			warn(`[Stage2Check] FAIL  {name}{if detail then " -- " .. detail else ""}`)
		end
	end

	-- Remotes
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local missing = {}
	for _, name in Remotes.Names do
		local remote = folder and folder:FindFirstChild(name)
		if not (remote and remote:IsA("RemoteEvent")) then
			table.insert(missing, name)
		end
	end
	check("remote events exist", #missing == 0, "missing " .. table.concat(missing, ", "))

	-- Limb rigs on R15 and R6 test dummies: all four shoulder/hip joints are found, and the
	-- aim maths turns each limb (which hangs along -Y) to point at a target.
	for _, rigType in { Enum.HumanoidRigType.R15, Enum.HumanoidRigType.R6 } do
		local name = `limb rig ({rigType.Name}): 4 joints found and aim points the limb at a target`
		local ok, dummy = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), rigType)
		end)
		if not ok or dummy == nil then
			check(name, false, `could not create a test dummy: {dummy}`)
			continue
		end
		local limbs, missingJoints = LimbRig.find(dummy)
		local problems = table.clone(missingJoints)
		for limbName, limb in limbs do
			local jointFrame = (limb.joint.Part0 :: BasePart).CFrame * limb.joint.C0
			local target = jointFrame.Position + Vector3.new(0.7, 2, -1.5)
			local transform = LimbRig.aimTransform(limb, target)
			-- With that Transform the limb's down axis must point at the target.
			local limbFrame = jointFrame * transform * limb.joint.C1:Inverse()
			local pointing = limbFrame:VectorToWorldSpace(Vector3.new(0, -1, 0))
			local wanted = (target - jointFrame.Position).Unit
			if pointing:Dot(wanted) < 0.999 then
				table.insert(problems, `{limbName} points {pointing:Dot(wanted)} off`)
			end
		end
		check(name, #problems == 0, table.concat(problems, "; "))
		dummy:Destroy()
	end

	local group = Config.Climb.LimbCollisionGroup
	check(
		`collision group "{group}" exists and ignores the world`,
		PhysicsService:IsCollisionGroupRegistered(group) and not PhysicsService:CollisionGroupsAreCollidable(group, "Default")
	)

	-- Server reach/type rules, from a climber standing on the start pad
	local route = TestWall.Find()
	local pad = route and route:FindFirstChild("StartPad")
	if pad and pad:IsA("BasePart") then
		local standing = pad.Position - Vector3.yAxis * (pad.Size.Y / 2 - 3)
		local cases: { { any } } = {
			{ "start jug, left hand", "LeftHand", "TestWall_05", nil },
			{ "foothold, right foot", "RightFoot", "TestWall_01", nil },
			{ "foothold refused for a hand", "LeftHand", "TestWall_01", "feet only" },
			{ "pinch refused for a foot", "LeftFoot", "TestWall_10", "hands only" },
			{ "finish hold refused from the ground", "RightHand", "TestWall_20", "out of reach" },
			{ "unknown hold refused", "LeftHand", "TestWall_99", "no such hold" },
			{ "unknown limb refused", "Tail", "TestWall_05", "unknown limb" },
			{ "non-string hold id refused", "LeftHand", 5, "bad hold id" },
		}
		for _, case in cases do
			local name, limb, id, expected = case[1], case[2], case[3], case[4]
			local result = ClimbService.CheckPlace(standing, limb, id)
			local good = if expected then (not result.ok and result.reason == expected) else result.ok
			check(`CheckPlace: {name}`, good, `got ok={result.ok} reason={result.reason}`)
		end
	else
		check("CheckPlace cases", false, "TestWall StartPad not found")
	end

	-- Body solver on the start position: both hands on the start jugs, feet on the footholds
	local hands = { grip("TestWall_05"), grip("TestWall_06") }
	local feet = { grip("TestWall_01"), grip("TestWall_02") }
	if hands[1] and hands[2] and feet[1] and feet[2] then
		local wallNormal = TestWall.getFrame().normal
		local grips: { ClimbMath.Grip } = {}
		for _, p in hands do
			table.insert(grips, { kind = "Hand", position = p :: Vector3, reach = Config.Limbs.LeftHand.Reach })
		end
		for _, p in feet do
			table.insert(grips, { kind = "Foot", position = p :: Vector3, reach = Config.Limbs.LeftFoot.Reach })
		end
		local planePoint = ((hands[1] :: Vector3) + (feet[1] :: Vector3)) / 2
		local problems = {}
		for _, shift in { Vector2.zero, Vector2.new(1, 1), Vector2.new(-1, -1) } do
			local body, satisfied = ClimbMath.solveBody(grips, wallNormal, shift, Config.Climb)
			for _, g in grips do
				if (body - g.position).Magnitude > g.reach + 1e-3 then
					table.insert(problems, `shift {shift}: a limb is out of reach`)
				end
			end
			if (body - planePoint):Dot(wallNormal) < Config.Climb.MinWallGap - 1e-3 then
				table.insert(problems, `shift {shift}: body inside the wall`)
			end
			if shift == Vector2.zero and not satisfied then
				table.insert(problems, "resting pose not satisfied")
			end
		end
		local rest = ClimbMath.solveBody(grips, wallNormal, Vector2.zero, Config.Climb)
		if not (rest.Y > (feet[1] :: Vector3).Y and rest.Y < (hands[1] :: Vector3).Y) then
			table.insert(problems, "resting body is not between feet and hands")
		end
		check("body solver keeps limbs in reach and the body off the wall", #problems == 0, table.concat(problems, "; "))

		local hanging = ClimbMath.solveBody({ grips[1], grips[2] }, wallNormal, Vector2.zero, Config.Climb)
		check("hands only: body hangs below the hands", hanging.Y < (hands[1] :: Vector3).Y - 1.5, `body y {hanging.Y}`)
	else
		check("body solver", false, "start holds not found")
	end

	print(`[Stage2Check] {passed} passed, {failed} failed`)
	return failed == 0
end

return Stage2Check
