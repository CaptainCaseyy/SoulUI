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

-- px is one physical pixel in the same units the frame will snap to.
-- Nil uses the UIParent pixel.
local function Snapped(value, px)
	if type(value) ~= "number" then return 0 end
	if type(px) == "number" and px > 0 then
		if value >= 0 then
			return math.floor(value / px + 0.5) * px
		end
		return math.ceil(value / px - 0.5) * px
	end
	return Pixel:Scale(value)
end

-- Editor sizes are whole numbers. dir is 1, -1, or nil (an absolute edit).
-- A notch keeps going until the snapped size actually changes, so a step
-- that lands on the same physical pixel is not returned as a change.
function Soul:QuantizeSize(old, incoming, dir, minV, maxV, px)
	local base = type(old) == "number" and old or (incoming or minV or 1)
	local n = math.floor((incoming or base) + 0.5)
	if dir ~= 1 and dir ~= -1 then
		if minV and n < minV then n = minV end
		if maxV and n > maxV then n = maxV end
		return n
	end
	if dir == 1 and n <= base then n = base + 1 end
	if dir == -1 and n >= base then n = base - 1 end
	local previous = Snapped(base, px)
	local guard = 0
	while guard < 16 do
		if minV and n < minV then n = minV end
		if maxV and n > maxV then n = maxV end
		local snapped = Snapped(n, px)
		local moved = (dir == 1 and snapped > previous + 0.001) or (dir == -1 and snapped < previous - 0.001)
		if moved then break end
		if dir == 1 and maxV and n >= maxV then break end
		if dir == -1 and minV and n <= minV then break end
		n = n + dir
		guard = guard + 1
	end
	if minV and n < minV then n = minV end
	if maxV and n > maxV then n = maxV end
	return n
end

-- One scroll notch. Grows or shrinks by about 6% (15% with Shift), and never
-- by less than one snapped pixel. Alt is a single pixel. dir is 1 or -1.
function Soul:ScaleStep(old, dir, minV, maxV, px)
	local base = type(old) == "number" and old or (minV or 1)
	local sign = dir < 0 and -1 or 1
	local pct = 0.06
	if IsAltKeyDown() then pct = 0
	elseif IsShiftKeyDown() then pct = 0.15 end
	local delta = math.floor(math.abs(base) * pct + 0.5)
	if delta < 1 then delta = 1 end
	return self:QuantizeSize(base, base + sign * delta, sign, minV, maxV, px)
end

-- Absolute edit (the inspector, a typed size). If the request is only a
-- fraction of a unit past the stored size, still move one step that way.
-- Grid elements need this: one pixel on a 12-wide bar is 1/12 of a button.
function Soul:MatchSize(old, want, minV, maxV, px)
	local n = self:QuantizeSize(old, want, nil, minV, maxV, px)
	local base = type(old) == "number" and old or n
	if type(want) ~= "number" then return n end
	if math.floor(base + 0.5) ~= n then return n end
	if want > base + 0.001 then
		return self:QuantizeSize(base, base + 1, 1, minV, maxV, px)
	end
	if want < base - 0.001 then
		return self:QuantizeSize(base, base - 1, -1, minV, maxV, px)
	end
	return n
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
