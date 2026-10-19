--[[
	ClientState  (ModuleScript, ReplicatedStorage/Shared)

	Plain table shared between the LocalScripts on one client (the bike
	controller writes it every frame, HUD / effects read it). It never
	replicates anywhere - purely local presentation data.
]]

return {
	-- written by BikeClient while this player controls a bike
	controlling = nil :: Model?,
	mode = "None", -- None | Ride | Push | Coast
	speedKmh = 0,
	rpm = 0,
	gear = 1,
	gearCount = 1,
	wheelie = 0,
	skidding = false,
	grounded = true,
	pushStrain = 0, -- 0..1 how heavy the bike you are pushing feels
	pushLeash = 0, -- 0..1 how stretched your arms are
	throttle = 0,
	brake = 0,
	steer = 0, -- -1..1, +1 = right (drives the handlebar animation)
	-- written by DataChanged handler (HUD)
	data = nil :: any,
}
