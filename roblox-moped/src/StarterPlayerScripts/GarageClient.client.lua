--[[
	GarageClient  (LocalScript, StarterPlayerScripts)

	Animates the roller doors of the personal garages. The server never moves
	the slats - it only flips the door model's `Open` attribute (and the
	invisible collision). Each client rolls the slats up / down itself, which is
	far smoother than replicating 11 moving parts from the server.

	Each slat carries OpenDY / OpenDZ (how far it travels when open) and an
	Index so the roll can be staggered like a real shutter.
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local closedCF: { [BasePart]: CFrame } = {}
local running: { [BasePart]: Tween } = {}

local function slatsOf(door: Instance): { BasePart }
	local list = {}
	for _, d in ipairs(door:GetChildren()) do
		if d:IsA("BasePart") and d:GetAttribute("OpenDY") ~= nil then
			table.insert(list, d)
		end
	end
	return list
end

local function pose(door: Instance, open: boolean, instant: boolean)
	for _, slat in ipairs(slatsOf(door)) do
		local closed = closedCF[slat]
		if not closed then
			closed = slat.CFrame
			closedCF[slat] = closed
		end
		local target = open and closed * CFrame.new(0, slat:GetAttribute("OpenDY"), slat:GetAttribute("OpenDZ")) or closed
		local previous = running[slat]
		if previous then
			previous:Cancel()
			running[slat] = nil
		end
		if instant then
			slat.CFrame = target
		else
			local index = slat:GetAttribute("Index") or 0
			-- opening: bottom first; closing: top first
			local delay = open and (index + 1) * 0.045 or (10 - index) * 0.04
			local tween = TweenService:Create(slat, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = target })
			running[slat] = tween
			task.delay(delay, function()
				if running[slat] == tween then
					tween:Play()
				end
			end)
		end
	end
end

local function watch(door: Instance)
	if not door:IsA("Model") then
		return
	end
	-- remember the closed pose before anything moves, then match the current state
	for _, slat in ipairs(slatsOf(door)) do
		closedCF[slat] = slat.CFrame
	end
	pose(door, door:GetAttribute("Open") == true, true)
	door:GetAttributeChangedSignal("Open"):Connect(function()
		pose(door, door:GetAttribute("Open") == true, false)
	end)
end

CollectionService:GetInstanceAddedSignal("PlayerGarageDoor"):Connect(function(door)
	-- children arrive with the model, but give replication a beat
	task.defer(watch, door)
end)
for _, door in ipairs(CollectionService:GetTagged("PlayerGarageDoor")) do
	task.defer(watch, door)
end
