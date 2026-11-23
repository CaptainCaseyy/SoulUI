if SoulUI_Blocked or not SoulUI then return end

-- SoulUI Bags (0.9.0). One combined bag window: a header with the title,
-- search, sort and the bag bar toggle; sections of items (categories by
-- Enum.ItemClass, which is locale safe); a footer with free slots, tracked
-- currencies and gold. Bank.lua adds the bank and warband bank window and
-- reuses the pieces here (BG.NewWindow, BG.NewView, BG.Read*, BG.Pack).
--
-- Rules this file keeps:
--  * Item slots are ContainerFrameItemButtonTemplate buttons, so use, equip,
--    drag and the tooltip are Blizzard's own secure code. Each button is bound
--    to one bag and slot for life (holder frame ID = bag, button ID = slot), so
--    an update only repaints; layout only moves buttons.
--  * Buttons are only created out of combat (a button born in combat is
--    tainted). If the client ever marks them protected, layout waits for the
--    end of combat; repaints never wait.
--  * Nothing is written onto Blizzard template frames. Our per-slot data lives
--    in a side table (recOf / rec records), created once per slot.
--  * Updates are batched: BAG_UPDATE marks bags dirty, BAG_UPDATE_DELAYED (and
--    the other events) schedule one refresh, which only reads dirty bags.
--    Nothing is read while the window is closed.
--  * Blizzard's bag frames are parked under a hidden parent (never Hide()), and
--    put back when the module is turned off.

local Soul = SoulUI
local UI = Soul.UI
local BG = Soul:NewModule("Bags", "SoulUI_Bags")

local C_Container, C_Item, C_NewItems = C_Container, C_Item, C_NewItems
local CreateFrame, InCombatLockdown, GetTime = CreateFrame, InCombatLockdown, GetTime
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local pairs, type, pcall = pairs, type, pcall
local issecret = issecretvalue or function() return false end

local function DB() return Soul:ModuleDB("Bags") end
BG.DB = DB

local BACKPACK = Enum and Enum.BagIndex and Enum.BagIndex.Backpack or 0
local REAGENT = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
BG.REAGENT = REAGENT

local HEADER = 46
local FOOTER = 34
local BAGBAR = 46
local MIN_WIDTH = 420
BG.HEADER, BG.FOOTER, BG.MIN_WIDTH, BG.BAGBAR = HEADER, FOOTER, MIN_WIDTH, BAGBAR

------------------------------------------------------------------------------
-- Colors
------------------------------------------------------------------------------

local QCOLOR = {}
for q = 0, 8 do
	local r, g, b
	if C_Item and C_Item.GetItemQualityColor then
		local ok, cr, cg, cb = pcall(C_Item.GetItemQualityColor, q)
		if ok then r, g, b = cr, cg, cb end
	end
	if not r and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
		r, g, b = ITEM_QUALITY_COLORS[q].r, ITEM_QUALITY_COLORS[q].g, ITEM_QUALITY_COLORS[q].b
	end
	QCOLOR[q] = { r or 1, g or 1, b or 1 }
end
BG.QCOLOR = QCOLOR
local QUEST_COLOR = { 1, 0.82, 0.2 }
local NEUTRAL_EDGE = { 1, 1, 1, 0.07 }

------------------------------------------------------------------------------
-- Categories. Enum.ItemClass ids: 0 consumable, 1 container, 2 weapon, 3 gem,
-- 4 armor, 5 reagent, 7 trade goods, 8 item enhancement, 9 recipe, 12 quest,
-- 15 miscellaneous, 16 glyph, 17 battle pet, 19 profession gear.
------------------------------------------------------------------------------

BG.CATEGORIES = {
	{ key = "pin", label = "Pinned", tip = "Alt-click a slot to pin that item. Pinned items stay in their own section." },
	{ key = "new", label = "New", tip = "Items you picked up since the bags were last closed." },
	{ key = "equipment", label = "Equipment", tip = "Weapons, armor and profession gear." },
	{ key = "consumable", label = "Consumables", tip = "Potions, flasks, food and other usable items." },
	{ key = "quest", label = "Quest", tip = "Quest items, and items that start a quest." },
	{ key = "reagent", label = "Reagents", tip = "Trade goods and crafting reagents." },
	{ key = "gem", label = "Gems & Enhancements", short = "Gems & Enchants", tip = "Gems, enchants, armor kits and other item enhancements." },
	{ key = "recipe", label = "Recipes", tip = "Recipes, patterns and books." },
	{ key = "misc", label = "Miscellaneous", tip = "Bags, mounts, pets, toys, glyphs and anything else." },
	{ key = "other", label = "Items" },
	{ key = "junk", label = "Junk", tip = "Poor quality items that sell to a vendor." },
	{ key = "free", label = "Free" },
}

local CLASS_CAT = {
	[0] = "consumable", [1] = "misc", [2] = "equipment", [3] = "gem", [4] = "equipment",
	[5] = "reagent", [7] = "reagent", [8] = "gem", [9] = "recipe", [12] = "quest",
	[15] = "misc", [16] = "misc", [17] = "misc", [19] = "equipment",
}
local GEAR = { [2] = true, [4] = true, [19] = true }

local function Classify(rec, cats)
	if rec.junk and cats.junk then return "junk" end
	if rec.new and cats.new then return "new" end
	if rec.quest and cats.quest then return "quest" end
	local key = rec.classID and CLASS_CAT[rec.classID]
	if key and cats[key] then return key end
	return "other"
end

------------------------------------------------------------------------------
-- Small drawn glyphs that UIKit does not have (bag). Same stroke as UI.Glyph.
------------------------------------------------------------------------------

local BAG_GLYPH = {
	{ -0.34, 0.14, 0.34, 0.14 }, { 0.34, 0.14, 0.28, -0.38 }, { 0.28, -0.38, -0.28, -0.38 },
	{ -0.28, -0.38, -0.34, 0.14 }, { -0.16, 0.14, -0.12, 0.36 }, { -0.12, 0.36, 0.12, 0.36 },
	{ 0.12, 0.36, 0.16, 0.14 },
}

local function Lines(parent, size, segs, color)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	frame:EnableMouse(false)
	local lines = {}
	for i = 1, #segs do
		local s = segs[i]
		local line = frame:CreateLine(nil, "OVERLAY")
		line:SetThickness(1.5)
		line:SetStartPoint("CENTER", frame, s[1] * size, s[2] * size)
		line:SetEndPoint("CENTER", frame, s[3] * size, s[4] * size)
		lines[i] = line
	end
	function frame:SetColor(r, g, b, a)
		for i = 1, #lines do lines[i]:SetColorTexture(r, g, b, a or 1) end
	end
	frame:SetColor(color[1], color[2], color[3], 1)
	return frame
end

-- Square hairline icon button. glyph is a UI.Glyph kind or a segment table.
-- isOn() (optional) paints the button as a lit toggle.
function BG.GlyphButton(parent, size, glyph, title, body, onClick, isOn)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	local face = UI.Fill(button, { 1, 1, 1, 0 })
	local edge = UI.Edge(button, 1, 1, 1, 0.14)
	local mark
	if type(glyph) == "table" then
		mark = Lines(button, floor(size * 0.56), glyph, UI.C.dim)
	else
		mark = UI.Glyph(button, glyph, floor(size * 0.5), UI.C.dim, 1.5)
	end
	mark:SetPoint("CENTER")
	local hovered = false
	local function Paint()
		local r, g, b = Soul:Accent()
		local on = isOn and isOn()
		if on then
			face:SetColorTexture(r, g, b, hovered and 0.22 or 0.12)
			edge:SetColor(r, g, b, 0.8)
			mark:SetColor(r, g, b, 1)
		elseif hovered then
			face:SetColorTexture(1, 1, 1, 0.06)
			edge:SetColor(1, 1, 1, 0.3)
			mark:SetColor(1, 1, 1, 1)
		else
			face:SetColorTexture(1, 1, 1, 0)
			edge:SetColor(1, 1, 1, 0.14)
			mark:SetColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3], 1)
		end
	end
	button:SetScript("OnEnter", function() hovered = true Paint() end)
	button:SetScript("OnLeave", function() hovered = false Paint() end)
	button:SetScript("OnClick", function(self, mouse)
		if onClick then onClick(self, mouse) end
		Paint()
	end)
	if title then UI.Tip(button, title, body) end
	button.Paint = Paint
	UI.OnAccent(Paint)
	return button
end

------------------------------------------------------------------------------
-- Positions. The windows are SoulUI movers; dragging the header writes the
-- same profile position edit mode writes.
------------------------------------------------------------------------------

local function PointXY(frame, point)
	local left, bottom, width, height = frame:GetRect()
	if not left then return 0, 0 end
	local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	left, bottom, width, height = left * ratio, bottom * ratio, width * ratio, height * ratio
	local fx, fy = 0.5, 0.5
	if point:find("LEFT") then fx = 0 elseif point:find("RIGHT") then fx = 1 end
	if point:find("TOP") then fy = 1 elseif point:find("BOTTOM") then fy = 0 end
	return left + width * fx, bottom + height * fy
end

