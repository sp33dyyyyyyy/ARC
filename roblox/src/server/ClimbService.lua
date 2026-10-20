-- Climb tracking: base/peak zones, payouts, checkpoints, trails.
--
-- A climb starts when you touch a tower's BaseZone and pays out once when you
-- reach its PeakZone. The peak only pays if the climb started on the same
-- tower and took a physically plausible amount of time.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local RopeService = require(script.Parent.RopeService)
local RagdollService = require(script.Parent.RagdollService)

local ClimbService = {}

type Checkpoint = { tower: string, position: Vector3, normal: Vector3 }

local active: { [Player]: Rules.ActiveClimb } = {}
-- Last sampled height per climber, to catch teleporting up a tower.
local climbTrack: { [Player]: { y: number, t: number } } = {}
local checkpoints: { [Player]: Checkpoint } = {}
local lastRejectNotice: { [Player]: number } = {}
local plazaSpawn: CFrame = CFrame.new(0, 4, 24)

local notify: RemoteEvent
local towersById: { [string]: Model } = {}

local function playerFromHit(hit: BasePart): (Player?, Humanoid?)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil, nil
	end
	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return player, humanoid
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function ClimbService.toast(player: Player, text: string, style: string?)
	notify:FireClient(player, "Toast", { text = text, style = style or "info" })
end

function ClimbService.sendToPlaza(player: Player)
	checkpoints[player] = nil
	RopeService.unclip(player)
	local character = player.Character
	if character then
		local offset = Vector3.new(math.random(-6, 6), 0, math.random(-4, 4))
		character:PivotTo(plazaSpawn + offset)
		RagdollService.resetFall(player, (plazaSpawn + offset).Position.Y)
	end
	climbTrack[player] = nil
end

function ClimbService.equipTrail(player: Player)
	local character = player.Character
	local root = rootOf(player)
	local data = DataService.get(player)
	if not character or not root or not data then
		return
	end
	local best = Rules.bestTrail(Config.Trails, data.Climbs)
	local existing = root:FindFirstChild("ClimbTrail") :: Trail?
	if existing and best and existing:GetAttribute("TrailName") == best.Name then
		return
	end
	if existing then
		existing:Destroy()
	end
	for _, name in { "TrailTop", "TrailBottom" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	if not best then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "ClimbTrail"
	trail:SetAttribute("TrailName", best.Name)
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	local c = Color3.fromRGB(best.Color[1], best.Color[2], best.Color[3])
	trail.Color = ColorSequence.new(c)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = root
end

local function onPeak(tower: Model, player: Player)
	local id = tower:GetAttribute("TowerId") :: string
	local height = tower:GetAttribute("Height") :: number
	local ok, reason = Rules.validatePeak(Config.Climb, active[player], id, height, os.clock())
	if not ok then
		local now = os.clock()
		if now - (lastRejectNotice[player] or 0) > 6 then
			lastRejectNotice[player] = now
			ClimbService.toast(player, reason :: string, "bad")
		end
		return
	end
	local climb = active[player] :: Rules.ActiveClimb
	climb.paid = true
	checkpoints[player] = nil

	local payout = Rules.payout(tower:GetAttribute("Payout") :: number, Config.GamePasses, DataService.effectiveBoosts(player))
	local before = (DataService.get(player) or {}).Climbs or 0
	DataService.update(player, function(data)
		data.Cash += payout
		data.Climbs += 1
	end)
	local data = DataService.get(player)
	if not data then
		return
	end
	notify:FireClient(player, "Summit", { tower = id, payout = payout, climbs = data.Climbs })

	local oldTrail = Rules.bestTrail(Config.Trails, before)
	local newTrail = Rules.bestTrail(Config.Trails, data.Climbs)
	if newTrail and newTrail ~= oldTrail then
		notify:FireClient(player, "Unlock", { text = newTrail.Name .. " trail unlocked!" })
		ClimbService.equipTrail(player)
	end
end

local function restLevels(tower: Model): { number }
	local levels = {}
	for value in string.gmatch(tostring(tower:GetAttribute("RestLevels") or ""), "[^,]+") do
		table.insert(levels, tonumber(value) :: number)
	end
	return levels
end

-- The client says it's hanging on a rest bar; check that's plausible and save
-- a checkpoint there (you respawn hanging on the wall at that spot).
local function onRestCheckpoint(player: Player, normal: any)
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 0.5 or normal.Magnitude > 1.5 then
		return
	end
	local climb = active[player]
	local root = rootOf(player)
	if not climb or climb.paid or not root then
		return
	end
	local tower = towersById[climb.tower]
	if not tower then
		return
	end
	local pivot = tower.WorldPivot.Position
	local radius = tower:GetAttribute("Radius") or 0
	local pos = root.Position
	if math.abs(pos.X - pivot.X) > radius or math.abs(pos.Z - pivot.Z) > radius then
		return
	end
	local handY = pos.Y + 2.5
	local nearBar = false
	for _, y in restLevels(tower) do
		if math.abs(handY - y) <= Config.Climb.RestBarReach + 1 then
			nearBar = true
		end
	end
	if not nearBar then
		return
	end
	local cp = checkpoints[player]
	if cp and cp.tower == climb.tower and pos.Y <= cp.position.Y + 4 then
		return
	end
	local flat = Vector3.new(normal.X, 0, normal.Z)
	checkpoints[player] = {
		tower = climb.tower,
		position = pos,
		normal = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis,
	}
	ClimbService.toast(player, "Checkpoint saved", "good")
end

local function hookTower(tower: Model)
	local id = tower:GetAttribute("TowerId") :: string
	towersById[id] = tower
	local base = tower:FindFirstChild("BaseZone") :: BasePart
	local peak = tower:FindFirstChild("PeakZone") :: BasePart

	base.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if not player then
			return
		end
		local climb = active[player]
		-- Re-arm when starting fresh, switching tower, or after being paid.
		-- Still at the bottom of the current climb: the timer runs from the last
		-- base touch, which keeps the "too fast" check strict.
		if climb and climb.tower == id and not climb.paid then
			climb.startTime = os.clock()
			return
		end
		active[player] = { tower = id, startTime = os.clock(), paid = false }
		local cp = checkpoints[player]
		if cp and cp.tower ~= id then
			checkpoints[player] = nil
		end
	end)

	peak.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player then
			onPeak(tower, player)
		end
	end)

