if SoulUI_Blocked or not SoulUI then return end

-- Settings window (/soul), 0.7.2. 1 unit = 1 pixel (times the window scale).
-- Deep navy shell. The accent color is the mark, the group labels, the
-- selected-page bar, the streak under the title, and the controls.
--
--   +-------------------+------------------------------------------------------+
--   | o SoulUI          |  Page title                                          [x] |
--   |  o Edit Mode      |  description                          ~~~~streak~~~~ |
--   |  General          |  Tab   Tab   Tab                        [search page] |
--   |  Profiles         |------------------------------------------------------|
--   | [search        ]  |  live preview (optional)                             |
--   | Frames            |  SECTION                                             |
--   |  Unit Frames    o |  label          control  |  label           control  |
--   | Combat            |                                                      |
--   |  ...              |------------------------------------------------------|
--   | Default      v#   |  [Reset] [Reload UI]      Scale --o--     [Close]    |
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

local WIDTH, HEIGHT = 1280, 840
local SIDEBAR = 280
local HEADER = 104
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TABS = 44
local FOOTER = 64
local CONTENT_W = WIDTH - SIDEBAR
local GUTTER = 48 -- content inset, matches Widgets PAD

local panel = CreateFrame("Frame", "SoulUI_OptionsFrame", UIParent)
panel:SetSize(WIDTH, HEIGHT)
panel:SetFrameStrata("DIALOG")
panel:SetToplevel(true)
panel:SetClampedToScreen(true)
panel:SetClampRectInsets(WIDTH - 120, -(WIDTH - 120), 0, HEIGHT - 60)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:Hide()

local function Hairline(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetColorTexture(UI.C.line[1], UI.C.line[2], UI.C.line[3], UI.C.line[4])
	return t
end

-- Surfaces: navy content, a darker sidebar, a 1px frame.
UI.Fill(panel, UI.C.panel, "BACKGROUND", -7)
-- Soft drop shadow: a bundled 64px black falloff, 9-sliced so the corners
-- stay round at any window size. It hangs outside the frame, lower and wider.
local shadow = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
shadow:SetTexture(UI.TEX .. "Shadow.tga")
if shadow.SetTextureSliceMargins then
	pcall(shadow.SetTextureSliceMargins, shadow, 24, 24, 24, 24)
	if shadow.SetTextureSliceMode then pcall(shadow.SetTextureSliceMode, shadow, 0) end
end
shadow:SetPoint("TOPLEFT", -22, 14)
shadow:SetPoint("BOTTOMRIGHT", 22, -30)
local rim = CreateFrame("Frame", nil, panel)
rim:SetAllPoints()
rim:SetFrameLevel(panel:GetFrameLevel() + 20)
rim:EnableMouse(false)
UI.Edge(rim, 1, 1, 1, 0.1, "OVERLAY")

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

-- Search box: dark field, hairline, placeholder. No stock magnifier icon.
local function SearchBox(parent, width, height, placeholder, size)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, height)
	box:SetAutoFocus(false)
	box:SetTextInsets(12, 10, 0, 0)
	UI.SetFont(box, size or 13)
	box:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
	UI.Fill(box, { 0, 0, 0, 0.45 })
	box.edge = UI.Edge(box, 1, 1, 1, 0.1)
	box.hint = UI.Text(box, size or 13, UI.C.faint)
	box.hint:SetPoint("LEFT", 12, 0)
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

