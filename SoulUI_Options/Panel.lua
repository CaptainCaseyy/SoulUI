if SoulUI_Blocked or not SoulUI then return end

-- Settings window (/soul), 0.6.0 layout. 1 unit = 1 pixel (times the window scale).
--
--   +-------------------+------------------------------------------------------+
--   | <> SoulUI         |  Page title                 Window scale --o-- 100% [x] |  header (drag)
--   | ----------------- |  description                                           |
--   |  Edit Mode     >  |  Tab   Tab   Tab                        [search page] |  tabs
--   |  General          |------------------------------------------------------|
--   |  Profiles         |  live preview (optional)                             |
--   | [search all    ]  |------------------------------------------------------|
--   | Frames            |  SECTION                                             |
--   |  Unit Frames    o |  label          control  |  label           control  |
--   |  ...              |  label          control  |  label           control  |
--   | Combat            |                                                      |
--   |  ...              |------------------------------------------------------|
--   | Profile  Default  |  [Reload UI] [Reset page]          [Edit Mode] [Close] |  footer
--   +-------------------+------------------------------------------------------+
--
-- Pages: Soul:RegisterPage{ key, title, description, group, groupOrder, order,
-- addon = "SoulUI_X" (sidebar on/off dot), build(col) | tabs = { { key, title,
-- build(col), preview } }, preview, reset() }. Pages in group "SoulUI" sit at
-- the top of the sidebar without a heading; other groups get an accent heading.
-- preview(holder, width) -> height, update(): a live mock at the top of the page.

local Soul = SoulUI
local UI = Soul.UI
local W = Soul.Widgets
Soul.Options = Soul.Options or {}

local WIDTH, HEIGHT = 1180, 780
local SIDEBAR = 240
local HEADER = 92
local TABS = 46
local FOOTER = 64
local CONTENT_W = WIDTH - SIDEBAR
local GUTTER = 36 -- content left/right inset, matches Widgets PAD

local panel = CreateFrame("Frame", "SoulUI_OptionsFrame", UIParent)
panel:SetSize(WIDTH, HEIGHT)
panel:SetFrameStrata("DIALOG")
panel:SetToplevel(true)
panel:SetClampedToScreen(true)
panel:SetClampRectInsets(WIDTH - 120, -(WIDTH - 120), 0, HEIGHT - 60)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:Hide()

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Hairline(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetColorTexture(UI.C.line[1], UI.C.line[2], UI.C.line[3], UI.C.line[4])
	return t
end

-- Surfaces: one base, a darker sidebar, a faint accent haze behind the header.
UI.Fill(panel, UI.C.panel, "BACKGROUND", -8)
local haze = panel:CreateTexture(nil, "BACKGROUND", nil, -6)
haze:SetPoint("TOPLEFT", SIDEBAR, 0)
haze:SetPoint("TOPRIGHT")
haze:SetHeight(HEADER + TABS + 40)
haze:SetTexture(WHITE)
-- The outline sits on its own frame above the sidebar and content.
local rim = CreateFrame("Frame", nil, panel)
rim:SetAllPoints()
rim:SetFrameLevel(panel:GetFrameLevel() + 20)
rim:EnableMouse(false)
local frameEdge = UI.Edge(rim, 1, 1, 1, 0.1, "OVERLAY")

local function PaintChrome()
	local r, g, b = Soul:Accent()
	if haze.SetGradient and CreateColor then
		haze:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.075))
	else
		haze:SetVertexColor(r, g, b, 0.04)
	end
	frameEdge:SetColor(r, g, b, 0.3)
end

-- Drag the header or the sidebar brand to move the window.
local function Mover(frame)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function() panel:StartMoving() end)
	frame:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		local point, _, relPoint, x, y = panel:GetPoint(1)
		Soul.db.account.windows = Soul.db.account.windows or {}
		Soul.db.account.windows.SoulUI_OptionsFrame = { point = point, relPoint = relPoint, x = x, y = y }
	end)
end

