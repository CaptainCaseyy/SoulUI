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
	shieldPlacement = "wash",
	shieldPattern = "striped",
	shieldColor = { 1, 1, 1 },
	shieldAlpha = 1,
	overflowAlpha = 1,
	healAbsorbs = true,       -- heal-absorb (necrotic etc.) overlay eating into the fill
	hoverHighlight = true,    -- brighten the frame under the mouse
	targetHighlight = true,   -- white outline on a frame whose unit is your current target
	tooltip = true,           -- unit tooltip on mouseover
	raidIcon = true,          -- raid target marker on the top edge
	leaderIcon = true,        -- group leader crown on the top-left corner
	combatIcon = true,        -- crossed swords on the player frame while in combat

	units = {
		player = Unit(254, 101, -303, -208.5, { showCast = false, nameSize = 20 }),
		target = Unit(254, 101, 303, -208.5, { castHeight = 80, castWidth = 210, color = { 1, 1, 1 } }),
		focus = Unit(118, 29, -282, -149.25, { castHeight = 18, castWidth = 118 }),
		targettarget = Unit(118, 29, 505.5, -236.25, { showCast = false }),
		pet = Unit(94, 31, 545.25, -516, { showCast = false, namePosition = "above", healthFormat = "none" }),
	},
}
