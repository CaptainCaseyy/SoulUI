if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI
local DM = Soul:NewModule("DamageMeters", "SoulUI_DamageMeters")

local math_floor, math_ceil, math_abs, math_max, math_min, math_exp = math.floor, math.ceil, math.abs, math.max, math.min, math.exp
local string_format = string.format
local type, pcall = type, pcall
local GetTime, InCombatLockdown = GetTime, InCombatLockdown

local MAX_ROWS = 20 -- most rows a window can show at once
local POOL = MAX_ROWS + 1 -- one spare row slides in while scrolling smoothly
local MAX_DATA = 80 -- most entries a window can scroll through
local WINDOWS = 3
local WHITE = "Interface\\Buttons\\WHITE8X8"

local TYPES = {
	{ key = "damage", label = "Damage Done", enum = "DamageDone" },
	{ key = "healing", label = "Healing Done", enum = "HealingDone" },
	{ key = "taken", label = "Damage Taken", enum = "DamageTaken" },
	{ key = "avoidable", label = "Avoidable", enum = "AvoidableDamageTaken" },
	{ key = "enemy", label = "Enemy Damage", enum = "EnemyDamageTaken" },
	{ key = "interrupts", label = "Interrupts", enum = "Interrupts", count = true },
	{ key = "dispels", label = "Dispels", enum = "Dispels", count = true },
	{ key = "deaths", label = "Deaths", enum = "Deaths", count = true },
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

local function IsSecret(v)
	return Soul.Secret.IsSecret(v)
end

local function Present(v)
	return Soul.Secret.Present(v)
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

-- A plain (not secret) table entry from a readable list, or nil.
local function Entry(list, i)
	local v = list[i]
	if not Present(v) or IsSecret(v) or type(v) ~= "table" then return nil end
	if issecrettable and issecrettable(v) then return nil end
	return v
end

local function Fighting(unit)
	if not UnitExists(unit) then return false end
	local ok, value = pcall(UnitAffectingCombat, unit)
	if not ok or IsSecret(value) then return false end
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

------------------------------------------------------------------------------
-- Number format
--
-- 0.6.1 showed "23M (21.600304115133)". The client's AbbreviateNumbers, called
-- without options, uses Blizzard's default breakpoints: nothing below 1000 is
-- abbreviated (a float per-second value comes back with every digit) and 10M+
-- loses its decimal. We hand it our own breakpoints instead, built once, so
-- every value reads 1.23B / 23.1M / 35.5K / 21 - in and out of combat, because
-- the formatting runs engine-side and accepts secret numbers.
------------------------------------------------------------------------------

local BREAKPOINTS = {
	{ breakpoint = 1e12, abbreviation = "T", significandDivisor = 1e10, fractionDivisor = 100, abbreviationIsGlobal = false },
	{ breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e7, fractionDivisor = 100, abbreviationIsGlobal = false },
	{ breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
	{ breakpoint = 1e3, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
	{ breakpoint = 0, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
}

local abbrevOptions -- engine options that passed the probe, or false
local abbrevProbed = false

local function ProbeOptions(options)
	if options == nil then return false end
	-- Below 1000 must come back as a whole number (truncated or rounded), and
	-- millions with one decimal.
	local ok, small = pcall(AbbreviateNumbers, 21.600304115133, options)
	if not ok or IsSecret(small) or type(small) ~= "string" or not small:find("^2[12]$") then return false end
	local ok2, big = pcall(AbbreviateNumbers, 23123456, options)
	if not ok2 or IsSecret(big) or type(big) ~= "string" or not big:find("^23%.1%s?M$") then return false end
	return true
end

local function PickAbbrevOptions()
	abbrevProbed = true
	abbrevOptions = false
	if not AbbreviateNumbers then return end
	local config
	if CreateAbbreviateConfig then
		local ok, made = pcall(CreateAbbreviateConfig, BREAKPOINTS)
		if ok and made ~= nil then config = made end
	end
	local candidates = { config and { config = config } or nil, config, { breakpointData = BREAKPOINTS } }
	for i = 1, 3 do
		local options = candidates[i]
		if options ~= nil and ProbeOptions(options) then
			abbrevOptions = options
			return
		end
	end
end

-- Lua twin of the breakpoints for plain numbers when the engine probe failed.
local function PlainAbbrev(v)
	local sign = ""
	if v < 0 then sign = "-" v = -v end
	for i = 1, #BREAKPOINTS do
		local bp = BREAKPOINTS[i]
		if v >= bp.breakpoint then
			local n = math_floor(v / bp.significandDivisor) / bp.fractionDivisor
			local text
			if bp.fractionDivisor >= 100 then
				text = string_format("%.2f", n)
			elseif bp.fractionDivisor >= 10 then
				text = string_format("%.1f", n)
			else
				return string_format("%s%d%s", sign, n, bp.abbreviation)
			end
			text = text:gsub("0+$", ""):gsub("%.$", "")
			return sign .. text .. bp.abbreviation
		end
	end
	return sign .. "0"
end

local function Abbrev(value)
	if not abbrevProbed then PickAbbrevOptions() end
	if abbrevOptions then
		local ok, text = pcall(AbbreviateNumbers, value, abbrevOptions)
		if ok then return text end
	end
	if not IsSecret(value) then
		if type(value) ~= "number" then return "" end
		return PlainAbbrev(value)
	end
	-- Secret and no custom breakpoints: the core helper (client defaults).
	return Soul:Abbrev(value)
end
DM.Abbrev = Abbrev

local function ClockText(secs)
	local seconds = math_floor(secs % 60)
	local minutes = math_floor(secs / 60) % 60
	local hours = math_floor(secs / 3600)
	if hours > 0 then
		return string_format("%d:%02d:%02d", hours, minutes, seconds)
	end
	return string_format("%d:%02d", minutes, seconds)
end

------------------------------------------------------------------------------
-- Clocks
------------------------------------------------------------------------------

function DM:ReadDuration(which)
	if not C_DamageMeter or not C_DamageMeter.GetSessionDurationSeconds then return nil end
	local enumName = which == "overall" and "Overall" or "Current"
	local segment = EnumValue(Enum and Enum.DamageMeterSessionType, enumName)
	if segment == nil then return nil end
	local ok, secs = pcall(C_DamageMeter.GetSessionDurationSeconds, segment)
	if not ok or IsSecret(secs) or type(secs) ~= "number" then return nil end
	-- With no finished session the API has been seen to hand back the client
	-- uptime (a "301:36:13" clock). A real fight is never a day long.
	if secs < 0 or secs > 86400 then return nil end
	return secs
end

function DM:UpdateClocks()
	if not self.windows then return end
	local current = self:ReadDuration("current")
	local overall = self:ReadDuration("overall")
	if current then self._pinnedCurrent = current end
	if overall then self._pinnedOverall = overall end
	local db = DB()
	for i = 1, WINDOWS do
		local window = self.windows[i]
		if window then
			local cfg = db.windows[i]
			local segment = cfg and cfg.segment
			local shown = segment == "overall" and (overall or self._pinnedOverall) or (current or self._pinnedCurrent)
			if shown and not window._breakdown and db.showClock ~= false then
				window.Clock:SetText(ClockText(shown))
			else
				window.Clock:SetText("")
			end
		end
	end
end

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------

local function SetBar(row, value)
	row.Bar:SetValue(value)
end

local function ClassColor(class)
	if not IsSecret(class) and type(class) == "string" then
		local color = RAID_CLASS_COLORS[class]
		if color then return color.r, color.g, color.b end
	end
	return Soul:Accent()
end

-- Value mode of a window: "columns" draws the main number and the secondary
-- number (per second, share) in two right-aligned columns, so digits line up
-- down the window; "single" draws one string; "count" one plain total.
local function ValueMode(window, cfg, db)
	local info = TypeInfo(cfg.type)
	if info.count and not window._breakdown then return "count" end
	local format = db.valueFormat or "both"
	if db.valueColumns ~= false and (format == "both" or format == "percent") then return "columns" end
	return "single"
end

-- Plain share of a total in whole percent, or nil while the numbers are secret.
local function Share(amount, total)
	if IsSecret(amount) or IsSecret(total) then return nil end
	if type(amount) ~= "number" or type(total) ~= "number" or total <= 0 then return nil end
	return math_floor(amount / total * 100 + 0.5)
end

-- Formats: "both" = 23.1M (35.5K), "pipe" = 23.1M | 35.5K, "total", "persec",
-- "percent" = 23.1M 28% (falls back to "both" while the share is secret).
local function ValueText(row, mode, total, perSecond, share, format)
	local main, side = row.Value2, row.Value
	if mode == "count" then
		side:SetFormattedText("%s", Abbrev(total))
		return
	end
	format = format or "both"
	if mode == "columns" then
		main:SetFormattedText("%s", Abbrev(total))
		if format == "percent" and share then
			side:SetFormattedText("%d%%", share)
		else
			side:SetFormattedText("(%s)", Abbrev(perSecond))
		end
		return
	end
	if format == "total" then
		side:SetFormattedText("%s", Abbrev(total))
	elseif format == "persec" then
		side:SetFormattedText("%s", Abbrev(perSecond))
	elseif format == "pipe" then
		side:SetFormattedText("%s | %s", Abbrev(total), Abbrev(perSecond))
	elseif format == "percent" and share then
		side:SetFormattedText("%s  %d%%", Abbrev(total), share)
	else
		side:SetFormattedText("%s (%s)", Abbrev(total), Abbrev(perSecond))
	end
end

local CREST = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local function SetIcon(row, db, iconID, class)
	if db.showIcons == false then
		row.Icon:Hide()
		return
	end
	if not IsSecret(iconID) and type(iconID) == "number" and iconID > 0 then
		row.Icon:SetTexture(iconID)
		row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.Icon:Show()
		return
	end
	-- No spec yet (out of range, pet): the class crest instead.
	local coords = not IsSecret(class) and type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		row.Icon:SetTexture(CREST)
		row.Icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		row.Icon:Show()
	else
		row.Icon:Hide()
	end
end

local function SetRank(row, db, index)
	if db.showRank then
		row.Rank:SetFormattedText("%d", index)
		row.Rank:Show()
	else
		row.Rank:Hide()
	end
end

-- Snap the bar instead of easing when a row starts showing someone else
-- (scrolling, a new mode), so bars never sweep between two players' values.
local function Retarget(row, key)
	local instant = row._soulKey ~= key
	row._soulKey = key
	return instant
end

local function PaintSource(window, row, src, index, maxAmount, sessionTotal, mode, db)
	row:Show()
	row._soulIndex = index
	local class = src.classFilename
	local r, g, b
	if db.classColors == false then
		r, g, b = Soul:Accent()
	else
		r, g, b = ClassColor(class)
	end
	row.Bar:SetStatusBarColor(r, g, b, db.barAlpha or 1)
	SetRank(row, db, index)
	local instant = Retarget(row, window._paintKey + index)
	if mode == "count" and window._isDeaths then
		row.Bar:SetMinMaxValues(0, 1)
		row.Bar:SetValue(1)
	elseif Present(maxAmount) then
		row.Bar:SetMinMaxValues(0, maxAmount)
		SetBar(row, src.totalAmount, instant)
	end
	local name = src.name
	if not IsSecret(name) and type(name) == "string" then
		local dash = name:find("-", 1, true)
		if dash then name = name:sub(1, dash - 1) end
	end
	row.Name:SetText(name or "")
	if window._isDeaths then
		row.Value:SetText("")
		row.Value2:SetText("")
	else
		local share = db.valueFormat == "percent" and Share(src.totalAmount, sessionTotal) or nil
		ValueText(row, mode, src.totalAmount, src.amountPerSecond, share, db.valueFormat)
	end
	SetIcon(row, db, src.specIconID, class)
	local mine = src.isLocalPlayer
	if db.markSelf ~= false and not IsSecret(mine) and mine then
		row.Self:Show()
		row.SelfTint:Show()
	else
		row.Self:Hide()
		row.SelfTint:Hide()
	end
	row._soulTip = src
end

local function PaintSpell(window, row, spell, index, maxAmount, total, mode, db)
	row:Show()
	row._soulIndex = index
	row._soulTip = nil
	row.Self:Hide()
	row.SelfTint:Hide()
	local color = window._breakdownColor
	if color and db.classColors ~= false then
		row.Bar:SetStatusBarColor(color.r, color.g, color.b, db.barAlpha or 1)
	else
		local r, g, b = Soul:Accent()
		row.Bar:SetStatusBarColor(r, g, b, db.barAlpha or 1)
	end
	SetRank(row, db, index)
	local spellID = spell.spellID
	local plainID = not IsSecret(spellID) and type(spellID) == "number"
	local spellName
	if plainID and C_Spell and C_Spell.GetSpellName then
		spellName = C_Spell.GetSpellName(spellID)
	end
	row.Name:SetText(spellName or "")
	local share = db.valueFormat == "percent" and Share(spell.totalAmount, total) or nil
	ValueText(row, mode, spell.totalAmount, spell.amountPerSecond, share, db.valueFormat)
	local instant = Retarget(row, window._paintKey + index)
	if Present(maxAmount) then
		row.Bar:SetMinMaxValues(0, maxAmount)
		SetBar(row, spell.totalAmount, instant)
	end
	local texture
	if plainID and C_Spell and C_Spell.GetSpellTexture then
		texture = C_Spell.GetSpellTexture(spellID)
	end
	if db.showIcons ~= false and Present(texture) then
		row.Icon:SetTexture(texture)
		row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.Icon:Show()
	else
		row.Icon:Hide()
	end
end

------------------------------------------------------------------------------
-- Scrolling (mouse wheel; eased through the core ticker while it moves)
------------------------------------------------------------------------------

local driver -- Soul.Ticker driver, created in OnEnable

local function Stride(window)
	return window._stride or 19
end

-- Puts the row strip at a pixel offset and works out which entry is on top.
-- Returns true when the set of entries on screen changed (needs a repaint).
local function PlaceScroll(window, pos)
	local stride = Stride(window)
	window._scrollPos = pos
	local first = math_floor(pos / stride + 0.0001) + 1
	local pixel = pos - (first - 1) * stride
	if pixel < 0.01 then pixel = 0 end
	window.Content:ClearAllPoints()
	window.Content:SetPoint("TOPLEFT", window.Body, "TOPLEFT", 0, pixel)
	window.Content:SetPoint("TOPRIGHT", window.Body, "TOPRIGHT", 0, pixel)
	local partial = pixel > 0
	local changed = first ~= window._first or partial ~= window._partial
	window._first = first
	window._partial = partial
	-- Scroll thumb
	local count, visible = window._count or 0, window._visible or 1
	if count > visible then
		local bodyH = visible * stride - (window._gap or 0)
		local thumbH = math_max(8, bodyH * visible / count)
		local maxScroll = (count - visible) * stride
		local y = maxScroll > 0 and (bodyH - thumbH) * pos / maxScroll or 0
		window.Thumb:SetHeight(thumbH)
		window.Thumb:ClearAllPoints()
		window.Thumb:SetPoint("TOPRIGHT", window.Body, "TOPRIGHT", 0, -y)
		window.Thumb:Show()
	else
		window.Thumb:Hide()
	end
	return changed
end

local function MaxScroll(window)
	local over = (window._count or 0) - (window._visible or 0)
	if over < 0 then over = 0 end
	return over * Stride(window)
end

local function StopScrollAnim(window)
	if driver and window._animating then
		driver:Remove(window._animKey)
	end
	window._animating = false
end

local function ResetScroll(window)
	StopScrollAnim(window)
	window._scrollTarget = 0
	PlaceScroll(window, 0)
end

-- Clamp after the entry count changes; no animation.
local function ClampScroll(window)
	local maxScroll = MaxScroll(window)
	local target = window._scrollTarget or 0
	if target > maxScroll then target = maxScroll end
	window._scrollTarget = target
	local pos = window._scrollPos or 0
	if pos > maxScroll then
		StopScrollAnim(window)
		pos = maxScroll
	end
	PlaceScroll(window, pos)
	local wheel = (window._count or 0) > (window._visible or 0) and DB().scrollWheel ~= false
	if wheel ~= window._wheel then
		window._wheel = wheel
		window.Body:EnableMouseWheel(wheel)
	end
end

local function ScrollBy(window, delta)
	local stride = Stride(window)
	local maxScroll = MaxScroll(window)
	local target = (window._scrollTarget or 0) - delta * stride
	target = math_floor(target / stride + 0.5) * stride
	if target < 0 then target = 0 end
	if target > maxScroll then target = maxScroll end
	window._scrollTarget = target
	if DB().smoothScroll == false or not driver then
		if PlaceScroll(window, target) then DM:PaintWindow(window._index) end
		return
	end
	window._animTime = GetTime()
	if not window._animating then
		window._animating = true
		driver:Add(window._animKey, window._animStep)
	end
end

------------------------------------------------------------------------------
-- Painting
------------------------------------------------------------------------------

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

-- Re-anchors the row text for a value mode. Runs only when the mode changes.
-- In "columns" the trailing column (per second, share) reads a step dimmer.
local function EnsureMode(window, mode)
	if window._mode == mode then return end
	window._mode = mode
	local columns = mode == "columns"
	local valueW = columns and window._columnWidth or 0
	local rank = DB().showRank and true or false
	for n = 1, POOL do
		local row = window.rows[n]
		row.Value:SetWidth(valueW)
		row.Value2:SetShown(columns)
		row.Name:ClearAllPoints()
		if rank then
			row.Name:SetPoint("LEFT", row.Rank, "RIGHT", 5, 0)
		else
			row.Name:SetPoint("LEFT", row.Bar, "LEFT", 6, 0)
		end
		row.Name:SetPoint("RIGHT", columns and row.Value2 or row.Value, "LEFT", -6, 0)
		if columns then
			local a = row._soulSideDim or 0.62
			row.Value:SetTextColor(a, a, a + 0.03, 1)
		else
			row.Value:SetTextColor(1, 1, 1, 1)
			row.Value2:SetText("")
		end
	end
end

local function ShowEmpty(window, text)
	if text and DB().emptyText ~= false then
		window.Empty:SetText(text)
		window.Empty:Show()
	else
		window.Empty:Hide()
	end
end

local function HideRowsFrom(window, from)
	for n = from, POOL do
		window.rows[n]:Hide()
	end
end

local function PaintHeader(window, cfg)
	local info = TypeInfo(cfg.type)
	window.Title:SetText(info.label)
	local inBreakdown = window._breakdown and true or false
	if inBreakdown then
		window.Segment:SetText(window._breakdownName or "Spells")
	else
		window.Segment:SetText(SegmentInfo(cfg.segment).label)
	end
	if window._titleShifted ~= inBreakdown then
		window._titleShifted = inBreakdown
		window.Back:SetShown(inBreakdown)
		window.Title:ClearAllPoints()
		window.Title:SetPoint("BOTTOMLEFT", window.Header, "BOTTOMLEFT",
			inBreakdown and (window._titleBackX or 20) or (window._titleX or 8), window._baseY or 4)
	end
end

local function PaintSources(window, cfg, db)
	local session = FetchSession(cfg)
	local sources = session and session.combatSources
	if not Readable(sources) then
		window._count = 0
		ClampScroll(window)
		HideRowsFrom(window, 1)
		ShowEmpty(window, C_DamageMeter and "No combat data yet" or "Combat meter unavailable")
		return
	end
	local count = #sources
	if count > MAX_DATA then count = MAX_DATA end
	window._count = count
	ClampScroll(window)
	if count == 0 then
		HideRowsFrom(window, 1)
		ShowEmpty(window, cfg.segment == "overall" and "No combat data yet" or "Waiting for combat")
		return
	end
	ShowEmpty(window, nil)
	local mode = ValueMode(window, cfg, db)
	EnsureMode(window, mode)
	local maxAmount = session.maxAmount
	if not Present(maxAmount) then
		local top = Entry(sources, 1)
		maxAmount = top and top.totalAmount
	end
	local sessionTotal = session.totalAmount
	local first = window._first or 1
	local slots = window._visible + (window._partial and 1 or 0)
	for n = 1, POOL do
		local row = window.rows[n]
		local index = first + n - 1
		local src = n <= slots and index <= count and Entry(sources, index) or nil
		if src then
			PaintSource(window, row, src, index, maxAmount, sessionTotal, mode, db)
		else
			row:Hide()
		end
	end
end

local function PaintSpells(window, cfg, db)
	local session, meter, segment = FetchSession(cfg)
	if not session or InCombatLockdown() or not Readable(session.combatSources) then
		return false
	end
	local src = Entry(session.combatSources, window._breakdown)
	if not src or IsSecret(src.sourceGUID) then return false end
	local creature = src.sourceCreatureID
	if IsSecret(creature) then creature = nil end
	local ok, detail = pcall(C_DamageMeter.GetCombatSessionSourceFromType, segment, meter, src.sourceGUID, creature)
	local spells = ok and Readable(detail) and detail.combatSpells
	if not Readable(spells) then
		window._count = 0
		ClampScroll(window)
		HideRowsFrom(window, 1)
		ShowEmpty(window, "No spell data")
		return true
	end
	local count = #spells
	if count > MAX_DATA then count = MAX_DATA end
	window._count = count
	ClampScroll(window)
	ShowEmpty(window, count == 0 and "No spell data" or nil)
	local mode = ValueMode(window, cfg, db)
	EnsureMode(window, mode)
	local maxAmount = detail.maxAmount
	if not Present(maxAmount) then
		local top = Entry(spells, 1)
		maxAmount = top and top.totalAmount
	end
	local total = detail.totalAmount
	local first = window._first or 1
	local slots = window._visible + (window._partial and 1 or 0)
	for n = 1, POOL do
		local row = window.rows[n]
		local index = first + n - 1
		local spell = n <= slots and index <= count and Entry(spells, index) or nil
		if spell then
			PaintSpell(window, row, spell, index, maxAmount, total, mode, db)
		else
			row:Hide()
		end
	end
	return true
end

local function PaintInner(window, cfg)
	local db = DB()
	window._isDeaths = cfg.type == "deaths"
	if window._breakdown then
		if not PaintSpells(window, cfg, db) then
			window._breakdown = nil
			window._paintKey = (window._paintKey or 0) + 1000
			ResetScroll(window)
		else
			PaintHeader(window, cfg)
			return
		end
	end
	PaintHeader(window, cfg)
	PaintSources(window, cfg, db)
end

function DM:PaintWindow(index)
	local window = self.windows and self.windows[index]
	if not window then return end
	local cfg = DB().windows[index]
	if not DB().enabled or not cfg or not cfg.enabled then
		StopScrollAnim(window)
		window:Hide()
		return
	end
	window:Show()
	local ok, err = pcall(PaintInner, window, cfg)
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

-- A new view (mode, segment, breakdown): back to the top, bars snap.
function DM:NewView(index)
	local window = self.windows and self.windows[index]
	if not window then return end
	window._paintKey = (window._paintKey or 0) + 1000
	ResetScroll(window)
	self:PaintWindow(index)
	self:UpdateClocks()
end

------------------------------------------------------------------------------
-- Combat tickers
------------------------------------------------------------------------------

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
	-- Server events paint the bars. This ticker only covers a push that never
	-- arrived, and it is never slower than 20 times a second. Older profiles
	-- saved 0.25 (4 Hz); that value is treated as "as fast as the meter goes".
	local rate = DB().refresh
	if type(rate) ~= "number" or rate >= 0.2 or rate < 0.03 then rate = 0.05 end
	self._ticker = C_Timer.NewTicker(rate, function()
		if gen ~= DM._gen then return end
		DM:RefreshAll()
		if not DM._inCombat and not GroupInCombat() then
			local secs = DM:ReadDuration()
			if secs then DM._pinned = secs end
			DM:StopTicker(gen)
		end
	end)
	self._clock = C_Timer.NewTicker(0.1, function()
		if gen ~= DM._gen then return end
		DM:UpdateClocks()
	end)
end

function DM:BeginCombat()
	self._gen = (self._gen or 0) + 1
	self._inCombat = true
	self._pinned = nil
	for i = 1, WINDOWS do
		local window = self.windows[i]
		if window then
			if window._breakdown then
				window._breakdown = nil
				window._paintKey = (window._paintKey or 0) + 1000
			end
			ResetScroll(window)
		end
	end
	self:StartTicker()
	self:RefreshAll()
end

------------------------------------------------------------------------------
-- Look
--
-- Own design: a solid header with the meter name in the accent color, a small
-- dot and the segment dimmed beside it, the fight clock right-aligned and
-- drawn line icons at the right edge, all sitting on one baseline; a fading
-- accent hairline under it. Rows are a square spec icon plus a class-colored
-- bar on a faint track, with a soft top sheen, a fixed rank column, the name
-- left and the numbers in right-aligned columns. Your own row gets a thin
-- accent edge and a faint lift. Rows clip inside the body and glide when the
-- list is longer than the window.
------------------------------------------------------------------------------

local GLYPHS = {
	close = { { -0.3, 0.3, 0.3, -0.3 }, { -0.3, -0.3, 0.3, 0.3 } },
	-- two opposed arrows: switch Current / Overall
	swap = {
		{ -0.34, 0.15, 0.34, 0.15 }, { 0.34, 0.15, 0.13, 0.36 },
		{ 0.34, -0.15, -0.34, -0.15 }, { -0.34, -0.15, -0.13, -0.36 },
	},
	-- bin: reset meter data
	reset = {
		{ -0.34, 0.22, 0.34, 0.22 },
		{ -0.11, 0.22, -0.11, 0.34 }, { -0.11, 0.34, 0.11, 0.34 }, { 0.11, 0.34, 0.11, 0.22 },
		{ -0.25, 0.22, -0.19, -0.34 }, { -0.19, -0.34, 0.19, -0.34 }, { 0.19, -0.34, 0.25, 0.22 },
	},
	back = { { 0.12, 0.3, -0.16, 0 }, { -0.16, 0, 0.12, -0.3 } },
}

local ICON_IDLE = { 0.62, 0.64, 0.67 }

local function Glyph(parent, kind)
	local frame = CreateFrame("Frame", nil, parent)
	frame:EnableMouse(false)
	frame.lines = {}
	frame.spec = GLYPHS[kind] or GLYPHS.close
	for i = 1, #frame.spec do
		frame.lines[i] = frame:CreateLine(nil, "OVERLAY")
	end
	function frame:Layout(size, thickness)
		self:SetSize(size, size)
		for i = 1, #self.lines do
			local seg, line = self.spec[i], self.lines[i]
			line:SetThickness(thickness)
			line:SetStartPoint("CENTER", self, seg[1] * size, seg[2] * size)
			line:SetEndPoint("CENTER", self, seg[3] * size, seg[4] * size)
		end
	end
	function frame:SetColor(r, g, b, a)
		for i = 1, #self.lines do self.lines[i]:SetColorTexture(r, g, b, a or 1) end
	end
	frame:Layout(12, 1.5)
	frame:SetColor(ICON_IDLE[1], ICON_IDLE[2], ICON_IDLE[3])
	return frame
end

local function TextStyle(fs, size, db)
	local style = db.textStyle or "shadow"
	if style == "outline" then
		Soul:ApplyFont(fs, size, "OUTLINE")
		fs:SetShadowOffset(0, 0)
	else
		Soul:ApplyFont(fs, size, "NONE")
		if style == "none" then
			fs:SetShadowOffset(0, 0)
		else
			fs:SetShadowColor(0, 0, 0, 0.9)
			fs:SetShadowOffset(1, -1)
		end
	end
end

local function Geometry(db)
	local rowHeight = Soul.Pixel:Scale(db.rowHeight or 18)
	local gap = Soul.Pixel:Scale(db.rowGap or 1)
	local rows = db.rows or 8
	if rows > MAX_ROWS then rows = MAX_ROWS end
	if rows < 1 then rows = 1 end
	local headerH = Soul.Pixel:Scale(db.headerHeight or 22)
	return rowHeight, gap, rows, headerH
end

local function MeasureWidth(fs, text)
	fs:SetText(text)
	local w = fs:GetStringWidth() or 0
	fs:SetText("")
	return math_ceil(w) + 1
end

local function StyleRow(window, row, n, rowHeight, stride, fontSize, db)
	row:ClearAllPoints()
	local y = -(n - 1) * stride
	row:SetPoint("TOPLEFT", window.Content, "TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", window.Content, "TOPRIGHT", 0, y)
	row:SetHeight(rowHeight)
	row.Icon:SetSize(rowHeight, rowHeight)
	row.Icon:ClearAllPoints()
	row.Icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.Bar:ClearAllPoints()
	if db.showIcons ~= false then
		row.Bar:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", Soul.Pixel:Scale(1), 0)
	else
		row.Bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	end
	row.Bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	row.Bar:SetStatusBarTexture(db.texture and Soul:Media("statusbar", db.texture) or Soul:StatusbarTexture())
	local bg = db.rowBackground or { 1, 1, 1, 0.04 }
	row.Bar.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 0.04)
	local fill = row.Bar:GetStatusBarTexture()
	row.Sheen:ClearAllPoints()
	row.Sheen:SetPoint("TOPLEFT", fill, "TOPLEFT")
	row.Sheen:SetPoint("BOTTOMRIGHT", fill, "RIGHT")
	row.Sheen:SetShown(db.barSheen ~= false)
	TextStyle(row.Name, fontSize, db)
	TextStyle(row.Value, fontSize, db)
	TextStyle(row.Value2, fontSize, db)
	TextStyle(row.Rank, math_max(8, fontSize - 1), db)
	row.Rank:ClearAllPoints()
	row.Rank:SetPoint("LEFT", row.Bar, "LEFT", 4, 0)
	row.Rank:SetWidth(window._rankWidth or 14)
	row.Value:ClearAllPoints()
	row.Value:SetPoint("RIGHT", row.Bar, "RIGHT", -6, 0)
	row.Value2:ClearAllPoints()
	row.Value2:SetPoint("RIGHT", row.Value, "LEFT", -4, 0)
	local dim = db.secondaryAlpha or 0.62
	row.Value:SetTextColor(1, 1, 1, 1)
	row.Value2:SetTextColor(1, 1, 1, 1)
	row._soulSideDim = dim
	row.Self:SetWidth(Soul.Pixel:Scale(2))
	row._soulKey = nil
end

function DM:Apply()
	local db = DB()
	if not db.enabled then
		self._inCombat = false
		self:StopTicker()
		if self.windows then
			for i = 1, WINDOWS do
				StopScrollAnim(self.windows[i])
				self.windows[i]:Hide()
			end
		end
		-- Leave damageMeterEnabled at 0. Putting Blizzard's meter back on
		-- here does not unload until a reload, so the next "on" could not
		-- show our windows until /reload.
		return
	end
	local meterCVar = GetCVar("damageMeterEnabled")
	Soul:SetOwnedCVar("damageMeterEnabled", "0", "DamageMeters")
	if meterCVar == "1" then
		if StaticPopupDialogs and StaticPopupDialogs.SOULUI_RELOAD and StaticPopup_Show then
			StaticPopup_Show("SOULUI_RELOAD")
		else
			Soul:Print("Reload the UI (/reload) so the damage meters can take over again.")
		end
	end
	local width = Soul.Pixel:Scale(db.width or 260)
	local rowHeight, gap, rows, headerH = Geometry(db)
	local stride = rowHeight + gap
	local headerColor = db.headerColor or { 0.106, 0.106, 0.106, 1 }
	local headerFont = db.headerFontSize or 0
	if headerFont <= 0 then headerFont = math_max(10, math_floor(headerH * 0.52 + 0.5)) end
	local fontSize = db.fontSize or 0
	if fontSize <= 0 then fontSize = math_max(9, math_floor(rowHeight * 0.6 + 0.5)) end
	local r, g, b = Soul:Accent()
	local lineFrom = CreateColor and CreateColor(r, g, b, 0.9)
	local lineTo = CreateColor and CreateColor(r, g, b, 0.05)
	local pad = Soul.Pixel:Scale(8)
	for i = 1, WINDOWS do
		local window = self.windows[i]
		local cfg = db.windows[i]
		StopScrollAnim(window)
		window._stride = stride
		window._gap = gap
		window._visible = rows
		window:SetWidth(width)
		window:SetHeight(headerH + gap + rows * stride - gap)

		-- Header
		window.Header:SetHeight(headerH)
		window.HeaderBg:SetColorTexture(headerColor[1], headerColor[2], headerColor[3], headerColor[4] or 1)
		local lineAlpha = db.headerLine == false and 0 or 1
		window.HeaderLine:SetHeight(Soul.Pixel:Scale(1))
		window.HeaderLine:SetAlpha(lineAlpha)
		window.HeaderLine:SetTexture(WHITE)
		if not (lineFrom and pcall(window.HeaderLine.SetGradient, window.HeaderLine, "HORIZONTAL", lineFrom, lineTo)) then
			window.HeaderLine:SetColorTexture(r, g, b, 0.9)
		end
		TextStyle(window.Title, headerFont, db)
		TextStyle(window.Segment, math_max(9, headerFont - 2), db)
		TextStyle(window.Clock, math_max(9, headerFont - 1), db)
		if db.headerAccent == false then
			window.Title:SetTextColor(1, 1, 1)
		else
			window.Title:SetTextColor(r, g, b)
		end
		window.Title:SetText("Damage Done")
		local titleH = window.Title:GetStringHeight() or headerFont
		local baseY = math_floor((headerH - titleH) / 2 + 0.5)
		if baseY < 0 then baseY = 0 end
		local midY = baseY + titleH / 2
		local iconSize = math_max(12, math_floor(headerH * 0.72 + 0.5))
		local glyphSize = math_max(8, math_floor(headerH * 0.4 + 0.5))
		local thickness = headerH >= 26 and 2 or 1.5
		local x = -pad + Soul.Pixel:Scale(3)
		local order = window.ButtonOrder
		for n = 1, #order do
			local button = order[n]
			button:SetSize(iconSize, iconSize)
			button.Glyph:Layout(glyphSize, thickness)
			button:ClearAllPoints()
			button:SetPoint("RIGHT", window.Header, "BOTTOMRIGHT", x, midY)
			x = x - iconSize
		end
		window.Back:Layout(math_max(7, glyphSize - 2), thickness)
		window.Back:ClearAllPoints()
		window.Back:SetPoint("CENTER", window.Header, "BOTTOMLEFT", pad + glyphSize / 2 - 2, midY)
		window._titleX = pad
		window._titleBackX = pad + glyphSize + 2
		window._baseY = baseY
		window._titleShifted = nil -- PaintHeader anchors the title
		window.Dot:SetSize(Soul.Pixel:Scale(3), Soul.Pixel:Scale(3))
		window.Dot:ClearAllPoints()
		window.Dot:SetPoint("LEFT", window.Title, "RIGHT", Soul.Pixel:Scale(6), 0)
		window.Segment:ClearAllPoints()
		window.Segment:SetPoint("BOTTOMLEFT", window.Title, "BOTTOMRIGHT", Soul.Pixel:Scale(15), 0)
		window.Clock:ClearAllPoints()
		window.Clock:SetPoint("BOTTOMRIGHT", window.Header, "BOTTOMRIGHT", x - Soul.Pixel:Scale(4), baseY)

		-- Body
		window.Body:ClearAllPoints()
		window.Body:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -headerH - gap)
		window.Body:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
		window.Content:SetHeight(POOL * stride)
		TextStyle(window.Empty, fontSize, db)
		window.Thumb:SetWidth(Soul.Pixel:Scale(2))
		window.Thumb:SetColorTexture(1, 1, 1, 0.22)

		-- Column widths from the font in use (all rows share it).
		local probe = window.rows[1]
		TextStyle(probe.Rank, math_max(8, fontSize - 1), db)
		TextStyle(probe.Value, fontSize, db)
		window._rankWidth = MeasureWidth(probe.Rank, "20")
		local format = db.valueFormat or "both"
		window._columnWidth = MeasureWidth(probe.Value, format == "percent" and "100%" or "(888.8K)")
		window._mode = nil
		for n = 1, POOL do
			local row = window.rows[n]
			StyleRow(window, row, n, rowHeight, stride, fontSize, db)
			row.Self:SetColorTexture(r, g, b, 1)
			row.Rank:SetShown(db.showRank and true or false)
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
		window._wheel = nil
		window._scrollTarget = 0
		PlaceScroll(window, 0)
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
	local sheen = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	sheen:SetTexture(WHITE)
	if CreateColor then
		if not pcall(sheen.SetGradient, sheen, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.12)) then
			sheen:SetColorTexture(1, 1, 1, 0.06)
		end
	else
		sheen:SetColorTexture(1, 1, 1, 0.06)
	end
	row.Sheen = sheen
	local tint = bar:CreateTexture(nil, "ARTWORK", nil, 3)
	tint:SetAllPoints(bar)
	tint:SetColorTexture(1, 1, 1, 0.05)
	tint:Hide()
	row.SelfTint = tint
	local text = CreateFrame("Frame", nil, bar)
	text:SetAllPoints(bar)
	text:SetFrameLevel(bar:GetFrameLevel() + 2)
	local rank = text:CreateFontString(nil, "OVERLAY")
	rank:SetJustifyH("RIGHT")
	rank:SetTextColor(0.78, 0.79, 0.82)
	rank:Hide()
	row.Rank = rank
	local name = text:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	name:SetTextColor(1, 1, 1)
	row.Name = name
	local value = text:CreateFontString(nil, "OVERLAY")
	value:SetJustifyH("RIGHT")
	value:SetWordWrap(false)
	value:SetTextColor(1, 1, 1)
	row.Value = value
	local value2 = text:CreateFontString(nil, "OVERLAY")
	value2:SetJustifyH("RIGHT")
	value2:SetWordWrap(false)
	value2:SetTextColor(1, 1, 1)
	value2:Hide()
	row.Value2 = value2
	local mark = text:CreateTexture(nil, "OVERLAY", nil, 7)
	mark:SetPoint("TOPLEFT", bar, "TOPLEFT")
	mark:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
	mark:SetWidth(2)
	mark:Hide()
	row.Self = mark
	local hover = text:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints(row)
	hover:SetColorTexture(1, 1, 1, 0.07)
	hover:Hide()
	row:SetScript("OnEnter", function(self)
		hover:Show()
		local src = self._soulTip
		if not src or InCombatLockdown() then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		pcall(function()
			GameTooltip:AddLine(self.Name:GetText() or "", 1, 1, 1)
			GameTooltip:AddDoubleLine("Total", Abbrev(src.totalAmount), 0.7, 0.7, 0.75, 1, 1, 1)
			GameTooltip:AddDoubleLine("Per second", Abbrev(src.amountPerSecond), 0.7, 0.7, 0.75, 1, 1, 1)
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

local function HeaderButton(parent, kind, tip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(16, 16)
	local glyph = Glyph(button, kind)
	glyph:SetPoint("CENTER")
	button.Glyph = glyph
	button:SetScript("OnEnter", function(self)
		glyph:SetColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(tip, 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		glyph:SetColor(ICON_IDLE[1], ICON_IDLE[2], ICON_IDLE[3])
		GameTooltip:Hide()
	end)
	return button
end

local function MenuItems(list)
	local items = {}
	for i = 1, #list do items[i] = { value = list[i].key, label = list[i].label } end
	return items
end
local TYPE_ITEMS = MenuItems(TYPES)
local SEGMENT_ITEMS = MenuItems(SEGMENTS)

local function MakeWindow(index)
	local window = CreateFrame("Frame", "SoulUIMeter" .. index, UIParent)
	window._index = index
	window._animKey = "meter" .. index
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
	line:SetHeight(1)
	window.HeaderLine = line

	local back = Glyph(header, "back")
	back:Hide()
	window.Back = back
	local title = header:CreateFontString(nil, "OVERLAY")
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	window.Title = title
	local dot = header:CreateTexture(nil, "OVERLAY")
	dot:SetColorTexture(1, 1, 1, 0.3)
	window.Dot = dot
	local segment = header:CreateFontString(nil, "OVERLAY")
	segment:SetJustifyH("LEFT")
	segment:SetWordWrap(false)
	segment:SetTextColor(0.6, 0.62, 0.66)
	window.Segment = segment
	local clock = header:CreateFontString(nil, "OVERLAY")
	clock:SetJustifyH("RIGHT")
	clock:SetTextColor(0.78, 0.79, 0.82)
	window.Clock = clock

	local close = HeaderButton(header, "close", "Hide this meter")
	local reset = HeaderButton(header, "reset", "Reset all meter data")
	local seg = HeaderButton(header, "swap", "Current / Overall")
	window.Buttons = { close = close, reset = reset, segment = seg }
	window.ButtonOrder = { close, reset, seg }
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
		window._breakdown = nil
		DM:NewView(index)
	end)
	-- Click the title: pick the meter type (right-click: the segment). While a
	-- spell breakdown is open, a click goes back.
	header:SetScript("OnClick", function(_, button)
		if window._breakdown then
			window._breakdown = nil
			DM:NewView(index)
			return
		end
		local UI = Soul.UI
		if not UI then return end
		if button == "RightButton" then
			UI.OpenMenu(title, SEGMENT_ITEMS, DB().windows[index].segment, function(key)
				DB().windows[index].segment = key
				DM:NewView(index)
			end, 160)
		else
			UI.OpenMenu(title, TYPE_ITEMS, DB().windows[index].type, function(key)
				DB().windows[index].type = key
				DM:NewView(index)
			end, 180)
		end
	end)

	-- Body: clips the row strip so rows can glide in and out.
	local body = CreateFrame("Frame", nil, window)
	body:SetClipsChildren(true)
	body:EnableMouseWheel(false)
	window.Body = body
	local content = CreateFrame("Frame", nil, body)
	content:SetPoint("TOPLEFT")
	content:SetPoint("TOPRIGHT")
	content:SetHeight(1)
	window.Content = content
	-- Scroll thumb on its own layer above the rows so a bar never covers it.
	local thumbHolder = CreateFrame("Frame", nil, body)
	thumbHolder:SetAllPoints(body)
	thumbHolder:SetFrameLevel(content:GetFrameLevel() + 10)
	thumbHolder:EnableMouse(false)
	local thumb = thumbHolder:CreateTexture(nil, "OVERLAY", nil, 7)
	thumb:SetColorTexture(1, 1, 1, 0.22)
	thumb:SetWidth(2)
	thumb:Hide()
	window.Thumb = thumb
	local empty = body:CreateFontString(nil, "OVERLAY")
	empty:SetPoint("CENTER", body, "CENTER", 0, 0)
	empty:SetTextColor(0.5, 0.52, 0.56)
	empty:Hide()
	window.Empty = empty

	body:SetScript("OnMouseWheel", function(_, delta)
		ScrollBy(window, delta)
	end)
	window._animStep = function()
		local now = GetTime()
		local dt = now - (window._animTime or now)
		window._animTime = now
		local pos = window._scrollPos or 0
		local target = window._scrollTarget or 0
		pos = pos + (target - pos) * (1 - math_exp(-dt * 16))
		if math_abs(target - pos) < 0.5 then
			pos = target
			StopScrollAnim(window)
		end
		if PlaceScroll(window, pos) then DM:PaintWindow(index) end
	end

	window.rows = {}
	for i = 1, POOL do
		local row = MakeRow(content)
		row:SetScript("OnClick", function(self, button)
			if InCombatLockdown() then return end
			if window._breakdown or button == "RightButton" then
				window._breakdown = nil
			else
				local src = self._soulTip
				window._breakdown = self._soulIndex
				window._breakdownName = nil
				window._breakdownColor = nil
				if src then
					local name = self.Name:GetText()
					if not IsSecret(name) and type(name) == "string" and name ~= "" then
						window._breakdownName = name
					end
					local class = src.classFilename
					if not IsSecret(class) and type(class) == "string" then
						window._breakdownColor = RAID_CLASS_COLORS[class]
					end
				end
			end
			DM:NewView(index)
		end)
		window.rows[i] = row
	end
	window._paintKey = (window._paintKey or 0) + 1000
	window._scrollPos = 0
	window._scrollTarget = 0
	window._first = 1
	window._partial = false
	window._visible = 8
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
	driver = Soul.Ticker and Soul.Ticker:NewDriver() or nil
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
			getEnabled = function() return DB().enabled and DB().windows[index].enabled end,
			setEnabled = function(on)
				local db = DB()
				db.windows[index].enabled = on and true or false
				if on then db.enabled = true end
				DM:Apply()
			end,
			fallback = function()
				local cfg = DB().windows[index]
				return { point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y }
			end,
			onResize = function(width, height, dir)
				local db = DB()
				local rows = db.rows or 6
				if rows < 1 then rows = 1 end
				local oldW = db.width or width
				local oldH = db.rowHeight or 18
				if dir == 1 or dir == -1 then
					db.width = Soul:ScaleStep(oldW, dir, 120, 500)
					db.rowHeight = Soul:ScaleStep(oldH, dir, 10, 40)
				else
					db.width = Soul:MatchSize(oldW, width, 120, 500)
					local rowH = (height - (db.headerHeight or 22)) / rows - (db.rowGap or 1)
					db.rowHeight = Soul:MatchSize(oldH, rowH, 10, 40)
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
	local function onMeterData()
		DM:RefreshAll()
	end
	self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", onMeterData)
	self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", onMeterData)
	self:RegisterEvent("DAMAGE_METER_RESET", function()
		DM._pinned = nil
		for i = 1, WINDOWS do
			local window = DM.windows[i]
			window._breakdown = nil
			ResetScroll(window)
		end
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