-- Search box: dark field, hairline, magnifier, placeholder.
local function SearchBox(parent, width, height, placeholder, size)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, height)
	box:SetAutoFocus(false)
	box:SetTextInsets(28, 10, 0, 0)
	UI.SetFont(box, size or 13)
	box:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
	UI.Fill(box, { 0, 0, 0, 0.32 })
	box.edge = UI.Edge(box, 1, 1, 1, 0.1)
	local icon = box:CreateTexture(nil, "OVERLAY")
	icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	icon:SetSize(13, 13)
	icon:SetPoint("LEFT", 9, -1)
	icon:SetVertexColor(0.55, 0.57, 0.6)
	box.hint = UI.Text(box, size or 13, UI.C.faint)
	box.hint:SetPoint("LEFT", 28, 0)
	box.hint:SetText(placeholder)
	return box
end

------------------------------------------------------------------------------
-- Sidebar
------------------------------------------------------------------------------

local sidebar = CreateFrame("Frame", nil, panel)
sidebar:SetPoint("TOPLEFT")
sidebar:SetPoint("BOTTOMLEFT")
sidebar:SetWidth(SIDEBAR)
UI.Fill(sidebar, UI.C.sidebar)
local sideRule = Hairline(sidebar)
sideRule:SetPoint("TOPRIGHT")
sideRule:SetPoint("BOTTOMRIGHT")
sideRule:SetWidth(1)

-- Brand: a diamond mark (rotated square with a dark core) and the name.
local brand = CreateFrame("Frame", nil, sidebar)
brand:SetPoint("TOPLEFT")
brand:SetPoint("TOPRIGHT")
brand:SetHeight(80)
Mover(brand)
-- A Line is a rectangle along its direction, so a 45-degree line as thick as
-- it is long draws a diamond.
local markHost = CreateFrame("Frame", nil, brand)
markHost:SetSize(26, 26)
markHost:SetPoint("LEFT", 28, 0)
local function Diamond(side, layer)
	local half = side / (2 * math.sqrt(2))
	local line = markHost:CreateLine(nil, layer)
	line:SetThickness(side)
	line:SetStartPoint("CENTER", markHost, -half, -half)
	line:SetEndPoint("CENTER", markHost, half, half)
	return line
end
local mark = Diamond(17, "ARTWORK")
local markCore = Diamond(8, "OVERLAY")
markCore:SetColorTexture(UI.C.sidebar[1], UI.C.sidebar[2], UI.C.sidebar[3], 1)
local brandName = UI.Text(brand, 24, UI.C.text)
brandName:SetPoint("LEFT", markHost, "RIGHT", 12, 0)
brandName:SetText("SoulUI")

-- Glow rule under the brand: accent fading out to both ends.
local ruleLeft = sidebar:CreateTexture(nil, "ARTWORK")
ruleLeft:SetTexture(WHITE)
ruleLeft:SetHeight(1)
ruleLeft:SetPoint("TOPLEFT", 20, -80)
ruleLeft:SetPoint("TOPRIGHT", sidebar, "TOP", 0, -80)
local ruleRight = sidebar:CreateTexture(nil, "ARTWORK")
ruleRight:SetTexture(WHITE)
ruleRight:SetHeight(1)
ruleRight:SetPoint("TOPLEFT", sidebar, "TOP", 0, -80)
ruleRight:SetPoint("TOPRIGHT", -20, -80)
local ruleGlow = sidebar:CreateTexture(nil, "ARTWORK", nil, -1)
ruleGlow:SetTexture(WHITE)
ruleGlow:SetSize(SIDEBAR - 80, 10)
ruleGlow:SetPoint("BOTTOM", sidebar, "TOP", 0, -80)

UI.OnAccent(function(r, g, b)
	mark:SetColorTexture(r, g, b, 1)
	if ruleLeft.SetGradient and CreateColor then
		ruleLeft:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.9))
		ruleRight:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.9), CreateColor(r, g, b, 0))
		ruleGlow:SetGradient("VERTICAL", CreateColor(r, g, b, 0.12), CreateColor(r, g, b, 0))
	else
		ruleLeft:SetVertexColor(r, g, b, 0.5)
		ruleRight:SetVertexColor(r, g, b, 0.5)
		ruleGlow:SetVertexColor(r, g, b, 0.05)
	end
