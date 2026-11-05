if SoulUI_Blocked or not SoulUI then return end

-- Starting sizes only. Core/Layout.lua writes the reference layout into the
-- profile on first login, and the editor overwrites anything after that.
SoulUI.Defaults = SoulUI.Defaults or {}

local function Unit(width, height, x, y, extra)
	local cfg = {
		enabled = true,
		width = width,
		height = height,
		showPower = false,
		powerHeight = 6,
		showCast = true,
		castHeight = 18,
		showName = true,
		namePosition = "inside", -- inside | above
		textLayout = "corners",  -- corners (name top-left, health bottom-right) | center
		healthFormat = "both",   -- both | value | percent | none
		nameSize = 0,            -- 0 = sized from the bar height
		healthSize = 0,
		x = x,
		y = y,
	}
	if extra then
		for key, value in pairs(extra) do cfg[key] = value end
	end
	return cfg
end

SoulUI.Defaults.UnitFrames = {
	hideBlizzard = true,
	units = {
		player = Unit(225, 68, -400, -300, { showCast = false }),
		target = Unit(225, 68, 400, -300),
		focus = Unit(140, 34, -400, -200),
		targettarget = Unit(140, 34, 400, -200, { showCast = false }),
		pet = Unit(92, 20, -400, -360, { showCast = false, namePosition = "above", healthFormat = "none" }),
	},
}
