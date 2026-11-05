if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}
SoulUI.Defaults.DamageMeters = {
	enabled = true,
	width = 230,
	rows = 8,
	rowHeight = 16,
	refresh = 0.25,
	showClock = true,
	bgAlpha = 0.55,
	windows = {
		{ enabled = true, type = "healing", segment = "current", x = 1040, y = 60 },
		{ enabled = true, type = "damage", segment = "overall", x = 1040, y = -160 },
		{ enabled = true, type = "damage", segment = "current", x = 1040, y = -340 },
	},
}
