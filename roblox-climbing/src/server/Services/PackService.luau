--!strict
-- PackService (server): what's in your bag, and the things you put down.
--
--  * Pack at the gym lockers ("Pack bag"): choose what to carry (Shared/Pack), up to your
--    bag's capacity. The loadout saves (DataService "pack"); a heavier pack drains stamina
--    a little faster (StaminaService reads the PackWeight attribute).
--  * Put things down ("Place"): the rope bag at a route's base (click it to tie in,
--    RopeService), crash pads, a spare chalk bag. Each has a "Pack up" prompt (X) for its
--    owner. Everything you put down is cleared when you leave.
--  * Use ("Use"): clip a quickdraw beside your top hand on a lead route (RopeService.Clip),
--    or drink water (+stamina, not mid-climb).
--  * Every chalk bucket on the ground (gym and crags) is shown as a real catalog chalk
--    bag, the same accessories climbers wear (ShopService.loadAccessory).
--
-- Player attributes: Pack_<id> (packed), Have_<id> (ready to use now), PackWeight,
-- PackCapacity.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Gear)
local HoldUtil = require(Shared.HoldUtil)
local Pack = require(Shared.Pack)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)

local BuildUtil = require(script.Parent.Parent.World.BuildUtil)
local DataService = require(script.Parent.DataService)
local HoldService = require(script.Parent.HoldService)
local RopeService = require(script.Parent.RopeService)
local ShopService = require(script.Parent.ShopService)
local StaminaService = require(script.Parent.StaminaService)

local LOCKER_REACH = 16
local SPACING = 2.2 -- things put down keep this far apart

local PackService = {}

type State = { placed: { [Model]: string }, water: number }

local states: { [Player]: State } = {}
local resultRemote: RemoteEvent
local folder: Folder
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true
local rockParams = RaycastParams.new()
rockParams.FilterType = Enum.RaycastFilterType.Include

local function stateFor(player: Player): State
	local state = states[player]
	if state == nil then
		local data = DataService.Get(player)
		state = { placed = {}, water = if data then data.pack.Water or 0 else 0 }
		states[player] = state
	end
	return state :: State
end

local function reply(player: Player, ok: boolean, message: string)
	resultRemote:FireClient(player, ok, message)
end

local function packed(player: Player): { [string]: number }
	local data = DataService.Get(player)
	return if data then data.pack else {}
end

local function placedCount(state: State, id: string): number
	local n = 0
	for _, placedId in state.placed do
		if placedId == id then
			n += 1
		end
	end
	return n
end

-- How many of `id` are ready to use now.
local function have(player: Player, id: string): number
	local state = stateFor(player)
	local count = packed(player)[id] or 0
	if id == "Water" then
		return math.min(count, state.water)
	elseif id == "Quickdraws" then
		return count - RopeService.PiecesPlaced(player)
	end
	return count - placedCount(state, id)
end

local function capacityOf(player: Player): number
	local equipped = player:GetAttribute("Equip_Pack")
	return Pack.capacity(if type(equipped) == "string" then equipped else nil)
end

local function refresh(player: Player)
	local counts = packed(player)
	for _, item in Pack.ITEMS do
		player:SetAttribute(`Pack_{item.id}`, counts[item.id] or 0)
		player:SetAttribute(`Have_{item.id}`, math.max(0, have(player, item.id)))
	end
	player:SetAttribute("PackWeight", Pack.weight(counts))
	player:SetAttribute("PackCapacity", capacityOf(player))
end
PackService.Refresh = refresh

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

---------------------------------------------------------------------------------------
-- Models

local function packUpPrompt(holder: BasePart, name: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PackUp"
	prompt.ActionText = "Pack up"
	prompt.ObjectText = name
	prompt.KeyboardKeyCode = Enum.KeyCode.X
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 40)
	prompt.Parent = holder
end

