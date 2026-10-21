--!strict
-- Environment: realistic lighting and post-processing (Future lighting, PBR reflections,
-- soft shadows, atmosphere, gentle bloom and colour grading).
--
-- Applied once per place: afterwards Lighting carries the attribute "ClimbLookApplied"
-- and your own tweaks in Studio are left alone. Post effects are only added when Lighting
-- has none of that class. To re-apply the preset, run in the command bar:
--     require(game.ServerScriptService.Server.World.Environment).Apply(true)

local Lighting = game:GetService("Lighting")

local APPLIED_ATTRIBUTE = "ClimbLookApplied"

local Environment = {}

local function ensureEffect<T>(className: string, configure: (T) -> ())
	if Lighting:FindFirstChildWhichIsA(className) then
		return
	end
	local effect = Instance.new(className :: any)
	configure(effect :: any)
	effect.Parent = Lighting
end

function Environment.Apply(force: boolean?)
	if Lighting:GetAttribute(APPLIED_ATTRIBUTE) and not force then
		return
	end
	if force then
		for _, className in { "Atmosphere", "BloomEffect", "ColorCorrectionEffect", "SunRaysEffect" } do
			local existing = Lighting:FindFirstChildWhichIsA(className)
			if existing then
				existing:Destroy()
			end
		end
	end

	-- Future is the only technology with per-light shadows and specular highlights.
	-- It is also set by the Rojo project; this covers places set up by hand.
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)

	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 41
	Lighting.Brightness = 3
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = Color3.fromRGB(58, 60, 66)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 124, 132)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 246, 232)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	-- Image-based lighting: without these, PBR materials look flat and plasticky.
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.18

	ensureEffect("Atmosphere", function(atmosphere: Atmosphere)
		atmosphere.Density = 0.3
		atmosphere.Offset = 0.25
		atmosphere.Color = Color3.fromRGB(199, 205, 214)
		atmosphere.Decay = Color3.fromRGB(106, 112, 125)
		atmosphere.Glare = 0.1
		atmosphere.Haze = 1.2
	end)
	ensureEffect("BloomEffect", function(bloom: BloomEffect)
		bloom.Intensity = 0.35
		bloom.Size = 24
		bloom.Threshold = 1.6
	end)
	ensureEffect("ColorCorrectionEffect", function(grade: ColorCorrectionEffect)
		grade.Brightness = 0.01
		grade.Contrast = 0.06
		grade.Saturation = 0.04
		grade.TintColor = Color3.fromRGB(255, 252, 247)
	end)
	ensureEffect("SunRaysEffect", function(rays: SunRaysEffect)
		rays.Intensity = 0.04
		rays.Spread = 0.6
	end)

	Lighting:SetAttribute(APPLIED_ATTRIBUTE, true)
end

return Environment