-- Places a window from its saved position, then re-anchors it by its top
-- edge (same spot on screen). The bag window changes height when you filter,
-- search or loot; anchored by the top, the header and search stay under the
-- cursor. The saved position is not rewritten.
function BG.PlaceTop(win, key, fallback)
	Soul:Place(win, key, fallback)
	if InCombatLockdown() and win:IsProtected() then return end
	local point, rel, relPoint, x, y = win:GetPoint(1)
	if not point or point:find("TOP") then return end
	local fy = point:find("BOTTOM") and 0 or 0.5
	local h = win:GetHeight() or 0
	local side = point:find("LEFT") and "LEFT" or (point:find("RIGHT") and "RIGHT" or "")
	win:ClearAllPoints()
	win:SetPoint("TOP" .. side, rel, relPoint, x or 0, (y or 0) + (1 - fy) * h)
end

function BG.SaveDrag(win, key, fallback)
	local saved = Soul:GetUnlockPosition(key)
	local point = saved and saved.point or fallback.point or "CENTER"
	local relPoint = saved and saved.relPoint or fallback.relPoint or point
	local fx, fy = PointXY(win, point)
	local rx, ry = PointXY(UIParent, relPoint)
	Soul:ActiveProfile().unlock.positions[key] = {
		point = point, relPoint = relPoint,
		x = Soul.Pixel:Scale(fx - rx), y = Soul.Pixel:Scale(fy - ry),
	}
	BG.PlaceTop(win, key, fallback)
end

-- Tallest the bag window may grow, in its own units: the setting, and never
-- more than 85% of the screen.
function BG.MaxHeight(win)
	local db = DB()
	local cap = type(db.maxHeight) == "number" and db.maxHeight or 560
	local ratio = win and (win:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 1
	if not ratio or ratio <= 0 then ratio = 1 end
	local screen = (UIParent:GetHeight() or 768) * 0.85 / ratio
	if cap > screen then cap = screen end
	if cap < 300 then cap = 300 end
	return cap
end

function BG.WindowScale()
	local db = DB()
	local s = type(db.scale) == "number" and db.scale or 1
	if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
	return UI.PanelScale() * s
end

------------------------------------------------------------------------------
-- Window chrome, shared with the bank. Matches the settings window: navy
-- surface, 1px rim, soft shadow, an accent glow behind the header, hairlines.
------------------------------------------------------------------------------

function BG.NewWindow(name, titleText, key, fallback)
	local win = CreateFrame("Frame", name, UIParent)
	win:SetFrameStrata("MEDIUM")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	if win.SetDontSavePosition then win:SetDontSavePosition(true) end
	win:SetSize(MIN_WIDTH, 300)
	win:Hide()

	-- Everything visible lives on body, so the open motion can slide it
	-- without moving the anchored window itself.
	local body = CreateFrame("Frame", nil, win)
	body:SetPoint("TOPLEFT")
	body:SetPoint("BOTTOMRIGHT")
	win.body = body

	local shadow = body:CreateTexture(nil, "BACKGROUND", nil, -8)
	shadow:SetTexture(UI.TEX .. "Shadow.tga")
	if shadow.SetTextureSliceMargins then
		pcall(shadow.SetTextureSliceMargins, shadow, 24, 24, 24, 24)
		if shadow.SetTextureSliceMode then pcall(shadow.SetTextureSliceMode, shadow, 0) end
	end
	shadow:SetPoint("TOPLEFT", -20, 12)
	shadow:SetPoint("BOTTOMRIGHT", 20, -26)
	win.bg = UI.Fill(body, UI.C.panel, "BACKGROUND", -7)

	local rim = CreateFrame("Frame", nil, body)
	rim:SetAllPoints()
	rim:SetFrameLevel(body:GetFrameLevel() + 30)
	rim:EnableMouse(false)
	UI.Edge(rim, 1, 1, 1, 0.1, "OVERLAY")

	local header = CreateFrame("Frame", nil, body)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	win.header = header
	local glow = header:CreateTexture(nil, "BACKGROUND", nil, -6)
	glow:SetTexture(UI.TEX .. "Glow.tga")
	glow:SetBlendMode("ADD")
	glow:SetSize(360, 140)
	glow:SetPoint("CENTER", header, "TOPLEFT", 90, -4)
	local rule = header:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1)
	rule:SetColorTexture(UI.C.line[1], UI.C.line[2], UI.C.line[3], UI.C.line[4])

	local mark = header:CreateTexture(nil, "ARTWORK")
	mark:SetTexture(UI.TEX .. "Circle.tga")
	mark:SetSize(9, 9)
	mark:SetPoint("LEFT", 16, 0)
	local title = UI.Text(header, 18, UI.C.text)
	title:SetPoint("LEFT", mark, "RIGHT", 9, 0)
	title:SetText(titleText or "")
	win.title = title
	UI.OnAccent(function(r, g, b)
		glow:SetVertexColor(r, g, b, 0.12)
		mark:SetVertexColor(r, g, b, 1)
	end)

	header:SetScript("OnDragStart", function()
		if Soul.unlocking then return end
		win:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		if win.SetUserPlaced then pcall(win.SetUserPlaced, win, false) end
		BG.SaveDrag(win, key, fallback())
	end)

	local close = UI.IconButton(header, "close", 26)
	close:SetPoint("RIGHT", -12, 0)
	win.close = close

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER)
	local band = footer:CreateTexture(nil, "BACKGROUND", nil, -5)
	band:SetAllPoints()
	band:SetColorTexture(0, 0, 0, 0.18)
	local frule = footer:CreateTexture(nil, "ARTWORK")
	frule:SetPoint("TOPLEFT")
	frule:SetPoint("TOPRIGHT")
	frule:SetHeight(1)
	frule:SetColorTexture(UI.C.line[1], UI.C.line[2], UI.C.line[3], UI.C.line[4])
	win.footer = footer

	-- Items sit in a scroll area, so a tall bag never grows the window past
	-- its height cap. The wheel scrolls it; a thin thumb on the right shows
	-- where you are.
	local scroll = CreateFrame("ScrollFrame", nil, body)
	scroll:SetSize(1, 1)
	scroll:EnableMouseWheel(true)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	win.scroll = scroll
	win.content = content
	local thumb = body:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(3)
	thumb:Hide()
	UI.OnAccent(function(r, g, b) thumb:SetColorTexture(r, g, b, 0.55) end)
	local function PaintThumb()
		local viewH = scroll:GetHeight() or 0
		local fullH = content:GetHeight() or 0
		if viewH <= 0 or fullH <= viewH + 0.5 then thumb:Hide() return end
		local range = fullH - viewH
		local h = max(18, viewH * viewH / fullH)
		local off = (scroll:GetVerticalScroll() or 0) / range * (viewH - h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 7, -off)
		thumb:SetHeight(h)
		thumb:Show()
	end
	-- value is clamped to the real range; the range is computed from the
	-- sizes we set, not GetVerticalScrollRange (that lags a frame).
	function win:SetScrollOffset(value)
		local range = max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
		if value > range then value = range end
		if value < 0 then value = 0 end
		scroll:SetVerticalScroll(value)
		PaintThumb()
	end
	scroll:SetScript("OnMouseWheel", function(_, delta)
		if not BG.CanLayout() then return end
		local step = ((DB().iconSize or 40) + (DB().spacing or 4)) * 2
		win:SetScrollOffset((scroll:GetVerticalScroll() or 0) - delta * step)
	end)

	-- Open: fade in while rising 8px. Close: fade out while sinking 4px.
	local animKey = "bags:" .. (name or "win")
	local function Slide(y)
		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", 0, y)
		body:SetPoint("BOTTOMRIGHT", 0, y)
	end
	function win:OpenAnimated()
		self._closing = nil
		self:SetAlpha(0)
		self:Show()
		local still = BG.protectedButtons and InCombatLockdown()
		UI.Animate(animKey, 0.2, function(p)
			self:SetAlpha(p)
			if not still then Slide(-8 * (1 - p)) end
		end)
	end
	function win:CloseAnimated()
		if not self:IsShown() or self._closing then return end
		self._closing = true
		local from = self:GetAlpha() or 1
		local still = BG.protectedButtons and InCombatLockdown()
		UI.Animate(animKey, 0.13, function(p)
			self:SetAlpha(from * (1 - p))
			if not still then Slide(-4 * p) end
		end, function()
			self._closing = nil
			self:Hide()
			self:SetAlpha(1)
			Slide(0)
		end)
	end
	win:HookScript("OnHide", function(self)
		UI.StopAnimation(animKey)
		self._closing = nil
		self:SetAlpha(1)
		Slide(0)
	end)

	function win:ApplyLook()
		local a = DB().bgAlpha
		if type(a) ~= "number" then a = 0.97 end
		self.bg:SetColorTexture(UI.C.panel[1], UI.C.panel[2], UI.C.panel[3], a)
	end
	win:ApplyLook()
	return win
end

