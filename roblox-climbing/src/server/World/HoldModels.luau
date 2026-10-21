--!strict
-- HoldModels: builds realistic-looking climbing holds out of primitive parts.
--
-- Each hold is ONE tagged BasePart (the "body") with decorative child parts: rolled lips,
-- bevels, bolt holes and bolt heads, screw-on screws, chalk build-up on the gripping
-- surface, chalk smears and shoe-rubber marks on the wall, and start/finish tape.
-- HoldUtil.findHold walks up from a child, so clicking a detail still selects the hold.
--
-- Every detail is placed in "surface space": the CFrame at the point where the hold sits
-- on the wall, with -Z pointing out of the wall (LookVector) and +Y up the wall.
--
-- To use real meshes later, replace build() with a function that clones your MeshPart.
-- Keep the same tag/attribute rules (see HoldUtil) and add a "Grip" Attachment.

local BuildUtil = require(script.Parent.BuildUtil)

type DetailShape = "ellipsoid" | "block" | "cylX" | "cylZ" | "wedgeUnder"
type Detail = {
	name: string,
	shape: DetailShape,
	surface: string,
	size: Vector3,
	at: Vector3, -- surface-space centre
	tint: ("hold" | "shade")?, -- use the hold colour, or a dark shade of it
	query: boolean?, -- part of the grabbable hold (true) or just a wall mark (false)
	shadow: boolean?,
}

export type HoldLook = {
	size: Vector3,
	color: Color3,
	ellipsoid: boolean,
	embed: number, -- how far the body sinks into the wall
	grip: Vector3, -- surface-space point the hand/foot targets
	footprint: Vector2, -- half extents on the wall, including details
	details: { Detail },
}

-- Wall marks sit just in front of the wall face, ordered so their faces never coincide.
-- build() also pushes each hold's marks out by MARK_LAYER_STEP * markLayer so marks of
-- neighbouring holds that overlap don't flicker either.
local SMEAR_Z = -0.013
local RUBBER_Z = -0.014
local TAPE_Z = -0.008
local MARK_LAYER_STEP = 0.0015
local MARK_LAYERS = 4

local function smear(width: number, height: number, y: number): Detail
	return { name = "ChalkSmear", shape = "ellipsoid", surface = "ChalkSmear", size = Vector3.new(width, height, 0.014), at = Vector3.new(0, y, SMEAR_Z), shadow = false }
end

local function boltRecess(y: number, z: number, holeDiameter: number): { Detail }
	return {
		{ name = "BoltHole", shape = "cylZ", surface = "BoltHole", size = Vector3.new(0.02, holeDiameter, holeDiameter), at = Vector3.new(0, y, z), query = true, shadow = false },
		{ name = "BoltHead", shape = "cylZ", surface = "BoltHead", size = Vector3.new(0.035, holeDiameter * 0.55, holeDiameter * 0.55), at = Vector3.new(0, y, z - 0.012), query = true, shadow = false },
	}
end

local function join(...: { Detail }): { Detail }
	local out = {}
	for _, list in { ... } do
		for _, d in list do
			table.insert(out, d)
		end
	end
	return out
end

