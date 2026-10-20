-- Climbing animation: Roblox's standard climb animation, taken from the
-- avatar's own Animate script (every avatar has one, R15 and R6), so it never
-- T-poses and needs no uploads. It's played on your own Animator, so every
-- other player sees it automatically.
--
-- The controller tells us what you're doing each frame:
--   "climb"  moving on the wall   -> plays at a speed matching your climbing
--   "hold"   hanging still        -> frozen mid-reach
--   "leap"   dyno                 -> plays fast
--   "rappel" sliding down a rope  -> plays slowly in reverse
--   ""       not climbing         -> stopped (your normal animations take over)
local Players = game:GetService("Players")

local ClimbAnimator = {}

local player = Players.LocalPlayer
local track: AnimationTrack? = nil
local trackCharacter: Model? = nil

local function loadTrack(): AnimationTrack?
	local character = player.Character
	if not character then
		return nil
	end
	if track and trackCharacter == character then
		return track
	end
	track, trackCharacter = nil, character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = character:FindFirstChild("Animate")
	local folder = animate and animate:FindFirstChild("climb")
	local animation = folder and folder:FindFirstChildOfClass("Animation")
	if not animator or not animation then
		return nil
	end
	local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
	if not ok then
		return nil
	end
	loaded.Priority = Enum.AnimationPriority.Action
	loaded.Looped = true
	track = loaded
	return loaded
end

-- `rate` scales the "climb" speed (1 = normal climbing pace).
function ClimbAnimator.set(mode: string, rate: number?)
	if mode == "" then
		if track and track.IsPlaying then
			track:Stop(0.2)
		end
		return
	end
	local t = loadTrack()
	if not t then
		return
	end
	if not t.IsPlaying then
		t:Play(0.15)
	end
	local speed = if mode == "climb"
		then (rate or 1)
		elseif mode == "leap" then 2.5
		elseif mode == "rappel" then -0.8
		else 0 -- hold: freeze mid-reach
	if math.abs(t.Speed - speed) > 0.01 then
		t:AdjustSpeed(speed)
	end
end

-- One-off arm gesture on top of the climb pose, e.g. reaching up to clip a
-- carabiner. Uses one of the avatar's built-in emote animations ("point" lifts
-- one arm) at a higher priority, so only the gesture's limbs move.
local gestures: { [string]: AnimationTrack } = {}
local gestureCharacter: Model? = nil

function ClimbAnimator.gesture(name: string, duration: number, speed: number?)
	local character = player.Character
	if not character then
		return
	end
	if gestureCharacter ~= character then
		gestures, gestureCharacter = {}, character
	end
	local t = gestures[name]
	if not t then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local animate = character:FindFirstChild("Animate")
		local folder = animate and animate:FindFirstChild(name)
		local animation = folder and folder:FindFirstChildOfClass("Animation")
		if not animator or not animation then
			return
		end
		local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
		if not ok then
			return
		end
		loaded.Priority = Enum.AnimationPriority.Action2
		loaded.Looped = false
		gestures[name] = loaded
		t = loaded
	end
	t:Play(0.1, 1, speed or 1)
	task.delay(duration, function()
		if t.IsPlaying then
			t:Stop(0.25)
		end
	end)
end

return ClimbAnimator
