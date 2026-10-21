--!strict
-- RouteService (server): timed runs on routes, summits, rewards.
--
--  * A run starts when you put a limb on one of a route's holds near its base (within
--    Config.Routes.StartBand of BaseY). The player gets "RunRoute" (route id) and
--    "RunStart" (Workspace:GetServerTimeNow()) attributes, which the HUD's timer and
--    progress bar read.
--  * You top out by clicking the route's finish button (RouteKit.addFinishButton): on top of
--    the rock outside (climb up over the edge with F, walk over, press it), on the wall at
--    the top of indoor routes. The server times the run, checks it is plausible, pays money (£) and XP (DataService),
--    records the time (LeaderboardService) and sends the client a summit card.
--  * The run fails if you die, fall onto the rope, or are back on the ground at the base.
--  * After a summit roped climbers let go (or press R) to be lowered.
--  * Clients can ask to "Retry" (back to the start of their last route) or "Travel" to
--    the base of any route.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HoldUtil = require(Shared.HoldUtil)
local LimbRig = require(Shared.LimbRig)
local Remotes = require(Shared.Remotes)

local ClimbService = require(script.Parent.ClimbService)
local DataService = require(script.Parent.DataService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local RopeService = require(script.Parent.RopeService)
local ChalkService = require(script.Parent.ChalkService)

local ROUTES = Config.Routes
local FINISH_REACH = 12 -- studs from the body to the finish button when you click it

type Run = {
	route: Instance,
	character: Model,
	started: number, -- os.clock()
	holds: { [string]: boolean }, -- distinct holds used, a sanity check
	groundFor: number,
}

export type Result = {
	routeId: string,
	routeName: string,
	grade: string,
	meters: number,
	seconds: number,
	best: number?, -- previous best
	newBest: boolean,
	firstClear: boolean,
	gems: number,
	xp: number,
	rank: number?,
}

local RouteService = {}

local runs: { [Player]: Run } = {}
local lastRoute: { [Player]: Instance } = {}
local lastRequest: { [Player]: number } = {}
local eventRemote: RemoteEvent
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function routesFolder(): Instance?
	return Workspace:FindFirstChild("Routes")
end

local function routeOf(hold: BasePart): Instance?
	local route = HoldUtil.getRouteFolder(hold)
	local routes = routesFolder()
	if route and routes and route.Parent == routes and route:GetAttribute("RouteName") ~= nil then
		return route
	end
	return nil
end

local function numberAttr(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function endRun(player: Player)
	runs[player] = nil
	player:SetAttribute("RunRoute", nil)
	player:SetAttribute("RunStart", nil)
end

function RouteService.Fail(player: Player, reason: string)
	local run = runs[player]
	if run == nil then
		return
	end
	endRun(player)
	eventRemote:FireClient(player, "Failed", run.route.Name, reason)
end

local function start(player: Player, route: Instance, character: Model)
	runs[player] = {
		route = route,
		character = character,
		started = os.clock(),
		holds = {},
		groundFor = 0,
	}
	lastRoute[player] = route
	player:SetAttribute("RunRoute", route.Name)
	player:SetAttribute("RunStart", Workspace:GetServerTimeNow())
	eventRemote:FireClient(player, "Started", route.Name)
end

local function onPlaced(player: Player, _limb: string, hold: BasePart)
	local character = player.Character
	if character == nil then
		return
	end
	local run = runs[player]
	if run then
		run.holds[tostring(hold:GetAttribute("HoldId"))] = true
		return
	end
	local route = routeOf(hold)
	if route == nil then
		return
	end
	local baseY = numberAttr(route, "BaseY", 0)
	if hold.Position.Y - baseY > ROUTES.StartBand then
		return -- jumped on halfway up: not a run
	end
	start(player, route, character)
	runs[player].holds[tostring(hold:GetAttribute("HoldId"))] = true
end

local function rewardsFor(meters: number, firstClear: boolean, newBest: boolean): (number, number)
	local gems = math.floor(ROUTES.GemsBase + ROUTES.GemsPerMeter * meters + 0.5)
	if firstClear then
		gems *= ROUTES.FirstClearBonus
	else
		gems = math.max(1, math.floor(gems / 2))
	end
	local xp = math.floor(ROUTES.XPPerMeter * meters * (if newBest then 1.5 else 1) + 0.5)
	return gems, xp
end
RouteService.rewardsFor = rewardsFor

local function summit(player: Player, run: Run)
	local route = run.route
	local seconds = os.clock() - run.started
	local rise = numberAttr(route, "HeightStuds", 10)
	local holdCount = 0
	for _ in run.holds do
		holdCount += 1
	end
	endRun(player)
	-- Plausibility: nobody climbs faster than 30 studs a second or skips most of the holds.
	if seconds < rise / 30 or holdCount < math.max(2, math.floor(rise / 8)) then
		warn(`[RouteService] {player.Name}'s run on {route.Name} looked impossible ({seconds}s, {holdCount} holds); not counted`)
		eventRemote:FireClient(player, "Failed", route.Name, "That run didn't count")
		return
	end

	local routeId = route.Name
	local meters = numberAttr(route, "HeightMeters", 0)
	local data = DataService.Get(player)
	local best = data and data.bestTimes[routeId]
	local firstClear = data == nil or (data.clears[routeId] or 0) == 0
	local newBest = best == nil or seconds < best
	local gems, xp = rewardsFor(meters, firstClear, newBest)
	DataService.Update(player, function(d)
		d.gems += gems
		d.xp += xp
		d.summits += 1
		d.totalClimbed += math.floor(meters + 0.5)
		d.clears[routeId] = (d.clears[routeId] or 0) + 1
		if newBest then
			d.bestTimes[routeId] = math.floor(seconds * 1000 + 0.5) / 1000
		end
	end)
	local rank: number? = nil
	if route:GetAttribute("Leaderboard") == true and newBest then
		rank = LeaderboardService.Submit(player, routeId, seconds)
	end

	local result: Result = {
		routeId = routeId,
		routeName = tostring(route:GetAttribute("RouteName")),
		grade = tostring(route:GetAttribute("Grade")),
		meters = meters,
		seconds = seconds,
		best = best,
		newBest = newBest,
		firstClear = firstClear,
		gems = gems,
		xp = xp,
		rank = rank,
	}
	eventRemote:FireClient(player, "Summit", result)
	if player.Character then
		RopeService.gesture(player.Character, "Summit")
	end

	-- Getting down again.
	local character = player.Character
	if character and character:GetAttribute("TiedIn") ~= nil and character:GetAttribute("Climbing") == true then
		eventRemote:FireClient(player, "Notice", "Press R (or let go) and your belayer lowers you down")
	elseif route:GetAttribute("Indoor") ~= true then
		eventRemote:FireClient(player, "Notice", "Retry, or M on your phone to travel back down")
	end
	if meters >= 50 then
		local text = `{player.DisplayName} topped {result.routeName} in {LeaderboardService.formatTime(seconds * 1000)}!`
		for _, other in Players:GetPlayers() do
			if other ~= player then
				eventRemote:FireClient(other, "Notice", text)
			end
		end
	end
end

-- The finish button (RouteKit.addFinishButton) was clicked: top out if this player is on
-- a run of that route and close enough to have reached it.
local function onFinishClicked(button: BasePart, player: Player)
	local route: Instance? = button.Parent
	while route and route:GetAttribute("RouteName") == nil do
		route = route.Parent
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if route == nil or character == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	if (root.Position - button.Position).Magnitude > FINISH_REACH then
		return
	end
	RopeService.gesture(character, "Press")
	local run = runs[player]
	if run and run.route == route then
		task.delay(0.35, function()
			if runs[player] == run then
				summit(player, run)
			end
		end)
	elseif run == nil then
		eventRemote:FireClient(player, "Notice", "Start from the bottom to time a run")
	end
end

local function tick(dt: number)
	for player, run in runs do
		local character = run.character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if player.Character ~= character or humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
			RouteService.Fail(player, "You fell")
			continue
		end
		if character:GetAttribute("RopeCatch") == true then
			RouteService.Fail(player, "Caught by the rope")
			continue
		end
		if character:GetAttribute("Ragdolled") == true then
			RouteService.Fail(player, "You fell")
			continue
		end

		-- Back on the ground at the base (ledges up the wall don't count).
		if character:GetAttribute("Climbing") ~= true then
			rayParams.FilterDescendantsInstances = { character }
			local reach = LimbRig.standingHeight(humanoid, root) + 1.2
			local hit = Workspace:Raycast(root.Position, Vector3.yAxis * -reach, rayParams)
			if hit and hit.Position.Y < numberAttr(run.route, "BaseY", 0) + 4 then
				run.groundFor += dt
				if run.groundFor >= ROUTES.FailGroundSeconds then
					RouteService.Fail(player, "Back on the ground")
				end
			else
				run.groundFor = 0
			end
		else
			run.groundFor = 0
		end
	end
end

-- Puts a player at the base of `route`.
function RouteService.TeleportTo(player: Player, route: Instance): boolean
	local character = player.Character
	local position = route:GetAttribute("StartPosition")
	if character == nil or typeof(position) ~= "Vector3" then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") == true then
		return false
	end
	if runs[player] then
		endRun(player)
	end
	ClimbService.ForceOff(player, "Teleport")
	RopeService.Untie(player)
	local summitPart = route:FindFirstChild("Summit")
	local look = if summitPart and summitPart:IsA("BasePart") then Vector3.new(summitPart.Position.X, position.Y, summitPart.Position.Z) else position + Vector3.zAxis
	character:PivotTo(CFrame.lookAt(position, look))
	lastRoute[player] = route
	return true
end

local function onRequest(player: Player, action: any, routeId: any)
	-- Teleports (Retry, Travel) have a cooldown; the rest are cheap.
	local now = os.clock()
	if action == "Retry" or action == "Travel" then
		if now - (lastRequest[player] or 0) < ROUTES.RetryCooldown then
			return
		end
		lastRequest[player] = now
	end
	local routes = routesFolder()
	if routes == nil then
		return
	end
	if action == "Untie" then
		RopeService.Untie(player)
	elseif action == "Lower" then
		RopeService.Lower(player)
	elseif action == "RopeFeed" then
		RopeService.Feed(player, if type(routeId) == "number" then routeId else 0)
	elseif action == "Chalk" then
		ChalkService.FromBag(player)
	elseif action == "Retry" then
		local route = lastRoute[player]
		if route and route.Parent == routes then
			RouteService.TeleportTo(player, route)
		end
	elseif action == "Travel" and type(routeId) == "string" then
		local route = routes:FindFirstChild(routeId)
		if route and route:GetAttribute("RouteName") ~= nil then
			RouteService.TeleportTo(player, route)
		end
	end
end

function RouteService.GetRun(player: Player): Instance?
	local run = runs[player]
	return if run then run.route else nil
end

function RouteService.Init()
	eventRemote = Remotes.event("RouteEvent")
	Remotes.event("RouteRequest").OnServerEvent:Connect(function(player, action, routeId)
		onRequest(player, action, routeId)
	end)
end

function RouteService.Start()
	ClimbService.OnPlaced(onPlaced)
	local function watch(instance: Instance)
		if instance:IsA("ClickDetector") and instance.Name == "Finish" then
			local button = instance.Parent
			if button and button:IsA("BasePart") then
				instance.MouseClick:Connect(function(player)
					onFinishClicked(button, player)
				end)
			end
		end
	end
	local routes = routesFolder()
	if routes then
		for _, d in routes:GetDescendants() do
			watch(d)
		end
		routes.DescendantAdded:Connect(watch)
	end
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
		lastRoute[player] = nil
		lastRequest[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= ROUTES.ProgressTick then
			tick(elapsed)
			elapsed = 0
		end
	end)
end

return RouteService