local function ropeBag(model: Model, base: CFrame, color: Color3): BasePart
	local bag = BuildUtil.part({ name = "RopeBag", size = Vector3.new(0.7, 2.1, 2.1), cframe = base * CFrame.new(0, 0.35, 0) * BuildUtil.AXIS_Y, surface = "Tape", color = Color3.fromRGB(40, 42, 48), shape = Enum.PartType.Cylinder, query = true, parent = model })
	bag.Material = Enum.Material.Fabric
	-- The rope flaked on top of the open bag, in loose coils.
	for i = 1, 4 do
		local coil = BuildUtil.part({ name = "Coil", size = Vector3.new(0.16, 1.85 - i * 0.28, 1.85 - i * 0.28), cframe = base * CFrame.new(math.sin(i * 1.7) * 0.08, 0.72 + i * 0.1, math.cos(i * 1.7) * 0.08) * BuildUtil.AXIS_Y, surface = "Tape", color = color, shape = Enum.PartType.Cylinder, shadow = false, parent = model })
		coil.Material = Enum.Material.Fabric
	end
	-- The tarp it sits on.
	local tarp = BuildUtil.part({ name = "Tarp", size = Vector3.new(3.4, 0.05, 3.0), cframe = base * CFrame.new(0, 0.025, 0), surface = "Tape", color = Color3.fromRGB(200, 70, 50), shadow = false, parent = model })
	tarp.Material = Enum.Material.Fabric
	local click = Instance.new("ClickDetector")
	click.Name = "TieIn"
	click.MaxActivationDistance = 14
	click.Parent = bag
	return bag
end

local function crashPad(model: Model, base: CFrame): BasePart
	local size = Vector3.new(4.2, 1.0, 3.3)
	local pad = BuildUtil.part({ name = "CrashPad", size = size, cframe = base * CFrame.new(0, size.Y / 2, 0), surface = "Tape", color = Color3.fromRGB(44, 48, 56), collide = true, query = true, parent = model })
	pad.Material = Enum.Material.Fabric
	CollectionService:AddTag(pad, Tags.CrashMat)
	-- Coloured top panels with the hinge seam between them, straps round the side.
	for _, side in { -1, 1 } do
		local panel = BuildUtil.part({ name = "Panel", size = Vector3.new(size.X / 2 - 0.12, 0.04, size.Z - 0.2), cframe = base * CFrame.new(side * size.X / 4, size.Y + 0.02, 0), surface = "Tape", color = Color3.fromRGB(240, 120, 40), shadow = false, parent = model })
		panel.Material = Enum.Material.Fabric
		local strap = BuildUtil.part({ name = "Strap", size = Vector3.new(0.25, size.Y + 0.06, size.Z + 0.06), cframe = base * CFrame.new(side * size.X * 0.32, size.Y / 2, 0), surface = "Tape", color = Color3.fromRGB(24, 24, 28), shadow = false, parent = model })
		strap.Material = Enum.Material.Fabric
	end
	return pad
end

