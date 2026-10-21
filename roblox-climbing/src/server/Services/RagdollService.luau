--!strict
-- RagdollService (server): falling off, getting knocked down, and dying.
--
--  * Leaving the wall high up (letting go, running out of stamina, a missed dyno) turns
--    the climber into a limp ragdoll (Physics/Ragdoll).
--  * Every fall is measured from its highest point to where the climber lands:
--      below Config.Falls.SafeHeight    nothing happens
--      up to LethalHeight               knocked down, back up after KnockdownSeconds
--      LethalHeight and more            dead (the ragdoll crumples), respawn
--    Landing on a crash mat raises the lethal height by CrashMatFactor.
--  * Climbers tied in to a rope ("TiedIn" attribute, RopeService) are caught instead.
--  * Publishes "FellReason" ("Exhausted", "MissedDyno", "LetGo") and "LastFall" (metres)
--    on the character, and "FallDeath" (metres) when a fall kills, for the client's messages.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LimbRig = require(Shared.LimbRig)
local Tags = require(Shared.Tags)

local ClimbService = require(script.Parent.ClimbService)
local Ragdoll = require(script.Parent.Parent.Physics.Ragdoll)

local FALLS = Config.Falls
local TICK = 0.05

local RagdollService = {}

type State = {
	character: Model,
	airborne: boolean,
	peakY: number?, -- highest root height since leaving the ground or wall
	dynoUntil: number?, -- a dyno is in the air until then
	getUpAt: number?, -- when a knocked-down climber stands back up
}

local states: { [Player]: State } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function stateFor(player: Player): State?
	local character = player.Character
	if character == nil then
		return nil
	end
	local state = states[player]
	if state == nil or state.character ~= character then
		state = { character = character, airborne = false, peakY = nil, dynoUntil = nil, getUpAt = nil }
		states[player] = state
	end
	return state
end

local function parts(character: Model): (Humanoid?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid, if root and root:IsA("BasePart") then root else nil
end

-- The floor under the character, if it's within `distance` of the root part.
local function groundBelow(character: Model, root: BasePart, distance: number): RaycastResult?
	rayParams.FilterDescendantsInstances = { character }
	return Workspace:Raycast(root.Position, Vector3.yAxis * -distance, rayParams)
end

local function heightAboveGround(character: Model, humanoid: Humanoid, root: BasePart): number
	local hit = groundBelow(character, root, 500)
	if hit == nil then
		return math.huge
	end
	return root.Position.Y - LimbRig.standingHeight(humanoid, root) - hit.Position.Y
end

local function isCrashMat(instance: Instance): boolean
	local current: Instance? = instance
	while current and current ~= Workspace do
		if CollectionService:HasTag(current, Tags.CrashMat) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function goLimp(character: Model, reason: string?)
	if reason then
		character:SetAttribute("FellReason", reason)
	end
	Ragdoll.enable(character)
end

local function onLeftWall(player: Player, reason: string)
	local state = stateFor(player)
	if state == nil or reason == "Died" or reason == "Teleport" or reason == "Mantle" then
		return
	end
	local character = state.character
	local humanoid, root = parts(character)
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return
	end
	if reason == "Dyno" then
		state.dynoUntil = os.clock() + FALLS.DynoGrace
		return
	end
	if character:GetAttribute("TiedIn") ~= nil then
		return -- the rope catches you (RopeService)
	end
	if reason == "Exhausted" then
		goLimp(character, "Exhausted")
	elseif heightAboveGround(character, humanoid, root) > FALLS.RagdollOnLetGoAbove then
		goLimp(character, "LetGo")
	end
end

local function kill(character: Model, humanoid: Humanoid, fallStuds: number)
	character:SetAttribute("FallDeath", math.floor(Config.studsToMeters(fallStuds) * 10 + 0.5) / 10)
	goLimp(character, nil)
	humanoid.Health = 0
end

local function land(state: State, humanoid: Humanoid, root: BasePart, ground: RaycastResult)
	local character = state.character
	local peak = state.peakY or root.Position.Y
	-- Height of the feet at the top of the fall above where they landed.
	local fall = peak - LimbRig.standingHeight(humanoid, root) - ground.Position.Y
	character:SetAttribute("LastFall", math.floor(Config.studsToMeters(math.max(0, fall)) * 10 + 0.5) / 10)
	-- Helmets (ShopService's GearFallBonus) let you survive a bit higher.
	local player = Players:GetPlayerFromCharacter(character)
	local helmet = if player then player:GetAttribute("GearFallBonus") else nil
	local lethal = FALLS.LethalHeight * (if isCrashMat(ground.Instance) then FALLS.CrashMatFactor else 1) * (if type(helmet) == "number" then helmet else 1)
	if fall >= lethal then
		kill(character, humanoid, fall)
	elseif fall >= FALLS.SafeHeight or Ragdoll.isRagdolled(character) then
		goLimp(character, nil)
		state.getUpAt = os.clock() + FALLS.KnockdownSeconds
	end
end

local function tick()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local state = stateFor(player)
		if state == nil then
			continue
		end
		local character = state.character
		local humanoid, root = parts(character)
		if humanoid == nil or root == nil or humanoid.Health <= 0 or character.Parent == nil then
			continue
		end

		-- On the wall, or tied in (the rope catches and lowers you): no fall to measure.
		if character:GetAttribute("Climbing") == true or (character:GetAttribute("TiedIn") ~= nil and not Ragdoll.isRagdolled(character)) then
			state.airborne = false
			state.peakY = nil
			state.dynoUntil = nil
			continue
		end

		local ragdolled = Ragdoll.isRagdolled(character)
		local reach = if ragdolled then 3 else LimbRig.standingHeight(humanoid, root) + 1.2
		local ground = groundBelow(character, root, reach)

		if state.dynoUntil and now > state.dynoUntil then
			state.dynoUntil = nil
			if ground == nil and not ragdolled then
				goLimp(character, "MissedDyno")
				ragdolled = true
			end
		end

		if ground == nil then
			state.airborne = true
			state.peakY = math.max(state.peakY or root.Position.Y, root.Position.Y)
		elseif state.airborne then
			state.airborne = false
			land(state, humanoid, root, ground)
			state.peakY = nil
		elseif ragdolled then
			if state.getUpAt == nil then
				state.getUpAt = now + FALLS.KnockdownSeconds
			elseif now >= state.getUpAt and root.AssemblyLinearVelocity.Magnitude < 4 then
				state.getUpAt = nil
				Ragdoll.disable(character)
				character:SetAttribute("FellReason", nil)
			end
		end
	end
end

local function prepareCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		-- Keep the body in one piece when it dies (the ragdoll is the death animation), and
		-- don't kill a ragdoll just because its neck joint is swapped for a ball socket.
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
end

function RagdollService.Start()
	Players.RespawnTime = FALLS.RespawnSeconds
	ClimbService.OnLeftWall(onLeftWall)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(prepareCharacter)
		if player.Character then
			task.spawn(prepareCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= TICK then
			elapsed = 0
			tick()
		end
	end)
end

return RagdollService
