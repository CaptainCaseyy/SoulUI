if SoulUI_Blocked then return end

-- Shared look for SoulUI's own chrome: the settings panel (SoulUI_Options) and
-- edit mode (Unlock.lua) are both built from these pieces so they match.
-- Style (0.6.0): cool near-black surfaces, every gray is white-plus-alpha, one
-- accent color (theme accent), 1 physical pixel hairlines, square controls,
-- icons drawn with Line objects (no letters standing in for icons), and one
-- condensed UI font (account.uiFont, default Arial Narrow) separate from the
-- font used on unit frames. Panels run at 1 unit = 1 pixel.

local Soul = SoulUI
local UI = {}
Soul.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"

UI.C = {
	panel = { 0.047, 0.055, 0.063, 0.97 },
	band = { 0.062, 0.071, 0.080, 1 },
	sidebar = { 0.033, 0.039, 0.045, 1 },
	control = { 0.0, 0.0, 0.0, 0.32 },
	controlHover = { 1, 1, 1, 0.06 },
	text = { 0.92, 0.93, 0.94 },
	dim = { 0.62, 0.64, 0.67 },
	faint = { 0.42, 0.44, 0.47 },
	line = { 1, 1, 1, 0.07 },
}

------------------------------------------------------------------------------
-- UI font (settings window and edit mode). Unit frames keep the theme font.
------------------------------------------------------------------------------

UI.DEFAULT_FONT = "Fonts\\ARIALN.TTF"
local fontRegistry = setmetatable({}, { __mode = "k" })

function UI.FontPath()
	local name = Soul.db and Soul.db.account and Soul.db.account.uiFont
	if type(name) == "string" and name ~= "" then
		local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
		local path = LSM and LSM:Fetch("font", name, true)
		if path then return path end
	end
	return UI.DEFAULT_FONT
end

-- Sets the UI font on a FontString or EditBox and remembers it so a font
-- change re-fonts every open SoulUI window.
function UI.SetFont(object, size)
	size = size or 13
	fontRegistry[object] = size
	object:SetFont(UI.FontPath(), size, "")
	-- A missing font file leaves the object without a font: fall back.
	if not object:GetFont() then
		object:SetFont(UI.DEFAULT_FONT, size, "")
	end
end

function UI.RefreshFonts()
	for object, size in pairs(fontRegistry) do
		pcall(UI.SetFont, object, size)
	end
end

------------------------------------------------------------------------------
-- Drawn icons. Each glyph is a few Line objects inside a square frame.
--   close, chevron-down, chevron-right, check, plus
------------------------------------------------------------------------------

local GLYPHS = {
	close = { { -0.32, 0.32, 0.32, -0.32 }, { -0.32, -0.32, 0.32, 0.32 } },
	["chevron-down"] = { { -0.32, 0.14, 0.02, -0.2 }, { -0.02, -0.2, 0.32, 0.14 } },
	["chevron-right"] = { { -0.14, 0.32, 0.2, -0.02 }, { 0.2, 0.02, -0.14, -0.32 } },
	check = { { -0.34, 0.0, -0.08, -0.26 }, { -0.1, -0.26, 0.36, 0.24 } },
	plus = { { -0.34, 0, 0.34, 0 }, { 0, -0.34, 0, 0.34 } },
}

function UI.Glyph(parent, kind, size, color, thickness)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	frame:EnableMouse(false)
	local lines = {}
	local spec = GLYPHS[kind] or GLYPHS.close
	color = color or UI.C.dim
	for i = 1, #spec do
		local seg = spec[i]
		local line = frame:CreateLine(nil, "OVERLAY")
		line:SetThickness(thickness or 1.5)
		line:SetStartPoint("CENTER", frame, seg[1] * size, seg[2] * size)
		line:SetEndPoint("CENTER", frame, seg[3] * size, seg[4] * size)
		line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		lines[i] = line
	end
	function frame:SetColor(r, g, b, a)
		for i = 1, #lines do lines[i]:SetColorTexture(r, g, b, a or 1) end
	end
	return frame
end

local accentRegs = {}

