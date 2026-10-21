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

	-- Natural rock (crags and the giant wall).
	RockFace = { Material = Enum.Material.Rock, Color = Color3.fromRGB(116, 113, 108), Variant = "GraniteFace" },
	RockHold = { Material = Enum.Material.Granite, Color = Color3.fromRGB(132, 128, 121), Variant = "GraniteHold" },
	Ledge = { Material = Enum.Material.Slate, Color = Color3.fromRGB(104, 101, 96), Variant = "GraniteFace" },

	-- Gym building.
	GymWall = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(240, 241, 243) },
	NavyPanel = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(26, 36, 70) },
	Ceiling = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(18, 18, 22) },
	GymFloor = { Material = Enum.Material.Concrete, Color = Color3.fromRGB(160, 160, 158), Variant = "PolishedConcrete", Reflectance = 0.03 },
	RubberFloor = { Material = Enum.Material.Rubber, Color = Color3.fromRGB(38, 40, 46) },
	LightWood = { Material = Enum.Material.Wood, Color = Color3.fromRGB(214, 184, 140), Variant = "BirchPlywood" },
	Glass = { Material = Enum.Material.Glass, Color = Color3.fromRGB(190, 220, 235), Transparency = 0.6 },
	Neon = { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 255, 255) },
	Bark = { Material = Enum.Material.Wood, Color = Color3.fromRGB(88, 62, 44) },
	PineNeedles = { Material = Enum.Material.Grass, Color = Color3.fromRGB(44, 82, 52) },
	Cardboard = { Material = Enum.Material.Cardboard, Color = Color3.fromRGB(186, 150, 104) },

	-- Modern gym (Ascent): white, charcoal, white oak and one orange accent.
	Charcoal = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(42, 44, 50) },
	SoftWhite = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(232, 233, 235) },
	WhiteOak = { Material = Enum.Material.Wood, Color = Color3.fromRGB(196, 166, 126), Variant = "WhiteOak" },
	OakFloor = { Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(178, 146, 108), Variant = "OakFloor" },
	Accent = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(255, 122, 48) },
	BlackSteel = { Material = Enum.Material.Metal, Color = Color3.fromRGB(34, 35, 38), Variant = "PaintedSteel" },
	Diffuser = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(250, 248, 242) },
	ClearGlass = { Material = Enum.Material.Glass, Color = Color3.fromRGB(205, 225, 232), Transparency = 0.72, Reflectance = 0.08 },
	Mirror = { Material = Enum.Material.Glass, Color = Color3.fromRGB(220, 226, 230), Transparency = 0.2, Reflectance = 0.6 },
	Upholstery = { Material = Enum.Material.Fabric, Color = Color3.fromRGB(70, 82, 96) },
	Leaves = { Material = Enum.Material.Grass, Color = Color3.fromRGB(58, 112, 64) },
	Planter = { Material = Enum.Material.Concrete, Color = Color3.fromRGB(190, 186, 180) },
	LockerPaint = { Material = Enum.Material.Metal, Color = Color3.fromRGB(62, 72, 88) },
	PaddedMat = { Material = Enum.Material.Fabric, Color = Color3.fromRGB(48, 52, 62), Variant = "MatVinyl" },
	RubberTile = { Material = Enum.Material.Rubber, Color = Color3.fromRGB(58, 60, 66) },

	-- Floor and crash mats.
	MatVinyl = { Material = Enum.Material.Leather, Color = Color3.fromRGB(40, 46, 64), Variant = "MatVinyl" },
	MatSeamCover = { Material = Enum.Material.Fabric, Color = Color3.fromRGB(28, 32, 44) },
	Floor = { Material = Enum.Material.Concrete, Color = Color3.fromRGB(148, 148, 150), Variant = "PolishedConcrete", Reflectance = 0.02 },

	-- Structure, rigging and signs.
	Steel = { Material = Enum.Material.Metal, Color = Color3.fromRGB(96, 100, 106), Variant = "PaintedSteel" },
	LampHousing = { Material = Enum.Material.Metal, Color = Color3.fromRGB(30, 30, 33) },
	-- Not Neon: neon lenses bloom into a blinding glare under Future lighting.
	LampLens = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(255, 248, 232) },
	SignBoard = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(19, 20, 23) },
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
