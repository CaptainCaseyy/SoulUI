if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}
SoulUI.Defaults.DamageMeters = {
	enabled = true,
	width = 260,
	rows = 8,
	rowHeight = 18,
	rowGap = 1,
	headerHeight = 22,
	headerFontSize = 0,
	fontSize = 0,
	valueFormat = "both",   -- both | total | persec | pipe | percent
	showIcons = true,
	showRank = false,
	classColors = true,
	barAlpha = 1,
	markSelf = true,
	headerAccent = true,
	headerLine = true,
	headerIconsOnHover = false,
	border = false,
	refresh = 0.25,
	showClock = true,
	bgAlpha = 0.75,
	windows = {
		{ enabled = true, type = "healing", segment = "current", x = 1040, y = 60 },
		{ enabled = true, type = "damage", segment = "overall", x = 1040, y = -160 },
		{ enabled = true, type = "damage", segment = "current", x = 1040, y = -340 },
	},
}
