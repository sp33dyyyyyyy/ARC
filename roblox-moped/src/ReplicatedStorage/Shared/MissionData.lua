--[[
	MissionData  (ModuleScript, ReplicatedStorage/Shared)

	Mission templates. Locations are NAMES of parts inside Workspace/MissionSpots.
	Move those parts around in Studio to match your own town - no code changes.

	Types
	  Delivery    pick up at `pickup`, drop at `dropoff`. Parcel is fragile:
	              damage to the bike while carrying it cuts the payout.
	  Checkpoint  drive through `checkpoints` in order before the clock runs out.
	  Cruise      just ride (fuel + ignition + kick, remember?) to `destination`.
	              Arrive undamaged for a bonus.
]]

return {
	{
		id = "bakery_run",
		type = "Delivery",
		title = "Broetchen fuer den Gasthof",
		description = "Grab the warm rolls from the bakery and get them to the Gasthof before they go cold.",
		pickup = "Spot_Bakery",
		dropoff = "Spot_Gasthof",
		timeLimit = 120,
		basePay = 220,
	},
	{
		id = "farm_milk",
		type = "Delivery",
		title = "Frische Milch",
		description = "Milk churns from the farm to the village shop. Do not spill. Do not hurry. Hurry a little.",
		pickup = "Spot_Farm",
		dropoff = "Spot_Dorfladen",
		timeLimit = 150,
		basePay = 300,
	},
	{
		id = "forest_dash",
		type = "Checkpoint",
		title = "Waldweg-Sprint",
		description = "Five gates, one clock. Beat the par time for a bonus.",
		checkpoints = { "CP_Forest1", "CP_Forest2", "CP_Forest3", "CP_Forest4", "CP_Forest5" },
		timeLimit = 150,
		parTime = 100,
		basePay = 380,
	},
	{
		id = "sunday_cruise",
		type = "Cruise",
		title = "Sonntagsausflug",
		description = "A relaxed ride out to Huegeldorf. Arrive without a scratch for a bonus.",
		destination = "Spot_Huegeldorf",
		basePay = 260,
	},
}
