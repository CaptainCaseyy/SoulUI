if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI
local DM = Soul:NewModule("DamageMeters", "SoulUI_DamageMeters")

local MAX_ROWS = 20
local MAX_SPELLS = 10
local WINDOWS = 3

local TYPES = {
	{ key = "damage", label = "Damage Done", enum = "DamageDone" },
	{ key = "healing", label = "Healing Done", enum = "HealingDone" },
	{ key = "taken", label = "Damage Taken", enum = "DamageTaken" },
	{ key = "avoidable", label = "Avoidable", enum = "AvoidableDamageTaken" },
	{ key = "enemy", label = "Enemy Damage", enum = "EnemyDamageTaken" },
	{ key = "interrupts", label = "Interrupts", enum = "Interrupts" },
	{ key = "dispels", label = "Dispels", enum = "Dispels" },
	{ key = "deaths", label = "Deaths", enum = "Deaths" },
}

local SEGMENTS = {
	{ key = "current", label = "Current", enum = "Current" },
	{ key = "overall", label = "Overall", enum = "Overall" },
}

local RAID_UNITS = {}
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
for i = 1, 40 do
	RAID_UNITS[i] = "raid" .. i
end

local function DB()
	return Soul:ModuleDB("DamageMeters")
end

local function TypeInfo(key)
	for i = 1, #TYPES do
		if TYPES[i].key == key then return TYPES[i], i end
	end
	return TYPES[1], 1
end

local function SegmentInfo(key)
	for i = 1, #SEGMENTS do
		if SEGMENTS[i].key == key then return SEGMENTS[i], i end
	end
	return SEGMENTS[1], 1
end

local function EnumValue(enumTable, name)
	local value = enumTable and enumTable[name]
	if type(value) == "number" then return value end
	return nil
end

local function Readable(value)
	if type(value) ~= "table" then return false end
	if issecrettable and issecrettable(value) then return false end
	if canaccesstable and not canaccesstable(value) then return false end
	return true
end

local function Fighting(unit)
	if not UnitExists(unit) then return false end
	local ok, value = pcall(UnitAffectingCombat, unit)
	if not ok or Soul.Secret.IsSecret(value) then return false end
	return value and true or false
end

local function GroupInCombat()
	if Fighting("player") then return true end
	if IsInRaid() then
		local count = GetNumGroupMembers()
		if type(count) ~= "number" then count = 0 end
		if count > 40 then count = 40 end
		for i = 1, count do
			if Fighting(RAID_UNITS[i]) then return true end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			if Fighting(PARTY_UNITS[i]) then return true end
		end
	end
	return false
end

local function ClockText(secs)
	local seconds = math.floor(secs % 60)
	local minutes = math.floor(secs / 60) % 60
	local hours = math.floor(secs / 3600)
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds)
	end
	return string.format("%d:%02d", minutes, seconds)
end

function DM:ReadDuration(which)
	if not C_DamageMeter or not C_DamageMeter.GetSessionDurationSeconds then return nil end
	local enumName = which == "overall" and "Overall" or "Current"
	local segment = EnumValue(Enum and Enum.DamageMeterSessionType, enumName)
	if segment == nil then return nil end
	local ok, secs = pcall(C_DamageMeter.GetSessionDurationSeconds, segment)
	if not ok or Soul.Secret.IsSecret(secs) or type(secs) ~= "number" then return nil end
	-- With no finished session the API has been seen to hand back the client
	-- uptime (a "301:36:13" clock). A real fight is never a day long.
	if secs < 0 or secs > 86400 then return nil end
	return secs
end

function DM:UpdateClocks()
	local current = self:ReadDuration("current")
	local overall = self:ReadDuration("overall")
	if current then self._pinnedCurrent = current end
	if overall then self._pinnedOverall = overall end
	for i = 1, WINDOWS do
		local window = self.windows[i]
		if window then
			local cfg = DB().windows[i]
			local segment = cfg and cfg.segment
			local shown = segment == "overall" and (overall or self._pinnedOverall) or (current or self._pinnedCurrent)
			if shown and not window._breakdown and DB().showClock ~= false then
				window.Clock:SetText(ClockText(shown))
			else
				window.Clock:SetText("")
			end
		end
	end
