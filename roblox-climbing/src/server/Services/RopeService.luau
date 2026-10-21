--!strict
-- RopeService (server): top-rope and auto-belay, with real rope physics.
--
--  * Outdoors: click a route's rope bag to tie in to the anchor at its top (RouteKit
--    TopAnchor). Click it again, or walk away, to untie.
--  * Indoors: walls with AutoBelay have an auto-belay: click its carabiner to clip in. It
--    unclips you once you're back on the floor after a climb.
--  * Ropes are optional: you can free solo anything. A fall from high up is then fatal.
--
-- The rope is one RopeConstraint from the anchor (or the auto-belay unit) to your harness,
-- with its winch playing the belayer:
--  * climbing: it takes in and pays out to keep Config.Rope.Slack of slack, which you see
--    sag (the winch is too weak to drag a climber about);
--  * fall or let go: the length freezes, so you drop the slack and the rope stretches and
--    bounces (Restitution), then you swing and dangle ("Caught", then "Hanging");
--  * then the winch pays out at LowerSpeed and lowers you to the ground ("Lowering");
--  * press R while climbing (RouteRequest "Lower") to sit back on the rope and be lowered.
-- Grab a hold at any point to climb on. Outdoors a second, taut rope runs from the anchor
-- down to the rope bag, the belayer's side.
--
-- Character attributes: "TiedIn" (route id), "RopeCatch" (true while the rope holds you),
-- "RopeMode" ("Caught" | "Hanging" | "Lowering", for the client's animations) and
-- "Gesture" ("Clip@n" when you clip in). RagdollService skips fall damage while tied in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LimbRig = require(Shared.LimbRig)

local ClimbService = require(script.Parent.ClimbService)

local ROPE = Config.Rope

type Mode = "climb" | "caught" | "hanging" | "lowering"

type Tie = {
	route: Instance,
	character: Model,
	auto: boolean,
	mode: Mode,
	since: number,
	groundFor: number,
	climbed: boolean, -- has been on the wall since tying in
	anchor: Attachment,
	tieAttachment: Attachment,
	rope: RopeConstraint,
	belaySide: RopeConstraint?, -- outdoors: anchor down to the rope bag
	hidden: { Instance }, -- the auto-belay's own carabiner and strap, hidden while in use
}

local RopeService = {}

local ties: { [Player]: Tie } = {}
local gestureCount = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function setAttribute(character: Model, name: string, value: any)
	if character:GetAttribute(name) ~= value then
		character:SetAttribute(name, value)
	end
end

local function gesture(character: Model, name: string)
	gestureCount += 1
	character:SetAttribute("Gesture", `{name}@{gestureCount}`)
end
RopeService.gesture = gesture

-- The anchor at the top of a route: a steel ring, made on first use.
local function topAnchor(route: Instance): Attachment?
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

-- Where the rope comes from: the auto-belay unit's drum, or the top anchor. Also returns
-- the auto-belay's own carabiner and strap, which are hidden while someone is clipped in.
local function ropeOrigin(route: Instance, auto: boolean): (Attachment?, { Instance })
	if auto then
		local unit = route:FindFirstChild("AutoBelay")
		local housing = unit and unit:FindFirstChild("Unit")
		local strap = housing and housing:FindFirstChild("Strap")
		if strap and strap:IsA("Beam") and strap.Attachment0 then
			local hidden: { Instance } = { strap }
			local clip = unit and unit:FindFirstChild("Carabiner")
			if clip then
				table.insert(hidden, clip)
			end
			return strap.Attachment0, hidden
		end
	end
	return topAnchor(route), {}
end

local function setHidden(things: { Instance }, hidden: boolean)
	for _, thing in things do
		if thing:IsA("Beam") then
			thing.Enabled = not hidden
		elseif thing:IsA("BasePart") then
			thing.Transparency = if hidden then 1 else 0
		end
	end
end

local function setMode(tie: Tie, mode: Mode)
	tie.mode = mode
	tie.since = os.clock()
	local name = if mode == "caught" then "Caught" elseif mode == "hanging" then "Hanging" elseif mode == "lowering" then "Lowering" else nil
	setAttribute(tie.character, "RopeMode", name)
	setAttribute(tie.character, "RopeCatch", if mode ~= "climb" then true else nil)
end

local function ropeDistance(tie: Tie): number
	return (tie.anchor.WorldPosition - tie.tieAttachment.WorldPosition).Magnitude
end

function RopeService.Untie(player: Player)
	local tie = ties[player]
	if tie == nil then
		return
	end
	ties[player] = nil
	tie.rope:Destroy()
	if tie.belaySide then
		tie.belaySide:Destroy()
	end
	tie.tieAttachment:Destroy()
	setHidden(tie.hidden, false)
	if tie.character.Parent then
		setAttribute(tie.character, "TiedIn", nil)
		setAttribute(tie.character, "RopeCatch", nil)
		setAttribute(tie.character, "RopeMode", nil)
	end
end

function RopeService.TieIn(player: Player, route: Instance, auto: boolean): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	local anchor, hidden = ropeOrigin(route, auto)
	if anchor == nil then
		return false
	end
	RopeService.Untie(player)

	local tieAttachment = Instance.new("Attachment")
	tieAttachment.Name = "RopeTie"
	tieAttachment.Position = Vector3.new(0, -0.6, -0.45) -- harness, at the front of the hips
	tieAttachment.Parent = root

	local gearColor = player:GetAttribute("GearRopeColor")
	local color = if auto then ROPE.AutoBelayColor elseif typeof(gearColor) == "Color3" then gearColor else ROPE.Color
	local distance = (anchor.WorldPosition - tieAttachment.WorldPosition).Magnitude

	local rope = Instance.new("RopeConstraint")
	rope.Name = "BelayRope"
	rope.Attachment0 = anchor
	rope.Attachment1 = tieAttachment
	rope.Visible = true
	rope.Thickness = if auto then 0.16 else 0.11
	rope.Color = BrickColor.new(color)
	rope.Restitution = ROPE.Stretch
	rope.Length = distance + ROPE.Slack
	rope.WinchEnabled = true
	rope.WinchTarget = rope.Length
	rope.WinchSpeed = ROPE.TakeInSpeed
	rope.WinchForce = 2500 -- too weak to drag a climber about; holds them once they fall
	rope.WinchResponsiveness = 45
	rope.Parent = root

	-- Outdoors: the belayer's side of the rope, from the anchor down to the rope bag.
	local belaySide: RopeConstraint? = nil
	local bag = route:FindFirstChild("RopeBag")
	if not auto and bag and bag:IsA("BasePart") then
		local found = bag:FindFirstChild("RopeEnd")
		local bagEnd: Attachment
		if found and found:IsA("Attachment") then
			bagEnd = found
		else
			bagEnd = Instance.new("Attachment")
			bagEnd.Name = "RopeEnd"
			bagEnd.Parent = bag
			bagEnd.WorldPosition = bag.Position + Vector3.yAxis * 0.4
		end
		local side = Instance.new("RopeConstraint")
		side.Name = "BelaySide"
		side.Attachment0 = anchor
		side.Attachment1 = bagEnd
		side.Visible = true
		side.Thickness = 0.11
		side.Color = BrickColor.new(color)
		side.Length = (anchor.WorldPosition - bagEnd.WorldPosition).Magnitude + 0.5
		side.Parent = bag
		belaySide = side
	end
	setHidden(hidden, true)

	ties[player] = {
		route = route,
		character = character,
		auto = auto,
		mode = "climb",
		since = os.clock(),
		groundFor = 0,
		climbed = false,
		anchor = anchor,
		tieAttachment = tieAttachment,
		rope = rope,
		belaySide = belaySide,
		hidden = hidden,
	}
	character:SetAttribute("TiedIn", route.Name)
	gesture(character, "Clip")
	return true
end

-- The rope comes tight: freeze its length (you drop the slack and bounce).
local function catch(tie: Tie)
	tie.rope.WinchTarget = tie.rope.Length
	setMode(tie, "caught")
end

-- Sit back on the rope gently: the belayer takes in, then lowers you.
function RopeService.Lower(player: Player)
	local tie = ties[player]
	local character = player.Character
	if tie == nil or character == nil or character:GetAttribute("Climbing") ~= true then
		return
	end
	tie.rope.WinchSpeed = ROPE.TakeSpeed
	tie.rope.WinchTarget = ropeDistance(tie) + 0.2
	setMode(tie, "hanging")
	ClimbService.ForceOff(player, "Take")
end

local function backOnWall(tie: Tie)
	tie.rope.WinchSpeed = ROPE.TakeInSpeed
	tie.rope.WinchTarget = ropeDistance(tie) + ROPE.Slack
	setMode(tie, "climb")
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
	if tie == nil or reason == "Died" or reason == "Teleport" or reason == "Take" or reason == "Mantle" then
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

local function onPlaced(player: Player, _limb: string, _hold: BasePart)
	local tie = ties[player]
	if tie and tie.mode ~= "climb" then
		backOnWall(tie)
	end
end

local function tick(dt: number)
	local now = os.clock()
	for player, tie in ties do
		local character = tie.character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if player.Character ~= character or character.Parent == nil or humanoid == nil or humanoid.Health <= 0 or tie.tieAttachment.Parent == nil then
			RopeService.Untie(player)
			continue
		end
		local climbing = character:GetAttribute("Climbing") == true
		local onGround = not climbing and grounded(character)

		if tie.mode == "climb" then
			if climbing or onGround then
				tie.climbed = tie.climbed or climbing
				-- The belayer follows you (climbing, or walking about on the top after
				-- climbing up onto it): keep a little slack in the rope.
				tie.rope.WinchSpeed = ROPE.TakeInSpeed
				tie.rope.WinchTarget = ropeDistance(tie) + ROPE.Slack
			end
			-- Auto-belays unclip you once you're back on the floor after a climb; walking
			-- away unties you.
			tie.groundFor = if onGround then tie.groundFor + dt else 0
			local start = tie.route:GetAttribute("StartPosition")
			local root = tie.tieAttachment.Parent :: BasePart
			local far = typeof(start) == "Vector3" and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude > ROPE.UntieDistance
			if (tie.auto and tie.climbed and tie.groundFor > 1.5) or (onGround and far) then
				RopeService.Untie(player)
			end
		elseif tie.mode == "caught" then
			if now - tie.since >= ROPE.CaughtSeconds then
				setMode(tie, "hanging")
			end
		elseif tie.mode == "hanging" then
			if now - tie.since >= ROPE.HangSeconds then
				-- Lower: the winch pays out steadily.
				tie.rope.WinchSpeed = ROPE.LowerSpeed
				tie.rope.WinchTarget = tie.rope.Length + 5000
				setMode(tie, "lowering")
			end
		elseif tie.mode == "lowering" then
			if onGround then
				tie.rope.WinchTarget = tie.rope.Length
				tie.climbed = true
				setMode(tie, "climb")
			end
		end
	end
end

local function onClick(clicker: ClickDetector, player: Player)
	-- The route is the nearest ancestor with a RouteName (bag -> route, carabiner ->
	-- AutoBelay -> route).
	local route: Instance? = clicker.Parent
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
		RopeService.TieIn(player, route, clicker.Name == "ClipIn")
	end
end

function RopeService.IsTiedIn(player: Player): boolean
	return ties[player] ~= nil
end

function RopeService.Start()
	ClimbService.OnLeftWall(onLeftWall)
	ClimbService.OnPlaced(onPlaced)

	local function watch(instance: Instance)
		if instance:IsA("ClickDetector") and (instance.Name == "TieIn" or instance.Name == "ClipIn") then
			instance.MouseClick:Connect(function(player)
				onClick(instance, player)
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
