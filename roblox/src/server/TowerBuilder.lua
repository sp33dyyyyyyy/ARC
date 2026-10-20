-- Procedural towers for Grip & Lunge climbing (no ladders).
--
-- Climbable surfaces carry the "Climbable" tag; the client climbing controller
-- raycasts against them. Anything solid that sticks out from a climbable wall
-- (platforms, balconies) blocks you, and you mantle onto it to rest.
--
-- Telecom towers follow real self-supporting lattice towers: four tapering
-- legs, X-bracing, a railed rest platform on top of every section, dishes,
-- panel antennas and aviation lights. Each face of each section has an
-- invisible climb panel lying in the lattice face, so you climb the lattice.
--
-- Skyscrapers are glass towers with a frame grid, a railed maintenance balcony
-- every `BalconyEvery` studs (the only rest spots), rooftop AC units, an
-- optional helipad, and windows that light up at night.

local Build = require(script.Parent.Build)

local TowerBuilder = {}

local WHITE = Color3.fromRGB(235, 235, 235)
local CONCRETE = Color3.fromRGB(170, 168, 160)
local MAX_PART = 2000 -- Roblox parts are capped at 2048 studs per side

local FACES = {
	Vector3.new(0, 0, -1), -- face 0 points at the path
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

local function liftKiosk(model: Model, cf: CFrame)
	local kiosk = Build.part(model, {
		Name = "Lift",
		Size = Vector3.new(4, 7, 4),
		CFrame = cf * CFrame.new(0, 3.5, 0),
		Color = Color3.fromRGB(40, 45, 55),
		Material = Enum.Material.DiamondPlate,
	})
	Build.part(model, {
		Name = "LiftLamp",
		Size = Vector3.new(4.2, 0.4, 4.2),
		CFrame = cf * CFrame.new(0, 7.2, 0),
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

-- Railing around a square platform/balcony of half-size p whose top is at y.
local function railing(model: Model, towerCF: CFrame, p: number, y: number, props: { [string]: any }, postEvery: number)
	for f = 0, 3 do
		local o = faceDir(f)
		local rail = {
			Name = "Rail",
			Size = Vector3.new(0.3, 0.3, p * 2),
			CFrame = faceCF(towerCF, o, p - 0.15, 0, y + 3),
		}
		for k, v in props do
			rail[k] = v
		end
		Build.part(model, rail)
		for v = -p, p, postEvery do
			local post = {
				Name = "RailPost",
				Size = Vector3.new(0.3, 3, 0.3),
				CFrame = faceCF(towerCF, o, p - 0.15, v, y + 1.5),
				CanCollide = false,
				CanQuery = false,
			}
			for k, val in props do
				if post[k] == nil then
					post[k] = val
				end
			end
			Build.part(model, post)
		end
	end
end

-- Telecom lattice tower --------------------------------------------------------

local function buildTelecom(model: Model, towerCF: CFrame, def: any): (number, number)
	local S, n = def.SectionHeight, def.Sections
	local H = S * n
	local paint = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
	local overhang = 4

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

		for f = 0, 3 do
			local o = faceDir(f)
			-- Leg on this face's left corner (four faces -> four legs).
			local leg = Build.beam(model, corner(o, -1, bottom), corner(o, -1, top), 1.4, metal)
			leg.CanCollide = true

			-- X-bracing about every 10 studs, plus a horizontal girt.
			local panels = math.max(1, math.floor(S / 10))
			local panelH = S / panels
			for j = 0, panels - 1 do
				local y0, y1 = bottom + j * panelH, bottom + (j + 1) * panelH
				Build.beam(model, corner(o, -1, y0), corner(o, 1, y1), 0.5, metal)
				Build.beam(model, corner(o, 1, y0), corner(o, -1, y1), 0.5, metal)
				Build.beam(model, corner(o, -1, y0), corner(o, 1, y0), 0.5, metal)
			end

			-- Invisible climb panel lying in the (tapered) lattice face.
			local along = o:Cross(Vector3.yAxis)
			local b = o * hw(bottom) + Vector3.new(0, bottom, 0)
			local t = o * hw(top) + Vector3.new(0, top, 0)
			local slope = t - b
			local normal = slope:Cross(along).Unit
			local width = hw(bottom) + hw(top) -- average full width
			Build.part(model, {
				Name = "ClimbFace",
				Size = Vector3.new(1, slope.Magnitude, width),
				CFrame = towerCF * CFrame.fromMatrix((b + t) / 2 - normal * 0.5, normal, slope.Unit),
				Transparency = 1,
				Tags = { "Climbable" },
			})
		end

		-- Rest platform on top of the section, sticking out past the lattice so
		-- climbers bump into it and mantle up.
		local p = hw(top) + overhang
		Build.part(model, {
			Name = "Platform",
			Size = Vector3.new(p * 2, 1, p * 2),
			CFrame = towerCF * CFrame.new(0, top - 0.5, 0),
			Color = Color3.fromRGB(120, 124, 130),
			Material = Enum.Material.DiamondPlate,
			Attributes = { Checkpoint = true },
		})
		railing(model, towerCF, p, top, { Color = Color3.fromRGB(255, 220, 60), Material = Enum.Material.Metal }, 12)

		-- Microwave dishes on a couple of faces per section.
		if k > 0 and k < n - 1 and k % 2 == 1 then
			for _, f in { k % 4, (k + 2) % 4 } do
				local o = faceDir(f)
				local y = bottom + S * 0.45
				Build.part(model, {
					Name = "Dish",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1, 7, 7),
					CFrame = faceCF(towerCF, o, hw(y) + 2.2, hw(y) * 0.45, y),
					Color = WHITE,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					CanQuery = false,
				})
			end
		end
		-- Aviation lights every few sections, like the real thing.
		if k % 3 == 2 then
			for _, c in { { 1, 1 }, { -1, -1 } } do
				Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(c[1] * (p - 0.5), top + 0.8, c[2] * (p - 0.5))), 1.2)
			end
		end
	end

	-- Panel antennas just under the summit.
	for f = 0, 3 do
		local o = faceDir(f)
		local y = H - S * 0.4
		for _, side in { -1, 1 } do
			Build.part(model, {
				Name = "PanelAntenna",
				Size = Vector3.new(0.6, 6, 1.6),
				CFrame = faceCF(towerCF, o, hw(y) + 1, side * hw(y) * 0.6, y),
				Color = WHITE,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
			})
		end
	end

	-- Summit: service lift in the middle with the antenna mast on its roof.
	liftKiosk(model, towerCF * CFrame.new(0, H, 0))
	local mastHeight = math.clamp(H * 0.06, 14, 60)
	Build.cylinder(model, towerCF:PointToWorldSpace(Vector3.new(0, H + 7 + mastHeight / 2, 0)), mastHeight, 1, {
		Name = "Antenna",
		Color = paint,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(0, H + 7 + mastHeight + 0.8, 0)), 2)

	return H, hw(H) + overhang
