if SoulUI_Blocked or not SoulUI then return end

-- Settings window (/soul). Layout, at 1 unit = 1 pixel (times the user's
-- window scale):
--
--   +-----------------------------------------------------------------+
--   | SoulUI 0.3.0                                  [Edit Mode]  x   |  title bar, drag to move
--   +------------+----------------------------------------------------+
--   | [search  ] | Page title                                         |
--   | GROUP      | description                                        |
--   | > Page     | [Tab] [Tab] [Tab]                                  |
--   |   Page     |----------------------------------------------------|
--   |            | rows (scroll)                                      |
--   | profile    |----------------------------------------------------|
--   |            | [Reload UI] [Reset Page]                  [Close]  |
--   +------------+----------------------------------------------------+
--
-- Pages register with Soul:RegisterPage{ key, title, description, group,
-- groupOrder, order, build(col) | tabs = { { key, title, build(col) } },
-- reset() }.

local Soul = SoulUI
local UI = Soul.UI
local W = Soul.Widgets
Soul.Options = Soul.Options or {}

local WIDTH, HEIGHT = 1180, 760
local SIDEBAR = 240
local HEADER = 92
local TABS = 40
local FOOTER = 58
local CONTENT_W = WIDTH - SIDEBAR

local panel = UI.Window("SoulUI_OptionsFrame", "", WIDTH, HEIGHT, {
	strata = "DIALOG",
	barHeight = 48,
	onClose = function() Soul.Options.Close() end,
})

-- Title: accent name + dim version.
local brand = UI.Text(panel.bar, 20, UI.C.text)
brand:SetPoint("LEFT", 18, 0)
brand:SetText("SoulUI")
UI.OnAccent(function(r, g, b) brand:SetTextColor(r, g, b) end)
local version = UI.Text(panel.bar, 12, UI.C.faint)
version:SetPoint("LEFT", brand, "RIGHT", 8, -1)
version:SetText("v" .. (Soul.version or "?"))

local editButton = UI.Button(panel.bar, "Edit Mode", 120, 30, function()
	Soul.Options.Close()
	Soul:OpenUnlock()
end, "accent")
editButton:SetPoint("RIGHT", panel.close, "LEFT", -10, 0)
UI.Tip(editButton, "Edit Mode", "Move, resize and anchor every SoulUI element on screen.")

-- Sidebar.
local sidebar = CreateFrame("Frame", nil, panel)
sidebar:SetPoint("TOPLEFT", 0, -48)
sidebar:SetPoint("BOTTOMLEFT")
sidebar:SetWidth(SIDEBAR)
UI.Fill(sidebar, UI.C.sidebar)
local sideRule = sidebar:CreateTexture(nil, "ARTWORK")
sideRule:SetPoint("TOPRIGHT")
sideRule:SetPoint("BOTTOMRIGHT")
sideRule:SetWidth(1)
sideRule:SetColorTexture(1, 1, 1, 0.06)

local search = CreateFrame("EditBox", nil, sidebar)
search:SetPoint("TOPLEFT", 14, -14)
search:SetPoint("TOPRIGHT", -14, -14)
search:SetHeight(30)
search:SetAutoFocus(false)
search:SetTextInsets(10, 10, 0, 0)
Soul:ApplyFont(search, 13, "")
search:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
UI.Fill(search, { 0, 0, 0, 0.35 })
local searchEdge = UI.Edge(search, 1, 1, 1, 0.12)
local searchHint = UI.Text(search, 13, UI.C.faint)
searchHint:SetPoint("LEFT", 10, 0)
searchHint:SetText("Search settings")

local profileText = UI.Text(sidebar, 12, UI.C.faint)
profileText:SetPoint("BOTTOMLEFT", 16, 16)
profileText:SetPoint("BOTTOMRIGHT", -16, 16)

-- Content region.
local content = CreateFrame("Frame", nil, panel)
content:SetPoint("TOPLEFT", SIDEBAR, -48)
content:SetPoint("BOTTOMRIGHT")

local header = CreateFrame("Frame", nil, content)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetHeight(HEADER)
local pageTitle = UI.Text(header, 24, UI.C.text)
pageTitle:SetPoint("TOPLEFT", 28, -22)
local pageDesc = UI.Text(header, 13, UI.C.dim)
pageDesc:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -8)
pageDesc:SetPoint("RIGHT", -28, 0)

