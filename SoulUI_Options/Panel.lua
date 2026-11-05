if SoulUI_Blocked or not SoulUI then return end

-- Settings window (/soul). Layout at 1 unit = 1 pixel (times the window scale):
--
--   +----------------+----------------------------------------------------------+
--   | [S] SoulUI 0.4 |  Page title                                      [x]     |  header band (drag)
--   |                |  description                                             |
--   | [search all ]  |  Tab  Tab  Tab                          [search page  ]  |
--   | SOULUI         |----------------------------------------------------------|
--   |   General      |  live preview (optional)                                 |
--   |   Profiles     |----------------------------------------------------------|
--   | FRAMES         |  SECTION                                                 |
--   |   Unit Frames *|  +-----------------------------------------------------+ |
--   |   ...          |  | label        control  |  label          control     | |
--   |                |  +-----------------------------------------------------+ |
--   | profile        |  [Reset Page] [Reload UI]            [Edit Mode] [Done]  |
--   +----------------+----------------------------------------------------------+
--
-- Pages: Soul:RegisterPage{ key, title, description, group, groupOrder, order,
-- addon = "SoulUI_X" (sidebar on/off dot), build(col) | tabs = { { key, title,
-- build(col), preview } }, preview, reset() }.
-- preview(holder, width) -> height, update(): a live mock of the element at the
-- top of the page, re-drawn after every change on that page.

local Soul = SoulUI
local UI = Soul.UI
local W = Soul.Widgets
Soul.Options = Soul.Options or {}

local WIDTH, HEIGHT = 1240, 800
local SIDEBAR = 250
local HEADER = 112
local FOOTER = 60
local CONTENT_W = WIDTH - SIDEBAR

local panel = CreateFrame("Frame", "SoulUI_OptionsFrame", UIParent)
panel:SetSize(WIDTH, HEIGHT)
panel:SetFrameStrata("DIALOG")
panel:SetToplevel(true)
panel:SetClampedToScreen(true)
panel:SetClampRectInsets(WIDTH - 120, -(WIDTH - 120), 0, HEIGHT - 60)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:Hide()

-- Background: deep gradient tinted toward the accent, plus a glow in the header.
local bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
bg:SetAllPoints()
bg:SetTexture("Interface\\Buttons\\WHITE8X8")
local glow = panel:CreateTexture(nil, "BACKGROUND", nil, -6)
glow:SetPoint("TOPLEFT", SIDEBAR, 0)
glow:SetPoint("TOPRIGHT")
glow:SetHeight(HEADER + 40)
glow:SetTexture("Interface\\Buttons\\WHITE8X8")
local streak = panel:CreateTexture(nil, "BACKGROUND", nil, -5)
streak:SetPoint("TOPLEFT", SIDEBAR, -1)
streak:SetPoint("TOPRIGHT", 0, -1)
streak:SetHeight(2)
streak:SetTexture("Interface\\Buttons\\WHITE8X8")
UI.Edge(panel, 1, 1, 1, 0.08)

local function PaintChrome()
	local r, g, b = Soul:Accent()
	if bg.SetGradient and CreateColor then
		bg:SetGradient("VERTICAL",
			CreateColor(0.030 + r * 0.01, 0.034 + g * 0.01, 0.040 + b * 0.01, 0.98),
			CreateColor(0.060 + r * 0.035, 0.066 + g * 0.035, 0.074 + b * 0.035, 0.98))
		glow:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.10))
		streak:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.05), CreateColor(r, g, b, 0.9))
	else
		bg:SetVertexColor(0.05, 0.055, 0.065, 0.98)
		glow:SetVertexColor(r, g, b, 0.05)
		streak:SetVertexColor(r, g, b, 0.8)
	end
end

-- Drag the header band or the sidebar brand to move the window.
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

------------------------------------------------------------------------------
-- Sidebar
------------------------------------------------------------------------------

local sidebar = CreateFrame("Frame", nil, panel)
sidebar:SetPoint("TOPLEFT")
sidebar:SetPoint("BOTTOMLEFT")
sidebar:SetWidth(SIDEBAR)
UI.Fill(sidebar, { 0, 0, 0, 0.28 })
local sideRule = sidebar:CreateTexture(nil, "ARTWORK")
sideRule:SetPoint("TOPRIGHT")
sideRule:SetPoint("BOTTOMRIGHT")
sideRule:SetWidth(1)
sideRule:SetColorTexture(1, 1, 1, 0.07)