end

local function Ease(bar, value)
	local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
	if interp then
		bar:SetValue(value, interp)
	else
		bar:SetValue(value)
	end
end

local function ClassColor(class)
	if not Soul.Secret.IsSecret(class) and type(class) == "string" then
		local color = RAID_CLASS_COLORS[class]
		if color then return color.r, color.g, color.b end
	end
	return Soul:Accent()
end

local function PaintRow(row, src, maxAmount, deaths)
	row:Show()
	local r, g, b = ClassColor(src.classFilename)
	row.Bar:SetStatusBarColor(r, g, b)
	if row.Rank then
		local index = row._soulIndex
		if type(index) == "number" then
			row.Rank:SetText(index)
		else
			row.Rank:SetText("")
		end
	end
	if deaths then
		row.Bar:SetMinMaxValues(0, 1)
		row.Bar:SetValue(1)
	elseif Soul.Secret.Present(maxAmount) then
		row.Bar:SetMinMaxValues(0, maxAmount)
		Ease(row.Bar, src.totalAmount)
	end
	local name = src.name
	if not Soul.Secret.IsSecret(name) and type(name) == "string" then
		local dash = name:find("-", 1, true)
		if dash then name = name:sub(1, dash - 1) end
	end
	row.Name:SetText(name or "")
	local total = src.totalAmount
	local perSecond = src.amountPerSecond
	local sessionTotal = row._soulSessionTotal
	if not Soul.Secret.IsSecret(total) and not Soul.Secret.IsSecret(sessionTotal)
		and type(total) == "number" and type(sessionTotal) == "number"
		and sessionTotal > 0 then
		local share = math.floor(total / sessionTotal * 100 + 0.5)
		row.Value:SetFormattedText("%s  %d%%", Soul:Abbrev(total), share)
	else
		row.Value:SetFormattedText("%s (%s)", Soul:Abbrev(total), Soul:Abbrev(perSecond))
	end
	local icon = src.specIconID
	if not Soul.Secret.IsSecret(icon) and type(icon) == "number" and icon > 0 then
		row.Icon:SetTexture(icon)
		row.Icon:Show()
	else
		row.Icon:Hide()
	end
	local mine = src.isLocalPlayer
	if not Soul.Secret.IsSecret(mine) and mine then
		row.Mark:Show()
	else
		row.Mark:Hide()
	end
end

local function HideRows(window)
	for i = 1, MAX_ROWS do
		window.rows[i]:Hide()
	end
end

local function FetchSession(cfg)
	if not C_DamageMeter or not C_DamageMeter.GetCombatSessionFromType then return nil end
	local typeInfo = TypeInfo(cfg.type)
	local segmentInfo = SegmentInfo(cfg.segment)
	local meter = EnumValue(Enum and Enum.DamageMeterType, typeInfo.enum)
	local segment = EnumValue(Enum and Enum.DamageMeterSessionType, segmentInfo.enum)
	if meter == nil or segment == nil then return nil end
	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, segment, meter)
	if not ok or not Readable(session) then return nil end
	return session, meter, segment
end

local function PaintSources(window, cfg)
	local session = FetchSession(cfg)
	if window.Sync then window.Sync(window, cfg) end
	if not session or not Readable(session.combatSources) then
		HideRows(window)
		return
	end
	local sources = session.combatSources
	local deaths = cfg.type == "deaths"
	local limit = cfg and DB().rows or 12
	if limit > MAX_ROWS then limit = MAX_ROWS end
	local maxAmount = session.maxAmount
	local top = sources[1]
	if not Soul.Secret.Present(maxAmount) and top and not Soul.Secret.IsSecret(top) and not (issecrettable and issecrettable(top)) then
		maxAmount = top.totalAmount
	end
	for i = 1, MAX_ROWS do
		local row = window.rows[i]
		local src = sources[i]
		if i <= limit and Soul.Secret.Present(src) and not Soul.Secret.IsSecret(src) then
			row._soulIndex = i
			row._soulSessionTotal = session.totalAmount
			PaintRow(row, src, maxAmount, deaths)
		else
			row:Hide()
		end
	end
