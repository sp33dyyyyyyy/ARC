--[[
	ModelKit  (ModuleScript, ReplicatedStorage/Shared)

	A tiny construction kit for building detailed models out of Roblox parts:
	boxes, cylinders, balls, struts, tubes, rounded "stadium" slabs, arcs
	(mudguards), curved pipes and spoked wheels.

	Two modes
	  * welded:   ModelKit.new(model, rootPart, rootCFrame)      (bikes)
	              every part is welded to rootPart, massless, no collision
	  * anchored: ModelKit.new(model, nil, worldCFrame, true)    (buildings)
	              every part is anchored at worldCFrame * offset

	All offsets / points are in the kit's LOCAL space: -Z forward, +Y up.
	Cylinders (Roblox) run along their local X axis; use tube()/rotate offsets
	to point them elsewhere.
]]

local ModelKit = {}
ModelKit.__index = ModelKit

local V3 = Vector3.new
local CF = CFrame.new

function ModelKit.new(parent: Instance, root: BasePart?, baseCF: CFrame?, anchored: boolean?)
	return setmetatable({
		parent = parent,
		root = root,
		base = baseCF or CF(),
		anchored = anchored == true,
		count = 0,
	}, ModelKit)
end

----------------------------------------------------------------------------
-- core placement
----------------------------------------------------------------------------
function ModelKit:place(p: BasePart, offset: CFrame, opts: { [string]: any }?)
	opts = opts or {}
	p.Anchored = self.anchored
	p.CanCollide = opts.collide == true
	p.CanQuery = opts.collide == true or opts.query == true
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.shadow == false then
		p.CastShadow = false
	end
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	if opts.reflectance then
		p.Reflectance = opts.reflectance
	end
	if opts.paint then
		p:SetAttribute("Paint", opts.paint)
	end
	p.CFrame = self.base * offset
	p.Parent = self.parent
	if self.root then
		local w = Instance.new("Weld")
		w.Part0 = self.root
		w.Part1 = p
		w.C0 = offset
		w.Parent = p
	end
	self.count += 1
	return p
end

function ModelKit:part(name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, opts: { [string]: any }?)
	local p = Instance.new("Part")
	p.Name = name
	if shape ~= Enum.PartType.Block then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	return self:place(p, offset, opts)
end

----------------------------------------------------------------------------
-- primitives
----------------------------------------------------------------------------
function ModelKit:box(name, size: Vector3, offset: CFrame, color, material, opts)
	return self:part(name, Enum.PartType.Block, size, offset, color, material, opts)
end

-- cylinder along the offset's local X axis; dz defaults to dy (round)
function ModelKit:cyl(name, length: number, dy: number, dz: number?, offset: CFrame, color, material, opts)
	return self:part(name, Enum.PartType.Cylinder, V3(length, dy, dz or dy), offset, color, material, opts)
end

function ModelKit:ball(name, diameter: number, offset: CFrame, color, material, opts)
	return self:part(name, Enum.PartType.Ball, V3(diameter, diameter, diameter), offset, color, material, opts)
end

local function aim(a: Vector3, b: Vector3): CFrame
	local dir = b - a
	local up = V3(0, 1, 0)
	if dir.Magnitude > 0 and math.abs(dir.Unit.Y) > 0.98 then
		up = V3(0, 0, 1)
	end
	return CFrame.lookAt((a + b) / 2, b, up)
end

-- square bar between two points
function ModelKit:strut(name, a: Vector3, b: Vector3, thick: number, color, material, opts)
	local len = (b - a).Magnitude
	return self:box(name, V3(thick, thick, len), aim(a, b), color, material, opts)
end

-- flat bar (width x thick) between two points; `thick` is the dimension
-- perpendicular to the strut's local X (width)
function ModelKit:strip(name, a: Vector3, b: Vector3, width: number, thick: number, color, material, opts)
	local len = (b - a).Magnitude
	return self:box(name, V3(width, thick, len + 0.02), aim(a, b), color, material, opts)
end

-- round tube between two points
function ModelKit:tube(name, a: Vector3, b: Vector3, dia: number, color, material, opts)
	local len = (b - a).Magnitude
	return self:cyl(name, len, dia, dia, aim(a, b) * CFrame.Angles(0, math.pi / 2, 0), color, material, opts)
end