local tabBar = CreateFrame("Frame", nil, content)
tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
tabBar:SetHeight(TABS)
local tabRule = tabBar:CreateTexture(nil, "ARTWORK")
tabRule:SetPoint("BOTTOMLEFT")
tabRule:SetPoint("BOTTOMRIGHT")
tabRule:SetHeight(1)
tabRule:SetColorTexture(1, 1, 1, 0.07)

local footer = CreateFrame("Frame", nil, content)
footer:SetPoint("BOTTOMLEFT")
footer:SetPoint("BOTTOMRIGHT")
footer:SetHeight(FOOTER)
UI.Fill(footer, { 0, 0, 0, 0.18 })
local footRule = footer:CreateTexture(nil, "ARTWORK")
footRule:SetPoint("TOPLEFT")
footRule:SetPoint("TOPRIGHT")
footRule:SetHeight(1)
footRule:SetColorTexture(1, 1, 1, 0.07)

local closeButton = UI.Button(footer, "Close", 110, 32, function() Soul.Options.Close() end, "accent")
closeButton:SetPoint("RIGHT", -20, 0)
local reloadButton = UI.Button(footer, "Reload UI", 110, 32, function() ReloadUI() end)
reloadButton:SetPoint("LEFT", 20, 0)
local resetButton = UI.Button(footer, "Reset Page", 120, 32, function() end, "plain")
resetButton:SetPoint("LEFT", reloadButton, "RIGHT", 8, 0)

-- Scroll area with eased scrolling and a thin thumb.
local scroll = CreateFrame("ScrollFrame", nil, content)
scroll:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -10, 0)
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
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 7, -travel * frac)
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
		local step = (target - current) * math.min(1, dt * 14)
		if math.abs(target - current) < 0.5 then
			self:SetVerticalScroll(target)
			self:SetScript("OnUpdate", nil)
		else
			self:SetVerticalScroll(math.floor(current + step + 0.5))
		end
		PaintThumb()
	end)
end

scroll:SetScript("OnMouseWheel", function(_, delta)
	ScrollTo(target - delta * 70)
end)

-- Navigation and pages.
local navRows = {}
local tabButtons = {}
local built = {}
local activePage, activeTab

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

local function Build(info, tab)
	local id = info.key .. ":" .. (tab and tab.key or "")
	if built[id] then return built[id] end
	local page = CreateFrame("Frame", nil, scroll)
	page:SetWidth(CONTENT_W - 10)
	page:Hide()
	local col = W.Begin(page, CONTENT_W - 10, info.key, tab and tab.key)
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
			row.glow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.18), CreateColor(r, g, b, 0))
		end
		local c = on and UI.C.text or UI.C.dim
		row.text:SetTextColor(c[1], c[2], c[3])
	end
	profileText:SetText("Profile: " .. (Soul.db and Soul.db.activeProfile or "?"))
end

local function PaintTabs(info)
	for i = 1, #tabButtons do tabButtons[i]:Hide() end
	if not info.tabs or #info.tabs < 2 then
		tabBar:SetHeight(1)
		return
	end
	tabBar:SetHeight(TABS)
	local x = 22
	local r, g, b = Soul:Accent()
	for i = 1, #info.tabs do
		local tab = info.tabs[i]
		local button = tabButtons[i]
		if not button then
			button = CreateFrame("Button", nil, tabBar)
			button:SetHeight(TABS)
			button.text = UI.Text(button, 14, UI.C.dim, "CENTER")
			button.text:SetPoint("CENTER", 0, 1)
			button.line = button:CreateTexture(nil, "OVERLAY")
			button.line:SetPoint("BOTTOMLEFT", 6, 0)
			button.line:SetPoint("BOTTOMRIGHT", -6, 0)
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
		local width = (button.text:GetStringWidth() or 60) + 28
		button:SetWidth(width)
		button:ClearAllPoints()
		button:SetPoint("BOTTOMLEFT", x, 0)
		x = x + width + 2
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

local current

function Soul.Options.Show(pageKey, tabKey)
	local info = PageInfo(pageKey) or Soul.optionPages[1]
	if not info then return end
	UI.CloseMenu()
	local tab = TabInfo(info, tabKey or (info.key == activePage and activeTab) or (info._lastTab))
	activePage = info.key
	activeTab = tab and tab.key
	info._lastTab = activeTab
	pageTitle:SetText(info.title)
	pageDesc:SetText(info.description or "")
	PaintNav()
	PaintTabs(info)
	if current then current.frame:Hide() end
	current = Build(info, tab)
	scroll:SetScrollChild(current.frame)
	current.frame:Show()
	W.Refresh(current.col)
	ScrollTo(0, true)
	if info.reset then
		resetButton:Show()
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

