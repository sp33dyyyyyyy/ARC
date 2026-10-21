--!strict
-- Npc: standing, anchored people for the world (front desk, shop staff, climbers), built
-- from a HumanoidDescription. They can wear climbing gear from the Roblox catalog
-- (helmet, pack, chalk bag), which Roblox loads onto them by asset id.

local Players = game:GetService("Players")

export type Gear = { hat: number?, back: number?, waist: number? }

local Npc = {}

function Npc.spawn(name: string, position: Vector3, facing: Vector3, parent: Instance, shirt: Color3, gear: Gear?)
	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		description.HeadColor = Color3.fromRGB(234, 184, 146)
		description.LeftArmColor = shirt
		description.RightArmColor = shirt
		description.TorsoColor = shirt
		description.LeftLegColor = Color3.fromRGB(30, 36, 60)
		description.RightLegColor = Color3.fromRGB(30, 36, 60)
		if gear then
			description.HatAccessory = if gear.hat then tostring(gear.hat) else ""
			description.BackAccessory = if gear.back then tostring(gear.back) else ""
			description.WaistAccessory = if gear.waist then tostring(gear.waist) else ""
		end
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or model == nil then
		return
	end
	model.Name = name
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root and humanoid then
		root.Anchored = true
		-- Feet exactly on the floor: the root sits HipHeight + half its height above it.
		local y = humanoid.HipHeight + root.Size.Y / 2
		model:PivotTo(CFrame.lookAt(position + Vector3.yAxis * y, position + Vector3.yAxis * y + facing))
		humanoid.DisplayName = name
		humanoid.NameDisplayDistance = 30
	end
	model.Parent = parent
end

return table.freeze(Npc)
