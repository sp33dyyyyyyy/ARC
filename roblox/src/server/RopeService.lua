-- Climbing rope: clip a carabiner onto a telecom tower's horizontal beam, or
-- stick a suction cup onto skyscraper glass, and a real RopeConstraint ties
-- your harness to it. Created here so every player sees the rope; the climber's
-- client simulates their own body, so the rope physically catches their falls.
-- The client asks for a clip point; it's validated here (on a clip bar / glass,
-- within reach) before anything is created.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RopeService = {}

local anchors: { [Player]: BasePart } = {}
local lastRequest: { [Player]: number } = {}

local function ropesFolder(): Folder
	local folder = Workspace:FindFirstChild("Ropes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Ropes"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Closest point on a beam (its length runs along the part's Z axis).
local function closestOnBar(bar: BasePart, point: Vector3): Vector3
	local cf = bar.CFrame
	local along = cf.LookVector
	local half = bar.Size.Z / 2
	local d = math.clamp((point - cf.Position):Dot(along), -half, half)
	return cf.Position + along * d
end

-- What the point is clipped to: "carabiner" (telecom beam), "suction" (glass), or nil.
local function clipKind(point: Vector3): string?
	for _, bar in CollectionService:GetTagged("ClipBar") do
		if bar:IsA("BasePart") and (closestOnBar(bar, point) - point).Magnitude <= 1 then
			return "carabiner"
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace:FindFirstChild("Towers") :: Instance }
	for _, part in Workspace:GetPartBoundsInRadius(point, 1.5, params) do
		local tower = part:FindFirstAncestorOfClass("Model")
		if part:HasTag("Climbable") and tower and tower:GetAttribute("Kind") == "Skyscraper" then
			local localPoint = part.CFrame:PointToObjectSpace(point)
			local half = part.Size / 2 + Vector3.one
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return "suction"
			end
		end
	end
	return nil
end

function RopeService.unclip(player: Player)
	local anchor = anchors[player]
	if anchor then
		anchor:Destroy()
		anchors[player] = nil
	end
	player:SetAttribute("RopeAnchor", nil)
	player:SetAttribute("RopeKind", nil)
end

local function clip(player: Player, point: Vector3)
	local root = rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (point - root.Position).Magnitude > Config.Rope.Reach + 3 then
		return -- too far from the climber (allowing a little for lag)
	end
	local kind = clipKind(point)
	if not kind then
		return
	end
	RopeService.unclip(player)

	local anchor = Instance.new("Part")
	anchor.Name = player.Name .. "_" .. kind
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	if kind == "carabiner" then
		anchor.Size = Vector3.new(0.35, 0.9, 0.35)
		anchor.Color = Color3.fromRGB(255, 140, 30)
		anchor.Material = Enum.Material.Metal
	else
		anchor.Shape = Enum.PartType.Ball
		anchor.Size = Vector3.one * 1.3
		anchor.Color = Color3.fromRGB(255, 120, 40)
		anchor.Material = Enum.Material.Glass
		anchor.Transparency = 0.3
	end
	anchor.CFrame = CFrame.new(point)
	local att0 = Instance.new("Attachment")
	att0.Parent = anchor
	local harness = root:FindFirstChild("RopeAttachment") :: Attachment?
	if not harness then
		local att = Instance.new("Attachment")
		att.Name = "RopeAttachment"
		att.Parent = root
		harness = att
	end
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = att0
	rope.Attachment1 = harness
	rope.Length = Config.Rope.Length
	rope.Visible = true
	rope.Thickness = 0.12
	rope.Color = BrickColor.new("Deep orange")
	rope.Restitution = 0.1
	rope.Parent = anchor
	anchor.Parent = ropesFolder()

	anchors[player] = anchor
	player:SetAttribute("RopeKind", kind)
	player:SetAttribute("RopeAnchor", point)
end

function RopeService.start()
	Remotes.get("Rope").OnServerEvent:Connect(function(player, action, point)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.25 then
			return
		end
		lastRequest[player] = now
		if action == "clip" and typeof(point) == "Vector3" then
			clip(player, point)
		elseif action == "unclip" then
			RopeService.unclip(player)
		end
	end)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			RopeService.unclip(player)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.Died:Connect(function()
				RopeService.unclip(player)
			end)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		RopeService.unclip(player)
		lastRequest[player] = nil
	end)
end

return RopeService