end

local function PaintSpells(window, cfg)
	local session, meter, segment = FetchSession(cfg)
	if window.Mode then window.Mode.Label:SetText("Back") end
	HideRows(window)
	if not session or InCombatLockdown() then
		window._breakdown = nil
		PaintSources(window, cfg)
		return
	end
	local src = session.combatSources and session.combatSources[window._breakdown]
	if not src or Soul.Secret.IsSecret(src) or (issecrettable and issecrettable(src)) or Soul.Secret.IsSecret(src.sourceGUID) then
		window._breakdown = nil
		PaintSources(window, cfg)
		return
	end
	local creature = src.sourceCreatureID
	if Soul.Secret.IsSecret(creature) then creature = nil end
	local ok, detail = pcall(C_DamageMeter.GetCombatSessionSourceFromType, segment, meter, src.sourceGUID, creature)
	if not ok or not Readable(detail) or not Readable(detail.combatSpells) then
		window.rows[1]:Show()
		window.rows[1].Name:SetText(src.name or "")
		window.rows[1].Value:SetText("")
		return
	end
	local spells = detail.combatSpells
	local maxAmount = detail.maxAmount
	for i = 1, MAX_SPELLS do
		local spell = spells[i]
		local row = window.rows[i]
		if not Soul.Secret.Present(spell) or Soul.Secret.IsSecret(spell) or (issecrettable and issecrettable(spell)) then
			row:Hide()
		else
			row:Show()
			row.Icon:Hide()
			row.Mark:Hide()
			local spellName
			if C_Spell and C_Spell.GetSpellName and not Soul.Secret.IsSecret(spell.spellID) then
				spellName = C_Spell.GetSpellName(spell.spellID)
			end
			row.Name:SetText(spellName or "")
			row.Value:SetFormattedText("%s", Soul:Abbrev(spell.totalAmount))
			local r, g, b = Soul:Accent()
			row.Bar:SetStatusBarColor(r, g, b)
			if Soul.Secret.Present(maxAmount) then
				row.Bar:SetMinMaxValues(0, maxAmount)
				Ease(row.Bar, spell.totalAmount)
			end
			if row.Rank then row.Rank:SetText("") end
			if C_Spell and C_Spell.GetSpellTexture and not Soul.Secret.IsSecret(spell.spellID) and type(spell.spellID) == "number" then
				local texture = C_Spell.GetSpellTexture(spell.spellID)
				if Soul.Secret.Present(texture) then
					row.Icon:SetTexture(texture)
					row.Icon:Show()
				end
			end
		end
	end
end

function DM:PaintWindow(index)
	local window = self.windows and self.windows[index]
	if not window then return end
	local cfg = DB().windows[index]
	if not DB().enabled or not cfg or not cfg.enabled then
		window:Hide()
		return
	end
	window:Show()
	local ok, err = pcall(function()
		if window._breakdown then
			PaintSpells(window, cfg)
		else
			PaintSources(window, cfg)
		end
	end)
	if not ok and not window._soulReported then
		window._soulReported = true
		Soul:Print("Damage meter paint failed:", err)
	end
end

function DM:RefreshAll()
	if not self.windows then return end
	for i = 1, WINDOWS do
		self:PaintWindow(i)
	end
	self:UpdateClocks()
end

function DM:StopTicker(gen)
	if gen and gen ~= self._gen then return end
	if self._ticker then
		self._ticker:Cancel()
		self._ticker = nil
	end
	if self._clock then
		self._clock:Cancel()
		self._clock = nil
	end
	self:RefreshAll()
end

