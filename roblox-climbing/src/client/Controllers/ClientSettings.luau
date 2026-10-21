--!strict
-- ClientSettings (client): this player's options, set on the phone's Settings app and read
-- by the HUD. Kept for the session.

local ClientSettings = {}

local values: { [string]: boolean } = {
	Hints = true, -- the how-to line at the bottom while climbing
	StaminaAlways = false, -- show the stamina bar even when it's full
	RunTimer = true, -- the run card with the timer
}

local changed = Instance.new("BindableEvent")
ClientSettings.Changed = changed.Event

function ClientSettings.get(name: string): boolean
	return values[name] == true
end

function ClientSettings.set(name: string, value: boolean)
	if values[name] ~= value then
		values[name] = value
		changed:Fire(name, value)
	end
end

return ClientSettings
