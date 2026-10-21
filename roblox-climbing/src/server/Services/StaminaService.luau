--!strict
-- StaminaService (server): grip stamina, worked out on the server so it can't be cheated.
--
-- Every tick it looks at what each climber is holding (ClimbService's attributes), drains
-- or recovers stamina with StaminaMath, and publishes it as the character attribute
-- "Stamina" (0..Max) for the HUD. Resting means all four limbs on holds without moving one
-- for Config.Stamina.RestDelay seconds. At zero the climber is too tired and peels off
-- (ClimbService.ForceOff "Exhausted", which RagdollService turns into a limp fall).
-- Chalk (the character's "Chalk" attribute, from ChalkService) slows the drain and wears
-- off while you climb.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Pack = require(Shared.Pack)
local StaminaMath = require(Shared.StaminaMath)

local ClimbService = require(script.Parent.ClimbService)
local HoldService = require(script.Parent.HoldService)

local STAMINA = Config.Stamina
local CHALK = Config.Chalk

local StaminaService = {}

type State = {
	character: Model,
	stamina: number,
	holdsKey: string, -- which holds are held, to notice a limb moving
	restSince: number?, -- when all four limbs last settled
}

local states: { [Player]: State } = {}

local function stateFor(player: Player): State?
	local character = player.Character
	if character == nil then
		return nil
	end
	local state = states[player]
	if state == nil or state.character ~= character then
		state = { character = character, stamina = STAMINA.Max, holdsKey = "", restSince = nil }
		states[player] = state
		character:SetAttribute("Stamina", STAMINA.Max)
	end
	return state
end

-- The grips a character is on right now, plus a key that changes when any limb moves.
local function gripsOf(character: Model): ({ StaminaMath.Grip }, string)
	local grips: { StaminaMath.Grip } = {}
	local ids = {}
	for _, limb in Config.LimbOrder do
		local id = character:GetAttribute("Climb_" .. limb)
		local hold = if type(id) == "string" then HoldService.GetHold(id) else nil
		local info = hold and HoldService.GetHoldInfo(hold)
		if info then
			table.insert(grips, { kind = Config.Limbs[limb].Kind, drain = info.Def.DrainMultiplier, quality = info.Quality })
			table.insert(ids, `{limb}={id}`)
		end
	end
	return grips, table.concat(ids, ",")
end

function StaminaService.Get(player: Player): number
	local state = states[player]
	return if state then state.stamina else STAMINA.Max
end

-- Adds stamina (a drink of water), up to the maximum.
function StaminaService.Give(player: Player, amount: number)
	local state = stateFor(player)
	if state then
		state.stamina = math.min(STAMINA.Max, state.stamina + amount)
		state.character:SetAttribute("Stamina", math.floor(state.stamina * 10 + 0.5) / 10)
	end
end

function StaminaService.Spend(player: Player, amount: number)
	local state = stateFor(player)
	if state then
		state.stamina = math.max(0, state.stamina - amount)
		state.character:SetAttribute("Stamina", math.floor(state.stamina * 10 + 0.5) / 10)
	end
end

local function gearNumber(player: Player, name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function tick(dt: number)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local state = stateFor(player)
		if state == nil then
			continue
		end
		local character = state.character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") == true then
			continue -- no recovering while knocked down
		end

		local grips, key = gripsOf(character)
		if key ~= state.holdsKey then
			state.holdsKey = key
			state.restSince = if #grips >= 4 then now else nil
		end
		local restingFor = if state.restSince then now - state.restSince else 0
		local rate = StaminaMath.rate(grips, restingFor, STAMINA)
		-- Gear (ShopService publishes it on the player): shoes help whenever a foot is on.
		if rate < 0 then
			local hasFoot = false
			for _, grip in grips do
				if grip.kind == "Foot" then
					hasFoot = true
				end
			end
			if hasFoot then
				rate *= gearNumber(player, "GearFootDrain", 1)
			end
			-- A heavy pack (PackService) tires you a little faster.
			rate *= 1 + gearNumber(player, "PackWeight", 0) * Pack.DRAIN_PER_WEIGHT
		end
		local chalk = character:GetAttribute("Chalk")
		if type(chalk) == "number" and chalk > 0 then
			rate = StaminaMath.withChalk(rate, chalk / CHALK.Max, gearNumber(player, "GearChalkReduction", CHALK.DrainReduction))
			if #grips > 0 then
				local left = math.max(0, chalk - gearNumber(player, "GearChalkRate", CHALK.DrainPerSecond) * dt)
				character:SetAttribute("Chalk", if left > 0 then math.floor(left * 10 + 0.5) / 10 else nil)
			end
		end
		state.stamina = StaminaMath.step(state.stamina, rate, dt, STAMINA.Max)

		local rounded = math.floor(state.stamina * 10 + 0.5) / 10
		if character:GetAttribute("Stamina") ~= rounded then
			character:SetAttribute("Stamina", rounded)
		end
		if #grips > 0 and state.stamina <= 0 then
			ClimbService.ForceOff(player, "Exhausted")
		end
	end
end

function StaminaService.Start()
	ClimbService.OnDyno(function(player)
		StaminaService.Spend(player, gearNumber(player, "GearDynoCost", STAMINA.DynoCost))
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= STAMINA.TickSeconds then
			tick(elapsed)
			elapsed = 0
		end
	end)
end

return StaminaService