local LOOKS: { [string]: HoldLook } = {
	Jug = {
		size = Vector3.new(1.3, 0.9, 0.8),
		color = Color3.fromRGB(64, 170, 84),
		ellipsoid = true,
		embed = 0.2,
		grip = Vector3.new(0, 0.3, -0.5),
		footprint = Vector2.new(0.7, 0.5),
		details = {
			{ name = "Lip", shape = "cylX", surface = "HoldUrethane", tint = "hold", size = Vector3.new(0.8, 0.24, 0.24), at = Vector3.new(0, 0.2, -0.5), query = true },
			{ name = "Bucket", shape = "ellipsoid", surface = "HoldUrethane", tint = "shade", size = Vector3.new(0.9, 0.16, 0.36), at = Vector3.new(0, 0.4, -0.22), query = true, shadow = false },
			{ name = "Chalk", shape = "ellipsoid", surface = "Chalk", size = Vector3.new(0.7, 0.07, 0.2), at = Vector3.new(0, 0.32, -0.5), query = true, shadow = false },
			smear(1.2, 0.7, 0.8),
		},
	},
	Edge = {
		size = Vector3.new(1.4, 0.35, 0.45),
		color = Color3.fromRGB(232, 196, 48),
		ellipsoid = false,
		embed = 0,
		grip = Vector3.new(0, 0.17, -0.45),
		footprint = Vector2.new(0.75, 0.5),
		details = join({
			{ name = "Nose", shape = "cylX", surface = "HoldUrethane", tint = "hold", size = Vector3.new(1.38, 0.35, 0.35), at = Vector3.new(0, 0, -0.45), query = true },
			{ name = "Bevel", shape = "wedgeUnder", surface = "HoldUrethane", tint = "hold", size = Vector3.new(1.36, 0.3, 0.4), at = Vector3.new(0, -0.325, -0.2), query = true },
			{ name = "Chalk", shape = "block", surface = "Chalk", size = Vector3.new(1.1, 0.04, 0.3), at = Vector3.new(0, 0.18, -0.38), query = true, shadow = false },
			smear(1.4, 0.6, 0.55),
		}, boltRecess(0, -0.632, 0.2)),
	},
	Crimp = {
		size = Vector3.new(0.9, 0.28, 0.32),
		color = Color3.fromRGB(198, 52, 52),
		ellipsoid = false,
		embed = 0,
		grip = Vector3.new(0, 0.14, -0.36),
		footprint = Vector2.new(0.5, 0.4),
		details = {
			{ name = "Lip", shape = "cylX", surface = "HoldUrethane", tint = "hold", size = Vector3.new(0.88, 0.2, 0.2), at = Vector3.new(0, 0.04, -0.32), query = true },
			{ name = "Bevel", shape = "wedgeUnder", surface = "HoldUrethane", tint = "hold", size = Vector3.new(0.86, 0.22, 0.3), at = Vector3.new(0, -0.25, -0.15), query = true },
			{ name = "ScrewL", shape = "cylZ", surface = "BoltHead", size = Vector3.new(0.02, 0.06, 0.06), at = Vector3.new(-0.3, -0.04, -0.33), query = true, shadow = false },
			{ name = "ScrewR", shape = "cylZ", surface = "BoltHead", size = Vector3.new(0.02, 0.06, 0.06), at = Vector3.new(0.3, -0.04, -0.33), query = true, shadow = false },
			{ name = "Chalk", shape = "block", surface = "Chalk", size = Vector3.new(0.75, 0.035, 0.22), at = Vector3.new(0, 0.145, -0.28), query = true, shadow = false },
			smear(1.0, 0.5, 0.45),
		},
	},
	Sloper = {
		size = Vector3.new(1.5, 1.1, 0.6),
		color = Color3.fromRGB(52, 104, 196),
		ellipsoid = true,
		embed = 0.15,
		grip = Vector3.new(0, 0.38, -0.36),
		footprint = Vector2.new(0.8, 0.6),
		details = join({
			{ name = "Chalk", shape = "ellipsoid", surface = "Chalk", size = Vector3.new(1.1, 0.3, 0.5), at = Vector3.new(0, 0.42, -0.22), query = true, shadow = false },
			smear(1.6, 0.8, 0.85),
		}, boltRecess(-0.05, -0.452, 0.3)),
	},
	Pinch = {
		size = Vector3.new(0.5, 1.2, 0.6),
		color = Color3.fromRGB(184, 64, 160),
		ellipsoid = true,
		embed = 0.1,
		grip = Vector3.new(0, 0.1, -0.48),
		footprint = Vector2.new(0.3, 0.65),
		details = join({
			{ name = "ChalkL", shape = "ellipsoid", surface = "Chalk", size = Vector3.new(0.1, 0.8, 0.35), at = Vector3.new(-0.23, 0.05, -0.3), query = true, shadow = false },
			{ name = "ChalkR", shape = "ellipsoid", surface = "Chalk", size = Vector3.new(0.1, 0.8, 0.35), at = Vector3.new(0.23, 0.05, -0.3), query = true, shadow = false },
		}, boltRecess(-0.3, -0.47, 0.18)),
	},
	Pocket = {
		size = Vector3.new(0.8, 0.8, 0.5),
		color = Color3.fromRGB(226, 124, 40),
		ellipsoid = true,
		embed = 0.1,
		grip = Vector3.new(0, 0.06, -0.38),
		footprint = Vector2.new(0.45, 0.45),
		details = {
			-- A dark ellipsoid that only just breaks the surface reads as a hole.
			{ name = "Hole", shape = "ellipsoid", surface = "BoltHole", size = Vector3.new(0.36, 0.24, 0.3), at = Vector3.new(0, 0.06, -0.26), query = true, shadow = false },
			{ name = "Chalk", shape = "ellipsoid", surface = "Chalk", size = Vector3.new(0.5, 0.1, 0.3), at = Vector3.new(0, 0.36, -0.12), query = true, shadow = false },
			smear(1.0, 0.7, 0.6),
		},
	},
	Foothold = {
		size = Vector3.new(0.6, 0.4, 0.4),
		color = Color3.fromRGB(46, 46, 52),
		ellipsoid = true,
		embed = 0.1,
		grip = Vector3.new(0, 0.12, -0.25),
		footprint = Vector2.new(0.35, 0.25),
		details = {
			{ name = "ScrewL", shape = "cylZ", surface = "BoltHead", size = Vector3.new(0.02, 0.06, 0.06), at = Vector3.new(-0.15, 0, -0.28), query = true, shadow = false },
			{ name = "ScrewR", shape = "cylZ", surface = "BoltHead", size = Vector3.new(0.02, 0.06, 0.06), at = Vector3.new(0.15, 0, -0.28), query = true, shadow = false },
			{ name = "ShoeRubber", shape = "ellipsoid", surface = "ShoeRubber", size = Vector3.new(0.9, 0.45, 0.014), at = Vector3.new(0.1, 0.3, RUBBER_Z), shadow = false },
			{ name = "ShoeRubber2", shape = "ellipsoid", surface = "ShoeRubber", size = Vector3.new(0.6, 0.3, 0.014), at = Vector3.new(-0.2, -0.22, RUBBER_Z - 0.002), shadow = false },
		},
	},
	Crack = {
		-- The body is the dark inside of the crack; two grey volumes form its sides.
		size = Vector3.new(0.35, 2.4, 0.3),
		color = Color3.fromRGB(28, 28, 30),
		ellipsoid = false,
		embed = 0,
		grip = Vector3.new(0, 0, -0.34),
		footprint = Vector2.new(1.0, 1.45),
		details = {
			{ name = "CheekL", shape = "block", surface = "HoldVolume", size = Vector3.new(0.55, 2.8, 0.6), at = Vector3.new(-0.45, 0, -0.3), query = true },
			{ name = "CheekR", shape = "block", surface = "HoldVolume", size = Vector3.new(0.55, 2.8, 0.6), at = Vector3.new(0.45, 0, -0.3), query = true },
			{ name = "ChalkL", shape = "block", surface = "ChalkSmear", size = Vector3.new(0.3, 1.4, 0.012), at = Vector3.new(-0.3, 0.2, -0.607), shadow = false },
			{ name = "ChalkR", shape = "block", surface = "ChalkSmear", size = Vector3.new(0.3, 1.4, 0.012), at = Vector3.new(0.3, 0.2, -0.607), shadow = false },
		},
	},
}