-- Registers a callback that repaints something in the accent color, so a
-- theme change recolors every open SoulUI window at once.
function UI.OnAccent(fn)
	accentRegs[#accentRegs + 1] = fn
	fn(Soul:Accent())
end

function UI.RefreshAccent()
	local r, g, b = Soul:Accent()
	for i = 1, #accentRegs do
		pcall(accentRegs[i], r, g, b)
	end
end

Soul:On("ThemeChanged", function() UI.RefreshAccent() end)
Soul:On("ProfileChanged", function() UI.RefreshAccent() end)

function UI.PanelScale()
	local eff = UIParent:GetEffectiveScale()
	local perfect = Soul.Pixel and Soul.Pixel.perfect or 1
	if type(eff) ~= "number" or eff <= 0 then eff = 1 end
	local user = Soul.db and Soul.db.account and Soul.db.account.panelScale or 1
	if type(user) ~= "number" or user < 0.5 or user > 2 then user = 1 end
	return perfect / eff * user
end

function UI.Fill(frame, color, layer, sub)
	local texture = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
	texture:SetAllPoints()
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return texture
end

-- A 1-unit outline. Inside a pixel-perfect panel one unit is one pixel.
function UI.Edge(frame, r, g, b, a, layer)
	local edges = {}
	local function Line()
		local t = frame:CreateTexture(nil, layer or "BORDER", nil, 7)
		t:SetColorTexture(r, g, b, a)
		if t.SetSnapToPixelGrid then
			t:SetSnapToPixelGrid(false)
			t:SetTexelSnappingBias(0)
		end
		edges[#edges + 1] = t
		return t
	end
	local top, bottom, left, right = Line(), Line(), Line(), Line()
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
	bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
	left:SetPoint("TOPLEFT", 0, -1); left:SetPoint("BOTTOMLEFT", 0, 1); left:SetWidth(1)
	right:SetPoint("TOPRIGHT", 0, -1); right:SetPoint("BOTTOMRIGHT", 0, 1); right:SetWidth(1)
	local outline = { edges = edges }
	function outline:SetColor(nr, ng, nb, na)
		for i = 1, #edges do edges[i]:SetColorTexture(nr, ng, nb, na) end
	end
	function outline:SetShown(on)
		for i = 1, #edges do edges[i]:SetShown(on) end
	end
	return outline
end

function UI.Text(parent, size, color, justify, layer)
	local text = parent:CreateFontString(nil, layer or "OVERLAY")
	UI.SetFont(text, size or 13)
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.75)
	color = color or UI.C.text
	text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	return text
end

-- Tooltip on any frame. text may be a function.
function UI.Tip(frame, title, text)
	frame:HookScript("OnEnter", function(self)
		local body = type(text) == "function" and text() or text
		if not title and not body then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if title then GameTooltip:AddLine(title, 1, 1, 1) end
		if body then GameTooltip:AddLine(body, 0.75, 0.75, 0.8, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Movable window with a title band and a close button. The position is
-- remembered per window in SoulUIDB.account.windows.
function UI.Window(name, title, width, height, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", name, UIParent)
	frame:SetSize(width, height)
	frame:SetFrameStrata(opts.strata or "DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetClampRectInsets(width - 80, -(width - 80), 0, height - 40)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:Hide()
	frame.bg = UI.Fill(frame, UI.C.panel)
	frame.outline = UI.Edge(frame, 1, 1, 1, 0.08)

	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(opts.barHeight or 40)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	UI.Fill(bar, UI.C.band)
	local accentLine = bar:CreateTexture(nil, "ARTWORK")
	accentLine:SetPoint("TOPLEFT")
	accentLine:SetPoint("TOPRIGHT")
	accentLine:SetHeight(2)
	UI.OnAccent(function(r, g, b) accentLine:SetColorTexture(r, g, b, 1) end)
	local divider = bar:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("BOTTOMLEFT")
	divider:SetPoint("BOTTOMRIGHT")
	divider:SetHeight(1)
	divider:SetColorTexture(1, 1, 1, 0.06)
	frame.bar = bar

	local titleText = UI.Text(bar, opts.titleSize or 15, UI.C.text)
	titleText:SetPoint("LEFT", 14, 0)
	titleText:SetText(title or "")
	frame.title = titleText

	bar:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint(1)
		if Soul.db and Soul.db.account then
			Soul.db.account.windows = Soul.db.account.windows or {}
			Soul.db.account.windows[name] = { point = point, relPoint = relPoint, x = x, y = y }
		end
	end)

	if not opts.noClose then
		local close = UI.IconButton(bar, "close", 26)
		close:SetPoint("RIGHT", -8, 0)
		close:SetScript("OnClick", function()
			if opts.onClose then opts.onClose() else frame:Hide() end
		end)
		frame.close = close
	end

	function frame:RestorePosition(defaultPoint, defaultX, defaultY)
		self:SetScale(UI.PanelScale())
		self:ClearAllPoints()
		local saved = Soul.db and Soul.db.account and Soul.db.account.windows and Soul.db.account.windows[name]
		if type(saved) == "table" and saved.point then
			self:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
		else
			self:SetPoint(defaultPoint or "CENTER", UIParent, defaultPoint or "CENTER", defaultX or 0, defaultY or 0)
		end
	end

	return frame
end

-- Square icon button (close and similar): hairline box, drawn glyph.
function UI.IconButton(parent, kind, size, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size or 28, size or 28)
	local face = UI.Fill(button, { 1, 1, 1, 0 })
	local outline = UI.Edge(button, 1, 1, 1, 0.14)
	local glyph = UI.Glyph(button, kind, math.floor((size or 28) * 0.5), UI.C.dim, 1.5)
	glyph:SetPoint("CENTER")
	button:SetScript("OnEnter", function()
		face:SetColorTexture(1, 1, 1, 0.06)
		outline:SetColor(1, 1, 1, 0.3)
		glyph:SetColor(1, 1, 1, 1)
	end)
	button:SetScript("OnLeave", function()
		face:SetColorTexture(1, 1, 1, 0)
		outline:SetColor(1, 1, 1, 0.14)
		glyph:SetColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3], 1)
	end)
	if onClick then button:SetScript("OnClick", onClick) end
	button.glyph = glyph
	return button
end

-- Buttons: style "accent" (filled accent), "plain" (hairline), "ghost" (text
-- only), "outline" (accent hairline), "danger".
function UI.Button(parent, label, width, height, onClick, style)
	style = style or "plain"
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width or 120, height or 28)
	local face = UI.Fill(button, UI.C.control)
	local outline = UI.Edge(button, 1, 1, 1, 0.14)
	local text = UI.Text(button, 14, UI.C.text, "CENTER")
	text:SetPoint("LEFT", 6, 0)
	text:SetPoint("RIGHT", -6, 0)
	text:SetText(label or "")
	button.text = text
	button.face = face
	local hovered = false
	local function Paint()
		local r, g, b = Soul:Accent()
		if button._disabled then
			face:SetColorTexture(1, 1, 1, 0)
			outline:SetColor(1, 1, 1, 0.06)
			text:SetTextColor(UI.C.faint[1], UI.C.faint[2], UI.C.faint[3])
		elseif style == "accent" then
			face:SetColorTexture(r, g, b, hovered and 1 or 0.85)
			outline:SetColor(r, g, b, 1)
			text:SetTextColor(0.02, 0.02, 0.03)
		elseif style == "ghost" then
			face:SetColorTexture(1, 1, 1, hovered and 0.06 or 0)
			outline:SetColor(1, 1, 1, 0)
			text:SetTextColor(hovered and 1 or UI.C.dim[1], hovered and 1 or UI.C.dim[2], hovered and 1 or UI.C.dim[3])
		elseif style == "outline" then
			face:SetColorTexture(r, g, b, hovered and 0.16 or 0.04)
			outline:SetColor(r, g, b, hovered and 1 or 0.7)
			text:SetTextColor(hovered and 1 or r, hovered and 1 or g, hovered and 1 or b)
		elseif style == "danger" then
			face:SetColorTexture(hovered and 0.45 or 0.3, 0.08, 0.08, 1)
			outline:SetColor(1, 0.3, 0.3, 0.35)
			text:SetTextColor(1, 0.85, 0.85)
		else
			face:SetColorTexture(1, 1, 1, hovered and 0.06 or 0.015)
			outline:SetColor(1, 1, 1, hovered and 0.3 or 0.14)
			text:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
		end
	end
	button:SetScript("OnEnter", function() hovered = true Paint() end)
	button:SetScript("OnLeave", function() hovered = false Paint() end)
	button:SetScript("OnClick", function(self, mouse)
		if self._disabled then return end
		if onClick then onClick(self, mouse) end
	end)
	function button:SetLabel(value) text:SetText(value) end
	function button:SetDisabled(off) self._disabled = off and true or false Paint() end
	button.Paint = Paint
	UI.OnAccent(Paint)
	return button
end

-- Switch: square track with a hairline, square knob. get() -> bool, set(bool).
function UI.Switch(parent, get, set)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(38, 20)
	local track = button:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	local edge = UI.Edge(button, 1, 1, 1, 0.16)
	local knob = button:CreateTexture(nil, "ARTWORK")
	knob:SetSize(14, 14)
	local pos = 0
	local function Place(target, animate)
		button:SetScript("OnUpdate", nil)
		if not animate then
			pos = target
			knob:ClearAllPoints()
			knob:SetPoint("LEFT", 3 + pos * 18, 0)
			return
		end
		local from, t = pos, 0
		button:SetScript("OnUpdate", function(self, dt)
			t = t + dt / 0.12
			if t >= 1 then t = 1 self:SetScript("OnUpdate", nil) end
			local eased = 1 - (1 - t) * (1 - t)
			pos = from + (target - from) * eased
			knob:ClearAllPoints()
			knob:SetPoint("LEFT", 3 + pos * 18, 0)
		end)
	end
	local function Paint(animate)
		local on = get() and true or false
		local r, g, b = Soul:Accent()
		if button._disabled then
			track:SetColorTexture(1, 1, 1, 0.03)
			edge:SetColor(1, 1, 1, 0.07)
			knob:SetColorTexture(1, 1, 1, 0.18)
		elseif on then
			track:SetColorTexture(r, g, b, 0.85)
			edge:SetColor(r, g, b, 1)
			knob:SetColorTexture(1, 1, 1, 1)
		else
			track:SetColorTexture(0, 0, 0, 0.35)
			edge:SetColor(1, 1, 1, 0.16)
			knob:SetColorTexture(0.62, 0.64, 0.67, 1)
		end
		Place(on and 1 or 0, animate)
	end
	button:SetScript("OnClick", function(self)
		if self._disabled then return end
		set(not get())
		Paint(true)
	end)
	button.Refresh = function() Paint(false) end
	function button:SetDisabled(off) self._disabled = off and true or false Paint(false) end
	Paint(false)
	UI.OnAccent(function() Paint(false) end)
	return button
end

-- Numeric box: commits on Enter or focus loss, mouse wheel steps it.
function UI.NumberBox(parent, width, get, set, step)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width or 56, 26)
	box:SetAutoFocus(false)
	box:SetJustifyH("CENTER")
	UI.SetFont(box, 14)
	box:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
	UI.Fill(box, { 0, 0, 0, 0.35 })
	local outline = UI.Edge(box, 1, 1, 1, 0.12)
	local function Show()
		local value = get()
		if type(value) ~= "number" then box:SetText("") return end
		if math.abs(value - math.floor(value + 0.5)) < 0.01 then
			box:SetText(string.format("%d", math.floor(value + 0.5)))
		else
			box:SetText(string.format("%.2f", value))
		end
	end
	local function Commit()
		local n = tonumber(box:GetText())
		if n then set(n) end
		Show()
	end
	box:SetScript("OnEnterPressed", function(self) Commit() self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self) Show() self:ClearFocus() end)
	box:SetScript("OnEditFocusLost", function() Commit() end)
	box:SetScript("OnEditFocusGained", function(self)
		local r, g, b = Soul:Accent()
		outline:SetColor(r, g, b, 0.8)
		self:HighlightText()
	end)
	box:HookScript("OnEditFocusLost", function() outline:SetColor(1, 1, 1, 0.12) end)
	box:EnableMouseWheel(true)
	box:SetScript("OnMouseWheel", function(_, delta)
		local value = get()
		if type(value) ~= "number" then return end
		local amount = step or 1
		if IsShiftKeyDown() then amount = amount * 10 end
		set(value + delta * amount)
		Show()
	end)
	box.Refresh = Show
	Show()
	return box
