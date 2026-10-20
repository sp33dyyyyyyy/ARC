-- Admins and the admin panel's powers: ban / unban by username, give or take
-- gamepasses, send players to the plaza, and game-wide announcements.
--
-- Security: the admin password only ever lives on the server (AdminConfig),
-- everyone (owner included) must enter it, guesses are rate limited, and every
-- admin action is re-checked here. Clients only get an "IsAdmin" attribute to
-- show the panel.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AdminConfig = require(script.Parent.AdminConfig)
local ClimbService = require(script.Parent.ClimbService)
local DataService = require(script.Parent.DataService)

local AdminService = {}

local admins: { [Player]: boolean } = {}
-- Keyed by UserId and kept after leaving, so rejoining doesn't reset the limit.
local attempts: { [number]: { number } } = {}
local lastAction: { [Player]: number } = {}
local notify: RemoteEvent

local banStore: DataStore? = nil
pcall(function()
	banStore = DataStoreService:GetDataStore(Config.Admin.BanStoreName)
end)

-- The game's owner can't be banned from the panel.
local function isProtected(userId: number): boolean
	return game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId
end

function AdminService.isAdmin(player: Player): boolean
	return admins[player] == true
end

local function grant(player: Player)
	admins[player] = true
	player:SetAttribute("IsAdmin", true)
end

local function reply(player: Player, ok: boolean, text: string, action: string?)
	notify:FireClient(player, "AdminResult", { ok = ok, text = text, action = action })
end

local function passDef(id: any): any?
	for _, pass in Config.GamePasses do
		if pass.Id == id then
			return pass
		end
	end
	return nil
end

-- Filter admin-typed text the way Roblox requires before others see it.
local function filterForEveryone(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, fromUserId):GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

local function findOnline(name: string): Player?
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == string.lower(name) then
			return p
		end
	end
	return nil
end

local function userIdFor(name: string): number?
	local online = findOnline(name)
	if online then
		return online.UserId
	end
	local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
	return if ok then id else nil
end

-- Actions -------------------------------------------------------------------------

local actions: { [string]: (Player, any) -> () } = {}

function actions.ban(admin: Player, args: any)
	local name = args.username
	if not Rules.isValidUsername(name) then
		reply(admin, false, "That's not a valid username.")
		return
	end
	local userId = userIdFor(name)
	if not userId then
		reply(admin, false, "No Roblox user called " .. name .. ".")
		return
	end
	local online = Players:GetPlayerByUserId(userId)
	if userId == admin.UserId or isProtected(userId) or (online and admins[online]) then
		reply(admin, false, "You can't ban yourself, another admin or the game's owner.")
		return
	end
	local reason = "Banned by an admin."
	if type(args.reason) == "string" and #args.reason > 0 and #args.reason <= 100 then
		reason = filterForEveryone(args.reason, admin.UserId) or reason
	end
	-- Our own ban list (always works) plus Roblox's ban API (published games only).
	local listed = banStore ~= nil
		and pcall(function()
			(banStore :: DataStore):SetAsync(tostring(userId), { by = admin.UserId, reason = reason, time = os.time() })
		end)
	local robloxBan = pcall(function()
		Players:BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = -1,
			DisplayReason = reason,
			PrivateReason = "Banned by " .. admin.Name .. " from the admin panel",
			ExcludeAltAccounts = false,
		})
	end)
	local target = Players:GetPlayerByUserId(userId)
	if target then
		target:Kick("You have been banned. " .. reason)
	end
	print(string.format("[Admin] %s banned %s (%d) list=%s roblox=%s", admin.Name, name, userId, tostring(listed), tostring(robloxBan)))
	if not listed and not robloxBan then
		reply(admin, false, name .. " was kicked, but the ban couldn't be saved (publish the game and enable API services).")
	elseif not robloxBan then
		reply(admin, true, name .. " is banned (game ban list only; Roblox's ban API failed).")
	else
		reply(admin, true, name .. " has been banned.")
	end
end

function actions.unban(admin: Player, args: any)
	local name = args.username
	if not Rules.isValidUsername(name) then
		reply(admin, false, "That's not a valid username.")
		return
	end
	local userId = userIdFor(name)
	if not userId then
		reply(admin, false, "No Roblox user called " .. name .. ".")
		return
	end
	local listed = banStore ~= nil
		and pcall(function()
			(banStore :: DataStore):RemoveAsync(tostring(userId))
		end)
	local robloxBan = pcall(function()
		Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
	end)
	print(string.format("[Admin] %s unbanned %s (%d)", admin.Name, name, userId))
	if listed or robloxBan then
		reply(admin, true, name .. " has been unbanned.")
	else
		reply(admin, false, "Couldn't unban " .. name .. " (publish the game and enable API services).")
	end
end

function actions.plaza(admin: Player, args: any)
	if args.all == true then
		for _, p in Players:GetPlayers() do
			ClimbService.sendToPlaza(p)
		end
		print(string.format("[Admin] %s sent everyone to the plaza", admin.Name))
		reply(admin, true, "Sent everyone to the plaza.")
		return
	end
	local target = if Rules.isValidUsername(args.username) then findOnline(args.username) else nil
	if not target then
		reply(admin, false, "That player isn't in this server.")
		return
	end
	ClimbService.sendToPlaza(target)
	ClimbService.toast(target, "An admin sent you to the plaza.", "info")
	reply(admin, true, "Sent " .. target.Name .. " to the plaza.")
