if SoulUI_Blocked then return end

local Soul = SoulUI
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

if LSM then
	LSM:Register("statusbar", "SoulUI Flat", "Interface\\Buttons\\WHITE8X8")
	if STANDARD_TEXT_FONT then
		LSM:Register("font", "SoulUI Default", STANDARD_TEXT_FONT)
	end
	-- Bundled UI font: Barlow Semi Condensed (SIL Open Font License 1.1,
	-- Media/Fonts/OFL-Barlow.txt). Also usable on frames through the font lists.
	LSM:Register("font", "SoulUI Barlow", "Interface\\AddOns\\SoulUI\\Media\\Fonts\\BarlowSemiCondensed-Medium.ttf")
	LSM:Register("statusbar", "SoulUI Smooth", "Interface\\AddOns\\SoulUI\\Media\\Textures\\Smooth.tga")
	LSM:Register("font", "SoulUI Barlow SemiBold", "Interface\\AddOns\\SoulUI\\Media\\Fonts\\BarlowSemiCondensed-SemiBold.ttf")
end

function Soul:Media(kind, name)
	if LSM and type(name) == "string" then
		local path = LSM:Fetch(kind, name, true)
		if path then return path end
	end
	if kind == "font" then
		return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	end
	return "Interface\\Buttons\\WHITE8X8"
end

function Soul:StatusbarTexture()
	local theme = self:Theme()
	return self:Media("statusbar", theme and theme.statusbar)
end

-- Text style (0.9.0). Modules pass "OUTLINE" to mean "the normal frame text
-- style", so that value follows the theme setting (General > Look > Outline):
--   SHADOW        no outline, soft drop shadow (default: the owner found the
--                 black outline heavy and hard to read)
--   OUTLINE / THICKOUTLINE / NONE   as named
-- Any other explicit flag ("NONE" from a module) is used as given.
function Soul:ApplyFont(fontString, size, flags)
	local theme = self:Theme()
	local path = self:Media("font", theme and theme.font)
	local style = theme and theme.fontOutline or "SHADOW"
	local outline = flags or style
	if flags == "OUTLINE" then outline = style end
	-- "BRIGHT": text on a colored bar (nameplate name, enemy cast). No
	-- outline (the owner finds outlines hard to read), a full-strength
	-- shadow instead so white text holds up on yellow and red fills.
	local bright = flags == "BRIGHT"
	if bright then outline = "SHADOW" end
	local shadow = outline == "SHADOW"
	if outline == "NONE" or shadow then outline = "" end
	local ok = pcall(fontString.SetFont, fontString, path, size, outline)
	if not ok then
		pcall(fontString.SetFont, fontString, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, outline)
	end
	if shadow then
		fontString:SetShadowColor(0, 0, 0, bright and 1 or 0.9)
		fontString:SetShadowOffset(1, -1)
	elseif outline ~= "" then
		fontString:SetShadowOffset(0, 0)
	end
end

function Soul:Accent()
	local theme = self:Theme()
	if theme and theme.accentUseClass then
		local _, class = UnitClass("player")
		local color = class and RAID_CLASS_COLORS[class]
		if color then return color.r, color.g, color.b end
	end
	local accent = theme and theme.accent
	if accent then return accent.r or 0, accent.g or 0.93, accent.b or 1 end
	return 0, 0.93, 1
end

local function PrepareBar(bar)
	local texture = bar:GetStatusBarTexture()
	if texture and texture.SetSnapToPixelGrid then
		texture:SetSnapToPixelGrid(false)
		texture:SetTexelSnappingBias(0)
	end
end

function Soul:StatusBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(self:StatusbarTexture())
	PrepareBar(bar)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
	bar.bg = bg
	self:Round(bar)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	return bar
end
