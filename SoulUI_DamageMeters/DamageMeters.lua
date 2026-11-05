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

-- Value text formats. "both" = 23.1M (52.3K), the EllesmereUI-style default.
local function ValueText(fs, total, perSecond, share, format)
	format = format or "both"
	if format == "total" then
		fs:SetFormattedText("%s", Soul:Abbrev(total))
	elseif format == "persec" then
		fs:SetFormattedText("%s", Soul:Abbrev(perSecond))
	elseif format == "pipe" then
		fs:SetFormattedText("%s | %s", Soul:Abbrev(total), Soul:Abbrev(perSecond))
	elseif format == "percent" and share then
		fs:SetFormattedText("%s  %d%%", Soul:Abbrev(total), share)
	else
		fs:SetFormattedText("%s (%s)", Soul:Abbrev(total), Soul:Abbrev(perSecond))
	end
end

local function PaintRow(row, src, maxAmount, deaths)
	row:Show()
	local db = DB()
	local r, g, b = ClassColor(src.classFilename)
	if db.classColors == false then
		r, g, b = Soul:Accent()
	end
	row.Bar:SetStatusBarColor(r, g, b, db.barAlpha or 1)
	if row.Rank then
		local index = row._soulIndex
		if db.showRank and type(index) == "number" then
			row.Rank:SetFormattedText("%d.", index)
			row.Rank:Show()
		else
			row.Rank:SetText("")
			row.Rank:Hide()
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
	local sessionTotal = row._soulSessionTotal
	local share
	if not Soul.Secret.IsSecret(total) and not Soul.Secret.IsSecret(sessionTotal)
		and type(total) == "number" and type(sessionTotal) == "number" and sessionTotal > 0 then
		share = math.floor(total / sessionTotal * 100 + 0.5)
	end
	if deaths then
		row.Value:SetText("")
	else
		ValueText(row.Value, total, src.amountPerSecond, share, db.valueFormat)
	end
	local icon = src.specIconID
	if db.showIcons ~= false and not Soul.Secret.IsSecret(icon) and type(icon) == "number" and icon > 0 then
		row.Icon:SetTexture(icon)
		row.Icon:Show()
	elseif db.showIcons ~= false then
		-- No spec yet (out of range, pet): show the class crest instead.
		local class = src.classFilename
		local coords = not Soul.Secret.IsSecret(class) and type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		if coords then
			row.Icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
			row.Icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
			row.Icon:Show()
			row._soulCrest = true
		else
			row.Icon:Hide()
		end
	else
		row.Icon:Hide()
	end
	if not row._soulCrest then row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	row._soulCrest = nil
	local mine = src.isLocalPlayer
	if db.markSelf ~= false and not Soul.Secret.IsSecret(mine) and mine then
		row.Mark:Show()
	else
		row.Mark:Hide()
	end
	row._soulTip = src
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
	if window.Sync then window.Sync(window, cfg) end
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
			row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row._soulTip = nil
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

