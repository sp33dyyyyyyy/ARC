--!strict
-- Stage4Check: automatic acceptance test for the world and route features (gym,
-- outdoor crags, routes, ropes, chalk, saving, leaderboards). Runs when you press Play in
-- Studio. Re-run from the server command bar:
--     require(game.ServerScriptService.Server.Diagnostics.Stage4Check).Run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Gear = require(Shared.Gear)
local StaminaMath = require(Shared.StaminaMath)

local Services = script.Parent.Parent.Services
local DataService = require(Services.DataService)
local LeaderboardService = require(Services.LeaderboardService)
local RouteService = require(Services.RouteService)

-- Furthest a climber can get from one hold to the next (two arm reaches, plus standing on
-- a ledge between them on the big walls).
local MAX_HOLD_GAP = 6.5

local Stage4Check = {}

function Stage4Check.Run(): boolean
	local passed, failed = 0, 0
	local function check(name: string, ok: boolean, detail: string?)
		if ok then
			passed += 1
			print(`[Stage4Check] PASS  {name}`)
		else
			failed += 1
			warn(`[Stage4Check] FAIL  {name}{if detail then " -- " .. detail else ""}`)
		end
	end

	local remotesOk = pcall(function()
		Remotes.event("RouteEvent")
		Remotes.event("RouteRequest")
	end)
	check("route remotes exist", remotesOk)

	local crags = Workspace:FindFirstChild("Crags")
	check("gym built", Workspace:FindFirstChild("Gym") ~= nil)
	check("outdoors built", Workspace:FindFirstChild("Outdoors") ~= nil)
	check(
		"three outdoor walls built",
		crags ~= nil and crags:FindFirstChild("WallA") ~= nil and crags:FindFirstChild("WallB") ~= nil and crags:FindFirstChild("Colossus") ~= nil
	)

	-- Every route is complete and climbable.
	local routes = Workspace:FindFirstChild("Routes")
	local routeCount = 0
	local problems: { string } = {}
	local orders: { [number]: string } = {}
	for _, route in (if routes then routes:GetChildren() else {}) do
		if route:GetAttribute("RouteName") == nil then
			continue
		end
		routeCount += 1
		local name = route.Name
		for _, attribute in { "Grade", "Order", "HeightStuds", "HeightMeters", "BaseY", "StartPosition", "TopAnchor" } do
			if route:GetAttribute(attribute) == nil then
				table.insert(problems, `{name}: no {attribute}`)
			end
		end
		local order = route:GetAttribute("Order")
		if type(order) == "number" then
			if orders[order] then
				table.insert(problems, `{name}: same Order as {orders[order]}`)
			end
			orders[order] = name
		end
		if route:FindFirstChild("StartPad") == nil or route:FindFirstChild("Summit") == nil then
			table.insert(problems, `{name}: missing StartPad/Summit`)
		end
		if route:GetAttribute("Leaderboard") == true and route:FindFirstChild("Sign") == nil then
			table.insert(problems, `{name}: leaderboard route without a sign`)
		end
		if route:GetAttribute("Rope") == true and route:FindFirstChild("RopeBag") == nil then
			table.insert(problems, `{name}: rope route without a rope bag`)
		end
		local belay = route:FindFirstChild("AutoBelay")
		if route:GetAttribute("AutoBelay") == true and (belay == nil or belay:FindFirstChild("ClipIn", true) == nil) then
			table.insert(problems, `{name}: auto-belay route without a click-to-clip carabiner`)
		end

		local holds: { BasePart } = {}
		local roles = { Start = 0, Finish = 0 }
		local folder = route:FindFirstChild("Holds")
		for _, hold in (if folder then folder:GetChildren() else {}) do
			if hold:IsA("BasePart") then
				table.insert(holds, hold)
				local role = hold:GetAttribute("Role")
				if role == "Start" or role == "Finish" then
					roles[role] += 1
				end
			end
		end
		if #holds < 2 or roles.Start == 0 or roles.Finish == 0 then
			table.insert(problems, `{name}: {#holds} holds, {roles.Start} start, {roles.Finish} finish`)
			continue
		end
		-- Every hold has a neighbour within reach (no impossible gaps).
		for _, hold in holds do
			local nearest = math.huge
			for _, other in holds do
				if other ~= hold then
					nearest = math.min(nearest, (other.Position - hold.Position).Magnitude)
				end
			end
			if nearest > MAX_HOLD_GAP then
				table.insert(problems, `{name}: {hold.Name} is {math.floor(nearest * 10) / 10} studs from any other hold`)
				break
			end
		end
	end
	check(`every route is complete ({routeCount} routes)`, routeCount >= 20 and #problems == 0, table.concat(problems, "; "))

	-- Pure rules.
	local firstGems = RouteService.rewardsFor(10, true, true)
	local repeatGems = RouteService.rewardsFor(10, false, false)
	check("first summit pays more than a repeat", firstGems > repeatGems and repeatGems >= 1)
	check("levels go up with XP", DataService.levelFor(0) == 1 and DataService.levelFor(100) == 2 and DataService.levelFor(10000) == 11)
	check("times format as m:ss.cc", LeaderboardService.formatTime(83450) == "1:23.45", LeaderboardService.formatTime(83450))
	check(
		"chalk slows stamina drain but not recovery",
		StaminaMath.withChalk(-10, 1, Config.Chalk.DrainReduction) > -10 and StaminaMath.withChalk(5, 1, Config.Chalk.DrainReduction) == 5
	)
	-- Gear: every slot has a free item, prices are sane, and the shop and lockers exist.
	local gearOk = true
	for _, slot in Gear.SLOTS do
		local default = Gear.default(slot :: Gear.Slot)
		if default == nil or default.price ~= 0 then
			gearOk = false
		end
	end
	for _, item in Gear.ITEMS do
		if item.price < 0 or (item.stats.footDrain and item.stats.footDrain > 1) then
			gearOk = false
		end
	end
	check("gear catalog: a free item in every slot, upgrades only help", gearOk)
	local gym = Workspace:FindFirstChild("Gym")
	check(
		"pro shop and lockers are in the gym",
		gym ~= nil and gym:FindFirstChild("OpenShop", true) ~= nil and gym:FindFirstChild("OpenLocker", true) ~= nil
	)
	-- Ropes are optional and work by clicking: rope bags and carabiners have ClickDetectors.
	local clickable, total = 0, 0
	for _, route in (if routes then routes:GetChildren() else {}) do
		local bag = route:FindFirstChild("RopeBag")
		local belay = route:FindFirstChild("AutoBelay")
		for _, thing in { bag, belay } do
			if thing then
				total += 1
				if thing:FindFirstChildWhichIsA("ClickDetector", true) then
					clickable += 1
				end
			end
		end
	end
	check(`every rope bag and auto-belay clips in with a click ({clickable}/{total})`, total > 0 and clickable == total)
	check("saving is " .. (if DataService.IsPersistent() then "on" else "in memory only (Studio API access off)"), true)

	print(`[Stage4Check] {passed} passed, {failed} failed`)
	return failed == 0
end

return Stage4Check
