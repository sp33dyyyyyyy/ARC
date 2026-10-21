--!strict
-- PanelWall: a gym climbing panel on a Face (any angles): painted plate over birch
-- plywood, with the bolt-on T-nut dot grid (the "pegboard" look), skipping spots covered by
-- holds. Used for the bouldering monoliths and the Kilter board.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Shared").Tags)

local BuildUtil = require(script.Parent.BuildUtil)
local Face = require(script.Parent.Face)
local HoldModels = require(script.Parent.HoldModels)

local part = BuildUtil.part
local frameAt = BuildUtil.frameAt

export type Options = {
	width: number,
	thickness: number?, -- total (plate 0.2 + plywood)
	plate: string?, -- surface of the climbing face (default WallPaint)
	plateColor: Color3?,
	tnutSpacing: number?, -- 0 = no dots
	holds: { any }?, -- hold specs ({x, y, type}), to leave the dots out where holds sit
}

local PanelWall = {}

function PanelWall.build(face: Face.Face, parent: Instance, options: Options)
	local width = options.width
	local plateThickness = 0.2
	local core = (options.thickness or 1) - plateThickness
	for i, segment in face.segments do
		local mid = segment.startS + segment.length / 2
		local plate = part({
			name = "Wall",
			size = Vector3.new(width, segment.length, plateThickness),
			cframe = frameAt(Face.point(face, 0, mid, -plateThickness / 2), segment.normal, segment.up),
			surface = options.plate or "WallPaint",
			color = options.plateColor,
			collide = true,
			query = true,
			parent = parent,
		})
		plate.Name = if i == 1 then "Wall" else `Wall{i}`
		CollectionService:AddTag(plate, Tags.Climbable)
		part({
			name = "WallCore",
			size = Vector3.new(width, segment.length, core),
			cframe = frameAt(Face.point(face, 0, mid, -plateThickness - core / 2), segment.normal, segment.up),
			surface = "Plywood",
			collide = true,
			query = true,
			parent = parent,
		})
	end

	local spacing = options.tnutSpacing or 0.9
	if spacing <= 0 then
		return
	end
	local covered = {}
	local holds: { any } = options.holds or {}
	for _, h in holds do
		local look = HoldModels.getLook(h.type)
		if look then
			table.insert(covered, { x = h.x, y = h.y, hx = look.footprint.X + 0.1, hy = look.footprint.Y + 0.1 })
		end
	end
	local dots = Instance.new("Folder")
	dots.Name = "TNuts"
	local half = width / 2 - spacing / 2
	local y = spacing / 2
	while y < face.height - spacing / 2 do
		local x = -half
		while x <= half + 1e-6 do
			local hidden = false
			for _, c in covered do
				if math.abs(x - c.x) < c.hx and math.abs(y - c.y) < c.hy then
					hidden = true
					break
				end
			end
			if not hidden then
				part({
					name = "TNut",
					size = Vector3.new(0.01, 0.12, 0.12),
					cframe = Face.frame(face, x, y) * CFrame.new(0, 0, -0.005) * BuildUtil.AXIS_Z,
					surface = "TNut",
					shape = Enum.PartType.Cylinder,
					shadow = false,
					parent = dots,
				})
			end
			x += spacing
		end
		y += spacing
	end
	dots.Parent = parent
end

return PanelWall
