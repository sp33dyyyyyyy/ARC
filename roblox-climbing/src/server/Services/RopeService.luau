--!strict
-- RopeService (server): top-rope, lead and auto-belay, with real rope physics.
--
--  * Outdoors you bring the rope: drop the rope bag from your pack at a route's base
--    (PackService), then click it to tie in (click again, or walk away, to untie).
--      - Wall A and Wall B: top rope, through the two-bolt anchor under the lip (Hardware).
--      - The Colossus ("Lead" routes): no fixed anchors. The rope runs up from your bag and
--        through every quickdraw you place (Clip). Until the first one is in, a fall is a
--        ground fall; above a piece you fall twice your height above it, plus the slack.
--  * Indoors: walls with AutoBelay have an auto-belay: click its carabiner to clip in. It
--    unclips you once you're back on the floor after a climb.
--  * Ropes are optional: you can free solo anything. A fall from high up is then fatal.
--
-- The rope is one RopeConstraint from the anchor (or the last piece, or the auto-belay
-- unit) to a locking carabiner on your harness, with its winch playing the belayer:
--  * climbing: it follows you, keeping Config.Rope.Slack of slack, which you see sag. Hold
--    Y to pay out more slack, T to take it in ("RopeFeed");
--  * fall or let go: you drop the slack, then the dynamic rope stretches (it gives a little
--    while it catches you, so the catch is soft), bounces, and you swing ("Caught", then
--    "Hanging");
--  * then you're lowered ("Lowering"): Y lowers you faster, T stops you, and T while
--    stopped hauls you up; R goes back to a steady lower;
--  * R while climbing: sit back on the rope and be lowered. R standing on top (tied in):
--    back over the edge (the client walks you over) and rappel down.
-- Grab a hold at any point to climb on. On top ropes a second, taut rope runs from the
-- anchor down to your bag, the belayer's side.
--
-- Character attributes: "TiedIn" (route id), "RopeCatch" (true while the rope holds you),
-- "RopeMode" ("Caught" | "Hanging" | "Lowering", for the client's animations), "RopeSlack"
-- (studs, while climbing), "RopeLead" (lead route), "Unprotected" (lead with no piece in
-- yet: the rope won't catch you) and "Gesture" ("Clip@n" when you clip in).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LimbRig = require(Shared.LimbRig)

local BuildUtil = require(script.Parent.Parent.World.BuildUtil)
local Hardware = require(script.Parent.Parent.World.Hardware)
local ClimbService = require(script.Parent.ClimbService)

local ROPE = Config.Rope

type Mode = "climb" | "caught" | "hanging" | "lowering"

type Piece = { model: Model, at: Attachment }

type Tie = {
	route: Instance,
	character: Model,
	auto: boolean,
	lead: boolean,
	mode: Mode,
	since: number,
	hangFor: number, -- seconds to dangle before being lowered
	groundFor: number,
	climbed: boolean, -- has been on the wall since tying in
	stretched: boolean, -- this catch's stretch has been given
	manual: boolean, -- you've taken control of the lower (T/Y)
	feed: number, -- -1 take in, 0, +1 pay out (held keys)
	extra: number, -- slack added (or taken in) on top of Config.Rope.Slack
	anchor: Attachment, -- where the rope runs from now
	tieAttachment: Attachment,
	rope: RopeConstraint,
	bag: BasePart?,
	belaySide: RopeConstraint?, -- top ropes: anchor down to the rope bag
	pieces: { Piece }, -- lead: quickdraws placed, bottom first
	gear: Model?, -- the locking carabiner on the harness
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

-- The ring in the locking carabiner of a route's top anchor (RouteKit / Hardware).
local function topAnchor(route: Instance): Attachment?
	local part = route:FindFirstChild("TopAnchorPart", true)
	local ring = part and part:FindFirstChild("Ring")
	return if ring and ring:IsA("Attachment") then ring else nil
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

local function bagEnd(bag: BasePart): Attachment
	local found = bag:FindFirstChild("RopeEnd")
	if found and found:IsA("Attachment") then
		return found
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "RopeEnd"
	attachment.Position = Vector3.new(0, 0.4, 0)
	attachment.Parent = bag
	return attachment
end

local function setMode(tie: Tie, mode: Mode)
	tie.mode = mode
	tie.since = os.clock()
	local name = if mode == "caught" then "Caught" elseif mode == "hanging" then "Hanging" elseif mode == "lowering" then "Lowering" else nil
	setAttribute(tie.character, "RopeMode", name)
	setAttribute(tie.character, "RopeCatch", if mode ~= "climb" then true else nil)
	setAttribute(tie.character, "RopeSlack", nil)
	-- Holding a climber's weight needs a strong winch; following a climber a weak one.
	tie.rope.WinchForce = if mode == "climb" then ROPE.ClimbForce else ROPE.HoldForce
end

local function ropeDistance(tie: Tie): number
	return (tie.anchor.WorldPosition - tie.tieAttachment.WorldPosition).Magnitude
end

-- Does the rope catch a fall right now? (Not on lead before the first quickdraw.)
local function protects(tie: Tie): boolean
	return not tie.lead or #tie.pieces > 0
end

-- The locking carabiner on the harness, welded to the body.
local function harnessGear(root: BasePart, tieAttachment: Attachment, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "HarnessCarabiner"
	local top = root.CFrame * CFrame.new(tieAttachment.Position + Vector3.new(0, 0.16, -0.04))
	Hardware.carabiner(model, top, 0.34, color, true)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
		end
	end
	return model
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
	for _, piece in tie.pieces do
		piece.model:Destroy()
	end
	if tie.gear then
		tie.gear:Destroy()
	end
	tie.tieAttachment:Destroy()
	setHidden(tie.hidden, false)
	if tie.character.Parent then
		for _, name in { "TiedIn", "RopeCatch", "RopeMode", "RopeSlack", "RopeLead", "Unprotected" } do
			setAttribute(tie.character, name, nil)
		end
	end
end

-- Tie in to `route`: the auto-belay (`auto`), or with the rope in `bag` (a rope bag dropped
-- from a pack).
function RopeService.TieIn(player: Player, route: Instance, auto: boolean, bag: BasePart?): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	local lead = not auto and route:GetAttribute("Lead") == true
	local anchor: Attachment?, hidden: { Instance }
	if lead then
		if bag == nil then
			return false
		end
		anchor, hidden = bagEnd(bag), {}
	else
		anchor, hidden = ropeOrigin(route, auto)
	end
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
	rope.WinchForce = ROPE.ClimbForce
	rope.WinchResponsiveness = 45
	rope.Parent = root

	-- Top ropes: the belayer's side, from the anchor down to the rope bag.
	local belaySide: RopeConstraint? = nil
	if not auto and not lead and bag then
		local bottom = bagEnd(bag)
		local side = Instance.new("RopeConstraint")
		side.Name = "BelaySide"
		side.Attachment0 = anchor
		side.Attachment1 = bottom
		side.Visible = true
		side.Thickness = 0.11
		side.Color = BrickColor.new(color)
		side.Length = (anchor.WorldPosition - bottom.WorldPosition).Magnitude + 0.5
		side.Parent = bag
		belaySide = side
	end
	setHidden(hidden, true)

	local gear = harnessGear(root, tieAttachment, Hardware.GOLD)
	gear.Parent = character

	ties[player] = {
		route = route,
		character = character,
		auto = auto,
		lead = lead,
		mode = "climb",
		since = os.clock(),
		hangFor = ROPE.HangSeconds,
		groundFor = 0,
		climbed = false,
		stretched = false,
		manual = false,
		feed = 0,
		extra = 0,
		anchor = anchor,
		tieAttachment = tieAttachment,
		rope = rope,
		bag = bag,
		belaySide = belaySide,
		pieces = {},
		gear = gear,
		hidden = hidden,
	}
	character:SetAttribute("TiedIn", route.Name)
	character:SetAttribute("RopeLead", if lead then true else nil)
	character:SetAttribute("Unprotected", if lead then true else nil)
	gesture(character, "Clip")
	return true
end

-- Lead: clip a quickdraw into the rock at `position` (on the face, `normal` out of it).
-- The rope now runs through it.
function RopeService.Clip(player: Player, position: Vector3, normal: Vector3): (boolean, string?)
	local tie = ties[player]
	if tie == nil or not tie.lead then
		return false, "tie in on a lead route first"
	end
	if tie.character:GetAttribute("Climbing") ~= true then
		return false, "you need to be on the wall"
	end
	if #tie.pieces >= ROPE.Quickdraws then
		return false, "no quickdraws left"
	end
	local up = Vector3.yAxis - normal * normal:Dot(Vector3.yAxis)
	up = if up.Magnitude > 0.1 then up.Unit else normal:Cross(Vector3.xAxis).Unit
	local folder: Instance? = tie.route:FindFirstChild("Protection")
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = "Protection"
		created.Parent = tie.route
		folder = created
	end
	local model, ropeAt = Hardware.quickdraw(folder :: Instance, BuildUtil.frameAt(position, normal, up), Color3.fromRGB(240, 110, 40))
	model.Name = `Quickdraw_{player.UserId}_{#tie.pieces + 1}`
	local holder = BuildUtil.part({ name = "RopeRun", size = Vector3.new(0.1, 0.1, 0.1), cframe = CFrame.new(ropeAt), surface = "BoltHead", parent = model })
	holder.Transparency = 1
	local at = Instance.new("Attachment")
	at.Name = "Rope"
	at.Parent = holder
	-- The rope below now runs from the last piece (or the bag) up to this one.
	local runner = Instance.new("RopeConstraint")
	runner.Name = "Runner"
	runner.Attachment0 = tie.anchor
	runner.Attachment1 = at
	runner.Visible = true
	runner.Thickness = tie.rope.Thickness
	runner.Color = tie.rope.Color
	runner.Length = (tie.anchor.WorldPosition - at.WorldPosition).Magnitude + 0.4
	runner.Parent = holder

	tie.anchor = at
	tie.rope.Attachment0 = at
	tie.rope.Length = ropeDistance(tie) + ROPE.Slack + tie.extra
	tie.rope.WinchTarget = tie.rope.Length
	table.insert(tie.pieces, { model = model, at = at })
	setAttribute(tie.character, "Unprotected", nil)
	gesture(tie.character, "Clip")
	return true, nil
end

function RopeService.PiecesPlaced(player: Player): number
	local tie = ties[player]
	return if tie then #tie.pieces else 0
end

-- The rope comes tight: freeze its length (you drop the slack), then let it stretch.
local function catch(tie: Tie)
	if not protects(tie) then
		return -- lead with nothing clipped: the rope can't hold you
	end
	tie.rope.WinchTarget = tie.rope.Length
	tie.stretched = false
	tie.manual = false
	tie.hangFor = ROPE.HangSeconds
	setMode(tie, "caught")
end

-- R: sit back on the rope and be lowered (climbing), back to a steady lower (hanging), or
-- back over the edge to rappel down (standing on the top).
function RopeService.Lower(player: Player)
	local tie = ties[player]
	local character = player.Character
	if tie == nil or character == nil or not protects(tie) then
		return
	end
	if character:GetAttribute("Climbing") == true then
		tie.rope.WinchSpeed = ROPE.TakeSpeed
		tie.rope.WinchTarget = ropeDistance(tie) + 0.2
		tie.manual = false
		tie.hangFor = ROPE.HangSeconds
		setMode(tie, "hanging")
		ClimbService.ForceOff(player, "Take")
	elseif tie.mode == "hanging" or tie.mode == "lowering" then
		tie.manual = false
		tie.rope.WinchSpeed = ROPE.LowerSpeed
		tie.rope.WinchTarget = tie.rope.Length + 5000
		setMode(tie, "lowering")
	elseif tie.mode == "climb" then
		local baseY = tie.route:GetAttribute("BaseY")
		local root = tie.tieAttachment.Parent :: BasePart
		if type(baseY) == "number" and root.Position.Y > baseY + 8 then
			-- On the top: the client walks you back over the edge, then you rappel.
			tie.rope.WinchSpeed = ROPE.TakeSpeed
			tie.rope.WinchTarget = ropeDistance(tie) + 1.5
			tie.manual = false
			tie.hangFor = ROPE.HangSeconds + 1.2
			setMode(tie, "hanging")
		end
	end
end

-- Held T (-1) / Y (+1) / released (0).
function RopeService.Feed(player: Player, direction: number)
	local tie = ties[player]
	if tie == nil then
		return
	end
	tie.feed = math.clamp(math.round(direction), -1, 1)
	if tie.feed ~= 0 and (tie.mode == "hanging" or tie.mode == "lowering") then
		tie.manual = true
	end
end

local function backOnWall(tie: Tie)
	tie.rope.WinchSpeed = ROPE.TakeInSpeed
	tie.rope.WinchTarget = ropeDistance(tie) + ROPE.Slack + tie.extra
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
		if player.Character ~= character or character.Parent == nil or humanoid == nil or humanoid.Health <= 0 or tie.tieAttachment.Parent == nil or (tie.bag ~= nil and tie.bag.Parent == nil) then
			RopeService.Untie(player)
			continue
		end
		local rope = tie.rope
		local root = tie.tieAttachment.Parent :: BasePart
		local climbing = character:GetAttribute("Climbing") == true
		local onGround = not climbing and grounded(character)

		if tie.mode == "climb" then
			if climbing or onGround then
				tie.climbed = tie.climbed or climbing
				-- The belayer follows you (climbing, or walking about on the top after
				-- climbing up onto it), with the slack you've asked for.
				tie.extra = math.clamp(tie.extra + tie.feed * ROPE.FeedSpeed * dt, ROPE.MinSlack - ROPE.Slack, ROPE.MaxSlack - ROPE.Slack)
				rope.WinchSpeed = ROPE.TakeInSpeed
				rope.WinchTarget = ropeDistance(tie) + ROPE.Slack + tie.extra
				setAttribute(character, "RopeSlack", math.round((ROPE.Slack + tie.extra) * 10) / 10)
			elseif tie.climbed and root.AssemblyLinearVelocity.Y < -14 then
				catch(tie) -- walked off an edge, or fell from a ledge
			end
			-- Auto-belays unclip you once you're back on the floor after a climb; walking
			-- away unties you.
			tie.groundFor = if onGround then tie.groundFor + dt else 0
			local start = tie.route:GetAttribute("StartPosition")
			local far = typeof(start) == "Vector3" and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude > ROPE.UntieDistance
			if (tie.auto and tie.climbed and tie.groundFor > 1.5) or (onGround and far and root.Position.Y < (start :: Vector3).Y + 6) then
				RopeService.Untie(player)
			end
		elseif tie.mode == "caught" then
			-- The rope comes tight: a dynamic rope gives a little as it takes your weight.
			if not tie.stretched and ropeDistance(tie) >= rope.Length - 0.15 then
				tie.stretched = true
				rope.WinchSpeed = ROPE.StretchSpeed
				rope.WinchTarget = rope.Length + math.min(ROPE.CatchStretchMax, rope.Length * ROPE.CatchStretch)
			end
			if now - tie.since >= ROPE.CaughtSeconds then
				rope.WinchTarget = rope.Length
				setMode(tie, "hanging")
			end
		elseif tie.mode == "hanging" then
			if tie.manual then
				if tie.feed > 0 then
					rope.WinchSpeed = ROPE.LowerSpeed
					rope.WinchTarget = rope.Length + 5000
					setMode(tie, "lowering")
				elseif tie.feed < 0 then
					rope.WinchSpeed = ROPE.HaulSpeed
					rope.WinchTarget = math.max(1.5, rope.Length - 50)
				else
					rope.WinchTarget = rope.Length
				end
			elseif now - tie.since >= tie.hangFor then
				-- Lower: the winch pays out steadily.
				rope.WinchSpeed = ROPE.LowerSpeed
				rope.WinchTarget = rope.Length + 5000
				setMode(tie, "lowering")
			end
		elseif tie.mode == "lowering" then
			if onGround then
				rope.WinchTarget = rope.Length
				tie.climbed = true
				tie.manual = false
				setMode(tie, "climb")
			elseif tie.manual then
				if tie.feed > 0 then
					rope.WinchSpeed = ROPE.FastLowerSpeed
					rope.WinchTarget = rope.Length + 5000
				elseif tie.feed < 0 then
					rope.WinchTarget = rope.Length
					setMode(tie, "hanging") -- stopped; keep T held to haul up
				else
					rope.WinchTarget = rope.Length -- stopped where you let go of Y
				end
			end
		end
	end
end

local function onClick(clicker: ClickDetector, player: Player)
	local character = player.Character
	if character and character:GetAttribute("Climbing") == true then
		return -- no untying mid-climb
	end
	local routes = Workspace:FindFirstChild("Routes")
	local holder = clicker.Parent
	-- A dropped rope bag knows its route; an auto-belay carabiner sits inside it.
	local route: Instance? = nil
	local bag: BasePart? = nil
	if holder and holder:IsA("BasePart") and holder:GetAttribute("RouteId") ~= nil then
		local owner = holder:GetAttribute("Owner")
		if owner ~= player.UserId then
			return
		end
		bag = holder
		local id = holder:GetAttribute("RouteId")
		route = if routes and type(id) == "string" then routes:FindFirstChild(id) else nil
	else
		route = holder
		while route and route:GetAttribute("RouteName") == nil do
			route = route.Parent
		end
	end
	if route == nil then
		return
	end
	local tie = ties[player]
	if tie and tie.route == route then
		RopeService.Untie(player)
	else
		RopeService.TieIn(player, route, clicker.Name == "ClipIn", bag)
	end
end

function RopeService.IsTiedIn(player: Player): boolean
	return ties[player] ~= nil
end

-- Is `bag` the rope someone is tied in with (PackService won't pack it up then)?
function RopeService.BagInUse(bag: Instance): boolean
	for _, tie in ties do
		if tie.bag == bag then
			return true
		end
	end
	return false
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
	for _, name in { "Routes", "PlacedGear" } do
		task.spawn(function()
			local folder = Workspace:WaitForChild(name, 30)
			if folder then
				for _, descendant in folder:GetDescendants() do
					watch(descendant)
				end
				folder.DescendantAdded:Connect(watch)
			end
		end)
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
