-- Procedural towers.
--
-- Telecom towers follow real self-supporting lattice towers: four tapering legs,
-- X-braced faces, stacked sections with a rest platform on top of each, and an
-- antenna with an aviation light. Skyscrapers follow stepped-setback supertalls:
-- a glass core per section that steps inward, with the setback roofs as ledges.
--
-- Climbing uses Roblox's native TrussPart climbing. Each section has one ladder,
-- and successive ladders rotate around the tower so climbers must step onto
-- every platform or ledge between them.
--
-- Geometry rules (checked by tests/run.lua against Config):
--   * Ladder k stands outside section k's structure, from the floor below to
--     the platform/roof on top of section k.
--   * Telecom platforms overhang the lattice and have a notch where the ladder
--     passes through. A backing plate stops people climbing the inner face of
--     the ladder (which would bonk them on the platform above).
--   * Skyscraper setbacks are >= 5 studs so you can stand outside the next ladder.

local Build = require(script.Parent.Build)

local TowerBuilder = {}

local LADDER_COLOR = Color3.fromRGB(255, 190, 40)
local WHITE = Color3.fromRGB(235, 235, 235)
local STEEL = Color3.fromRGB(95, 100, 110)
local CONCRETE = Color3.fromRGB(170, 168, 160)

local FACES = {
	Vector3.new(0, 0, -1), -- face 0 points at the plaza
	Vector3.new(1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(-1, 0, 0),
}

local function faceDir(f: number): Vector3
	return FACES[f % 4 + 1]
end

-- CFrame in tower space where local X points out of face `o`, Y is up and Z runs
-- along the face. (u, v, y) = (outward, along-face, height).
local function faceCF(towerCF: CFrame, o: Vector3, u: number, v: number, y: number): CFrame
	local along = o:Cross(Vector3.yAxis)
	return towerCF * CFrame.fromMatrix(o * u + along * v + Vector3.new(0, y, 0), o, Vector3.yAxis)
end

local function ladder(model: Model, towerCF: CFrame, o: Vector3, u: number, bottom: number, height: number)
	return Build.part(model, {
		ClassName = "TrussPart",
		Name = "Ladder",
		Size = Vector3.new(2, height, 2),
		CFrame = faceCF(towerCF, o, u, 0, bottom + height / 2),
		Color = LADDER_COLOR,
		Material = Enum.Material.Metal,
	})
end

local function liftKiosk(model: Model, cf: CFrame)
	local kiosk = Build.part(model, {
		Name = "Lift",
		Size = Vector3.new(3, 7, 3),
		CFrame = cf,
		Color = Color3.fromRGB(40, 45, 55),
		Material = Enum.Material.DiamondPlate,
	})
	Build.part(model, {
		Name = "LiftLamp",
		Size = Vector3.new(3.2, 0.4, 3.2),
		CFrame = cf * CFrame.new(0, 3.6, 0),
		Color = Color3.fromRGB(80, 255, 140),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LiftPrompt"
	prompt.ActionText = "Ride down"
	prompt.ObjectText = "Service lift"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = kiosk
	return kiosk
end

local function zones(model: Model, towerCF: CFrame, baseHalf: number, peakY: number, peakHalf: number)
	Build.part(model, {
		Name = "BaseZone",
		Size = Vector3.new(baseHalf * 2, 12, baseHalf * 2),
		CFrame = towerCF * CFrame.new(0, 6, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	Build.part(model, {
		Name = "PeakZone",
		Size = Vector3.new(peakHalf * 2, 10, peakHalf * 2),
		CFrame = towerCF * CFrame.new(0, peakY + 5, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
end

local function baseAndSign(model: Model, towerCF: CFrame, def: any, entry: any, baseHalf: number)
	Build.part(model, {
		Name = "Pad",
		Size = Vector3.new(baseHalf * 2, 1, baseHalf * 2),
		CFrame = towerCF * CFrame.new(0, -0.5, 0),
		Color = CONCRETE,
		Material = Enum.Material.Concrete,
	})
	local signCF = towerCF * CFrame.new(-baseHalf * 0.55, 0, -(baseHalf - 1))
	Build.part(model, {
		Name = "SignPost",
		Size = Vector3.new(0.6, 6, 0.6),
		CFrame = signCF * CFrame.new(0, 3, 0),
		Color = STEEL,
		Material = Enum.Material.Metal,
	})
	local board = Build.part(model, {
		Name = "Sign",
		Size = Vector3.new(14, 6, 0.5),
		CFrame = signCF * CFrame.new(0, 8, 0),
		Color = Color3.fromRGB(25, 28, 36),
		Material = Enum.Material.SmoothPlastic,
	})
	local stars = math.clamp(math.round(def.DrainMultiplier), 1, 4)
	Build.surfaceText(board, {
		{ text = string.upper(entry.Name), size = 70, color = Color3.fromRGB(255, 255, 255) },
		{ text = def.DisplayName .. "  ·  $" .. def.Payout, size = 50, color = Color3.fromRGB(110, 230, 140), font = Enum.Font.GothamBold },
		{ text = string.rep("★", stars) .. string.rep("☆", 4 - stars) .. "  drain x" .. def.DrainMultiplier, size = 46, color = Color3.fromRGB(255, 200, 70), font = Enum.Font.GothamBold },
	})
end

-- Telecom lattice tower --------------------------------------------------------

local function buildTelecom(model: Model, towerCF: CFrame, def: any): (number, number, number)
	local S, n = def.SectionHeight, def.Sections
	local H = S * n
	local paint = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
	local overhang = 5
	local notchHalf = 2.5

	local function hw(y: number): number
		return def.BaseHalfWidth + (def.TopHalfWidth - def.BaseHalfWidth) * (y / H)
	end
	local function corner(o: Vector3, side: number, y: number): Vector3
		local along = o:Cross(Vector3.yAxis)
		local h = hw(y)
		return towerCF:PointToWorldSpace(o * h + along * (side * h) + Vector3.new(0, y, 0))
	end

	for k = 0, n - 1 do
		local bottom, top = k * S, (k + 1) * S
		local band = if k % 2 == 0 then paint else WHITE
		local metal = { Color = band, Material = Enum.Material.Metal }

		-- Legs (solid) at the four corners.
		for f = 0, 3 do
			local o = faceDir(f)
			local leg = Build.beam(model, corner(o, -1, bottom), corner(o, -1, top), 1.2, metal)
			leg.CanCollide = true
		end

		-- X-bracing every 10 studs on every face, plus a horizontal girt.
		local panels = math.max(1, math.floor(S / 10))
		local panelH = S / panels
		for f = 0, 3 do
			local o = faceDir(f)
			for j = 0, panels - 1 do
				local y0, y1 = bottom + j * panelH, bottom + (j + 1) * panelH
				Build.beam(model, corner(o, -1, y0), corner(o, 1, y1), 0.45, metal)
				Build.beam(model, corner(o, 1, y0), corner(o, -1, y1), 0.45, metal)
				Build.beam(model, corner(o, -1, y0), corner(o, 1, y0), 0.45, metal)
			end
		end

		-- Ladder for this section, on a rotating face, hugging the lattice.
		local o = faceDir(k)
		local a = hw(bottom) -- ladder inner edge
		ladder(model, towerCF, o, a + 1, bottom, S)
		Build.part(model, {
			Name = "LadderBacking",
			Size = Vector3.new(0.3, S, 2.4),
			CFrame = faceCF(towerCF, o, a - 0.15, 0, bottom + S / 2),
			Color = STEEL,
			Material = Enum.Material.DiamondPlate,
		})

		-- Rest platform on top of the section, notched where the ladder comes up.
		local p = hw(top) + overhang
		local u0 = a - 0.3
		local pieces = {
			{ -p, u0, -p, p },
			{ u0, p, -p, -notchHalf },
			{ u0, p, notchHalf, p },
		}
		for _, r in pieces do
			Build.part(model, {
				Name = "Platform",
				Size = Vector3.new(r[2] - r[1], 1, r[4] - r[3]),
				CFrame = faceCF(towerCF, o, (r[1] + r[2]) / 2, (r[3] + r[4]) / 2, top - 0.5),
				Color = Color3.fromRGB(120, 124, 130),
				Material = Enum.Material.DiamondPlate,
				Attributes = { Checkpoint = true },
			})
		end

		-- Guard rails around the platform edge, open where the ladder arrives.
		for f = 0, 3 do
			local ro = faceDir(f)
			local spans = if f % 4 == k % 4 then { { -p, -notchHalf }, { notchHalf, p } } else { { -p, p } }
			for _, span in spans do
				local len = span[2] - span[1]
				local mid = (span[1] + span[2]) / 2
				Build.part(model, {
					Name = "Rail",
					Size = Vector3.new(0.3, 0.3, len),
					CFrame = faceCF(towerCF, ro, p - 0.15, mid, top + 3),
					Color = Color3.fromRGB(255, 220, 60),
					Material = Enum.Material.Metal,
				})
				for v = span[1], span[2], 5 do
					Build.part(model, {
						Name = "RailPost",
						Size = Vector3.new(0.3, 3, 0.3),
						CFrame = faceCF(towerCF, ro, p - 0.15, v, top + 1.5),
						Color = Color3.fromRGB(255, 220, 60),
						Material = Enum.Material.Metal,
						CanCollide = false,
					})
				end
			end
		end

		-- Microwave dish on the face opposite this section's ladder.
		if k > 0 and k < n - 1 then
			local dishO = faceDir(k + 2)
			local y = bottom + S * 0.5
			Build.part(model, {
				Name = "Dish",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.8, 5, 5),
				CFrame = faceCF(towerCF, dishO, hw(y) + 0.8, 0, y),
				Color = WHITE,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
			})
		end
	end

	-- Panel antennas near the corners of the top section.
	for f = 0, 3 do
		local o = faceDir(f)
		local y = H - 6
		for _, side in { -1, 1 } do
			Build.part(model, {
				Name = "PanelAntenna",
				Size = Vector3.new(0.5, 5, 1.4),
				CFrame = faceCF(towerCF, o, hw(y) + 0.5, side * (hw(y) - 0.8), y),
				Color = WHITE,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
			})
		end
	end

	-- Antenna mast with an aviation light on top.
	local mastHeight = if H >= 150 then 30 else 16
	Build.cylinder(model, towerCF:PointToWorldSpace(Vector3.new(0, H + mastHeight / 2, 0)), mastHeight, 0.9, {
		Name = "Antenna",
		Color = paint,
		Material = Enum.Material.Metal,
	})
	Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(0, H + mastHeight + 0.6, 0)))
	Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(0, H * 0.5, 0)), 1.2)

	local summitHalf = hw(H) + overhang
	liftKiosk(model, faceCF(towerCF, faceDir(n - 1 + 2), summitHalf - 2.5, 0, H + 3.5))
	return H, summitHalf, def.BaseHalfWidth + 12
end

-- Stepped-setback skyscraper -----------------------------------------------------

local function buildSkyscraper(model: Model, towerCF: CFrame, def: any): (number, number, number)
	local S = def.SectionHeight
	local widths = def.HalfWidths
	local n = #widths
	local H = S * n
	local glass = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])

	for k = 0, n - 1 do
		local h = widths[k + 1]
		local bottom, top = k * S, (k + 1) * S

		Build.part(model, {
			Name = "Facade",
			Size = Vector3.new(h * 2, S, h * 2),
			CFrame = towerCF * CFrame.new(0, bottom + S / 2, 0),
			Color = glass,
			Material = Enum.Material.Glass,
			Reflectance = 0.25,
		})

		-- Floor bands every 10 studs give the facade scale and texture.
		for y = bottom + 10, top - 10, 10 do
			Build.part(model, {
				Name = "FloorBand",
				Size = Vector3.new(h * 2 + 0.6, 0.8, h * 2 + 0.6),
				CFrame = towerCF * CFrame.new(0, y, 0),
				Color = Color3.fromRGB(205, 205, 200),
				Material = Enum.Material.Concrete,
				CanQuery = false,
			})
		end

		-- Vertical mullions.
		local count = math.max(2, math.floor(h * 2 / 8))
		local spacing = h * 2 / count
		for f = 0, 3 do
			local o = faceDir(f)
			for i = 0, count - 1 do
				Build.part(model, {
					Name = "Mullion",
					Size = Vector3.new(0.4, S, 0.5),
					CFrame = faceCF(towerCF, o, h + 0.2, -h + (i + 0.5) * spacing, bottom + S / 2),
					Color = Color3.fromRGB(55, 60, 70),
					Material = Enum.Material.Metal,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
				})
			end
		end

		-- Setback roof: the ledge you rest on before the next ladder.
		Build.part(model, {
			Name = "Ledge",
			Size = Vector3.new(h * 2 + 1, 1, h * 2 + 1),
			CFrame = towerCF * CFrame.new(0, top - 0.5, 0),
			Color = CONCRETE,
			Material = Enum.Material.Concrete,
			Attributes = { Checkpoint = true },
		})

		-- Window-washer rail (the climbable ladder) on a rotating face.
		ladder(model, towerCF, faceDir(k), h + 1, bottom, S)

		-- Corner lights on each setback.
		if k < n - 1 then
			Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(h, top + 0.8, h)), 1.2)
			Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(-h, top + 0.8, -h)), 1.2)
		end
	end

	-- Lobby canopy and doors, offset from the first ladder.
	local h0 = widths[1]
	local front = faceDir(0)
	Build.part(model, {
		Name = "Canopy",
		Size = Vector3.new(6, 0.6, 16),
		CFrame = faceCF(towerCF, front, h0 + 3, -h0 * 0.5, 12),
		Color = Color3.fromRGB(40, 40, 46),
		Material = Enum.Material.Metal,
	})
	Build.part(model, {
		Name = "Doors",
		Size = Vector3.new(0.4, 10, 12),
		CFrame = faceCF(towerCF, front, h0 + 0.2, -h0 * 0.5, 5),
		Color = Color3.fromRGB(20, 25, 30),
		Material = Enum.Material.Glass,
		Reflectance = 0.4,
	})

	-- Summit: helipad or spire, plus lights and the lift.
	local hTop = widths[n]
	if def.Spire then
		local stages = { { 6, 0.35 }, { 4, 0.3 }, { 2.4, 0.2 }, { 1.2, 0.15 } }
		local y = H
		for _, stage in stages do
			local len = def.Spire * stage[2]
			Build.cylinder(model, towerCF:PointToWorldSpace(Vector3.new(0, y + len / 2, 0)), len, stage[1], {
				Name = "Spire",
				Color = Color3.fromRGB(200, 205, 215),
				Material = Enum.Material.Metal,
				Reflectance = 0.2,
			})
			y += len
		end
		Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(0, y + 1, 0)), 2)
	else
		local d = math.min(hTop * 2 - 6, 22)
		Build.cylinder(model, towerCF:PointToWorldSpace(Vector3.new(0, H + 0.1, 0)), 0.2, d, {
			Name = "Helipad",
			Color = Color3.fromRGB(40, 42, 48),
			Material = Enum.Material.Asphalt,
			CanCollide = false,
		})
		local hColor = { Color = Color3.fromRGB(255, 210, 50), Material = Enum.Material.SmoothPlastic, CanCollide = false }
		for _, spec in { { -2, 0, 1, 8 }, { 2, 0, 1, 8 }, { 0, 0, 3, 1 } } do
			Build.part(model, {
				Name = "HelipadH",
				Size = Vector3.new(spec[3], 0.1, spec[4]),
				CFrame = towerCF * CFrame.new(spec[1], H + 0.25, spec[2]),
				Color = hColor.Color,
				Material = hColor.Material,
				CanCollide = false,
			})
		end
	end
	for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(c[1] * (hTop - 0.5), H + 0.8, c[2] * (hTop - 0.5))), 1.2)
	end
	liftKiosk(model, faceCF(towerCF, faceDir(n - 1 + 2), hTop - 3, 0, H + 3.5))
	return H, hTop + 0.5, h0 + 14
end

-- Public -------------------------------------------------------------------------

function TowerBuilder.build(parent: Instance, entry: any, def: any, towerCF: CFrame): Model
	local model = Instance.new("Model")
	model.Name = entry.Name

	local height, peakHalf, baseHalf
	if def.Kind == "Telecom" then
		height, peakHalf, baseHalf = buildTelecom(model, towerCF, def)
	else
		height, peakHalf, baseHalf = buildSkyscraper(model, towerCF, def)
	end
	baseAndSign(model, towerCF, def, entry, baseHalf)
	zones(model, towerCF, baseHalf, height, peakHalf)

	model:SetAttribute("TowerId", entry.Name)
	model:SetAttribute("DisplayName", entry.Name)
	model:SetAttribute("Kind", def.Kind)
	model:SetAttribute("Height", height)
	model:SetAttribute("Payout", def.Payout)
	model:SetAttribute("DrainMultiplier", def.DrainMultiplier)
	model:SetAttribute("Slippery", def.Slippery)
	model:SetAttribute("Radius", baseHalf)
	model.WorldPivot = towerCF
	model.Parent = parent
	return model
end

return TowerBuilder
