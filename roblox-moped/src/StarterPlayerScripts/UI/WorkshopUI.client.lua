--[[
	WorkshopUI  (LocalScript, StarterPlayerScripts/UI)

	Opens when the server lifts your bike on the stand (OpenWorkshop). Shows
	the bike's stats with the installed parts, what is fitted in each slot, and
	the parts waiting in your inventory with an Install button.

	Everything here is a request; PartsService checks that the bike really is on
	your raised stand and that you own the part.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartsData = require(Shared:WaitForChild("PartsData"))
local VehicleData = require(Shared:WaitForChild("VehicleData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(Shared:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local T = UIKit.theme
local make, label, button = UIKit.make, UIKit.label, UIKit.button

local gui = UIKit.screenGui("Workshop", 7)
gui.Enabled = false

local state = { bike = nil :: string?, data = ClientState.data :: any, busy = false }

local STATS = {
	{ "topSpeedKmh", "Top speed", "%d km/h", false },
	{ "acceleration", "Acceleration", "%d", false },
	{ "braking", "Braking", "%d", false },
	{ "handling", "Handling", "%d", false },
	{ "weightKg", "Weight", "%.1f kg", true }, -- lower is better
	{ "fuelCapacityL", "Fuel tank", "%.1f L", false },
}

local panel = make("Frame", {
	Parent = gui, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0),
	Size = UDim2.new(0, 360, 0.9, 0), BackgroundColor3 = T.bg, BackgroundTransparency = 0.04,
}, { UIKit.corner(16), UIKit.padding(14), make("UISizeConstraint", { MinSize = Vector2.new(300, 380), MaxSize = Vector2.new(380, 760) }) })

local title = label({ Parent = panel, Size = UDim2.new(1, -40, 0, 26), Text = "WORKSHOP", TextSize = 20, Font = Enum.Font.GothamBlack })
local closeBtn = button({ Parent = panel, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(32, 28), Text = "X" })

local scroll = make("ScrollingFrame", {
	Parent = panel, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -90), BackgroundTransparency = 1,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local releaseBtn = button({
	Parent = panel, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 44),
	Text = "Lower the stand & release the bike", TextSize = 15, BackgroundColor3 = Color3.fromRGB(46, 130, 80),
})

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function section(text: string)
	label({ Parent = scroll, LayoutOrder = nextOrder(), Size = UDim2.new(1, -6, 0, 24), Text = text, TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = T.accent })
end

local function request(remote: string, ...: any)
	if state.busy then
		return
	end
	state.busy = true
	local args = { ... }
	task.spawn(function()
		local ok, res = pcall(function()
			return Remotes.func(remote):InvokeServer(table.unpack(args))
		end)
		state.busy = false
		if ok and res and not res.ok then
			ClientState.toast = res.reason or "Not possible"
		end
	end)
end

local function refresh()
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	order = 0
	local base = state.bike and VehicleData.byId[state.bike]
	if not base then
		return
	end
	local profile = state.data or { parts = {} }
	local e = profile.parts and profile.parts[base.id] or { owned = {}, installed = {} }
	local now = PartsData.apply(base, PartsData.installedList(profile, base.id))
	title.Text = "WORKSHOP - " .. string.upper(base.displayName)

	-- stats: stock -> now
	section("Performance")
	for _, s in ipairs(STATS) do
		local key, name, fmt, lowerBetter = s[1], s[2], s[3], s[4]
		local a, b = base.stats[key], now.stats[key]
		local row = make("Frame", { Parent = scroll, LayoutOrder = nextOrder(), Size = UDim2.new(1, -6, 0, 22), BackgroundTransparency = 1 })
		label({ Parent = row, Size = UDim2.new(0.4, 0, 1, 0), Text = name, TextSize = 13, TextColor3 = T.muted })
		local diff = b - a
		local better = (lowerBetter and diff < 0) or (not lowerBetter and diff > 0)
		label({
			Parent = row, Position = UDim2.fromScale(0.4, 0), Size = UDim2.new(0.6, 0, 1, 0), TextSize = 13, Font = Enum.Font.GothamBold,
			TextColor3 = math.abs(diff) < 0.05 and T.text or (better and T.good or T.warn), TextXAlignment = Enum.TextXAlignment.Right,
			Text = fmt:format(b) .. (math.abs(diff) < 0.05 and "" or (" (" .. (diff > 0 and "+" or "") .. ("%.1f"):format(diff) .. ")")),
		})
	end

	-- slots
	section("Fitted parts")
	for _, slot in ipairs(PartsData.slots) do
		local id = e.installed and e.installed[slot.id]
		local part = id and PartsData.byId[id]
		local row = make("Frame", { Parent = scroll, LayoutOrder = nextOrder(), Size = UDim2.new(1, -6, 0, 40), BackgroundColor3 = T.panel }, { UIKit.corner(8) })
		label({ Parent = row, Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -90, 0, 16), Text = slot.name, TextSize = 11, TextColor3 = T.muted })
		label({
			Parent = row, Position = UDim2.fromOffset(10, 19), Size = UDim2.new(1, -90, 0, 18), TextSize = 14, Font = Enum.Font.GothamBold,
			Text = part and part.name or "- stock -", TextColor3 = part and T.text or T.muted,
		})
		if part then
			local b = button({ Parent = row, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(70, 28), Text = "Remove", TextSize = 12, BackgroundColor3 = Color3.fromRGB(110, 60, 56) })
			b.MouseButton1Click:Connect(function()
				request("PartsRemove", base.id, slot.id)
			end)
		end
	end

	-- inventory
	section("In your garage")
	local any = false
	for _, part in ipairs(PartsData.list) do
		if e.owned and e.owned[part.id] then
			any = true
			local fits = PartsData.fits(part, base)
			local row = make("Frame", { Parent = scroll, LayoutOrder = nextOrder(), Size = UDim2.new(1, -6, 0, 60), BackgroundColor3 = T.panel }, { UIKit.corner(8) })
			label({ Parent = row, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -92, 0, 18), Text = part.name, TextSize = 14, Font = Enum.Font.GothamBold })
			label({ Parent = row, Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -92, 0, 34), Text = PartsData.describe(part), TextSize = 11, TextColor3 = T.muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
			local b = button({ Parent = row, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(76, 36), Text = fits and "INSTALL" or "N/A", TextSize = 13, BackgroundColor3 = fits and Color3.fromRGB(190, 120, 30) or T.bg })
			if fits then
				b.MouseButton1Click:Connect(function()
					request("PartsInstall", base.id, part.id)
				end)
			end
		end
	end
	if not any then
		label({ Parent = scroll, LayoutOrder = nextOrder(), Size = UDim2.new(1, -6, 0, 40), Text = "Nothing waiting. Order parts on your phone, then click the crate in the garage to unpack it.", TextSize = 12, TextColor3 = T.muted, TextWrapped = true })
	end
end

local function close()
	gui.Enabled = false
	state.bike = nil
end

Remotes.event("OpenWorkshop").OnClientEvent:Connect(function(info)
	if info and info.bikeId then
		state.bike = info.bikeId
		gui.Enabled = true
		refresh()
	else
		close()
	end
end)
Remotes.event("DataChanged").OnClientEvent:Connect(function(view)
	state.data = view
	if gui.Enabled then
		refresh()
	end
end)
closeBtn.MouseButton1Click:Connect(close)
releaseBtn.MouseButton1Click:Connect(function()
	close()
	Remotes.event("GarageAction"):FireServer("Release")
end)
