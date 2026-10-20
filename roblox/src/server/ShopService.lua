-- Server-authoritative purchases. Clients only ask; every check happens here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local ShopService = {}

local RATE_LIMIT = 0.2
local lastCall: { [Player]: number } = {}

local function allowed(player: Player): boolean
	local now = os.clock()
	if now - (lastCall[player] or 0) < RATE_LIMIT then
		return false
	end
	lastCall[player] = now
	return DataService.isLoaded(player)
end

local function toast(player: Player, text: string, style: string)
	Remotes.get("Notify"):FireClient(player, "Toast", { text = text, style = style })
end

function ShopService.start()
	Remotes.get("BuyBoost").OnServerEvent:Connect(function(player, boostId)
		if typeof(boostId) ~= "string" or #boostId > 32 or not allowed(player) then
			return
		end
		local data = DataService.get(player)
		local def = Rules.boostDef(Config.Boosts, boostId)
		if not data or not def then
			return
		end
		local result = Rules.canBuyBoost(Config.Boosts, boostId, data.Boosts[boostId] or 0, data.Cash)
		if not result.ok then
			toast(player, result.reason :: string, "bad")
			return
		end
		DataService.update(player, function(d)
			d.Cash -= result.cost :: number
			d.Boosts[boostId] = (d.Boosts[boostId] or 0) + 1
		end)
		toast(player, string.format("%s upgraded to level %d!", def.Name, data.Boosts[boostId]), "good")
	end)

	Remotes.get("BuyChalk").OnServerEvent:Connect(function(player)
		if not allowed(player) then
			return
		end
		local data = DataService.get(player)
		if not data then
			return
		end
		local result = Rules.canBuyChalk(Config.Chalk, data.Chalk, data.Cash)
		if not result.ok then
			toast(player, result.reason :: string, "bad")
			return
		end
		DataService.update(player, function(d)
			d.Cash -= result.cost :: number
			d.Chalk += 1
		end)
		toast(player, "Bought chalk (" .. data.Chalk .. " in bag)", "good")
	end)

	Remotes.get("BuyEmote").OnServerEvent:Connect(function(player, emoteId)
		if typeof(emoteId) ~= "string" or #emoteId > 32 or not allowed(player) then
			return
		end
		local data = DataService.get(player)
		if not data then
			return
		end
		local result = Rules.canBuyEmote(Config.Emotes, data.Emotes, emoteId, data.Cash)
		if not result.ok then
			toast(player, result.reason :: string, "bad")
			return
		end
		local def = Rules.emoteDef(Config.Emotes, emoteId)
		DataService.update(player, function(d)
			d.Cash -= result.cost :: number
			d.Emotes[emoteId] = true
			d.SummitEmote = emoteId -- a fresh purchase becomes your summit emote
		end)
		toast(player, def.Name .. " emote unlocked! Press G to use it.", "good")
	end)

	Remotes.get("EquipEmote").OnServerEvent:Connect(function(player, emoteId)
		if typeof(emoteId) ~= "string" or #emoteId > 32 or not allowed(player) then
			return
		end
		local data = DataService.get(player)
		if not data or not Rules.ownsEmote(Config.Emotes, data.Emotes, emoteId) then
			return
		end
		DataService.update(player, function(d)
			d.SummitEmote = emoteId
		end)
	end)

	Remotes.get("UseChalk").OnServerEvent:Connect(function(player)
		if not allowed(player) then
			return
		end
		local data = DataService.get(player)
		if not data then
			return
		end
		local now = Workspace:GetServerTimeNow()
		if (player:GetAttribute("ChalkUntil") or 0) > now then
			return -- already chalked up; don't waste one
		end
		if data.Chalk <= 0 then
			toast(player, "No chalk left - buy some at the shop", "bad")
			return
		end
		DataService.update(player, function(d)
			d.Chalk -= 1
		end)
		player:SetAttribute("ChalkUntil", now + Config.Chalk.Duration)
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastCall[player] = nil
	end)
end

return ShopService
