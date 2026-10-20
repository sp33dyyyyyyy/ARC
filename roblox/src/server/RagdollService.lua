-- Server half of the ragdoll: swaps Motor6Ds for BallSocketConstraints so every
-- client sees the floppy body, and applies fall damage when the player gets up.
-- The owning client puts its Humanoid into the Physics state (it owns the
-- character's physics).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local RagdollService = {}

type RagdollState = {
	character: Model,
	startY: number,
	startedAt: number,
	motors: { Motor6D },
	created: { Instance },
	collisions: { [BasePart]: boolean },
}

local states: { [Player]: RagdollState } = {}
local ROOT_JOINTS = { Root = true, RootJoint = true }

local function enableRagdoll(character: Model): ({ Motor6D }, { Instance }, { [BasePart]: boolean })
	local motors, created, collisions = {}, {}, {}
	for _, motor in character:GetDescendants() do
		if motor:IsA("Motor6D") and not ROOT_JOINTS[motor.Name] and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 70
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -50
			socket.TwistUpperAngle = 50
			socket.Parent = motor.Part0
			motor.Enabled = false
			table.insert(motors, motor)
			table.insert(created, a0)
			table.insert(created, a1)
			table.insert(created, socket)
		end
	end
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			collisions[part] = part.CanCollide
			part.CanCollide = true
		end
	end
	return motors, created, collisions
end

local function disableRagdoll(state: RagdollState)
	for _, motor in state.motors do
		if motor.Parent then
			motor.Enabled = true
		end
	end
	for _, inst in state.created do
		inst:Destroy()
	end
	for part, canCollide in state.collisions do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
end

local function rootOf(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function RagdollService.set(player: Player, ragdolled: boolean, claimedStartY: number?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and rootOf(character)
	if not character or not humanoid or not root then
		return
	end
	local state = states[player]

	if ragdolled and not state then
		if humanoid.Health <= 0 then
			return
		end
		-- Trust the client's fall start only within sane bounds (it can only lie
		-- in its own disfavour by more than this).
		local y = root.Position.Y
		local startY = if typeof(claimedStartY) == "number" and claimedStartY == claimedStartY
			then math.clamp(claimedStartY, y, y + 1500)
			else y
		local motors, created, collisions = enableRagdoll(character)
		states[player] = {
			character = character,
			startY = startY,
			startedAt = os.clock(),
			motors = motors,
			created = created,
			collisions = collisions,
		}
	elseif not ragdolled and state then
		states[player] = nil
		if state.character ~= character then
			return
		end
		disableRagdoll(state)
		local data = DataService.get(player)
		local damage = if data
			then Rules.fallDamage(Config.Fall, Config.Boosts, DataService.effectiveBoosts(player), state.startY - root.Position.Y, Config.GamePasses)
			else 0
		if damage > 0 and humanoid.Health > 0 then
			humanoid:TakeDamage(damage)
			Remotes.get("Notify"):FireClient(player, "Hurt", { damage = math.floor(damage) })
		end
	end
end

-- After a teleport (e.g. to the plaza mid-fall) measure any fall damage from
-- the new spot, not from where the ragdoll started.
function RagdollService.resetFall(player: Player, y: number)
	local state = states[player]
	if state then
		state.startY = y
	end
end

function RagdollService.start()
	local lastCall: { [Player]: number } = {}
	Remotes.get("Ragdoll").OnServerEvent:Connect(function(player, ragdolled, startY)
		if typeof(ragdolled) ~= "boolean" then
			return
		end
		local now = os.clock()
		if ragdolled and now - (lastCall[player] or 0) < 0.25 then
			return
		end
		lastCall[player] = now
		RagdollService.set(player, ragdolled, if typeof(startY) == "number" then startY else nil)
	end)

	local function onCharacter(player: Player, character: Model)
		states[player] = nil -- old body is gone; nothing to restore
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			-- Ragdoll Engine-style limp death instead of falling apart.
			if not states[player] and character.Parent then
				enableRagdoll(character)
			end
		end)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		lastCall[player] = nil
	end)

	-- Failsafe: a client that never sends "get up" still gets its joints back.
	task.spawn(function()
		while true do
			task.wait(1)
			for player, state in states do
				if os.clock() - state.startedAt > Config.Fall.MaxRagdollTime + 5 then
					RagdollService.set(player, false)
				end
			end
		end
	end)
end

return RagdollService