end

-- Glass skyscraper -----------------------------------------------------------------

local function buildSkyscraper(model: Model, towerCF: CFrame, def: any): (number, number)
	local H, h, every = def.Height, def.HalfWidth, def.BalconyEvery
	local glass = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
	local frame = Color3.fromRGB(def.Frame[1], def.Frame[2], def.Frame[3])
	local rng = Random.new(H + h) -- deterministic window pattern per tower
	local balconyDepth = 4

	-- Facade, in segments (part size limit) between balconies.
	for y0 = 0, H - every, every do
		local seg = math.min(every, MAX_PART)
		Build.part(model, {
			Name = "Facade",
			Size = Vector3.new(h * 2, seg, h * 2),
			CFrame = towerCF * CFrame.new(0, y0 + seg / 2, 0),
			Color = glass,
			Material = Enum.Material.Glass,
			Reflectance = 0.2,
			Tags = { "Climbable" },
		})

		-- Corner columns and vertical mullions.
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			Build.part(model, {
				Name = "Column",
				Size = Vector3.new(2.4, seg, 2.4),
				CFrame = towerCF * CFrame.new(c[1] * (h - 0.8), y0 + seg / 2, c[2] * (h - 0.8)),
				Color = frame,
				Material = Enum.Material.Concrete,
				CanQuery = false,
			})
		end
		local count = math.floor(h * 2 / 9)
		local spacing = h * 2 / count
		for f = 0, 3 do
			local o = faceDir(f)
			for i = 1, count - 1 do
				Build.part(model, {
					Name = "Mullion",
					Size = Vector3.new(0.5, seg, 0.6),
					CFrame = faceCF(towerCF, o, h + 0.2, -h + i * spacing, y0 + seg / 2),
					Color = frame,
					Material = Enum.Material.Metal,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
				})
			end
		end
		-- Floor bands every 15 studs.
		for y = y0 + 15, y0 + seg - 5, 15 do
			Build.part(model, {
				Name = "FloorBand",
				Size = Vector3.new(h * 2 + 0.6, 1, h * 2 + 0.6),
				CFrame = towerCF * CFrame.new(0, y, 0),
				Color = frame,
				Material = Enum.Material.Concrete,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			})
		end
		-- A few windows that light up at night.
		for _ = 1, 6 do
			local f = rng:NextInteger(0, 3)
			local y = y0 + rng:NextInteger(1, math.floor(seg / 15) - 1) * 15 - 7.5
			local v = -h + (rng:NextInteger(1, count) - 0.5) * spacing
			Build.part(model, {
				Name = "NightWindow",
				Size = Vector3.new(0.2, 11, spacing - 1.2),
				CFrame = faceCF(towerCF, faceDir(f), h + 0.05, v, y),
				Color = Color3.fromRGB(255, 214, 120),
				Material = Enum.Material.Neon,
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Tags = { "NightWindow" },
			})
		end

		-- Maintenance balcony on top of this segment (the roof for the last one).
		local top = y0 + seg
		if top < H then
			local p = h + balconyDepth
			Build.part(model, {
				Name = "Balcony",
				Size = Vector3.new(p * 2, 1, p * 2),
				CFrame = towerCF * CFrame.new(0, top - 0.5, 0),
				Color = CONCRETE,
				Material = Enum.Material.Concrete,
				Attributes = { Checkpoint = true },
			})
			railing(model, towerCF, p, top, {
				Color = Color3.fromRGB(180, 210, 230),
				Material = Enum.Material.Glass,
				Transparency = 0.4,
			}, 10)
		end
	end

	-- Lobby doors facing the path.
	local front = faceDir(0)
	Build.part(model, {
		Name = "Doors",
		Size = Vector3.new(0.4, 10, 12),
		CFrame = faceCF(towerCF, front, h + 0.25, 0, 5),
		Color = Color3.fromRGB(20, 25, 30),
		Material = Enum.Material.Glass,
		Reflectance = 0.4,
		CanQuery = false,
	})
	Build.part(model, {
		Name = "Canopy",
		Size = Vector3.new(5, 0.6, 18),
		CFrame = faceCF(towerCF, front, h + 2.5, 0, 12),
		Color = frame,
		Material = Enum.Material.Metal,
		CanCollide = false, -- decorative: it would otherwise stop climbers above the doors
		CanQuery = false,
	})

	-- Roof slab and a climbable parapet you climb over onto the roof.
	Build.part(model, {
		Name = "Roof",
		Size = Vector3.new(h * 2 + 1, 1, h * 2 + 1),
		CFrame = towerCF * CFrame.new(0, H - 0.5, 0),
		Color = Color3.fromRGB(110, 112, 118),
		Material = Enum.Material.Concrete,
		Attributes = { Checkpoint = true },
	})
	for f = 0, 3 do
		Build.part(model, {
			Name = "Parapet",
			Size = Vector3.new(1, 2, h * 2 + 1),
			CFrame = faceCF(towerCF, faceDir(f), h, 0, H + 1),
			Color = frame,
			Material = Enum.Material.Concrete,
			Tags = { "Climbable" },
		})
	end

	-- Rooftop AC units, kept well away from the edges so mantling is never blocked.
	local spots = { { -0.45, -0.45 }, { 0.45, -0.45 }, { -0.45, 0.45 }, { 0.45, 0.45 }, { 0, -0.5 } }
	for i, s in spots do
		if not def.Helipad or i <= 4 then
			local pos = Vector3.new(s[1] * h, H, s[2] * h)
			Build.part(model, {
				Name = "ACUnit",
				Size = Vector3.new(7, 4, 6),
				CFrame = towerCF * CFrame.new(pos + Vector3.new(0, 2, 0)),
				Color = Color3.fromRGB(200, 202, 205),
				Material = Enum.Material.Metal,
			})
			Build.cylinder(model, towerCF:PointToWorldSpace(pos + Vector3.new(0, 4.1, 0)), 0.2, 4.5, {
				Name = "ACFan",
				Color = Color3.fromRGB(60, 62, 66),
				Material = Enum.Material.Metal,
				CanCollide = false,
			})
		end
	end

	if def.Helipad then
		local d = math.min(h * 2 - 30, 30)
		Build.cylinder(model, towerCF:PointToWorldSpace(Vector3.new(0, H + 0.1, 0)), 0.2, d, {
			Name = "Helipad",
			Color = Color3.fromRGB(45, 47, 52),
			Material = Enum.Material.Asphalt,
			CanCollide = false,
		})
		Build.cylinder(model, towerCF:PointToWorldSpace(Vector3.new(0, H + 0.15, 0)), 0.2, d - 3, {
			Name = "HelipadRing",
			Color = Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		Build.cylinder(model, towerCF:PointToWorldSpace(Vector3.new(0, H + 0.2, 0)), 0.2, d - 5, {
			Name = "HelipadInner",
			Color = Color3.fromRGB(45, 47, 52),
			Material = Enum.Material.Asphalt,
			CanCollide = false,
		})
		for _, spec in { { -3, 0, 1.5, 11 }, { 3, 0, 1.5, 11 }, { 0, 0, 4.5, 1.5 } } do
			Build.part(model, {
				Name = "HelipadH",
				Size = Vector3.new(spec[3], 0.1, spec[4]),
				CFrame = towerCF * CFrame.new(spec[1], H + 0.3, spec[2]),
				Color = Color3.fromRGB(240, 240, 240),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
			})
		end
	end
	for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		Build.aviationLight(model, towerCF:PointToWorldSpace(Vector3.new(c[1] * (h - 0.8), H + 2.8, c[2] * (h - 0.8))), 1.4)
	end
	liftKiosk(model, towerCF * CFrame.new(0, H, if def.Helipad then h * 0.55 else 0))
	return H, h + 0.5
end

-- Public -------------------------------------------------------------------------

-- Builds one tower. `lotHalf` is the half-size of its fenced lot (used for the
-- base zone and for the client to know which tower you're on).
function TowerBuilder.build(parent: Instance, entry: any, def: any, towerCF: CFrame, lotHalf: number): Model
	local model = Instance.new("Model")
	model.Name = entry.Name

	local height, peakHalf
	if def.Kind == "Telecom" then
		height, peakHalf = buildTelecom(model, towerCF, def)
	else
		height, peakHalf = buildSkyscraper(model, towerCF, def)
	end
	zones(model, towerCF, lotHalf - 2, height, peakHalf)

	model:SetAttribute("TowerId", entry.Name)
	model:SetAttribute("DisplayName", entry.Name)
	model:SetAttribute("Difficulty", entry.Difficulty)
	model:SetAttribute("Kind", def.Kind)
	model:SetAttribute("Height", height)
	model:SetAttribute("Payout", def.Payout)
	model:SetAttribute("DrainMultiplier", def.DrainMultiplier)
	model:SetAttribute("Slippery", def.Slippery)
	model:SetAttribute("Radius", lotHalf)
	model.WorldPivot = towerCF
	model.Parent = parent
	return model
end

return TowerBuilder