-- Window look (own design, after the EllesmereUI meter's proportions): a solid
-- dark header with the meter name in the accent color, the segment and fight
-- clock dimmed beside it, and small icon buttons on the right; rows are a spec
-- icon plus a class-colored bar with name left and value right on a dark,
-- mostly opaque body.
local HEADER_ICONS = {
	segment = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
	reset = "Interface\\Buttons\\UI-RefreshButton",
	close = "Interface\\Buttons\\UI-StopButton",
}

local function Geometry()
	local db = DB()
	local rowHeight = Soul.Pixel:Scale(db.rowHeight or 18)
	local gap = Soul.Pixel:Scale(db.rowGap or 1)
	local rows = db.rows or 8
	if rows > MAX_ROWS then rows = MAX_ROWS end
	local headerH = Soul.Pixel:Scale(db.headerHeight or 22)
	return rowHeight, gap, rows, headerH
end

local function StyleRow(row, rowHeight, db)
	local fontSize = db.fontSize or 0
	if fontSize <= 0 then fontSize = math.max(9, math.floor(rowHeight * 0.62 + 0.5)) end
	local iconOn = db.showIcons ~= false
	row.Icon:SetSize(rowHeight, rowHeight)
	row.Icon:ClearAllPoints()
	row.Icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.Bar:ClearAllPoints()
	if iconOn then
		row.Bar:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", Soul.Pixel:Scale(1), 0)
	else
		row.Bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	end
	row.Bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	row.Bar:SetStatusBarTexture(db.texture and Soul:Media("statusbar", db.texture) or Soul:StatusbarTexture())
	local bg = db.rowBackground or { 0, 0, 0, 0.35 }
	if row.Bar.bg then row.Bar.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 0.35) end
	Soul:ApplyFont(row.Name, fontSize, "OUTLINE")
	Soul:ApplyFont(row.Value, fontSize, "OUTLINE")
	Soul:ApplyFont(row.Rank, fontSize, "OUTLINE")
	row.Rank:ClearAllPoints()
	row.Rank:SetPoint("LEFT", row.Bar, "LEFT", 4, 0)
	row.Name:ClearAllPoints()
	if db.showRank then
		row.Name:SetPoint("LEFT", row.Rank, "RIGHT", 2, 0)
	else
		row.Name:SetPoint("LEFT", row.Bar, "LEFT", 5, 0)
	end
	row.Name:SetPoint("RIGHT", row.Value, "LEFT", -6, 0)
end

local function PaintHeader(window, cfg)
	local db = DB()
	local r, g, b = Soul:Accent()
	local info = TypeInfo(cfg.type)
	if window._breakdown then
		window.Title:SetText("< " .. info.label)
	else
		window.Title:SetText(info.label)
	end
	if db.headerAccent == false then
		window.Title:SetTextColor(1, 1, 1)
	else
		window.Title:SetTextColor(r, g, b)
	end
	window.Segment:SetText(SegmentInfo(cfg.segment).label)
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
	local width = Soul.Pixel:Scale(db.width or 260)
	local rowHeight, gap, rows, headerH = Geometry()
	local stride = rowHeight + gap
	local headerColor = db.headerColor or { 0.106, 0.106, 0.106, 1 }
	local headerFont = db.headerFontSize or 0
	if headerFont <= 0 then headerFont = math.max(10, math.floor(headerH * 0.52 + 0.5)) end
	local r, g, b = Soul:Accent()
	for i = 1, WINDOWS do
		local window = self.windows[i]
		local cfg = db.windows[i]
		window:SetWidth(width)
		window:SetHeight(headerH + gap + rows * stride - gap)
		window.Header:SetHeight(headerH)
		window.HeaderBg:SetColorTexture(headerColor[1], headerColor[2], headerColor[3], headerColor[4] or 1)
		window.HeaderLine:SetColorTexture(r, g, b, db.headerLine == false and 0 or 0.9)
		Soul:ApplyFont(window.Title, headerFont, "OUTLINE")
		Soul:ApplyFont(window.Segment, math.max(9, headerFont - 2), "OUTLINE")
		Soul:ApplyFont(window.Clock, math.max(9, headerFont - 1), "OUTLINE")
		local iconSize = math.max(10, headerH - 8)
		for _, button in pairs(window.Buttons) do button:SetSize(iconSize, iconSize) end
		for n = 1, MAX_ROWS do
			local row = window.rows[n]
			local y = -headerH - gap - (n - 1) * stride
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", window, "TOPLEFT", 0, y)
			row:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, y)
			row:SetHeight(rowHeight)
			StyleRow(row, rowHeight, db)
			row.Mark:SetColorTexture(r, g, b, 1)
		end
		Soul:Place(window, "DamageMeters:" .. i, {
			point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y,
		})
		local tint = cfg.color
		local alpha = db.bgAlpha or 0.75
		if type(tint) == "table" then
			window.bg:SetColorTexture(tint[1], tint[2], tint[3], alpha)
		else
			window.bg:SetColorTexture(0, 0, 0, alpha)
		end
		Soul:ShowBorder(window, db.border and true or false, 1)
		window.ButtonsShown(db.headerIconsOnHover ~= true)
		PaintHeader(window, cfg)
	end
	self:RefreshAll()
	if self._ticker then
		self:StartTicker()
	end
