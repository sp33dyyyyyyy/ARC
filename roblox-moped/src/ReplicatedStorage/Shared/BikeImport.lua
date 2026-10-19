--[[
	BikeImport  (ModuleScript, ReplicatedStorage/Shared)

	Turns a bike you imported from a .glb (Studio's 3D Importer) into a game
	bike. The data about the file - part names, colours, which parts steer or
	spin, pivots of the kickstand / fuel tap / key / choke - is in
	ImportedModels (generated from the .glb by tools/glb_to_lua.py).

	What it does with the imported Model (ReplicatedStorage/VehicleModels/<id>):
	  1. scales it so the tyres match VehicleData.geometry (physics = visuals)
	  2. works out which way is forward from the two tyres (the importer may
	     have turned the model around) and builds the invisible Chassis there
	  3. welds every part to the chassis, applies the file's colours/materials
	     and the two paint options, adds the interaction attachments
	  4. builds the animated groups with BikeRig: steering, kickstand,
	     fuel tap, ignition key, choke, and a kick-start lever (the file has none)
]]

local BikeRig = require(script.Parent.BikeRig)
local ImportedModels = require(script.Parent.ImportedModels)
local ModelKit = require(script.Parent.ModelKit)

local BikeImport = {}

local V3 = Vector3.new

function BikeImport.hasSpec(vehicleId: string): boolean
	return ImportedModels[vehicleId] ~= nil
end

local function attach(chassis: BasePart, name: string, pos: Vector3)
	local a = chassis:FindFirstChild(name)
	if not a then
		a = Instance.new("Attachment")
		a.Name = name
		a.Parent = chassis
	end
	a.Position = pos
end

function BikeImport.adapt(template: Model, vehicle): Model?
	local spec = ImportedModels[vehicle.id]
	if not spec then
		return nil
	end
	local model = template:Clone()
	model.Name = vehicle.id

	local byName: { [string]: BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if byName[d.Name] == nil then
				byName[d.Name] = d
			end
			-- no stray textures: the colours come from ImportedModels
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("SurfaceAppearance") or c:IsA("Decal") or c:IsA("Texture") then
					c:Destroy()
				end
			end
		end
	end
	local front, rear = byName[spec.frontTyre], byName[spec.rearTyre]
	if not (front and rear) then
		warn(("[BikeImport] %s: parts '%s' / '%s' not found in the imported model"):format(vehicle.id, spec.frontTyre, spec.rearTyre))
		return nil
	end

	-- 1. scale: tyres match the physics geometry
	local diameter = math.max(front.Size.X, front.Size.Y, front.Size.Z)
	local factor = (vehicle.geometry.wheelRadius * 2) / diameter
	model:ScaleTo(model:GetScale() * factor)
	local studsPerUnit = vehicle.geometry.wheelRadius / spec.tyreRadius

	-- 2. orientation + chassis
	local frontPos, rearPos = front.Position, rear.Position
	local fobs = Vector3.new(frontPos.X - rearPos.X, 0, frontPos.Z - rearPos.Z).Unit
	local zero = V3()
	local R = CFrame.lookAt(zero, fobs) * CFrame.lookAt(zero, spec.forward):Inverse()
	local function world(g: Vector3): Vector3
		return frontPos + R:VectorToWorldSpace((g - spec.frontCentre) * studsPerUnit)
	end
	local function worldDir(g: Vector3): Vector3
		return R:VectorToWorldSpace(g).Unit
	end

	local mid = (frontPos + rearPos) / 2
	local chassisPos = V3(mid.X, (frontPos.Y + rearPos.Y) / 2 + 0.25, mid.Z)
	local chassisCF = CFrame.lookAt(chassisPos, chassisPos + fobs)
	local L = vehicle.geometry.wheelbase

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = V3(0.8, 0.7, L * 0.7)
	chassis.Transparency = 1
	chassis.CanQuery = false
	chassis.Material = Enum.Material.Metal
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CFrame = chassisCF
	chassis.Anchored = true
	chassis.Parent = model
	model.PrimaryPart = chassis

	local function local_(g: Vector3): Vector3
		return chassisCF:PointToObjectSpace(world(g))
	end

	-- 3. colours, welds
	for name, part in pairs(byName) do
		local look = spec.parts[name]
		if look then
			part.Color = look.c
			part.Material = Enum.Material[look.m]
			part.Transparency = look.t
			if look.paint then
				part:SetAttribute("Paint", look.paint)
			end
		end
		part.Anchored = false
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
		part.Massless = true
		local w = Instance.new("Weld")
		w.Name = "Weld"
		w.Part0 = chassis
		w.Part1 = part
		w.C0 = chassisCF:ToObjectSpace(part.CFrame)
		w.Parent = part
	end
	chassis.Anchored = false

	-- wheel spin groups (EffectsController turns them about the axle)
	local function tagWheel(names: { string }, group: string, centre: Vector3)
		for _, n in ipairs(names) do
			local p = byName[n]
			if p then
				p:SetAttribute("Wheel", group)
				p:SetAttribute("WheelCenter", centre)
			end
		end
	end
	tagWheel(spec.wheelFront, "Front", chassisCF:PointToObjectSpace(frontPos))
	tagWheel(spec.wheelRear, "Rear", chassisCF:PointToObjectSpace(rearPos))

	-- interaction points
	attach(chassis, "SeatPoint", local_(spec.seatPoint) + V3(0, 0.35, 0))
	attach(chassis, "HandlebarPoint", local_(spec.barsPoint))
	attach(chassis, "FuelTapPoint", local_(spec.tapPoint))
	attach(chassis, "IgnitionPoint", local_(spec.ignitionPoint))
	attach(chassis, "ChokePoint", local_(spec.chokePoint))
	attach(chassis, "StarterPoint", local_(spec.starterPoint))
	attach(chassis, "ExhaustPoint", local_(spec.exhaustPoint))
	attach(chassis, "KickPoint", local_(spec.kickTip))

	-- the invisible Seat the rider sits on (the mesh called "Seat" is only the cushion)
	local seatAt = chassis:FindFirstChild("SeatPoint") :: Attachment
	local sit = Instance.new("Seat")
	sit.Name = "SitSeat"
	sit.Size = V3(0.9, 0.3, 1.6)
	sit.Transparency = 1
	sit.CanCollide, sit.CanQuery, sit.CanTouch = false, false, false
	sit.Massless = true
	sit.CFrame = chassisCF * CFrame.new(seatAt.Position - V3(0, 0.15, 0))
	sit.Parent = model
	local sw = Instance.new("Weld")
	sw.Part0 = chassis
	sw.Part1 = sit
	sw.C0 = CFrame.new(seatAt.Position - V3(0, 0.15, 0))
	sw.Parent = sit

	-- kick-start lever (the file has none): a tube and a rubber pad
	local kit = ModelKit.new(model, chassis, chassisCF)
	local kp, kt = local_(spec.kickPivot), local_(spec.kickTip)
	local leverPart = kit:tube("KickLever", kp, kt, 0.2, Color3.fromRGB(150, 154, 162), Enum.Material.Metal)
	local padPart = kit:box("KickPad", V3(0.34, 0.14, 0.4), CFrame.new(kt), Color3.fromRGB(24, 24, 26), Enum.Material.Rubber)
	for _, p in ipairs({ leverPart, padPart }) do
		p.CanCollide, p.CanQuery = false, false
	end

	-- 4. animated groups
	local right = chassisCF.RightVector
	local steerParts, taken = {}, { Choke = true }
	for _, n in ipairs(spec.steerParts) do
		if byName[n] and not taken[n] then
			table.insert(steerParts, byName[n])
		end
	end
	local steerPivot = BikeRig.group(model, chassis, {
		name = "Steer", anim = "Steer", point = world(spec.steer.point), axis = worldDir(spec.steer.dir), parts = steerParts, a1 = 0.6,
	})

	local function animGroup(key: string, kind: string, extra)
		local a = spec[key]
		local part = byName[a.part]
		if not part then
			return
		end
		local s = {
			name = key, anim = kind, point = world(a.pivot), axis = worldDir(a.axis), parts = { part }, a1 = a.angle,
		}
		for k, v in pairs(extra or {}) do
			s[k] = v
		end
		BikeRig.group(model, chassis, s)
	end
	-- the stand is modelled FOLDED; parked = rotated down by the file's angle
	animGroup("stand", "Stand", { tip = world(spec.standTip), hint = V3(0, -1, 0) })
	animGroup("tap", "Tap")
	animGroup("key", "Key")
	animGroup("choke", "Choke", { parent = steerPivot }) -- sits on the bars, so it steers too

	BikeRig.group(model, chassis, {
		name = "Kick", anim = "Kick", point = world(spec.kickPivot), axis = right, parts = { leverPart, padPart }, a1 = 1.15,
		tip = world(spec.kickTip), hint = fobs - V3(0, 0.8, 0),
	})
	return model
end

return BikeImport
