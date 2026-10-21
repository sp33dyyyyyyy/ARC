--!strict
-- GearModels: the packs and chalk bags you see on climbers' backs and hips, built from
-- rounded parts (no uploaded meshes). Shared: ShopService welds them onto characters, and
-- the locker UI shows them in a preview.
--
-- Every model is built around its "Anchor" part (invisible, the PrimaryPart): for a pack
-- that's the middle of the wearer's back, with the pack behind it (+Z); for a chalk bag,
-- the back of the right hip.

local GearModels = {}

local STRAP = Color3.fromRGB(36, 38, 44)

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, shape: ("ellipsoid" | "cylinder" | "box")?, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = model
	return p
end

local function newModel(name: string): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local anchor = newPart(model, "Anchor", Vector3.new(0.2, 0.2, 0.2), CFrame.identity, STRAP, "box")
	anchor.Transparency = 1
	model.PrimaryPart = anchor
	return model, anchor
end

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis (X) to up

-- The pack `id` in `color`, built at the origin (see the header).
function GearModels.pack(id: string, color: Color3): Model
	local model = newModel("GearPack")
	local darker = color:Lerp(Color3.new(0, 0, 0), 0.25)
	local depth = 0.55
	if id == "CragPack" then
		newPart(model, "Body", Vector3.new(1.45, 2.1, 0.9), CFrame.new(0, 0.05, 0.45 + depth / 2), color, "ellipsoid")
		newPart(model, "Lid", Vector3.new(1.3, 0.5, 0.85), CFrame.new(0, 1.05, 0.5 + depth / 2), darker, "ellipsoid")
		newPart(model, "Rope", Vector3.new(1.5, 0.45, 0.45), CFrame.new(0, 1.25, 0.6 + depth / 2), Color3.fromRGB(245, 205, 40), "cylinder")
	elseif id == "Duffel" then
		newPart(model, "Body", Vector3.new(1.9, 0.95, 0.95), CFrame.new(0, -0.1, 0.48 + depth / 2) * CFrame.Angles(0, 0, math.rad(-12)), color, "cylinder")
		for _, x in { -0.96, 0.96 } do
			newPart(model, "End", Vector3.new(0.06, 0.97, 0.97), CFrame.new(x * math.cos(math.rad(12)), -0.1 - x * math.sin(math.rad(12)), 0.48 + depth / 2) * CFrame.Angles(0, 0, math.rad(-12)), darker, "cylinder")
		end
	elseif id == "HaulBag" then
		newPart(model, "Body", Vector3.new(2.3, 1.35, 1.35), CFrame.new(0, 0, 0.6 + depth / 2) * VERTICAL, color, "cylinder")
		newPart(model, "Top", Vector3.new(0.1, 1.38, 1.38), CFrame.new(0, 1.15, 0.6 + depth / 2) * VERTICAL, darker, "cylinder")
		for _, x in { -0.35, 0.35 } do
			newPart(model, "HaulStrap", Vector3.new(0.12, 0.9, 0.08), CFrame.new(x, 1.55, 0.6 + depth / 2), STRAP, "box")
		end
	else -- DayPack
		newPart(model, "Body", Vector3.new(1.35, 1.75, 0.75), CFrame.new(0, 0, 0.38 + depth / 2), color, "ellipsoid")
		newPart(model, "Pocket", Vector3.new(0.9, 0.7, 0.35), CFrame.new(0, -0.35, 0.72 + depth / 2), darker, "ellipsoid")
	end
	-- Shoulder straps over the front of the shoulders.
	for _, x in { -0.42, 0.42 } do
		newPart(model, "Strap", Vector3.new(0.18, 1.6, 0.08), CFrame.new(x, 0.1, -0.52), STRAP, "box")
		newPart(model, "StrapTop", Vector3.new(0.18, 0.08, 1.1), CFrame.new(x, 0.92, 0.02), STRAP, "box")
	end
	return model
end

-- A chalk bag in `color`, built at the origin (see the header).
function GearModels.chalkBag(color: Color3): Model
	local model = newModel("GearChalkBag")
	newPart(model, "Bag", Vector3.new(0.62, 0.58, 0.58), CFrame.new(0, -0.05, 0.32) * VERTICAL, color, "cylinder")
	newPart(model, "Rim", Vector3.new(0.08, 0.62, 0.62), CFrame.new(0, 0.26, 0.32) * VERTICAL, Color3.fromRGB(236, 236, 232), "cylinder")
	newPart(model, "Belt", Vector3.new(0.5, 0.12, 0.3), CFrame.new(0, 0.1, 0.05), STRAP, "box")
	return model
end

-- Welds `model` (built at the origin) onto `bodyPart` at `offset` in its local space.
function GearModels.attach(model: Model, bodyPart: BasePart, offset: CFrame)
	local anchor = model.PrimaryPart :: BasePart
	local base = anchor.CFrame
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = bodyPart.CFrame * offset * base:ToObjectSpace(d.CFrame)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bodyPart
			weld.Part1 = d
			weld.Parent = d
		end
	end
end

return table.freeze(GearModels)
