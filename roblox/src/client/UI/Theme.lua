-- One place for the HUD's look: dark glass panels, hazard-yellow accent.
local Theme = {
	Panel = Color3.fromRGB(18, 20, 28),
	PanelLight = Color3.fromRGB(30, 34, 46),
	Card = Color3.fromRGB(38, 42, 56),
	Stroke = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(244, 245, 250),
	Muted = Color3.fromRGB(150, 158, 180),
	Accent = Color3.fromRGB(255, 196, 46),
	AccentDark = Color3.fromRGB(200, 140, 20),
	Good = Color3.fromRGB(88, 224, 132),
	Bad = Color3.fromRGB(255, 86, 86),
	Info = Color3.fromRGB(100, 172, 255),
	Gold = Color3.fromRGB(255, 214, 90),
	StaminaHigh = Color3.fromRGB(88, 224, 132),
	StaminaMid = Color3.fromRGB(255, 200, 60),
	StaminaLow = Color3.fromRGB(255, 80, 80),
	Chalk = Color3.fromRGB(235, 240, 255),

	PanelTransparency = 0.18,
	Radius = 12,

	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
}

function Theme.styleColor(style: string?): Color3
	if style == "good" then
		return Theme.Good
	elseif style == "bad" then
		return Theme.Bad
	elseif style == "gold" then
		return Theme.Gold
	end
	return Theme.Info
end

function Theme.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""):gsub("^%-,", "-"))
end

return Theme
