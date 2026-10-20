-- Climbing rope: clip a carabiner onto a telecom tower's horizontal beam, or
-- stick a suction cup onto skyscraper glass, and a real RopeConstraint ties
-- your harness to it. Created here so every player sees the rope; the climber's
-- client simulates their own body, so the rope physically catches their falls.
--
-- The client asks for a clip point. It's checked here with the same Lattice
-- maths the client used to pick it (so a point the client offers always
-- passes), and the climber always hears back ("RopeResult": ok + why not).
--
-- The gear is a real model: a D-shaped carabiner (orange body, silver gate)
-- with a quickdraw sling and a small rope-end clip, or a suction cup with a
-- handle. It flies from your harness up onto the beam/glass when you clip in,
-- and drops back to your harness when you unclip.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Lattice = require(ReplicatedStorage.Shared.Lattice)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RopeService = {}

-- How far (studs) a requested point may be from the beam/glass, and how much
-- further than Config.Rope.Reach from the climber it may be (network lag).
RopeService.CLIP_TOLERANCE = 1
RopeService.LAG_ALLOWANCE = 3

local gear: { [Player]: Model } = {}
local lastRequest: { [Player]: number } = {}
local notify = Remotes.get("Notify")

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

local function towerAt(point: Vector3): Model?
	local towers = Workspace:FindFirstChild("Towers")
	if not towers then
		return nil
	end
	for _, tower in towers:GetChildren() do
		local radius = tower:GetAttribute("Radius")
		if radius and tower:IsA("Model") then
			local p = tower.WorldPivot.Position
			if math.abs(point.X - p.X) <= radius + 2 and math.abs(point.Z - p.Z) <= radius + 2 then
				return tower
			end
		end
	end
	return nil
end

-- Clip bars of each tower as segments (towers never change once built).
local barCache: { [Model]: { Lattice.Segment } } = {}
local function clipBars(tower: Model): { Lattice.Segment }
	local cached = barCache[tower]
	if cached then
		return cached
	end
	local list = {}
	for _, bar in CollectionService:GetTagged("ClipBar") do
		if bar:IsA("BasePart") and bar:IsDescendantOf(tower) then
			table.insert(list, Lattice.segment(bar))
		end
	end
	barCache[tower] = list
	return list
end

-- What can be clipped at `point`: ("carabiner", beam point, beam direction),
-- ("suction", glass point, glass normal), or nil + the reason.
function RopeService.validate(point: Vector3): (string?, Vector3 | string, Vector3?)
	local tower = towerAt(point)
	if not tower then
		return nil, "You're not on a tower."
	end
	if tower:GetAttribute("Kind") == "Telecom" then
		local q, seg = Lattice.nearest(clipBars(tower), point, RopeService.CLIP_TOLERANCE)
		if not q or not seg then
			return nil, "No beam there - get your hands near a horizontal beam."
		end
		local along = seg.b - seg.a
		local dir = Vector3.new(along.X, 0, along.Z)
		return "carabiner", q, if dir.Magnitude > 1e-3 then dir.Unit else Vector3.xAxis
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { tower }
	for _, part in Workspace:GetPartBoundsInRadius(point, 1.5, params) do
		if part:HasTag("Climbable") then
			local localPoint = part.CFrame:PointToObjectSpace(point)
			local half = part.Size / 2 + Vector3.one * RopeService.CLIP_TOLERANCE
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return "suction", point, Lattice.faceNormal(tower.WorldPivot, point)
			end
		end
	end
	return nil, "No glass there to stick the suction cup on."
end

-- Gear models -----------------------------------------------------------------------

local ORANGE = Color3.fromRGB(255, 120, 30)
local SILVER = Color3.fromRGB(205, 210, 220)

-- A small part welded to `root`, placed at `offset` in root space.
local function piece(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, props: { [string]: any }?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = root.CFrame * offset
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Metal
	part.Color = ORANGE
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for key, value in props do
			(part :: any)[key] = value
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local function newRoot(model: Model, cf: CFrame): BasePart
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = cf
	root.Parent = model
	model.PrimaryPart = root
	return root
end

-- Carabiner hanging off a beam. Root space: X runs along the beam, Y up, the
-- ring hangs below the root (the beam passes through the top of the ring).
local function buildCarabiner(model: Model, cf: CFrame): (BasePart, Attachment)
	local root = newRoot(model, cf)
	local t = 0.14 -- wire thickness
	-- D-shaped ring in the root's YZ plane: top bar over the beam, back spine,
	-- narrower bottom, silver gate on the front, rounded corners.
	piece(model, root, "Top", Vector3.new(t, t, 0.62), CFrame.new(0, 0.36, 0))
	piece(model, root, "Spine", Vector3.new(t, 1.5, t), CFrame.new(0, -0.39, -0.31))
	piece(model, root, "Bottom", Vector3.new(t, t, 0.44), CFrame.new(0, -1.14, -0.09))
	piece(model, root, "Gate", Vector3.new(0.1, 1.28, 0.1), CFrame.new(0, -0.33, 0.24) * CFrame.Angles(math.rad(-9), 0, 0), {
		Color = SILVER,
	})
	for _, c in { Vector3.new(0, 0.36, -0.31), Vector3.new(0, 0.36, 0.31), Vector3.new(0, -1.14, -0.31), Vector3.new(0, -1.08, 0.13) } do
		piece(model, root, "Bend", Vector3.one * 0.2, CFrame.new(c), { Shape = Enum.PartType.Ball })
	end
	-- Quickdraw sling (flat webbing) and the rope-end clip.
	piece(model, root, "Sling", Vector3.new(0.06, 1.3, 0.32), CFrame.new(0, -1.85, -0.09), {
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(40, 150, 230),
	})
	piece(model, root, "RopeClip", Vector3.new(0.1, 0.55, 0.32), CFrame.new(0, -2.65, -0.09), { Color = SILVER })
	local att = Instance.new("Attachment")
	att.Name = "RopeEnd"
	att.Position = Vector3.new(0, -2.9, -0.09)
	att.Parent = root
	return root, att
end

-- Suction cup on glass. Root space: X points out of the glass.
local function buildSuction(model: Model, cf: CFrame): (BasePart, Attachment)
	local root = newRoot(model, cf)
	piece(model, root, "Cup", Vector3.new(0.25, 1.6, 1.6), CFrame.new(0.12, 0, 0), {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Color = ORANGE,
	})
	piece(model, root, "Body", Vector3.new(0.35, 0.9, 0.9), CFrame.new(0.4, 0, 0), {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(40, 40, 46),
	})
	piece(model, root, "Handle", Vector3.new(0.18, 0.18, 1.1), CFrame.new(0.8, 0, 0), { Color = SILVER })
	local att = Instance.new("Attachment")
	att.Name = "RopeEnd"
	att.Position = Vector3.new(0.85, -0.2, 0)
	att.Parent = root
	return root, att
end

-- Gear flying between your harness and the clip point.
local function fly(root: BasePart, from: CFrame, to: CFrame, time: number): Tween
	root.CFrame = from
	local tween = TweenService:Create(root, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = to })
	tween:Play()
	return tween