local brand = CreateFrame("Frame", nil, sidebar)
brand:SetPoint("TOPLEFT")
brand:SetPoint("TOPRIGHT")
brand:SetHeight(72)
Mover(brand)
local mark = brand:CreateTexture(nil, "ARTWORK")
mark:SetSize(30, 30)
mark:SetPoint("LEFT", 20, 0)
local markInner = brand:CreateTexture(nil, "OVERLAY")
markInner:SetSize(24, 24)
markInner:SetPoint("CENTER", mark)
markInner:SetColorTexture(0.04, 0.045, 0.05, 1)
local markLetter = UI.Text(brand, 16, UI.C.text, "CENTER")
markLetter:SetPoint("CENTER", mark, "CENTER", 0, 0)
markLetter:SetText("S")
local brandName = UI.Text(brand, 20, UI.C.text)
brandName:SetPoint("LEFT", mark, "RIGHT", 12, 6)
brandName:SetText("SoulUI")
local brandVersion = UI.Text(brand, 11, UI.C.faint)
brandVersion:SetPoint("TOPLEFT", brandName, "BOTTOMLEFT", 0, -3)
brandVersion:SetText("v" .. (Soul.version or "?"))
UI.OnAccent(function(r, g, b)
	mark:SetColorTexture(r, g, b, 1)
	markLetter:SetTextColor(r, g, b)
end)

local search = CreateFrame("EditBox", nil, sidebar)
search:SetHeight(30)
search:SetPoint("TOPLEFT", 16, -80)
search:SetPoint("TOPRIGHT", -16, -80)
search:SetAutoFocus(false)
search:SetTextInsets(28, 10, 0, 0)
Soul:ApplyFont(search, 13, "")
search:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
UI.Fill(search, { 0, 0, 0, 0.4 })
local searchEdge = UI.Edge(search, 1, 1, 1, 0.1)
local searchIcon = search:CreateTexture(nil, "OVERLAY")
searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
searchIcon:SetSize(14, 14)
searchIcon:SetPoint("LEFT", 9, 0)
searchIcon:SetVertexColor(0.6, 0.6, 0.65)
local searchHint = UI.Text(search, 13, UI.C.faint)
searchHint:SetPoint("LEFT", 28, 0)
searchHint:SetText("Search all settings")

local profileText = UI.Text(sidebar, 12, UI.C.faint)
profileText:SetPoint("BOTTOMLEFT", 20, 18)
profileText:SetPoint("BOTTOMRIGHT", -20, 18)

------------------------------------------------------------------------------
-- Content: header, tabs, preview, scroll, footer
------------------------------------------------------------------------------

local content = CreateFrame("Frame", nil, panel)
content:SetPoint("TOPLEFT", SIDEBAR, 0)
content:SetPoint("BOTTOMRIGHT")

local header = CreateFrame("Frame", nil, content)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetHeight(HEADER - 40)
Mover(header)
local pageTitle = UI.Text(header, 26, UI.C.text)
pageTitle:SetPoint("TOPLEFT", 32, -20)
local pageDesc = UI.Text(header, 13, UI.C.dim)
pageDesc:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 1, -6)
pageDesc:SetPoint("RIGHT", -60, 0)

local close = CreateFrame("Button", nil, header)
close:SetSize(30, 30)
close:SetPoint("TOPRIGHT", -14, -14)
local closeFace = UI.Fill(close, { 1, 1, 1, 0.04 })
local closeEdge = UI.Edge(close, 1, 1, 1, 0.12)
local closeGlyph = UI.Text(close, 15, UI.C.dim, "CENTER")
closeGlyph:SetPoint("CENTER", 0, 1)
closeGlyph:SetText("x")
close:SetScript("OnEnter", function()
	closeFace:SetColorTexture(0.8, 0.2, 0.2, 0.35)
	closeEdge:SetColor(1, 0.4, 0.4, 0.6)
	closeGlyph:SetTextColor(1, 1, 1)
end)
close:SetScript("OnLeave", function()
	closeFace:SetColorTexture(1, 1, 1, 0.04)
	closeEdge:SetColor(1, 1, 1, 0.12)
	closeGlyph:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
end)
close:SetScript("OnClick", function() Soul.Options.Close() end)

local tabBar = CreateFrame("Frame", nil, content)
tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
tabBar:SetHeight(40)
UI.Fill(tabBar, { 0, 0, 0, 0.18 })
local tabRule = tabBar:CreateTexture(nil, "ARTWORK")
tabRule:SetPoint("BOTTOMLEFT")
tabRule:SetPoint("BOTTOMRIGHT")
tabRule:SetHeight(1)
tabRule:SetColorTexture(1, 1, 1, 0.07)