-- A filled disc. The client mask makes it round; without the mask it stays a tile.
local function Disc(parent, size, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetSize(size, size)
	-- Bundled antialiased disc (0.8.0); tint with SetVertexColor.
	tex:SetTexture(UI.TEX .. "Circle.tga")
	return tex
end

-- Ring with a stem, used as the module status mark. Not a button.
local function PowerMark(parent)
	local host = CreateFrame("Frame", nil, parent)
	host:SetSize(15, 15)
	host:EnableMouse(false)
	local ring = Disc(host, 15, "ARTWORK")
	ring:SetPoint("CENTER")
	local hole = Disc(host, 9, "OVERLAY")
	hole:SetPoint("CENTER")
	hole:SetVertexColor(UI.C.sidebar[1], UI.C.sidebar[2], UI.C.sidebar[3], 1)
	local stem = host:CreateTexture(nil, "OVERLAY", nil, 2)
	stem:SetSize(2, 6)
	stem:SetPoint("TOP", host, "TOP", 0, 1)
	function host:SetColor(r, g, b, a)
		ring:SetVertexColor(r, g, b, a or 1)
		stem:SetColorTexture(r, g, b, a or 1)
	end
	return host
end

-- Brand: an accent disc and the name.
local brand = CreateFrame("Frame", nil, sidebar)
brand:SetPoint("TOPLEFT")
brand:SetPoint("TOPRIGHT")
brand:SetHeight(88)
Mover(brand)
local markGlow = brand:CreateTexture(nil, "BACKGROUND", nil, 1)
markGlow:SetTexture(UI.TEX .. "Glow.tga")
markGlow:SetBlendMode("ADD")
markGlow:SetSize(84, 84)
local mark = Disc(brand, 26, "ARTWORK")
mark:SetPoint("LEFT", 26, 0)
markGlow:SetPoint("CENTER", mark, "CENTER")
local markRing = brand:CreateTexture(nil, "ARTWORK", nil, 1)
markRing:SetTexture(UI.TEX .. "Ring.tga")
markRing:SetSize(36, 36)
markRing:SetPoint("CENTER", mark, "CENTER")
local markCore = Disc(brand, 9, "OVERLAY")
markCore:SetPoint("CENTER", mark, "CENTER")
markCore:SetVertexColor(1, 1, 1, 0.9)
UI.OnAccent(function(r, g, b)
	mark:SetVertexColor(r, g, b, 1)
	markRing:SetVertexColor(r, g, b, 0.35)
	markGlow:SetVertexColor(r, g, b, 0.35)
end)
-- A slow breathing glow on the mark: the one ambient motion in the window.
local breathe = markGlow:CreateAnimationGroup()
breathe:SetLooping("BOUNCE")
local breatheAlpha = breathe:CreateAnimation("Alpha")
breatheAlpha:SetFromAlpha(1)
breatheAlpha:SetToAlpha(0.45)
breatheAlpha:SetDuration(2.4)
breatheAlpha:SetSmoothing("IN_OUT")
local brandName = UI.Text(brand, 24, UI.C.text)
brandName:SetPoint("LEFT", mark, "RIGHT", 16, 0)
brandName:SetText("SoulUI")

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
local profileName = UI.Text(profileRow, 14, UI.C.text)
profileName:SetPoint("LEFT", 26, 8)
profileName:SetPoint("RIGHT", -16, 8)
local versionText = UI.Text(profileRow, 12, UI.C.faint, "LEFT")
versionText:SetPoint("BOTTOMLEFT", 26, 14)
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
local headerGlow = header:CreateTexture(nil, "BACKGROUND", nil, -6)
headerGlow:SetTexture(UI.TEX .. "Glow.tga")
headerGlow:SetBlendMode("ADD")
headerGlow:SetSize(620, 240)
headerGlow:SetPoint("CENTER", header, "TOPLEFT", GUTTER + 160, -6)
UI.OnAccent(function(r, g, b) headerGlow:SetVertexColor(r, g, b, 0.13) end)
local pageTitle = UI.Text(header, 30, UI.C.text)
pageTitle:SetPoint("TOPLEFT", GUTTER, -26)
local pageDesc = UI.Text(header, 14, UI.C.dim)
pageDesc:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -4)
pageDesc:SetPoint("RIGHT", -64, 0)

local close = UI.IconButton(header, "close", 30, function() Soul.Options.Close() end)
close:SetPoint("TOPRIGHT", -18, -18)

