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
		{ enabled = true, type = "healing", segment = "current", x = 1040, y = 60 },
		{ enabled = true, type = "damage", segment = "overall", x = 1040, y = -160 },
		{ enabled = true, type = "damage", segment = "current", x = 1040, y = -340 },
	},
}