end)

-- Footer of the sidebar: active profile (click: Profiles page) and version.
local profileRow = CreateFrame("Button", nil, sidebar)
profileRow:SetPoint("BOTTOMLEFT", 0, 0)
profileRow:SetPoint("BOTTOMRIGHT", -1, 0)
profileRow:SetHeight(FOOTER)
local profileRule = Hairline(profileRow)
profileRule:SetPoint("TOPLEFT")
profileRule:SetPoint("TOPRIGHT")
profileRule:SetHeight(1)
local profileHover = UI.Fill(profileRow, { 1, 1, 1, 0.035 })
profileHover:Hide()
local profileLabel = UI.Text(profileRow, 12, UI.C.faint)
profileLabel:SetPoint("TOPLEFT", 24, -16)
profileLabel:SetText("Profile")
local profileName = UI.Text(profileRow, 15, UI.C.text)
profileName:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -4)
profileName:SetPoint("RIGHT", -60, 0)
local versionText = UI.Text(profileRow, 12, UI.C.faint, "RIGHT")
versionText:SetPoint("BOTTOMRIGHT", -20, 16)
versionText:SetText("v" .. (Soul.version or "?"))
profileRow:SetScript("OnEnter", function() profileHover:Show() end)
profileRow:SetScript("OnLeave", function() profileHover:Hide() end)
profileRow:SetScript("OnClick", function() Soul.Options.Show("profiles") end)

-- Nav lives in a scroll frame between the brand and the profile row.
local navScroll = CreateFrame("ScrollFrame", nil, sidebar)
navScroll:SetPoint("TOPLEFT", 0, -92)
navScroll:SetPoint("BOTTOMRIGHT", profileRow, "TOPRIGHT", 0, 6)
navScroll:SetClipsChildren(true)
navScroll:EnableMouseWheel(true)
local nav = CreateFrame("Frame", nil, navScroll)
nav:SetSize(SIDEBAR - 1, 10)
navScroll:SetScrollChild(nav)
navScroll:SetScript("OnMouseWheel", function(self, delta)
	local maxScroll = math.max(0, nav:GetHeight() - self:GetHeight())
	self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 40)))
end)

------------------------------------------------------------------------------
-- Content: header, tabs, preview, scroll, footer
------------------------------------------------------------------------------

local content = CreateFrame("Frame", nil, panel)
content:SetPoint("TOPLEFT", SIDEBAR, 0)
content:SetPoint("BOTTOMRIGHT")

local header = CreateFrame("Frame", nil, content)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetHeight(HEADER)
Mover(header)
local pageTitle = UI.Text(header, 30, UI.C.text)
pageTitle:SetPoint("TOPLEFT", GUTTER, -24)
local pageDesc = UI.Text(header, 14, UI.C.dim)
pageDesc:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 1, -8)
pageDesc:SetPoint("RIGHT", -380, 0)

local close = UI.IconButton(header, "close", 30, function() Soul.Options.Close() end)
close:SetPoint("TOPRIGHT", -18, -18)

-- Window scale lives in the header, next to close.
local scaleValue = UI.Text(header, 13, UI.C.text, "RIGHT")
scaleValue:SetPoint("RIGHT", close, "LEFT", -16, 0)
scaleValue:SetWidth(40)
local function PanelScaleSetting() return Soul.db and Soul.db.account.panelScale or 1 end
local scaleSlider = UI.Slider(header, 110, 0.6, 1.6, 0.05, PanelScaleSetting, function(v)
	Soul.db.account.panelScale = v
	scaleValue:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
end)
scaleSlider:SetPoint("RIGHT", scaleValue, "LEFT", -10, 0)
-- Applying the scale while dragging would move the slider under the cursor;
-- apply it when the mouse is released.
scaleSlider:HookScript("OnMouseUp", function() panel:SetScale(UI.PanelScale()) end)
scaleSlider:HookScript("OnMouseWheel", function() panel:SetScale(UI.PanelScale()) end)
local scaleLabel = UI.Text(header, 13, UI.C.dim, "RIGHT")
scaleLabel:SetPoint("RIGHT", scaleSlider, "LEFT", -12, 0)
scaleLabel:SetText("Window scale")

