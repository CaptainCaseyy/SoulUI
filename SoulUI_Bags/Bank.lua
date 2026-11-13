if SoulUI_Blocked or not SoulUI then return end

-- Bank and warband bank (0.9.0). The 12.x bank is a set of purchased tabs,
-- each one a container (Enum.BagIndex.CharacterBankTab_N / AccountBankTab_N)
-- listed by C_Bank.FetchPurchasedBankTabData. This window shows one tab at a
-- time in its physical slot order, with the same slot buttons as the bags.
--
-- Blizzard's BankFrame stays open (the bank interaction lives on it) but is
-- parked under a hidden parent. It is never Hide()n: that would end the
-- interaction. Closing our window calls C_Bank.CloseBankFrame(). "Blizzard
-- bank" hands this visit back to the stock frame (for buying tabs and tab
-- settings, which this window does not do).
--
-- Known limit: a right-click on a bag item deposits into the bank type
-- Blizzard's frame has active (the character bank, or the warband bank at a
-- warband-only banker). Our Bank / Warband switch does not change that, so
-- the warband side offers "Deposit warbound" instead.

local Soul = SoulUI
local UI = Soul.UI
local BG = Soul:GetModule("Bags")
if not BG then return end

local C_Bank, C_Container = C_Bank, C_Container
local max = math.max

local Bank = {}
BG.Bank = Bank

local CHAR = Enum and Enum.BankType and Enum.BankType.Character
local ACCOUNT = Enum and Enum.BankType and Enum.BankType.Account
local supported = C_Bank and C_Bank.FetchPurchasedBankTabData and CHAR ~= nil and ACCOUNT ~= nil and true or false
Bank.supported = supported

local TABS = 46
local MAX_TABS = 8

local win, view
local typeButtons = {}
local tabButtons = {}
local tabName, emptyNote, footerFree, footerMoney, depositButton, blizzButton, sortButton
local bankType = CHAR
local selected = {}
local NO_TABS = {}
local tabs = NO_TABS
local atBank = false
local warbandOnly = false
local handedToBlizzard = false

local function DB() return BG.DB() end

local function Fallback()
	return { point = "TOPLEFT", relPoint = "TOPLEFT", x = 40, y = -120 }
end

local function Active()
	return supported and BG.Active() and DB().bank ~= false
end

local function ParkBank(on)
	if not BankFrame then return end
	Soul:RunAfterCombat("bank:park", function() BG.Park(BankFrame, on) end)
end

local function Interacting(kind)
	local manager = C_PlayerInteractionManager
	if not manager or not manager.IsInteractingWithNpcOfType or not Enum.PlayerInteractionType then return false end
	local value = Enum.PlayerInteractionType[kind]
	if value == nil then return false end
	return manager.IsInteractingWithNpcOfType(value) and true or false
end

local function CanView(kind)
	if C_Bank.CanViewBank then
		local ok, can = pcall(C_Bank.CanViewBank, kind)
		if ok then return can and true or false end
	end
	return true
end

------------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------------

local function Discover()
	tabs = C_Bank.FetchPurchasedBankTabData(bankType) or NO_TABS
	local sel = selected[bankType]
	local found
	for i = 1, #tabs do
		if tabs[i].ID == sel then found = tabs[i] end
	end
	if not found then
		found = tabs[1]
		selected[bankType] = found and found.ID or nil
	end
	local bags = view.bags
	for i = #bags, 1, -1 do bags[i] = nil end
	if found then bags[1] = found.ID end
	return found
end

local function PaintTypes()
	local r, g, b = Soul:Accent()
	for i = 1, #typeButtons do
		local button = typeButtons[i]
		local on = button.kind == bankType
		button.face:SetColorTexture(on and r or 1, on and g or 1, on and b or 1, on and 0.14 or (button.hovered and 0.05 or 0))
		button.edge:SetColor(on and r or 1, on and g or 1, on and b or 1, on and 0.9 or 0.12)
		if on then
			button.text:SetTextColor(1, 1, 1)
		else
			button.text:SetTextColor(UI.C.dim[1], UI.C.dim[2], UI.C.dim[3])
		end
	end
end

