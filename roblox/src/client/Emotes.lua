-- Plays emotes from the avatar's own Animate script (no uploaded animations),
-- stops them when you move, jump or climb, and plays your summit emote when you
-- reach a peak. Animations played on your own character replicate to everyone.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)

local Emotes = {}

local player = Players.LocalPlayer
local track: AnimationTrack? = nil
local isClimbing: () -> boolean = function()
	return false
end
local toast: (string, string?) -> () = function() end

-- Emote ids the player owns (free ones included), in shop order.
function Emotes.owned(): { string }
	local owned = {}
	for id in string.gmatch(player:GetAttribute("Emotes") or "", "[^,]+") do
		owned[id] = true
	end
	local list = {}
	for _, def in Config.Emotes do
		if Rules.ownsEmote(Config.Emotes, owned, def.Id) then
			table.insert(list, def.Id)
		end
	end
	return list
end

function Emotes.stop()
	if track then
		track:Stop(0.2)
		track = nil
	end
end

function Emotes.play(id: string)
	local def = Rules.emoteDef(Config.Emotes, id)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not def or not character or not humanoid or not animator or humanoid.Health <= 0 then
		return
	end
	if not table.find(Emotes.owned(), id) then
		toast("Buy " .. def.Name .. " at the Power Up Shop first", "bad")
		return
	end
	if isClimbing() then
		toast("You can't emote while climbing!", "bad")
		return
	end
	local animate = character:FindFirstChild("Animate")
	local folder = animate and (animate:FindFirstChild(def.Anim) or animate:FindFirstChild("dance"))
	local anim = folder and folder:FindFirstChildOfClass("Animation")
	if not anim then
		toast("This avatar has no " .. def.Name .. " animation", "bad")
		return
	end
	Emotes.stop()
	local ok, loaded = pcall(animator.LoadAnimation, animator, anim)
	if not ok then
		return
	end
	loaded.Priority = Enum.AnimationPriority.Action
	loaded.Looped = string.find(def.Anim, "dance") ~= nil
	loaded:Play(0.2)
	track = loaded
end

-- After reaching a peak: wait until you're standing, then show off.
function Emotes.playSummit()
	task.spawn(function()
		local deadline = os.clock() + 4
		while os.clock() < deadline do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and not isClimbing() and humanoid.FloorMaterial ~= Enum.Material.Air then
				task.wait(0.3)
				Emotes.play(player:GetAttribute("SummitEmote") or "Wave")
				return
			end
			task.wait(0.1)
		end
	end)
end

function Emotes.start(climbingFn: () -> boolean, toastFn: (string, string?) -> ())
	isClimbing, toast = climbingFn, toastFn
	RunService.Heartbeat:Connect(function()
		local current = track
		if not current then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local state = humanoid and humanoid:GetState()
		if
			not current.IsPlaying
			or not humanoid
			or humanoid.MoveDirection.Magnitude > 0.1
			or isClimbing()
			or state == Enum.HumanoidStateType.Jumping
			or state == Enum.HumanoidStateType.Freefall
			or state == Enum.HumanoidStateType.Physics
		then
			Emotes.stop()
		end
	end)
	player.CharacterAdded:Connect(function()
		track = nil
	end)
end

return Emotes
