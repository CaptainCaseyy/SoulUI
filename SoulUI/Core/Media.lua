if SoulUI_Blocked then return end

local Soul = SoulUI
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

if LSM then
	LSM:Register("statusbar", "SoulUI Flat", "Interface\\Buttons\\WHITE8X8")
	if STANDARD_TEXT_FONT then
		LSM:Register("font", "SoulUI Default", STANDARD_TEXT_FONT)
	end
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

function Soul:ApplyFont(fontString, size, flags)
	local theme = self:Theme()
	local path = self:Media("font", theme and theme.font)
	local outline = flags or (theme and theme.fontOutline) or "OUTLINE"
	if outline == "NONE" then outline = "" end
	local ok = pcall(fontString.SetFont, fontString, path, size, outline)
	if not ok then
		pcall(fontString.SetFont, fontString, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
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
