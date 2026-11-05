if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}
SoulUI.Defaults.ResourceBars = {
	width = 276,
	showPrimary = false,
	showPips = true,
	showCast = true,
	showGCD = false,
	primary = { height = 10, width = 276, x = 0, y = -280, textSize = 0, showText = true },
	pips = {
		height = 32,
		width = 276,
		gap = 2,
		border = true,
		gloss = false,
		colorMode = "class",
		showCount = true,
		countSize = 0,
		x = 0,
		y = -296,
	},
	cast = { height = 22, width = 276, x = 0, y = -230, textSize = 0, showIcon = true },
	gcd = { height = 3, width = 552, x = 0, y = -402 },
}
