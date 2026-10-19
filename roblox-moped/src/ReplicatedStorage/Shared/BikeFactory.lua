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
local PartsData = require(script.Parent.PartsData)

local BikeFactory = {}

local ModelKit = require(script.Parent.ModelKit)
local BikeModels = require(script.Parent.BikeModels)

----------------------------------------------------------------------------
-- Geometry helpers
----------------------------------------------------------------------------

-- Distance from chassis centre to the wheel contact patch at rest.
-- Shared with BikePhysics so the visuals sit exactly on the ground.
function BikeFactory.rideHeight(geo): number
	local ceq = (workspace.Gravity / 2) / GameConfig.Physics.SpringK
	return geo.wheelRadius + 0.25 + ceq
end

local function attach(chassis: BasePart, name: string, pos: Vector3)
	if not chassis:FindFirstChild(name) then
		local a = Instance.new("Attachment")
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
	attach(chassis, "SeatPoint", Vector3.new(0, 1.7, L * 0.25))
	attach(chassis, "HandlebarPoint", Vector3.new(0, 2.25, -L / 2 + 0.8))
	attach(chassis, "FuelTapPoint", Vector3.new(-0.7, 1.15, -0.1))
	attach(chassis, "IgnitionPoint", Vector3.new(0, 1.65, -L / 2 + 0.9))
	attach(chassis, "ChokePoint", Vector3.new(-0.5, 0.6, -0.3))
	attach(chassis, "KickPoint", Vector3.new(0.95, -0.5, 1.0))
	attach(chassis, "StarterPoint", Vector3.new(0.6, 2.2, -L / 2 + 0.8))
	attach(chassis, "ExhaustPoint", Vector3.new(0.64, -0.25, L * 0.62))
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
-- Aftermarket parts: how they look. Stats come from PartsData.apply; this only
-- recolours / rescales named parts of the model and remembers the originals
-- (attributes BaseColor / BaseSize) so removing a part puts everything back.
----------------------------------------------------------------------------
local rgbc = Color3.fromRGB
local MOD_LOOKS = {
	sport_exhaust = { colour = { { { "Muffler", "Silencer", "Header" }, rgbc(34, 34, 38) } } },
	race_pipe = { colour = { { { "Muffler", "Silencer", "Header" }, rgbc(176, 120, 64) } } },
	titan_exhaust = { colour = { { { "Muffler", "Silencer", "Header" }, rgbc(112, 128, 168) } } },
	air_kit = { colour = { { { "AirBox" }, rgbc(225, 150, 40) } } },
	big_carb = { colour = { { { "AirBox", "IntakeBoot" }, rgbc(210, 40, 40) } } },
	short_gear = { colour = { { { "Sprocket" }, rgbc(214, 168, 58) } } },
	long_gear = { colour = { { { "Sprocket" }, rgbc(214, 168, 58) } } },
	road_tyres = { colour = { { { "Rib" }, rgbc(72, 72, 78) } } },
	sport_tyres = { colour = { { { "Rib" }, rgbc(196, 30, 30) } } },
	steel_lines = { colour = { { { "Caliper" }, rgbc(200, 30, 30) } } },
	big_disc = { colour = { { { "Caliper" }, rgbc(200, 30, 30) } }, scale = { { "Disc$", Vector3.new(1, 1.22, 1.22) } } },
	fork_springs = { colour = { { { "ShockSpring", "MonoSpring" }, rgbc(200, 30, 30) } } },
	race_suspension = { colour = { { { "ForkTube", "ForkLeg", "ForkSlider", "ShockSpring", "MonoSpring" }, rgbc(214, 168, 58) } } },
	big_tank = { scale = { { "^Tank$", Vector3.new(1.1, 1.14, 1.14) } } },
	light_frame = { colour = { { { "Cradle", "SubFrame", "SwingArm", "SeatStay" }, rgbc(205, 208, 216) } } },
}

function BikeFactory.applyMods(model: Model, mods: { string })
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			-- put the stock look back first
			local c = d:GetAttribute("BaseColor")
			if c then
				d.Color = c
			end
			local s = d:GetAttribute("BaseSize")
			if s then
				d.Size = s
			end
		end
	end
	for _, id in ipairs(mods) do
		local look = MOD_LOOKS[id]
		if look then
			for _, p in ipairs(parts) do
				for _, rule in ipairs(look.colour or {}) do
					for _, pattern in ipairs(rule[1]) do
						if string.find(p.Name, pattern) then
							if p:GetAttribute("BaseColor") == nil then
								p:SetAttribute("BaseColor", p.Color)
							end
							p.Color = rule[2]
							break
						end
					end
				end
				for _, rule in ipairs(look.scale or {}) do
					if string.find(p.Name, rule[1]) then
						if p:GetAttribute("BaseSize") == nil then
							p:SetAttribute("BaseSize", p.Size)
						end
						local base = p:GetAttribute("BaseSize") :: Vector3
						p.Size = Vector3.new(base.X * rule[2].X, base.Y * rule[2].Y, base.Z * rule[2].Z)
					end
				end
			end
		end
	end
	model:SetAttribute("Mods", PartsData.encode(mods))
end

----------------------------------------------------------------------------
-- Procedural bike (detailed, part-built; see BikeModels)
----------------------------------------------------------------------------
function BikeFactory.styleOf(vehicle): string
	if vehicle.geometry.style then
		return vehicle.geometry.style
	end
	if vehicle.class == "Supermoto" then
		return "supermoto"
	end
	return vehicle.drivetrain.transmission == "cvt" and "scooter" or "moped"
end

function BikeFactory.build(vehicle, paintIndex: number): Model
	local L = vehicle.geometry.wheelbase
	local model = Instance.new("Model")
	model.Name = vehicle.id

	-- Chassis = the invisible physics body (centre of the whole bike)
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(0.8, 0.7, L * 0.7)
	chassis.Transparency = 1
	chassis.CanQuery = false -- invisible; mouse rays must pass through to the clickable controls
	chassis.Material = Enum.Material.Metal
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CFrame = CFrame.new(0, 10, 0)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local kit = ModelKit.new(model, chassis, chassis.CFrame)
	local builder = BikeModels[BikeFactory.styleOf(vehicle)]
	builder(kit, vehicle)

	-- The sit target: an invisible Seat at the saddle
	local seatAt = chassis:FindFirstChild("SeatPoint") :: Attachment
	local seatPos = seatAt and seatAt.Position or Vector3.new(0, 1.6, L * 0.2)
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(0.9, 0.3, 1.6)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanQuery = false
	seat.CanTouch = false
	seat.Massless = true
	seat.CFrame = chassis.CFrame * CFrame.new(seatPos - Vector3.new(0, 0.15, 0))
	seat.Parent = model
	local sw = Instance.new("Weld")
	sw.Part0 = chassis
	sw.Part1 = seat
	sw.C0 = CFrame.new(seatPos - Vector3.new(0, 0.15, 0))
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