end

local function MakeRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:Hide()
	row.Icon = icon
	local bar = Soul:StatusBar(row)
	row.Bar = bar
	local rank = bar:CreateFontString(nil, "OVERLAY")
	rank:SetJustifyH("LEFT")
	rank:SetTextColor(0.85, 0.85, 0.88)
	rank:Hide()
	row.Rank = rank
	local name = bar:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	name:SetTextColor(1, 1, 1)
	row.Name = name
	local value = bar:CreateFontString(nil, "OVERLAY")
	value:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
	value:SetJustifyH("RIGHT")
	value:SetTextColor(1, 1, 1)
	row.Value = value
	local mark = bar:CreateTexture(nil, "OVERLAY", nil, 7)
	mark:SetPoint("TOPRIGHT")
	mark:SetPoint("BOTTOMRIGHT")
	mark:SetWidth(2)
	mark:Hide()
	row.Mark = mark
	local hover = bar:CreateTexture(nil, "OVERLAY", nil, 6)
	hover:SetAllPoints(row)
	hover:SetColorTexture(1, 1, 1, 0.08)
	hover:Hide()
	row:SetScript("OnEnter", function(self)
		hover:Show()
		local src = self._soulTip
		if not src or InCombatLockdown() then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		pcall(function()
			GameTooltip:AddLine(self.Name:GetText() or "", 1, 1, 1)
			GameTooltip:AddDoubleLine("Total", Soul:Abbrev(src.totalAmount), 0.7, 0.7, 0.75, 1, 1, 1)
			GameTooltip:AddDoubleLine("Per second", Soul:Abbrev(src.amountPerSecond), 0.7, 0.7, 0.75, 1, 1, 1)
			GameTooltip:AddLine("Click for spells", 0.5, 0.5, 0.55)
		end)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		hover:Hide()
		GameTooltip:Hide()
	end)
	return row
end

