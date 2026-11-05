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
		spacing = 1,
		showPower = true,
		powerHeight = 6,
		showPlayer = true,
		showSolo = false,
		showAuras = true,
		auraPosition = "inside", -- inside | above
		font = 13,
		autoFont = true,         -- shrink text to fit small buttons
		healthFont = 0,          -- 0 = follow the name size
		textLayout = "auto",     -- auto | inline | stacked
		healthColor = "class",   -- class | dark (a custom `color` table overrides both)
		nameClassColor = false,
		healthText = "percent",  -- percent | deficit | none
		hideFullHealthText = true,
		showRole = true,
		showAbsorbs = true,
		gradient = true,
		rangeAlpha = 0.4,
		targetHighlight = true,
		hoverHighlight = true,
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
		auraPosition = "inside",
		font = 13,
		autoFont = true,
		healthFont = 0,
		textLayout = "auto",
		healthColor = "class",
		nameClassColor = false,
		healthText = "deficit",
		hideFullHealthText = true,
		showRole = true,
		showAbsorbs = true,
		gradient = true,
		rangeAlpha = 0.4,
		targetHighlight = true,
		hoverHighlight = true,
		x = 0,
		y = 220,
	},
}