local tabBar = CreateFrame("Frame", nil, content)
tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
tabBar:SetHeight(TABS)
-- Accent streak along the top of the tab row, bright in the middle.
local flareL = tabBar:CreateTexture(nil, "BACKGROUND", nil, -1)
flareL:SetTexture(WHITE)
flareL:SetHeight(3)
flareL:SetPoint("TOPLEFT", 12, 0)
flareL:SetPoint("TOP", tabBar, "TOP", 0, 0)
local flareR = tabBar:CreateTexture(nil, "BACKGROUND", nil, -1)
flareR:SetTexture(WHITE)
flareR:SetHeight(3)
flareR:SetPoint("TOP", tabBar, "TOP", 0, 0)
flareR:SetPoint("TOPRIGHT", -12, 0)
local bloom = tabBar:CreateTexture(nil, "BACKGROUND", nil, -2)
bloom:SetTexture(WHITE)
bloom:SetPoint("TOPLEFT", 28, 8)
bloom:SetPoint("TOPRIGHT", -28, 8)
bloom:SetHeight(64)
UI.OnAccent(function(r, g, b)
	if flareL.SetGradient and CreateColor then
		flareL:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.95))
		flareR:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.95), CreateColor(r, g, b, 0))
		bloom:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.18))
	else
		flareL:SetVertexColor(r, g, b, 0.7)
		flareR:SetVertexColor(r, g, b, 0.7)
		bloom:SetVertexColor(r, g, b, 0.08)
	end
end)

-- The page search lives in the header, so pages without tabs need no tab band.
local pageSearch = SearchBox(header, 220, 32, "Search this page", 13)
pageSearch:SetPoint("RIGHT", close, "LEFT", -14, 0)
pageDesc:SetPoint("RIGHT", pageSearch, "LEFT", -24, 0)
for _, decoration in ipairs({ flareL, flareR, bloom }) do decoration:Hide() end
local tabRule = Hairline(tabBar)
tabRule:SetPoint("BOTTOMLEFT", GUTTER - 12, 0)
tabRule:SetPoint("BOTTOMRIGHT", -GUTTER + 12, 0)
tabRule:SetHeight(1)
-- One underline that slides to the active tab.
local tabLine = tabBar:CreateTexture(nil, "OVERLAY")
tabLine:SetHeight(2)
tabLine:SetPoint("BOTTOMLEFT", GUTTER, 0)
tabLine:SetWidth(40)
tabLine:Hide()
UI.OnAccent(function(r, g, b) tabLine:SetColorTexture(r, g, b, 1) end)
local tabLineX, tabLineW = GUTTER, 40

local footer = CreateFrame("Frame", nil, content)
footer:SetPoint("BOTTOMLEFT")
footer:SetPoint("BOTTOMRIGHT")
footer:SetHeight(FOOTER)
local footRule = Hairline(footer)
footRule:SetPoint("TOPLEFT")
footRule:SetPoint("TOPRIGHT")
footRule:SetHeight(1)

local closeButton = UI.Button(footer, "Close", 132, 34, function() Soul.Options.Close() end, "accent")
closeButton:SetPoint("RIGHT", -GUTTER + 8, 0)
local reloadButton = UI.Button(footer, "Reload UI", 132, 34, function() ReloadUI() end, "well")
reloadButton:SetPoint("LEFT", GUTTER - 8, 0)
local resetButton = UI.Button(footer, "Reset page", 180, 34, function() end, "ghost")
resetButton:SetPoint("LEFT", reloadButton, "RIGHT", 10, 0)

