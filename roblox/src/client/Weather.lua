-- Client weather: rain that follows the camera, lightning flashes, and the
-- slippery-wall stamina multiplier. The server picks the weather and tweens the
-- sky; it publishes the current state as Workspace's "Weather" attribute.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Weather = {}

local RAIN_RATE = 900

function Weather.current(): string
	return Workspace:GetAttribute("Weather") or "Clear"
end

-- Stamina drain multiplier from the weather (rain makes every wall slippery).
function Weather.drainMultiplier(): number
	return if Weather.current() == "Rain" then Config.Weather.RainDrainMultiplier else 1
end

function Weather.start(onChanged: (name: string) -> ())
	-- Rain: a wide invisible emitter that rides above the camera.
	local cloud = Instance.new("Part")
	cloud.Name = "RainCloud"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Transparency = 1
	cloud.Size = Vector3.new(160, 1, 160)
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.Shape = Enum.ParticleEmitterShape.Box
	rain.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Speed = NumberRange.new(110, 140)
	rain.Lifetime = NumberRange.new(0.7, 1)
	rain.Size = NumberSequence.new(0.18)
	rain.Squash = NumberSequence.new(2.5) -- stretch drops into streaks
	rain.Color = ColorSequence.new(Color3.fromRGB(200, 212, 235))
	rain.Transparency = NumberSequence.new(0.35)
	rain.LightEmission = 0.2
	rain.Rate = 0
	rain.Parent = cloud
	cloud.Parent = Workspace

	local flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "Lightning"
	flash.Parent = Lighting

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera then
			cloud.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
		end
	end)

	local function apply()
		local name = Weather.current()
		rain.Rate = if name == "Rain" then RAIN_RATE else 0
		onChanged(name)
	end
	Workspace:GetAttributeChangedSignal("Weather"):Connect(apply)
	apply()

	-- Lightning: a double flash every so often while it rains.
	task.spawn(function()
		local rng = Random.new()
		while true do
			task.wait(rng:NextNumber(8, 20))
			if Weather.current() == "Rain" then
				for _ = 1, 2 do
					flash.Brightness = 0.55
					TweenService:Create(flash, TweenInfo.new(0.25), { Brightness = 0 }):Play()
					task.wait(0.18)
				end
			end
		end
	end)
end

return Weather