local tabBar = CreateFrame("Frame", nil, content)
tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
tabBar:SetHeight(TABS)
local tabRule = Hairline(tabBar)
tabRule:SetPoint("BOTTOMLEFT")
tabRule:SetPoint("BOTTOMRIGHT")
tabRule:SetHeight(1)

local pageSearch = SearchBox(tabBar, 240, 30, "Search this page", 13)
pageSearch:SetPoint("RIGHT", -GUTTER + 8, 2)

local footer = CreateFrame("Frame", nil, content)
footer:SetPoint("BOTTOMLEFT")
footer:SetPoint("BOTTOMRIGHT")
footer:SetHeight(FOOTER)
UI.Fill(footer, { 0, 0, 0, 0.18 })
local footRule = Hairline(footer)
footRule:SetPoint("TOPLEFT")
footRule:SetPoint("TOPRIGHT")
footRule:SetHeight(1)

local closeButton = UI.Button(footer, "Close", 136, 34, function() Soul.Options.Close() end, "outline")
closeButton:SetPoint("RIGHT", -GUTTER + 8, 0)
local editButton = UI.Button(footer, "Edit Mode", 136, 34, function()
	Soul.Options.Close()
	Soul:OpenUnlock()
end, "plain")
editButton:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
UI.Tip(editButton, "Edit Mode", "Move, resize, anchor and hide every SoulUI element on screen.")
local reloadButton = UI.Button(footer, "Reload UI", 136, 34, function() ReloadUI() end, "plain")
reloadButton:SetPoint("LEFT", GUTTER - 8, 0)
local resetButton = UI.Button(footer, "Reset page", 170, 34, function() end, "ghost")
resetButton:SetPoint("LEFT", reloadButton, "RIGHT", 10, 0)

local previewHolder = CreateFrame("Frame", nil, content)
previewHolder:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
previewHolder:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
previewHolder:SetHeight(1)
previewHolder:SetClipsChildren(true)
local previewBg = previewHolder:CreateTexture(nil, "BACKGROUND")
previewBg:SetAllPoints()
previewBg:SetColorTexture(0, 0, 0, 0.2)
local previewRule = Hairline(previewHolder)
previewRule:SetPoint("BOTTOMLEFT")
previewRule:SetPoint("BOTTOMRIGHT")
previewRule:SetHeight(1)
local previewLabel = UI.Text(previewHolder, 11, UI.C.faint)
previewLabel:SetPoint("TOPLEFT", GUTTER - 18, -10)
previewLabel:SetText("PREVIEW")

local scroll = CreateFrame("ScrollFrame", nil, content)
scroll:SetPoint("TOPLEFT", previewHolder, "BOTTOMLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -14, 0)
scroll:SetClipsChildren(true)
scroll:EnableMouseWheel(true)
local track = content:CreateTexture(nil, "OVERLAY")
track:SetWidth(2)
track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -10)
track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 8, 10)
track:SetColorTexture(1, 1, 1, 0.05)
track:Hide()
local thumb = content:CreateTexture(nil, "OVERLAY", nil, 1)
thumb:SetWidth(2)
thumb:Hide()

local target = 0
local function MaxScroll()
	local child = scroll:GetScrollChild()
	if not child then return 0 end
	return math.max(0, child:GetHeight() - scroll:GetHeight())
end

local function PaintThumb()
	local child = scroll:GetScrollChild()
	local view = scroll:GetHeight() - 20
	local total = child and child:GetHeight() or 0
	if total <= scroll:GetHeight() + 1 then
		thumb:Hide()
		track:Hide()
		return
	end
	local h = math.max(30, view * scroll:GetHeight() / total)
	local travel = view - h
	local frac = scroll:GetVerticalScroll() / (total - scroll:GetHeight())
	thumb:SetHeight(h)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -10 - travel * frac)
	local r, g, b = Soul:Accent()
	thumb:SetColorTexture(r, g, b, 0.8)
	thumb:Show()
	track:Show()
