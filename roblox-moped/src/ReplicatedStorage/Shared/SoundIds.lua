--[[
	SoundIds  (ModuleScript, ReplicatedStorage/Shared)

	All audio is optional and OFF until you paste asset ids here
	("rbxassetid://123456"). Leave a field empty and that sound is simply skipped.

	Upload your OWN recordings (or use audio you have the rights to) in
	Creator Hub > Assets > Audio. Do not reuse audio ripped from other games.

	engine*  must be LOOPING clips. Playback speed is driven by rpm, so a single
	         steady idle/rev recording works for every bike. A separate id per
	         bike id is checked first (see `perBike`).
]]

return {
	engineLoop = "", -- looping engine tone, pitch follows rpm
	engineIdle = "", -- optional separate idle loop
	kick = "", -- kickstart lever stomp
	click = "", -- ignition / tap / choke switch
	crank = "", -- electric starter whirr
	startUp = "", -- engine catching (one-shot)
	sputter = "", -- running out of fuel
	stall = "", -- engine dies
	crash = "", -- impact
	coin = "", -- mission paid
	missionStart = "",
	refuel = "",
	repair = "",

	-- Optional overrides per vehicle id, e.g. perBike = { aerox50 = { engineLoop = "rbxassetid://..." } }
	perBike = {},
}
