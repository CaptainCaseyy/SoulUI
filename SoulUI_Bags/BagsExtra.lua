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

local sidebar, listRows, splitFrame, quick, offlineFrame, goldFrame
local hovered

local function Account()
	local root = Soul.db and Soul.db.account
	if type(root) ~= "table" then return nil end
	if type(root.bags) ~= "table" then root.bags = {} end
	return root.bags
end

local function Who()
	local name, realm = UnitName("player"), GetRealmName()
	if type(name) ~= "string" or issecret(name) then return nil end
	if type(realm) ~= "string" or realm == "" then realm = "Realm" end
	return name .. "-" .. realm
end

------------------------------------------------------------------------------
-- List rows. One line per item: icon, name, count, item level.
------------------------------------------------------------------------------

function BG.PackList(view, titles, sortFn)
	local db = DB()
	local rowH = 26
	local width = 360
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
	local function Row()
		used = used + 1
		local row = pool[used]
		if row then return row end
		row = CreateFrame("Button", nil, content)
		row:SetHeight(rowH - 2)
		row:RegisterForClicks("AnyUp")
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(20, 20)
		icon:SetPoint("LEFT", 2, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.icon = icon
		local name = row:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(name, 13)
		name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
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
			if not rec or not rec.btn then return end
			if button == "LeftButton" and IsAltKeyDown() then
				BG.TogglePin(rec)
				return
			end
			rec.btn:Click(button)
		end)
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
		pool[used] = row
		return row
	end

	for i = 1, #view.order do
		local sec = view.order[i]
		local n = sec.n
		local list = sec.list
		if n > 0 then
			if n > 1 and sortFn then table.sort(list, sortFn) end
			if titles and sec.label then
				sec.tick:ClearAllPoints()
				sec.tick:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y - 4)
				sec.tick:SetSize(2, 12)
				sec.tick:Show()
				sec.title:ClearAllPoints()
				sec.title:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
				sec.title:SetWidth(width - 8)
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
				rec.btn:Hide()
				local row = Row()
				row.rec = rec
				row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
				local icon = rec.btn.icon
				row.icon:SetTexture(icon and icon:GetTexture())
				local color = BG.QCOLOR and BG.QCOLOR[rec.quality or 1] or { 1, 1, 1 }
				row.name:SetText(rec.name or "")
				row.name:SetTextColor(color[1], color[2], color[3])
				local bits = ""
				if (rec.count or 1) > 1 then bits = "x" .. rec.count end
				if rec.level and rec.level > 1 then
					bits = (bits ~= "" and (bits .. "  ") or "") .. rec.level
				end
				row.meta:SetText(bits)
				row:Show()
				y = y + rowH
			end
			y = y + 6
		else
			sec.title:Hide()
			sec.tick:Hide()
		end
	end
	for i = used + 1, #pool do pool[i]:Hide() end
	for _, list in pairs(view.recs) do
		for slot = 1, #list do
			local rec = list[slot]
			if rec.pass ~= pass and rec.btn:IsShown() then rec.btn:Hide() end
		end
	end
	return width, max(1, y)
end

------------------------------------------------------------------------------
-- Sidebar
------------------------------------------------------------------------------