local pageSearch = CreateFrame("EditBox", nil, tabBar)
pageSearch:SetSize(220, 26)
pageSearch:SetPoint("RIGHT", -24, 0)
pageSearch:SetAutoFocus(false)
pageSearch:SetTextInsets(26, 8, 0, 0)
Soul:ApplyFont(pageSearch, 12, "")
pageSearch:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
UI.Fill(pageSearch, { 0, 0, 0, 0.35 })
local pageSearchEdge = UI.Edge(pageSearch, 1, 1, 1, 0.1)
local pageSearchIcon = pageSearch:CreateTexture(nil, "OVERLAY")
pageSearchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
pageSearchIcon:SetSize(12, 12)
pageSearchIcon:SetPoint("LEFT", 8, 0)
pageSearchIcon:SetVertexColor(0.6, 0.6, 0.65)
local pageSearchHint = UI.Text(pageSearch, 12, UI.C.faint)
pageSearchHint:SetPoint("LEFT", 26, 0)
pageSearchHint:SetText("Search this page")

local footer = CreateFrame("Frame", nil, content)
footer:SetPoint("BOTTOMLEFT")
footer:SetPoint("BOTTOMRIGHT")
footer:SetHeight(FOOTER)
UI.Fill(footer, { 0, 0, 0, 0.22 })
local footRule = footer:CreateTexture(nil, "ARTWORK")
footRule:SetPoint("TOPLEFT")
footRule:SetPoint("TOPRIGHT")
footRule:SetHeight(1)
footRule:SetColorTexture(1, 1, 1, 0.07)

local doneButton = UI.Button(footer, "Done", 130, 34, function() Soul.Options.Close() end, "outline")
doneButton:SetPoint("RIGHT", -24, 0)
local editButton = UI.Button(footer, "Edit Mode", 130, 34, function()
	Soul.Options.Close()
	Soul:OpenUnlock()
end, "plain")
editButton:SetPoint("RIGHT", doneButton, "LEFT", -10, 0)
UI.Tip(editButton, "Edit Mode", "Move, resize and anchor every SoulUI element on screen.")
local resetButton = UI.Button(footer, "Reset Page", 170, 34, function() end, "plain")
resetButton:SetPoint("LEFT", 24, 0)
local reloadButton = UI.Button(footer, "Reload UI", 120, 34, function() ReloadUI() end, "plain")
reloadButton:SetPoint("LEFT", resetButton, "RIGHT", 10, 0)

local previewHolder = CreateFrame("Frame", nil, content)
previewHolder:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
previewHolder:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
previewHolder:SetHeight(1)
previewHolder:SetClipsChildren(true)
local previewBg = previewHolder:CreateTexture(nil, "BACKGROUND")
previewBg:SetAllPoints()
previewBg:SetColorTexture(0, 0, 0, 0.22)
local previewRule = previewHolder:CreateTexture(nil, "ARTWORK")
previewRule:SetPoint("BOTTOMLEFT")
previewRule:SetPoint("BOTTOMRIGHT")
previewRule:SetHeight(1)
previewRule:SetColorTexture(1, 1, 1, 0.07)
local previewLabel = UI.Text(previewHolder, 10, UI.C.faint)
previewLabel:SetPoint("TOPLEFT", 14, -8)
previewLabel:SetText("PREVIEW")

local scroll = CreateFrame("ScrollFrame", nil, content)
scroll:SetPoint("TOPLEFT", previewHolder, "BOTTOMLEFT", 0, -6)
scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -12, 6)
scroll:SetClipsChildren(true)
scroll:EnableMouseWheel(true)
local thumb = content:CreateTexture(nil, "OVERLAY")
thumb:SetWidth(3)
thumb:Hide()

local target = 0
local function MaxScroll()
	local child = scroll:GetScrollChild()
	if not child then return 0 end
	return math.max(0, child:GetHeight() - scroll:GetHeight())
end

local function PaintThumb()
	local child = scroll:GetScrollChild()
	local view = scroll:GetHeight()
	local total = child and child:GetHeight() or 0
	if total <= view + 1 then thumb:Hide() return end
	local h = math.max(30, view * view / total)
	local travel = view - h
	local frac = scroll:GetVerticalScroll() / (total - view)
	thumb:SetHeight(h)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -travel * frac)
	local r, g, b = Soul:Accent()
	thumb:SetColorTexture(r, g, b, 0.7)
	thumb:Show()
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
	ScrollTo(target - delta * 80)
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
		local on = key == activePage
		row.bar:SetShown(on)
		row.bar:SetColorTexture(r, g, b, 1)
		row.glow:SetShown(on)
		if row.glow.SetGradient and CreateColor then
			row.glow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0))
		end
		local c = on and UI.C.text or UI.C.dim
		row.text:SetTextColor(c[1], c[2], c[3])
		if row.dot then
			if AddonOn(row.info.addon) == false then
				row.dot:SetColorTexture(0.5, 0.5, 0.52, 0.6)
				row.text:SetTextColor(0.42, 0.42, 0.45)
			else
				row.dot:SetColorTexture(r, g, b, 0.9)
			end
		end
	end
	profileText:SetText("Profile:  " .. (Soul.db and Soul.db.activeProfile or "?"))
