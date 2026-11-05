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
		nameClassColor = false,  -- name text in the class color (players only)
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
	dispelGlow = true,  -- outline when a friend has a debuff you can cleanse
	purgeGlow = true,   -- outline when an enemy target/focus has a buff you can purge or soothe

	-- Look, shared by all five frames.
	backdropColor = { 0.06, 0.06, 0.07, 1 }, -- empty part of the health and power bars
	borderColor = { 0, 0, 0, 1 },            -- 1px outline and the line above the power bar
	gloss = true,             -- soft vertical shading on the health fill
	textShadow = true,        -- drop shadow under name and health text (on top of the outline)
	absorbs = true,           -- shield overlay past the health fill, and over-shield inside it
	healAbsorbs = true,       -- heal-absorb (necrotic etc.) overlay eating into the fill
	hoverHighlight = true,    -- brighten the frame under the mouse
	targetHighlight = true,   -- white outline on a frame whose unit is your current target
	tooltip = true,           -- unit tooltip on mouseover
	raidIcon = true,          -- raid target marker on the top edge
	leaderIcon = true,        -- group leader crown on the top-left corner
	combatIcon = true,        -- crossed swords on the player frame while in combat

	units = {
		player = Unit(225, 68, -400, -300, { showCast = false }),
		target = Unit(225, 68, 400, -300),
		focus = Unit(140, 34, -400, -200),
		targettarget = Unit(140, 34, 400, -200, { showCast = false }),
		pet = Unit(92, 20, -400, -360, { showCast = false, namePosition = "above", healthFormat = "none" }),
	},
}
