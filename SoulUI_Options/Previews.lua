if SoulUI_Blocked or not SoulUI then return end

-- Live previews shown at the top of a settings page. Each builder makes a mock
-- of the element from the same settings the real frame reads, and returns
-- (height, update). The panel calls update after every change on the page.

local Soul = SoulUI
local UI = Soul.UI
local P = {}
Soul.Previews = P

local function ClassRGB()
	local _, class = UnitClass("player")
	local color = type(class) == "string" and RAID_CLASS_COLORS[class]
	if color then return color.r, color.g, color.b end
	return 0.53, 0.53, 0.93
end

local function Bar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(Soul:StatusbarTexture())
	bar:SetMinMaxValues(0, 1)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
	bar.bg = bg
	return bar
end

local function Caption(parent, text)
	local font = UI.Text(parent, 11, UI.C.faint, "CENTER")
	font:SetText(text)
	return font
end

-- Fit a mock of width w into the preview without upscaling.
local function Fit(frame, w, h, maxW, maxH)
	local scale = math.min(1, maxW / math.max(1, w), maxH / math.max(1, h))
	frame:SetScale(scale)
end

------------------------------------------------------------------------------
-- Unit frame
------------------------------------------------------------------------------

function P.UnitFrame(getUnit, getCfg)
	return function(holder, width)
		local height = 150
		local stage = CreateFrame("Frame", nil, holder)
		stage:SetPoint("CENTER", holder, "CENTER", 0, -6)
		local health = Bar(stage)
		health:SetAllPoints()
		local name = health:CreateFontString(nil, "OVERLAY")
		local text = health:CreateFontString(nil, "OVERLAY")
		local power = Bar(stage)
		local cast = Bar(stage)
		local castText = cast:CreateFontString(nil, "OVERLAY")
		castText:SetPoint("LEFT", 4, 0)
		local function update()
			local cfg = getCfg()
			if not cfg then return end
			local w, h = cfg.width or 200, cfg.height or 40
			local total = h + (cfg.showPower and (cfg.powerHeight or 6) or 0)
			stage:SetSize(w, total)
			health:ClearAllPoints()
			health:SetPoint("TOPLEFT")
			health:SetPoint("TOPRIGHT")
			health:SetHeight(h)
			health:SetStatusBarTexture(Soul:StatusbarTexture())
			health:SetValue(0.78)
			local r, g, b = ClassRGB()
			if type(cfg.color) == "table" then r, g, b = cfg.color[1], cfg.color[2], cfg.color[3] end
			if getUnit() ~= "player" and getUnit() ~= "pet" and type(cfg.color) ~= "table" then r, g, b = 0.85, 0.2, 0.2 end
			health:SetStatusBarColor(r, g, b)
			local auto = math.max(10, math.min(18, math.floor(h * 0.26 + 0.5)))
			Soul:ApplyFont(name, (cfg.nameSize or 0) > 0 and cfg.nameSize or auto, "OUTLINE")
			Soul:ApplyFont(text, (cfg.healthSize or 0) > 0 and cfg.healthSize or auto, "OUTLINE")
			name:ClearAllPoints()
			text:ClearAllPoints()
			if cfg.namePosition == "above" then
				name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 1, 2)
			elseif cfg.textLayout == "center" then
				name:SetPoint("LEFT", health, "LEFT", 6, 0)
			else
				name:SetPoint("TOPLEFT", health, "TOPLEFT", 5, -4)
			end
			if cfg.textLayout == "center" then
				text:SetPoint("RIGHT", health, "RIGHT", -6, 0)
			else
				text:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -5, 4)
			end
			name:SetText(UnitName("player") or "Name")
			name:SetShown(cfg.showName ~= false)
			local format = cfg.healthFormat or "both"
			local sample = { both = "925K | 78%", value = "925K", percent = "78%", none = "" }
			text:SetText(sample[format] or "")
			power:SetShown(cfg.showPower and true or false)
			power:ClearAllPoints()
			power:SetPoint("TOPLEFT", health, "BOTTOMLEFT")
			power:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT")
			power:SetHeight(cfg.powerHeight or 6)
			power:SetStatusBarTexture(Soul:StatusbarTexture())
			power:SetValue(0.6)
			power:SetStatusBarColor(0.3, 0.45, 1)
			local showCast = cfg.showCast and getUnit() ~= "player"
			cast:SetShown(showCast and true or false)
			if showCast then
				local ch = cfg.castHeight or 16
				cast:ClearAllPoints()
				cast:SetSize(cfg.castWidth or w, ch)
				cast:SetPoint("BOTTOM", stage, "TOP", 0, 4)
				cast:SetStatusBarTexture(Soul:StatusbarTexture())
				cast:SetValue(0.55)
				local c = Soul.Cast.Settings().interruptible
				if type(cfg.castColor) == "table" then c = cfg.castColor end
				cast:SetStatusBarColor(c[1], c[2], c[3])
				Soul:ApplyFont(castText, math.max(10, math.floor(ch * 0.6)), "OUTLINE")
				castText:SetText("Shadow Bolt")
			end
			Fit(stage, w, total + 40, width - 80, height - 40)
		end
		update()
		return height, update
	end
