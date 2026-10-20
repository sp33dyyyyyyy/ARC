-- Small helpers for creating anchored geometry from code.
local Build = {}

-- Create an instance, apply properties, then parent it last (cheaper replication).
function Build.part(parent: Instance, props: { [string]: any }): BasePart
	local part = Instance.new(props.ClassName or "Part") :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		-- Shape first: changing it afterwards can resize the part.
		(part :: Part).Shape = props.Shape
	end
	for key, value in props do
		if key ~= "ClassName" and key ~= "Attributes" and key ~= "Tags" and key ~= "Shape" then
			(part :: any)[key] = value
		end
	end
	if props.Attributes then
		for key, value in props.Attributes do
			part:SetAttribute(key, value)
		end
	end
	if props.Tags then
		for _, tag in props.Tags do
			part:AddTag(tag)
		end
	end
	part.Parent = parent
	return part
end

-- Decorative strut between two world points. Non-colliding so it never snags climbers.
function Build.beam(parent: Instance, a: Vector3, b: Vector3, thickness: number, props: { [string]: any }): BasePart
	local dir = b - a
	local length = dir.Magnitude
	local up = if math.abs(dir.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local merged = {
		Size = Vector3.new(thickness, thickness, length),
		CFrame = CFrame.lookAt((a + b) / 2, b, up),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}
	for key, value in props do
		merged[key] = value
	end
	return Build.part(parent, merged)
end

-- Vertical cylinder centred at `center`.
function Build.cylinder(parent: Instance, center: Vector3, height: number, diameter: number, props: { [string]: any }): BasePart
	local merged = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
	}
	for key, value in props do
		merged[key] = value
	end
	return Build.part(parent, merged)
end

-- Red blinking aviation light (blinking is driven by EnvironmentService).
function Build.aviationLight(parent: Instance, position: Vector3, size: number?): BasePart
	local bulb = Build.part(parent, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (size or 1.6),
		Position = position,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 40, 40),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Tags = { "AviationLight" },
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 60)
	light.Range = 24
	light.Brightness = 3
	light.Parent = bulb
	return bulb
end

-- Billboard-style sign text on the front face of a part.
function Build.surfaceText(part: BasePart, lines: { { text: string, size: number, color: Color3, font: Enum.Font? } })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = gui
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -20, 0, line.size)
		label.Font = line.font or Enum.Font.GothamBlack
		label.Text = line.text
		label.TextColor3 = line.color
		label.TextScaled = true
		label.Parent = gui
	end
	gui.Parent = part
	return gui
end

return Build
