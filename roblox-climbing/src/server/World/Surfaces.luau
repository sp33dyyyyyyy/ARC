--!strict
-- Surfaces: the look (built-in material + colour) of every surface the world builders
-- create, so the whole game uses one consistent set.
--
-- Built-in 2022 materials are already PBR. For photo-real textures, create a
-- MaterialVariant in MaterialService with the name in `Variant` (Studio: View >
-- Material Manager, base material = `Material`, add your Color/Normal/Roughness maps).
-- Every part using that surface switches to it automatically, with no code changes.
-- Until a variant with that name exists, Roblox uses the plain base material.

export type Surface = {
	Material: Enum.Material,
	Color: Color3,
	Variant: string?,
	Transparency: number?,
	Reflectance: number?,
}

local Surfaces: { [string]: Surface } = {
	-- Climbing wall: textured paint over birch plywood.
	WallPaint = { Material = Enum.Material.Plaster, Color = Color3.fromRGB(236, 234, 228), Variant = "GymWallPaint" },
	Plywood = { Material = Enum.Material.Wood, Color = Color3.fromRGB(214, 188, 146), Variant = "BirchPlywood" },
	PanelSeam = { Material = Enum.Material.Plaster, Color = Color3.fromRGB(176, 175, 170) },
	TNut = { Material = Enum.Material.Metal, Color = Color3.fromRGB(46, 46, 48) },

	-- Holds: matte polyurethane. The colour comes from the hold.
	HoldUrethane = { Material = Enum.Material.Plastic, Color = Color3.new(1, 1, 1), Variant = "HoldUrethane" },
	HoldVolume = { Material = Enum.Material.Plaster, Color = Color3.fromRGB(150, 154, 160), Variant = "GymWallPaint" },
	CrackInside = { Material = Enum.Material.Plaster, Color = Color3.fromRGB(28, 28, 30) },
	BoltHead = { Material = Enum.Material.Metal, Color = Color3.fromRGB(70, 72, 76), Reflectance = 0.05 },
	BoltHole = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(14, 14, 16) },
	Chalk = { Material = Enum.Material.Salt, Color = Color3.fromRGB(246, 246, 242), Transparency = 0.25 },
	ChalkSmear = { Material = Enum.Material.Salt, Color = Color3.fromRGB(250, 250, 248), Transparency = 0.72 },
	ShoeRubber = { Material = Enum.Material.Rubber, Color = Color3.fromRGB(26, 26, 28), Transparency = 0.55 },
	Tape = { Material = Enum.Material.Fabric, Color = Color3.fromRGB(70, 200, 120) },

	-- Floor and crash mats.
	MatVinyl = { Material = Enum.Material.Leather, Color = Color3.fromRGB(40, 46, 64), Variant = "MatVinyl" },
	MatSeamCover = { Material = Enum.Material.Fabric, Color = Color3.fromRGB(28, 32, 44) },
	Floor = { Material = Enum.Material.Concrete, Color = Color3.fromRGB(148, 148, 150), Variant = "PolishedConcrete", Reflectance = 0.02 },

	-- Structure, rigging and signs.
	Steel = { Material = Enum.Material.Metal, Color = Color3.fromRGB(96, 100, 106), Variant = "PaintedSteel" },
	LampHousing = { Material = Enum.Material.Metal, Color = Color3.fromRGB(30, 30, 33) },
	LampLens = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 244, 226) },
	SignBoard = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(20, 28, 48) },
	DeckBoards = { Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(176, 150, 112), Variant = "DeckBoards" },
}

local module = {}

module.List = table.freeze(Surfaces)

-- Apply a surface to a part. `color` overrides the surface colour (holds, tape).
function module.apply(part: BasePart, name: string, color: Color3?)
	local surface = Surfaces[name]
	assert(surface, `unknown surface {name}`)
	part.Material = surface.Material
	part.Color = color or surface.Color
	part.MaterialVariant = surface.Variant or ""
	part.Transparency = surface.Transparency or 0
	part.Reflectance = surface.Reflectance or 0
end

return table.freeze(module)