-- A chalk bag standing on the ground at `base`: the catalog accessory's mesh, upright and
-- a bit bigger than worn, or a simple drawstring bag if it can't be loaded.
function PackService.chalkBag(parent: Instance, base: CFrame, look: number): BasePart
	local variant = Gear.CHALK_BAGS[(look - 1) % #Gear.CHALK_BAGS + 1]
	local accessory = ShopService.loadAccessory(variant.asset)
	local handle = accessory and accessory:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		local bag = handle:Clone()
		bag.Name = "ChalkBag"
		for _, d in bag:GetChildren() do
			if not (d:IsA("SpecialMesh") or d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture")) then
				d:Destroy()
			end
		end
		local scale = 1.8
		local mesh = bag:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			mesh.Scale *= scale
		end
		bag.Size *= scale
		bag.Anchored = true
		bag.CanCollide = false
		bag.CanTouch = false
		bag.CanQuery = true
		bag.Massless = true
		local height = if mesh then bag.Size.Y else bag.Size.Y
		bag.CFrame = base * CFrame.new(0, height / 2, 0)
		bag.Parent = parent
		if accessory then
			accessory:Destroy()
		end
		return bag
	end
	if accessory then
		accessory:Destroy()
	end
	local bag = BuildUtil.part({ name = "ChalkBag", size = Vector3.new(0.9, 1.0, 0.9), cframe = base * CFrame.new(0, 0.5, 0) * BuildUtil.AXIS_Y, surface = "Tape", color = variant.color, shape = Enum.PartType.Cylinder, query = true, parent = parent })
	bag.Material = Enum.Material.Fabric
	BuildUtil.part({ name = "Chalk", size = Vector3.new(0.04, 0.8, 0.8), cframe = base * CFrame.new(0, 1.0, 0) * BuildUtil.AXIS_Y, surface = "Chalk", shape = Enum.PartType.Cylinder, shadow = false, parent = parent }).Transparency = 0
	return bag
end

local function chalkPrompt(holder: BasePart, object: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChalkUp"
	prompt.ActionText = "Chalk up"
	prompt.ObjectText = object
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = holder
end

-- The route a rope bag dropped at `position` belongs to: the nearest roped route whose
-- base is close.
local function routeNear(position: Vector3): Instance?
	local routes = Workspace:FindFirstChild("Routes")
	local best: Instance?, bestDistance = nil, Pack.ROUTE_REACH
	for _, route in (if routes then routes:GetChildren() else {}) do
		local spot = route:GetAttribute("RopeSpot") or route:GetAttribute("StartPosition")
		if route:GetAttribute("Rope") == true and typeof(spot) == "Vector3" and math.abs(spot.Y - position.Y) < 10 then
			local d = (Vector3.new(spot.X, 0, spot.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
			if d < bestDistance then
				best, bestDistance = route, d
			end
		end
	end
	return best
end

---------------------------------------------------------------------------------------
-- Requests

local function place(player: Player, id: string, position: any, facing: any)
	local item = Pack.item(id)
	local root = rootOf(player)
	local character = player.Character
	if item == nil or item.kind ~= "place" or root == nil or character == nil or typeof(position) ~= "Vector3" then
		return
	end
	if character:GetAttribute("Climbing") == true then
		return reply(player, false, "Get off the wall first")
	end
	if have(player, id) <= 0 then
		return reply(player, false, `No {string.lower(item.name)} in your pack`)
	end
	if (position - root.Position).Magnitude > Pack.PLACE_REACH then
		return reply(player, false, "Too far away")
	end
	floorParams.FilterDescendantsInstances = { folder, character }
	local floor = Workspace:Raycast(position + Vector3.yAxis * 3, Vector3.yAxis * -8, floorParams)
	if floor == nil or floor.Normal.Y < 0.75 then
		return reply(player, false, "Put it on flat ground")
	end
	local at = floor.Position
	for _, other in folder:GetChildren() do
		if other:IsA("Model") and (other:GetPivot().Position - at).Magnitude < SPACING then
			return reply(player, false, "Too close to something else")
		end
	end
	local route = if id == "Rope" then routeNear(at) else nil
	if id == "Rope" and route == nil then
		return reply(player, false, "Drop the rope at the base of an outdoor route")
	end
	local flat = if typeof(facing) == "Vector3" then Vector3.new(facing.X, 0, facing.Z) else Vector3.zero
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	local base = CFrame.lookAt(at, at + flat.Unit)

	local model = Instance.new("Model")
	model.Name = `{id}_{player.UserId}`
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Item", id)
	local holder: BasePart
	if id == "Rope" then
		local color = player:GetAttribute("GearRopeColor")
		holder = ropeBag(model, base, if typeof(color) == "Color3" then color else Color3.fromRGB(245, 205, 40))
		holder:SetAttribute("Owner", player.UserId)
		holder:SetAttribute("RouteId", (route :: Instance).Name)
	elseif id == "CrashPad" then
		holder = crashPad(model, base)
	else
		local look = player:GetAttribute("ChalkColor")
		holder = PackService.chalkBag(model, base, if type(look) == "number" then look else 1)
		chalkPrompt(holder, `{player.DisplayName}'s chalk`)
	end
	packUpPrompt(holder, item.name)
	model.Parent = folder
	stateFor(player).placed[model] = id
	RopeService.gesture(character, "Drop")
	refresh(player)
	if id == "Rope" then
		reply(player, true, `Rope down for {(route :: Instance):GetAttribute("RouteName")}. Click it to tie in`)
	end
end

local function packUp(player: Player, model: Model)
	local state = states[player]
	if state == nil or state.placed[model] == nil then
		return
	end
	local root = rootOf(player)
	if root == nil or (root.Position - model:GetPivot().Position).Magnitude > 12 then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and RopeService.BagInUse(d) then
			return reply(player, false, "Untie from the rope first")
		end
	end
	state.placed[model] = nil
	model:Destroy()
	if player.Character then
		RopeService.gesture(player.Character, "Drop")
	end
	refresh(player)
end

-- A quickdraw beside your highest hand, bolted to the rock there.
local function clipQuickdraw(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	if have(player, "Quickdraws") <= 0 then
		return reply(player, false, "No quickdraws left. Pack more at the lockers")
	end
	local top: CFrame? = nil
	for _, limb in { "LeftHand", "RightHand" } do
		local id = character:GetAttribute("Climb_" .. limb)
		local hold = if type(id) == "string" then HoldService.GetHold(id) else nil
		if hold then
			local grip = HoldUtil.getGripCFrame(hold)
			if top == nil or grip.Position.Y > top.Position.Y then
				top = grip
			end
		end
	end
	if top == nil then
		return reply(player, false, "Get a hand on a hold first")
	end
	local crags = Workspace:FindFirstChild("Crags")
	if crags == nil then
		return
	end
	rockParams.FilterDescendantsInstances = { crags }
	-- Beside the hand and a little above, on the rock itself.
	for _, side in { 0.8, -0.8, 0 } do
		local spot = top.Position + top.RightVector * side + top.UpVector * 0.5
		local hit = Workspace:Raycast(spot + top.LookVector * 2.5, -top.LookVector * 5, rockParams)
		if hit then
			local ok, reason = RopeService.Clip(player, hit.Position, hit.Normal)
			if not ok then
				reply(player, false, `Can't clip: {reason}`)
			end
			refresh(player)
			return
		end
	end
	reply(player, false, "No rock to place it on here")
end

local function drink(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	if character:GetAttribute("Climbing") == true then
		return reply(player, false, "Can't drink mid-climb")
	end
	if have(player, "Water") <= 0 then
		return reply(player, false, "Out of water. Refill at the lockers")
	end
	local state = stateFor(player)
	state.water -= 1
	StaminaService.Give(player, Pack.WATER_STAMINA)
	RopeService.gesture(character, "Drink")
	refresh(player)
end

local function nearLockers(player: Player): boolean
	local root = rootOf(player)
	local gym = Workspace:FindFirstChild("Gym")
	local station = gym and gym:FindFirstChild("BagStation", true)
	return root ~= nil and station ~= nil and station:IsA("BasePart") and (root.Position - station.Position).Magnitude <= LOCKER_REACH
end

local function setPack(player: Player, counts: any)
	if not nearLockers(player) then
		return reply(player, false, "Pack your bag at the lockers")
	end
	local clean = Pack.sanitize(counts)
	local weight, capacity = Pack.weight(clean), capacityOf(player)
	if weight > capacity then
		return reply(player, false, `Too heavy: {weight} / {capacity}. A bigger bag carries more`)
	end
	local state = stateFor(player)
	for _, item in Pack.ITEMS do
		local out = if item.id == "Quickdraws" then RopeService.PiecesPlaced(player) else placedCount(state, item.id)
		if (clean[item.id] or 0) < out then
			return reply(player, false, `Pack up your {string.lower(item.name)} first`)
		end
	end
	DataService.Update(player, function(data)
		data.pack = clean
	end)
	state.water = clean.Water or 0
	refresh(player)
	reply(player, true, "Packed")
end

-- A smaller bag after switching packs: leave the heaviest extras at the lockers.
local function fitToBag(player: Player)
	local data = DataService.Get(player)
	if data == nil then
		return
	end
	local capacity = capacityOf(player)
	if Pack.weight(data.pack) <= capacity then
		refresh(player)
		return
	end
	DataService.Update(player, function(d)
		local counts = table.clone(d.pack)
		for i = #Pack.ITEMS, 1, -1 do
			local item = Pack.ITEMS[i]
			while (counts[item.id] or 0) > 0 and Pack.weight(counts) > capacity do
				counts[item.id] -= 1
			end
		end
		d.pack = Pack.sanitize(counts)
	end)
	refresh(player)
end

local function onRequest(player: Player, action: any, a: any, b: any, c: any)
	if action == "Set" then
		setPack(player, a)
	elseif action == "Place" and type(a) == "string" then
		place(player, a, b, c)
	elseif action == "Use" and a == "Quickdraws" then
		clipQuickdraw(player)
	elseif action == "Use" and a == "Water" then
		drink(player)
	end
end

local function clearPlayer(player: Player)
	local state = states[player]
	if state then
		for model in state.placed do
			model:Destroy()
		end
	end
	states[player] = nil
end

-- Every chalk bucket in the world (RouteKit.addChalkBucket) becomes a catalog chalk bag,
-- keeping its prompt. If the accessory can't load, the bucket stays.
local function dressBucket(bucket: BasePart, index: number)
	local base = CFrame.new(bucket.Position - Vector3.yAxis * (bucket.Size.X / 2)) * CFrame.Angles(0, index * 1.3, 0)
	local holder = Instance.new("Model")
	holder.Name = "ChalkBagStand"
	local bag = PackService.chalkBag(holder, base, index)
	if bag:IsA("BasePart") and bag:FindFirstChildOfClass("SpecialMesh") == nil and not bag:IsA("MeshPart") then
		holder:Destroy() -- only the stand-in: the bucket looks better
		return
	end
	holder.Parent = bucket.Parent
	for _, d in bucket:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
	bucket.Transparency = 1
	local prompt = bucket:FindFirstChild("ChalkUp")
	if prompt then
		prompt.Parent = bag
	end
end

function PackService.Init()
	resultRemote = Remotes.event("PackResult")
	local existing = Workspace:FindFirstChild("PlacedGear")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "PlacedGear"
		folder.Parent = Workspace
	end
end

function PackService.Start()
	Remotes.event("PackRequest").OnServerEvent:Connect(onRequest)
	DataService.OnLoaded(function(player, data)
		stateFor(player).water = data.pack.Water or 0
		refresh(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("Equip_Pack"):Connect(function()
			fitToBag(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player:GetAttributeChangedSignal("Equip_Pack"):Connect(function()
			fitToBag(player)
		end)
		refresh(player)
	end
	Players.PlayerRemoving:Connect(clearPlayer)
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, player)
		if prompt.Name ~= "PackUp" then
			return
		end
		local model: Model? = prompt:FindFirstAncestorWhichIsA("Model") :: any
		if model and model:IsDescendantOf(folder) and model:GetAttribute("Owner") == player.UserId then
			packUp(player, model)
		end
	end)
	-- Quickdraws come back when you untie (RopeService clears them): keep Have_ right.
	local function watchCharacter(player: Player, character: Model)
		character:GetAttributeChangedSignal("TiedIn"):Connect(function()
			refresh(player)
		end)
	end
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			watchCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	task.spawn(function()
		local index = 0
		for _, d in Workspace:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "ChalkBucket" then
				index += 1
				local ok, err = pcall(dressBucket :: any, d, index)
				if not ok then
					warn(`[PackService] chalk bag at {d:GetFullName()}: {err}`)
				end
			end
		end
	end)
end

return PackService