local function PaintTabs()
	local r, g, b = Soul:Accent()
	local current = selected[bankType]
	local name
	for i = 1, MAX_TABS do
		local button = tabButtons[i]
		local tab = tabs[i]
		if tab then
			button.tabID = tab.ID
			button.tabTitle = tab.name
			button.icon:SetTexture(tab.icon or 134400)
			local on = tab.ID == current
			if on then
				button.edge:SetColor(r, g, b, 1)
				name = tab.name
			else
				button.edge:SetColor(1, 1, 1, 0.14)
			end
			button.icon:SetDesaturated(not on)
			button.icon:SetAlpha(on and 1 or 0.7)
			button:Show()
		else
			button.tabID = nil
			button:Hide()
		end
	end
	tabName:ClearAllPoints()
	local shown = math.min(#tabs, MAX_TABS)
	tabName:SetPoint("LEFT", win.tabs, "LEFT", 12 + shown * 40 + 6, 0)
	if name and name ~= "" then
		tabName:SetText(name)
	elseif #tabs > 0 then
		tabName:SetText("Tab")
	else
		tabName:SetText("")
	end
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

local function UpdateFooter()
	local bag = view.bags[1]
	local free = bag and C_Container.GetContainerNumFreeSlots(bag) or 0
	local total = bag and C_Container.GetContainerNumSlots(bag) or 0
	footerFree:SetFormattedText("%d free  |cff7a8794·  %d slots|r", free, total)
	if bankType == ACCOUNT and C_Bank.FetchDepositedMoney then
		local ok, money = pcall(C_Bank.FetchDepositedMoney, ACCOUNT)
		footerMoney:SetText("|cff7a8794Warband|r  " .. BG.FormatMoney(ok and money or 0))
	else
		footerMoney:SetText(BG.FormatMoney(GetMoney()))
	end
	depositButton:SetLabel(bankType == ACCOUNT and "Deposit warbound" or "Deposit reagents")
	depositButton:SetShown(C_Bank.AutoDepositItemsIntoBank ~= nil and #tabs > 0)
end

Bank.UpdateFooter = UpdateFooter

local function Layout()
	if not win then return end
	if not BG.CanLayout() then
		Soul:RunAfterCombat("bank:layout", Layout)
		return
	end
	local db = DB()
	BG.ResetSections(view)
	local bag = view.bags[1]
	if bag then
		local list = view.recs[bag]
		for slot = 1, (view.numSlots[bag] or 0) do
			local rec = list[slot]
			rec.freeCount = nil
			BG.Add(view, "tab", rec)
		end
	end
	local cols = db.bankColumns or 14
	if cols < 4 then cols = 4 end
	local width, height = BG.Pack(view, cols, false, BG.ByBagSlot)
	local pad = db.padding or 12
	local top = BG.HEADER + TABS + pad
	if not bag then
		emptyNote:Show()
		width = max(width, emptyNote:GetStringWidth() or 200)
		height = 40
	else
		emptyNote:Hide()
	end
	view.content:ClearAllPoints()
	view.content:SetPoint("TOPLEFT", win.body, "TOPLEFT", pad, -top)
	view.content:SetSize(max(1, width), max(1, height))
	win:SetSize(max(BG.MIN_WIDTH + 60, width + pad * 2), top + max(1, height) + pad + BG.FOOTER)
	PaintTypes()
	PaintTabs()
	UpdateFooter()
end

function Bank.Refresh(full)
	if not win then return end
	BG.ReadView(view, full)
	Layout()
end

function Bank.IsShown()
	return win and win:IsShown() or false
end

function Bank.MarkDirty(bag)
	if view then view.dirty[bag] = true end
end

function Bank.MarkAll()
	if view then view.dirtyAll = true end
end

function Bank.Rec(bag, slot)
	local list = view and view.recs[bag]
	return list and list[slot]
end

local function SetType(kind)
	if kind == bankType then return end
	bankType = kind
	Discover()
	view.dirtyAll = true
	Bank.Refresh(true)
end

------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------

local function TypeButton(label, kind)
	local button = CreateFrame("Button", nil, win.header)
	local text = UI.Text(button, 13, UI.C.dim, "CENTER")
	text:SetPoint("CENTER")
	text:SetText(label)
	button:SetSize(max(70, (text:GetStringWidth() or 50) + 24), 26)
	button.face = UI.Fill(button, { 1, 1, 1, 0 })
	button.edge = UI.Edge(button, 1, 1, 1, 0.12)
	button.text = text
	button.kind = kind
	button:SetScript("OnEnter", function(self) self.hovered = true PaintTypes() end)
	button:SetScript("OnLeave", function(self) self.hovered = false PaintTypes() end)
	button:SetScript("OnClick", function() SetType(kind) end)
	typeButtons[#typeButtons + 1] = button
	return button
end

local function Build()
	win = BG.NewWindow("SoulUI_Bank", "Bank", "Bags:bank", Fallback)
	Bank.win = win
	win.close:SetScript("OnClick", function() win:CloseAnimated() end)
	if UISpecialFrames then table.insert(UISpecialFrames, "SoulUI_Bank") end
	view = BG.NewView("bank", win)
	BG.AddSection(view, "tab", nil, BG.ByBagSlot)

	local charButton = TypeButton("Bank", CHAR)
	charButton:SetPoint("LEFT", win.title, "RIGHT", 16, 0)
	local warButton = TypeButton("Warband", ACCOUNT)
	warButton:SetPoint("LEFT", charButton, "RIGHT", 6, 0)
	UI.OnAccent(PaintTypes)

	sortButton = BG.GlyphButton(win.header, 26, "bars", "Clean up",
		"Sorts this bank (the game's own sort).", function()
			if InCombatLockdown() then return end
			if bankType == ACCOUNT and C_Container.SortAccountBankBags then
				C_Container.SortAccountBankBags()
			elseif C_Container.SortBankBags then
				C_Container.SortBankBags()
			end
		end)
	sortButton:SetPoint("RIGHT", win.close, "LEFT", -6, 0)

	local strip = CreateFrame("Frame", nil, win.body)
	strip:SetPoint("TOPLEFT", win.header, "BOTTOMLEFT")
	strip:SetPoint("TOPRIGHT", win.header, "BOTTOMRIGHT")
	strip:SetHeight(TABS)
	local rule = strip:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1)
	rule:SetColorTexture(UI.C.line[1], UI.C.line[2], UI.C.line[3], UI.C.line[4])
	win.tabs = strip
	for i = 1, MAX_TABS do
		local button = CreateFrame("Button", nil, strip)
		button:SetSize(32, 32)
		button:SetPoint("LEFT", 12 + (i - 1) * 40, 0)
		UI.Fill(button, { 0, 0, 0, 0.42 })
		button.edge = UI.Edge(button, 1, 1, 1, 0.14)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetPoint("TOPLEFT", 1, -1)
		button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button:SetScript("OnClick", function(self)
			if not self.tabID then return end
			selected[bankType] = self.tabID
			Discover()
			Bank.Refresh(true)
		end)
		UI.Tip(button, nil, function() return button.tabTitle end)
		button:Hide()
		tabButtons[i] = button
	end
	tabName = UI.Text(strip, 14, UI.C.text)

	blizzButton = UI.Button(strip, "Blizzard bank", 112, 24, function()
		-- Hand this visit to the stock frame (buy tabs, tab settings).
		handedToBlizzard = true
		ParkBank(false)
		win:Hide()
	end, "ghost")
	blizzButton:SetPoint("RIGHT", -12, 0)
	UI.Tip(blizzButton, "Blizzard bank", "Shows Blizzard's bank window for this visit, to buy tabs or change tab settings. SoulUI's bank is back next time.")

	emptyNote = UI.Text(win.body, 13, UI.C.dim)
	emptyNote:SetPoint("TOPLEFT", win.body, "TOPLEFT", 16, -(BG.HEADER + TABS + 20))
	emptyNote:SetText("No bank tabs bought yet. Use Blizzard bank to buy one.")
	emptyNote:Hide()

	local footer = win.footer
	footerFree = UI.Text(footer, 13, UI.C.dim)
	footerFree:SetPoint("LEFT", 16, 0)
	depositButton = UI.Button(footer, "Deposit reagents", 128, 22, function()
		if C_Bank.AutoDepositItemsIntoBank then C_Bank.AutoDepositItemsIntoBank(bankType) end
	end, "outline")
	depositButton:SetPoint("LEFT", footerFree, "RIGHT", 14, 0)
	footerMoney = UI.Text(footer, 14, UI.C.text, "RIGHT")
	footerMoney:SetPoint("RIGHT", -16, 0)

	win:HookScript("OnHide", function()
		-- Closing our window ends the bank visit, unless it was handed to
		-- Blizzard's frame or the visit already ended.
		if atBank and not handedToBlizzard and C_Bank.CloseBankFrame then
			C_Bank.CloseBankFrame()
		end
	end)
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local function OnOpened()
	atBank = true
	handedToBlizzard = false
	if not Active() then return end
	ParkBank(true)
	warbandOnly = Interacting("AccountBanker")
	if warbandOnly or not CanView(CHAR) then
		bankType = ACCOUNT
	elseif bankType == ACCOUNT and not CanView(ACCOUNT) then
		bankType = CHAR
	end
	typeButtons[1]:SetShown(not warbandOnly and CanView(CHAR))
	typeButtons[2]:SetShown(CanView(ACCOUNT))
	win:SetScale(BG.WindowScale())
	Soul:Place(win, "Bags:bank", Fallback())
	Discover()
	view.dirtyAll = true
	Bank.Refresh(true)
	win:OpenAnimated()
	win:Raise()
	if not BG:IsOpen() then BG:Open("bank") end
	-- Tab contents can arrive a moment after the open event.
	view.dirtyAll = true
	BG.ScheduleRefresh(0.15)
end

local function OnClosed()
	atBank = false
	if win and win:IsShown() then win:CloseAnimated() end
	if BG.openedBy == "bank" or (BankFrame and BG.openedBy == BankFrame) then BG:Close() end
	if handedToBlizzard then
		handedToBlizzard = false
		if Active() then ParkBank(true) end
	end
end

local function OnEvent(_, event)
	if event == "BANKFRAME_OPENED" then
		OnOpened()
	elseif event == "BANKFRAME_CLOSED" then
		OnClosed()
	elseif event == "BANK_TABS_CHANGED" or event == "BANK_TAB_SETTINGS_UPDATED" then
		if win and win:IsShown() then
			Discover()
			view.dirtyAll = true
			BG.ScheduleRefresh(0.1)
		end
	elseif event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" or event == "PLAYERBANKSLOTS_CHANGED" then
		if view then view.dirtyAll = true end
		BG.ScheduleRefresh()
	elseif event == "ACCOUNT_MONEY" then
		if win and win:IsShown() then UpdateFooter() end
	end
end

local EVENTS = {
	"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED",
	"PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "PLAYERBANKSLOTS_CHANGED", "ACCOUNT_MONEY",
}

function Bank.Enable()
	if not supported or win then return end
	Build()
	for i = 1, #EVENTS do
		-- pcall: an event name the client does not know raises an error.
		pcall(BG.RegisterEvent, BG, EVENTS[i], OnEvent)
	end
	Soul:RegisterMover({
		key = "Bags:bank",
		label = "Bank",
		page = "bags",
		getFrame = function() return win end,
		fallback = Fallback,
		isHidden = function() return not BG.Active() end,
		getEnabled = function() return DB().bank ~= false end,
		setEnabled = function(on)
			DB().bank = on and true or false
			BG:Apply()
		end,
	})
	win:SetScale(BG.WindowScale())
	Soul:Place(win, "Bags:bank", Fallback())
	if Active() then ParkBank(true) end
end

function Bank.Apply()
	if not win then return end
	win:SetScale(BG.WindowScale())
	Soul:Place(win, "Bags:bank", Fallback())
	win:ApplyLook()
	for _, list in pairs(view.recs) do
		for slot = 1, #list do BG.StyleRec(list[slot]) end
	end
	if Active() then
		if not handedToBlizzard then ParkBank(true) end
		if win:IsShown() then Bank.Refresh(true) end
	else
		ParkBank(false)
		if win:IsShown() then
			-- Turned off at the bank: hand the open visit to Blizzard's frame.
			handedToBlizzard = atBank
			win:Hide()
		end
	end
end
