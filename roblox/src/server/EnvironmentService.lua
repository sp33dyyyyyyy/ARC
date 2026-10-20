-- Day/night cycle, blinking aviation lights, street lights and wind gusts.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EnvironmentService = {}

local function isNight(clock: number): boolean
	return clock < 6.3 or clock > 17.7
end

local function setStreetLights(on: boolean)
	for _, head in CollectionService:GetTagged("StreetLight") do
		local light = head:FindFirstChildOfClass("SpotLight")
		if light then
			light.Enabled = on
		end
		(head :: BasePart).Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

function EnvironmentService.start()
	-- Advance the clock a few times a second rather than every frame: ClockTime
	-- replicates to every client, so per-frame writes are needless traffic.
	local hoursPerSecond = 24 / Config.DayLengthSeconds
	local wasNight: boolean? = nil
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			Lighting.ClockTime = (Lighting.ClockTime + (now - last) * hoursPerSecond) % 24
			last = now
			local night = isNight(Lighting.ClockTime)
			if night ~= wasNight then
				wasNight = night
				setStreetLights(night)
			end
		end
	end)

	-- Aviation lights: slow red blink, like the real thing.
	task.spawn(function()
		local on = true
		while true do
			task.wait(if on then 1.2 else 0.8)
			on = not on
			for _, bulb in CollectionService:GetTagged("AviationLight") do
				local light = bulb:FindFirstChildOfClass("PointLight")
				if light then
					light.Enabled = on
				end
				(bulb :: BasePart).Transparency = if on then 0 else 0.6
			end
		end
	end)

	-- Wind gusts: warn everyone, then blow. Clients apply the effect to themselves.
	local gust = Remotes.get("Gust")
	local rng = Random.new()
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(Config.Wind.MinInterval, Config.Wind.MaxInterval))
			local angle = rng:NextNumber(0, math.pi * 2)
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			gust:FireAllClients("warn", dir, Config.Wind.WarningTime)
			task.wait(Config.Wind.WarningTime)
			gust:FireAllClients("start", dir, Config.Wind.Duration)
		end
	end)
end

return EnvironmentService
