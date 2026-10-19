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
		id = "butcher_run",
		type = "Delivery",
		title = "Wurst fuer den Gasthof",
		description = "Fresh sausages from the Eichenbach butcher to the Gasthof in Kleindorf. Take the backroads, the Eichenweg is the quick way.",
		pickup = "Spot_Metzgerei",
		dropoff = "Spot_Gasthof",
		timeLimit = 300,
		basePay = 650,
	},
	{
		id = "eichenbach_post",
		type = "Delivery",
		title = "Post nach Eichenbach",
		description = "A parcel from the Dorfladen to the other end of the Eichenweg. Nobody is in a hurry. Except the customer.",
		pickup = "Spot_Dorfladen",
		dropoff = "Spot_Eichenbach",
		timeLimit = 240,
		basePay = 520,
	},
	{
		id = "backroad_dash",
		type = "Checkpoint",
		title = "Feldweg-Runde",
		description = "Five gates on the gravel backroads around the lake. Loose surface, long straights, no mercy.",
		checkpoints = { "CP_Back1", "CP_Back2", "CP_Back3", "CP_Back4", "CP_Back5" },
		timeLimit = 300,
		parTime = 200,
		basePay = 700,
	},
	{
		id = "mill_cruise",
		type = "Cruise",
		title = "Zur Muehle",
		description = "Ride out to the old mill by the lake. Arrive without a scratch for a bonus.",
		destination = "Spot_Muehle",
		basePay = 420,
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
