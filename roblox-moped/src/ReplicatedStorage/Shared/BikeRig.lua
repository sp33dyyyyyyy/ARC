--[[
	BikeRig  (ModuleScript, ReplicatedStorage/Shared)

	Turns parts of a finished bike model into animated groups. A group is an
	invisible PIVOT part sitting on the rotation axis; the parts that move with
	it are welded to the pivot, and the pivot is welded to the chassis (or to
	another pivot) by a Weld called "J". The server only builds this once. Every
	client then animates `J.C0` locally (EffectsController) - purely visual.

	Pivot attributes (read by EffectsController):
	  Anim      "Steer" | "Stand" | "Kick" | "Tap" | "Key" | "Choke"
	  A1        angle in radians reached at state 1
	  Inverted  true: the model is built in its state-1 pose (see Stand)
	  Pivot frame: local Y = rotation axis, local X = bike's right (roughly)

	Used two ways:
	  BikeRig.auto   - the built-in part-built bikes (finds the parts by name)
	  BikeRig.group  - BikeImport, with data measured from the imported meshes
]]

local BikeRig = {}

local V3 = Vector3.new

-- A part's two ends along its longest side (tubes and struts), world space.
function BikeRig.ends(part: BasePart): (Vector3, Vector3)
	local s = part.Size
	local axis, half
	if s.X >= s.Y and s.X >= s.Z then
		axis, half = part.CFrame.RightVector, s.X / 2
	elseif s.Y >= s.Z then
		axis, half = part.CFrame.UpVector, s.Y / 2
	else
		axis, half = part.CFrame.LookVector, s.Z / 2
	end
	return part.Position - axis * half, part.Position + axis * half
end

local function weldTo(part: BasePart, parent: BasePart)
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("Weld") or c:IsA("WeldConstraint") then
			c:Destroy()
		end
	end
	local w = Instance.new("Weld")
	w.Name = "Weld"
	w.Part0 = parent
	w.Part1 = part
	w.C0 = parent.CFrame:ToObjectSpace(part.CFrame)
	w.Parent = part
end

--[[ spec:
	name     string
	anim     "Steer" | "Stand" | "Kick" | ...
	point    Vector3   world point on the axis
	axis     Vector3   world axis direction
	parts    { BasePart }
	a1       number    radians at state 1
	tip      Vector3?  with `hint`: a point that should move toward `hint`
	hint     Vector3?  when rotating by +a1 (the axis is flipped if needed)
	inverted boolean?
	parent   BasePart? pivot to hang this one on (default: the chassis)
]]
function BikeRig.group(model: Model, chassis: BasePart, spec): BasePart
	local axis = spec.axis.Unit
	if spec.tip and spec.hint then
		local motion = axis:Cross(spec.tip - spec.point)
		if motion:Dot(spec.hint) < 0 then
			axis = -axis
		end
	end
	local ref = chassis.CFrame.RightVector
	if math.abs(ref:Dot(axis)) > 0.95 then
		ref = chassis.CFrame.UpVector
	end
	local x = (ref - axis * ref:Dot(axis)).Unit
	local z = x:Cross(axis)

	local pivot = Instance.new("Part")
	pivot.Name = "Pivot_" .. spec.name
	pivot.Size = V3(0.2, 0.2, 0.2)
	pivot.Transparency = 1
	pivot.CanCollide, pivot.CanQuery, pivot.CanTouch = false, false, false
	pivot.Massless = true
	pivot.CastShadow = false
	pivot.CFrame = CFrame.fromMatrix(spec.point, x, axis, z)
	pivot:SetAttribute("Anim", spec.anim)
	pivot:SetAttribute("A1", spec.a1)
	pivot:SetAttribute("Inverted", spec.inverted == true)
	pivot.Parent = model

	local parent = spec.parent or chassis
	local j = Instance.new("Weld")
	j.Name = "J"
	j.Part0 = parent
	j.Part1 = pivot
	j.C0 = parent.CFrame:ToObjectSpace(pivot.CFrame)
	j.Parent = pivot

	for _, part in ipairs(spec.parts) do
		-- wheel centres are stored in the frame of the weld's Part0
		local centre = part:GetAttribute("WheelCenter")
		if centre then
			local world = chassis.CFrame:PointToWorldSpace(centre)
			part:SetAttribute("WheelCenter", pivot.CFrame:PointToObjectSpace(world))
		end
		weldTo(part, pivot)
	end
	return pivot
end

----------------------------------------------------------------------------
-- The built-in part-built bikes
----------------------------------------------------------------------------
local STEER_PREFIX = {
	"Front", "Fork", "TopYoke", "BottomYoke", "AxleBrace", "AxlePlate", "Handlebar", "Grip", "Lever",
	"Mirror", "Speedo", "Headlight", "BarCowl", "BarBrace", "NumberBoard", "FenderBridge", "FenderStay",
}

local function startsWithAny(name: string, list: { string }): boolean
	for _, p in ipairs(list) do
		if string.sub(name, 1, #p) == p then
			return true
		end
	end
	return false
end

function BikeRig.auto(model: Model, chassis: BasePart, vehicle)
	local steer, stand, kick = {}, {}, {}
	local bars = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= chassis and d.Name ~= "Seat" then
			local n = d.Name
			if n == "Handlebar" then
				table.insert(bars, d.Position)
			end
			if n == "Kickstand" or n == "Centrestand" then
				table.insert(stand, d)
			elseif n == "KickLever" or n == "KickPad" then
				table.insert(kick, d)
			elseif n ~= "FrontSprocket" and (d:GetAttribute("Wheel") == "Front" or startsWithAny(n, STEER_PREFIX)) then
				table.insert(steer, d)
			end
		end
	end

	local cf = chassis.CFrame
	local right, up, back = cf.RightVector, cf.UpVector, -cf.LookVector

	if #steer > 0 and #bars > 0 then
		local sum = V3()
		for _, p in ipairs(bars) do
			sum += p
		end
		local top = sum / #bars
		local wheel = cf:PointToWorldSpace(V3(0, -0.25, -vehicle.geometry.wheelbase / 2))
		BikeRig.group(model, chassis, { name = "Steer", anim = "Steer", point = wheel, axis = top - wheel, parts = steer, a1 = 0.6 })
	end

	-- built in their DOWN pose, so state 1 (parked = 0) folds them
	for _, part in ipairs(stand) do
		local a, b = BikeRig.ends(part)
		local hi, lo = a, b
		if b.Y > a.Y then
			hi, lo = b, a
		end
		BikeRig.group(model, chassis, {
			name = "Stand", anim = "Stand", point = hi, axis = right, parts = { part }, a1 = 1.25,
			tip = lo, hint = up + back, inverted = true,
		})
	end

	-- kick lever: swings down and forward on every kick
	local lever
	for _, part in ipairs(kick) do
		if part.Name == "KickLever" then
			lever = part
		end
	end
	if lever then
		local a, b = BikeRig.ends(lever)
		local hi, lo = a, b
		if b.Y > a.Y then
			hi, lo = b, a
		end
		BikeRig.group(model, chassis, {
			name = "Kick", anim = "Kick", point = hi, axis = right, parts = kick, a1 = 1.0,
			tip = lo, hint = -back * 1.0 - up * 0.6,
		})
	end
end

return BikeRig
