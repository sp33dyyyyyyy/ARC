--!strict
-- RopeMotion (client): procedural animations for being on the rope, and short gestures.
-- No animation assets: everything is posed with ClimbAnimator's IK, so it works on R6 and
-- R15 and on every character on screen (other players included).
--
-- On the rope (the character's "RopeMode" attribute, from RopeService):
--   Caught    the jolt: arms flail up for the rope, legs swing loose
--   Hanging   sitting back in the harness: one hand high on the rope, the brake hand low,
--             feet braced flat on the wall
--   Lowering  leaning back and walking down the wall, step by step, the brake hand
--             feeding rope
-- The owning client also steers its own body while hanging and lowering: leaning back
-- from the wall at the right distance for the feet to reach it (control()).
--
-- Gestures (the "Gesture" attribute, "Name@n", set by the server):
--   Chalk   a dip into the chalk bag behind each hip, then a clap
--   Clip    both hands to the harness, clipping the carabiner
--   Summit  both arms up, fist-pumping
--   Mantle  climbing up over an edge: hands on the lip in front, then pushing down
--   Press   a hand out to press the finish button

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClimbMath = require(Shared:WaitForChild("ClimbMath"))

local ClimbAnimator = require(script.Parent:WaitForChild("ClimbAnimator"))

local RopeMotion = {}

local STEP = 1.7 -- studs of descent per walking step while lowering
local CAUGHT_FLAIL = 0.9 -- seconds of flailing after a catch

type Wall = { point: Vector3, normal: Vector3, at: number }
type Watch = { mode: string?, since: number, gesture: string?, gestureAt: number }

local walls: { [Model]: Wall } = setmetatable({}, { __mode = "k" }) :: any
local watches: { [Model]: Watch } = setmetatable({}, { __mode = "k" }) :: any
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function watchFor(character: Model): Watch
	local watch = watches[character]
	if watch == nil then
		watch = { mode = nil, since = os.clock(), gesture = nil, gestureAt = 0 }
		watches[character] = watch
	end
	return watch :: Watch
end

-- The route the character is tied in to, and where its rope comes from.
local function ropeInfo(character: Model): (Instance?, Vector3?)
	local routeId = character:GetAttribute("TiedIn")
	local routes = Workspace:FindFirstChild("Routes")
	local route = if type(routeId) == "string" and routes then routes:FindFirstChild(routeId) else nil
	if route == nil then
		return nil, nil
	end
	local unit = route:FindFirstChild("AutoBelay")
	local housing = unit and unit:FindFirstChild("Unit")
	if route:GetAttribute("AutoBelay") == true and housing and housing:IsA("BasePart") then
		return route, housing.Position
	end
	local anchor = route:GetAttribute("TopAnchor")
	return route, if typeof(anchor) == "Vector3" then anchor else nil
end

-- The wall in front of the character (cached briefly): a point on it at body height, and
-- its normal. Nil when there's no wall to put your feet on (hanging under a roof).
local function wallFor(character: Model, root: BasePart, route: Instance, anchor: Vector3): Wall?
	local now = os.clock()
	local cached = walls[character]
	if cached and now - cached.at < 0.15 then
		return cached
	end
	local start = route:GetAttribute("StartPosition")
	local guess = if typeof(start) == "Vector3" then Vector3.new(start.X - anchor.X, 0, start.Z - anchor.Z) else -root.CFrame.LookVector
	if guess.Magnitude < 1e-3 then
		guess = -root.CFrame.LookVector
	end
	guess = guess.Unit
	rayParams.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position + guess * 0.5, -guess * 7, rayParams)
	if hit == nil then
		walls[character] = nil
		return nil
	end
	local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	normal = if normal.Magnitude > 0.2 then normal.Unit else guess
	local wall = { point = hit.Position, normal = normal, at = now }
	walls[character] = wall
	return wall
end

