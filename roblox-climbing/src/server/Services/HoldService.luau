--!strict
-- HoldService (server): the authoritative registry of every hold in the game.
--
--  * Finds every part tagged "Hold" (now and later, e.g. Wall Builder/Kilter in Stage 8).
--  * Cleans up its attributes so the rest of the game can trust them: valid HoldType,
--    Quality clamped to 0..1, HandOK/FootOK filled from the type, a unique HoldId,
--    Anchored, and a "Grip" attachment.
--  * Answers lookups the climbing code needs: by id, and "which holds are near here".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HoldTypes = require(Shared.HoldTypes)
local HoldUtil = require(Shared.HoldUtil)
local Tags = require(Shared.Tags)

local HoldService = {}

local holdsById: { [string]: BasePart? } = {}
local idByHold: { [BasePart]: string } = {}
local nextAutoId = 0

local function makeId(part: BasePart): string
	local route = HoldUtil.getRouteFolder(part)
	local prefix = if route then route.Name else "Hold"
	repeat
		nextAutoId += 1
	until holdsById[`{prefix}_{nextAutoId}`] == nil
	return `{prefix}_{nextAutoId}`
end

local function ensureGrip(part: BasePart)
	if part:FindFirstChild(HoldUtil.GRIP_ATTACHMENT) then
		return
	end
	local grip = Instance.new("Attachment")
	grip.Name = HoldUtil.GRIP_ATTACHMENT
	-- Front face centre, facing out of the wall (see HoldUtil authoring rules).
	grip.CFrame = CFrame.new(0, 0, -part.Size.Z / 2)
	grip.Parent = part
end

local function sanitize(part: BasePart)
	local typeName = part:GetAttribute("HoldType")
	if not HoldTypes.isValid(typeName) then
		warn(`[HoldService] {part:GetFullName()} has invalid HoldType {tostring(typeName)}; using {HoldTypes.DEFAULT_TYPE}`)
		part:SetAttribute("HoldType", HoldTypes.DEFAULT_TYPE)
	end

	-- HoldUtil.read fills every missing value from the type defaults; write them back so
	-- the attributes shown in Studio are what the game actually uses.
	local info = HoldUtil.read(part) :: HoldUtil.HoldInfo
	part:SetAttribute("Quality", info.Quality)
	part:SetAttribute("HandOK", info.HandOK)
	part:SetAttribute("FootOK", info.FootOK)

	part.Anchored = true
	ensureGrip(part)
end

local function register(instance: Instance)
	if not instance:IsA("BasePart") then
		warn(`[HoldService] {instance:GetFullName()} is tagged {Tags.Hold} but is not a BasePart; ignored`)
		return
	end
	local part = instance :: BasePart
	if idByHold[part] then
		return
	end

	sanitize(part)

	local id = part:GetAttribute("HoldId")
	if type(id) ~= "string" or id == "" or holdsById[id] ~= nil then
		if type(id) == "string" and holdsById[id] ~= nil then
			warn(`[HoldService] duplicate HoldId {id} on {part:GetFullName()}; assigning a new one`)
		end
		id = makeId(part)
		part:SetAttribute("HoldId", id)
	end

	holdsById[id :: string] = part
	idByHold[part] = id :: string
end

local function unregister(instance: Instance)
	local part = instance :: BasePart
	local id = idByHold[part]
	if id then
		idByHold[part] = nil
		holdsById[id] = nil
	end
end

function HoldService.Init()
	CollectionService:GetInstanceAddedSignal(Tags.Hold):Connect(register)
	CollectionService:GetInstanceRemovedSignal(Tags.Hold):Connect(unregister)
	for _, instance in CollectionService:GetTagged(Tags.Hold) do
		register(instance)
	end
end

function HoldService.Start()
	print(`[HoldService] {HoldService.Count()} holds registered`)
end

function HoldService.Count(): number
	local n = 0
	for _ in holdsById do
		n += 1
	end
	return n
end

function HoldService.GetHold(id: string): BasePart?
	return holdsById[id]
end

function HoldService.GetHoldInfo(part: BasePart): HoldUtil.HoldInfo?
	if idByHold[part] == nil then
		return nil
	end
	return HoldUtil.read(part)
end

-- Holds whose grip point is within `radius` of `position`, nearest first.
-- Optional `limbKind` keeps only holds that limb may use. A linear scan is fine for the
-- few hundred holds near a player; Stage 8 can swap in a spatial grid if needed.
function HoldService.GetHoldsNear(position: Vector3, radius: number, limbKind: ("Hand" | "Foot")?): { HoldUtil.HoldInfo }
	local found: { { info: HoldUtil.HoldInfo, distance: number } } = {}
	for part in idByHold do
		local distance = (HoldUtil.getGripCFrame(part).Position - position).Magnitude
		if distance <= radius then
			local info = HoldUtil.read(part)
			if info and (limbKind == nil or HoldUtil.accepts(info, limbKind)) then
				table.insert(found, { info = info, distance = distance })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local result = table.create(#found)
	for i, entry in found do
		result[i] = entry.info
	end
	return result
end

return HoldService