end

------------------------------------------------------------------------------
-- Cast colors
------------------------------------------------------------------------------

function P.Casts(holder, width)
	local height = 130
	local samples = {
		{ label = "Interruptible", kind = "interruptible" },
		{ label = "Your interrupt on cooldown", kind = "kickCooldown" },
		{ label = "Not interruptible", kind = "locked" },
		{ label = "Important, not interruptible", kind = "stun" },
	}
	local bars = {}
	local barW = math.min(200, math.floor((width - 200) / 4))
	for i = 1, #samples do
		local host = CreateFrame("Frame", nil, holder)
		host:SetSize(barW, 18)
		host:SetPoint("LEFT", holder, "LEFT", 40 + (i - 1) * (barW + 26), -4)
		local bar = Bar(host)
		bar:SetAllPoints()
		bar:SetValue(0.62)
		local text = bar:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(text, 11, "OUTLINE")
		text:SetPoint("LEFT", 4, 0)
		text:SetText("Spell name")
		local cap = Caption(holder, samples[i].label)
		cap:SetPoint("TOP", host, "BOTTOM", 0, -8)
		bars[i] = { host = host, bar = bar, kind = samples[i].kind }
	end
	local function update()
		local cfg = Soul.Cast.Settings()
		for i = 1, #bars do
			local item = bars[i]
			item.bar:SetStatusBarTexture(Soul:StatusbarTexture())
			local deco = Soul.Cast.Decorate(item.host, item.bar)
			Soul.Cast.Size(item.host, 18)
			local c = cfg.interruptible
			if item.kind == "kickCooldown" then c = cfg.kickColoring and cfg.kickCooldown or cfg.interruptible end
			if item.kind == "locked" or item.kind == "stun" then c = cfg.locked end
			item.bar:SetStatusBarColor(c[1], c[2], c[3])
			local locked = item.kind == "locked" or item.kind == "stun"
			deco.lock:SetAlpha((locked and cfg.showLock) and 1 or 0)
			local ic = cfg.important
			if deco.glowEdges then deco.glowEdges:SetColor(ic[1], ic[2], ic[3], 1) end
			if deco.glowInner then deco.glowInner:SetColor(ic[1], ic[2], ic[3], 0.6) end
			deco.glow:SetAlpha((item.kind == "stun" and cfg.showImportant) and 1 or 0)
			deco.stunHolder:SetAlpha((item.kind == "stun" and cfg.showStun) and 1 or 0)
			deco.badge:SetAlpha(1)
		end
	end
	update()
	return height, update
end

------------------------------------------------------------------------------
-- Nameplate
------------------------------------------------------------------------------

