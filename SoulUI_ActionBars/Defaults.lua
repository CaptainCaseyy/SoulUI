if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}

local function Bar(x, y, extra)
	local bar = {
		enabled = true,
		size = 45,
		spacing = 1,
		buttons = 12,
		rows = 1,
		vertical = false,
		fade = false,
		fadeAlpha = 0,
		visibility = "always",
		showHotkey = true,
		showCount = true,
		showMacro = false,
		x = x,
		y = y,
	}
	if extra then
		for key, value in pairs(extra) do
			bar[key] = value
		end
	end
	return bar
end

-- Positions here are only a first-boot fallback. Layout.lua writes the
-- reference layout (two 12-button rows under the shards, three columns on the
-- left edge, a small 2x6 bar under the pet) into the profile on first login.
SoulUI.Defaults.ActionBars = {
	showBorder = true,
	showEmpty = true,
	hotkeySize = 0,
	countSize = 0,
	macroSize = 0,
	bars = {
		main = Bar(0, -330),
		bar2 = Bar(0, -376),
		bar3 = Bar(-900, 40, { vertical = true, size = 36 }),
		bar4 = Bar(-860, 40, { vertical = true, size = 36 }),
		bar5 = Bar(-820, 40, { vertical = true, size = 36 }),
		bar6 = Bar(-400, -360, { size = 16, rows = 2 }),
		bar7 = Bar(0, -92, { enabled = false, fade = true }),
		bar8 = Bar(0, -40, { enabled = false, fade = true }),
	},
}
