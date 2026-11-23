if SoulUI_Blocked or not SoulUI then return end

-- Sidebar, list rows, pins, stack split, a quick-action button, a remembered
-- picture of this character's bags, and a short gold history. The grid and
-- the per-bag blocks live in Bags.lua.

local Soul = SoulUI
local UI = Soul.UI
local BG = Soul:GetModule("Bags")
if not BG then return end

local DB = BG.DB
local floor, max = math.floor, math.max
local issecret = issecretvalue or function() return false end

BG.SidebarWidth = 132
local SIDE_ROW = 24

local sidebar, listRows, splitFrame, quick, offlineFrame, goldFrame
local footButtons = {}

local function Account()
	local root = Soul.db and Soul.db.account
	if type(root) ~= "table" then return nil end
	if type(root.bags) ~= "table" then root.bags = {} end
	return root.bags
end

local function Who()
	local name, realm = UnitName("player"), GetRealmName()
	if type(name) ~= "string" or issecret(name) or name == "" then return nil end
	if type(realm) ~= "string" or realm == "" then realm = "Realm" end
	return name .. "-" .. realm
end

------------------------------------------------------------------------------
-- List rows. One line per item: the item's own slot button as a small icon
-- (so use, equip and drag stay Blizzard's secure click), then the name, the
-- count and the item level. The row itself only shows the tooltip and takes
-- alt-click to pin; it never clicks the item for you (that would be an
-- addon-driven use, which the game blocks).
------------------------------------------------------------------------------

local ROW_H = 26
local LIST_W = 360

local function NewRow(content)
	local row = CreateFrame("Button", nil, content)
	row:SetHeight(ROW_H - 2)
	row:RegisterForClicks("LeftButtonUp")
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.04)
	local name = row:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(name, 13)
	name:SetPoint("LEFT", 32, 0)
	name:SetPoint("RIGHT", -70, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	row.name = name
	local meta = row:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(meta, 12)
	meta:SetPoint("RIGHT", -4, 0)
	meta:SetJustifyH("RIGHT")
	row.meta = meta
	row:SetScript("OnClick", function(self, button)
		local rec = self.rec
		if rec and rec.has and button == "LeftButton" and IsAltKeyDown() then BG.TogglePin(rec) end
	end)
	-- Shows the slot's own tooltip (read only; nothing is used or moved).
	row:SetScript("OnEnter", function(self)
		local btn = self.rec and self.rec.btn
		local enter = btn and btn:GetScript("OnEnter")
		if enter then enter(btn) end
	end)
	row:SetScript("OnLeave", function(self)
		local btn = self.rec and self.rec.btn
		local leave = btn and btn:GetScript("OnLeave")
		if leave then leave(btn) end
		if GameTooltip then GameTooltip:Hide() end
	end)
	return row
end

function BG.PackList(view, titles, sortFn)
	local content = view.content
	view.pass = view.pass + 1
	local pass = view.pass
	local y = 0
	local pool = listRows
	if not pool then
		pool = {}
		listRows = pool
	end
	local used = 0
	local QC = BG.QCOLOR
	local icon = ROW_H - 4

	for i = 1, #view.order do
		local sec = view.order[i]
		local n = sec.n
		local list = sec.list
		for k = n + 1, sec.max do list[k] = nil end
		sec.max = n
		if n > 0 then
			if n > 1 then table.sort(list, sec.comparator or sortFn) end
			if titles and sec.label then
				sec.tick:ClearAllPoints()
				sec.tick:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y - 4)
				sec.tick:SetSize(2, 12)
				sec.tick:Show()
				sec.title:ClearAllPoints()
				sec.title:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
				sec.title:SetWidth(LIST_W - 8)
				sec.title:SetText(sec.label)
				sec.title:Show()
				y = y + 20
			else
				sec.title:Hide()
				sec.tick:Hide()
			end
			for k = 1, n do
				local rec = list[k]
				rec.pass = pass
				used = used + 1
				local row = pool[used]
				if not row then
					row = NewRow(content)
					pool[used] = row
				end
				row.rec = rec
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
				local btn = rec.btn
				btn:SetSize(icon, icon)
				btn:ClearAllPoints()
				btn:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 1))
				if rec.has then
					local color = QC[rec.quality or 1] or QC[1]
					row.name:SetText(rec.name or "")
					row.name:SetTextColor(color[1], color[2], color[3])
					local bits = ""
					if (rec.count or 1) > 1 then bits = "x" .. rec.count end
					if rec.level and rec.level > 1 then
						bits = (bits ~= "" and (bits .. "  ") or "") .. rec.level
					end
					row.meta:SetText(bits)
				else
					row.name:SetText(rec.freeCount and (rec.freeCount .. " free") or "Empty slot")
					row.name:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
					row.meta:SetText("")
				end
				row:Show()
				y = y + ROW_H
			end
			y = y + 6
		else
			sec.title:Hide()
			sec.tick:Hide()
		end
	end
	for i = used + 1, #pool do
		pool[i].rec = nil
		pool[i]:Hide()
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
	return LIST_W, max(1, y)