function P.Nameplate(holder, width)
	local height = 150
	local stage = CreateFrame("Frame", nil, holder)
	stage:SetPoint("CENTER", 0, -8)
	local health = Bar(stage)
	local name = health:CreateFontString(nil, "OVERLAY")
	name:SetPoint("LEFT", 4, 0)
	local pct = health:CreateFontString(nil, "OVERLAY")
	pct:SetPoint("RIGHT", -4, 0)
	local cast = CreateFrame("Frame", nil, stage)
	local castBar = Bar(cast)
	castBar:SetAllPoints()
	castBar:SetValue(0.5)
	local castText = castBar:CreateFontString(nil, "OVERLAY")
	castText:SetPoint("LEFT", 4, 0)
	local icons = {}
	for i = 1, 6 do
		local icon = stage:CreateTexture(nil, "ARTWORK")
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icons[i] = icon
	end
	local purge = {}
	for i = 1, 2 do
		local holderIcon = CreateFrame("Frame", nil, stage)
		local tex = holderIcon:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		tex:SetTexture(i == 1 and 136085 or 132126)
		UI.Edge(holderIcon, 0.25, 0.65, 1, 1)
		purge[i] = holderIcon
	end
	local purgeOutline = CreateFrame("Frame", nil, stage)
	local outline = UI.Edge(purgeOutline, 0.25, 0.65, 1, 1)
	local debuffArt = { 136197, 135817, 136118, 132090, 135735, 136207 }
	local function update()
		local cfg = Soul:ModuleDB("Nameplates")
		local w, h = cfg.width or 140, cfg.height or 16
		stage:SetSize(w, h)
		health:ClearAllPoints()
		health:SetPoint("TOPLEFT")
		health:SetSize(w, h)
		health:SetStatusBarTexture(Soul:StatusbarTexture())
		health:SetStatusBarColor(0.85, 0.15, 0.15)
		health:SetValue(0.64)
		local gap = cfg.spacing or 2
		local above = (cfg.namePos or "above") == "above"
		name:ClearAllPoints()
		if above then
			name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, gap)
		else
			name:SetPoint("LEFT", health, "LEFT", 4, 0)
		end
		Soul:ApplyFont(name, (cfg.nameSize or 0) > 0 and cfg.nameSize or math.max(10, h - 4), "OUTLINE")
		Soul:ApplyFont(pct, (cfg.percentSize or 0) > 0 and cfg.percentSize or math.max(9, h - 5), "OUTLINE")
		name:SetText(cfg.showName and "Venomous Acolyte" or "")
		pct:SetText(cfg.showPercent ~= false and "64%" or "")
		local ch = cfg.castHeight or 12
		cast:SetShown(cfg.showCast and true or false)
		cast:ClearAllPoints()
		cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -gap)
		cast:SetSize(w, ch)
		castBar:SetStatusBarTexture(Soul:StatusbarTexture())
		local c = Soul.Cast.Settings().interruptible
		castBar:SetStatusBarColor(c[1], c[2], c[3])
		Soul:ApplyFont(castText, math.max(9, ch - 2), "OUTLINE")
		castText:SetText("Poison Bolt")
		local size = cfg.debuffSize or 20
		local count = cfg.showDebuffs ~= false and math.min(3, cfg.debuffMax or 5) or 0
		for i = 1, #icons do
			icons[i]:ClearAllPoints()
			icons[i]:SetSize(size, size)
			icons[i]:SetPoint("BOTTOMLEFT", health, "TOPLEFT", (i - 1) * (size + 2), (above and cfg.showName) and (gap * 2 + math.max(10, h - 4)) or (gap + 1))
			icons[i]:SetTexture(debuffArt[i])
			icons[i]:SetShown(i <= count)
		end
		local mode = cfg.purge or "auto"
		local magic, enrage = Soul.Auras.OffensiveDispel()
		local showPurge = mode == "always" or (mode == "auto" and (magic or enrage))
		local psize = cfg.purgeSize or 20
		for i = 1, #purge do
			purge[i]:ClearAllPoints()
			purge[i]:SetSize(psize, psize)
			purge[i]:SetPoint("LEFT", health, "RIGHT", 4 + (i - 1) * (psize + 2), 0)
			purge[i]:SetShown(showPurge and true or false)
		end
		purgeOutline:ClearAllPoints()
		purgeOutline:SetAllPoints(health)
		purgeOutline:SetShown(showPurge and cfg.purgeGlow ~= false)
		outline:SetColor(0.25, 0.65, 1, 1)
		Fit(stage, w + psize * 3, h + ch + size + 30, width - 120, height - 50)
	end
	update()
	return height, update
end

------------------------------------------------------------------------------
-- Class resource tiles
------------------------------------------------------------------------------

