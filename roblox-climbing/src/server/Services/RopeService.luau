--!strict
-- RopeService (server): top-rope and auto-belay.
--
--  * Outdoors: hold the "Tie in" prompt on a route's rope bag to tie in to the anchor at
--    its top (RouteKit TopAnchor). Untie with the prompt again, or by walking away.
--    Not tied in = free solo: a fall from high up is fatal.
--  * Indoors: walls with AutoBelay have an auto-belay: hold "Clip in" at its carabiner. It
--    unclips you once you're back on the floor after a climb.
--  * Every roped wall must be clipped into: grabbing a hold on a route with a rope bag or
--    an auto-belay is refused until you're tied in to that route (ClimbService guard).
--  * While you climb, a rope (a Beam) runs from your harness up to the anchor. Fall or let
--    go and a real RopeConstraint catches you after a little slack, you dangle for a
--    moment, then the belayer lowers you to the ground. Grab a hold while hanging to climb
--    on (your run is over, though: RouteService fails it when the rope catches you).
--
-- Character attributes: "TiedIn" (route id) while tied in, "RopeCatch" while hanging or
-- being lowered on the rope. RagdollService skips fall damage while "TiedIn" is set.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HoldUtil = require(Shared.HoldUtil)
local LimbRig = require(Shared.LimbRig)

local ClimbService = require(script.Parent.ClimbService)

local ROPE = Config.Rope

type Mode = "climb" | "caught" | "lowering"

type Tie = {
	route: Instance,
	character: Model,
	auto: boolean,
	mode: Mode,
	since: number,
	groundFor: number,
	climbed: boolean, -- has been on the wall since tying in
	tieAttachment: Attachment,
	beam: Beam,
	rope: RopeConstraint,
}

local RopeService = {}

local ties: { [Player]: Tie } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

-- The anchor at the top of a route: two bolts and a ring, made on first use.
local function anchorFor(route: Instance): Attachment?
	local existing = route:FindFirstChild("TopAnchorPart")
	if existing then
		local attachment = existing:FindFirstChild("Ring")
		return if attachment and attachment:IsA("Attachment") then attachment else nil
	end
	local position = route:GetAttribute("TopAnchor")
	if typeof(position) ~= "Vector3" then
		return nil
	end
	local anchor = Instance.new("Part")
	anchor.Name = "TopAnchorPart"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Shape = Enum.PartType.Ball
	anchor.Material = Enum.Material.DiamondPlate
	anchor.Color = Color3.fromRGB(190, 192, 198)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = position
	local ring = Instance.new("Attachment")
	ring.Name = "Ring"
	ring.Parent = anchor
	anchor.Parent = route
	return ring
end

local function setAttribute(character: Model, name: string, value: any)
	if character:GetAttribute(name) ~= value then
		character:SetAttribute(name, value)
	end
end

function RopeService.Untie(player: Player)
	local tie = ties[player]
	if tie == nil then
		return
	end
	ties[player] = nil
	tie.beam:Destroy()
	tie.rope:Destroy()
	tie.tieAttachment:Destroy()
	if tie.character.Parent then
		setAttribute(tie.character, "TiedIn", nil)
		setAttribute(tie.character, "RopeCatch", nil)
	end
end

function RopeService.TieIn(player: Player, route: Instance, auto: boolean): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	local anchor = anchorFor(route)
	if anchor == nil then
		return false
	end
	RopeService.Untie(player)

	local tieAttachment = Instance.new("Attachment")
	tieAttachment.Name = "RopeTie"
	tieAttachment.Position = Vector3.new(0, -0.6, -0.4) -- harness, at the front of the hips
	tieAttachment.Parent = root

	local gearColor = player:GetAttribute("GearRopeColor")
	local color = if auto then ROPE.AutoBelayColor elseif typeof(gearColor) == "Color3" then gearColor else ROPE.Color
	local beam = Instance.new("Beam")
	beam.Name = "ClimbRope"
	beam.Attachment0 = anchor
	beam.Attachment1 = tieAttachment
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.Segments = 12
	beam.CurveSize0 = 0
	beam.CurveSize1 = -1.5 -- a little slack hanging below the climber
	beam.FaceCamera = true
	beam.LightInfluence = 1
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0)
	beam.Parent = root

	local rope = Instance.new("RopeConstraint")
	rope.Name = "BelayRope"
	rope.Attachment0 = anchor
	rope.Attachment1 = tieAttachment
	rope.Visible = true
	rope.Thickness = 0.12
	rope.Color = BrickColor.new(color)
	rope.Enabled = false
	rope.Parent = root

	ties[player] = {
		route = route,
		character = character,
		auto = auto,
		mode = "climb",
		since = os.clock(),
		groundFor = 0,
		climbed = false,
		tieAttachment = tieAttachment,
		beam = beam,
		rope = rope,
	}
	character:SetAttribute("TiedIn", route.Name)
	return true
end

