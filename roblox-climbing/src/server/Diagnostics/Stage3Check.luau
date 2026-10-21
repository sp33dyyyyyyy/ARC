--!strict
-- Stage3Check: automatic acceptance test for Stage 3 (stamina, ragdoll, falls). Runs when
-- you press Play in Studio. Re-run from the server command bar:
--     require(game.ServerScriptService.Server.Diagnostics.Stage3Check).Run()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HoldTypes = require(Shared.HoldTypes)
local LimbRig = require(Shared.LimbRig)
local StaminaMath = require(Shared.StaminaMath)

local Server = script.Parent.Parent
local Ragdoll = require(Server.Physics.Ragdoll)

local Stage3Check = {}

function Stage3Check.Run(): boolean
	local passed, failed = 0, 0
	local function check(name: string, ok: boolean, detail: string?)
		if ok then
			passed += 1
			print(`[Stage3Check] PASS  {name}`)
		else
			failed += 1
			warn(`[Stage3Check] FAIL  {name}{if detail then " -- " .. detail else ""}`)
		end
	end

	-- Stamina rules (the same pure module the server runs).
	local jug = HoldTypes.get("Jug") :: HoldTypes.HoldTypeDef
	local twoHands = {
		{ kind = "Hand", drain = jug.DrainMultiplier, quality = jug.DefaultQuality },
		{ kind = "Hand", drain = jug.DrainMultiplier, quality = jug.DefaultQuality },
	} :: { StaminaMath.Grip }
	local fourLimbs = table.clone(twoHands)
	table.insert(fourLimbs, { kind = "Foot", drain = 1, quality = 0.6 })
	table.insert(fourLimbs, { kind = "Foot", drain = 1, quality = 0.6 })
	check(
		"stamina drains while hanging and recovers resting on four limbs",
		StaminaMath.rate(twoHands, 0, Config.Stamina) < 0 and StaminaMath.rate(fourLimbs, 5, Config.Stamina) > 0
	)
	check(
		"fall thresholds are in order (jump < safe < lethal)",
		Config.Falls.SafeHeight > 7.5 and Config.Falls.LethalHeight > Config.Falls.SafeHeight
	)

	-- Ragdoll on and off, on R15 and R6 test dummies.
	for _, rigType in { Enum.HumanoidRigType.R15, Enum.HumanoidRigType.R6 } do
		local name = `ragdoll ({rigType.Name}): joints swap for ball sockets and back`
		local ok, dummy = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), rigType)
		end)
		if not ok or dummy == nil then
			check(name, false, `could not create a test dummy: {dummy}`)
			continue
		end
		local before = #LimbRig.allJoints(dummy)
		Ragdoll.enable(dummy)
		local folder = dummy:FindFirstChild("RagdollConstraints")
		local sockets = 0
		if folder then
			for _, c in folder:GetChildren() do
				if c:IsA("BallSocketConstraint") then
					sockets += 1
				end
			end
		end
		local stillRigid = #LimbRig.allJoints(dummy) -- only the root joint should be left
		local problems = {}
		if not Ragdoll.isRagdolled(dummy) then
			table.insert(problems, "not marked Ragdolled")
		end
		if sockets < before - 1 or sockets == 0 then
			table.insert(problems, `{sockets} ball sockets for {before} joints`)
		end
		if stillRigid ~= 1 then
			table.insert(problems, `{stillRigid} joints still rigid (expected just the root)`)
		end
		Ragdoll.disable(dummy)
		if #LimbRig.allJoints(dummy) ~= before then
			table.insert(problems, `after getting up {#LimbRig.allJoints(dummy)} of {before} joints are back`)
		end
		if dummy:FindFirstChild("RagdollConstraints") or Ragdoll.isRagdolled(dummy) then
			table.insert(problems, "ragdoll leftovers after getting up")
		end
		check(name, #problems == 0, table.concat(problems, "; "))
		dummy:Destroy()
	end

	print(`[Stage3Check] {passed} passed, {failed} failed`)
	return failed == 0
end

return Stage3Check