end

-- Clip / unclip ---------------------------------------------------------------------

local function result(player: Player, ok: boolean, text: string, kind: string?)
	notify:FireClient(player, "RopeResult", { ok = ok, text = text, kind = kind })
end

function RopeService.unclip(player: Player, animate: boolean?)
	local model = gear[player]
	gear[player] = nil
	player:SetAttribute("RopeAnchor", nil)
	player:SetAttribute("RopeKind", nil)
	if not model then
		return
	end
	local rope = model:FindFirstChildWhichIsA("RopeConstraint", true)
	if rope then
		rope:Destroy()
	end
	local root = model.PrimaryPart
	local harness = rootOf(player)
	if animate and root and harness then
		-- Drop the gear back down to the harness, then put it away.
		fly(root, root.CFrame, harness.CFrame * CFrame.new(0.6, -0.8, 0), 0.3)
		task.delay(0.35, function()
			model:Destroy()
		end)
	else
		model:Destroy()
	end
end

local function clip(player: Player, point: Vector3)
	local root = rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (point - root.Position).Magnitude > Config.Rope.Reach + RopeService.LAG_ALLOWANCE + 2.5 then
		result(player, false, "Too far away to clip there - climb closer.")
		return
	end
	local kind, at, dir = RopeService.validate(point)
	if not kind or typeof(at) ~= "Vector3" or not dir then
		result(player, false, if typeof(at) == "string" then at else "Can't clip there.")
		return
	end
	RopeService.unclip(player)

	local model = Instance.new("Model")
	model.Name = player.Name .. "_" .. kind
	local target, gearRoot, ropeEnd
	if kind == "carabiner" then
		-- Ring hangs off the beam with the beam through its top.
		target = CFrame.fromMatrix(at - Vector3.new(0, 0.36, 0), dir, Vector3.yAxis)
		gearRoot, ropeEnd = buildCarabiner(model, target)
	else
		target = CFrame.fromMatrix(at - dir * 0.3, dir, Vector3.yAxis)
		gearRoot, ropeEnd = buildSuction(model, target)
	end

	local harness = root:FindFirstChild("RopeAttachment") :: Attachment?
	if not harness then
		local att = Instance.new("Attachment")
		att.Name = "RopeAttachment"
		att.Position = Vector3.new(0, -0.6, 0) -- at the waist
		att.Parent = root
		harness = att
	end
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = ropeEnd
	rope.Attachment1 = harness
	-- Config.Rope.Length is measured from the clip point to your body (that's
	-- what the client limits); add the quickdraw and harness offsets so the
	-- rope never pulls against your own climbing before that.
	rope.Length = Config.Rope.Length + (at - target:PointToWorldSpace(ropeEnd.Position)).Magnitude + 1.2
	rope.Visible = true
	rope.Thickness = 0.2
	rope.Color = BrickColor.new("Deep orange")
	rope.Restitution = 0.1
	rope.Parent = gearRoot
	model.Parent = ropesFolder()
	-- The clip animation: the gear flies up from the harness onto the beam.
	fly(gearRoot, root.CFrame * CFrame.new(0.6, -0.8, 0) * target.Rotation, target, 0.35)

	gear[player] = model
	player:SetAttribute("RopeKind", kind)
	player:SetAttribute("RopeAnchor", at)
	result(player, true, if kind == "carabiner" then "Clipped in! Carabiner's on the beam." else "Suction cup stuck on!", kind)
end

function RopeService.start()
	Remotes.get("Rope").OnServerEvent:Connect(function(player, action, point)
		if action == "clip" and typeof(point) == "Vector3" then
			-- Rate limit clips only: an unclip (e.g. climbing onto the summit
			-- right after clipping) must never be dropped.
			local now = os.clock()
			if now - (lastRequest[player] or 0) < 0.25 then
				result(player, false, "Easy - one clip at a time.")
				return
			end
			lastRequest[player] = now
			clip(player, point)
		elseif action == "unclip" then
			RopeService.unclip(player, true)
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