-- Window scale sits in the footer so the page title has the header to itself.
-- The scale is applied when the mouse is released, not while dragging.
local function PanelScaleSetting() return Soul.db and Soul.db.account.panelScale or 1 end
local scaleValue = UI.Text(footer, 12, UI.C.dim, "LEFT")
scaleValue:SetWidth(40)
local scaleSlider = UI.Slider(footer, 96, 0.6, 1.6, 0.05, PanelScaleSetting, function(v)
	Soul.db.account.panelScale = v
	scaleValue:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
end)
scaleSlider:HookScript("OnMouseUp", function() panel:SetScale(UI.PanelScale()) end)
scaleSlider:HookScript("OnMouseWheel", function() panel:SetScale(UI.PanelScale()) end)
local scaleLabel = UI.Text(footer, 12, UI.C.faint, "RIGHT")
scaleLabel:SetText("Scale")
scaleSlider:SetPoint("CENTER", footer, "CENTER", 8, 0)
scaleLabel:SetPoint("RIGHT", scaleSlider, "LEFT", -10, 0)
scaleValue:SetPoint("LEFT", scaleSlider, "RIGHT", 10, 0)

local previewHolder = CreateFrame("Frame", nil, content)
previewHolder:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
previewHolder:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
previewHolder:SetHeight(1)
previewHolder:SetClipsChildren(true)
local previewBg = previewHolder:CreateTexture(nil, "BACKGROUND")
previewBg:SetAllPoints()
previewBg:SetColorTexture(1, 1, 1, 0.025)
local previewRule = Hairline(previewHolder)
previewRule:SetPoint("BOTTOMLEFT")
previewRule:SetPoint("BOTTOMRIGHT")
previewRule:SetHeight(1)
local previewLabel = UI.Text(previewHolder, 11, UI.C.faint)
previewLabel:SetPoint("TOPLEFT", GUTTER - 18, -10)
previewLabel:SetText("Preview")

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
	thumb:SetColorTexture(1, 1, 1, 0.28)
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

-- One selection indicator (accent bar + fading wash) that slides between rows.
local indicator = CreateFrame("Frame", nil, nav)
indicator:SetHeight(40)
indicator:SetPoint("TOPLEFT", 0, 0)
indicator:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
indicator:EnableMouse(false)
indicator:Hide()
local indicatorBar = indicator:CreateTexture(nil, "ARTWORK")
indicatorBar:SetPoint("TOPLEFT")
indicatorBar:SetPoint("BOTTOMLEFT")
indicatorBar:SetWidth(3)
local indicatorWash = indicator:CreateTexture(nil, "BACKGROUND")
indicatorWash:SetAllPoints()
indicatorWash:SetTexture(WHITE)
UI.OnAccent(function(r, g, b)
	indicatorBar:SetColorTexture(r, g, b, 1)
	if indicatorWash.SetGradient and CreateColor then
		indicatorWash:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.2), CreateColor(r, g, b, 0))
	else
		indicatorWash:SetVertexColor(r, g, b, 0.1)
	end
end)
local indicatorY

local function MoveIndicator(row)
	if not row or not row._y then
		indicator:Hide()
		return
	end
	local to = row._y
	if not indicator:IsShown() or not indicatorY then
		indicatorY = to
		indicator:SetPoint("TOPLEFT", 0, to)
		indicator:Show()
		return
	end
	local from = indicatorY
	indicatorY = to
	UI.Animate("nav-indicator", 0.22, function(p)
		indicator:SetPoint("TOPLEFT", 0, UI.Lerp(from, to, p))
	end)
end

local function PaintNav()
	local r, g, b = Soul:Accent()
	MoveIndicator(navRows[activePage])
	for key, row in pairs(navRows) do
		if row.info then
			local on = key == activePage
			row.bar:Hide()
			row.wash:Hide()
			if row.icon then
				local ic = on and UI.C.text or UI.C.dim
				if on then row.icon:SetColor(r, g, b, 1) else row.icon:SetColor(ic[1], ic[2], ic[3], 0.8) end
			end
			local off = row.power and AddonOn(row.info.addon) == false
			local c = on and UI.C.text or UI.C.dim
			if off then c = UI.C.faint end
			row.text:SetTextColor(c[1], c[2], c[3])
			if row.power then
				if off then
					row.power:SetColor(1, 1, 1, 0.22)
				else
					row.power:SetColor(r, g, b, on and 1 or 0.72)
				end
			end
		end
	end
	profileName:SetText(Soul.db and Soul.db.activeProfile or "?")
