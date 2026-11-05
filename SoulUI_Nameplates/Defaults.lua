if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}
SoulUI.Defaults.Nameplates = {
	enabled = true,
	width = 140,
	height = 16,
	showName = true,
	showCast = true,
	castHeight = 12,
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