local function catch(tie: Tie)
	local root = tie.tieAttachment.Parent
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local anchor = tie.rope.Attachment0
	if anchor == nil then
		return
	end
	tie.rope.Length = (anchor.WorldPosition - tie.tieAttachment.WorldPosition).Magnitude + ROPE.CatchSlack
	tie.rope.Enabled = true
	tie.beam.Enabled = false
	tie.mode = "caught"
	tie.since = os.clock()
	setAttribute(tie.character, "RopeCatch", true)
end

local function backOnWall(tie: Tie)
	tie.rope.Enabled = false
	tie.beam.Enabled = true
	tie.mode = "climb"
	setAttribute(tie.character, "RopeCatch", nil)
end

local function grounded(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	rayParams.FilterDescendantsInstances = { character }
	return Workspace:Raycast(root.Position, Vector3.yAxis * -(LimbRig.standingHeight(humanoid, root) + 0.8), rayParams) ~= nil
end

local function onLeftWall(player: Player, reason: string)
	local tie = ties[player]
	if tie == nil or reason == "Died" or reason == "Teleport" then
		return
	end
	if reason == "Dyno" then
		-- Give the jump time to land; catch it if it missed.
		task.delay(Config.Falls.DynoGrace * 0.8, function()
			if ties[player] == tie and tie.mode == "climb" and tie.character:GetAttribute("Climbing") ~= true and not grounded(tie.character) then
				catch(tie)
			end
		end)
		return
	end
	if not grounded(tie.character) then
		catch(tie)
	end
end

local function onPlaced(player: Player, _limb: string, hold: BasePart)
	local tie = ties[player]
	if tie then
		if tie.mode ~= "climb" then
			backOnWall(tie)
		end
		return
	end
end

-- Roped routes can only be climbed tied in to them.
local function placeGuard(player: Player, hold: BasePart): string?
	local route = HoldUtil.getRouteFolder(hold)
	if route == nil or (route:GetAttribute("Rope") ~= true and route:GetAttribute("AutoBelay") ~= true) then
		return nil
	end
	local tie = ties[player]
	if tie and tie.route == route then
		return nil
	end
	return if route:GetAttribute("AutoBelay") == true then "clip in to the auto-belay first" else "tie in at the rope bag first"
end
RopeService.placeGuard = placeGuard

local function tick(dt: number)
	local now = os.clock()
	for player, tie in ties do
		local character = tie.character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if player.Character ~= character or character.Parent == nil or humanoid == nil or humanoid.Health <= 0 or tie.tieAttachment.Parent == nil then
			RopeService.Untie(player)
			continue
		end
		local onGround = character:GetAttribute("Climbing") ~= true and grounded(character)

		if tie.mode == "caught" then
			if now - tie.since >= ROPE.HangSeconds then
				tie.mode = "lowering"
			end
		elseif tie.mode == "lowering" then
			if onGround then
				backOnWall(tie)
				tie.beam.Enabled = true
			else
				tie.rope.Length += ROPE.LowerSpeed * dt
			end
		end

		if tie.mode == "climb" then
			-- Auto-belays unclip you once you're back on the floor after a climb; walking
			-- away unties you.
			if character:GetAttribute("Climbing") == true then
				tie.climbed = true
			end
			tie.groundFor = if onGround then tie.groundFor + dt else 0
			local start = tie.route:GetAttribute("StartPosition")
			local root = tie.tieAttachment.Parent :: BasePart
			local far = typeof(start) == "Vector3" and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude > ROPE.UntieDistance
			if (tie.auto and tie.climbed and tie.groundFor > 1.5) or (onGround and far) then
				RopeService.Untie(player)
			end
		end
	end
end

local function onPrompt(prompt: ProximityPrompt, player: Player)
	-- The route is the nearest ancestor with a RouteName (bag -> route, carabiner ->
	-- AutoBelay -> route).
	local route: Instance? = prompt.Parent
	while route and route:GetAttribute("RouteName") == nil do
		route = route.Parent
	end
	if route == nil then
		return
	end
	local character = player.Character
	if character and character:GetAttribute("Climbing") == true then
		return -- no untying mid-climb
	end
	local tie = ties[player]
	if tie and tie.route == route then
		RopeService.Untie(player)
	else
		RopeService.TieIn(player, route, prompt.Name == "ClipIn")
	end
end

function RopeService.IsTiedIn(player: Player): boolean
	return ties[player] ~= nil
end

function RopeService.Start()
	ClimbService.OnLeftWall(onLeftWall)
	ClimbService.OnPlaced(onPlaced)
	ClimbService.AddPlaceGuard(placeGuard)

	local function watch(instance: Instance)
		if instance:IsA("ProximityPrompt") and (instance.Name == "TieIn" or instance.Name == "ClipIn") then
			instance.Triggered:Connect(function(player)
				onPrompt(instance, player)
			end)
		end
	end
	local routes = Workspace:WaitForChild("Routes", 30)
	if routes then
		for _, descendant in routes:GetDescendants() do
			watch(descendant)
		end
		routes.DescendantAdded:Connect(watch)
	end

	Players.PlayerRemoving:Connect(RopeService.Untie)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.05 then
			tick(elapsed)
			elapsed = 0
		end
	end)
end

return RopeService
