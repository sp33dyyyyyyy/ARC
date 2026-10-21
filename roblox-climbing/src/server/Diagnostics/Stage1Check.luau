--!strict
-- Stage1Check: automatic acceptance test for Stage 1. Runs when you press Play in Studio
-- (Config.Debug.RunSelfChecksInStudio) and prints PASS/FAIL lines to the Output window.
-- Run it again any time from the server command bar during Play:
--     require(game.ServerScriptService.Server.Diagnostics.Stage1Check).Run()

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HoldTypes = require(Shared.HoldTypes)
local HoldUtil = require(Shared.HoldUtil)
local Tags = require(Shared.Tags)

local Server = script.Parent.Parent
local HoldService = require(Server.Services.HoldService)
local TestWall = require(Server.World.TestWall)
local Layout = require(Server.World.TestWallLayout)

local Stage1Check = {}

local function taggedUnder(root: Instance, tag: string): { Instance }
	local found = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(root) then
			table.insert(found, instance)
		end
	end
	return found
end

function Stage1Check.Run(): boolean
	local passed, failed = 0, 0
	local function check(name: string, ok: boolean, detail: string?)
		if ok then
			passed += 1
			print(`[Stage1Check] PASS  {name}`)
		else
			failed += 1
			warn(`[Stage1Check] FAIL  {name}{if detail then " -- " .. detail else ""}`)
		end
	end

	local route = TestWall.Find()
	check("Workspace.Routes.TestWall exists", route ~= nil)
	if route == nil then
		return false
	end

	local holdsFolder = route:FindFirstChild("Holds")
	check("TestWall has a Holds folder", holdsFolder ~= nil)

	local holds = taggedUnder(route, Tags.Hold)
	check(`{#Layout.Holds} holds tagged "{Tags.Hold}"`, #holds == #Layout.Holds, `found {#holds}`)

	local problems: { string } = {}
	local ids: { [string]: boolean } = {}
	local typesSeen: { [string]: boolean } = {}
	local starts, finishes = 0, 0
	for _, instance in holds do
		local part = instance :: BasePart
		local info = HoldUtil.read(part)
		if info == nil then
			table.insert(problems, `{part.Name}: unreadable`)
			continue
		end
		if not HoldTypes.isValid(part:GetAttribute("HoldType")) then
			table.insert(problems, `{part.Name}: bad HoldType`)
		end
		local quality = part:GetAttribute("Quality")
		if type(quality) ~= "number" or quality < 0 or quality > 1 then
			table.insert(problems, `{part.Name}: Quality out of 0..1`)
		end
		if type(part:GetAttribute("HandOK")) ~= "boolean" or type(part:GetAttribute("FootOK")) ~= "boolean" then
			table.insert(problems, `{part.Name}: HandOK/FootOK missing`)
		end
		if not part.Anchored then
			table.insert(problems, `{part.Name}: not anchored`)
		end
		if not part:FindFirstChild(HoldUtil.GRIP_ATTACHMENT) then
			table.insert(problems, `{part.Name}: no Grip attachment`)
		end
		if info.Id == nil or ids[info.Id] then
			table.insert(problems, `{part.Name}: missing or duplicate HoldId`)
		else
			ids[info.Id] = true
			if HoldService.GetHold(info.Id) ~= part then
				table.insert(problems, `{part.Name}: not registered in HoldService`)
			end
		end
		typesSeen[info.Type] = true
		if info.Role == "Start" then
			starts += 1
		elseif info.Role == "Finish" then
			finishes += 1
		end
	end
	check("every hold has valid attributes, a Grip and a unique registered HoldId", #problems == 0, table.concat(problems, "; "))

	local missingTypes = {}
	for _, name in HoldTypes.Names do
		if not typesSeen[name] then
			table.insert(missingTypes, name)
		end
	end
	check("every hold type is on the wall", #missingTypes == 0, "missing " .. table.concat(missingTypes, ", "))
	check("2 start holds and 1 finish hold", starts == 2 and finishes == 1, `starts={starts} finishes={finishes}`)

	local wall = route:FindFirstChild("Wall") :: BasePart?
	check(`Wall is tagged "{Tags.Climbable}"`, wall ~= nil and CollectionService:HasTag(wall, Tags.Climbable))

	-- Every hold's grip sits on the wall face (inside the width/height, just in front of it).
	if wall then
		local outside = {}
		for _, instance in holds do
			local part = instance :: BasePart
			local localGrip = wall.CFrame:PointToObjectSpace(HoldUtil.getGripCFrame(part).Position)
			local onFace = math.abs(localGrip.X) <= wall.Size.X / 2
				and math.abs(localGrip.Y) <= wall.Size.Y / 2
				and -localGrip.Z >= wall.Size.Z / 2
				and -localGrip.Z <= wall.Size.Z / 2 + 1.5
			if not onFace then
				table.insert(outside, part.Name)
			end
		end
		check("all holds sit on the wall face", #outside == 0, table.concat(outside, ", "))
	end

	check(`one "{Tags.RouteStart}" and one "{Tags.RouteSummit}" in the route`, #taggedUnder(route, Tags.RouteStart) == 1 and #taggedUnder(route, Tags.RouteSummit) == 1)

	-- Climbable without a dyno: every hold except the finish has a hold above it within reach.
	local gaps = {}
	for _, a in holds do
		local pa = HoldUtil.getGripCFrame(a :: BasePart).Position
		if (a :: BasePart):GetAttribute("Role") == "Finish" then
			continue
		end
		local best = math.huge
		for _, b in holds do
			local pb = HoldUtil.getGripCFrame(b :: BasePart).Position
			if b ~= a and pb.Y > pa.Y + 0.5 then
				best = math.min(best, (pb - pa).Magnitude)
			end
		end
		if best > Layout.MaxMoveGap then
			table.insert(gaps, `{a.Name} ({string.format("%.1f", best)})`)
		end
	end
	check(`no move longer than {Layout.MaxMoveGap} studs`, #gaps == 0, table.concat(gaps, ", "))

	-- HoldService spatial query: standing on the start pad you can reach the start jugs.
	local pad = taggedUnder(route, Tags.RouteStart)[1]
	if pad and pad:IsA("BasePart") then
		local rootHeight = Vector3.yAxis * 3
		local near = HoldService.GetHoldsNear(pad.Position + rootHeight, 8, "Hand")
		local reachesStart = false
		for _, info in near do
			if info.Role == "Start" then
				reachesStart = true
			end
			if not info.HandOK then
				reachesStart = false
				break
			end
		end
		check("GetHoldsNear(start pad) finds start holds and only hand-OK holds", reachesStart, `{#near} holds found`)
	end

	print(`[Stage1Check] {passed} passed, {failed} failed`)
	return failed == 0
end

return Stage1Check