local function BuildNav()
	local y = -60
	local lastGroup
	for i = 1, #Soul.optionPages do
		local info = Soul.optionPages[i]
		if info.group ~= lastGroup then
			lastGroup = info.group
			y = y - 10
			local group = UI.Text(sidebar, 11, UI.C.faint)
			group:SetText(string.upper(info.group or ""))
			group:SetPoint("TOPLEFT", 18, y)
			UI.OnAccent(function(r, g, b) group:SetTextColor(r, g, b, 0.85) end)
			y = y - 22
		end
		local row = CreateFrame("Button", nil, sidebar)
		row:SetHeight(34)
		row:SetPoint("TOPLEFT", 0, y)
		row:SetPoint("TOPRIGHT", -1, y)
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
		row.text:SetPoint("LEFT", 22, 0)
		row.text:SetText(info.title)
		row:SetScript("OnEnter", function(self) self.hover:Show() end)
		row:SetScript("OnLeave", function(self) self.hover:Hide() end)
		row:SetScript("OnClick", function() Soul.Options.Show(info.key) end)
		navRows[info.key] = row
		y = y - 34
	end
end

-- Search: matches row labels on every page (pages are built on first search).
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

local function RunSearch()
	local text = (search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	searchHint:SetShown(text == "")
	if #text < 2 then UI.CloseMenu() return end
	BuildAll()
	local items, seen = {}, {}
	for i = 1, #W.searchIndex do
		local entry = W.searchIndex[i]
		if entry.lower:find(text, 1, true) then
			local id = entry.label .. "|" .. (entry.page or "") .. "|" .. (entry.tab or "")
			if not seen[id] then
				seen[id] = true
				items[#items + 1] = {
					value = i,
					label = entry.label .. "  |cff8a8a96" .. TitleOf(entry.page, entry.tab) .. "|r",
				}
			end
		end
		if #items >= 40 then break end
	end
	if #items == 0 then
		items[1] = { value = 0, label = "|cff8a8a96No matches|r" }
	end
	UI.CloseMenu()
	UI.OpenMenu(search, items, nil, function(value)
		local entry = W.searchIndex[value]
		if not entry then return end
		local shown = Soul.Options.Show(entry.page, entry.tab)
		if shown and entry.row then
			C_Timer.After(0, function()
				local top = shown.frame:GetTop()
				local rowTop = entry.row:GetTop()
				if top and rowTop then ScrollTo(top - rowTop - 60, true) end
				W.Flash(entry.row)
			end)
		end
	end, 380)
end

search:SetScript("OnTextChanged", function(_, userInput)
	if userInput then RunSearch() end
	searchHint:SetShown((search:GetText() or "") == "")
end)
search:SetScript("OnEscapePressed", function(self)
	self:SetText("")
	self:ClearFocus()
	UI.CloseMenu()
end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEditFocusGained", function()
	local r, g, b = Soul:Accent()
	searchEdge:SetColor(r, g, b, 0.8)
end)
search:SetScript("OnEditFocusLost", function() searchEdge:SetColor(1, 1, 1, 0.12) end)

-- Open / close.
local navBuilt = false

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
	panel:RestorePosition("CENTER", 0, 30)
	panel:SetAlpha(1)
	panel:Show()
	Soul.Options.Show(pageKey or activePage or (Soul.optionPages[1] and Soul.optionPages[1].key))
end

function Soul.Options.Close()
	UI.CloseMenu()
	search:ClearFocus()
	panel:Hide()
end

function Soul.Options.Toggle()
	if panel:IsShown() then Soul.Options.Close() else Soul.Options.Open(nil) end
end

function Soul.Options.Refresh()
	if current then W.Refresh(current.col) end
	PaintNav()
	if panel:IsShown() then
		local info = PageInfo(activePage)
		if info then PaintTabs(info) end
	end
end

-- Rebuilds every cached page (after a profile switch, so lists repaint).
function Soul.Options.Invalidate()
	for _, page in pairs(built) do page.frame:Hide() end
	built = {}
	W.searchIndex = {}
	current = nil
	if panel:IsShown() and activePage then Soul.Options.Show(activePage, activeTab) end
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