function DM:StartTicker()
	if self._ticker then
		self._ticker:Cancel()
		self._ticker = nil
	end
	if self._clock then
		self._clock:Cancel()
		self._clock = nil
	end
	local gen = self._gen
	local rate = DB().refresh
	if type(rate) ~= "number" or rate < 0.25 then rate = 0.25 end
	if rate > 1 then rate = 1 end
	self._ticker = C_Timer.NewTicker(rate, function()
		if gen ~= DM._gen then return end
		DM:RefreshAll()
		if not DM._inCombat and not GroupInCombat() then
			local secs = DM:ReadDuration()
			if secs then DM._pinned = secs end
			DM:StopTicker(gen)
		end
	end)
	self._clock = C_Timer.NewTicker(0.5, function()
		if gen ~= DM._gen then return end
		DM:UpdateClocks()
	end)
end

function DM:BeginCombat()
	self._gen = (self._gen or 0) + 1
	self._inCombat = true
	self._pinned = nil
	for i = 1, WINDOWS do
		if self.windows[i] then self.windows[i]._breakdown = nil end
	end
	self:StartTicker()
	self:RefreshAll()
end

local function RestoreCVar()
	local saved = Soul.db and Soul.db.cvars and Soul.db.cvars.damageMeterEnabled
	if saved and type(saved.original) == "string" and not InCombatLockdown() then
		SetCVar("damageMeterEnabled", saved.original)
	end
end

function DM:Apply()
	local db = DB()
	if not db.enabled then
		self._inCombat = false
		self:StopTicker()
		if self.windows then
			for i = 1, WINDOWS do
				self.windows[i]:Hide()
			end
		end
		RestoreCVar()
		return
	end
	Soul:SetOwnedCVar("damageMeterEnabled", "0", "DamageMeters")
	local width = db.width or 300
	local rowHeight = db.rowHeight or 18
	local rows = db.rows or 12
	if rows > MAX_ROWS then rows = MAX_ROWS end
	local headerH = 22
	local gap = 1
	local stride = rowHeight + gap
	for i = 1, WINDOWS do
		local window = self.windows[i]
		local cfg = db.windows[i]
		window:SetWidth(width)
		window:SetHeight(headerH + rows * stride - gap)
		window.Header:SetHeight(headerH)
		for n = 1, MAX_ROWS do
			local row = window.rows[n]
			local y = -headerH - (n - 1) * stride
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", window, "TOPLEFT", 0, y)
			row:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, y)
			row:SetHeight(rowHeight)
			row.Icon:SetSize(rowHeight - 4, rowHeight - 4)
		end
		Soul:Place(window, "DamageMeters:" .. i, {
			point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y,
		})
		local tint = cfg.color
		if type(tint) == "table" and window.bg then
			window.bg:SetColorTexture(tint[1], tint[2], tint[3], db.bgAlpha or 0.55)
		elseif window.bg then
			window.bg:SetColorTexture(0.02, 0.02, 0.025, db.bgAlpha or 0.55)
		end
		local r, g, b = Soul:Accent()
		if window.Sync then window.Sync(window, cfg) end
		window.MarkColor = { r, g, b }
		for n = 1, MAX_ROWS do
			window.rows[n].Mark:SetColorTexture(r, g, b, 1)
		end
	end
	self:RefreshAll()
	if self._ticker then
		self:StartTicker()
	end
end