end

local function SlideTabLine(button)
	local x = button._x or GUTTER
	local w = button:GetWidth()
	if not tabLine:IsShown() then
		tabLineX, tabLineW = x, w
		tabLine:SetPoint("BOTTOMLEFT", x, 0)
		tabLine:SetWidth(w)
		tabLine:Show()
		return
	end
	local fx, fw = tabLineX, tabLineW
	tabLineX, tabLineW = x, w
	UI.Animate("tab-line", 0.2, function(p)
		tabLine:SetPoint("BOTTOMLEFT", UI.Lerp(fx, x, p), 0)
		tabLine:SetWidth(math.max(1, UI.Lerp(fw, w, p)))
	end)
end

local function PaintTabs(info)
	for i = 1, #tabButtons do tabButtons[i]:Hide() end
	if not info.tabs or #info.tabs < 2 then
		-- No tabs: collapse the band so the page starts under the header.
		tabBar:SetHeight(1)
		tabLine:Hide()
		tabRule:Hide()
		return
	end
	tabBar:SetHeight(TABS)
	tabRule:Show()
	local x = GUTTER
	local r, g, b = Soul:Accent()
	for i = 1, #info.tabs do
		local tab = info.tabs[i]
		local button = tabButtons[i]
		if not button then
			button = CreateFrame("Button", nil, tabBar)
			button:SetHeight(TABS)
			button.text = UI.Text(button, 14, UI.C.dim, "CENTER")
			button.text:SetPoint("CENTER", 0, 2)
			button.line = button:CreateTexture(nil, "OVERLAY")
			button.line:SetPoint("BOTTOMLEFT", 0, 0)
			button.line:SetPoint("BOTTOMRIGHT", 0, 0)
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
		button._x = x
		x = x + width + 30
		button.on = tab.key == activeTab
		button.line:Hide()
		if button.on then SlideTabLine(button) end
		if button.on then
			button.text:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
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
		preview.frame:ClearAllPoints()
		preview.frame:SetPoint("TOPLEFT", 0, -22)
		preview.frame:SetPoint("TOPRIGHT", 0, -22)
		preview.frame:SetHeight(preview.height)
		previewHolder:SetHeight(preview.height + 44)
		preview.frame:Show()
	else
		previewHolder:SetHeight(1)
	end
	previewLabel:Hide()
	previewBg:SetShown(preview ~= nil)
	previewRule:SetShown(preview ~= nil)
	current = Build(info, tab)
	current.col.onRefresh = preview and preview.update or nil
	scroll:SetScrollChild(current.frame)
	current.frame:Show()
	if not panel._soulOpening then
		-- New page content rises 12px into place while fading in.
		local frame = current.frame
		frame:SetAlpha(0)
		UI.Animate("page", 0.24, function(p)
			frame:SetAlpha(p)
			scroll:SetPoint("TOPLEFT", previewHolder, "BOTTOMLEFT", 0, -12 * (1 - p))
		end)
	end
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

local NAV_ROW = 40
local NAV_ICONS = {
	general = "sliders",
	profiles = "user",
	unitframes = "frame",
	nameplates = "plate",
	groupframes = "group",
	actionbars = "grid",
	resources = "pips",
	meters = "bars",
}

