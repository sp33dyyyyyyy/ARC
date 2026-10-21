--!strict
-- ChalkService (server): chalk buckets ("ChalkUp" prompts in the gym and at every route).
-- Chalking up fills the character's "Chalk" attribute; StaminaService makes a chalked
-- climber's grip drain slower and wears the chalk off while they climb.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local RopeService = require(script.Parent.RopeService)

local ChalkService = {}

-- A white puff around both hands.
local function puff(character: Model)
	for _, name in { "LeftHand", "RightHand", "Left Arm", "Right Arm" } do
		local hand = character:FindFirstChild(name)
		if hand and hand:IsA("BasePart") then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "ChalkPuff"
			emitter.Color = ColorSequence.new(Color3.fromRGB(248, 248, 244))
			emitter.LightEmission = 0.2
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1.1) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			emitter.Lifetime = NumberRange.new(0.6, 1.1)
			emitter.Speed = NumberRange.new(1, 2.5)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Acceleration = Vector3.new(0, 1.5, 0)
			emitter.Drag = 3
			emitter.Rate = 0
			emitter.Parent = hand
			emitter:Emit(18)
			task.delay(1.5, function()
				emitter:Destroy()
			end)
		end
	end
end

local function chalkUp(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	character:SetAttribute("Chalk", Config.Chalk.Max)
	RopeService.gesture(character, "Chalk")
	task.delay(0.45, puff, character) -- as the hands come out of the bag
end

function ChalkService.Start()
	local function watch(instance: Instance)
		if instance:IsA("ProximityPrompt") and instance.Name == "ChalkUp" then
			instance.Triggered:Connect(chalkUp)
		end
	end
	for _, descendant in Workspace:GetDescendants() do
		watch(descendant)
	end
	Workspace.DescendantAdded:Connect(watch)
end

return ChalkService