end

------------------------------------------------------------------------------
-- Sidebar
------------------------------------------------------------------------------

function BG.SidebarHeight()
	local n = sidebar and sidebar.buttons and #sidebar.buttons or 11
	return n * SIDE_ROW
end

local function PaintSidebar()
	if not sidebar or not sidebar.buttons then return end
	local filter = BG.view and BG.view.filter
	local r, g, b = Soul:Accent()
	for i = 1, #sidebar.buttons do
		local button = sidebar.buttons[i]
		local on = (button.key == "all" and not filter) or button.key == filter
		-- An empty category is dimmed (still clickable) so the list shows
		-- at a glance where items are.
		local counts = BG.view and BG.view.catCounts
		local empty = counts and button.key ~= "all" and (counts[button.key] or 0) == 0
		if on then
			button.text:SetTextColor(r, g, b)
			button.mark:SetColorTexture(r, g, b, 1)
			button.mark:Show()
		elseif button.hovered then
			button.text:SetTextColor(1, 1, 1)
			button.mark:Hide()
		elseif empty then
			button.text:SetTextColor(0.38, 0.38, 0.42)
			button.mark:Hide()
		else
			button.text:SetTextColor(0.75, 0.75, 0.78)
			button.mark:Hide()
		end
	end
end

local function Panel(name, title)
	local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetSize(300, 340)
	frame:SetPoint("CENTER")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	frame:SetBackdropColor(UI.C.panel[1], UI.C.panel[2], UI.C.panel[3], 0.97)
	UI.Edge(frame, 1, 1, 1, 0.1)
	local head = UI.Text(frame, 16, UI.C.text)
	head:SetPoint("TOPLEFT", 14, -12)
	head:SetText(title)
	local close = UI.IconButton(frame, "close", 22, function() frame:Hide() end)
	close:SetPoint("TOPRIGHT", -8, -8)
	local text = frame:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(text, 12)
	text:SetPoint("TOPLEFT", 14, -40)
	text:SetPoint("BOTTOMRIGHT", -14, 14)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetWordWrap(true)
	frame.text = text
	frame:Hide()
	if UISpecialFrames then table.insert(UISpecialFrames, name) end
	return frame
end