-- tapered pipe built from stacked tubes (dia0 -> dia1)
function ModelKit:cone(name, a: Vector3, b: Vector3, dia0: number, dia1: number, steps: number, color, material, opts)
	for i = 1, steps do
		local t0, t1 = (i - 1) / steps, i / steps
		local d = dia0 + (dia1 - dia0) * (t0 + t1) / 2
		self:tube(name, a:Lerp(b, t0), a:Lerp(b, t1), d, color, material, opts)
	end
end

-- a rounded slab ("stadium" in side view) running along Z: tanks, seats, panels
function ModelKit:stadium(name, length: number, height: number, width: number, offset: CFrame, color, material, opts)
	local mid = math.max(length - height, 0.05)
	self:box(name, V3(width, height, mid), offset, color, material, opts)
	for _, s in ipairs({ -1, 1 }) do
		self:cyl(name, width, height, height, offset * CF(0, 0, s * mid / 2), color, material, opts)
	end
end

-- Catmull-Rom spline through the points (perSegment extra samples per span)
function ModelKit.spline(pts: { Vector3 }, perSegment: number): { Vector3 }
	if #pts < 3 then
		return pts
	end
	local out = {}
	for i = 1, #pts - 1 do
		local p0 = pts[math.max(i - 1, 1)]
		local p1, p2 = pts[i], pts[i + 1]
		local p3 = pts[math.min(i + 2, #pts)]
		for k = 0, perSegment - 1 do
			local t = k / perSegment
			local t2, t3 = t * t, t * t * t
			local a = p1 * 2
			local b = (p2 - p0) * t
			local c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
			local d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
			table.insert(out, (a + b + c + d) * 0.5)
		end
	end
	table.insert(out, pts[#pts])
	return out
end

-- smooth bent tube through points. The path is a spline (no sharp corners)
-- and joints get a ball only where the pipe bends noticeably.
function ModelKit:curve(name, pts: { Vector3 }, dia: number, color, material, opts)
	local raw = ModelKit.spline(pts, 4)
	local path = { raw[1] }
	for i = 2, #raw do
		if (raw[i] - path[#path]).Magnitude > 0.02 then
			table.insert(path, raw[i])
		end
	end
	for i = 1, #path - 1 do
		self:tube(name, path[i], path[i + 1], dia, color, material, opts)
	end
	for i = 2, #path - 1 do
		local d1 = (path[i] - path[i - 1]).Unit
		local d2 = (path[i + 1] - path[i]).Unit
		if d1:Dot(d2) < 0.985 then
			self:ball(name, dia * 1.02, CF(path[i]), color, material, opts)
		end
	end
end

-- A rounded capsule along Z (tanks, seats, shrouds): an elliptical body with
-- two tapering rings at each end, smooth from every side.
function ModelKit:pod(name, length: number, height: number, width: number, offset: CFrame, color, material, opts)
	local bodyLen = length * 0.6
	local axis = CFrame.Angles(0, math.pi / 2, 0)
	self:cyl(name, bodyLen, height, width, offset * axis, color, material, opts)
	local rings = { { 0.13, 0.9 }, { 0.07, 0.66 } }
	local z = bodyLen / 2
	for _, r in ipairs(rings) do
		local len = length * r[1]
		for _, s in ipairs({ -1, 1 }) do
			self:cyl(name, len, height * r[2], width * r[2], offset * CF(0, 0, s * (z + len / 2)) * axis, color, material, opts)
		end
		z += len
	end
end

-- quadratic bezier sample
function ModelKit.bezier(p0: Vector3, p1: Vector3, p2: Vector3, n: number): { Vector3 }
	local out = {}
	for i = 0, n do
		local t = i / n
		local a = p0:Lerp(p1, t)
		local b = p1:Lerp(p2, t)
		table.insert(out, a:Lerp(b, t))
	end
	return out
end

-- a band bent over a wheel (mudguards). Angles in radians measured from straight
-- up, positive toward `dir` (-1 = toward the front (-Z), +1 = toward the rear).
function ModelKit:arc(name, center: Vector3, radius: number, a0: number, a1: number, steps: number, width: number, thick: number, dir: number, color, material, opts)
	local prev
	for i = 0, steps do
		local a = a0 + (a1 - a0) * i / steps
		local p = center + V3(0, radius * math.cos(a), dir * radius * math.sin(a))
		if prev then
			self:strip(name, prev, p, width, thick, color, material, opts)
		end
		prev = p
	end
end

----------------------------------------------------------------------------
-- spoked wheel; axle along X through `center`
----------------------------------------------------------------------------
function ModelKit:wheel(name: string, center: Vector3, radius: number, width: number, o: { [string]: any }?)
	o = o or {}
	local rubber = Color3.fromRGB(24, 24, 26)
	local metal = o.rimColor or Color3.fromRGB(190, 194, 200)
	-- tyre: main tread + slightly narrower shoulders for a rounded profile
	self:cyl(name .. "Tyre", width, radius * 2, radius * 2, CF(center), rubber, Enum.Material.Rubber)
	for _, s in ipairs({ -1, 1 }) do
		self:cyl(name .. "TyreSide", width * 0.18, radius * 2 - 0.1, radius * 2 - 0.1, CF(center + V3(s * width * 0.46, 0, 0)), rubber, Enum.Material.Rubber)
	end
	if o.knobs then
		-- off-road style tread blocks
		local n = 22
		for i = 0, n - 1 do
			local a = i / n * math.pi * 2
			local dirv = V3(0, math.cos(a), math.sin(a))
			local cf = CFrame.lookAt(center + dirv * radius, center + dirv * (radius + 1)) * CFrame.Angles(0, 0, 0)
			self:box(name .. "Knob", V3(width * 0.9, 0.1, 0.16), cf, rubber, Enum.Material.Rubber)
		end
	end
	local rimR = radius * 0.78
	-- rim: a bright ring on each side of the tyre, a dark well inside it
	self:cyl(name .. "Rim", width * 0.5, rimR * 2, rimR * 2, CF(center), metal, Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		self:cyl(name .. "RimFace", 0.04, rimR * 2, rimR * 2, CF(center + V3(s * (width / 2 + 0.012), 0, 0)), metal, Enum.Material.Metal)
		self:cyl(name .. "RimWell", 0.04, rimR * 2 - 0.2, rimR * 2 - 0.2, CF(center + V3(s * (width / 2 + 0.03), 0, 0)), Color3.fromRGB(58, 60, 66), Enum.Material.Metal)
	end
	-- hub + spokes
	local hubR = o.hubRadius or 0.2
	self:cyl(name .. "Hub", width + 0.2, hubR * 2, hubR * 2, CF(center), metal, Enum.Material.Metal)
	local spokes = o.spokes or 12
	local spokeR = rimR - 0.08
	for _, s in ipairs({ -1, 1 }) do
		for i = 0, spokes - 1 do
			local a = i / spokes * math.pi * 2
			local tw = (s * 0.42)
			local p0 = center + V3(s * (width / 2 + 0.06), hubR * math.cos(a), hubR * math.sin(a))
			local p1 = center + V3(s * (width / 2 + 0.05), spokeR * math.cos(a + tw), spokeR * math.sin(a + tw))
			self:strut(name .. "Spoke", p0, p1, 0.05, metal, Enum.Material.Metal)
		end
	end
	if o.drum then
		self:cyl(name .. "Drum", 0.2, hubR * 5, hubR * 5, CF(center + V3(o.drumSide or 0.3, 0, 0)), Color3.fromRGB(150, 152, 158), Enum.Material.Metal)
	end
	if o.disc then
		local side = o.discSide or 0.2
		self:cyl(name .. "Disc", 0.03, radius * 1.15, radius * 1.15, CF(center + V3(side, 0, 0)), Color3.fromRGB(176, 178, 184), Enum.Material.Metal)
		self:cyl(name .. "DiscHub", 0.05, hubR * 3, hubR * 3, CF(center + V3(side, 0, 0)), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	end
end

-- text painted on one face of a part (signs, number plates, price boards)
function ModelKit.signText(part: BasePart, text: string, face: Enum.NormalId, textColor: Color3?, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = textColor or Color3.fromRGB(30, 30, 30)
	t.Font = font or Enum.Font.GothamBold
	t.TextScaled = true
	t.Parent = gui
	return t
end

function ModelKit:attach(name: string, pos: Vector3)
	local root = self.root
	if root and not root:FindFirstChild(name) then
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = root
	end
end

return ModelKit