-- Gesture keyframes: hand offsets in the root part's space (+X right, +Y up, +Z back).
type Key = { from: number, to: number, hands: { [string]: Vector3 } }
local GESTURES: { [string]: { duration: number, keys: { Key } } } = {
	Chalk = {
		duration = 1.35,
		keys = {
			{ from = 0.05, to = 0.5, hands = { RightHand = Vector3.new(0.55, -1.0, 0.75) } },
			{ from = 0.5, to = 0.85, hands = { LeftHand = Vector3.new(0.2, -1.0, 0.8), RightHand = Vector3.new(0.35, 0.0, -0.9) } },
			{ from = 0.85, to = 1.3, hands = { LeftHand = Vector3.new(-0.05, 0.25, -1.05), RightHand = Vector3.new(0.05, 0.25, -1.05) } },
		},
	},
	Clip = {
		duration = 0.9,
		keys = {
			{ from = 0.05, to = 0.85, hands = { LeftHand = Vector3.new(-0.12, -0.75, -0.75), RightHand = Vector3.new(0.18, -0.7, -0.75) } },
		},
	},
	Mantle = {
		duration = 1.4,
		keys = {
			{ from = 0, to = 0.6, hands = { LeftHand = Vector3.new(-0.75, 0.9, -1.2), RightHand = Vector3.new(0.75, 0.9, -1.2) } },
			{ from = 0.6, to = 1.3, hands = { LeftHand = Vector3.new(-0.75, -0.4, -1.0), RightHand = Vector3.new(0.75, -0.4, -1.0) } },
		},
	},
	Press = {
		duration = 0.7,
		keys = {
			{ from = 0.05, to = 0.6, hands = { RightHand = Vector3.new(0.35, 0.1, -1.6) } },
		},
	},
	Summit = {
		duration = 2.4,
		keys = {
			{ from = 0.1, to = 2.3, hands = { LeftHand = Vector3.new(-0.75, 2.1, -0.3), RightHand = Vector3.new(0.75, 2.1, -0.3) } },
		},
	},
}

local function gestureIntent(character: Model, root: BasePart, watch: Watch, now: number): ClimbAnimator.Intent?
	local value = character:GetAttribute("Gesture")
	if type(value) ~= "string" then
		return nil
	end
	if value ~= watch.gesture then
		watch.gesture = value
		watch.gestureAt = now
	end
	local name = string.match(value, "^(%a+)@")
	local def = name and GESTURES[name]
	if def == nil then
		return nil
	end
	local t = now - watch.gestureAt
	if t > def.duration then
		return nil
	end
	local targets: { [string]: Vector3? } = {}
	for _, key in def.keys do
		if t >= key.from and t <= key.to then
			for limb, offset in key.hands do
				local wobble = if name == "Summit" then Vector3.new(0, math.sin(t * 11) * 0.28, 0) elseif name == "Chalk" and t > 0.85 then Vector3.new(math.sin(t * 40) * 0.08, 0, 0) else Vector3.zero
				targets[limb] = root.CFrame * (offset + wobble)
			end
		end
	end
	if next(targets) == nil then
		return nil
	end
	return {
		climbing = false,
		normal = -root.CFrame.LookVector,
		targets = targets,
		look = if name == "Summit" then root.Position + Vector3.yAxis * 6 - root.CFrame.LookVector * 2 else nil,
		charge = 0,
	}
end

local function ropeIntent(character: Model, root: BasePart, mode: string, watch: Watch, now: number, floorY: number?): ClimbAnimator.Intent?
	local route, anchor = ropeInfo(character)
	if route == nil or anchor == nil then
		return nil
	end
	local harness = root.CFrame * Vector3.new(0, -0.6, -0.45)
	local up = anchor - harness
	if up.Magnitude < 0.5 then
		return nil
	end
	up = up.Unit
	local wall = wallFor(character, root, route, anchor)
	local normal = if wall then wall.normal else -root.CFrame.LookVector
	local right = ClimbMath.wallAxes(normal)
	local t = now - watch.since
	local targets: { [string]: Vector3? } = {}
	local look: Vector3

	if mode == "Caught" and t < CAUGHT_FLAIL then
		-- The jolt: grab for the rope above, arms flailing; legs swing free.
		local seed = root.Position.X * 0.37
		local flail = math.max(0, 1 - t / CAUGHT_FLAIL)
		targets.LeftHand = harness + up * 1.9 - right * 0.45 + Vector3.new(math.noise(t * 7, seed), math.noise(seed, t * 7), 0) * flail * 0.9
		targets.RightHand = harness + up * 1.4 + right * 0.45 + Vector3.new(math.noise(t * 7 + 5, seed), math.noise(seed + 5, t * 7), 0) * flail * 0.9
		look = harness + up * 4
	else
		-- On the rope: guide hand high, brake hand low by the hip.
		local feed = if mode == "Lowering" then math.sin(t * 5) * 0.18 else 0
		targets.LeftHand = harness + up * 1.55 - right * 0.1
		targets.RightHand = harness + up * (0.5 + feed) + right * 0.28 + normal * 0.1
		look = if mode == "Lowering" then root.Position - Vector3.yAxis * 6 + normal * 3 else harness + up * 3
		if wall then
			-- Feet flat on the wall below the hips.
			local base = Vector3.new(wall.point.X, root.Position.Y, wall.point.Z) + normal * 0.15
			if mode == "Lowering" then
				-- Walking down: each foot lifts off, swings down and plants again in turn.
				local phase = -root.Position.Y / STEP
				local feet: { [string]: number } = { LeftFoot = 0, RightFoot = 0.5 }
				for limb, offset in feet do
					local p = (phase + offset) % 1
					local side = if limb == "LeftFoot" then -0.45 else 0.45
					local foot: Vector3
					if p < 0.35 then
						local swing = p / 0.35
						foot = base + right * side + Vector3.yAxis * (-1.0 - swing * 0.9) + normal * (math.sin(swing * math.pi) * 0.7)
					else
						foot = base + right * side + Vector3.yAxis * (-1.9 + (p - 0.35) / 0.65 * 0.9)
					end
					targets[limb] = foot
				end
			else
				targets.LeftFoot = base - right * 0.5 + Vector3.yAxis * -1.75
				targets.RightFoot = base + right * 0.5 + Vector3.yAxis * -1.35
			end
		end
	end
	return {
		climbing = true,
		normal = normal,
		targets = targets,
		look = look,
		charge = 0,
		fatigue = 0,
		floorY = floorY,
	}