function P.Pips(holder, width)
	local height = 110
	local stage = CreateFrame("Frame", nil, holder)
	stage:SetPoint("CENTER", 0, -6)
	local tiles = {}
	for i = 1, 5 do
		local tile = CreateFrame("Frame", nil, stage)
		local edge = tile:CreateTexture(nil, "BACKGROUND")
		edge:SetAllPoints()
		edge:SetColorTexture(0, 0, 0, 1)
		local bar = Bar(tile)
		local count = bar:CreateFontString(nil, "OVERLAY")
		count:SetPoint("CENTER")
		tiles[i] = { tile = tile, edge = edge, bar = bar, count = count }
	end
	local function update()
		local cfg = Soul:ModuleDB("ResourceBars").pips
		if type(cfg) ~= "table" then return end
		local w, h = cfg.width or 276, cfg.height or 32
		local gap = cfg.gap or 2
		stage:SetSize(w, h)
		local tw = (w - gap * 4) / 5
		local r, g, b = ClassRGB()
		if cfg.colorMode == "custom" and type(cfg.color) == "table" then r, g, b = cfg.color[1], cfg.color[2], cfg.color[3] end
		local e = type(cfg.emptyColor) == "table" and cfg.emptyColor or { 0.17, 0.17, 0.17 }
		local countSize = (cfg.countSize or 0) > 0 and cfg.countSize or math.max(10, math.floor(h * 0.62 + 0.5))
		for i = 1, 5 do
			local t = tiles[i]
			t.tile:ClearAllPoints()
			t.tile:SetSize(tw, h)
			t.tile:SetPoint("TOPLEFT", stage, "TOPLEFT", (i - 1) * (tw + gap), 0)
			local inset = cfg.border ~= false and 1 or 0
			t.edge:SetShown(cfg.border ~= false)
			t.bar:ClearAllPoints()
			t.bar:SetPoint("TOPLEFT", inset, -inset)
			t.bar:SetPoint("BOTTOMRIGHT", -inset, inset)
			t.bar:SetStatusBarTexture(Soul:StatusbarTexture())
			t.bar:SetStatusBarColor(r, g, b)
			t.bar.bg:SetColorTexture(e[1], e[2], e[3], 1)
			t.bar:SetValue(i <= 3 and 1 or (i == 4 and 0.4 or 0))
			Soul:ApplyFont(t.count, countSize, "OUTLINE")
			-- One centered number, on the middle pip (matches the live bar).
			t.count:SetText(i == 3 and cfg.showCount ~= false and "3" or "")
			t.count:SetParent(stage)
			t.count:SetDrawLayer("OVERLAY", 7)
		end
		Fit(stage, w, h, width - 80, height - 40)
	end
	update()
	return height, update
end

------------------------------------------------------------------------------
-- Action bar row
------------------------------------------------------------------------------

function P.ActionBar(getBar)
	return function(holder, width)
		local height = 120
		local stage = CreateFrame("Frame", nil, holder)
		stage:SetPoint("CENTER", 0, -6)
		local art = { 136197, 135817, 136118, 132090, 135735, 136207, 135808, 136145, 136186, 135824, 136183, 136224 }
		local buttons = {}
		for i = 1, 12 do
			local button = CreateFrame("Frame", nil, stage)
			local edge = button:CreateTexture(nil, "BACKGROUND")
			edge:SetAllPoints()
			edge:SetColorTexture(0, 0, 0, 1)
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetTexture(art[i])
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			local key = button:CreateFontString(nil, "OVERLAY")
			key:SetPoint("TOPRIGHT", -2, -2)
			buttons[i] = { frame = button, edge = edge, icon = icon, key = key }
		end
		local function update()
			local db = Soul:ModuleDB("ActionBars")
			local cfg = getBar()
			if not cfg then return end
			local count = math.max(1, math.min(12, cfg.buttons or 12))
			local size = cfg.size or 45
			local gap = cfg.spacing or 1
			local lines = math.max(1, math.min(count, cfg.rows or 1))
			lines = math.ceil(count / math.ceil(count / lines))
			local cols, rows
			if cfg.vertical then cols, rows = lines, math.ceil(count / lines) else rows, cols = lines, math.ceil(count / lines) end
			local w = cols * size + (cols - 1) * gap
			local h = rows * size + (rows - 1) * gap
			stage:SetSize(w, h)
			local hotkey = (db.hotkeySize or 0) > 0 and db.hotkeySize or math.max(8, math.floor(size * 0.27 + 0.5))
			for i = 1, 12 do
				local b = buttons[i]
				if i <= count then
					local col, row
					if cfg.vertical then col, row = math.floor((i - 1) / rows), (i - 1) % rows
					else col, row = (i - 1) % cols, math.floor((i - 1) / cols) end
					b.frame:ClearAllPoints()
					b.frame:SetSize(size, size)
					b.frame:SetPoint("TOPLEFT", stage, "TOPLEFT", col * (size + gap), -row * (size + gap))
					local inset = db.showBorder and 1 or 0
					b.edge:SetShown(db.showBorder and true or false)
					b.icon:ClearAllPoints()
					b.icon:SetPoint("TOPLEFT", inset, -inset)
					b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
					Soul:ApplyFont(b.key, hotkey, "OUTLINE")
					b.key:SetText(cfg.showHotkey ~= false and tostring(i % 10) or "")
					b.frame:Show()
				else
					b.frame:Hide()
				end
			end
			stage:SetAlpha(cfg.enabled and 1 or 0.3)
			Fit(stage, w, h, width - 80, height - 30)
		end
		update()
		return height, update
	end
