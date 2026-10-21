--!strict
-- Stage2Check: automatic acceptance test for Stage 2 (limb climbing). Runs when you press
-- Play in Studio and prints PASS/FAIL lines to Output. Re-run from the server command bar:
--     require(game.ServerScriptService.Server.Diagnostics.Stage2Check).Run()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClimbMath = require(Shared.ClimbMath)
local Config = require(Shared.Config)
local HoldUtil = require(Shared.HoldUtil)
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

	-- IK rig on a test R15 dummy
	local ok, dummy = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if ok and dummy then
		local humanoid = dummy:FindFirstChildOfClass("Humanoid") :: Humanoid
		local rig = ClimbService.buildIK(dummy, humanoid)
		local problems = {}
		for _, limb in Config.LimbOrder do
			local def = Config.Limbs[limb]
			local control = rig and rig[limb]
			if control == nil then
				table.insert(problems, `{limb}: no IKControl`)
			elseif not (control.ChainRoot and control.ChainRoot.Name == def.ChainRoot and control.EndEffector and control.EndEffector.Name == def.EndEffector and control.Pole) then
				table.insert(problems, `{limb}: wrong chain`)
			end
		end
		check("IK rig: 4 IKControls with the right chains and poles", #problems == 0, table.concat(problems, "; "))
		dummy:Destroy()
	else
		check("IK rig: 4 IKControls with the right chains and poles", false, `could not create a test dummy: {dummy}`)
	end

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
