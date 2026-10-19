--[[
	BikeFactory  (ModuleScript, ReplicatedStorage/Shared)

	Creates a bike Model for a VehicleData entry.

	* If ReplicatedStorage/VehicleModels/<vehicleId> exists (your imported mesh
	  model), that is cloned. Requirements for your own models:
	    - a part named "Chassis" set as PrimaryPart (its centre is the
	      suspension origin; see the README for the exact axes)
	    - a Seat named "Seat" (optional - one is added if missing)
	    - parts with the Attribute Paint = "body" or "accent" get recoloured
	  Any missing interaction Attachment (FuelTapPoint, IgnitionPoint, ...) is
	  added automatically at a default position, so a model never "breaks".

	* Otherwise a blocky placeholder bike is built from the VehicleData
	  geometry, so the whole game is playable before you import anything.

	Local axes: -Z = forward, +X = right, +Y = up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(script.Parent.GameConfig)
local VehicleData = require(script.Parent.VehicleData)

local BikeFactory = {}

local DARK = Color3.fromRGB(36, 37, 41)
local METAL = Color3.fromRGB(150, 152, 158)

----------------------------------------------------------------------------
-- Geometry helpers
----------------------------------------------------------------------------

-- Distance from chassis centre to the wheel contact patch at rest.
-- Shared with BikePhysics so the visuals sit exactly on the ground.
function BikeFactory.rideHeight(geo): number
	local ceq = (workspace.Gravity / 2) / GameConfig.Physics.SpringK
	return geo.wheelRadius + 0.25 + ceq
end

local function addPart(model, chassis, name, size, offset: CFrame, color, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = opts.material or Enum.Material.SmoothPlastic
	if opts.shape then
		p.Shape = opts.shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	if opts.paint then
		p:SetAttribute("Paint", opts.paint)
	end
	p.Parent = model
	if chassis then
		-- place it where the weld will hold it, so PivotTo works before the weld "snaps"
		p.CFrame = chassis.CFrame * offset
		local w = Instance.new("Weld")
		w.Part0 = chassis
		w.Part1 = p
		w.C0 = offset
		w.Parent = p
	else
		p.CFrame = offset
	end
	return p
end

-- A thin bar between two chassis-local points.
local function strut(model, chassis, name, a: Vector3, b: Vector3, thickness: number, color)
	local len = (b - a).Magnitude
	return addPart(model, chassis, name, Vector3.new(thickness, thickness, len), CFrame.lookAt((a + b) / 2, b), color)
end

local function attach(chassis: BasePart, name: string, pos: Vector3)
	local a = chassis:FindFirstChild(name)
	if not a then
		a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = chassis
	end
end

----------------------------------------------------------------------------
-- Interaction points (prompts + exhaust) - added to any model that lacks them
----------------------------------------------------------------------------
function BikeFactory.ensureAttachments(model: Model, vehicle)
	local chassis = model.PrimaryPart :: BasePart
	local L = vehicle.geometry.wheelbase
	attach(chassis, "SeatPoint", Vector3.new(0, 1.3, L * 0.2))
	attach(chassis, "HandlebarPoint", Vector3.new(0, 2.0, -L / 2 + 0.7))
	attach(chassis, "FuelTapPoint", Vector3.new(-0.7, 1.2, -L * 0.05))
	attach(chassis, "IgnitionPoint", Vector3.new(0, 1.8, -L / 2 + 0.95))
	attach(chassis, "ChokePoint", Vector3.new(0.7, 0.5, L * 0.10))
	attach(chassis, "KickPoint", Vector3.new(0.8, -0.1, L * 0.22))
	attach(chassis, "StarterPoint", Vector3.new(0.6, 2.0, -L / 2 + 0.8))
	attach(chassis, "ExhaustPoint", Vector3.new(0.55, -0.1, L * 0.56))
end

----------------------------------------------------------------------------
-- Paint
----------------------------------------------------------------------------
function BikeFactory.applyPaint(model: Model, vehicle, paintIndex: number)
	local colour = vehicle.colours[paintIndex] or vehicle.colours[1]
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local kind = d:GetAttribute("Paint")
			if kind == "body" then
				d.Color = colour.body
			elseif kind == "accent" then
				d.Color = colour.accent
			end
		end
	end
	model:SetAttribute("Paint", paintIndex)
end

----------------------------------------------------------------------------
-- Procedural placeholder bike
----------------------------------------------------------------------------
function BikeFactory.build(vehicle, paintIndex: number): Model
	local geo = vehicle.geometry
	local L, R = geo.wheelbase, geo.wheelRadius
	local model = Instance.new("Model")
	model.Name = vehicle.id

	-- Chassis = engine block + the physics body. Centre of the whole bike.
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(0.8, 0.7, L * 0.7)
	chassis.Color = DARK
	chassis.Material = Enum.Material.Metal
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CFrame = CFrame.new(0, 10, 0)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local function offs(x, y, z)
		return CFrame.new(x, y, z)
	end

	-- wheels (cylinders: length axis = X)
	local wheelY = -0.25
	for _, wz in ipairs({ -L / 2, L / 2 }) do
		local tyre = addPart(model, chassis, wz < 0 and "FrontWheel" or "RearWheel",
			Vector3.new(0.5, R * 2, R * 2), offs(0, wheelY, wz), Color3.fromRGB(28, 28, 30),
			{ shape = Enum.PartType.Cylinder, material = Enum.Material.Rubber })
		addPart(model, chassis, "Rim", Vector3.new(0.56, R * 1.1, R * 1.1), offs(0, wheelY, wz), METAL,
			{ shape = Enum.PartType.Cylinder, material = Enum.Material.Metal })
		tyre:SetAttribute("Wheel", true)
	end

	-- frame
	local hb = Vector3.new(0, 2.0, -L / 2 + 0.7) -- handlebar centre
	strut(model, chassis, "Fork", Vector3.new(0, wheelY, -L / 2), hb, 0.2, METAL)
	strut(model, chassis, "FrameRear", Vector3.new(0, wheelY, L / 2), Vector3.new(0, 1.2, L * 0.2), 0.22, DARK)
	strut(model, chassis, "FrameFront", Vector3.new(0, 0.2, -L * 0.2), Vector3.new(0, 1.7, -L / 2 + 0.75), 0.22, DARK)

	-- bodywork
	addPart(model, chassis, "Tank", Vector3.new(0.95, 0.8, L * 0.36), offs(0, 1.45, -L * 0.1),
		vehicle.colours[1].body, { paint = "body" })
	addPart(model, chassis, "Tail", Vector3.new(0.75, 0.3, L * 0.22), offs(0, 1.55, L * 0.42),
		vehicle.colours[1].body, { paint = "body" })
	addPart(model, chassis, "FrontFender", Vector3.new(0.6, 0.18, R * 1.6), offs(0, wheelY + R + 0.25, -L / 2),
		vehicle.colours[1].accent, { paint = "accent" })
	addPart(model, chassis, "Handlebar", Vector3.new(1.7, 0.14, 0.14), offs(hb.X, hb.Y, hb.Z), METAL,
		{ material = Enum.Material.Metal })
	addPart(model, chassis, "Headlight", Vector3.new(0.5, 0.5, 0.5), offs(0, 1.7, -L / 2 - 0.05),
		Color3.fromRGB(255, 245, 200), { shape = Enum.PartType.Ball, material = Enum.Material.Neon })
	-- exhaust (cylinder rotated so its length runs front-to-back)
	addPart(model, chassis, "Exhaust", Vector3.new(L * 0.55, 0.28, 0.28),
		offs(0.55, -0.1, L * 0.28) * CFrame.Angles(0, math.rad(90), 0), METAL,
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Metal })
	addPart(model, chassis, "Accent", Vector3.new(0.9, 0.12, L * 0.3), offs(0, 1.05, -L * 0.1),
		vehicle.colours[1].accent, { paint = "accent" })

	-- class-specific details so mopeds and supermotos read differently at a glance
	if vehicle.class == "Moped" then
		addPart(model, chassis, "LegShield", Vector3.new(1.1, 2.3, 0.3),
			offs(0, 0.95, -L / 2 + 1.0) * CFrame.Angles(math.rad(-12), 0, 0),
			vehicle.colours[1].body, { paint = "body" })
		addPart(model, chassis, "Rack", Vector3.new(1.0, 0.15, 1.6), offs(0, 1.8, L * 0.5), METAL,
			{ material = Enum.Material.Metal })
		addPart(model, chassis, "Basket", Vector3.new(0.9, 0.5, 0.9), offs(0, 0.9, -L / 2 + 0.2) * CFrame.Angles(math.rad(-12), 0, 0),
			Color3.fromRGB(120, 92, 60), { material = Enum.Material.WoodPlanks })
	else
		addPart(model, chassis, "NumberPlate", Vector3.new(0.95, 0.95, 0.15),
			offs(0, 1.6, -L / 2 - 0.18) * CFrame.Angles(math.rad(-14), 0, 0), Color3.fromRGB(245, 245, 240))
		for _, sx in ipairs({ -1, 1 }) do
			addPart(model, chassis, "HandGuard", Vector3.new(0.15, 0.6, 0.6), offs(sx * 0.95, 2.05, hb.Z - 0.25), DARK)
		end
		addPart(model, chassis, "SkidPlate", Vector3.new(0.8, 0.15, L * 0.4), offs(0, -0.4, 0), METAL,
			{ material = Enum.Material.Metal })
	end

	-- seat
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(0.9, 0.3, L * 0.36)
	seat.Color = DARK
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.CanCollide = false
	seat.CanQuery = false
	seat.Massless = true
	seat.Parent = model
	seat.CFrame = chassis.CFrame * offs(0, 1.55, L * 0.2)
	local sw = Instance.new("Weld")
	sw.Part0 = chassis
	sw.Part1 = seat
	sw.C0 = offs(0, 1.55, L * 0.2)
	sw.Parent = seat

	BikeFactory.ensureAttachments(model, vehicle)
	BikeFactory.applyPaint(model, vehicle, paintIndex)
	return model
end

----------------------------------------------------------------------------
-- Physics setup (server, once per spawned bike)
----------------------------------------------------------------------------
function BikeFactory.setupPhysics(model: Model, vehicle)
	local chassis = model.PrimaryPart :: BasePart
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= chassis then
			d.Massless = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	-- Chassis density chosen so AssemblyMass == weightKg * MassScale
	local targetMass = vehicle.stats.weightKg * GameConfig.MassScale
	local vol = chassis.Size.X * chassis.Size.Y * chassis.Size.Z
	local density = math.clamp(targetMass / vol, 0.01, 100)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(density, 0.2, 0, 1, 1)
	chassis.CanCollide = true
	-- make the chassis the root of the assembly so Massless on the rest really applies
	chassis.RootPriority = 127
end

----------------------------------------------------------------------------
-- Public entry point
----------------------------------------------------------------------------
function BikeFactory.create(vehicleId: string, paintIndex: number): Model?
	local vehicle = VehicleData.byId[vehicleId]
	if not vehicle then
		return nil
	end
	local store = ReplicatedStorage:FindFirstChild("VehicleModels")
	local template = store and store:FindFirstChild(vehicleId)
	if template and template:IsA("Model") and template.PrimaryPart then
		local model = template:Clone()
		BikeFactory.ensureAttachments(model, vehicle)
		BikeFactory.applyPaint(model, vehicle, paintIndex)
		return model
	end
	return BikeFactory.build(vehicle, paintIndex)
end

return BikeFactory