end

------------------------------------------------------------------------------
-- Party / raid frames
------------------------------------------------------------------------------

function P.Group(kind)
	return function(holder, width)
		local height = kind == "party" and 220 or 170
		local stage = CreateFrame("Frame", nil, holder)
		stage:SetPoint("CENTER", 0, -6)
		local cells = {}
		local names = { "Aleindia", "Hencehammer", "Capcasey", "Boopsie", "Elleybae" }
		local classes = { "PALADIN", "WARRIOR", "WARLOCK", "DRUID", "ROGUE" }
		for i = 1, 10 do
			local bar = Bar(stage)
			local name = bar:CreateFontString(nil, "OVERLAY")
			name:SetPoint("LEFT", 4, 0)
			cells[i] = { bar = bar, name = name }
		end
		local function update()
			local cfg = Soul:ModuleDB("GroupFrames")[kind]
			if type(cfg) ~= "table" then return end
			local w, h, gap = cfg.width or 100, cfg.height or 40, cfg.spacing or 2
			local count = kind == "party" and 5 or 10
			local vertical = kind == "party" and cfg.orientation ~= "horizontal"
			local cols = vertical and 1 or 5
			local rows = math.ceil(count / cols)
			local sw, sh = cols * w + (cols - 1) * gap, rows * h + (rows - 1) * gap
			stage:SetSize(sw, sh)
			for i = 1, #cells do
				local cell = cells[i]
				if i <= count then
					local col = (i - 1) % cols
					local row = math.floor((i - 1) / cols)
					cell.bar:ClearAllPoints()
					cell.bar:SetSize(w, h)
					cell.bar:SetPoint("TOPLEFT", stage, "TOPLEFT", col * (w + gap), -row * (h + gap))
					cell.bar:SetStatusBarTexture(Soul:StatusbarTexture())
					local c = RAID_CLASS_COLORS[classes[(i - 1) % 5 + 1]]
					cell.bar:SetStatusBarColor(c.r, c.g, c.b)
					cell.bar:SetValue(0.55 + ((i * 37) % 45) / 100)
					Soul:ApplyFont(cell.name, cfg.font or 12, "OUTLINE")
					cell.name:SetText(names[(i - 1) % 5 + 1])
					cell.bar:Show()
				else
					cell.bar:Hide()
				end
			end
			Fit(stage, sw, sh, width - 80, height - 30)
		end
		update()
		return height, update
	end
end

------------------------------------------------------------------------------
-- Damage meter
------------------------------------------------------------------------------

