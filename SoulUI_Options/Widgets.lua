if SoulUI_Blocked or not SoulUI then return end

-- Page widgets for the settings panel. A page builder gets a "column" (W.Begin)
-- and stacks rows top-down. Every control is declarative:
--
--   { type = "toggle",   label, get, set }
--   { type = "slider",   label, min, max, step, get, set }
--   { type = "dropdown", label, items | fn, get, set, width }
--   { type = "font" | "statusbar", label, get, set }       LibSharedMedia pickers
--   { type = "color",    label, get -> r,g,b[,a], set(r,g,b[,a]), alpha }
--   { type = "button",   label, text, click, style }
--   { type = "number",   label, get, set, step }
--   common: tooltip, disabled = fn -> bool
--
-- W.Row(col, spec) is a full-width row, W.Row2(col, left, right) two halves.
-- After any set, the whole page refreshes, so dependent rows grey out at once.
--
-- Look (0.6.0): a section is a small uppercase heading over one flat panel
-- (white at 2%, no border). Rows inside have no separators; a two-column row
-- splits on one continuous hairline. Label left in the UI font, control right.

local Soul = SoulUI
local UI = Soul.UI
local W = {}
Soul.Widgets = W
-- Pages.lua publishes helpers on Soul.Options before Panel.lua (loaded last) runs.
Soul.Options = Soul.Options or {}

local ROW_H = 46
local PAD = 36   -- page inset, matches Panel.lua GUTTER
local INSET = 20 -- label / control inset inside a panel

W.searchIndex = {}

function W.Begin(parent, width, pageKey, tabKey)
	return {
		parent = parent,
		width = width,
		y = -26,
		stripe = 0,
		refreshers = {},
		pageKey = pageKey,
		tabKey = tabKey,
		section = nil,
	}
end

-- Sections are cards: a slightly lighter panel behind the rows, opened by
-- W.Section and closed by the next section or W.Finish.
local function CloseCard(col)
	local card = col.card
	if not card then return end
	col.y = col.y - 6
	card:SetHeight(math.max(8, card._top - col.y))
	col.card = nil
	col.y = col.y - 30
end

local function OpenCard(col)
	local card = CreateFrame("Frame", nil, col.parent)
	card:SetFrameLevel(math.max(0, col.parent:GetFrameLevel()))
	card:SetPoint("TOPLEFT", col.parent, "TOPLEFT", PAD, col.y)
	card:SetPoint("TOPRIGHT", col.parent, "TOPRIGHT", -PAD, col.y)
	card._top = col.y
	local bg = card:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.022)
	col.card = card
	col.firstRow = true
	col.y = col.y - 6
end

function W.Finish(col)
	CloseCard(col)
	col.parent:SetHeight(math.max(40, math.abs(col.y) + 24))
end

function W.Refresh(col)
	for i = 1, #col.refreshers do
		local ok, err = pcall(col.refreshers[i])
		if not ok then Soul:Debug("refresh", err) end
	end
	if col.onRefresh then pcall(col.onRefresh) end
end