local function BuildQuick()
	if quick then return end
	quick = CreateFrame("Button", "SoulUIBagQuick", UIParent, "SecureActionButtonTemplate")
	quick:SetSize(22, 22)
	quick:SetFrameStrata("HIGH")
	quick:Hide()
	-- Both: the secure template acts on the one that matches the
	-- ActionButtonUseKeyDown setting.
	quick:RegisterForClicks("AnyUp", "AnyDown")
	quick:SetAttribute("type", "macro")
	quick:SetAttribute("macrotext", "")
	local qtex = quick:CreateTexture(nil, "ARTWORK")
	qtex:SetAllPoints()
	qtex:SetColorTexture(0.15, 0.55, 0.7, 0.9)
	quick:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Use the spell on this item")
		GameTooltip:Show()
	end)
	quick:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function BG.BuildExtras(win)
	sidebar = CreateFrame("Frame", nil, win.body)
	sidebar:SetWidth(BG.SidebarWidth - 8)
	sidebar:EnableMouse(true)
	local buttons = {}
	local function Add(key, label)
		local b = CreateFrame("Button", nil, sidebar)
		b:SetHeight(SIDE_ROW - 2)
		b:SetPoint("TOPLEFT", 0, -(#buttons * SIDE_ROW))
		b:SetPoint("TOPRIGHT", 0, -(#buttons * SIDE_ROW))
		local mark = b:CreateTexture(nil, "ARTWORK")
		mark:SetSize(2, 12)
		mark:SetPoint("LEFT", 0, 0)
		mark:Hide()
		b.mark = mark
		local text = b:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(text, 12)
		text:SetPoint("LEFT", 8, 0)
		text:SetPoint("RIGHT", -2, 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		text:SetText(label)
		b.text = text
		b.key = key
		b:SetScript("OnEnter", function(self) self.hovered = true PaintSidebar() end)
		b:SetScript("OnLeave", function(self) self.hovered = false PaintSidebar() end)
		b:SetScript("OnClick", function()
			local view = BG.view
			if not view then return end
			view.filter = key ~= "all" and key or nil
			if BG.RefreshBags then BG.RefreshBags(false) end
			if BG.ResetScroll then BG.ResetScroll() end
		end)
		buttons[#buttons + 1] = b
	end
	Add("all", "All")
	for i = 1, #BG.CATEGORIES do
		local c = BG.CATEGORIES[i]
		if c.key ~= "free" and c.key ~= "other" then Add(c.key, c.short or c.label) end
	end
	sidebar.buttons = buttons
	BG.PaintSidebar = PaintSidebar
	sidebar:Hide()
	UI.OnAccent(PaintSidebar)

	offlineFrame = Panel("SoulUI_BagsAlts", "Other characters")
	goldFrame = Panel("SoulUI_BagsGold", "Gold")

	splitFrame = CreateFrame("Frame", "SoulUI_BagsSplit", UIParent)
	splitFrame:SetFrameStrata("TOOLTIP")
	splitFrame:SetSize(160, 44)
	splitFrame:EnableMouse(true)
	splitFrame:Hide()
	UI.Fill(splitFrame, { 0.06, 0.06, 0.07, 0.98 })
	UI.Edge(splitFrame, 1, 1, 1, 0.12)
	local box = CreateFrame("EditBox", nil, splitFrame)
	box:SetSize(70, 24)
	box:SetPoint("LEFT", 10, 0)
	-- Not auto focus: an auto-focus box steals the keyboard the moment it
	-- is created. OpenSplit focuses it.
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(4)
	UI.SetFont(box, 14)
	box:SetTextInsets(6, 6, 0, 0)
	UI.Fill(box, { 0, 0, 0, 0.4 })
	local go = UI.Button(splitFrame, "Split", 60, 24, nil, "outline")
	go:SetPoint("LEFT", box, "RIGHT", 8, 0)
	splitFrame.box = box
	if UISpecialFrames then table.insert(UISpecialFrames, "SoulUI_BagsSplit") end
	box:SetScript("OnEscapePressed", function() splitFrame:Hide() end)
	local function DoSplit()
		local rec = splitFrame.rec
		local n = tonumber(box:GetText())
		splitFrame:Hide()
		if not rec or not rec.has or not n or n < 1 then return end
		local count = rec.count or 1
		-- C_Container in 10.x+; the old global is gone.
		if n >= count then
			local pickup = C_Container.PickupContainerItem or PickupContainerItem
			if pickup then pickup(rec.bag, rec.slot) end
		else
			local split = C_Container.SplitContainerItem or SplitContainerItem
			if split then split(rec.bag, rec.slot, n) end
		end
	end
	box:SetScript("OnEnterPressed", DoSplit)
	go:SetScript("OnClick", DoSplit)

	-- A secure button cannot be set up in combat (reload in combat).
	Soul:RunAfterCombat("bags:quick", BuildQuick)

	local function Foot(label, fn)
		local b = CreateFrame("Button", nil, win.footer)
		local text = b:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(text, 12)
		text:SetPoint("CENTER")
		text:SetText(label)
		text:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
		b:SetSize(max(30, (text:GetStringWidth() or 30) + 10), 20)
		b:SetScript("OnEnter", function()
			local r, g, bl = Soul:Accent()
			text:SetTextColor(r, g, bl)
		end)
		b:SetScript("OnLeave", function() text:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3]) end)
		b:SetScript("OnClick", fn)
		footButtons[#footButtons + 1] = b
		return b
	end
	footButtons.alts = Foot("Alts", function() BG.ShowOffline() end)
	footButtons.gold = Foot("History", function() BG.ShowGold() end)
end

-- The last footer button showing, so Sell junk sits after it.
function BG.FootEnd()
	local last
	for i = 1, #footButtons do
		if footButtons[i]:IsShown() then last = footButtons[i] end
	end
	return last
end

function BG.ApplyExtras()
	local db = DB()
	if sidebar then
		local top = BG.HEADER + (db.bagBar and BG.BAGBAR or 0) + 6
		sidebar:ClearAllPoints()
		sidebar:SetPoint("TOPLEFT", BG.win.body, "TOPLEFT", 8, -top)
		sidebar:SetHeight(BG.SidebarHeight())
		sidebar:SetShown(db.sidebar and db.style ~= "bags" and true or false)
	end
	if listRows and db.style ~= "list" then
		for i = 1, #listRows do
			listRows[i].rec = nil
			listRows[i]:Hide()
		end
	end
	PaintSidebar()
	if footButtons.alts then
		footButtons.alts:SetShown(db.offline and true or false)
		footButtons.gold:SetShown(db.goldHistory and true or false)
		local prev = BG.footerFree
		for i = 1, #footButtons do
			local b = footButtons[i]
			if b:IsShown() and prev then
				b:ClearAllPoints()
				b:SetPoint("LEFT", prev, "RIGHT", 12, 0)
				prev = b
			end
		end
	end
end

function BG.TogglePin(rec)
	if not rec or type(rec.itemID) ~= "number" or issecret(rec.itemID) then return end
	local db = DB()
	if type(db.pins) ~= "table" then db.pins = {} end
	if db.pins[rec.itemID] then db.pins[rec.itemID] = nil else db.pins[rec.itemID] = true end
	if BG.RefreshBags then BG.RefreshBags(false) end
end

function BG.OpenSplit(rec)
	local db = DB()
	if not db.splitStack or not rec or not rec.has or (rec.count or 1) < 2 then return end
	if not splitFrame then return end
	splitFrame.rec = rec
	splitFrame:SetScale(rec.btn:GetEffectiveScale() / UIParent:GetEffectiveScale())
	splitFrame.box:SetText(tostring(floor((rec.count or 2) / 2)))
	splitFrame:ClearAllPoints()
	splitFrame:SetPoint("BOTTOMLEFT", rec.btn, "TOPLEFT", 0, 4)
	splitFrame:Show()
	splitFrame.box:SetFocus()
	splitFrame.box:HighlightText()
end

function BG.HideQuick()
	if quick and quick:IsShown() and not InCombatLockdown() then quick:Hide() end
end

function BG.HoverItem(rec)
	local db = DB()
	if not quick or InCombatLockdown() then return end
	if not db.quickAction or not rec or not rec.has or not rec.btn then quick:Hide() return end
	local spellID = db.quickSpell or 13262
	if IsPlayerSpell and not IsPlayerSpell(spellID) then quick:Hide() return end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if type(name) ~= "string" or issecret(name) then quick:Hide() return end
	quick:SetAttribute("macrotext", "/cast " .. name .. "\n/use " .. rec.bag .. " " .. rec.slot)
	quick:SetScale(rec.btn:GetEffectiveScale() / UIParent:GetEffectiveScale())
	quick:ClearAllPoints()
	quick:SetPoint("TOPRIGHT", rec.btn, "TOPRIGHT", 2, 2)
	quick:Show()
end

-- What this character carries, read straight from the bags (the window
-- does not have to be open). Runs when the bags close and at logout.
function BG.Snapshot()
	local db = DB()
	if not db.offline then return end
	local store = Account()
	local who = Who()
	if not store or not who then return end
	if type(store.offline) ~= "table" then store.offline = {} end
	local items = {}
	local bags = BG.MAIN_BAGS
	for i = 1, #bags do
		local bag = bags[i]
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if type(id) == "number" and not issecret(id) then
				local row = items[id]
				if not row then
					local name = info.itemName
					if type(name) ~= "string" or issecret(name) then name = "Item" end
					row = { name = name, count = 0 }
					items[id] = row
				end
				local count = info.stackCount
				row.count = row.count + ((type(count) == "number" and not issecret(count)) and count or 1)
			end
		end
	end
	store.offline[who] = { time = time(), items = items }
end

local function NoteGold()
	local db = DB()
	if not db.goldHistory then return end
	local store = Account()
	local who = Who()
	if not store or not who then return end
	local money = GetMoney()
	if type(money) ~= "number" or issecret(money) then return end
	if type(store.gold) ~= "table" then store.gold = {} end
	local row = store.gold[who]
	if type(row) ~= "table" then row = {} store.gold[who] = row end
	local last = row[#row]
	if last and last.total == money then return end
	local delta = last and (money - (last.total or 0)) or 0
	row[#row + 1] = { time = time(), total = money, delta = delta }
	while #row > 24 do table.remove(row, 1) end
end

function BG.AfterRefresh()
	BG.ApplyExtras()
end

local function ShowPanel(frame)
	frame:SetScale(BG.WindowScale())
	frame:Show()
	frame:Raise()
end

function BG.ShowOffline()
	if not offlineFrame then return end
	BG.Snapshot()
	local store = Account()
	local lines = {}
	local data = store and store.offline or {}
	for who, snap in pairs(data) do
		local n = 0
		if type(snap) == "table" and type(snap.items) == "table" then
			for _, row in pairs(snap.items) do n = n + (row.count or 0) end
		end
		local when = type(snap) == "table" and type(snap.time) == "number" and date("%b %d", snap.time) or ""
		lines[#lines + 1] = who .. "  |cff7a8794" .. BG.Group(n) .. " items  " .. when .. "|r"
	end
	table.sort(lines)
	offlineFrame.text:SetText(#lines > 0 and table.concat(lines, "\n") or "Open your bags on each character once.")
	ShowPanel(offlineFrame)
end

function BG.ShowGold()
	if not goldFrame then return end
	NoteGold()
	local store = Account()
	local who = Who()
	local row = store and who and store.gold and store.gold[who]
	local lines = {}
	if type(row) == "table" then
		for i = #row, max(1, #row - 12), -1 do
			local entry = row[i]
			local delta = entry.delta or 0
			local sign = delta > 0 and "|cff5fd35f+" or (delta < 0 and "|cffe06060-" or "|cff7a8794")
			local when = type(entry.time) == "number" and date("%b %d %H:%M", entry.time) or ""
			lines[#lines + 1] = "|cff7a8794" .. when .. "|r   " .. sign .. BG.FormatMoney(delta) .. "|r   " .. BG.FormatMoney(entry.total or 0)
		end
	end
	goldFrame.text:SetText(#lines > 0 and table.concat(lines, "\n") or "Gold changes show here after the next one.")
	ShowPanel(goldFrame)
end

function BG.StartExtras()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_MONEY")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_LOGOUT")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_MONEY" then
			NoteGold()
		elseif event == "PLAYER_LOGOUT" then
			if BG.Active() then pcall(BG.Snapshot) end
		elseif quick and quick:IsShown() then
			-- REGEN_DISABLED fires just before the lockdown starts.
			quick:Hide()
		end
	end)
	NoteGold()
end