end

local function ScrollTo(value, instant)
	target = math.max(0, math.min(MaxScroll(), value))
	if instant then
		scroll:SetVerticalScroll(target)
		scroll:SetScript("OnUpdate", nil)
		PaintThumb()
		return
	end
	scroll:SetScript("OnUpdate", function(self, dt)
		local current = self:GetVerticalScroll()
		if math.abs(target - current) < 0.5 then
			self:SetVerticalScroll(target)
			self:SetScript("OnUpdate", nil)
		else
			self:SetVerticalScroll(math.floor(current + (target - current) * math.min(1, dt * 14) + 0.5))
		end
		PaintThumb()
	end)
end

scroll:SetScript("OnMouseWheel", function(_, delta)
	ScrollTo(target - delta * 90)
end)

------------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------------

local navRows = {}
local tabButtons = {}
local built = {}
local previews = {}
local activePage, activeTab
local current

local function PageInfo(key)
	for i = 1, #Soul.optionPages do
		if Soul.optionPages[i].key == key then return Soul.optionPages[i] end
	end
	return nil
end

local function TabInfo(info, tabKey)
	if not info.tabs then return nil end
	for i = 1, #info.tabs do
		if info.tabs[i].key == tabKey then return info.tabs[i] end
	end
	return info.tabs[1]
end

local function AddonOn(name)
	if not name or not C_AddOns or not C_AddOns.GetAddOnEnableState then return nil end
	local state = C_AddOns.GetAddOnEnableState(name, UnitName("player"))
	return state and state > 0
end

local function Preview(info, tab)
	local builder = (tab and tab.preview) or info.preview
	if not builder then return nil end
	local id = info.key .. ":" .. (tab and tab.key or "") .. ":preview"
	if previews[id] ~= nil then return previews[id] or nil end
	local frame = CreateFrame("Frame", nil, previewHolder)
	frame:SetPoint("TOPLEFT")
	frame:SetPoint("TOPRIGHT")
	frame:Hide()
	local ok, height, update = pcall(builder, frame, CONTENT_W)
	if not ok then
		Soul:Debug("preview", height)
		frame:Hide()
		previews[id] = false
		return nil
	end
	previews[id] = { frame = frame, height = height or 120, update = update }
	return previews[id]
end

local function Build(info, tab)
	local id = info.key .. ":" .. (tab and tab.key or "")
	if built[id] then return built[id] end
	local page = CreateFrame("Frame", nil, scroll)
	page:SetWidth(CONTENT_W - 14)
	page:Hide()
	local col = W.Begin(page, CONTENT_W - 14, info.key, tab and tab.key)
	local builder = tab and tab.build or info.build
	local ok, err = pcall(builder, col)
	if not ok then
		W.Note(col, "|cffff5555This page failed to build:|r " .. tostring(err))
	end
	W.Finish(col)
	built[id] = { frame = page, col = col }
	return built[id]
end

local function PaintNav()
	local r, g, b = Soul:Accent()
	for key, row in pairs(navRows) do
		if row.info then
			local on = key == activePage
			row.bar:SetShown(on)
			row.bar:SetColorTexture(r, g, b, 1)
			row.glow:SetShown(on)
			if row.glow.SetGradient and CreateColor then
				row.glow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0.0))
			else
				row.glow:SetVertexColor(r, g, b, 0.08)
			end
			local c = on and UI.C.text or UI.C.dim
			row.text:SetTextColor(c[1], c[2], c[3])
			if row.dot then
				local state = AddonOn(row.info.addon)
				if state == false then
					row.dot:SetColorTexture(1, 1, 1, 0.18)
					row.text:SetTextColor(UI.C.faint[1], UI.C.faint[2], UI.C.faint[3])
				else
					row.dot:SetColorTexture(r, g, b, on and 1 or 0.7)
				end
			end
		end
	end
	profileName:SetText(Soul.db and Soul.db.activeProfile or "?")
end

