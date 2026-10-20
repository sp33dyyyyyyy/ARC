-- Day/night cycle, blinking aviation lights, street lights and wind gusts.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EnvironmentService = {}

local function isNight(clock: number): boolean
	return clock < 6.3 or clock > 17.7
end

local function setStreetLights(on: boolean)
	for _, head in CollectionService:GetTagged("StreetLight") do
		local light = head:FindFirstChildWhichIsA("Light")
		if light then
			light.Enabled = on
		end
		(head :: BasePart).Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	-- A scattering of skyscraper windows glow at night.
	for _, window in CollectionService:GetTagged("NightWindow") do
		(window :: BasePart).Transparency = if on then 0 else 1
	end
end

-- Weather: tween the sky to the new state and publish it as a Workspace
-- attribute; clients draw the rain and apply the slippery-wall drain.
local function pickWeather(rng: Random, current: string): string
	local options, total = {}, 0
	-- Every state can come up (including staying as is), so the configured
	-- chances are the real share of time spent in each.
	for name, chance in Config.Weather.Chances do
		table.insert(options, { name, chance })
		total += chance
	end
	table.sort(options, function(a, b)
		return a[1] < b[1]
	end)
	local roll = rng:NextNumber(0, total)
	for _, option in options do
		roll -= option[2]
		if roll <= 0 then
			return option[1]
		end
	end
	return options[#options][1]
end

local function applyWeather(name: string, clouds: Clouds)
	local state = Config.Weather.States[name]
	local info = TweenInfo.new(Config.Weather.TransitionTime, Enum.EasingStyle.Sine)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, { Density = state.Density, Haze = state.Haze }):Play()
	end
	local grade = Lighting:FindFirstChild("ColorGrade")
	if grade and grade:IsA("ColorCorrectionEffect") then
		TweenService:Create(grade, info, { Saturation = state.Saturation }):Play()
	end
	TweenService:Create(Lighting, info, { Brightness = state.Brightness }):Play()
	TweenService:Create(clouds, info, { Cover = state.CloudCover, Density = 0.4 + state.CloudCover * 0.4 }):Play()
	Workspace:SetAttribute("Weather", name)
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

	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = Workspace.Terrain
	end
	local weatherRng = Random.new()
	applyWeather("Clear", clouds :: Clouds)
	task.spawn(function()
		local current = "Clear"
		while true do
			task.wait(weatherRng:NextNumber(Config.Weather.MinDuration, Config.Weather.MaxDuration))
			current = pickWeather(weatherRng, current)
			applyWeather(current, clouds :: Clouds)
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
