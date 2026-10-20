-- Client entry point: builds the UI, wires input and server notifications.
local MarketplaceService = game:GetService("MarketplaceService")
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
local Settings = require(script.Parent.UI.Settings)
local AdminPanel = require(script.Parent.UI.AdminPanel)

local player = Players.LocalPlayer

local function useChalk()
	Remotes.get("UseChalk"):FireServer()
end

local shop, hud, settings, overlay -- forward-declared: the button callbacks below refer to them
hud = Hud.new({
	shop = function()
		shop:toggle()
	end,
	chalk = useChalk,
	ragdoll = ClimbController.toggleRagdoll,
	letGo = ClimbController.letGo,
	clip = ClimbController.clip,
	rappel = ClimbController.rappel,
	emotes = function()
		hud:toggleEmoteBar()
	end,
	settings = function()
		settings:toggle()
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
	buyPass = function(id)
		for _, pass in Config.GamePasses do
			if pass.Id == id then
				if pass.GamePassId and pass.GamePassId > 0 then
					MarketplaceService:PromptGamePassPurchase(player, pass.GamePassId)
				else
					overlay:toast(pass.Name .. " isn't on sale yet.", "bad")
				end
			end
		end
	end,
})
overlay = Overlay.new()

-- Name tags: hiding them is local to you (other players still see theirs).
local showNameTags = true
local function applyNameTag(character: Model?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if showNameTags
			then Enum.HumanoidDisplayDistanceType.Viewer
			else Enum.HumanoidDisplayDistanceType.None
	end
end
local function applyNameTags()
	for _, other in Players:GetPlayers() do
		if other ~= player then
			applyNameTag(other.Character)
		end
	end
end
local function watchPlayer(other: Player)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		applyNameTag(character)
	end)
	applyNameTag(other.Character)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, other in Players:GetPlayers() do
	watchPlayer(other)
end

local adminPanel = AdminPanel.new(function(action, args)
	Remotes.get("AdminAction"):FireServer(action, args)
end)

settings = Settings.new({
	setNameTags = function(on)
		showNameTags = on
		applyNameTags()
		Remotes.get("SaveSetting"):FireServer("NameTags", on)
	end,
	setCameraShake = function(on)
		Effects.setShakeEnabled(on)
		Remotes.get("SaveSetting"):FireServer("CameraShake", on)
	end,
	submitCode = function(code)
		Remotes.get("AdminLogin"):FireServer(code)
	end,
	openAdmin = function()
		adminPanel:open()
	end,
})

-- Saved settings and admin status arrive as attributes from the server.
local function applySavedSettings()
	local tags = player:GetAttribute("Setting_NameTags")
	if typeof(tags) == "boolean" and tags ~= showNameTags then
		showNameTags = tags
		settings.setNameTags(tags)
		applyNameTags()
	end
	local shake = player:GetAttribute("Setting_CameraShake")
	if typeof(shake) == "boolean" then
		settings.setCameraShake(shake)
		Effects.setShakeEnabled(shake)
	end
	settings:setAdmin(player:GetAttribute("IsAdmin") == true)
end
applySavedSettings()

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

local function ownedPasses(): { [string]: boolean }
	local owned = {}
	for _, pass in Config.GamePasses do
		owned[pass.Id] = player:GetAttribute("Pass_" .. pass.Id) == true
	end
	return owned
end

local lastEmotes = nil
local function refresh()
	hud:setCash(cashValue.Value)
	hud:setSubline(player:GetAttribute("BestHeight") or 0, player:GetAttribute("Streak") or 0)
	local owned = Emotes.owned()
	shop:refresh(cashValue.Value, boostLevels(), player:GetAttribute("Chalk") or 0, owned, player:GetAttribute("SummitEmote") or "", ownedPasses())
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
	if string.sub(name, 1, 8) == "Setting_" or name == "IsAdmin" then
		applySavedSettings()
	elseif name ~= "ChalkUntil" then
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
	elseif input.KeyCode == Enum.KeyCode.F then
		ClimbController.clip()
	elseif input.KeyCode == Enum.KeyCode.X then
		ClimbController.unclip()
	elseif input.KeyCode == Enum.KeyCode.V then
		ClimbController.rappel()
	elseif input.KeyCode == Enum.KeyCode.R then
		ClimbController.toggleRagdoll()
	elseif input.KeyCode == Enum.KeyCode.G then
		hud:toggleEmoteBar()
	elseif input.KeyCode == Enum.KeyCode.O then
		settings:toggle()
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
	elseif kind == "AdminResult" then
		local ok, text = payload.ok == true, tostring(payload.text)
		settings:showCodeResult(ok, text)
		adminPanel:showResult(ok, text)
		overlay:toast(text, if ok then "good" else "bad")
	elseif kind == "Announcement" then
		overlay:announcement(tostring(payload.text), tostring(payload.from or "Admin"))
		Effects.sound(Config.Sounds.Summit, 0.7, 0.8)
	elseif kind == "RopeResult" then
		ClimbController.onRopeResult(payload.ok == true, tostring(payload.text), payload.kind)
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
		overlay:toast("Start with the Tutorial Tower: walk into it to grab on, hold W to climb. Press F to clip your rope to a beam, and rest on the yellow bars!", "info")
	end
end)