-- Search field: dark well, hairline, magnifier glyph, placeholder.
function BG.SearchBox(parent, width, onChange)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, 28)
	box:SetAutoFocus(false)
	-- The header under the box is a drag handle. The box sits well above it
	-- and takes focus on any click, so typing always lands here.
	box:EnableMouse(true)
	box:EnableKeyboard(true)
	box:SetFrameLevel(parent:GetFrameLevel() + 10)
	box:SetHitRectInsets(0, 0, 0, 0)
	box:SetScript("OnMouseDown", function(self) self:SetFocus() end)
	box:SetTextInsets(28, 8, 0, 0)
	box:SetMaxLetters(60)
	UI.SetFont(box, 13)
	box:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
	UI.Fill(box, { 0, 0, 0, 0.42 })
	local edge = UI.Edge(box, 1, 1, 1, 0.1)
	local glyph = UI.Glyph(box, "search", 13, UI.C.faint, 1.3)
	glyph:SetPoint("LEFT", 9, 0)
	local hint = UI.Text(box, 13, UI.C.faint)
	hint:SetPoint("LEFT", 28, 0)
	hint:SetText("Search")
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		hint:SetShown(text == "")
		if onChange then onChange(text) end
	end)
	box:SetScript("OnEscapePressed", function(self)
		if (self:GetText() or "") ~= "" then self:SetText("") end
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function()
		local r, g, b = Soul:Accent()
		edge:SetColor(r, g, b, 0.8)
		glyph:SetColor(r, g, b, 1)
	end)
	box:SetScript("OnEditFocusLost", function()
		edge:SetColor(1, 1, 1, 0.1)
		glyph:SetColor(UI.C.faint[1], UI.C.faint[2], UI.C.faint[3], 1)
	end)
	return box
end

------------------------------------------------------------------------------
-- Item slots
------------------------------------------------------------------------------

local recOf = setmetatable({}, { __mode = "k" })
BG.recOf = recOf

local function HideRegion(region)
	if region then
		region:SetAlpha(0)
		region:Hide()
	end
end

-- Styles the template once: flat icon, our own border, text overlay above
-- the cooldown swipe. Only methods are called on template regions.
local function BuildButton(rec, holder)
	local ok, btn = pcall(CreateFrame, "ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")
	if not ok or not btn then
		btn = CreateFrame("Button", nil, holder, "ContainerFrameItemButtonTemplate")
	end
	btn:SetID(rec.slot)
	btn:Hide()
	rec.btn = btn
	recOf[btn] = rec
	if BG.protectedButtons == nil then
		BG.protectedButtons = btn:IsProtected() and true or false
	end

	HideRegion(btn.NewItemTexture)
	HideRegion(btn.BattlepayItemTexture)
	HideRegion(btn.flash)
	if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end
	if btn.IconBorder then btn.IconBorder:SetAlpha(0) end
	-- The item-button template draws the old diamond chip on its own. Ours
	-- replaces it, so the template copy stays hidden.
	HideRegion(btn.ProfessionQualityOverlay)
	HideRegion(btn.IconOverlay)
	HideRegion(btn.IconOverlay2)
	local normal = btn.GetNormalTexture and btn:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	if btn.searchOverlay then btn.searchOverlay:SetAlpha(0) end
	if btn.ItemContextOverlay then btn.ItemContextOverlay:SetAlpha(0) end
	-- The 12.x template masks the icon to its stock size; a flat square icon
	-- needs the mask gone (same treatment as the action buttons).
	if btn.icon and btn.IconMask then
		pcall(btn.icon.RemoveMaskTexture, btn.icon, btn.IconMask)
		btn.IconMask:Hide()
	end
	local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
	if hl then
		hl:SetColorTexture(1, 1, 1, 0.12)
		hl:ClearAllPoints()
		hl:SetPoint("TOPLEFT", 1, -1)
		hl:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
	if pushed then
		pushed:SetColorTexture(1, 1, 1, 0.2)
		pushed:ClearAllPoints()
		pushed:SetPoint("TOPLEFT", 1, -1)
		pushed:SetPoint("BOTTOMRIGHT", -1, 1)
	end

	local well = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
	well:SetAllPoints()
	well:SetColorTexture(0, 0, 0, 0.42)
	rec.well = well

	local overlay = CreateFrame("Frame", nil, btn)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(btn:GetFrameLevel() + 4)
	overlay:EnableMouse(false)
	rec.overlay = overlay
	rec.edge = UI.Edge(overlay, NEUTRAL_EDGE[1], NEUTRAL_EDGE[2], NEUTRAL_EDGE[3], NEUTRAL_EDGE[4])
	local craft = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	craft:SetSize(22, 22)
	craft:SetPoint("TOPLEFT", -3, 3)
	craft:Hide()
	rec.craft = craft
	if btn.Count then btn.Count:SetParent(overlay) end
	if btn.IconQuestTexture then btn.IconQuestTexture:SetParent(overlay) end
	rec.ilvl = overlay:CreateFontString(nil, "OVERLAY")
	rec.bind = overlay:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(rec.ilvl, 12)
	Soul:ApplyFont(rec.bind, 10)

	btn:HookScript("OnEnter", function(self)
		local r = recOf[self]
		if r and r.has and r.new and C_NewItems and C_NewItems.RemoveNewItem then
			pcall(C_NewItems.RemoveNewItem, r.bag, r.slot)
			r.new = false
			if r.glow then r.glow.anim:Stop() r.glow:Hide() end
		end
		if r and BG.HoverItem then BG.HoverItem(r) end
	end)
	btn:HookScript("OnMouseUp", function(self, button)
		local r = recOf[self]
		if not r or not r.has then return end
		if button == "LeftButton" and IsAltKeyDown() and BG.TogglePin then
			BG.TogglePin(r)
		elseif button == "RightButton" and IsShiftKeyDown() and BG.OpenSplit then
			BG.OpenSplit(r)
		end
	end)
	return btn
end

-- The new-item glow: an accent rim with an inner wash, pulsing. Built on
-- first use only.
local function EnsureGlow(rec)
	if rec.glow then return rec.glow end
	local glow = CreateFrame("Frame", nil, rec.btn)
	glow:SetAllPoints()
	glow:SetFrameLevel(rec.btn:GetFrameLevel() + 3)
	glow:EnableMouse(false)
	glow.outer = UI.Edge(glow, 1, 1, 1, 1, "OVERLAY")
	local inner = CreateFrame("Frame", nil, glow)
	inner:SetPoint("TOPLEFT", 1, -1)
	inner:SetPoint("BOTTOMRIGHT", -1, 1)
	glow.inner = UI.Edge(inner, 1, 1, 1, 0.45, "OVERLAY")
	glow.wash = glow:CreateTexture(nil, "ARTWORK")
	glow.wash:SetPoint("TOPLEFT", 1, -1)
	glow.wash:SetPoint("BOTTOMRIGHT", -1, 1)
	glow.wash:SetTexture("Interface\\Buttons\\WHITE8X8")
	local anim = glow:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local fade = anim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.85)
	fade:SetSmoothing("IN_OUT")
	glow.anim = anim
	glow:Hide()
	rec.glow = glow
	return glow
end

local function GlowColor()
	local db = DB()
	if db.newGlowAccent ~= false then return Soul:Accent() end
	local c = db.newGlowColor
	if type(c) == "table" then return c[1] or 1, c[2] or 0.82, c[3] or 0.32 end
	return 1, 0.82, 0.32
end

local ILVL_POINTS = {
	TOPLEFT = { "TOPLEFT", 2, -2, "LEFT" },
	TOPRIGHT = { "TOPRIGHT", -2, -2, "RIGHT" },
	BOTTOMLEFT = { "BOTTOMLEFT", 2, 2, "LEFT" },
	TOP = { "TOP", 0, -2, "CENTER" },
	CENTER = { "CENTER", 0, 0, "CENTER" },
}

-- Size and fonts. Called at creation and from Apply (out of combat).
function BG.StyleRec(rec)
	local db = DB()
	local btn = rec.btn
	local size = db.iconSize or 40
	btn:SetSize(size, size)
	if btn.icon then
		btn.icon:ClearAllPoints()
		btn.icon:SetPoint("TOPLEFT", 1, -1)
		btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		btn.icon:SetTexCoord(0, 1, 0, 1)
		if btn.icon.SetSnapToPixelGrid then btn.icon:SetSnapToPixelGrid(true) end
	end
	if btn.Cooldown then
		btn.Cooldown:ClearAllPoints()
		btn.Cooldown:SetPoint("TOPLEFT", 1, -1)
		btn.Cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	if btn.IconQuestTexture then
		btn.IconQuestTexture:ClearAllPoints()
		btn.IconQuestTexture:SetPoint("TOPLEFT", 1, -1)
		btn.IconQuestTexture:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	if btn.Count then
		Soul:ApplyFont(btn.Count, db.countSize or 12)
		btn.Count:ClearAllPoints()
		btn.Count:SetPoint("BOTTOMRIGHT", -2, 3)
		btn.Count:SetJustifyH("RIGHT")
	end
	Soul:ApplyFont(rec.ilvl, db.ilvlSize or 12, "BRIGHT")
	local spot = ILVL_POINTS[db.ilvlAnchor] or ILVL_POINTS.TOPLEFT
	rec.ilvl:ClearAllPoints()
	rec.ilvl:SetPoint(spot[1], spot[2], spot[3])
	rec.ilvl:SetJustifyH(spot[4])
	Soul:ApplyFont(rec.bind, max(8, floor((db.ilvlSize or 12) * 0.8 + 0.5)), "BRIGHT")
	rec.bind:ClearAllPoints()
	if db.ilvlAnchor == "BOTTOMLEFT" then
		rec.bind:SetPoint("TOPLEFT", 2, -2)
	else
		rec.bind:SetPoint("BOTTOMLEFT", 2, 3)
	end
