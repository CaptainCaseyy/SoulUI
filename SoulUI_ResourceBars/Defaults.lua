if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}
SoulUI.Defaults.ResourceBars = {
	width = 276,
	showPrimary = false,
	showPips = true,
	showCast = true,
	showGCD = false,
	primary = { height = 10, width = 244, x = -6, y = -501, textSize = 0, showText = true },
	pips = {
		height = 50,
		width = 322,
		gap = 0,
		border = true,
		gloss = false,
		colorMode = "custom",
		color = { 0.53, 0.53, 0.93 },
		showCount = true,
		countSize = 0,
		x = 0,
		y = -244.5,
	},
	cast = { height = 66, width = 305, x = 1.5, y = -462, textSize = 0, showIcon = true },
	gcd = { height = 3, width = 488, x = 1.5, y = -494.25 },
}