local function AddRefresher(col, fn)
	col.refreshers[#col.refreshers + 1] = fn
end

-- Every setter refreshes the page it lives on.
local function Wrap(col, fn)
	return function(...)
		fn(...)
		W.Refresh(col)
	end
end

local function Index(col, label, row)
	if not label or label == "" then return end
	W.searchIndex[#W.searchIndex + 1] = {
		label = label,
		lower = label:lower(),
		page = col.pageKey,
		tab = col.tabKey,
		section = col.section,
		row = row,
	}
end

function W.Section(col, text, hint)
	CloseCard(col)
	local font = UI.Text(col.parent, 12, UI.C.faint)
	font:SetText(string.upper(text))
	font:SetPoint("TOPLEFT", col.parent, "TOPLEFT", PAD + 2, col.y)
	if hint then
		local small = UI.Text(col.parent, 12, UI.C.faint)
		small:SetText(hint)
		small:SetPoint("LEFT", font, "RIGHT", 10, 0)
	end
	col.y = col.y - 22
	col.stripe = 0
	col.section = text
	OpenCard(col)
end

function W.Note(col, text)
	local font = col.parent:CreateFontString(nil, "OVERLAY")
	UI.SetFont(font, 14)
	font:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
	font:SetJustifyH("LEFT")
	font:SetJustifyV("TOP")
	font:SetWordWrap(true)
	font:SetSpacing(2)
	local inCard = col.card ~= nil
	local inset = inCard and INSET or 2
	font:SetWidth(math.min(760, col.width - PAD * 2 - inset * 2))
	font:SetText(text)
	font:SetPoint("TOPLEFT", col.parent, "TOPLEFT", PAD + inset, col.y - (inCard and 10 or 0))
	local height = font:GetStringHeight()
	if type(height) ~= "number" or height < 14 then height = 18 end
	col.y = col.y - height - (inCard and 20 or 22)
	return font
end

function W.Space(col, h)
	col.y = col.y - (h or 12)
end

local function RowFrame(col, height)
	col.stripe = col.stripe + 1
	local row = CreateFrame("Frame", nil, col.parent)
	row:SetFrameLevel(col.parent:GetFrameLevel() + 3)
	row:SetPoint("TOPLEFT", col.parent, "TOPLEFT", PAD, col.y)
	row:SetPoint("TOPRIGHT", col.parent, "TOPRIGHT", -PAD, col.y)
	row:SetHeight(height or ROW_H)
	col.firstRow = false
	local hover = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.022)
	hover:Hide()
	if row.SetMouseMotionEnabled then row:SetMouseMotionEnabled(true) end
	row:SetScript("OnEnter", function() hover:Show() end)
	row:SetScript("OnLeave", function(self)
		if not self:IsMouseOver() then hover:Hide() end
	end)
	col.refreshers[#col.refreshers + 1] = function()
		if not row:IsMouseOver() then hover:Hide() end
	end
	local flash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	flash:SetAllPoints()
	flash:SetAlpha(0)
	row.flash = flash
	col.y = col.y - (height or ROW_H)
	return row
end

-- Pulses a row (used when search jumps to it).
function W.Flash(row)
	if not row or not row.flash then return end
	local r, g, b = Soul:Accent()
	row.flash:SetColorTexture(r, g, b, 1)
	local t = 0
	row:SetScript("OnUpdate", function(self, dt)
		t = t + dt
		local a = 0.22 * math.max(0, 1 - t / 1.6) * (0.6 + 0.4 * math.sin(t * 9))
		self.flash:SetAlpha(a)
		if t > 1.6 then
			self.flash:SetAlpha(0)
			self:SetScript("OnUpdate", nil)
		end
	end)
end

-- Builds one control into a host frame (a full row or one half of a row).
local function Control(col, host, spec)
	local label = UI.Text(host, 15, UI.C.text)
	label:SetPoint("LEFT", INSET, 0)
	label:SetText(spec.label or "")
	local control
	local refresh
	local set = spec.set and Wrap(col, spec.set)
	local kind = spec.type

	if kind == "toggle" then
		control = UI.Switch(host, spec.get, set)
		control:SetPoint("RIGHT", -INSET, 0)
		refresh = control.Refresh
	elseif kind == "slider" then
		local box = UI.NumberBox(host, 54, spec.get, function(v)
			if v < spec.min then v = spec.min elseif v > spec.max then v = spec.max end
			set(v)
		end, spec.step)
		box:SetPoint("RIGHT", -INSET, 0)
		local slider = UI.Slider(host, spec.width or 140, spec.min, spec.max, spec.step or 1, spec.get, function(v)
			set(v)
			box.Refresh()
		end)
		slider:SetPoint("RIGHT", box, "LEFT", -14, 0)
		control = slider
		control.box = box
		refresh = function()
			slider.Refresh()
			box.Refresh()
		end
		local base = slider.SetDisabled
		function control:SetDisabled(off)
			base(self, off)
			box:SetEnabled(not off)
			box:SetAlpha(off and 0.4 or 1)
		end
	elseif kind == "dropdown" or kind == "font" or kind == "statusbar" then
		local items = spec.items
		if kind == "font" then items = function() return UI.MediaItems("font") end end
		if kind == "statusbar" then items = function() return UI.MediaItems("statusbar") end end
		control = UI.Dropdown(host, spec.width or 180, items, spec.get, set)
		control:SetPoint("RIGHT", -INSET, 0)
		refresh = control.Refresh
	elseif kind == "color" then
		control = UI.Swatch(host, spec.get, set, spec.alpha)
		control:SetPoint("RIGHT", -INSET, 0)
		refresh = control.Refresh
	elseif kind == "button" then
		control = UI.Button(host, spec.text or spec.label, spec.width or 150, 28, function(...)
			spec.click(...)
			W.Refresh(col)
		end, spec.style)
		control:SetPoint("RIGHT", -INSET, 0)
		if not spec.label then label:SetText("") end
		refresh = function()
			if type(spec.text) == "function" then control:SetLabel(spec.text()) end
		end
	elseif kind == "number" then
		control = UI.NumberBox(host, 70, spec.get, set, spec.step)
		control:SetPoint("RIGHT", -INSET, 0)
		refresh = control.Refresh
		function control:SetDisabled(off)
			self:SetEnabled(not off)
			self:SetAlpha(off and 0.4 or 1)
		end
	end

	if control then
		label:SetPoint("RIGHT", control, "LEFT", -12, 0)
	end
	if spec.tooltip then
		local hit = CreateFrame("Frame", nil, host)
		hit:SetAllPoints(label)
		hit:EnableMouse(true)
		UI.Tip(hit, spec.label, spec.tooltip)
	end
	AddRefresher(col, function()
		local off = spec.disabled and spec.disabled() and true or false
		if control and control.SetDisabled then control:SetDisabled(off) end
		label:SetAlpha(off and 0.4 or 1)
		if refresh then refresh() end
	end)
	return control
end

function W.Row(col, spec)
	local row = RowFrame(col, spec.height)
	Control(col, row, spec)
	Index(col, spec.label, row)
	return row
end

function W.Row2(col, left, right)
	local row = RowFrame(col)
	local half = (col.width - PAD * 2) / 2
	local a = CreateFrame("Frame", nil, row)
	a:SetPoint("TOPLEFT")
	a:SetPoint("BOTTOMLEFT")
	a:SetWidth(half)
	Control(col, a, left)
	Index(col, left.label, row)
	if right then
		local divider = row:CreateTexture(nil, "ARTWORK")
		divider:SetPoint("TOP", row, "TOP", 0, 0)
		divider:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
		divider:SetWidth(1)
		divider:SetColorTexture(1, 1, 1, 0.05)
		local b = CreateFrame("Frame", nil, row)
		b:SetPoint("TOPRIGHT")
		b:SetPoint("BOTTOMRIGHT")
		b:SetWidth(half)
		Control(col, b, right)
		Index(col, right.label, row)
	end
	return row
end

-- Rows of plain buttons, left aligned.
function W.Buttons(col, list)
	local row = RowFrame(col, 52)
	local x = INSET
	for i = 1, #list do
		local info = list[i]
		local button = UI.Button(row, info.text, info.width or 150, 32, function(...)
			info.click(...)
			W.Refresh(col)
		end, info.style)
		button:SetPoint("LEFT", x, 0)
		x = x + (info.width or 150) + 10
		if info.tooltip then UI.Tip(button, info.text, info.tooltip) end
		if info.disabled then
			AddRefresher(col, function() button:SetDisabled(info.disabled()) end)
		end
		Index(col, info.text, row)
	end
	return row
end

-- Segmented selector ("Player | Target | Focus ..."). Changing it refreshes
-- every row, whose getters read the selected key at call time.
function W.Selector(col, options, get, set)
	local row = RowFrame(col, 52)
	local buttons = {}
	local x = INSET
	local function Paint()
		local r, g, b = Soul:Accent()
		local current = get()
		for i = 1, #buttons do
			local button = buttons[i]
			local on = button.value == current
			button.face:SetColorTexture(on and r or 1, on and g or 1, on and b or 1, on and 0.14 or (button.hovered and 0.05 or 0))
			button.edge:SetColor(on and r or 1, on and g or 1, on and b or 1, on and 0.9 or 0.12)
			if on then
				button.text:SetTextColor(1, 1, 1)
			elseif button.hovered then
				button.text:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
			else
				button.text:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
			end
		end
	end
	for i = 1, #options do
		local option = options[i]
		local button = CreateFrame("Button", nil, row)
		local text = UI.Text(button, 14, UI.C.dim, "CENTER")
		text:SetPoint("CENTER")
		text:SetText(option.label)
		local width = math.max(78, (text:GetStringWidth() or 60) + 32)
		button:SetSize(width, 32)
		button:SetPoint("LEFT", x, 0)
		x = x + width + 6
		button.face = UI.Fill(button, { 1, 1, 1, 0 })
		button.edge = UI.Edge(button, 1, 1, 1, 0.12)
		button.text = text
		button.value = option.value
		button:SetScript("OnEnter", function(self) self.hovered = true Paint() end)
		button:SetScript("OnLeave", function(self) self.hovered = false Paint() end)
		button:SetScript("OnClick", function()
			set(option.value)
			W.Refresh(col)
		end)
		buttons[#buttons + 1] = button
	end
	AddRefresher(col, Paint)
	UI.OnAccent(Paint)
	return row
end

-- Multi-line text box (profile export/import).
function W.TextArea(col, height, readOnlyText)
	local row = RowFrame(col, height + 16)
	local holder = CreateFrame("Frame", nil, row)
	holder:SetPoint("TOPLEFT", INSET, -8)
	holder:SetPoint("BOTTOMRIGHT", -INSET, 8)
	UI.Fill(holder, { 0, 0, 0, 0.4 })
	UI.Edge(holder, 1, 1, 1, 0.12)
	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -8, 8)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	UI.SetFont(box, 13)
	box:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
	box:SetWidth(col.width - PAD * 2 - INSET * 2 - 20)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scroll:SetScrollChild(box)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, box:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 30)))
	end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	if readOnlyText then box:SetText(readOnlyText) end
	row.box = box
	return row