end

-- What `character` should look like this frame because of the rope or a gesture (nil =
-- nothing to do). `floorY` keeps dangling feet out of the floor.
function RopeMotion.intent(character: Model, floorY: number?): ClimbAnimator.Intent?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local now = os.clock()
	local watch = watchFor(character)
	local mode = character:GetAttribute("RopeMode")
	local modeName = if type(mode) == "string" then mode else nil
	if modeName ~= watch.mode then
		watch.mode = modeName
		watch.since = now
	end
	if modeName then
		return ropeIntent(character, root, modeName, watch, now, floorY)
	end
	return gestureIntent(character, root, watch, now)
end

---------------------------------------------------------------------------------------
-- Steering this player's own body on the rope

local lean: AlignOrientation? = nil
local stand: AlignPosition? = nil
local active = false

local function ensureControls(root: BasePart)
	if lean and lean.Parent == root and stand and stand.Parent == root then
		return
	end
	local attachment = root:FindFirstChild("RopeMotionAttachment") :: Attachment?
	if attachment == nil then
		local created = Instance.new("Attachment")
		created.Name = "RopeMotionAttachment"
		created.Parent = root
		attachment = created
	end
	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "RopeLean"
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.MaxTorque = 20000
	orientation.Responsiveness = 8
	orientation.Enabled = false
	orientation.Parent = root
	local position = Instance.new("AlignPosition")
	position.Name = "RopeStand"
	position.Mode = Enum.PositionAlignmentMode.OneAttachment
	position.Attachment0 = attachment
	position.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	position.MaxAxesForce = Vector3.new(3000, 0, 3000) -- sideways only: the rope holds the weight
	position.Responsiveness = 10
	position.Enabled = false
	position.Parent = root
	lean, stand = orientation, position
end

-- Called every frame for this player's character. Leans the body back from the wall
-- while hanging and lowering, with the hips the right distance out for the feet to reach.
-- Returns true while the rope has the body (the climbing code leaves it alone).
function RopeMotion.control(character: Model, root: BasePart, humanoid: Humanoid, climbing: boolean): boolean
	local mode = character:GetAttribute("RopeMode")
	local onRope = type(mode) == "string" and not climbing and humanoid.Health > 0 and character:GetAttribute("Ragdolled") ~= true
	ensureControls(root)
	local orientation, position = lean :: AlignOrientation, stand :: AlignPosition
	if not onRope then
		if active then
			active = false
			orientation.Enabled = false
			position.Enabled = false
			if not climbing and humanoid.Health > 0 then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
		return false
	end
	active = true
	humanoid.PlatformStand = true -- no running/falling animations while on the rope
	local route, anchor = ropeInfo(character)
	local wall = if route and anchor then wallFor(character, root, route, anchor) else nil
	if mode == "Caught" or wall == nil then
		orientation.Enabled = false
		position.Enabled = false
		return true
	end
	local leanBack = if mode == "Lowering" then 42 else 28
	local standOff = if mode == "Lowering" then 2.1 else 1.7
	local here = root.Position
	orientation.CFrame = CFrame.lookAt(here, here - wall.normal) * CFrame.Angles(math.rad(leanBack), 0, 0)
	position.Position = Vector3.new(wall.point.X, here.Y, wall.point.Z) + wall.normal * standOff
	orientation.Enabled = true
	position.Enabled = true
	return true
end

return RopeMotion
