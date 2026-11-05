if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}
SoulUI.Defaults.GroupFrames = {
	hideBlizzard = true,
	party = {
		enabled = true,
		orientation = "vertical", -- vertical | horizontal
		dispelGlow = true,
		width = 220,
		height = 48,
		spacing = 2,
		showPower = true,
		powerHeight = 6,
		showPlayer = true,
		showSolo = false,
		showAuras = true,
		font = 13,
		x = -460,
		y = 40,
	},
	raid = {
		enabled = true,
		dispelGlow = true,
		width = 120,
		height = 64,
		spacing = 1,
		showPower = false,
		powerHeight = 4,
		showPlayer = true,
		showAuras = true,
		font = 13,
		x = 0,
		y = 220,
	},
}
