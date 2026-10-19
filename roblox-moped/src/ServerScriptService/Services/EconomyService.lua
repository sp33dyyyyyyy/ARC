--[[
	EconomyService  (ModuleScript, ServerScriptService/Services)

	The ONLY code allowed to change a player's money. Everything else (garage
	purchases, fuel, repairs, mission payouts) calls into here.
	Clients can ask for things, but they never send an amount.

	Prices scale with engine size:
	  bike price   VehicleData.priceFor(cc)             (~ cc^1.5)
	  repairs      VehicleData.repairCostPerPoint(bike) * missing health
	  fuel         GameConfig.Economy.FuelPricePerLitre * litres
]]

local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)
local VehicleData = require(game.ReplicatedStorage.Shared.VehicleData)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

local Economy = {}
local DataService -- injected in init()

local function updateLeaderstats(player: Player)
	local profile = DataService.get(player)
	local stats = player:FindFirstChild("leaderstats")
	if not (profile and stats) then
		return
	end
	local money = stats:FindFirstChild("Money")
	if money then
		money.Value = profile.money
	end
	local jobs = stats:FindFirstChild("Jobs")
	if jobs then
		jobs.Value = profile.jobs
	end
end

function Economy.setupPlayer(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Parent = stats
	local jobs = Instance.new("IntValue")
	jobs.Name = "Jobs"
	jobs.Parent = stats
	stats.Parent = player
	updateLeaderstats(player)
end

local function changed(player: Player)
	updateLeaderstats(player)
	DataService.push(player)
end

function Economy.balance(player: Player): number
	local profile = DataService.get(player)
	return profile and profile.money or 0
end

function Economy.canAfford(player: Player, amount: number): boolean
	return Economy.balance(player) >= amount
end

-- Returns true if the money was taken.
function Economy.spend(player: Player, amount: number, _reason: string?): boolean
	amount = math.ceil(amount)
	local profile = DataService.get(player)
	if not profile or amount < 0 or profile.money < amount then
		return false
	end
	profile.money -= amount
	changed(player)
	return true
end

function Economy.pay(player: Player, amount: number, _reason: string?)
	amount = math.floor(amount)
	local profile = DataService.get(player)
	if not profile or amount <= 0 then
		return
	end
	profile.money += amount
	profile.earned += amount
	changed(player)
end

function Economy.recordJobDone(player: Player)
	local profile = DataService.get(player)
	if profile then
		profile.jobs += 1
		changed(player)
	end
end

----------------------------------------------------------------------------
-- Quotes (so station prompts / notifications agree on the numbers)
----------------------------------------------------------------------------
function Economy.fuelCost(litres: number): number
	return math.ceil(litres * GameConfig.Economy.FuelPricePerLitre)
end

function Economy.repairCost(vehicleId: string, missingHealth: number): number
	local vehicle = VehicleData.byId[vehicleId]
	if not vehicle then
		return 0
	end
	return math.ceil(missingHealth * VehicleData.repairCostPerPoint(vehicle))
end

function Economy.notify(player: Player, text: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, text, kind or "info")
end

function Economy.init(dataService)
	DataService = dataService -- leaderstats are created by Main after the profile loads
end

return Economy