local HoldModels = {}

function HoldModels.getLook(typeName: string): HoldLook?
	return LOOKS[typeName]
end

local function isWallMark(detail: Detail): boolean
	return detail.surface == "ChalkSmear" or detail.surface == "ShoeRubber"
end

local function detailFrame(surfaceCFrame: CFrame, detail: Detail, markOffset: number): CFrame
	local at = if isWallMark(detail) then detail.at - Vector3.zAxis * markOffset else detail.at
	local cframe = surfaceCFrame * CFrame.new(at)
	if detail.shape == "cylZ" then
		return cframe * BuildUtil.AXIS_Z
	elseif detail.shape == "wedgeUnder" then
		-- Flip a WedgePart upside down: flat on top (under the hold), full height at the wall.
		return cframe * CFrame.Angles(0, 0, math.pi)
	end
	return cframe
end

-- Start holds get two strips of tape below them, the finish hold one on each side,
-- as route setters do in real gyms.
local function addTape(body: BasePart, surfaceCFrame: CFrame, look: HoldLook, role: string?, tapeColor: Color3)
	local strips: { CFrame } = {}
	if role == "Start" then
		local below = -look.footprint.Y - 0.25
		table.insert(strips, surfaceCFrame * CFrame.new(-0.12, below, TAPE_Z) * CFrame.Angles(0, 0, math.rad(35)))
		table.insert(strips, surfaceCFrame * CFrame.new(0.12, below, TAPE_Z) * CFrame.Angles(0, 0, math.rad(-35)))
	elseif role == "Finish" then
		local side = look.footprint.X + 0.3
		table.insert(strips, surfaceCFrame * CFrame.new(-side, 0, TAPE_Z))
		table.insert(strips, surfaceCFrame * CFrame.new(side, 0, TAPE_Z))
	end
	for i, cframe in strips do
		BuildUtil.part({
			name = `Tape{i}`,
			size = Vector3.new(0.45, 0.1, 0.012),
			cframe = cframe,
			surface = "Tape",
			color = tapeColor,
			shadow = false,
			parent = body,
		})
	end
