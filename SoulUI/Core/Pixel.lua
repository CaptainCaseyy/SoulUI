if SoulUI_Blocked then return end

local Soul = SoulUI
local Pixel = { perfect = 1, mult = 1 }
Soul.Pixel = Pixel

function Pixel:Refresh()
	local _, height = GetPhysicalScreenSize()
	if type(height) ~= "number" or height < 1 then
		height = self._height or 1080
	end
	self._height = height
	local scale = UIParent:GetEffectiveScale()
	if type(scale) ~= "number" or scale <= 0 then
		scale = 1
	end
	self.perfect = 768 / height
	self.mult = self.perfect / scale
end

function Pixel:Scale(value)
	local mult = self.mult
	if type(value) ~= "number" or not mult or mult <= 0 then
		return value or 0
	end
	if value >= 0 then
		return math.floor(value / mult + 0.5) * mult
	end
	return math.ceil(value / mult - 0.5) * mult
end

function Soul:Round(frame)
	if frame.SetRoundLayoutToNearestPixel then
		frame:SetRoundLayoutToNearestPixel(true)
	end
end

local function Edge(parent)
	local texture = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	texture:SetColorTexture(0, 0, 0, 1)
	return texture
end

function Soul:Border(frame)
	if frame._soulBorder then return frame._soulBorder end
	local border = {
		top = Edge(frame),
		bottom = Edge(frame),
		left = Edge(frame),
		right = Edge(frame),
	}
	frame._soulBorder = border
	self:SizeBorder(frame, 1)
	return border
end

function Soul:ShowBorder(frame, shown, thickness)
	if shown then
		self:Border(frame)
		self:SizeBorder(frame, thickness or 1)
		local border = frame._soulBorder
		border.top:Show()
		border.bottom:Show()
		border.left:Show()
		border.right:Show()
		return
	end
	local border = frame._soulBorder
	if not border then return end
	border.top:Hide()
	border.bottom:Hide()
	border.left:Hide()
	border.right:Hide()
end

function Soul:SizeBorder(frame, thickness)
	local border = frame._soulBorder
	if not border then return end
	local px = self.Pixel:Scale(thickness or 1)
	if type(px) ~= "number" or px < 0.4 then px = 1 end
	border.top:ClearAllPoints()
	border.top:SetPoint("TOPLEFT")
	border.top:SetPoint("TOPRIGHT")
	border.top:SetHeight(px)
	border.bottom:ClearAllPoints()
	border.bottom:SetPoint("BOTTOMLEFT")
	border.bottom:SetPoint("BOTTOMRIGHT")
	border.bottom:SetHeight(px)
	border.left:ClearAllPoints()
	border.left:SetPoint("TOPLEFT", border.top, "BOTTOMLEFT")
	border.left:SetPoint("BOTTOMLEFT", border.bottom, "TOPLEFT")
	border.left:SetWidth(px)
	border.right:ClearAllPoints()
	border.right:SetPoint("TOPRIGHT", border.top, "BOTTOMRIGHT")
	border.right:SetPoint("BOTTOMRIGHT", border.bottom, "TOPRIGHT")
	border.right:SetWidth(px)
end
