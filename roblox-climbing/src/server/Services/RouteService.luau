--!strict
-- RouteService (server): timed runs on routes, summits, rewards.
--
--  * A run starts when you put a limb on one of a route's holds near its base (within
--    Config.Routes.StartBand of BaseY). The player gets "RunRoute" (route id) and
--    "RunStart" (Workspace:GetServerTimeNow()) attributes, which the HUD's timer and
--    progress bar read.
--  * You top out by reaching the Summit volume, or by holding a Finish hold with a hand.
--    The server times the run, checks it is plausible, pays gems and XP (DataService),
--    records the time (LeaderboardService) and sends the client a summit card.
--  * The run fails if you die, fall onto the rope, or are back on the ground at the base.
--  * After an outdoor summit a free soloist tops out onto the summit; roped climbers let go
--    to be lowered.
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
local HoldService = require(script.Parent.HoldService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local RopeService = require(script.Parent.RopeService)

local ROUTES = Config.Routes
local FINISH_HOLD_SECONDS = 0.6

type Run = {
	route: Instance,
	character: Model,
	started: number, -- os.clock()
	holds: { [string]: boolean }, -- distinct holds used, a sanity check
	groundFor: number,
	finishFor: number,
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
		finishFor = 0,
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

-- Climbs a free soloist over the top onto the summit, behind the Summit volume.
local function topOut(player: Player, route: Instance)
	local character = player.Character
	local summitPart = route:FindFirstChild("Summit")
	if character == nil or summitPart == nil or not summitPart:IsA("BasePart") then
		return
	end
	local inland = -summitPart.CFrame.LookVector
	local position = summitPart.Position + inland * 5 + Vector3.yAxis
	ClimbService.ForceOff(player, "Teleport")
	character:PivotTo(CFrame.lookAt(position, position - inland))
end

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

	-- Topping out: free soloists climb over onto the summit; roped climbers let go to be
	-- lowered; boulderers drop onto the mats.
	local character = player.Character
	if character and route:GetAttribute("Indoor") ~= true then
		if character:GetAttribute("TiedIn") == nil then
			task.delay(0.5, topOut, player, route)
		else
			eventRemote:FireClient(player, "Notice", "Press R (or let go) and your belayer lowers you down")
		end
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

-- Is `point` inside `part` (an axis-aligned box in the part's own frame)?
local function inside(part: BasePart, point: Vector3): boolean
	local relative = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

local function holdingFinish(character: Model): boolean
	for _, limb in { "LeftHand", "RightHand" } do
		local id = character:GetAttribute("Climb_" .. limb)
		local hold = if type(id) == "string" then HoldService.GetHold(id) else nil
		if hold and hold:GetAttribute("Role") == "Finish" then
			return true
		end
	end
	return false
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

		local summitPart = run.route:FindFirstChild("Summit")
		if summitPart and summitPart:IsA("BasePart") and inside(summitPart, root.Position) then
			summit(player, run)
			continue
		end
		if character:GetAttribute("Climbing") == true and holdingFinish(character) then
			run.finishFor += dt
			if run.finishFor >= FINISH_HOLD_SECONDS then
				summit(player, run)
				continue
			end
		else
			run.finishFor = 0
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
	local now = os.clock()
	if now - (lastRequest[player] or 0) < ROUTES.RetryCooldown then
		return
	end
	lastRequest[player] = now
	local routes = routesFolder()
	if routes == nil then
		return
	end
	if action == "Untie" then
		RopeService.Untie(player)
	elseif action == "Lower" then
		RopeService.Lower(player)
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