function P.Meter(holder, width)
	local height = 170
	local stage = CreateFrame("Frame", nil, holder)
	stage:SetPoint("CENTER", 0, -6)
	local bg = stage:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	local head = stage:CreateTexture(nil, "BORDER")
	local headLine = stage:CreateTexture(nil, "ARTWORK")
	local title = stage:CreateFontString(nil, "OVERLAY")
	local seg = stage:CreateFontString(nil, "OVERLAY")
	local rows = {}
	local data = {
		{ "Elleybae", "ROGUE", 1.0, "138M (412K)" },
		{ "Capcasey", "WARLOCK", 0.88, "122M (364K)" },
		{ "Boopsie", "DRUID", 0.80, "111M (331K)" },
		{ "Hencehammer", "WARRIOR", 0.74, "102M (304K)" },
		{ "Aleindia", "PALADIN", 0.13, "18M (54K)" },
	}
	for i = 1, #data do
		local icon = stage:CreateTexture(nil, "ARTWORK")
		icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data[i][2]]
		if coords then icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
		local bar = Bar(stage)
		local name = bar:CreateFontString(nil, "OVERLAY")
		local value = bar:CreateFontString(nil, "OVERLAY")
		value:SetPoint("RIGHT", -5, 0)
		rows[i] = { icon = icon, bar = bar, name = name, value = value }
	end
	local function update()
		local db = Soul:ModuleDB("DamageMeters")
		local w = db.width or 260
		local rh = db.rowHeight or 18
		local gap = db.rowGap or 1
		local hh = db.headerHeight or 22
		local count = #rows
		local h = hh + gap + count * (rh + gap) - gap
		stage:SetSize(w, h)
		bg:SetColorTexture(0, 0, 0, db.bgAlpha or 0.75)
		local hc = db.headerColor or { 0.106, 0.106, 0.106, 1 }
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT")
		head:SetPoint("TOPRIGHT")
		head:SetHeight(hh)
		head:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 1)
		local r, g, b = Soul:Accent()
		headLine:ClearAllPoints()
		headLine:SetPoint("TOPLEFT", 0, -hh + 1)
		headLine:SetPoint("TOPRIGHT", 0, -hh + 1)
		headLine:SetHeight(1)
		headLine:SetColorTexture(r, g, b, db.headerLine == false and 0 or 0.9)
		local hf = (db.headerFontSize or 0) > 0 and db.headerFontSize or math.max(10, math.floor(hh * 0.52 + 0.5))
		Soul:ApplyFont(title, hf, "OUTLINE")
		Soul:ApplyFont(seg, math.max(9, hf - 2), "OUTLINE")
		title:ClearAllPoints()
		title:SetPoint("LEFT", stage, "TOPLEFT", 7, -hh / 2)
		title:SetText("Damage Done")
		if db.headerAccent == false then title:SetTextColor(1, 1, 1) else title:SetTextColor(r, g, b) end
		seg:ClearAllPoints()
		seg:SetPoint("LEFT", title, "RIGHT", 6, 0)
		seg:SetText("Current")
		seg:SetTextColor(0.55, 0.55, 0.6)
		local fs = (db.fontSize or 0) > 0 and db.fontSize or math.max(9, math.floor(rh * 0.62 + 0.5))
		local formats = { total = "138M", persec = "412K", pipe = "138M | 412K", percent = "138M  28%" }
		for i = 1, count do
			local row = rows[i]
			local y = -hh - gap - (i - 1) * (rh + gap)
			local iconOn = db.showIcons ~= false
			row.icon:ClearAllPoints()
			row.icon:SetSize(rh, rh)
			row.icon:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, y)
			row.icon:SetShown(iconOn)
			row.bar:ClearAllPoints()
			row.bar:SetPoint("TOPLEFT", stage, "TOPLEFT", iconOn and rh + 1 or 0, y)
			row.bar:SetPoint("TOPRIGHT", stage, "TOPRIGHT", 0, y)
			row.bar:SetHeight(rh)
			row.bar:SetStatusBarTexture(db.texture and Soul:Media("statusbar", db.texture) or Soul:StatusbarTexture())
			local c = RAID_CLASS_COLORS[data[i][2]]
			if db.classColors == false then
				row.bar:SetStatusBarColor(r, g, b, db.barAlpha or 1)
			else
				row.bar:SetStatusBarColor(c.r, c.g, c.b, db.barAlpha or 1)
			end
			row.bar.bg:SetColorTexture(0, 0, 0, 0.35)
			row.bar:SetValue(data[i][3])
			Soul:ApplyFont(row.name, fs, "OUTLINE")
			Soul:ApplyFont(row.value, fs, "OUTLINE")
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", row.bar, "LEFT", 5, 0)
			row.name:SetText((db.showRank and (i .. ". ") or "") .. data[i][1])
			row.value:SetText(formats[db.valueFormat or "both"] or data[i][4])
		end
		Fit(stage, w, h, width - 80, height - 26)
	end
	update()
	return height, update
end