local function IconButton(parent, texture, tip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(14, 14)
	local art = button:CreateTexture(nil, "ARTWORK")
	art:SetAllPoints()
	art:SetTexture(texture)
	art:SetDesaturated(true)
	art:SetVertexColor(0.75, 0.75, 0.8)
	button.Art = art
	button:SetScript("OnEnter", function(self)
		art:SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(tip, 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		art:SetVertexColor(0.75, 0.75, 0.8)
		GameTooltip:Hide()
	end)
	return button
end

local function MenuItems(list)
	local items = {}
	for i = 1, #list do items[i] = { value = list[i].key, label = list[i].label } end
	return items
end

local function MakeWindow(index)
	local window = CreateFrame("Frame", "SoulUIMeter" .. index, UIParent)
	window:SetClampedToScreen(true)
	Soul:Round(window)
	local bg = window:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.75)
	window.bg = bg
	local header = CreateFrame("Button", nil, window)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(22)
	header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	window.Header = header
	local headerBg = header:CreateTexture(nil, "BACKGROUND", nil, 1)
	headerBg:SetAllPoints()
	window.HeaderBg = headerBg
	local line = header:CreateTexture(nil, "ARTWORK")
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(Soul.Pixel:Scale(1))
	window.HeaderLine = line

	local title = header:CreateFontString(nil, "OVERLAY")
	title:SetPoint("LEFT", 7, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	window.Title = title
	local segment = header:CreateFontString(nil, "OVERLAY")
	segment:SetPoint("LEFT", title, "RIGHT", 6, 0)
	segment:SetTextColor(0.55, 0.55, 0.6)
	window.Segment = segment
	local clock = header:CreateFontString(nil, "OVERLAY")
	clock:SetPoint("LEFT", segment, "RIGHT", 6, 0)
	clock:SetTextColor(0.75, 0.75, 0.8)
	window.Clock = clock

	local close = IconButton(header, HEADER_ICONS.close, "Hide this meter")
	close:SetPoint("RIGHT", -5, 0)
	local reset = IconButton(header, HEADER_ICONS.reset, "Reset all meter data")
	reset:SetPoint("RIGHT", close, "LEFT", -5, 0)
	local seg = IconButton(header, HEADER_ICONS.segment, "Current / Overall")
	seg:SetPoint("RIGHT", reset, "LEFT", -5, 0)
	window.Buttons = { close = close, reset = reset, segment = seg }
	window.Close = close

	function window.ButtonsShown(always)
		window._iconsAlways = always
		local a = always and 1 or 0
		for _, button in pairs(window.Buttons) do button:SetAlpha(a) end
	end
	local function HoverIcons(on)
		if window._iconsAlways then return end
		for _, button in pairs(window.Buttons) do button:SetAlpha(on and 1 or 0) end
	end
	header:SetScript("OnEnter", function() HoverIcons(true) end)
	header:SetScript("OnLeave", function()
		if not header:IsMouseOver() then HoverIcons(false) end
	end)
	for _, button in pairs(window.Buttons) do
		button:HookScript("OnEnter", function() HoverIcons(true) end)
		button:HookScript("OnLeave", function()
			if not header:IsMouseOver() then HoverIcons(false) end
		end)
	end

	close:SetScript("OnClick", function()
		DB().windows[index].enabled = false
		DM:PaintWindow(index)
		Soul:Print("Meter " .. index .. " hidden. Turn it back on in /soul > Damage Meters.")
	end)
	reset:SetScript("OnClick", function()
		if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
			pcall(C_DamageMeter.ResetAllCombatSessions)
		end
	end)
	seg:SetScript("OnClick", function()
		local cfg = DB().windows[index]
		cfg.segment = cfg.segment == "overall" and "current" or "overall"
		DM:PaintWindow(index)
		DM:UpdateClocks()
	end)
	-- Click the title: pick the meter type (right-click: the segment). While a
	-- spell breakdown is open, a click goes back.
	header:SetScript("OnClick", function(_, button)
		if window._breakdown then
			window._breakdown = nil
			DM:PaintWindow(index)
			return
		end
		local UI = Soul.UI
		if not UI then return end
		if button == "RightButton" then
			UI.OpenMenu(title, MenuItems(SEGMENTS), DB().windows[index].segment, function(key)
				DB().windows[index].segment = key
				DM:PaintWindow(index)
				DM:UpdateClocks()
			end, 160)
		else
			UI.OpenMenu(title, MenuItems(TYPES), DB().windows[index].type, function(key)
				DB().windows[index].type = key
				DM:PaintWindow(index)
			end, 180)
		end
	end)

	window.rows = {}
	for i = 1, MAX_ROWS do
		local row = MakeRow(window)
		row:SetScript("OnClick", function(self, button)
			if InCombatLockdown() then return end
			if window._breakdown or button == "RightButton" then
				window._breakdown = nil
			else
				window._breakdown = self._soulIndex
			end
			DM:PaintWindow(index)
		end)
		window.rows[i] = row
	end
	window.Sync = PaintHeader
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
				local gap = db.rowGap or 1
				local oldH = (db.headerHeight or 22) + gap + rows * ((db.rowHeight or 18) + gap) - gap
				if math.abs(width - oldW) < 3 and math.abs(height - oldH) < 3 then
					local dir = 0
					if width > oldW + 0.2 or height > oldH + 0.2 then dir = 1
					elseif width < oldW - 0.2 or height < oldH - 0.2 then dir = -1 end
					db.width = math.max(140, oldW + dir)
					db.rowHeight = math.max(10, math.min(28, (db.rowHeight or 16) + dir))
				else
					db.width = math.max(140, math.floor(width + 0.5))
					local rowH = math.floor((height - (db.headerHeight or 22)) / rows) - (db.rowGap or 1)
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
