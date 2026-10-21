--!strict
-- ClimbService (server): authority over which limb holds which hold.
--
--  * Stores the state as character attributes: "Climb_LeftHand" = HoldId (absent = free),
--    plus "Climbing" = true while any limb is on a hold. Every client reads these and
--    poses that character's arms and legs onto the holds (LimbRig), so everyone sees
--    everyone climbing. Works for R6 and R15.
--  * Validates every request from the client (rate limit, argument types, hold exists,
--    right limb type, within reach of the HumanoidRootPart) and tells the client when it
--    refuses one.
--  * Watchdog: a body that stays impossibly far from its holds is taken off the wall.
--  * Tells other services when someone leaves the wall and why (OnLeftWall: "Release",
--    "LetGo", "Dyno", "Exhausted", "Watchdog", "HoldGone", "Died", "Teleport"), when a limb
--    goes on a hold (OnPlaced), and lets them force a climber off (ForceOff, e.g.
--    StaminaService when grip runs out).
--
-- The body itself is moved by the owning client (it owns its character's physics);
-- the server only checks that it stays plausible.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClimbMath = require(Shared.ClimbMath)
local Config = require(Shared.Config)
local HoldUtil = require(Shared.HoldUtil)
local LimbRig = require(Shared.LimbRig)
local RateLimiter = require(Shared.RateLimiter)
local Remotes = require(Shared.Remotes)

local HoldService = require(script.Parent.HoldService)

local CLIMB = Config.Climb
local DYNO = CLIMB.Dyno
local ATTRIBUTE_PREFIX = "Climb_"
local WATCHDOG_INTERVAL = 0.25

local ClimbService = {}

type Rig = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	farFor: number, -- seconds the body has been implausibly far from its holds
	dynoUntil: number, -- os.clock() until which a dyno catch gets extra reach tolerance
}

local rigs: { [Player]: Rig } = {}
local limiter = RateLimiter.new(CLIMB.RequestsPerSecond, CLIMB.RequestBurst)
local rejectedEvent: RemoteEvent
local leftWallListeners: { (Player, string) -> () } = {}
local dynoListeners: { (Player) -> () } = {}
local placedListeners: { (Player, string, BasePart) -> () } = {}
local placeGuards: { (Player, BasePart) -> string? } = {}

function ClimbService.attributeName(limb: string): string
	return ATTRIBUTE_PREFIX .. limb
end

local function heldHolds(rig: Rig): { [string]: BasePart }
	local held = {}
	for _, limb in Config.LimbOrder do
		local id = rig.character:GetAttribute(ClimbService.attributeName(limb))
		local hold = if type(id) == "string" then HoldService.GetHold(id) else nil
		if hold then
			held[limb] = hold
		end
	end
	return held
end

local function setLimb(rig: Rig, limb: string, hold: BasePart?, reason: string?)
	local wasClimbing = rig.character:GetAttribute("Climbing") == true
	rig.character:SetAttribute(ClimbService.attributeName(limb), if hold then hold:GetAttribute("HoldId") else nil)
	local climbing = next(heldHolds(rig)) ~= nil
	rig.character:SetAttribute("Climbing", climbing)
	if wasClimbing and not climbing then
		for _, listener in leftWallListeners do
			task.spawn(listener, rig.player, reason or "Release")
		end
	end
	if hold then
		for _, listener in placedListeners do
			task.spawn(listener, rig.player, limb, hold)
		end
	end
end

local function releaseAll(rig: Rig, reason: string)
	for _, limb in Config.LimbOrder do
		setLimb(rig, limb, nil, reason)
	end
	rig.farFor = 0
end

-- `listener(player, reason)` runs whenever a climber stops holding anything.
function ClimbService.OnLeftWall(listener: (Player, string) -> ())
	table.insert(leftWallListeners, listener)
end

-- `listener(player, limb, hold)` runs every time the server puts a limb on a hold.
function ClimbService.OnPlaced(listener: (Player, string, BasePart) -> ())
	table.insert(placedListeners, listener)
end

