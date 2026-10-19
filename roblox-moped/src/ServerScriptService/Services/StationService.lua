--[[
	StationService  (ModuleScript, ServerScriptService/Services)

	Gives ProximityPrompts to anything you tag in Studio (CollectionService):
	  "PetrolStation"  -> Refuel (engine must be OFF)
	  "Workshop"       -> Repair
	  "GarageDoor"     -> opens the garage UI
	  "MissionBoard"   -> opens the mission list (handled by MissionService)

	Tag with the Tag Editor plugin or the Properties window. Any BasePart works.
	Costs always come from Economy - the client sends nothing but the key press.
]]

local CollectionService = game:GetService("CollectionService")

local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)

local REFUEL_RANGE = 28 -- bike must be this close to the pump
local REPAIR_RANGE = 28

local StationService = {}
local Economy, Vehicles, Garage

local function addPrompt(part: BasePart, action: string, object: string, hold: number, handler: (Player) -> ())
	if part:FindFirstChild("Prompt_" .. action) then
		return
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "Prompt_" .. action
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Parent = part
	p.Triggered:Connect(handler)
end

local function bikeNear(player: Player, part: BasePart, range: number)
	local rec = Vehicles.getBike(player)
	if not rec then
		Economy.notify(player, "You need your bike here. Press B to call it.", "hint")
		return nil
	end
	if (rec.chassis.Position - part.Position).Magnitude > range then
		Economy.notify(player, "Bring the bike closer.", "hint")
		return nil
	end
	return rec
end

local function refuel(player: Player, pump: BasePart)
	local rec = bikeNear(player, pump, REFUEL_RANGE)
	if not rec then
		return
	end
	if Vehicles.isEngineRunning(rec) then
		Economy.notify(player, "Switch the engine off first! (Ignition)", "warn")
		return
	end
	local missing = Vehicles.fuelMissing(rec)
	if missing < 0.05 then
		Economy.notify(player, "Tank is already full.", "info")
		return
	end
	local price = GameConfig.Economy.FuelPricePerLitre
	local affordable = math.floor(Economy.balance(player) / price * 10) / 10 -- litres, 0.1 steps
	local litres = math.min(missing, affordable)
	if litres < 0.1 then
		Economy.notify(player, "Not enough money for fuel.", "warn")
		return
	end
	local cost = Economy.fuelCost(litres)
	if Economy.spend(player, cost, "fuel") then
		Vehicles.addFuel(rec, litres)
		Economy.notify(player, ("Refuelled %.1f L for EUR %d"):format(litres, cost), "good")
	end
end

local function repair(player: Player, shop: BasePart)
	local rec = bikeNear(player, shop, REPAIR_RANGE)
	if not rec then
		return
	end
	local missing = Vehicles.healthMissing(rec)
	if missing < 0.5 then
		Economy.notify(player, "Nothing to fix - the bike is in good shape.", "info")
		return
	end
	local cost = Economy.repairCost(rec.vehicle.id, missing)
	if not Economy.spend(player, cost, "repair") then
		Economy.notify(player, ("Repairs cost EUR %d. You can't afford that yet."):format(cost), "warn")
		return
	end
	Vehicles.repairFully(rec)
	Economy.notify(player, ("Repaired for EUR %d. Good as new (nearly)."):format(cost), "good")
end

local function setup(part: Instance, tag: string)
	if not part:IsA("BasePart") then
		return
	end
	if tag == "PetrolStation" then
		addPrompt(part, "Refuel", "Petrol pump", 1.0, function(p) refuel(p, part) end)
	elseif tag == "Workshop" then
		addPrompt(part, "Repair bike", "Werkstatt", 1.0, function(p) repair(p, part) end)
	elseif tag == "GarageDoor" then
		addPrompt(part, "Open garage", "Garage", 0, function(p) Garage.openFor(p) end)
	end
end

function StationService.init(economyService, vehicleService, garageService)
	Economy, Vehicles, Garage = economyService, vehicleService, garageService
	for _, tag in ipairs({ "PetrolStation", "Workshop", "GarageDoor" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			setup(inst, tag)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			setup(inst, tag)
		end)
	end
end

return StationService