end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.BreakJointsOnDeath = false -- we ragdoll on death instead
	humanoid.RequiresNeck = false
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then
		return
	end
	task.defer(ClimbService.equipTrail, player)

	local cp = checkpoints[player]
	if cp then
		task.wait(0.1)
		if character.Parent then
			-- Back on the wall, facing it; the client grabs on straight away.
			character:PivotTo(CFrame.lookAt(cp.position, cp.position - cp.normal))
			climbTrack[player] = nil -- a checkpoint respawn isn't a teleport cheat
			notify:FireClient(player, "Regrip", {})
			ClimbService.toast(player, "Respawned at your last checkpoint", "info")
		end
	end
end

function ClimbService.start(towers: Folder, spawnCFrame: CFrame)
	plazaSpawn = spawnCFrame
	notify = Remotes.get("Notify")
	for _, tower in towers:GetChildren() do
		if tower:IsA("Model") and tower:GetAttribute("TowerId") then
			hookTower(tower)
		end
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
		active[player] = nil
		checkpoints[player] = nil
		climbTrack[player] = nil
		lastRejectNotice[player] = nil
	end)

	local lastRest: { [Player]: number } = {}
	Remotes.get("RestCheckpoint").OnServerEvent:Connect(function(player, normal)
		local now = os.clock()
		if now - (lastRest[player] or 0) < 0.5 then
			return
		end
		lastRest[player] = now
		onRestCheckpoint(player, normal)
	end)

	Remotes.get("ResetToPlaza").OnServerEvent:Connect(function(player)
		active[player] = nil
		ClimbService.sendToPlaza(player)
	end)

	-- Track best height reached (shown on the HUD), up to the tallest summit.
	local maxHeight = 0
	for _, tower in towers:GetChildren() do
		maxHeight = math.max(maxHeight, (tower:GetAttribute("Height") or 0) + 60)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				local data = DataService.get(player)
				if root and data and root.Position.Y > data.BestHeight + 1 and root.Position.Y < maxHeight then
					DataService.update(player, function(d)
						d.BestHeight = math.floor(root.Position.Y)
					end)
				end
				-- Anti-teleport: nobody climbs faster than MaxPlausibleSpeed, so a
				-- bigger jump upward during a climb voids that climb's payout.
				local climb = active[player]
				if root and climb and not climb.paid then
					local now, y = os.clock(), root.Position.Y
					local last = climbTrack[player]
					if last and y - last.y > Config.Climb.MaxPlausibleSpeed * (now - last.t) + 15 then
						active[player] = nil
						climbTrack[player] = nil
						ClimbService.toast(player, "That climb didn't count (moved up too fast).", "bad")
					else
						climbTrack[player] = { y = y, t = now }
					end
				else
					climbTrack[player] = nil
				end
			end
		end
	end)
end

return ClimbService
