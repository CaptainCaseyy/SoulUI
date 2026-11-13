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
	showEmpty = false,
	hotkeySize = 0,
	countSize = 0,
	macroSize = 0,
	countAnchor = "BOTTOMRIGHT",
	countColor = { 1, 1, 1 },
	countBright = 1,
	procGlow = true,
	procColor = { 1, 0.82, 0.32 },
	bars = {
		main = Bar(-3.75, -306, { size = 69, showMacro = true }),
		bar2 = Bar(-3.75, -376.5, { size = 69 }),
		bar3 = Bar(-940.5, 50.25, { vertical = true, size = 39 }),
		bar4 = Bar(-902.25, 50.25, { vertical = true, size = 39 }),
		bar5 = Bar(-863.25, 50.25, { vertical = true, size = 39 }),
		bar6 = Bar(-921.75, 588, { size = 12, rows = 2 }),
		bar7 = Bar(0, -92, { enabled = false, fade = true }),
		bar8 = Bar(0, -40, { enabled = false, fade = true }),
	},
}