function BG.BuildExtras(win)
	sidebar = CreateFrame("Frame", nil, win.body)
	sidebar:SetPoint("TOPLEFT", 8, -46)
	sidebar:SetPoint("BOTTOMLEFT", 8, 40)
	sidebar:SetWidth(BG.SidebarWidth - 8)
	sidebar:EnableMouse(true)
	local buttons = {}
	local function Add(key, label)
		local b = CreateFrame("Button", nil, sidebar)
		b:SetHeight(22)
		b:SetPoint("TOPLEFT", 0, -((#buttons) * 24))
		b:SetPoint("TOPRIGHT", 0, -((#buttons) * 24))
		local text = b:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(text, 12)
		text:SetPoint("LEFT", 8, 0)
		text:SetText(label)
		b.text = text
		b.key = key
		b:SetScript("OnClick", function()
			local view = BG.view
			if not view then return end
			view.filter = key ~= "all" and key or nil
			if BG.RefreshBags then BG.RefreshBags(true) end
		end)
		buttons[#buttons + 1] = b
	end
	Add("all", "All")
	for i = 1, #BG.CATEGORIES do
		local c = BG.CATEGORIES[i]
		if c.key ~= "free" and c.key ~= "other" then Add(c.key, c.label) end
	end
	sidebar.buttons = buttons
	sidebar:Hide()

	local function Panel(title)
		local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		frame:SetFrameStrata("DIALOG")
		frame:SetSize(280, 320)
		frame:SetPoint("CENTER")
		frame:EnableMouse(true)
		frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
		frame:SetBackdropColor(0.06, 0.06, 0.07, 0.97)
		local head = frame:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(head, 16)
		head:SetPoint("TOPLEFT", 14, -12)
		head:SetText(title)
		local close = CreateFrame("Button", nil, frame)
		close:SetSize(22, 22)
		close:SetPoint("TOPRIGHT", -8, -8)
		close:SetScript("OnClick", function() frame:Hide() end)
		local label = close:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(label, 14)
		label:SetAllPoints()
		label:SetText("x")
		frame:Hide()
		return frame, head
	end

	offlineFrame = Panel("Other characters")
	offlineFrame.text = offlineFrame:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(offlineFrame.text, 12)
	offlineFrame.text:SetPoint("TOPLEFT", 14, -40)
	offlineFrame.text:SetPoint("BOTTOMRIGHT", -14, 14)
	offlineFrame.text:SetJustifyH("LEFT")
	offlineFrame.text:SetJustifyV("TOP")
	offlineFrame.text:SetWordWrap(true)

	goldFrame = Panel("Gold")
	goldFrame.text = goldFrame:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(goldFrame.text, 12)
	goldFrame.text:SetPoint("TOPLEFT", 14, -40)
	goldFrame.text:SetPoint("BOTTOMRIGHT", -14, 14)
	goldFrame.text:SetJustifyH("LEFT")
	goldFrame.text:SetJustifyV("TOP")

	splitFrame = CreateFrame("Frame", nil, UIParent)
	splitFrame:SetFrameStrata("TOOLTIP")
	splitFrame:SetSize(160, 64)
	splitFrame:EnableMouse(true)
	UI.Fill(splitFrame, { 0.06, 0.06, 0.07, 0.98 })
	local box = CreateFrame("EditBox", nil, splitFrame)
	box:SetSize(70, 24)
	box:SetPoint("LEFT", 12, 0)
	box:SetAutoFocus(true)
	box:SetNumeric(true)
	box:SetMaxLetters(4)
	UI.SetFont(box, 14)
	box:SetTextInsets(6, 6, 0, 0)
	UI.Fill(box, { 0, 0, 0, 0.4 })
	local go = CreateFrame("Button", nil, splitFrame)
	go:SetSize(60, 24)
	go:SetPoint("LEFT", box, "RIGHT", 8, 0)
	local goText = go:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(goText, 12)
	goText:SetAllPoints()
	goText:SetText("Split")
	splitFrame.box = box
	splitFrame:Hide()
	box:SetScript("OnEscapePressed", function() splitFrame:Hide() end)
	local function DoSplit()
		local rec = splitFrame.rec
		local n = tonumber(box:GetText())
		splitFrame:Hide()
		if not rec or not n or n < 1 or InCombatLockdown() then return end
		if SplitContainerItem then SplitContainerItem(rec.bag, rec.slot, n) end
	end
	box:SetScript("OnEnterPressed", DoSplit)
	go:SetScript("OnClick", DoSplit)

	quick = CreateFrame("Button", "SoulUIBagQuick", UIParent, "SecureActionButtonTemplate")
	quick:SetSize(22, 22)
	quick:SetFrameStrata("HIGH")
	quick:Hide()
	quick:RegisterForClicks("AnyUp")
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

	local function Foot(label, x, fn)
		local b = CreateFrame("Button", nil, win.footer)
		b:SetSize(52, 18)
		b:SetPoint("CENTER", win.footer, "CENTER", x, 0)
		local text = b:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(text, 11)
		text:SetAllPoints()
		text:SetText(label)
		b:SetScript("OnClick", fn)
	end
	Foot("Alts", -40, function() BG.ShowOffline() end)
	Foot("History", 28, function() BG.ShowGold() end)
end

function BG.ApplyExtras()
	local db = DB()
	if sidebar then sidebar:SetShown(db.sidebar and db.style ~= "bags" and true or false) end
	if listRows and db.style ~= "list" then
		for i = 1, #listRows do listRows[i]:Hide() end
	end
	if sidebar and sidebar.buttons then
		local filter = BG.view and BG.view.filter
		for i = 1, #sidebar.buttons do
			local b = sidebar.buttons[i]
			local on = (b.key == "all" and not filter) or b.key == filter
			local r, g, bch = Soul:Accent()
			if on then
				b.text:SetTextColor(r, g, bch)
			else
				b.text:SetTextColor(0.75, 0.75, 0.78)
			end
		end
	end
end

function BG.TogglePin(rec)
	if not rec or type(rec.itemID) ~= "number" or issecret(rec.itemID) then return end
	local db = DB()
	if type(db.pins) ~= "table" then db.pins = {} end
	if db.pins[rec.itemID] then db.pins[rec.itemID] = nil else db.pins[rec.itemID] = true end
	if BG.RefreshBags then BG.RefreshBags(true) end
end

function BG.OpenSplit(rec)
	local db = DB()
	if not db.splitStack or not rec or not rec.has or (rec.count or 1) < 2 then return end
	if not splitFrame then return end
	splitFrame.rec = rec
	splitFrame.box:SetText("1")
	splitFrame:ClearAllPoints()
	splitFrame:SetPoint("BOTTOMLEFT", rec.btn, "TOPLEFT", 0, 4)
	splitFrame:Show()
	splitFrame.box:SetFocus()
end

function BG.HoverItem(rec)
	hovered = rec
	local db = DB()
	if not quick or not db.quickAction or InCombatLockdown() then
		if quick and not InCombatLockdown() then quick:Hide() end
		return
	end
	if not rec or not rec.has or not rec.btn then quick:Hide() return end
	local spellID = db.quickSpell or 13262
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if type(name) ~= "string" or issecret(name) then quick:Hide() return end
	quick:SetAttribute("macrotext", "/cast " .. name .. "\n/use " .. rec.bag .. " " .. rec.slot)
	quick:ClearAllPoints()
	quick:SetPoint("TOPRIGHT", rec.btn, "TOPRIGHT", 2, 2)
	quick:Show()
end

local function Snapshot()
	local db = DB()
	if not db.offline then return end
	local store = Account()
	local who = Who()
	local view = BG.view
	if not store or not who or not view then return end
	if type(store.offline) ~= "table" then store.offline = {} end
	local items = {}
	for _, list in pairs(view.recs) do
		for slot = 1, #list do
			local rec = list[slot]
			if rec.has and type(rec.itemID) == "number" and not issecret(rec.itemID) then
				local name = rec.name
				if type(name) ~= "string" or issecret(name) then name = "Item" end
				local row = items[rec.itemID]
				if not row then
					row = { name = name, count = 0 }
					items[rec.itemID] = row
				end
				row.count = row.count + (type(rec.count) == "number" and rec.count or 1)
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
	local delta = last and (money - last.total) or 0
	row[#row + 1] = { time = time(), total = money, delta = delta }
	if #row > 24 then table.remove(row, 1) end
end

function BG.AfterRefresh()
	Snapshot()
	NoteGold()
	BG.ApplyExtras()
end

function BG.ShowOffline()
	if not offlineFrame then return end
	local store = Account()
	local lines = {}
	local data = store and store.offline or {}
	for who, snap in pairs(data) do
		local n = 0
		if type(snap.items) == "table" then
			for _, row in pairs(snap.items) do n = n + (row.count or 0) end
		end
		lines[#lines + 1] = who .. "  " .. n .. " items"
	end
	table.sort(lines)
	offlineFrame.text:SetText(#lines > 0 and table.concat(lines, "\n") or "Open your bags on each character once.")
	offlineFrame:Show()
end

function BG.ShowGold()
	if not goldFrame then return end
	local store = Account()
	local who = Who()
	local row = store and who and store.gold and store.gold[who]
	local lines = {}
	if type(row) == "table" then
		for i = #row, math.max(1, #row - 12), -1 do
			local entry = row[i]
			local sign = (entry.delta or 0) >= 0 and "+" or ""
			lines[#lines + 1] = sign .. floor((entry.delta or 0) / 10000) .. "g    " .. floor((entry.total or 0) / 10000) .. "g"
		end
	end
	goldFrame.text:SetText(#lines > 0 and table.concat(lines, "\n") or "Gold changes show here after the next one.")
	goldFrame:Show()
end

function BG.StartExtras()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_MONEY")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_MONEY" then
			NoteGold()
		elseif quick and not InCombatLockdown() then
			quick:Hide()
		end
	end)
end