local function MakeRow(parent)
	local row = CreateFrame("Button", nil, parent)
	local bar = Soul:StatusBar(row)
	bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
	bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
	if bar.bg then
		bar.bg:SetColorTexture(0.07, 0.07, 0.08, 1)
	end
	row.Bar = bar
	local rank = bar:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(rank, 12, "OUTLINE")
	rank:SetPoint("LEFT", 4, 0)
	rank:SetWidth(14)
	rank:SetJustifyH("RIGHT")
	rank:SetTextColor(0.55, 0.55, 0.6)
	row.Rank = rank
	local icon = row:CreateTexture(nil, "OVERLAY")
	icon:SetPoint("LEFT", rank, "RIGHT", 3, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:Hide()
	row.Icon = icon
	local name = bar:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(name, 13, "OUTLINE")
	name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	name:SetJustifyH("LEFT")
	name:SetTextColor(1, 1, 1)
	row.Name = name
	local value = bar:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(value, 13, "OUTLINE")
	value:SetPoint("RIGHT", -4, 0)
	value:SetJustifyH("RIGHT")
	value:SetTextColor(1, 1, 1)
	row.Value = value
	name:SetPoint("RIGHT", value, "LEFT", -4, 0)
	local mark = row:CreateTexture(nil, "OVERLAY", nil, 7)
	mark:SetPoint("TOPLEFT")
	mark:SetPoint("BOTTOMLEFT")
	mark:SetWidth(2)
	mark:Hide()
	row.Mark = mark
	return row
end

local popup
local popupButtons = {}

local function ShowPopup(anchor, entries, current, onPick)
	if not popup then
		popup = CreateFrame("Frame", "SoulUIMeterPopup", UIParent)
		popup:SetFrameStrata("DIALOG")
		popup:SetClampedToScreen(true)
		popup:EnableMouse(true)
		popup:Hide()
		local bg = popup:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.06, 0.06, 0.07, 0.98)
		Soul:Border(popup)
		local catcher = CreateFrame("Button", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("DIALOG")
		catcher:SetFrameLevel(1)
		catcher:EnableMouse(true)
		catcher:Hide()
		catcher:SetScript("OnClick", function() popup:Hide() end)
		popup:SetFrameLevel(40)
		popup:SetScript("OnHide", function() catcher:Hide() end)
		popup._catcher = catcher
	end
	local count = #entries
	local rowH = 24
	popup:SetSize(168, count * rowH + 8)
	popup:ClearAllPoints()
	popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	for i = 1, count do
		local button = popupButtons[i]
		if not button then
			button = CreateFrame("Button", nil, popup)
			button:SetHeight(rowH)
			local face = button:CreateTexture(nil, "BACKGROUND")
			face:SetAllPoints()
			button.face = face
			local font = button:CreateFontString(nil, "OVERLAY")
			Soul:ApplyFont(font, 12, "OUTLINE")
			font:SetPoint("LEFT", 8, 0)
			font:SetPoint("RIGHT", -6, 0)
			font:SetJustifyH("LEFT")
			button.font = font
			button:SetScript("OnEnter", function(self)
				self.face:SetColorTexture(0, 0.42, 0.46, 0.95)
			end)
			button:SetScript("OnLeave", function(self)
				if self._on then
					self.face:SetColorTexture(0, 0.28, 0.32, 0.85)
				else
					self.face:SetColorTexture(0, 0, 0, 0)
				end
			end)
			popupButtons[i] = button
		end
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 4, -4 - (i - 1) * rowH)
		button:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * rowH)
		local entry = entries[i]
		button.font:SetText(entry.label)
		button._on = entry.key == current
		if button._on then
			button.face:SetColorTexture(0, 0.28, 0.32, 0.85)
			button.font:SetTextColor(1, 1, 1)
		else
			button.face:SetColorTexture(0, 0, 0, 0)
			button.font:SetTextColor(0.86, 0.86, 0.9)
		end
		button:SetScript("OnClick", function()
			popup:Hide()
			onPick(entry.key)
		end)
		button:Show()
	end
	for i = count + 1, #popupButtons do
		popupButtons[i]:Hide()
	end
	popup._catcher:Show()
	popup:Show()
end

local function HeaderButton(parent, width)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 18)
	local face = button:CreateTexture(nil, "BACKGROUND")
	face:SetAllPoints()
	face:SetColorTexture(1, 1, 1, 0)
	button.face = face
	local font = button:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(font, 12, "OUTLINE")
	font:SetPoint("LEFT", 2, 0)
	font:SetPoint("RIGHT", -2, 0)
	font:SetJustifyH("LEFT")
	font:SetWordWrap(false)
	button.Label = font
	button:SetScript("OnEnter", function() face:SetColorTexture(1, 1, 1, 0.08) end)
	button:SetScript("OnLeave", function() face:SetColorTexture(1, 1, 1, 0) end)
	return button