end

function BG.NewRec(view, bag, slot)
	local rec = { bag = bag, slot = slot, has = false, name = "", view = view }
	BuildButton(rec, view.holders[bag])
	BG.StyleRec(rec)
	return rec
end

-- Reads one slot into its record. Returns true when GetItemInfo was not
-- cached yet (GET_ITEM_INFO_RECEIVED will refresh once more).
function BG.ReadSlot(rec)
	local info = C_Container.GetContainerItemInfo(rec.bag, rec.slot)
	if not info then
		rec.has = false
		rec.link, rec.itemID, rec.classID, rec.subID, rec.level = nil, nil, nil, nil, nil
		rec.quality, rec.count, rec.junk, rec.new, rec.quest = 0, 0, false, false, false
		rec.name = ""
		return false
	end
	rec.has = true
	rec.icon = info.iconFileID
	rec.count = info.stackCount or 1
	rec.locked = info.isLocked and true or false
	local quality = info.quality
	if issecret(quality) or type(quality) ~= "number" then
		local itemID = info.itemID
		if type(itemID) == "number" and not issecret(itemID) and C_Item.GetItemQualityByID then
			quality = C_Item.GetItemQualityByID(itemID)
		end
	end
	if issecret(quality) or type(quality) ~= "number" then quality = 1 end
	rec.quality = quality
	rec.filtered = info.isFiltered and true or false
	rec.bound = info.isBound and true or false
	rec.name = info.itemName or ""
	if rec.link ~= info.hyperlink then
		rec.link = info.hyperlink
		rec.itemID = info.itemID
		rec.classID, rec.subID, rec.equipLoc = nil, nil, nil
		rec.level, rec.bindType, rec.craftAtlas = nil, nil, nil
	end
	local noValue = info.hasNoValue
	rec.junk = rec.quality == 0 and not issecret(noValue) and not noValue and true or false
	local pending = false
	if not rec.classID and rec.itemID and C_Item.GetItemInfoInstant then
		local _, _, _, equipLoc, _, classID, subID = C_Item.GetItemInfoInstant(rec.itemID)
		rec.classID, rec.subID, rec.equipLoc = classID, subID, equipLoc
	end
	local gear = rec.classID and GEAR[rec.classID] and rec.equipLoc and rec.equipLoc ~= "" and rec.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
	if gear and (rec.level == nil or rec.bindType == nil) and rec.link and C_Item.GetItemInfo then
		-- Item level and bind type both need the item cached. Until it is,
		-- leave them unread; GET_ITEM_INFO_RECEIVED reads the bags again.
		local bindType = select(14, C_Item.GetItemInfo(rec.link))
		if bindType == nil then
			pending = true
		else
			rec.bindType = bindType
			if rec.level == nil then
				rec.level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(rec.link) or false
			end
		end
	elseif rec.level == nil and not gear then
		rec.level = false
	end
	-- Read once per item (false = no mark), not on every bag update.
	if rec.craftAtlas == nil then
		rec.craftAtlas = BG.CraftingAtlas(rec.link, rec.itemID) or false
	end
	rec.new = C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(rec.bag, rec.slot) or false
	rec.quest, rec.questStart = false, false
	if rec.classID == 12 or rec.classID == 0 or rec.classID == 15 then
		local q = C_Container.GetContainerItemQuestInfo(rec.bag, rec.slot)
		if q then
			rec.quest = q.isQuestItem or (q.questID ~= nil)
			rec.questStart = q.questID ~= nil and not q.isActive
		end
	end
	return pending
end

-- Midnight's reagent marks (silver star, gold pentagon, and the rest) come
-- back as atlas names on the item link. A bare item id answers with the old
-- diamond, or with nothing. The inventory field is the bag-sized chip.
function BG.CraftingAtlas(link, itemID)
	local trade = C_TradeSkillUI
	if not trade then return end
	local function read(key)
		if key == nil or issecret(key) then return end
		local function from(method)
			if not method then return end
			local ok, info = pcall(method, key)
			if not ok or type(info) ~= "table" then return end
			local atlas = info.iconInventory or info.icon
			if type(atlas) == "string" and atlas ~= "" and not issecret(atlas) then
				return atlas
			end
		end
		return from(trade.GetItemReagentQualityInfo) or from(trade.GetItemCraftedQualityInfo)
	end
	local atlas
	if type(link) == "string" and link ~= "" and not issecret(link) then
		atlas = read(link)
	end
	if not atlas and type(itemID) == "number" and not issecret(itemID) then
		atlas = read(itemID)
	end
	return atlas
end

local function BaseAlpha(rec)
	return rec.has and rec.filtered and 0.22 or 1
end
BG.BaseAlpha = BaseAlpha

function BG.Paint(rec)
	local db = DB()
	local btn = rec.btn
	-- List rows carry the count and item level as text beside a small icon.
	local small = db.style == "list" and rec.view and rec.view.key == "main"
	if rec.has then
		if btn.icon then
			btn.icon:SetTexture(rec.icon)
			btn.icon:Show()
			local grey = db.junkGrey and rec.junk
			btn.icon:SetDesaturated(rec.locked or grey)
			btn.icon:SetAlpha(grey and 0.6 or 1)
		end
		if btn.Count then
			if not small and rec.count and rec.count > 1 then
				btn.Count:SetText(rec.count)
				btn.Count:SetTextColor(1, 1, 1)
				btn.Count:Show()
			else
				btn.Count:SetText("")
				btn.Count:Hide()
			end
		end
		local q = rec.quality or 1
		if type(q) ~= "number" or issecret(q) then q = 1 end
		-- Colors are read once at load (no table per paint).
		local c = QCOLOR[q] or QCOLOR[1]
		if rec.well then rec.well:SetColorTexture(0, 0, 0, 0.42) end
		if rec.quest and db.questMarks then
			rec.edge:SetColor(QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3], 1)
		elseif db.qualityBorders and c and q >= (db.qualityMin or 2) then
			rec.edge:SetColor(c[1], c[2], c[3], 0.95)
		else
			rec.edge:SetColor(NEUTRAL_EDGE[1], NEUTRAL_EDGE[2], NEUTRAL_EDGE[3], NEUTRAL_EDGE[4])
		end
		HideRegion(btn.ProfessionQualityOverlay)
		HideRegion(btn.IconOverlay)
		HideRegion(btn.IconOverlay2)
		if rec.craft then
			local atlas = rec.craftAtlas
			if not small and type(atlas) == "string" and rec.craft.SetAtlas then
				rec.craft:ClearAllPoints()
				rec.craft:SetPoint("TOPLEFT", rec.overlay, "TOPLEFT", 1, -1)
				rec.craft:SetAtlas(atlas, true)
				local slot = db.iconSize or 40
				local mark = math.max(24, math.floor(slot * 0.62 + 0.5))
				local w, h = rec.craft:GetWidth(), rec.craft:GetHeight()
				if type(w) == "number" and type(h) == "number" and w > 4 and h > 4 then
					local scale = mark / math.max(w, h)
					rec.craft:SetSize(math.floor(w * scale + 0.5), math.floor(h * scale + 0.5))
				else
					rec.craft:SetSize(mark, mark)
				end
				rec.craft:Show()
			else
				rec.craft:Hide()
			end
		end
		if not small and db.itemLevel and rec.level and rec.level > 1 then
			rec.ilvl:SetText(rec.level)
			local lc = db.ilvlQualityColor and c or QCOLOR[1]
			rec.ilvl:SetTextColor(lc[1], lc[2], lc[3])
			rec.ilvl:Show()
		else
			rec.ilvl:Hide()
		end
		local bindLabel
		if not small and db.bindText and not rec.bound and rec.bindType then
			if rec.bindType == 2 then bindLabel = "BoE"
			elseif rec.bindType == 9 then bindLabel = "WuE"
			elseif rec.bindType == 3 then bindLabel = "BoU" end
		end
		if bindLabel then
			rec.bind:SetText(bindLabel)
			rec.bind:SetTextColor(0.78, 0.86, 0.95)
			rec.bind:Show()
		else
			rec.bind:Hide()
		end
		if btn.IconQuestTexture then
			if db.questMarks and rec.questStart and TEXTURE_ITEM_QUEST_BANG then
				btn.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
				btn.IconQuestTexture:Show()
			else
				btn.IconQuestTexture:Hide()
			end
		end
		if db.newGlow and rec.new then
			local glow = EnsureGlow(rec)
			local r, g, b = GlowColor()
			glow.outer:SetColor(r, g, b, 1)
			glow.inner:SetColor(r, g, b, 0.45)
			if glow.wash.SetGradient and CreateColor then
				glow.wash:SetGradient("VERTICAL", CreateColor(r, g, b, 0.28), CreateColor(r, g, b, 0))
			else
				glow.wash:SetColorTexture(r, g, b, 0.12)
			end
			if not glow:IsShown() then
				glow:Show()
				glow.anim:Play()
			end
		elseif rec.glow and rec.glow:IsShown() then
			rec.glow.anim:Stop()
			rec.glow:Hide()
		end
	else
		if btn.icon then
			btn.icon:SetTexture(nil)
			btn.icon:Hide()
		end
		if btn.Count then
			btn.Count:SetText("")
			btn.Count:Hide()
		end
		if btn.IconQuestTexture then btn.IconQuestTexture:Hide() end
		rec.edge:SetColor(NEUTRAL_EDGE[1], NEUTRAL_EDGE[2], NEUTRAL_EDGE[3], NEUTRAL_EDGE[4])
		if rec.well then rec.well:SetColorTexture(0, 0, 0, 0.42) end
		if rec.craft then rec.craft:Hide() end
		rec.ilvl:Hide()
		rec.bind:Hide()
		if rec.glow and rec.glow:IsShown() then
			rec.glow.anim:Stop()
			rec.glow:Hide()
		end
		if btn.Cooldown then btn.Cooldown:Hide() end
	end
	btn:SetAlpha(BaseAlpha(rec))
