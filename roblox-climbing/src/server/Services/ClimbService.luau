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
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	farFor: number, -- seconds the body has been implausibly far from its holds
	dynoUntil: number, -- os.clock() until which a dyno catch gets extra reach tolerance
}

local rigs: { [Player]: Rig } = {}
local limiter = RateLimiter.new(CLIMB.RequestsPerSecond, CLIMB.RequestBurst)
local rejectedEvent: RemoteEvent

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

local function setLimb(rig: Rig, limb: string, hold: BasePart?)
	rig.character:SetAttribute(ClimbService.attributeName(limb), if hold then hold:GetAttribute("HoldId") else nil)
	rig.character:SetAttribute("Climbing", next(heldHolds(rig)) ~= nil)
end

local function releaseAll(rig: Rig)
	for _, limb in Config.LimbOrder do
		setLimb(rig, limb, nil)
	end
	rig.farFor = 0
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

local function onRequest(player: Player, action: any, limb: any, holdId: any)
	if not limiter:allow(player) then
		return
	end
	local rig = rigs[player]
	if rig == nil or rig.humanoid.Health <= 0 or type(action) ~= "string" then
		return
	end

	if action == "Place" then
		local extra = if os.clock() < rig.dynoUntil then DYNO.ServerExtraTolerance else 0
		local result = ClimbService.CheckPlace(rig.root.Position, limb, holdId, extra)
		if result.ok then
			setLimb(rig, limb :: string, result.hold)
		else
			rejectedEvent:FireClient(player, if type(limb) == "string" then limb else "", result.reason)
		end
	elseif action == "Release" then
		if type(limb) == "string" and Config.Limbs[limb] then
			setLimb(rig, limb, nil)
		end
	elseif action == "LetGo" then
		releaseAll(rig)
	elseif action == "Dyno" then
		releaseAll(rig)
		rig.dynoUntil = os.clock() + DYNO.ServerGrace
	end
end

local function onCharacter(player: Player, character: Model)
	rigs[player] = nil
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if humanoid == nil or root == nil or character.Parent == nil then
		return
	end
	if PhysicsService:IsCollisionGroupRegistered(CLIMB.LimbCollisionGroup) then
		for _, name in LimbRig.LIMB_PART_NAMES do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.CollisionGroup = CLIMB.LimbCollisionGroup
			end
		end
	end
	local rig: Rig = { character = character, humanoid = humanoid, root = root, farFor = 0, dynoUntil = 0 }
	rigs[player] = rig
	humanoid.Died:Connect(function()
		if rigs[player] == rig then
			releaseAll(rig)
		end
	end)
end

-- Takes players off the wall if their body is implausibly far from what they hold
-- (teleport exploits, physics glitches), or if a hold they were on disappears.
local function watchdog(dt: number)
	for player, rig in rigs do
		if rig.character.Parent == nil then
			rigs[player] = nil
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
				setLimb(rig, limb, nil)
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
			releaseAll(rig)
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