end

-- Plain text input row with a button.
function W.Input(col, label, buttonText, onSubmit, width)
	local row = RowFrame(col)
	local text = UI.Text(row, 15, UI.C.text)
	text:SetPoint("LEFT", INSET, 0)
	text:SetText(label)
	local button = UI.Button(row, buttonText, 120, 30, function() end, "plain")
	button:SetPoint("RIGHT", -INSET, 0)
	local box = CreateFrame("EditBox", nil, row)
	box:SetSize(width or 240, 30)
	box:SetPoint("RIGHT", button, "LEFT", -8, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)
	box:SetTextInsets(8, 8, 0, 0)
	UI.SetFont(box, 14)
	box:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
	UI.Fill(box, { 0, 0, 0, 0.35 })
	UI.Edge(box, 1, 1, 1, 0.14)
	local function Submit()
		onSubmit(box:GetText() or "", box)
		W.Refresh(col)
	end
	box:SetScript("OnEnterPressed", function(self) Submit() self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	button:SetScript("OnClick", Submit)
	row.box = box
	Index(col, label, row)
	return row
end

-- A list of rows built from a function at refresh time (profiles list).
function W.List(col, count, paint)
	local rows = {}
	for i = 1, count do
		local row = RowFrame(col, 40)
		row.index = i
		rows[i] = row
	end
	AddRefresher(col, function() paint(rows) end)
	return rows
end

-- Color helpers for settings stored as { r, g, b } arrays.
function W.ColorGet(tableFn, key, dr, dg, db)
	return function()
		local c = tableFn()[key]
		if type(c) == "table" then return c[1] or c.r, c[2] or c.g, c[3] or c.b, c[4] or c.a end
		return dr or 1, dg or 1, db or 1
	end
end

function W.ColorSet(tableFn, key, after)
	return function(r, g, b, a)
		if r == nil then return end
		tableFn()[key] = { r, g, b, a }
		if after then after() end
	end
end
