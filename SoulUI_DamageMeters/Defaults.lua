if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}
SoulUI.Defaults.DamageMeters = {
	enabled = true,
	width = 284,
	rows = 5,
	rowHeight = 22,
	rowGap = 1,
	headerHeight = 22,
	headerFontSize = 0,
	fontSize = 0,
	valueFormat = "pipe",   -- both | total | persec | pipe | percent
	showIcons = true,
	showRank = true,
	classColors = true,
	barAlpha = 1,
	markSelf = true,
	headerAccent = true,
	headerLine = true,
	headerIconsOnHover = false,
	border = false,
	refresh = 0.05,
	showClock = true,
	bgAlpha = 0.55,
	-- 0.6.2 meter polish
	valueColumns = true,    -- "both"/"percent": numbers in two right-aligned columns
	secondaryAlpha = 0.62,  -- brightness of the per-second / share column (0.3-1)
	textStyle = "shadow",   -- shadow | outline | none
	barSheen = true,        -- soft highlight on the top half of each bar
	rowBackground = { 1, 1, 1, 0.04 }, -- empty track behind each bar (r, g, b, a)
	emptyText = true,       -- "Waiting for combat" when a window has no data
	scrollWheel = true,     -- mouse wheel scrolls when there are more entries than rows
	smoothScroll = true,    -- glide instead of jumping a row at a time
	windows = {
		{ enabled = true, type = "healing", segment = "current", x = 810, y = -206.25, pixelWidth = 285, pixelHeight = 108, rows = 6 },
		{ enabled = true, type = "damage", segment = "overall", x = 809.25, y = -327.75 },
		{ enabled = true, type = "damage", segment = "current", x = 817.5, y = -462 },
	},
}