end

-- One dropdown menu shared by every SoulUI dropdown. items are
-- { value =, label =, font = optional LSM font path, texture = optional bar texture }.
local menu, catcher
local MENU_ROW = 24
local MENU_MAX = 14

local function EnsureMenu()
	if menu then return menu end
	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	-- TOOLTIP strata so menus open above the edit mode toolbar and inspector.
	catcher:SetFrameStrata("TOOLTIP")
	catcher:SetFrameLevel(280)
	catcher:Hide()
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", function() menu:Hide() end)

	menu = CreateFrame("Frame", "SoulUI_Menu", UIParent)
	menu:SetFrameStrata("TOOLTIP")
	menu:SetFrameLevel(300)
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:EnableMouseWheel(true)
	menu:Hide()
	UI.Fill(menu, { 0.055, 0.063, 0.071, 0.99 })
	UI.Edge(menu, 1, 1, 1, 0.14)
	menu.rows = {}
	menu.offset = 0
	menu:SetScript("OnHide", function() catcher:Hide() end)
	menu:SetScript("OnMouseWheel", function(self, delta)
		local maxOffset = math.max(0, #self.items - MENU_MAX)
		self.offset = math.min(maxOffset, math.max(0, self.offset - delta * 3))
		self:Paint()
	end)
	local thumb = menu:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(2)
	menu.thumb = thumb

	function menu:Paint()
		local items = self.items
		local shown = math.min(#items, MENU_MAX)
		local r, g, b = Soul:Accent()
		for i = 1, MENU_MAX do
			local row = self.rows[i]
			local item = items[i + self.offset]
			if i <= shown and item then
				row.item = item
				row.text:SetText(item.label or tostring(item.value))
				if item.font then
					pcall(row.text.SetFont, row.text, item.font, 13, "")
				else
					UI.SetFont(row.text, 14)
				end
				if item.texture then
					row.swatch:SetTexture(item.texture)
					row.swatch:SetVertexColor(r, g, b, 0.55)
					row.swatch:Show()
				else
					row.swatch:Hide()
				end
				local on = item.value == self.current
				row.mark:SetShown(on)
				row.mark:SetColorTexture(r, g, b, 1)
				if on then
					row.text:SetTextColor(r, g, b)
				else
					row.text:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
				end
				row:Show()
			else
				row:Hide()
			end
		end
		if #items > MENU_MAX then
			local h = self:GetHeight() - 8
			local th = math.max(16, h * MENU_MAX / #items)
			local travel = h - th
			local frac = self.offset / (#items - MENU_MAX)
			self.thumb:SetHeight(th)
			self.thumb:ClearAllPoints()
			self.thumb:SetPoint("TOPRIGHT", -2, -4 - travel * frac)
			self.thumb:SetColorTexture(r, g, b, 0.7)
			self.thumb:Show()
		else
			self.thumb:Hide()
		end
	end

	for i = 1, MENU_MAX do
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(MENU_ROW)
		row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW)
		row:SetPoint("TOPRIGHT", -6, -4 - (i - 1) * MENU_ROW)
		local hover = row:CreateTexture(nil, "BACKGROUND")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.07)
		hover:Hide()
		local swatch = row:CreateTexture(nil, "BORDER")
		swatch:SetPoint("TOPLEFT", 2, -3)
		swatch:SetPoint("BOTTOMRIGHT", -2, 3)
		swatch:Hide()
		row.swatch = swatch
		local mark = row:CreateTexture(nil, "ARTWORK")
		mark:SetPoint("LEFT", 0, 0)
		mark:SetSize(2, 14)
		row.mark = mark
		local text = UI.Text(row, 13, UI.C.text)
		text:SetPoint("LEFT", 10, 0)
		text:SetPoint("RIGHT", -6, 0)
		row.text = text
		row:SetScript("OnEnter", function() hover:Show() end)
		row:SetScript("OnLeave", function() hover:Hide() end)
		row:SetScript("OnClick", function(self)
			local pick = menu.onPick
			local item = self.item
			menu:Hide()
			if pick and item then pick(item.value) end
		end)
		menu.rows[i] = row
	end
	return menu
end

function UI.CloseMenu()
	if menu then menu:Hide() end
end

function UI.OpenMenu(anchor, items, current, onPick, width)
	local frame = EnsureMenu()
	if frame:IsShown() and frame.anchor == anchor then
		frame:Hide()
		return
	end
	frame.anchor = anchor
	frame.items = items
	frame.current = current
	frame.onPick = onPick
	frame.offset = 0
	for i = 1, #items do
		if items[i].value == current and i > MENU_MAX then
			frame.offset = math.min(#items - MENU_MAX, i - math.floor(MENU_MAX / 2))
		end
	end
	frame:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
	frame:SetWidth(width or math.max(160, anchor:GetWidth()))
	frame:SetHeight(math.min(#items, MENU_MAX) * MENU_ROW + 8)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	frame:Paint()
	catcher:Show()
	frame:Show()
	catcher:Raise()
	frame:Raise()
end

-- Dropdown button. items may be a table or a function returning one.
function UI.Dropdown(parent, width, items, get, set)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width or 200, 28)
	local face = UI.Fill(button, UI.C.control)
	local outline = UI.Edge(button, 1, 1, 1, 0.12)
	local text = UI.Text(button, 14, UI.C.text)
	text:SetPoint("LEFT", 10, 0)
	text:SetPoint("RIGHT", -26, 0)
	local arrow = UI.Glyph(button, "chevron-down", 12, UI.C.dim, 1.5)
	arrow:SetPoint("RIGHT", -9, 0)
	local function List()
		if type(items) == "function" then return items() end
		return items
	end
	local function Refresh()
		local value = get()
		local label = ""
		local list = List()
		for i = 1, #list do
			if list[i].value == value then
				label = list[i].label
				if list[i].font then pcall(text.SetFont, text, list[i].font, 13, "") end
				break
			end
		end
		text:SetText(label)
		if button._disabled then
			text:SetTextColor(UI.C.faint[1], UI.C.faint[2], UI.C.faint[3])
			arrow:SetColor(1, 1, 1, 0.2)
		else
			text:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
			arrow:SetColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3], 1)
		end
	end
	button:SetScript("OnEnter", function()
		if button._disabled then return end
		face:SetColorTexture(1, 1, 1, 0.05)
		outline:SetColor(1, 1, 1, 0.28)
	end)
	button:SetScript("OnLeave", function()
		face:SetColorTexture(UI.C.control[1], UI.C.control[2], UI.C.control[3], UI.C.control[4])
		outline:SetColor(1, 1, 1, 0.12)
	end)
	button:SetScript("OnClick", function(self)
		if self._disabled then return end
		UI.OpenMenu(self, List(), get(), function(value)
			set(value)
			Refresh()
		end)
	end)
	button.Refresh = Refresh
	function button:SetDisabled(off) self._disabled = off and true or false Refresh() end
	Refresh()
	return button
end

-- Horizontal slider with a filled track. Returns the slider; pair it with a
-- NumberBox for typed values.
function UI.Slider(parent, width, minValue, maxValue, step, get, set)
	local slider = CreateFrame("Slider", nil, parent)
	slider:SetSize(width or 200, 16)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step or 1)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
	slider:EnableMouseWheel(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(3)
	track:SetColorTexture(1, 1, 1, 0.1)
	local fill = slider:CreateTexture(nil, "BORDER")
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetHeight(3)
	local thumb = slider:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(10, 14)
	thumb:SetColorTexture(1, 1, 1, 1)
	slider:SetThumbTexture(thumb)
	local silent = false
	local function PaintFill(value)
		local lo, hi = slider:GetMinMaxValues()
		local frac = hi > lo and (value - lo) / (hi - lo) or 0
		if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
		fill:SetWidth(math.max(0.01, frac * slider:GetWidth()))
		local r, g, b = Soul:Accent()
		if slider._disabled then
			fill:SetColorTexture(1, 1, 1, 0.15)
			thumb:SetColorTexture(1, 1, 1, 0.3)
		else
			fill:SetColorTexture(r, g, b, 1)
			thumb:SetColorTexture(r, g, b, 1)
		end
	end
	local function Refresh()
		silent = true
		local value = get()
		if type(value) ~= "number" then value = minValue end
		slider:SetValue(value)
		PaintFill(value)
		silent = false
	end
	slider:SetScript("OnValueChanged", function(_, value)
		if step and step >= 1 then value = math.floor(value + 0.5) end
		PaintFill(value)
		if silent or slider._disabled then return end
		set(value)
	end)
	slider:SetScript("OnMouseWheel", function(self, delta)
		if self._disabled then return end
		local value = self:GetValue() + delta * (step or 1)
		local lo, hi = self:GetMinMaxValues()
		if value < lo then value = lo elseif value > hi then value = hi end
		self:SetValue(value)
	end)
	slider.Refresh = Refresh
	function slider:SetDisabled(off)
		self._disabled = off and true or false
		self:EnableMouse(not self._disabled)
		Refresh()
	end
	Refresh()
	UI.OnAccent(function() Refresh() end)
	return slider
end

-- Color swatch. get() -> r, g, b[, a]; set(r, g, b[, a]).
function UI.Swatch(parent, get, set, hasAlpha)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(30, 22)
	UI.Fill(button, { 0, 0, 0, 1 })
	local chip = button:CreateTexture(nil, "ARTWORK")
	chip:SetPoint("TOPLEFT", 2, -2)
	chip:SetPoint("BOTTOMRIGHT", -2, 2)
	local outline = UI.Edge(button, 1, 1, 1, 0.2)
	local function Refresh()
		local r, g, b, a = get()
		chip:SetColorTexture(r or 1, g or 1, b or 1, button._disabled and 0.25 or (a or 1))
	end
	button:SetScript("OnEnter", function() outline:SetColor(1, 1, 1, 0.6) end)
	button:SetScript("OnLeave", function() outline:SetColor(1, 1, 1, 0.2) end)
	button:SetScript("OnClick", function(self)
		if self._disabled then return end
		local r, g, b, a = get()
		local changed = false
		local function Apply()
			changed = true
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			local na = hasAlpha and ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or a
			set(nr, ng, nb, na)
			Refresh()
		end
		local info = {
			r = r or 1, g = g or 1, b = b or 1,
			opacity = a or 1,
			hasOpacity = hasAlpha and true or false,
			swatchFunc = Apply,
			opacityFunc = Apply,
			cancelFunc = function()
				if changed then
					set(r, g, b, a)
					Refresh()
				end
			end,
		}
		if ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:SetupColorPickerAndShow(info)
		end
		ColorPickerFrame:SetFrameStrata("TOOLTIP")
		ColorPickerFrame:SetFrameLevel(320)
	end)
	button.Refresh = Refresh
	function button:SetDisabled(off) self._disabled = off and true or false Refresh() end
	Refresh()
	return button
end

-- 3x3 point picker. get() -> point name; set(point).
UI.POINTS = {
	{ "TOPLEFT", "TOP", "TOPRIGHT" },
	{ "LEFT", "CENTER", "RIGHT" },
	{ "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
}

function UI.PointPicker(parent, size, get, set)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	UI.Fill(frame, { 0, 0, 0, 0.35 })
	UI.Edge(frame, 1, 1, 1, 0.12)
	local dots = {}
	local cell = size / 3
	for row = 1, 3 do
		for col = 1, 3 do
			local point = UI.POINTS[row][col]
			local dot = CreateFrame("Button", nil, frame)
			dot:SetSize(cell, cell)
			dot:SetPoint("TOPLEFT", (col - 1) * cell, -(row - 1) * cell)
			local face = dot:CreateTexture(nil, "ARTWORK")
			face:SetSize(math.max(4, cell * 0.36), math.max(4, cell * 0.36))
			face:SetPoint("CENTER")
			dot.face = face
			dot.point = point
			dot:SetScript("OnClick", function() set(point) frame.Refresh() end)
			UI.Tip(dot, (point:lower():gsub("^%l", string.upper)))
			dots[#dots + 1] = dot
		end
	end
	function frame.Refresh()
		local current = get()
		local r, g, b = Soul:Accent()
		for i = 1, #dots do
			if dots[i].point == current then
				dots[i].face:SetColorTexture(r, g, b, 1)
			else
				dots[i].face:SetColorTexture(1, 1, 1, 0.25)
			end
		end
	end
	frame.Refresh()
	return frame
end

-- LibSharedMedia lists for font and texture dropdowns.
function UI.MediaItems(kind)
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local items = {}
	if not LSM then return items end
	local list = LSM:List(kind)
	for i = 1, #list do
		local name = list[i]
		local item = { value = name, label = name }
		if kind == "font" then item.font = LSM:Fetch("font", name, true) end
		if kind == "statusbar" then item.texture = LSM:Fetch("statusbar", name, true) end
		items[#items + 1] = item
	end
	return items
end