local function PaintTabs(info)
	for i = 1, #tabButtons do tabButtons[i]:Hide() end
	if not info.tabs or #info.tabs < 2 then return end
	local x = GUTTER
	local r, g, b = Soul:Accent()
	for i = 1, #info.tabs do
		local tab = info.tabs[i]
		local button = tabButtons[i]
		if not button then
			button = CreateFrame("Button", nil, tabBar)
			button:SetHeight(TABS)
			button.text = UI.Text(button, 15, UI.C.dim, "CENTER")
			button.text:SetPoint("CENTER", 0, 1)
			button.line = button:CreateTexture(nil, "OVERLAY")
			button.line:SetPoint("BOTTOMLEFT", -4, 0)
			button.line:SetPoint("BOTTOMRIGHT", 4, 0)
			button.line:SetHeight(2)
			button:SetScript("OnEnter", function(self)
				if not self.on then self.text:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3]) end
			end)
			button:SetScript("OnLeave", function(self)
				if not self.on then self.text:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3]) end
			end)
			tabButtons[i] = button
		end
		button.text:SetText(tab.title)
		local width = (button.text:GetStringWidth() or 60) + 4
		button:SetWidth(width)
		button:ClearAllPoints()
		button:SetPoint("BOTTOMLEFT", x, 0)
		x = x + width + 30
		button.on = tab.key == activeTab
		button.line:SetColorTexture(r, g, b, 1)
		button.line:SetShown(button.on)
		if button.on then
			button.text:SetTextColor(1, 1, 1)
		else
			button.text:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
		end
		button:SetScript("OnClick", function() Soul.Options.Show(info.key, tab.key) end)
		button:Show()
	end
end

function Soul.Options.Show(pageKey, tabKey)
	local info = PageInfo(pageKey) or Soul.optionPages[1]
	if not info then return end
	UI.CloseMenu()
	local tab = TabInfo(info, tabKey or (info.key == activePage and activeTab) or info._lastTab)
	activePage = info.key
	activeTab = tab and tab.key
	info._lastTab = activeTab
	pageTitle:SetText(info.title)
	pageDesc:SetText(info.description or "")
	pageSearch:SetText("")
	pageSearch.hint:Show()
	PaintNav()
	PaintTabs(info)
	if current then current.frame:Hide() end
	for _, preview in pairs(previews) do
		if preview then preview.frame:Hide() end
	end
	local preview = Preview(info, tab)
	if preview then
		previewHolder:SetHeight(preview.height)
		preview.frame:SetHeight(preview.height)
		preview.frame:Show()
	else
		previewHolder:SetHeight(1)
	end
	previewLabel:SetShown(preview ~= nil)
	previewBg:SetShown(preview ~= nil)
	previewRule:SetShown(preview ~= nil)
	current = Build(info, tab)
	current.col.onRefresh = preview and preview.update or nil
	scroll:SetScrollChild(current.frame)
	current.frame:Show()
	W.Refresh(current.col)
	ScrollTo(0, true)
	if info.reset then
		resetButton:Show()
		resetButton:SetLabel("Reset " .. info.title)
		resetButton:SetScript("OnClick", function()
			info.reset()
			W.Refresh(current.col)
			Soul:Print(info.title .. " reset to defaults.")
		end)
	else
		resetButton:Hide()
	end
	return current
end

local NAV_ROW = 34

local function NavRow(info, y)
	local row = CreateFrame("Button", nil, nav)
	row:SetHeight(NAV_ROW)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row.info = info
	row.glow = row:CreateTexture(nil, "BACKGROUND")
	row.glow:SetAllPoints()
	row.glow:SetTexture(WHITE)
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.035)
	row.hover:Hide()
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	row.text = UI.Text(row, 15, UI.C.dim)
	row.text:SetPoint("LEFT", 32, 0)
	row.text:SetPoint("RIGHT", -34, 0)
	row.text:SetText(info.title)
	if info.addon then
		row.dot = row:CreateTexture(nil, "ARTWORK")
		row.dot:SetSize(6, 6)
		row.dot:SetPoint("RIGHT", -22, 0)
		UI.Tip(row, info.title, function()
			if AddonOn(info.addon) == false then return "Turned off. Turn it on under General > Modules." end
			return info.description
		end)
	end
	row:HookScript("OnEnter", function(self) self.hover:Show() end)
	row:HookScript("OnLeave", function(self) self.hover:Hide() end)
	row:SetScript("OnClick", function() Soul.Options.Show(info.key) end)
	navRows[info.key] = row
	return row