end

local function setPass(admin: Player, args: any, give: boolean)
	local pass = passDef(args.passId)
	if not pass then
		reply(admin, false, "Pick a gamepass first.")
		return
	end
	local target = if Rules.isValidUsername(args.username) then findOnline(args.username) else nil
	if not target then
		reply(admin, false, "That player needs to be in this server.")
		return
	end
	local ok = DataService.update(target, function(d)
		d.GrantedPasses[pass.Id] = if give then true else nil
	end)
	if not ok then
		reply(admin, false, target.Name .. "'s data hasn't loaded yet.")
		return
	end
	if give then
		notify:FireClient(target, "Unlock", { text = "An admin gave you the " .. pass.Name .. " gamepass!" })
	end
	print(string.format("[Admin] %s %s %s %s", admin.Name, if give then "gave" else "took", pass.Id, target.Name))
	reply(admin, true, string.format("%s %s %s.", if give then "Gave" else "Took", pass.Name, if give then "to " .. target.Name else "from " .. target.Name))
end

function actions.givePass(admin: Player, args: any)
	setPass(admin, args, true)
end

function actions.takePass(admin: Player, args: any)
	setPass(admin, args, false)
end

function actions.announce(admin: Player, args: any)
	local text = args.text
	if type(text) ~= "string" or #text == 0 or #text > Config.Admin.MaxAnnouncementLength then
		reply(admin, false, "Announcements need 1-" .. Config.Admin.MaxAnnouncementLength .. " characters.")
		return
	end
	local filtered = filterForEveryone(text, admin.UserId)
	if not filtered then
		reply(admin, false, "Roblox's text filter is unavailable right now; try again.")
		return
	end
	local message = { text = filtered, from = admin.DisplayName }
	local published = pcall(function()
		MessagingService:PublishAsync(Config.Admin.AnnounceTopic, message)
	end)
	if not published then
		-- Studio / messaging down: at least tell this server.
		notify:FireAllClients("Announcement", message)
	end
	print(string.format("[Admin] %s announced: %s", admin.Name, filtered))
	reply(admin, true, if published then "Announcement sent to every server." else "Announcement sent to this server.", "announce")
end

-- Gamepasses bought with Robux ---------------------------------------------------------

local function checkMarketPasses(player: Player)
	for _, pass in Config.GamePasses do
		if pass.GamePassId and pass.GamePassId > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.GamePassId)
			if ok and owns then
				DataService.setMarketPass(player, pass.Id, true)
			end
		end
	end
end

-- Start ---------------------------------------------------------------------------------

function AdminService.start()
	notify = Remotes.get("Notify")

	local function onPlayer(player: Player)
		-- Our own ban list (backs up Roblox bans, and works in unpublished places too).
		if banStore then
			local ok, ban = pcall(function()
				return (banStore :: DataStore):GetAsync(tostring(player.UserId))
			end)
			if ok and type(ban) == "table" and not isProtected(player.UserId) then
				player:Kick("You are banned. " .. tostring(ban.reason or ""))
				return
			end
		end
		task.spawn(checkMarketPasses, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
		lastAction[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased then
			return
		end
		for _, pass in Config.GamePasses do
			if pass.GamePassId == gamePassId then
				DataService.setMarketPass(player, pass.Id, true)
				notify:FireClient(player, "Unlock", { text = pass.Name .. " unlocked. Thanks for the support!" })
			end
		end
	end)

	Remotes.get("AdminLogin").OnServerEvent:Connect(function(player, code)
		if admins[player] then
			reply(player, true, "You're already an admin.", "login")
			return
		end
		local allowed
		allowed, attempts[player.UserId] = Rules.allowAttempt(Config.Admin, attempts[player.UserId] or {}, os.clock())
		if not allowed then
			reply(player, false, "Too many tries. Wait a few minutes.", "login")
			return
		end
		if Rules.adminCodeMatches(AdminConfig.Password, code) then
			grant(player)
			print("[Admin] " .. player.Name .. " unlocked the admin panel")
			reply(player, true, "Password accepted. Admin panel unlocked.", "login")
		else
			reply(player, false, "Wrong password.", "login")
		end
	end)

	Remotes.get("AdminAction").OnServerEvent:Connect(function(player, action, args)
		if not admins[player] then
			return -- not an admin: ignore silently
		end
		if typeof(action) ~= "string" or not actions[action] or typeof(args) ~= "table" then
			return
		end
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.5 then
			reply(player, false, "Slow down a little.")
			return
		end
		lastAction[player] = now
		actions[action](player, args)
	end)

	pcall(function()
		MessagingService:SubscribeAsync(Config.Admin.AnnounceTopic, function(message)
			local data = message.Data
			if type(data) == "table" and type(data.text) == "string" then
				notify:FireAllClients("Announcement", { text = data.text, from = tostring(data.from or "Admin") })
			end
		end)
	end)
end

return AdminService