end

-- The "one free slot" mode shows the free count on that slot.
function BG.PaintFree(rec)
	local count = rec.btn.Count
	if not count or rec.has then return end
	local small = DB().style == "list" and rec.view and rec.view.key == "main"
	if rec.freeCount and not small then
		count:SetText(rec.freeCount)
		count:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
		count:Show()
	else
		count:SetText("")
		count:Hide()
	end
end

function BG.PaintCooldown(rec)
	local cd = rec.btn.Cooldown
	if not cd then return end
	if not rec.has then cd:Hide() return end
	local start, duration, enable = C_Container.GetContainerItemCooldown(rec.bag, rec.slot)
	if start == nil or duration == nil or issecret(start) or issecret(duration) or issecret(enable) then return end
	if CooldownFrame_Set then pcall(CooldownFrame_Set, cd, start, duration, enable) end
end

function BG.PaintCooldowns(v)
	for _, list in pairs(v.recs) do
		for slot = 1, #list do
			local rec = list[slot]
			if rec.btn:IsShown() then BG.PaintCooldown(rec) end
		end
	end
end

------------------------------------------------------------------------------
-- Views: a set of bags shown in one content frame, split into sections.
------------------------------------------------------------------------------

function BG.NewView(key, win)
	return {
		key = key,
		win = win,
		content = win.content,
		bags = {},
		holders = {},
		recs = {},
		numSlots = {},
		dirty = {},
		order = {},
		secByKey = {},
		pass = 0,
	}
end

function BG.AddSection(view, key, label, comparator)
	local sec = view.secByKey[key]
	if sec then
		sec.label = label
		return sec
	end
	sec = { key = key, label = label, list = {}, n = 0, max = 0, comparator = comparator }
	local title = UI.Text(view.content, 12, UI.C.dim)
	title:SetWordWrap(false)
	sec.title = title
	local tick = view.content:CreateTexture(nil, "ARTWORK")
	tick:SetSize(2, 10)
	sec.tick = tick
	UI.OnAccent(function(r, g, b) tick:SetColorTexture(r, g, b, 1) end)
	view.secByKey[key] = sec
	view.order[#view.order + 1] = sec
	return sec
end

local function Holder(view, bag)
	local holder = view.holders[bag]
	if holder then return holder end
	holder = CreateFrame("Frame", nil, view.content)
	holder:SetID(bag)
	holder:SetAllPoints(view.content)
	view.holders[bag] = holder
	view.recs[bag] = {}
	return holder
end

-- Makes sure slot buttons exist for a bag. Returns how many are usable now.
local function EnsureSlots(view, bag, n)
	Holder(view, bag)
	local list = view.recs[bag]
	if #list >= n then return n end
	if InCombatLockdown() then
		Soul:RunAfterCombat("bags:create:" .. view.key, function()
			view.dirtyAll = true
			BG.ScheduleRefresh()
		end)
		return #list
	end
	for slot = #list + 1, n do
		list[slot] = BG.NewRec(view, bag, slot)
	end
	return n
end
BG.EnsureSlots = EnsureSlots

-- Reads a bag. Returns true when some item info was still loading.
function BG.ReadBag(view, bag)
	local n = C_Container.GetContainerNumSlots(bag) or 0
	local usable = EnsureSlots(view, bag, n)
	view.numSlots[bag] = usable
	local pending = false
	local list = view.recs[bag]
	for slot = 1, usable do
		local rec = list[slot]
		if BG.ReadSlot(rec) then pending = true end
		BG.Paint(rec)
		BG.PaintCooldown(rec)
	end
	return pending
end

function BG.ReadView(view, full)
	local pending = false
	local all = full or view.dirtyAll
	view.dirtyAll = nil
	for i = 1, #view.bags do
		local bag = view.bags[i]
		if all or view.dirty[bag] then
			view.dirty[bag] = nil
			if BG.ReadBag(view, bag) then pending = true end
		end
	end
	return pending
end

function BG.ResetSections(view)
	for i = 1, #view.order do view.order[i].n = 0 end
end

function BG.Add(view, key, rec)
	local sec = view.secByKey[key]
	if not sec then return end
	local n = sec.n + 1
	sec.n = n
	sec.list[n] = rec
end

-- Sort comparators read the cached record fields only.
local function ByBagSlot(a, b)
	if a.bag ~= b.bag then return a.bag < b.bag end
	return a.slot < b.slot
end
BG.ByBagSlot = ByBagSlot

local function ByQuality(a, b)
	local qa, qb = a.quality or 0, b.quality or 0
	if qa ~= qb then return qa > qb end
	local la, lb = a.level or 0, b.level or 0
	if la ~= lb then return la > lb end
	if a.name ~= b.name then return a.name < b.name end
	if a.count ~= b.count then return (a.count or 0) > (b.count or 0) end
	return ByBagSlot(a, b)
end

local function ByLevel(a, b)
	local la, lb = a.level or 0, b.level or 0
	if la ~= lb then return la > lb end
	return ByQuality(a, b)
end

local function ByName(a, b)
	if a.name ~= b.name then return a.name < b.name end
	if a.count ~= b.count then return (a.count or 0) > (b.count or 0) end
	return ByBagSlot(a, b)
end

local function ByType(a, b)
	local ca, cb = a.classID or 99, b.classID or 99
	if ca ~= cb then return ca < cb end
	local sa, sb = a.subID or 99, b.subID or 99
	if sa ~= sb then return sa < sb end
	return ByQuality(a, b)
end

local SORTS = { quality = ByQuality, ilvl = ByLevel, name = ByName, type = ByType, none = ByBagSlot }
BG.SORTS = SORTS

-- Flow layout. Each section is a block `w` slots wide; with packing on, a
-- block sits beside the previous one when it fits in the row. Returns the
-- content width and height. Records not placed are hidden.
function BG.Pack(view, cols, titles, defaultSort)
	local db = DB()
	local size = db.iconSize or 40
	local gap = db.spacing or 4
	local secGap = db.sectionGap or 12
	local titleSize = db.titleSize or 12
	local titleH = titles and (titleSize + 9) or 0
	local step = size + gap
	local inner = cols * size + (cols - 1) * gap
	local pack = db.packSections ~= false
	local content = view.content
	view.pass = view.pass + 1
	local pass = view.pass
	local x, y, lineH = 0, 0, 0
	local accentR, accentG, accentB = Soul:Accent()

	for i = 1, #view.order do
		local sec = view.order[i]
		local n = sec.n
		local list = sec.list
		for k = n + 1, sec.max do list[k] = nil end
		sec.max = n
		if n > 0 then
			if n > 1 then table.sort(list, sec.comparator or defaultSort) end
			local w = n < cols and n or cols
			local showTitle = titles and sec.label
			if showTitle then
				UI.SetFont(sec.title, titleSize)
				sec.title:SetText(sec.label)
				local need = ceil(((sec.title:GetStringWidth() or 0) + 14) / step)
				if need > w then w = min(cols, need) end
			end
			local rows = ceil(n / w)
			local bw = w * size + (w - 1) * gap
			local bh = titleH + rows * size + (rows - 1) * gap
			if x > 0 and (not pack or x + bw > inner + 0.5) then
				y = y + lineH + secGap
				x, lineH = 0, 0
			end
			if showTitle then
				sec.tick:ClearAllPoints()
				sec.tick:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y - 2)
				sec.tick:SetSize(2, titleSize - 1)
				sec.tick:SetColorTexture(accentR, accentG, accentB, 1)
				sec.tick:Show()
				sec.title:ClearAllPoints()
				sec.title:SetPoint("TOPLEFT", content, "TOPLEFT", x + 8, -y)
				sec.title:SetWidth(max(1, bw - 8))
				sec.title:Show()
			else
				sec.title:Hide()
				sec.tick:Hide()
			end
			for k = 1, n do
				local rec = list[k]
				local col = (k - 1) % w
				local row = floor((k - 1) / w)
				local btn = rec.btn
				btn:ClearAllPoints()
				btn:SetPoint("TOPLEFT", content, "TOPLEFT", x + col * step, -(y + titleH + row * step))
				rec.pass = pass
				if rec.freeCount ~= nil or not rec.has then BG.PaintFree(rec) end
			end
			x = x + bw + secGap
			if bh > lineH then lineH = bh end
		else
			sec.title:Hide()
			sec.tick:Hide()
		end
	end

	for _, list in pairs(view.recs) do
		for slot = 1, #list do
			local rec = list[slot]
			if rec.pass == pass then
				if not rec.btn:IsShown() then rec.btn:Show() end
			elseif rec.btn:IsShown() then
				rec.btn:Hide()
			end
		end
	end
	return inner, y + lineH