end

local function SyncHeader(window, cfg)
	window.Mode.Label:SetText(TypeInfo(cfg.type).label)
	window.Mode.Label:SetTextColor(0.92, 0.92, 0.94)
end

local function MakeWindow(index)
	local window = CreateFrame("Frame", "SoulUIMeter" .. index, UIParent)
	local bg = window:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.02, 0.025, 0.55)
	window.bg = bg
	local header = CreateFrame("Frame", nil, window)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(22)
	window.Header = header
	local mode = HeaderButton(header, 140)
	mode:SetPoint("LEFT", 8, 0)
	mode:SetPoint("RIGHT", header, "RIGHT", -78, 0)
	mode:SetHeight(18)
	window.Mode = mode
	local close = CreateFrame("Button", nil, header)
	close:SetSize(16, 16)
	close:SetPoint("RIGHT", -4, 0)
	local closeText = close:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(closeText, 12, "OUTLINE")
	closeText:SetPoint("CENTER")
	closeText:SetText("x")
	closeText:SetTextColor(0.7, 0.7, 0.74)
	close:SetScript("OnEnter", function() closeText:SetTextColor(1, 1, 1) end)
	close:SetScript("OnLeave", function() closeText:SetTextColor(0.7, 0.7, 0.74) end)
	window.Close = close
	local clock = header:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(clock, 11, "OUTLINE")
	clock:SetPoint("RIGHT", close, "LEFT", -4, 0)
	clock:SetTextColor(0.78, 0.78, 0.82)
	window.Clock = clock
	close:SetScript("OnClick", function()
		DB().windows[index].enabled = false
		DM:PaintWindow(index)
	end)
	mode:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mode:SetScript("OnClick", function(_, button)
		if window._breakdown then
			window._breakdown = nil
			DM:PaintWindow(index)
			return
		end
		if button == "RightButton" then
			ShowPopup(mode, SEGMENTS, DB().windows[index].segment, function(key)
				DB().windows[index].segment = key
				DM:PaintWindow(index)
			end)
			return
		end
		ShowPopup(mode, TYPES, DB().windows[index].type, function(key)
			DB().windows[index].type = key
			DM:PaintWindow(index)
		end)
	end)
	window.rows = {}
	for i = 1, MAX_ROWS do
		local row = MakeRow(window)
		row:SetScript("OnClick", function(self)
			if InCombatLockdown() then return end
			if window._breakdown then
				window._breakdown = nil
			else
				window._breakdown = self._soulIndex
			end
			DM:PaintWindow(index)
		end)
		window.rows[i] = row
	end
	Soul:Border(window)
	window.Sync = SyncHeader
	return window
end

function DM:OnInitialize()
	Soul:RegisterModuleDB("DamageMeters", Soul.Defaults.DamageMeters)
	Soul:RegisterMigration("meters-three-windows-0.2.2", function(db)
		local profiles = db.profiles
		if type(profiles) ~= "table" then return end
		for _, profile in pairs(profiles) do
			local modules = type(profile) == "table" and profile.modules
			local meters = modules and modules.DamageMeters
			local windows = meters and meters.windows
			if type(windows) == "table" then
				local first = windows[1]
				local second = windows[2]
				local third = windows[3]
				if type(first) == "table" then
					first.enabled = true
					first.type = "damage"
					first.segment = "current"
				end
				if type(second) == "table" then
					second.enabled = true
					second.type = "damage"
					second.segment = "overall"
				end
				if type(third) == "table" then
					third.enabled = true
					third.type = "healing"
					third.segment = "current"
				end
				if meters.width == 220 then
					meters.width = 300
				end
			end
		end
	end)
	Soul:RunMigrations()
end

