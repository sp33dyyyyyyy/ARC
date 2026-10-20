-- Sounds, confetti, camera shake and the "out of breath" screen effect.
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Effects = {}

function Effects.sound(id: string, volume: number?, pitch: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 6)
end

function Effects.confetti(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 130)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 160, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 110, 255)),
	})
	emitter.Size = NumberSequence.new(0.5)
	emitter.Lifetime = NumberRange.new(2, 3)
	emitter.Speed = NumberRange.new(25, 45)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Acceleration = Vector3.new(0, -35, 0)
	emitter.Drag = 1.5
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-300, 300)
	emitter.LightEmission = 0.4
	emitter.Enabled = false
	emitter.Parent = anchor
	anchor.Parent = Workspace
	emitter:Emit(120)
	Debris:AddItem(anchor, 5)
end

-- Shakes the camera through Humanoid.CameraOffset (no camera scripting needed).
local shakeUntil, shakeMagnitude = 0, 0
function Effects.shake(duration: number, magnitude: number)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
	shakeMagnitude = math.max(if os.clock() < shakeUntil then shakeMagnitude else 0, magnitude)
end

-- Low stamina drains the colour from the world and blurs the edges a bit.
local breath = Instance.new("ColorCorrectionEffect")
breath.Name = "OutOfBreath"
local blur = Instance.new("BlurEffect")
blur.Name = "OutOfBreathBlur"
blur.Size = 0

function Effects.setBreathless(amount: number)
	-- amount: 0 = fine, 1 = about to black out
	breath.Saturation = -0.7 * amount
	breath.Contrast = 0.15 * amount
	breath.TintColor = Color3.new(1, 1 - 0.15 * amount, 1 - 0.15 * amount)
	blur.Size = 10 * amount * amount
end

function Effects.start()
	breath.Parent = Lighting
	blur.Parent = Lighting
	local rng = Random.new()
	RunService.RenderStepped:Connect(function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local now = os.clock()
		if now < shakeUntil then
			local m = shakeMagnitude * math.clamp((shakeUntil - now) * 2, 0, 1)
			humanoid.CameraOffset = Vector3.new(rng:NextNumber(-m, m), rng:NextNumber(-m, m), rng:NextNumber(-m, m))
		elseif humanoid.CameraOffset ~= Vector3.zero then
			humanoid.CameraOffset = Vector3.zero
			shakeMagnitude = 0
		end
	end)
end

return Effects
