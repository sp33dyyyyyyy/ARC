--!strict
-- HoldUtil: read a hold's data from its attributes. Shared so the client (hover/preview)
-- and the server (validation) agree on exactly the same rules.
--
-- Hold authoring rules (for holds you build or import by hand):
--   * A hold is one BasePart (Part or MeshPart) tagged "Hold" inside Workspace.Routes.<Route>.Holds.
--   * Attributes: HoldType (string), Quality (0..1), HandOK (bool), FootOK (bool).
--     Optional: HoldId (string, auto-assigned), Role ("Start" | "Finish").
--   * The part's Front face (LookVector) points away from the wall. Or add an Attachment
--     named "Grip" where the hand/foot should go; it wins over the Front face.

local CollectionService = game:GetService("CollectionService")

local HoldTypes = require(script.Parent.HoldTypes)
local Tags = require(script.Parent.Tags)

export type HoldInfo = {
	Part: BasePart,
	Id: string?,
	Type: string,
	Def: HoldTypes.HoldTypeDef,
	Quality: number,
	HandOK: boolean,
	FootOK: boolean,
	Role: string?,
}

local HoldUtil = {}

HoldUtil.GRIP_ATTACHMENT = "Grip"

function HoldUtil.isHold(instance: Instance?): boolean
	return instance ~= nil and instance:IsA("BasePart") and CollectionService:HasTag(instance, Tags.Hold)
end

-- A click/raycast can hit a decoration parented under a hold; walk up to the tagged part.
function HoldUtil.findHold(instance: Instance?): BasePart?
	local current = instance
	for _ = 1, 3 do
		if current == nil then
			return nil
		end
		if HoldUtil.isHold(current) then
			return current :: BasePart
		end
		current = current.Parent
	end
	return nil
end

-- Returns the hold's data with defaults filled in from its HoldType, or nil if the part
-- is not a hold. Invalid types fall back to HoldTypes.DEFAULT_TYPE.
function HoldUtil.read(part: BasePart): HoldInfo?
	if not HoldUtil.isHold(part) then
		return nil
	end

	local typeName = part:GetAttribute("HoldType")
	if not HoldTypes.isValid(typeName) then
		typeName = HoldTypes.DEFAULT_TYPE
	end
	local def = HoldTypes.get(typeName :: string) :: HoldTypes.HoldTypeDef

	local quality = part:GetAttribute("Quality")
	if type(quality) ~= "number" or quality ~= quality then
		quality = def.DefaultQuality
	end

	local handOK = part:GetAttribute("HandOK")
	if type(handOK) ~= "boolean" then
		handOK = def.HandOK
	end
	local footOK = part:GetAttribute("FootOK")
	if type(footOK) ~= "boolean" then
		footOK = def.FootOK
	end

	local id = part:GetAttribute("HoldId")
	local role = part:GetAttribute("Role")

	return {
		Part = part,
		Id = if type(id) == "string" then id else nil,
		Type = def.Name,
		Def = def,
		Quality = math.clamp(quality :: number, 0, 1),
		HandOK = handOK :: boolean,
		FootOK = footOK :: boolean,
		Role = if type(role) == "string" then role else nil,
	}
end

function HoldUtil.accepts(info: HoldInfo, limbKind: "Hand" | "Foot"): boolean
	if limbKind == "Hand" then
		return info.HandOK
	end
	return info.FootOK
end

-- World CFrame where a hand/foot grips the hold. LookVector points out of the wall.
function HoldUtil.getGripCFrame(part: BasePart): CFrame
	local grip = part:FindFirstChild(HoldUtil.GRIP_ATTACHMENT)
	if grip and grip:IsA("Attachment") then
		return grip.WorldCFrame
	end
	return part.CFrame * CFrame.new(0, 0, -part.Size.Z / 2)
end

-- The route folder (Workspace.Routes.<Route>) a hold belongs to, if any.
function HoldUtil.getRouteFolder(part: BasePart): Instance?
	local holds = part.Parent
	if holds and holds.Name == "Holds" then
		return holds.Parent
	end
	return nil
end

return table.freeze(HoldUtil)