end

-- Layout may move buttons. If the client protects them, wait for combat end.
function BG.CanLayout()
	return not (BG.protectedButtons and InCombatLockdown())
end

------------------------------------------------------------------------------
-- The bag window
------------------------------------------------------------------------------

local win, view, search, bagBar, sortButton, barButton
local footerFree, footerGold, sellJunk
local currencyCells = {}
local bagSlots = {}
local hidden
local origParent = {}
local editWasOpen = false
local atMerchant = false
local lastSort = 0
local pendingInfo = false

local function Fallback()
	return { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -70, y = 110 }
end

local function Active()
	return BG.built and DB().enabled and true or false
end
BG.Active = Active

	local MAIN_BAGS = { BACKPACK, 1, 2, 3, 4 }
	if REAGENT and REAGENT ~= 4 then MAIN_BAGS[#MAIN_BAGS + 1] = REAGENT end
	BG.MAIN_BAGS = MAIN_BAGS

-- Thousands separators. BreakUpLargeNumbers follows the client locale; the
-- fallback groups by three with commas.
local function Group(n)
	if BreakUpLargeNumbers then
		local ok, text = pcall(BreakUpLargeNumbers, n)
		if ok and type(text) == "string" then return text end
	end
	local s = tostring(floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
BG.Group = Group

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- "965,326g 12s 4c" with coin icons. Zero silver and copper are left out.
local function FormatMoney(copper)
	if type(copper) ~= "number" or issecret(copper) then return "" end
	if copper < 0 then copper = -copper end
	copper = floor(copper)
	local gold = floor(copper / 10000)
	local silver = floor(copper / 100) % 100
	local cop = copper % 100
	local parts, n = {}, 0
	if gold > 0 then n = n + 1 parts[n] = Group(gold) .. GOLD_ICON end
	if silver > 0 then n = n + 1 parts[n] = silver .. SILVER_ICON end
	if cop > 0 or n == 0 then n = n + 1 parts[n] = cop .. COPPER_ICON end
	return table.concat(parts, " ")
end
BG.FormatMoney = FormatMoney

local function UpdateFooter()
	if not win then return end
	local db = DB()
	local free, reagentFree = 0, 0
	local total = 0
	for i = 1, #MAIN_BAGS do
		local bag = MAIN_BAGS[i]
		local f = C_Container.GetContainerNumFreeSlots(bag) or 0
		total = total + (C_Container.GetContainerNumSlots(bag) or 0)
		if bag == REAGENT then reagentFree = reagentFree + f else free = free + f end
	end
	if (C_Container.GetContainerNumSlots(REAGENT) or 0) > 0 then
		footerFree:SetFormattedText("%d free  |cff7a8794·  %d reagent|r", free, reagentFree)
	else
		footerFree:SetFormattedText("%d free  |cff7a8794·  %d slots|r", free, total)
	end

	footerGold:SetShown(db.gold ~= false)
	if db.gold ~= false then footerGold:SetText(FormatMoney(GetMoney())) end

	local anchor = db.gold ~= false and footerGold or nil
	for i = 1, #currencyCells do
		local cell = currencyCells[i]
		local info = db.currencies ~= false and C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo
			and C_CurrencyInfo.GetBackpackCurrencyInfo(i)
		if info and info.iconFileID then
			cell.icon:SetTexture(info.iconFileID)
			cell.text:SetText(Group(info.quantity or 0))
			cell:SetWidth((cell.text:GetStringWidth() or 20) + 22)
			cell:ClearAllPoints()
			if anchor then
				cell:SetPoint("RIGHT", anchor, "LEFT", -14, 0)
			else
				cell:SetPoint("RIGHT", win.footer, "RIGHT", -14, 0)
			end
			anchor = cell
			cell:Show()
		else
			cell:Hide()
		end
	end

	local hasJunk = (view and view.junkCount or 0) > 0
	-- After the Alts / History buttons when they show.
	local left = BG.FootEnd and BG.FootEnd() or footerFree
	sellJunk:ClearAllPoints()
	sellJunk:SetPoint("LEFT", left, "RIGHT", 14, 0)
	sellJunk:SetShown(atMerchant and hasJunk and C_MerchantFrame and C_MerchantFrame.SellAllJunkItems ~= nil)
end
BG.UpdateFooter = UpdateFooter

local function UpdateBagBar()
	if not bagBar or not bagBar:IsShown() then return end
	for i = 1, #bagSlots do
		local b = bagSlots[i]
		local inv = C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(b.bag)
		b.inv = inv
		local tex = inv and GetInventoryItemTexture("player", inv)
		if tex then
			b.icon:SetTexture(tex)
			b.icon:SetDesaturated(false)
			b.icon:SetAlpha(1)
			local slots = C_Container.GetContainerNumSlots(b.bag) or 0
			local free = C_Container.GetContainerNumFreeSlots(b.bag) or 0
			b.count:SetText(free .. "/" .. slots)
		else
			b.icon:SetTexture(nil)
			b.count:SetText("")
		end
	end
end

-- Dims every slot outside one bag while its bag-bar button is hovered.
local function DimOtherBags(bag)
	if not view then return end
	for b, list in pairs(view.recs) do
		for slot = 1, #list do
			local rec = list[slot]
			if bag and b ~= bag then
				rec.btn:SetAlpha(0.18)
			else
				rec.btn:SetAlpha(BaseAlpha(rec))
			end
		end
	end
end

local function Layout()
	if not win then return end
	if not BG.CanLayout() then
		Soul:RunAfterCombat("bags:layout", Layout)
		return
	end
	local db = DB()
	local cats = db.cats or {}
	local grouped = db.categories ~= false and db.style ~= "bags"
	local byBag = db.style == "bags"
	-- The sidebar (and its filter) only exists in the combined and list
	-- styles. A filter left over from those must not empty the per-bag view.
	local sidebar = db.sidebar and not byBag
	local filter = sidebar and view.filter or nil
	local pins = cats.pin ~= false and db.pins or nil
	local mode = db.emptyMode or "one"
	BG.ResetSections(view)
	local freeN, freeR = 0, 0
	local firstN, firstR
	local junk = 0
	local matched = 0
	-- Items per category, for dimming empty sidebar entries.
	local counts = view.catCounts or {}
	view.catCounts = counts
	wipe(counts)
	for i = 1, #view.bags do
		local bag = view.bags[i]
		local list = view.recs[bag]
		local n = view.numSlots[bag] or 0
		for slot = 1, n do
			local rec = list[slot]
			rec.freeCount = nil
			if rec.has then
				if rec.junk then junk = junk + 1 end
				-- Classified for the filter even when sections are off.
				local cat = (grouped or filter or sidebar) and Classify(rec, cats) or "other"
				local pinned = type(pins) == "table" and type(rec.itemID) == "number" and not issecret(rec.itemID) and pins[rec.itemID]
				if pinned then cat = "pin" end
				counts[cat] = (counts[cat] or 0) + 1
				if not filter or cat == filter then
					matched = matched + 1
					if byBag then
						BG.Add(view, "bag" .. bag, rec)
					elseif grouped or pinned then
						BG.Add(view, cat, rec)
					else
						BG.Add(view, "other", rec)
					end
				end
			else
				if bag == REAGENT then
					freeR = freeR + 1
					if not firstR then firstR = rec end
				else
					freeN = freeN + 1
					if not firstN then firstN = rec end
				end
				if mode == "all" then
					-- Per bag, an empty slot stays in its own bag's block.
					BG.Add(view, byBag and ("bag" .. bag) or "free", rec)
				end
			end
		end
	end
	if mode == "one" then
		if firstN then firstN.freeCount = freeN BG.Add(view, "free", firstN) end
		if firstR then firstR.freeCount = freeR BG.Add(view, "free", firstR) end
	end
	view.junkCount = junk

	local cols = db.columns or 12
	if cols < 4 then cols = 4 end
	local titles = db.sectionTitles ~= false and (grouped or byBag)
	local width, height
	if db.style == "list" and BG.PackList then
		width, height = BG.PackList(view, titles, SORTS[db.sortMode] or ByQuality)
	else
		width, height = BG.Pack(view, cols, titles, SORTS[db.sortMode] or ByQuality)
	end

	local pad = db.padding or 12
	local side = (sidebar and BG.SidebarWidth) or 0
	local top = HEADER + (db.bagBar and BAGBAR or 0) + pad
	local w = max(MIN_WIDTH, width + pad * 2 + side)
	height = max(1, height)
	-- The item area shows up to the height cap and scrolls past it. It is
	-- never shorter than the sidebar's category list.
	local viewH = height
	local cap = BG.MaxHeight(win) - top - pad - FOOTER
	if viewH > cap then viewH = cap end
	if side > 0 and BG.SidebarHeight then
		local need = BG.SidebarHeight() + 12 - pad * 2
		if viewH < need then viewH = need end
	end
	viewH = max(1, viewH)
	local scroll = win.scroll
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", win.body, "TOPLEFT", pad + side, -top)
	scroll:SetSize(max(1, width), viewH)
	view.content:SetSize(max(1, width), height)
	-- A sidebar filter that matches nothing says so under the free slot,
	-- instead of leaving a lone "Free" block that looks like a glitch.
	if filter and matched == 0 then
		if not win.emptyNote then
			win.emptyNote = UI.Text(win.body, 13, UI.C.dim)
		end
		local label = "these"
		for c = 1, #BG.CATEGORIES do
			if BG.CATEGORIES[c].key == filter then label = BG.CATEGORIES[c].label end
		end
		win.emptyNote:ClearAllPoints()
		win.emptyNote:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(height + 14))
		win.emptyNote:SetText("Nothing in " .. label .. ".")
		win.emptyNote:Show()
	elseif win.emptyNote then
		win.emptyNote:Hide()
	end
	win:SetSize(w, top + viewH + pad + FOOTER)
	if BG.PaintSidebar then BG.PaintSidebar() end
	win:SetScrollOffset(scroll:GetVerticalScroll() or 0)
	UpdateFooter()
	UpdateBagBar()
end

function BG.ResetScroll()
	if win and BG.CanLayout() then win:SetScrollOffset(0) end
end

local function Refresh(full)
	if not win then return end
	if BG.ReadView(view, full) then pendingInfo = true end
	Layout()
	if BG.AfterRefresh then BG.AfterRefresh() end
end
BG.RefreshBags = Refresh

------------------------------------------------------------------------------
-- Batching. One timer for every event.
------------------------------------------------------------------------------

local scheduled = false
local function RunScheduled()
	scheduled = false
	if win and win:IsShown() then Refresh(false) end
	if BG.Bank and BG.Bank.IsShown and BG.Bank.IsShown() then BG.Bank.Refresh(false) end
end

function BG.ScheduleRefresh(delay)
	if scheduled then return end
	scheduled = true
	C_Timer.After(delay or 0.05, RunScheduled)
end

------------------------------------------------------------------------------
-- Open / close and the Blizzard hooks
------------------------------------------------------------------------------

function BG:IsOpen()
	return win and win:IsShown() and not win._closing and true or false
end

function BG:Open(source)
	if Soul.unlocking then return end
	if not Active() then return end
	if self:IsOpen() then return end
	self.openedBy = source
	if DB().autoSort and not InCombatLockdown() and GetTime() - lastSort > 5 then
		lastSort = GetTime()
		C_Container.SortBags()
	end
	view.dirtyAll = true
	Refresh(true)
	BG.ResetScroll()
	win:OpenAnimated()
	win:Raise()
end

function BG:Close()
	if not win or not win:IsShown() then return end
	self.openedBy = nil
	win:CloseAnimated()
end

function BG:Toggle()
	if self:IsOpen() then self:Close() else self:Open() end
end

-- Several Blizzard functions fire for one key press (ToggleAllBags opens or
-- closes each bag). Every hook records an intent; one resolver acts on the
-- strongest intent on the next frame. A toggle always wins.
local RANK = { toggle = 3, open = 2, close = 1 }
local intent, intentSource
local resolver = CreateFrame("Frame")
resolver:Hide()
resolver:SetScript("OnUpdate", function(self)
	self:Hide()
	local what, src = intent, intentSource
	intent, intentSource = nil, nil
	if not Active() then return end
	if what == "toggle" then
		BG:Toggle()
	elseif what == "open" then
		BG:Open(src)
	elseif what == "close" then
		-- CloseAllBags(frame) only closes bags that frame opened.
		if src == nil or BG.openedBy == src then BG:Close() end
	end
end)

local function Want(what, src)
	if not Active() then return end
	if not intent or RANK[what] > RANK[intent] then
		intent, intentSource = what, src
	end
	resolver:Show()
end

local hooksDone = false
local function HookBlizzard()
	if hooksDone then return end
	hooksDone = true
	local function Hook(name, fn)
		if type(_G[name]) == "function" then hooksecurefunc(name, fn) end
	end
	Hook("ToggleAllBags", function() Want("toggle") end)
	Hook("ToggleBackpack", function() Want("toggle") end)
	Hook("ToggleBag", function() Want("toggle") end)
	Hook("OpenAllBags", function(frame) Want("open", frame) end)
	Hook("OpenBackpack", function() Want("open") end)
	Hook("OpenBag", function() Want("open") end)
	Hook("CloseAllBags", function(frame) Want("close", frame) end)
	Hook("CloseBackpack", function() Want("close") end)
end

local function BlizzardBagFrames(fn)
	if ContainerFrameCombinedBags then fn(ContainerFrameCombinedBags) end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local frame = _G["ContainerFrame" .. i]
		if frame then fn(frame) end
	end
end

function BG.HiddenParent()
	if not hidden then
		hidden = CreateFrame("Frame")
		hidden:Hide()
	end
	return hidden
end

function BG.Park(frame, on)
	if not frame then return end
	if on then
		if not origParent[frame] then origParent[frame] = frame:GetParent() or UIParent end
		if frame:GetParent() ~= BG.HiddenParent() then pcall(frame.SetParent, frame, BG.HiddenParent()) end
	elseif origParent[frame] then
		pcall(frame.SetParent, frame, origParent[frame])
	end
end

local function ParkBlizzardBags(on)
	Soul:RunAfterCombat("bags:park", function()
		BlizzardBagFrames(function(frame) BG.Park(frame, on) end)
	end)
end

------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------

local function BuildBagBar()
	bagBar = CreateFrame("Frame", nil, win.body)
	bagBar:SetPoint("TOPLEFT", win.header, "BOTTOMLEFT", 0, 0)
	bagBar:SetPoint("TOPRIGHT", win.header, "BOTTOMRIGHT", 0, 0)
	bagBar:SetHeight(BAGBAR)
	local rule = bagBar:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1)
	rule:SetColorTexture(UI.C.line[1], UI.C.line[2], UI.C.line[3], UI.C.line[4])
	local bags = { 1, 2, 3, 4 }
	if REAGENT and REAGENT ~= 4 then bags[#bags + 1] = REAGENT end
	for i = 1, #bags do
		local b = CreateFrame("Button", nil, bagBar)
		b:SetSize(32, 32)
		b:SetPoint("LEFT", 12 + (i - 1) * 40, 0)
		b.bag = bags[i]
		UI.Fill(b, { 0, 0, 0, 0.42 })
		local edge = UI.Edge(b, 1, 1, 1, 0.12)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1)
		b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.count = UI.Text(b, 10, UI.C.text, "RIGHT")
		b.count:SetPoint("BOTTOMRIGHT", -1, 1)
		b:RegisterForDrag("LeftButton")
		b:RegisterForClicks("LeftButtonUp")
		local function Put(self)
			if not self.inv then return end
			if CursorHasItem() then
				PutItemInBag(self.inv)
			else
				PickupBagFromSlot(self.inv)
			end
		end
		b:SetScript("OnClick", Put)
		b:SetScript("OnDragStart", function(self) if self.inv then PickupBagFromSlot(self.inv) end end)
		b:SetScript("OnReceiveDrag", Put)
		b:SetScript("OnEnter", function(self)
			local r, g, bl = Soul:Accent()
			edge:SetColor(r, g, bl, 0.9)
			DimOtherBags(self.bag)
			if self.inv then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				if not GameTooltip:SetInventoryItem("player", self.inv) then
					GameTooltip:SetText(self.bag == REAGENT and "Reagent bag slot" or "Empty bag slot")
				end
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function()
			edge:SetColor(1, 1, 1, 0.12)
			DimOtherBags(nil)
			GameTooltip:Hide()
		end)
		bagSlots[i] = b
	end
	local hint = UI.Text(bagBar, 12, UI.C.faint)
	hint:SetPoint("LEFT", 12 + #bags * 40 + 6, 0)
	hint:SetText("Hover a bag to find its slots. Drop a bag here to equip it.")
	bagBar:Hide()
end

local function BuildFooter()
	local footer = win.footer
	footerFree = UI.Text(footer, 13, UI.C.dim)
	footerFree:SetPoint("LEFT", 16, 0)
	BG.footerFree = footerFree

	sellJunk = UI.Button(footer, "Sell junk", 86, 22, function()
		if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
			C_MerchantFrame.SellAllJunkItems()
		end
	end, "outline")
	sellJunk:SetPoint("LEFT", footerFree, "RIGHT", 14, 0)
	sellJunk:Hide()

	footerGold = UI.Text(footer, 14, UI.C.text, "RIGHT")
	footerGold:SetPoint("RIGHT", -16, 0)

	for i = 1, 3 do
		local cell = CreateFrame("Frame", nil, footer)
		cell:SetSize(60, 20)
		cell.icon = cell:CreateTexture(nil, "ARTWORK")
		cell.icon:SetSize(15, 15)
		cell.icon:SetPoint("LEFT")
		cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		cell.text = UI.Text(cell, 13, UI.C.text)
		cell.text:SetPoint("LEFT", cell.icon, "RIGHT", 5, 0)
		cell:EnableMouse(true)
		cell.index = i
		cell:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if GameTooltip.SetBackpackToken then GameTooltip:SetBackpackToken(self.index) end
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
		cell:Hide()
		currencyCells[i] = cell
	end
end

local function Build()
	win = BG.NewWindow("SoulUI_Bags", "Bags", "Bags:main", Fallback)
	BG.win = win
	win.close:SetScript("OnClick", function() BG:Close() end)
	if UISpecialFrames then table.insert(UISpecialFrames, "SoulUI_Bags") end

	view = BG.NewView("main", win)
	BG.view = view
	for i = 1, #MAIN_BAGS do view.bags[i] = MAIN_BAGS[i] end
	for i = 1, #BG.CATEGORIES do
		local c = BG.CATEGORIES[i]
		BG.AddSection(view, c.key, c.label, c.key == "free" and ByBagSlot or nil)
	end
	for i = 1, #MAIN_BAGS do
		local bag = MAIN_BAGS[i]
		local label = bag == BACKPACK and "Backpack" or (bag == REAGENT and "Reagent" or ("Bag " .. bag))
		BG.AddSection(view, "bag" .. bag, label, ByBagSlot)
	end

	-- Header controls, right to left: close, sort, bag bar, search.
	sortButton = BG.GlyphButton(win.header, 26, "bars", "Clean up",
		"Sorts the items inside your bags (the game's own sort). The window already orders items by the sort mode in settings.",
		function()
			if InCombatLockdown() then return end
			lastSort = GetTime()
			C_Container.SortBags()
		end)
	sortButton:SetPoint("RIGHT", win.close, "LEFT", -6, 0)
	barButton = BG.GlyphButton(win.header, 26, BAG_GLYPH, "Bag slots",
		"Shows your equipped bags. Hover one to find its slots, drop a bag on a slot to equip it.",
		function()
			local db = DB()
			db.bagBar = not db.bagBar
			BG:ApplyChrome()
			Layout()
		end, function() return DB().bagBar end)
	barButton:SetPoint("RIGHT", sortButton, "LEFT", -6, 0)
	search = BG.SearchBox(win.header, 200, function(text)
		if C_Container.SetItemSearch then C_Container.SetItemSearch(text) end
	end)
	search:SetPoint("RIGHT", barButton, "LEFT", -10, 0)
	BG.search = search

	BuildBagBar()
	BuildFooter()
	if BG.BuildExtras then BG.BuildExtras(win) end

	win:HookScript("OnHide", function()
		if search:GetText() ~= "" then search:SetText("") end
		search:ClearFocus()
		BG.openedBy = nil
		if BG.HideQuick then BG.HideQuick() end
		if BG.Snapshot then BG.Snapshot() end
		if DB().clearNewOnClose and C_NewItems and C_NewItems.ClearAll then
			C_NewItems.ClearAll()
			view.dirtyAll = true
		end
	end)
	BG.built = true
end

function BG:ApplyChrome()
	if not win then return end
	local db = DB()
	search:SetShown(db.search ~= false)
	if bagBar then bagBar:SetShown(db.bagBar and true or false) end
	if BG.ApplyExtras then BG.ApplyExtras() end
	if barButton then barButton.Paint() end
	win:ApplyLook()
end

------------------------------------------------------------------------------
-- Apply, mover, events
------------------------------------------------------------------------------

function BG:Apply()
	if not win then return end
	Soul:RunAfterCombat("bags:apply", function()
		local db = DB()
		win:SetScale(BG.WindowScale())
		ParkBlizzardBags(db.enabled and true or false)
		BG:ApplyChrome()
		for _, list in pairs(view.recs) do
			for slot = 1, #list do BG.StyleRec(list[slot]) end
		end
		if not db.enabled then
			if win:IsShown() then win:Hide() end
		else
			Refresh(true)
		end
		-- Placed after the refresh, so the top edge is set from the real height.
		BG.PlaceTop(win, "Bags:main", Fallback())
		if BG.Bank and BG.Bank.Apply then BG.Bank.Apply() end
	end)
end

local function OnEvent(_, event, a1, a2)
	if event == "BAG_UPDATE" then
		if type(a1) == "number" then
			view.dirty[a1] = true
			if BG.Bank and BG.Bank.MarkDirty then BG.Bank.MarkDirty(a1) end
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		BG.ScheduleRefresh()
	elseif event == "ITEM_LOCK_CHANGED" then
		-- (bag, slot) for a container slot; slot is nil for equipment.
		if type(a1) == "number" and type(a2) == "number" then
			local list = view.recs[a1]
			local rec = list and list[a2]
			if not rec and BG.Bank and BG.Bank.Rec then rec = BG.Bank.Rec(a1, a2) end
			if rec and rec.btn:IsVisible() then
				BG.ReadSlot(rec)
				BG.Paint(rec)
			end
		end
	elseif event == "BAG_UPDATE_COOLDOWN" then
		if win:IsShown() then BG.PaintCooldowns(view) end
		if BG.Bank and BG.Bank.IsShown and BG.Bank.IsShown() and BG.Bank.view then
			BG.PaintCooldowns(BG.Bank.view)
		end
	elseif event == "INVENTORY_SEARCH_UPDATE" or event == "BAG_NEW_ITEMS_UPDATED" or event == "BAG_CONTAINER_UPDATE" then
		view.dirtyAll = true
		if BG.Bank and BG.Bank.MarkAll then BG.Bank.MarkAll() end
		BG.ScheduleRefresh()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if pendingInfo then
			pendingInfo = false
			view.dirtyAll = true
			BG.ScheduleRefresh(0.2)
		end
	elseif event == "PLAYER_MONEY" or event == "CURRENCY_DISPLAY_UPDATE" then
		if win:IsShown() then UpdateFooter() end
		if BG.Bank and BG.Bank.IsShown and BG.Bank.IsShown() and BG.Bank.UpdateFooter then BG.Bank.UpdateFooter() end
	elseif event == "MERCHANT_SHOW" then
		atMerchant = true
		if win:IsShown() then UpdateFooter() end
	elseif event == "MERCHANT_CLOSED" then
		atMerchant = false
		if win:IsShown() then UpdateFooter() end
	end
end

local EVENTS = {
	"BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
	"INVENTORY_SEARCH_UPDATE", "BAG_NEW_ITEMS_UPDATED", "BAG_CONTAINER_UPDATE",
	"GET_ITEM_INFO_RECEIVED", "PLAYER_MONEY", "CURRENCY_DISPLAY_UPDATE",
	"MERCHANT_SHOW", "MERCHANT_CLOSED",
}

function BG:OnInitialize()
	Soul:RegisterModuleDB("Bags", Soul.Defaults.Bags)
end

function BG:OnEnable()
	Build()
	for i = 1, #EVENTS do
		-- pcall: an event name this client does not know raises an error.
		pcall(self.RegisterEvent, self, EVENTS[i], OnEvent)
	end
	HookBlizzard()
	if BG.StartExtras then BG.StartExtras() end

	Soul:RegisterMover({
		key = "Bags:main",
		label = "Bags",
		page = "bags",
		getFrame = function() return win end,
		fallback = Fallback,
		getEnabled = function() return DB().enabled end,
		setEnabled = function(on)
			DB().enabled = on and true or false
			BG:Apply()
		end,
		onResize = function(width, _, dir)
			local db = DB()
			local stored = db.iconSize or 40
			if dir == 1 or dir == -1 then
				db.iconSize = Soul:ScaleStep(stored, dir, 24, 64)
			else
				local cols = max(4, db.columns or 12)
				-- width is in UIParent units; the window has its own scale.
				local ratio = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
				if not ratio or ratio <= 0 then ratio = 1 end
				local inner = width / ratio - (db.padding or 12) * 2
				local want = (inner - (db.spacing or 4) * (cols - 1)) / cols
				db.iconSize = Soul:MatchSize(stored, want, 24, 64)
			end
			BG:Apply()
		end,
		-- The open bag covers the screen, so edit mode cannot reach the
		-- frames under it. Keep the window closed and show a small tag.
		compact = true,
		onEdit = function(on)
			if on then
				editWasOpen = BG:IsOpen() and true or false
				if editWasOpen and not InCombatLockdown() then BG:Close() end
			else
				-- Edit mode places the window by its saved (bottom) anchor;
				-- turn that back into a top anchor.
				if not InCombatLockdown() then BG.PlaceTop(win, "Bags:main", Fallback()) end
				if editWasOpen then
					editWasOpen = false
					if not InCombatLockdown() then BG:Open() end
				end
			end
		end,
	})

	Soul:On("ProfileChanged", function() BG:Apply() end)
	Soul:On("ThemeChanged", function() BG:Apply() end)

	-- The window has a place right away (a /reload in combat can open it
	-- before the warm-up below runs).
	win:SetScale(BG.WindowScale())
	BG.PlaceTop(win, "Bags:main", Fallback())

	-- Pre-build every slot button now, out of combat, so opening the bags in
	-- combat never has to create one.
	Soul:RunAfterCombat("bags:warm", function()
		win:SetScale(BG.WindowScale())
		ParkBlizzardBags(DB().enabled and true or false)
		BG:ApplyChrome()
		Refresh(true)
		BG.PlaceTop(win, "Bags:main", Fallback())
		if BG.Bank and BG.Bank.Enable then BG.Bank.Enable() end
	end)
end