function DM:OnEnable()
	if not C_DamageMeter then
		Soul:Print("C_DamageMeter is missing. Damage meters will stay empty.")
	end
	self._gen = 0
	self._inCombat = false
	self.windows = {}
	for i = 1, WINDOWS do
		self.windows[i] = MakeWindow(i)
		local index = i
		Soul:RegisterMover({
			key = "DamageMeters:" .. index,
			label = "Meter " .. index,
			getFrame = function() return DM.windows[index] end,
			fallback = function()
				local cfg = DB().windows[index]
				return { point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y }
			end,
			onResize = function(width, height)
				local db = DB()
				local rows = db.rows or 6
				if rows < 1 then rows = 1 end
				local oldW = db.width or width
				local oldH = 22 + rows * ((db.rowHeight or 16) + 1) - 1
				if math.abs(width - oldW) < 3 and math.abs(height - oldH) < 3 then
					local dir = 0
					if width > oldW + 0.2 or height > oldH + 0.2 then dir = 1
					elseif width < oldW - 0.2 or height < oldH - 0.2 then dir = -1 end
					db.width = math.max(140, oldW + dir)
					db.rowHeight = math.max(10, math.min(28, (db.rowHeight or 16) + dir))
				else
					db.width = math.max(140, math.floor(width + 0.5))
					local rowH = math.floor((height - 22) / rows)
					if rowH < 10 then rowH = 10 end
					if rowH > 28 then rowH = 28 end
					db.rowHeight = rowH
				end
				DM:Apply()
			end,
			getColor = function()
				local cfg = DB().windows[index]
				if type(cfg.color) == "table" then return cfg.color[1], cfg.color[2], cfg.color[3] end
				return 0.02, 0.02, 0.025
			end,
			setColor = function(r, g, b)
				DB().windows[index].color = { r, g, b }
				DM:Apply()
			end,
		})
	end

	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		DM:BeginCombat()
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		DM._inCombat = false
		local gen = DM._gen
		C_Timer.After(5, function()
			if gen ~= DM._gen then return end
			local secs = DM:ReadDuration()
			if secs then DM._pinned = secs end
			DM:StopTicker(gen)
		end)
	end)
	self:RegisterEvent("ENCOUNTER_START", function()
		DM:BeginCombat()
	end)
	self:RegisterEvent("ENCOUNTER_END", function()
		local gen = DM._gen
		C_Timer.After(0.5, function()
			if gen ~= DM._gen then return end
			if not GroupInCombat() then
				local secs = DM:ReadDuration()
				if secs then DM._pinned = secs end
				DM._inCombat = false
				DM:StopTicker(gen)
			end
		end)
	end)
	local function OnUnitFlags()
		if DM._inCombat or DM._ticker then return end
		local inside = IsInInstance()
		if not inside then return end
		if GroupInCombat() then DM:BeginCombat() end
	end
	pcall(self.RegisterUnitEvent, self, "UNIT_FLAGS", OnUnitFlags, "player")
	for i = 1, 4 do
		pcall(self.RegisterUnitEvent, self, "UNIT_FLAGS", OnUnitFlags, PARTY_UNITS[i])
	end
	for i = 1, 40 do
		pcall(self.RegisterUnitEvent, self, "UNIT_FLAGS", OnUnitFlags, RAID_UNITS[i])
	end
	local function refreshIfIdle()
		if not DM._ticker then DM:RefreshAll() end
	end
	self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", refreshIfIdle)
	self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", refreshIfIdle)
	self:RegisterEvent("DAMAGE_METER_RESET", function()
		DM._pinned = nil
		DM:RefreshAll()
	end)
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function()
		DM:RefreshAll()
	end)
	self:RegisterEvent("CHALLENGE_MODE_START", function()
		if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
			pcall(C_DamageMeter.ResetAllCombatSessions)
		end
		DM._pinned = nil
		DM:RefreshAll()
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		if Fighting("player") or GroupInCombat() then
			if not DM._inCombat then DM:BeginCombat() end
		else
			DM:RefreshAll()
		end
	end)

	Soul:On("ProfileChanged", function() DM:Apply() end)
	Soul:On("ThemeChanged", function() DM:Apply() end)
	self:Apply()
end