end

local function PaintTabs(info)
	for i = 1, #tabButtons do tabButtons[i]:Hide() end
	if not info.tabs or #info.tabs < 2 then return end
	local x = 26
	local r, g, b = Soul:Accent()
	for i = 1, #info.tabs do
		local tab = info.tabs[i]
		local button = tabButtons[i]
		if not button then
			button = CreateFrame("Button", nil, tabBar)
			button:SetHeight(40)
			button.text = UI.Text(button, 14, UI.C.dim, "CENTER")
			button.text:SetPoint("CENTER", 0, 0)
			button.line = button:CreateTexture(nil, "OVERLAY")
			button.line:SetPoint("BOTTOMLEFT", 4, 0)
			button.line:SetPoint("BOTTOMRIGHT", -4, 0)
			button.line:SetHeight(2)
			button:SetScript("OnEnter", function(self)
				if not self.on then self.text:SetTextColor(1, 1, 1) end
			end)
			button:SetScript("OnLeave", function(self)
				if not self.on then self.text:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3]) end
			end)
			tabButtons[i] = button
		end
		button.text:SetText(tab.title)
		local width = (button.text:GetStringWidth() or 60) + 26
		button:SetWidth(width)
		button:ClearAllPoints()
		button:SetPoint("BOTTOMLEFT", x, 0)
		x = x + width + 4
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
	pageSearchHint:Show()
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
		reloadButton:ClearAllPoints()
		reloadButton:SetPoint("LEFT", resetButton, "RIGHT", 10, 0)
	else
		resetButton:Hide()
		reloadButton:ClearAllPoints()
		reloadButton:SetPoint("LEFT", 24, 0)
	end
	return current
end

local function NavRow(info, y)
	local row = CreateFrame("Button", nil, sidebar)
	row:SetHeight(34)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", -1, y)
	row.info = info
	row.glow = row:CreateTexture(nil, "BACKGROUND")
	row.glow:SetAllPoints()
	row.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.04)
	row.hover:Hide()
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(3)
	row.text = UI.Text(row, 14, UI.C.dim)
	row.text:SetPoint("LEFT", 26, 0)
	row.text:SetText(info.title)
	if info.addon then
		row.dot = row:CreateTexture(nil, "ARTWORK")
		row.dot:SetSize(6, 6)
		row.dot:SetPoint("RIGHT", -18, 0)
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

local navBuilt = false
local function BuildNav()
	local y = -124
	local lastGroup
	for i = 1, #Soul.optionPages do
		local info = Soul.optionPages[i]
		if info.group ~= lastGroup then
			lastGroup = info.group
			y = y - 12
			local group = UI.Text(sidebar, 11, UI.C.faint)
			group:SetText(string.upper(info.group or ""))
			group:SetPoint("TOPLEFT", 22, y)
			UI.OnAccent(function(r, g, b) group:SetTextColor(r, g, b, 0.9) end)
			y = y - 22
		end
		NavRow(info, y)
		y = y - 34
	end
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
				if not pageKey then label = label .. "  |cff8a8a96" .. TitleOf(entry.page, entry.tab) .. "|r" end
				items[#items + 1] = { value = i, label = label }
			end
		end
		if #items >= 40 then break end
	end
	if #items == 0 then items[1] = { value = 0, label = "|cff8a8a96No matches|r" } end
	return items
end

local function Clean(box)
	return ((box:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

search:SetScript("OnTextChanged", function(self, userInput)
	searchHint:SetShown((self:GetText() or "") == "")
	if not userInput then return end
	local text = Clean(self)
	if #text < 2 then UI.CloseMenu() return end
	BuildAll()
	UI.CloseMenu()
	UI.OpenMenu(self, Matches(text), nil, function(value)
		if W.searchIndex[value] then JumpTo(W.searchIndex[value]) end
	end, 400)
end)

pageSearch:SetScript("OnTextChanged", function(self, userInput)
	pageSearchHint:SetShown((self:GetText() or "") == "")
	if not userInput then return end
	local text = Clean(self)
	if #text < 2 then UI.CloseMenu() return end
	UI.CloseMenu()
	UI.OpenMenu(self, Matches(text, activePage, activeTab), nil, function(value)
		if W.searchIndex[value] then JumpTo(W.searchIndex[value]) end
	end, 300)
end)

local function SearchChrome(box, edge)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
		UI.CloseMenu()
	end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function()
		local r, g, b = Soul:Accent()
		edge:SetColor(r, g, b, 0.8)
	end)
	box:SetScript("OnEditFocusLost", function() edge:SetColor(1, 1, 1, 0.1) end)
end
SearchChrome(search, searchEdge)
SearchChrome(pageSearch, pageSearchEdge)

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