end

export type Options = {
	role: string?, -- "Start" / "Finish" get tape (plastic style)
	tapeColor: Color3?,
	markLayer: number?, -- any integer that differs between neighbouring holds
	style: ("plastic" | "rock")?, -- gym polyurethane (default) or natural rock
	color: Color3?, -- overrides the type colour (gym problems are one colour)
}

-- Details that only make sense on a bolt-on plastic hold.
local PLASTIC_ONLY = { BoltHole = true, BoltHead = true, ScrewL = true, ScrewR = true }
-- Wall marks skipped on rock to keep part counts down on huge crags.
local ROCK_SKIPS = { ChalkSmear = true, ShoeRubber = true, ShoeRubber2 = true, ChalkL = true, ChalkR = true }

-- Builds a hold of `typeName` sitting on the wall at `surfaceCFrame` (see top of file).
-- Returns the body part; the caller sets attributes, tags and parents it.
function HoldModels.buildStyled(typeName: string, surfaceCFrame: CFrame, options: Options): BasePart
	local look = LOOKS[typeName]
	assert(look, `HoldModels: no look for hold type {typeName}`)
	local rock = options.style == "rock"
	local color = options.color or (if rock then Color3.fromRGB(132, 128, 121) else look.color)
	local tint = if typeName == "Crack" and not rock then look.color else color

	local centerZ = -(look.size.Z / 2 - look.embed)
	local body = BuildUtil.part({
		name = typeName,
		size = look.size,
		cframe = surfaceCFrame * CFrame.new(0, 0, centerZ),
		surface = if typeName == "Crack" then "CrackInside" elseif rock then "RockHold" else "HoldUrethane",
		color = if typeName == "Crack" then nil else tint,
		ellipsoid = look.ellipsoid,
		query = true,
	})

	local shade = tint:Lerp(Color3.new(0, 0, 0), 0.7)
	local markOffset = ((options.markLayer or 0) % MARK_LAYERS) * MARK_LAYER_STEP
	for _, detail in look.details do
		if rock and (PLASTIC_ONLY[detail.name] or ROCK_SKIPS[detail.name]) then
			continue
		end
		local surface = detail.surface
		if rock and (surface == "HoldUrethane" or surface == "HoldVolume") then
			surface = "RockHold"
		end
		BuildUtil.part({
			name = detail.name,
			size = detail.size,
			cframe = detailFrame(surfaceCFrame, detail, markOffset),
			surface = surface,
			color = if detail.tint == "hold" then tint elseif detail.tint == "shade" then shade elseif surface == "RockHold" then color else nil,
			shape = if detail.shape == "cylX" or detail.shape == "cylZ" then Enum.PartType.Cylinder else nil,
			wedge = detail.shape == "wedgeUnder",
			ellipsoid = detail.shape == "ellipsoid",
			query = detail.query == true,
			shadow = detail.shadow,
			parent = body,
		})
	end

	if not rock then
		addTape(body, surfaceCFrame, look, options.role, options.tapeColor or Color3.fromRGB(70, 200, 120))
	end

	-- Where the hand/foot goes (HoldUtil.getGripCFrame), facing out of the wall.
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.CFrame = body.CFrame:ToObjectSpace(surfaceCFrame * CFrame.new(look.grip))
	grip.Parent = body

	return body
end

-- Gym hold in its type colour (the test wall).
function HoldModels.build(typeName: string, surfaceCFrame: CFrame, role: string?, tapeColor: Color3?, markLayer: number?): BasePart
	return HoldModels.buildStyled(typeName, surfaceCFrame, { role = role, tapeColor = tapeColor, markLayer = markLayer })
end

return table.freeze(HoldModels)
