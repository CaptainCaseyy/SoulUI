if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}
SoulUI.Defaults.Nameplates = {
	enabled = true,
	width = 140,
	height = 16,
	spacing = 2,          -- gap between health, name, cast bar, debuff row and purge row
	showName = true,
	namePos = "above",    -- above | inside (name on the health bar)
	nameSize = 0,         -- 0 = sized from the bar height
	showPercent = true,   -- health percent on the bar
	percentSize = 0,      -- 0 = sized from the bar height
	showClassification = true, -- gold (elite / boss) or silver (rare) mark before the name
	raidMarker = "left",  -- left | top | off
	raidMarkerSize = 0,   -- 0 = sized from the bar height
	targetStyle = "both", -- border | arrows | both | glow | none
	nonTargetAlpha = 0.85, -- other enemy plates while you target one (1 = no dimming)
	showCast = true,
	castHeight = 12,
	castIcon = true,
	castFont = 0,         -- 0 = sized from the cast height
	manageCVars = true,
	showAll = false,
	stack = true,
	showDebuffs = true,  -- your debuffs on the enemy
	debuffSize = 20,     -- icon sizes apply after /reload
	debuffMax = 5,
	purge = "auto",      -- auto (only if you can purge/soothe) | always | off
	purgeGlow = true,    -- outline the plate while it has something you can remove
	purgeSize = 20,
}