end

-- The pinned action at the top: Edit Mode, with a chevron.
local function ActionRow(y)
	local row = CreateFrame("Button", nil, nav)
	row:SetHeight(NAV_ROW)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	local hover = UI.Fill(row, { 1, 1, 1, 0.035 })
	hover:Hide()
	local text = UI.Text(row, 15, UI.C.dim)
	text:SetPoint("LEFT", 32, 0)
	text:SetText("Edit Mode")
	local chevron = UI.Glyph(row, "chevron-right", 12, UI.C.dim, 1.5)
	chevron:SetPoint("RIGHT", -20, 0)
	UI.OnAccent(function(r, g, b) chevron:SetColor(r, g, b, 1) end)
	row:SetScript("OnEnter", function()
		hover:Show()
		text:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
	end)
	row:SetScript("OnLeave", function()
		hover:Hide()
		text:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
	end)
	row:SetScript("OnClick", function()
		Soul.Options.Close()
		Soul:OpenUnlock()
	end)
	UI.Tip(row, "Edit Mode", "Move, resize, anchor and hide every SoulUI element. Also /soul move.")
	return row
end

local search = SearchBox(nav, SIDEBAR - 40, 30, "Search all settings", 13)

local navBuilt = false
local function BuildNav()
	local y = -2
	ActionRow(y)
	y = y - NAV_ROW
	local lastGroup
	local searchPlaced = false
	for i = 1, #Soul.optionPages do
		local info = Soul.optionPages[i]
		if info.group ~= lastGroup then
			lastGroup = info.group
			if info.group ~= "SoulUI" then
				if not searchPlaced then
					searchPlaced = true
					y = y - 12
					search:SetPoint("TOPLEFT", 20, y)
					y = y - 30 - 10
				end
				y = y - 12
				local group = UI.Text(nav, 14, UI.C.text)
				group:SetText(info.group or "")
				group:SetPoint("TOPLEFT", 24, y - 4)
				UI.OnAccent(function(r, g, b) group:SetTextColor(r, g, b, 1) end)
				y = y - 26
			end
		end
		NavRow(info, y)
		y = y - NAV_ROW
	end
	if not searchPlaced then
		search:SetPoint("TOPLEFT", 20, y - 12)
		y = y - 54
	end
	nav:SetHeight(math.abs(y) + 12)
end

------------------------------------------------------------------------------
-- Search (all settings, and this page)
------------------------------------------------------------------------------

local function BuildAll()
	for i = 1, #Soul.optionPages do
		local info = Soul.optionPages[i]
		if info.tabs then
			for t = 1, #info.tabs do Build(info, info.tabs[t]) end
		else
			Build(info, nil)
		end
	end
end

local function TitleOf(pageKey, tabKey)
	local info = PageInfo(pageKey)
	if not info then return pageKey or "" end
	local tab = tabKey and TabInfo(info, tabKey)
	if tab and info.tabs and #info.tabs > 1 then return info.title .. " / " .. tab.title end
	return info.title
end

local function JumpTo(entry)
	local shown = Soul.Options.Show(entry.page, entry.tab)
	if shown and entry.row then
		C_Timer.After(0, function()
			local top = shown.frame:GetTop()
			local rowTop = entry.row:GetTop()
			if top and rowTop then ScrollTo(top - rowTop - 40, true) end
			W.Flash(entry.row)
		end)
	end
end