local function NavRow(info, y)
	local row = CreateFrame("Button", nil, nav)
	row:SetHeight(NAV_ROW)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row.info = info
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetAllPoints()
	row.wash:SetTexture(WHITE)
	row.wash:Hide()
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.04)
	row.hover:Hide()
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(3)
	row._y = y
	local glyph = NAV_ICONS[info.key]
	if glyph then
		row.icon = UI.Glyph(row, glyph, 16, UI.C.dim, 1.4)
		row.icon:SetPoint("LEFT", 26, 0)
	end
	row.text = UI.Text(row, 14, UI.C.dim)
	row.text:SetPoint("LEFT", glyph and 54 or 28, 0)
	row.text:SetPoint("RIGHT", -36, 0)
	row.text:SetText(info.title)
	if info.addon then
		row.power = PowerMark(row)
		row.power:SetPoint("RIGHT", -20, 0)
		UI.Tip(row, info.title, function()
			if AddonOn(info.addon) == false then return "Turned off. Turn it on under General > Modules." end
			return info.description
		end)
	end
	local hoverKey = "nav-hover:" .. info.key
	row.hover:SetAlpha(0)
	row.hover:Show()
	row:HookScript("OnEnter", function(self)
		local from = self.hover:GetAlpha()
		UI.Animate(hoverKey, 0.12, function(p) self.hover:SetAlpha(UI.Lerp(from, 1, p)) end)
	end)
	row:HookScript("OnLeave", function(self)
		local from = self.hover:GetAlpha()
		UI.Animate(hoverKey, 0.18, function(p) self.hover:SetAlpha(UI.Lerp(from, 0, p)) end)
	end)
	row:SetScript("OnClick", function() Soul.Options.Show(info.key) end)
	navRows[info.key] = row
	return row
end

-- Pinned at the top, the way Unlock sits above the module list.
local function ActionRow(y)
	local row = CreateFrame("Button", nil, nav)
	row:SetHeight(NAV_ROW)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	local hover = row:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.04)
	hover:Hide()
	local icon = UI.Glyph(row, "move", 16, UI.C.dim, 1.4)
	icon:SetPoint("LEFT", 26, 0)
	UI.OnAccent(function(r, g, b) icon:SetColor(r, g, b, 1) end)
	local text = UI.Text(row, 14, UI.C.dim)
	text:SetPoint("LEFT", 54, 0)
	text:SetText("Edit Mode")
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

local search = SearchBox(nav, SIDEBAR - 48, 34, "Search settings", 14)

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
					search:SetPoint("TOPLEFT", 24, y)
					y = y - 34 - 16
				end
				y = y - 14
				local group = UI.Text(nav, 13, UI.C.text)
				group:SetText(info.group or "")
				group:SetPoint("TOPLEFT", 28, y - 2)
				UI.OnAccent(function(r, g, b) group:SetTextColor(r, g, b, 1) end)
				y = y - 24
			end
		end
		NavRow(info, y)
		y = y - NAV_ROW
	end
	if not searchPlaced then
		search:SetPoint("TOPLEFT", 24, y - 16)
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
		self.edge:SetColor(r, g, b, 0.7)
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
	panel._soulOpening = true
	panel:Show()
	Soul.Options.Show(pageKey or activePage or (Soul.optionPages[1] and Soul.optionPages[1].key))
	panel._soulOpening = nil
	-- Open: fade in while growing from 97% about the window's anchor. This
	-- replaces any close tween still running, so clear its closing flag.
	panel._soulClosing = nil
	local base = UI.PanelScale()
	panel:SetAlpha(0)
	UI.Animate("window", 0.22, function(p)
		panel:SetAlpha(p)
		panel:SetScale(base * (0.97 + 0.03 * p))
	end)
	breathe:Play()
end

function Soul.Options.Close()
	if panel._soulClosing then return end
	UI.CloseMenu()
	search:ClearFocus()
	pageSearch:ClearFocus()
	panel._soulClosing = true
	local base = UI.PanelScale()
	local from = panel:GetAlpha() or 1
	UI.Animate("window", 0.14, function(p)
		panel:SetAlpha(from * (1 - p))
		panel:SetScale(base * (1 - 0.02 * p))
	end, function()
		panel._soulClosing = nil
		panel:Hide()
		panel:SetAlpha(1)
		panel:SetScale(base)
		breathe:Stop()
	end)
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
