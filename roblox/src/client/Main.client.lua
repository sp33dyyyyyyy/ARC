-- Client entry point: builds the UI, wires input and server notifications.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Effects = require(script.Parent.Effects)
local ClimbController = require(script.Parent.ClimbController)
local Emotes = require(script.Parent.Emotes)
local Weather = require(script.Parent.Weather)
local Hud = require(script.Parent.UI.Hud)
local Overlay = require(script.Parent.UI.Overlay)
local Shop = require(script.Parent.UI.Shop)

local player = Players.LocalPlayer

local function useChalk()
	Remotes.get("UseChalk"):FireServer()
end

local shop, hud -- forward-declared: the button callbacks below refer to both
hud = Hud.new({
	shop = function()
		shop:toggle()
	end,
	chalk = useChalk,
	ragdoll = ClimbController.toggleRagdoll,
	letGo = ClimbController.letGo,
	emotes = function()
		hud:toggleEmoteBar()
	end,
	plaza = function()
		Remotes.get("ResetToPlaza"):FireServer()
	end,
})
shop = Shop.new({
	buyBoost = function(id)
		Remotes.get("BuyBoost"):FireServer(id)
	end,
	buyChalk = function()
		Remotes.get("BuyChalk"):FireServer()
	end,
	buyEmote = function(id)
		Remotes.get("BuyEmote"):FireServer(id)
	end,
	equipEmote = function(id)
		Remotes.get("EquipEmote"):FireServer(id)
	end,
})
local overlay = Overlay.new()

Effects.start()
ClimbController.start({ hud = hud, overlay = overlay })
Emotes.start(ClimbController.isClimbing, function(text, style)
	overlay:toast(text, style)
end)

local firstWeather = true
Weather.start(function(name)
	hud:setWeather(name)
	if not firstWeather then
		local messages = {
			Rain = "It's raining! Every wall is slippery (+25% stamina drain).",
			Fog = "Fog is rolling in. Watch your step up there.",
			Clear = "The skies have cleared.",
		}
		overlay:toast(messages[name] or name, if name == "Rain" then "bad" else "info")
	end
	firstWeather = false
end)

-- Profile values ----------------------------------------------------------------

local stats = player:WaitForChild("leaderstats")
local cashValue = stats:WaitForChild("Cash") :: IntValue
local climbsValue = stats:WaitForChild("Climbs") :: IntValue

local function boostLevels(): { [string]: number }
	local levels = {}
	for _, def in Config.Boosts do
		levels[def.Id] = player:GetAttribute("Boost_" .. def.Id) or 0
	end
	return levels
end

local lastEmotes = nil
local function refresh()
	hud:setCash(cashValue.Value)
	hud:setSubline(player:GetAttribute("BestHeight") or 0, player:GetAttribute("Streak") or 0)
	local owned = Emotes.owned()
	shop:refresh(cashValue.Value, boostLevels(), player:GetAttribute("Chalk") or 0, owned, player:GetAttribute("SummitEmote") or "")
	local key = table.concat(owned, ",")
	if key ~= lastEmotes then
		lastEmotes = key
		local list = {}
		for _, id in owned do
			for _, def in Config.Emotes do
				if def.Id == id then
					table.insert(list, { id = id, name = def.Name })
				end
			end
		end
		hud:setEmotes(list, Emotes.play)
	end
end

hud:setClimbs(climbsValue.Value)
climbsValue.Changed:Connect(function(value)
	hud:setClimbs(value, true)
end)
cashValue.Changed:Connect(refresh)
player.AttributeChanged:Connect(function(name)
	if name ~= "ChalkUntil" then
		refresh()
	end
end)
refresh()

-- Input -----------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		shop:toggle()
	elseif input.KeyCode == Enum.KeyCode.C then
		useChalk()
	elseif input.KeyCode == Enum.KeyCode.Q then
		ClimbController.letGo()
	elseif input.KeyCode == Enum.KeyCode.R then
		ClimbController.toggleRagdoll()
	elseif input.KeyCode == Enum.KeyCode.G then
		hud:toggleEmoteBar()
	elseif input.KeyCode == Enum.KeyCode.P then
		Remotes.get("ResetToPlaza"):FireServer()
	elseif input.KeyCode == Enum.KeyCode.Escape and shop:isOpen() then
		shop:close()
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "ShopPrompt" then
		shop:open()
	end
end)

-- Server notifications ----------------------------------------------------------------

Remotes.get("Notify").OnClientEvent:Connect(function(kind, payload)
	if typeof(payload) ~= "table" then
		return
	end
	if kind == "Toast" then
		overlay:toast(tostring(payload.text), payload.style)
	elseif kind == "Summit" then
		overlay:showSummit(tostring(payload.tower), payload.payout or 0, payload.climbs or 0)
		Effects.sound(Config.Sounds.Summit, 0.9)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.confetti((root :: BasePart).Position + Vector3.new(0, 4, 0))
		end
		Emotes.playSummit()
	elseif kind == "Daily" then
		overlay:toast(string.format("Daily reward: +$%d  (streak %d)", payload.reward or 0, payload.streak or 0), "gold")
	elseif kind == "Unlock" then
		overlay:toast(tostring(payload.text), "gold")
	elseif kind == "Regrip" then
		ClimbController.regrip()
	elseif kind == "Hurt" then
		overlay:hurtFlash(payload.damage or 0)
		Effects.shake(0.4, math.clamp((payload.damage or 0) / 60, 0.1, 0.6))
	end
end)

-- First-time hint.
task.delay(2, function()
	if climbsValue.Value == 0 then
		overlay:toast("Start with the Tutorial Tower: walk into it to grab on, hold W to climb, SPACE to leap. Hang on the yellow rest bars to breathe!", "info")
	end
end)