local function Matches(text, pageKey, tabKey)
	local items, seen = {}, {}
	for i = 1, #W.searchIndex do
		local entry = W.searchIndex[i]
		local samePage = not pageKey or (entry.page == pageKey and entry.tab == tabKey)
		if samePage and entry.lower:find(text, 1, true) then
			local id = entry.label .. "|" .. (entry.page or "") .. "|" .. (entry.tab or "")
			if not seen[id] then
				seen[id] = true
				local label = entry.label
				if not pageKey then label = label .. "  |cff70747a" .. TitleOf(entry.page, entry.tab) .. "|r" end
				items[#items + 1] = { value = i, label = label }
			end
		end
		if #items >= 40 then break end
	end
	if #items == 0 then items[1] = { value = 0, label = "|cff70747aNo matches|r" } end
	return items
end

local function Clean(box)
	return ((box:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

search:SetScript("OnTextChanged", function(self, userInput)
	self.hint:SetShown((self:GetText() or "") == "")
	if not userInput then return end
	local text = Clean(self)
	if #text < 2 then UI.CloseMenu() return end
	BuildAll()
	UI.CloseMenu()
	UI.OpenMenu(self, Matches(text), nil, function(value)
		if W.searchIndex[value] then JumpTo(W.searchIndex[value]) end
	end, 420)
end)

pageSearch:SetScript("OnTextChanged", function(self, userInput)
	self.hint:SetShown((self:GetText() or "") == "")
	if not userInput then return end
	local text = Clean(self)
	if #text < 2 then UI.CloseMenu() return end
	UI.CloseMenu()
	UI.OpenMenu(self, Matches(text, activePage, activeTab), nil, function(value)
		if W.searchIndex[value] then JumpTo(W.searchIndex[value]) end
	end, 300)
end)

local function SearchChrome(box)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
		UI.CloseMenu()
	end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self)
		local r, g, b = Soul:Accent()
		self.edge:SetColor(r, g, b, 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self) self.edge:SetColor(1, 1, 1, 0.1) end)
end
SearchChrome(search)
SearchChrome(pageSearch)

------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------

function Soul.Options.Open(_, pageKey)
	if InCombatLockdown() then
		Soul:Print("The editor closes during combat.")
		return
	end
	if Soul.unlocking then Soul:CommitUnlock(true) end
	if not navBuilt then
		navBuilt = true
		BuildNav()
	end
	PaintChrome()
	panel:SetScale(UI.PanelScale())
	scaleSlider.Refresh()
	scaleValue:SetText(string.format("%d%%", math.floor(PanelScaleSetting() * 100 + 0.5)))
	panel:ClearAllPoints()
	local saved = Soul.db.account.windows and Soul.db.account.windows.SoulUI_OptionsFrame
	if type(saved) == "table" and saved.point then
		panel:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end
	panel:Show()
	Soul.Options.Show(pageKey or activePage or (Soul.optionPages[1] and Soul.optionPages[1].key))
end

function Soul.Options.Close()
	UI.CloseMenu()
	search:ClearFocus()
	pageSearch:ClearFocus()
	panel:Hide()
end

function Soul.Options.Toggle()
	if panel:IsShown() then Soul.Options.Close() else Soul.Options.Open(nil) end
end

function Soul.Options.Refresh()
	PaintChrome()
	if current then W.Refresh(current.col) end
	PaintNav()
	if panel:IsShown() then
		local info = PageInfo(activePage)
		if info then PaintTabs(info) end
	end
end

function Soul.Options.Invalidate()
	for _, page in pairs(built) do page.frame:Hide() end
	built = {}
	W.searchIndex = {}
	current = nil
	if panel:IsShown() and activePage then Soul.Options.Show(activePage, activeTab) end
end

function Soul.Options.SetScale()
	panel:SetScale(UI.PanelScale())
	scaleSlider.Refresh()
	scaleValue:SetText(string.format("%d%%", math.floor(PanelScaleSetting() * 100 + 0.5)))
end

table.insert(UISpecialFrames, "SoulUI_OptionsFrame")

panel:SetScript("OnHide", function() UI.CloseMenu() end)
panel:RegisterEvent("PLAYER_REGEN_DISABLED")
panel:SetScript("OnEvent", function(self)
	if self:IsShown() then
		Soul.Options.Close()
		Soul:Print("Editor closed for combat.")
	end
end)

Soul:On("ProfileChanged", function() Soul.Options.Refresh() end)
Soul:On("ThemeChanged", function() Soul.Options.Refresh() end)
