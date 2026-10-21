--!strict
-- PropService (server): swaps the world's stand-in props for real Creator Store models
-- (see World/Props). Each asset is loaded once with AssetService:LoadAssetAsync (sandboxed:
-- no scripts run), cleaned up, then cloned into every slot that uses it, scaled to the
-- slot's size and stood on the floor. Slots whose model can't load keep their stand-in.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Props = require(script.Parent.Parent.World.Props)

local MAX_LIGHT_BRIGHTNESS = 1.2 -- models with their own lights mustn't glare

local PropService = {}

local templates: { [string]: Model | false } = {}
local loading: { [string]: boolean } = {}
local warned = false
local cache: Folder

-- Strips anything that shouldn't come along (scripts, sounds, spawns), anchors every part
-- and sets its collision.
local function clean(model: Model, entry: Props.Entry)
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("SpawnLocation") or d:IsA("Humanoid") or d:IsA("ClickDetector") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = entry.collide and d.Transparency < 1
			d.CanTouch = false
			d.CanQuery = entry.collide
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				(d :: any).Disabled = true
			end
		elseif d:IsA("Light") then
			d.Brightness = math.min(d.Brightness, MAX_LIGHT_BRIGHTNESS)
			d.Shadows = false
		end
	end
end

local function template(key: string): Model?
	while loading[key] do
		task.wait(0.1)
	end
	local cached = templates[key]
	if cached then
		return cached :: any
	elseif cached == false then
		return nil
	end
	loading[key] = true
	local entry = Props.LIBRARY[key]
	-- The model, or the next backup when one won't load.
	local result: Instance? = nil
	local lastError: any = nil
	for _, id in entry.ids do
		local ok, loaded = pcall(function()
			return AssetService:LoadAssetAsync(id)
		end)
		if ok and loaded and (loaded :: Instance):FindFirstChildWhichIsA("BasePart", true) then
			result = loaded
			break
		end
		lastError = loaded
		warn(`[PropService] "{entry.name}" model {id} didn't load ({loaded}); trying the next one`)
	end
	loading[key] = nil
	if result == nil then
		templates[key] = false
		if not warned then
			warned = true
			warn(`[PropService] couldn't load the Creator Store model "{entry.name}": {lastError}. The built-in stand-ins are used instead. To get the real models, turn on Game Settings > Security > "Allow Loading Third Party Assets" (the place must be published).`)
		end
		return nil
	end
	local model = Instance.new("Model")
	model.Name = key
	for _, child in (result :: Instance):GetChildren() do
		child.Parent = model
	end
	clean(model, entry)
	if model:FindFirstChildWhichIsA("BasePart", true) == nil then
		templates[key] = false
		return nil
	end
	model.Parent = cache
	templates[key] = model
	return model
end

-- Puts a copy of `source` in `slot`: facing the slot's way, scaled into its size, its
-- bottom on the floor (sunk a little for rocks).
local function fill(slot: Model, source: Model, entry: Props.Entry)
	local base = slot:GetAttribute("Base")
	local fit = slot:GetAttribute("FitSize")
	if typeof(base) ~= "CFrame" or typeof(fit) ~= "Vector3" then
		return
	end
	local model = source:Clone()
	-- Face the slot's way: the model's front is its pivot's -Z, flattened to the ground.
	local pivot = model:GetPivot()
	local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	model.WorldPivot = CFrame.lookAt(pivot.Position, pivot.Position + look.Unit)
	local turn = CFrame.Angles(0, math.rad(entry.yaw or 0), 0)
	model:PivotTo(CFrame.new(base.Position) * (base - base.Position) * turn)

	-- Scale to fit (keeping proportions), measured in the slot's own frame.
	local frame = CFrame.new(base.Position) * (base - base.Position) * turn
	local _, size = model:GetBoundingBox()
	local factor = math.min(fit.X / size.X, fit.Y / size.Y, fit.Z / size.Z)
	if factor > 0 and factor < math.huge then
		pcall(function()
			model:ScaleTo(model:GetScale() * factor)
		end)
	end
	-- Stand it on the floor: bottom of its box at the base point, centred over it.
	local box, boxSize = model:GetBoundingBox()
	local bottom = box.Position - Vector3.yAxis * (boxSize.Y / 2)
	local sink = (entry.sink or 0) * boxSize.Y
	local _ = frame
	model:PivotTo(model:GetPivot() + (base.Position - bottom) - Vector3.yAxis * sink)

	for _, child in slot:GetChildren() do
		child:Destroy()
	end
	for _, child in model:GetChildren() do
		child.Parent = slot
	end
	model:Destroy()
	slot:SetAttribute("Loaded", true)
end

local function dress(slot: Instance)
	if not slot:IsA("Model") or slot:GetAttribute("Loaded") then
		return
	end
	local key = slot:GetAttribute("AssetKey")
	local entry = if type(key) == "string" then Props.LIBRARY[key] else nil
	if entry == nil then
		return
	end
	local source = template(key :: string)
	if source then
		local ok, err = pcall(fill :: any, slot, source, entry)
		if not ok then
			warn(`[PropService] couldn't place {key}: {err}`)
		end
	end
end

-- How many slots have their real model (for Stage4Check / the README checklist).
function PropService.Stats(): (number, number)
	local loaded, total = 0, 0
	for _, slot in CollectionService:GetTagged(Props.TAG) do
		total += 1
		if slot:GetAttribute("Loaded") then
			loaded += 1
		end
	end
	return loaded, total
end

function PropService.Start()
	cache = Instance.new("Folder")
	cache.Name = "PropTemplates"
	cache.Parent = ServerStorage
	CollectionService:GetInstanceAddedSignal(Props.TAG):Connect(function(slot)
		task.spawn(dress, slot)
	end)
	-- Every kind of prop loads in parallel; then all its slots are filled.
	local byKey: { [string]: { Instance } } = {}
	for _, slot in CollectionService:GetTagged(Props.TAG) do
		local key = slot:GetAttribute("AssetKey")
		if type(key) == "string" then
			byKey[key] = byKey[key] or {}
			table.insert(byKey[key], slot)
		end
	end
	local pending = 0
	for _, slots in byKey do
		pending += 1
		task.spawn(function()
			for _, slot in slots do
				dress(slot)
			end
			pending -= 1
			if pending == 0 then
				local loaded, total = PropService.Stats()
				print(`[PropService] {loaded}/{total} props use Creator Store models`)
				for key, entry in Props.LIBRARY do
					if templates[key] == false then
						warn(`[PropService] still using the stand-in for "{entry.name}"`)
					end
				end
			end
		end)
	end
end

return PropService