-- `guard(player, hold)` can refuse a grab by returning a reason (RopeService: "clip in
-- first"). Every guard must allow it.
function ClimbService.AddPlaceGuard(guard: (Player, BasePart) -> string?)
	table.insert(placeGuards, guard)
end

-- `listener(player)` runs when a climber launches a dyno.
function ClimbService.OnDyno(listener: (Player) -> ())
	table.insert(dynoListeners, listener)
end

export type PlaceCheck = { ok: boolean, reason: string?, hold: BasePart? }

-- The reach rule, shared by the remote handler and the Diagnostics.
-- `extraTolerance` widens reach (used right after a dyno, when the server's view lags).
function ClimbService.CheckPlace(rootPosition: Vector3, limb: any, holdId: any, extraTolerance: number?): PlaceCheck
	local def = if type(limb) == "string" then Config.Limbs[limb] else nil
	if def == nil then
		return { ok = false, reason = "unknown limb" }
	end
	if type(holdId) ~= "string" then
		return { ok = false, reason = "bad hold id" }
	end
	local hold = HoldService.GetHold(holdId)
	local info = hold and HoldService.GetHoldInfo(hold)
	if hold == nil or info == nil then
		return { ok = false, reason = "no such hold" }
	end
	if not HoldUtil.accepts(info, def.Kind) then
		return { ok = false, reason = if def.Kind == "Hand" then "feet only" else "hands only" }
	end
	if not ClimbMath.inReach(rootPosition, HoldUtil.getGripCFrame(hold).Position, def.Reach, CLIMB.ReachTolerance + (extraTolerance or 0)) then
		return { ok = false, reason = "out of reach" }
	end
	return { ok = true, hold = hold }
end

-- The rig for the player's current character, made on first use. Never waits, and doesn't
-- care whether the character is in Workspace yet: Roblox fires CharacterAdded before
-- parenting the character, which is what silently broke climbing in v0.2/v0.3.
local function rigFor(player: Player): Rig?
	local character = player.Character
	if character == nil then
		return nil
	end
	local existing = rigs[player]
	if existing and existing.character == character then
		return existing
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	if PhysicsService:IsCollisionGroupRegistered(CLIMB.LimbCollisionGroup) then
		for _, name in LimbRig.LIMB_PART_NAMES do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.CollisionGroup = CLIMB.LimbCollisionGroup
			end
		end
	end
	local rig: Rig = { player = player, character = character, humanoid = humanoid, root = root, farFor = 0, dynoUntil = 0 }
	rigs[player] = rig
	humanoid.Died:Connect(function()
		if rigs[player] == rig then
			releaseAll(rig, "Died")
		end
	end)
	return rig
end

-- Takes a climber off the wall (every limb lets go) for `reason`.
function ClimbService.ForceOff(player: Player, reason: string)
	local rig = rigFor(player)
	if rig then
		releaseAll(rig, reason)
	end
end

local function onRequest(player: Player, action: any, limb: any, holdId: any)
	if not limiter:allow(player) then
		return
	end
	if type(action) ~= "string" then
		return
	end
	local rig = rigFor(player)
	if rig == nil or rig.humanoid.Health <= 0 then
		-- Always answer, so the client never waits on a request that went nowhere.
		rejectedEvent:FireClient(player, if type(limb) == "string" then limb else "", "your character isn't ready")
		return
	end

	if action == "Place" then
		if rig.character:GetAttribute("Ragdolled") == true then
			rejectedEvent:FireClient(player, if type(limb) == "string" then limb else "", "you're down")
			return
		end
		local extra = if os.clock() < rig.dynoUntil then DYNO.ServerExtraTolerance else 0
		local result = ClimbService.CheckPlace(rig.root.Position, limb, holdId, extra)
		if result.ok and result.hold then
			for _, guard in placeGuards do
				local refused = guard(player, result.hold)
				if refused then
					result = { ok = false, reason = refused }
					break
				end
			end
		end
		if result.ok then
			setLimb(rig, limb :: string, result.hold)
		else
			rejectedEvent:FireClient(player, if type(limb) == "string" then limb else "", result.reason)
		end
	elseif action == "Release" then
		if type(limb) == "string" and Config.Limbs[limb] then
			setLimb(rig, limb, nil, "Release")
		end
	elseif action == "LetGo" then
		releaseAll(rig, "LetGo")
	elseif action == "Dyno" then
		if rig.character:GetAttribute("Climbing") == true then
			for _, listener in dynoListeners do
				task.spawn(listener, player)
			end
		end
		releaseAll(rig, "Dyno")
		rig.dynoUntil = os.clock() + DYNO.ServerGrace
	end
end

local function onCharacter(player: Player, character: Model)
	-- Set the rig up as soon as the body parts exist (requests also make it on demand).
	character:WaitForChild("Humanoid", 10)
	character:WaitForChild("HumanoidRootPart", 10)
	if player.Character == character then
		rigFor(player)
	end
end

-- Takes players off the wall if their body is implausibly far from what they hold
-- (teleport exploits, physics glitches), or if a hold they were on disappears.
local function watchdog(dt: number)
	for player, rig in rigs do
		if player.Character ~= rig.character or player.Parent == nil then
			rigs[player] = nil -- respawned or left
			continue
		end
		local far = false
		for _, limb in Config.LimbOrder do
			local id = rig.character:GetAttribute(ClimbService.attributeName(limb))
			if type(id) ~= "string" then
				continue
			end
			local hold = HoldService.GetHold(id)
			if hold == nil then
				setLimb(rig, limb, nil, "HoldGone")
				continue
			end
			local reach = Config.Limbs[limb].Reach + CLIMB.WatchdogExtra
			if not ClimbMath.inReach(rig.root.Position, HoldUtil.getGripCFrame(hold).Position, reach) then
				far = true
			end
		end
		rig.farFor = if far then rig.farFor + dt else 0
		if rig.farFor >= CLIMB.WatchdogSeconds then
			warn(`[ClimbService] {player.Name} was too far from their holds; taken off the wall`)
			releaseAll(rig, "Watchdog")
		end
	end
end

function ClimbService.Init()
	-- Arms and legs pass through the world, so IK can put hands and feet on holds without
	-- the wall pushing the body around. The torso and head still collide.
	local ok, err = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(CLIMB.LimbCollisionGroup) then
			PhysicsService:RegisterCollisionGroup(CLIMB.LimbCollisionGroup)
		end
		PhysicsService:CollisionGroupSetCollidable(CLIMB.LimbCollisionGroup, "Default", false)
	end)
	if not ok then
		warn(`[ClimbService] couldn't set up the limb collision group (climbing still works): {err}`)
	end
	rejectedEvent = Remotes.event("ClimbRejected")
	Remotes.event("ClimbRequest").OnServerEvent:Connect(onRequest)
end

function ClimbService.Start()
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		rigs[player] = nil
		limiter:forget(player)
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= WATCHDOG_INTERVAL then
			watchdog(elapsed)
			elapsed = 0
		end
	end)
end

return ClimbService
