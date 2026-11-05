if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI
local RB = Soul:NewModule("ResourceBars", "SoulUI_ResourceBars")

local GCD_SPELL = 61304
local MAX_PIPS = 7

local function Power(name, fallback)
	local enum = Enum and Enum.PowerType
	local value = enum and enum[name]
	if not Soul.Secret.IsSecret(value) and type(value) == "number" then return value end
	return fallback
end

local CLASS = {
	ROGUE = { mode = "pips", power = Power("ComboPoints", 4), color = { 0.95, 0.85, 0.20 } },
	DRUID = { mode = "pips", power = Power("ComboPoints", 4), color = { 0.95, 0.85, 0.20 } },
	PALADIN = { mode = "pips", power = Power("HolyPower", 9), color = { 0.95, 0.90, 0.30 } },
	MONK = { mode = "pips", power = Power("Chi", 12), color = { 0.20, 0.85, 0.45 } },
	WARLOCK = { mode = "pips", power = Power("SoulShards", 7), color = { 0.55, 0.25, 0.85 } },
	MAGE = { mode = "pips", power = Power("ArcaneCharges", 16), color = { 0.20, 0.55, 0.95 } },
	EVOKER = { mode = "pips", power = Power("Essence", 19), color = { 0.20, 0.80, 0.85 } },
	DEATHKNIGHT = { mode = "runes", color = { 0.80, 0.15, 0.20 } },
}

local function DB()
	return Soul:ModuleDB("ResourceBars")
end

local function Reveal(frame, on)
	frame:SetAlpha(on and 1 or 0)
end

local function MakeBar(name, height)
	local frame = CreateFrame("Frame", name, UIParent)
	frame:SetHeight(height)
	frame:EnableMouse(false)
	local bar = Soul:StatusBar(frame)
	bar:SetAllPoints()
	bar:EnableMouse(false)
	frame.Bar = bar
	Soul:Border(frame)
	return frame
end

local function ClassSpec()
	local _, class = UnitClass("player")
	if Soul.Secret.IsSecret(class) or type(class) ~= "string" then return nil end
	return CLASS[class]
end

local function PipCount(spec)
	if not spec or spec.mode ~= "pips" then return 0 end
	local max = UnitPowerMax("player", spec.power)
	if Soul.Secret.IsSecret(max) then return spec.power == Power("ComboPoints", 4) and 5 or MAX_PIPS end
	if type(max) ~= "number" or max <= 0 then return 0 end
	if max > MAX_PIPS then return MAX_PIPS end
	return max
end

-- Default fill is the class color itself, the same color as the player health
-- bar, which is how the reference draws its shards.
local function PipFill()
	local cfg = DB().pips
	if cfg.colorMode == "custom" and type(cfg.color) == "table" then
		return cfg.color[1], cfg.color[2], cfg.color[3]
	end
	local _, class = UnitClass("player")
	if not Soul.Secret.IsSecret(class) and type(class) == "string" then
		local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
		if color and color.GetRGB then return color:GetRGB() end
		color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then return color.r, color.g, color.b end
	end
	local spec = ClassSpec()
	if spec then return spec.color[1], spec.color[2], spec.color[3] end
	return 0.53, 0.53, 0.93
end

local function EmptyColor()
	local color = DB().pips.emptyColor
	if type(color) == "table" then return color[1], color[2], color[3] end
	return 0.17, 0.17, 0.17
end

local function PaintPip(pip)
	local r, g, b = PipFill()
	pip:SetStatusBarColor(r, g, b)
	if pip.bg then
		local er, eg, eb = EmptyColor()
		pip.bg:SetColorTexture(er, eg, eb, 1)
	end
end

local function LayoutPips(count)
	local holder = RB.pips
	local cfg = DB().pips
	local px = Soul.Pixel:Scale(1)
	local gap = Soul.Pixel:Scale(cfg.gap or 2)
	local width = cfg.width or holder:GetWidth()
	local height = cfg.height or holder:GetHeight()
	if type(width) ~= "number" or width < 10 then width = 250 end
	if type(height) ~= "number" or height < 4 then height = 18 end
	local pipW = width
	if count > 0 then
		pipW = Soul.Pixel:Scale((width - gap * (count - 1)) / count)
	end
	if pipW < 4 then pipW = 4 end
	local countSize = cfg.countSize or 0
	if countSize <= 0 then countSize = math.max(10, math.floor(height * 0.62 + 0.5)) end
	local bordered = cfg.border ~= false
	-- UNIT_POWER_FREQUENT lands here; only re-lay the tiles when the shape changed.
	local sig = count .. ":" .. width .. ":" .. height .. ":" .. gap .. ":" .. tostring(bordered) .. ":" .. tostring(cfg.gloss) .. ":" .. countSize
	if RB._pipSig == sig then return end
	RB._pipSig = sig
	local inset = bordered and px or 0
	for i = 1, MAX_PIPS do
		local pip = RB.pipBars[i]
		local tile = pip.tile
		if i <= count and count > 0 then
			tile:Show()
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (pipW + gap), 0)
			-- The last tile takes up any rounding so the row keeps its width.
			if i == count then
				tile:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
			else
				tile:SetSize(pipW, height)
			end
			Soul:ShowBorder(tile, bordered, 1)
			pip:ClearAllPoints()
			pip:SetPoint("TOPLEFT", tile, "TOPLEFT", inset, -inset)
			pip:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -inset, inset)
			if pip.gloss then
				pip.gloss:SetShown(cfg.gloss and true or false)
				pip.gloss:SetHeight(math.max(2, math.floor(height * 0.4)))
			end
			if pip.Count then
				Soul:ApplyFont(pip.Count, countSize, "OUTLINE")
				pip.Count:SetText(tostring(i))
			end
		else
			tile:Hide()
		end
	end
end

-- Count text sits on the last full tile ("3" on the third shard). With a plain
-- value Lua picks the tile; with a secret value each tile's alpha comes from a
-- step curve, so nothing compares the secret in Lua.
local countCurves = {}
local function CountCurve(i, scale)
	local key = i * 100 + scale
	if countCurves[key] ~= nil then return countCurves[key] or nil end
	local curve
	if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
		local ok = pcall(function()
			curve = C_CurveUtil.CreateCurve()
			curve:SetType(Enum.LuaCurveType.Step)
			curve:AddPoint(0, 0)
			curve:AddPoint(i * scale, 1)
			curve:AddPoint((i + 1) * scale, 0)
		end)
		if not ok then curve = nil end
	end
	countCurves[key] = curve or false
	return curve
end

local function PaintCounts(count, current, scale)
	local show = DB().pips.showCount ~= false
	if not show then
		for i = 1, MAX_PIPS do
			if RB.pipBars[i].Count then RB.pipBars[i].Count:SetAlpha(0) end
		end
		return
	end
	if not Soul.Secret.IsSecret(current) then
		local full = type(current) == "number" and math.floor(current / scale) or 0
		for i = 1, MAX_PIPS do
			local text = RB.pipBars[i].Count
			if text then text:SetAlpha((i == full and i <= count) and 1 or 0) end
		end
		return
	end
	for i = 1, MAX_PIPS do
		local text = RB.pipBars[i].Count
		if text then
			local curve = i <= count and CountCurve(i, scale)
			local ok = curve and pcall(function() text:SetAlpha(curve:Evaluate(current)) end)
			if not ok then text:SetAlpha(0) end
		end
	end
end

local function UpdatePips()
	local db = DB()
	local spec = ClassSpec()
	if not db.showPips or not spec then
		Reveal(RB.pips, false)
		return
	end
	if spec.mode == "runes" then
		if not GetRuneCooldown then
			Reveal(RB.pips, false)
			return
		end
		Reveal(RB.pips, true)
		LayoutPips(6)
		for i = 1, MAX_PIPS do
			if RB.pipBars[i].Count then RB.pipBars[i].Count:SetAlpha(0) end
		end
		for i = 1, 6 do
			local pip = RB.pipBars[i]
			local start, duration, ready = GetRuneCooldown(i)
			PaintPip(pip)
			local secret = Soul.Secret.IsSecret(start) or Soul.Secret.IsSecret(duration) or Soul.Secret.IsSecret(ready)
			if secret then
				pip:SetMinMaxValues(0, 1)
				pip:SetValue(1)
			elseif ready or type(duration) ~= "number" or duration <= 0 then
				pip:SetMinMaxValues(0, 1)
				pip:SetValue(1)
			else
				local obj = pip._soulDuration
				if not obj and C_DurationUtil and C_DurationUtil.CreateDuration then
					obj = C_DurationUtil.CreateDuration()
					pip._soulDuration = obj
				end
				if obj and obj.SetTimeFromStart and type(start) == "number" then
					obj:SetTimeFromStart(start, duration)
					pip:SetMinMaxValues(0, 1)
					local direction = Enum.StatusBarTimerDirection
					local interp = Enum.StatusBarInterpolation
					if pip.SetTimerDuration and direction and interp then
						pcall(pip.SetTimerDuration, pip, obj, interp.Immediate, direction.ElapsedTime)
					end
				end
			end
		end
		return
	end
	local count = PipCount(spec)
	if count < 1 then
		Reveal(RB.pips, false)
		return
	end
	Reveal(RB.pips, true)
	LayoutPips(count)
	local scale = 1
	if spec.power == Power("SoulShards", 7) then
		scale = 10
	end
	local current = UnitPower("player", spec.power, scale ~= 1)
	for i = 1, count do
		local pip = RB.pipBars[i]
		PaintPip(pip)
		pip:SetMinMaxValues((i - 1) * scale, i * scale)
		pip:SetValue(current)
	end
	PaintCounts(count, current, scale)
end

local function UpdatePrimary()
	local db = DB()
	Reveal(RB.primary, db.showPrimary and true or false)
	if not db.showPrimary then return end
	local bar = RB.primary.Bar
	local kind = UnitPowerType("player")
	bar:SetStatusBarColor(Soul:PowerColor(kind))
	local custom = db.primary.color
	if type(custom) == "table" then
		bar:SetStatusBarColor(custom[1], custom[2], custom[3])
	end
	bar:SetMinMaxValues(0, UnitPowerMax("player"))
	bar:SetValue(UnitPower("player"))
	local curve = CurveConstants and CurveConstants.ScaleTo100
	if curve and not Soul.Secret.IsSecret(kind) and type(kind) == "number" then
		RB.primary.Text:SetFormattedText("%.0f", UnitPowerPercent("player", kind, true, curve))
	else
		RB.primary.Text:SetText("")
	end
end

local function ShowCast(channel, empower)
	local bar = RB.cast.Bar
	local duration
	if empower and UnitEmpoweredChannelDuration then
		duration = UnitEmpoweredChannelDuration("player")
	elseif channel then
		duration = UnitChannelDuration("player")
	else
		duration = UnitCastingDuration("player")
	end
	if not Soul.Secret.Present(duration) then
		Reveal(RB.cast, false)
		return
	end
	local info, notInterruptible
	if channel or empower then
		info = { UnitChannelInfo("player") }
		notInterruptible = info[7]
	else
		info = { UnitCastingInfo("player") }
		notInterruptible = info[8]
	end
	RB.cast.Text:SetText(info[1] or "")
	if Soul.Secret.Present(info[3]) and DB().cast.showIcon ~= false then
		pcall(RB.cast.Icon.SetTexture, RB.cast.Icon, info[3])
		RB.cast.Icon:Show()
	end
	local direction = Enum.StatusBarTimerDirection
	local interp = Enum.StatusBarInterpolation
	if not (bar.SetTimerDuration and direction and interp) then
		Reveal(RB.cast, false)
		return
	end
	local which
	if channel or empower then
		which = direction.RemainingTime
	else
		which = direction.ElapsedTime
	end
	local ok = pcall(bar.SetTimerDuration, bar, duration, interp.Immediate, which)
	if not ok then
		Reveal(RB.cast, false)
		return
	end
	if bar.SetToTargetValue then bar:SetToTargetValue() end
	local r, g, b = Soul:Accent()
	local accent = CreateColor(r, g, b, 1)
	local grey = CreateColor(0.45, 0.45, 0.48, 1)
	local picked = Soul.Secret.PickColor(notInterruptible, accent, grey)
	if picked and picked.GetRGB then
		bar:SetStatusBarColor(picked:GetRGB())
	else
		bar:SetStatusBarColor(r, g, b)
	end
	local custom = DB().cast.color
	if type(custom) == "table" then
		bar:SetStatusBarColor(custom[1], custom[2], custom[3])
	end
	Soul.Secret.AlphaFromBool(RB.cast.Shield, notInterruptible, 1, 0)
	Reveal(RB.cast, true)
end

local function RefreshCast()
	if not DB().showCast then
		Reveal(RB.cast, false)
		return
	end
	local casting = UnitCastingInfo("player")
	if Soul.Secret.Present(casting) then
		ShowCast(false, false)
		return
	end
	local channel = UnitChannelInfo("player")
	if Soul.Secret.Present(channel) then
		ShowCast(true, false)
	else
		Reveal(RB.cast, false)
	end
end

local function UpdateGCD()
	local db = DB()
	Reveal(RB.gcd, db.showGCD and true or false)
	if not db.showGCD then return end
	if not C_Spell or not C_Spell.GetSpellCooldownDuration then return end
	local duration = C_Spell.GetSpellCooldownDuration(GCD_SPELL)
	local bar = RB.gcd.Bar
	local direction = Enum.StatusBarTimerDirection
	local interp = Enum.StatusBarInterpolation
	if not Soul.Secret.Present(duration) or not (bar.SetTimerDuration and direction and interp) then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		return
	end
	pcall(bar.SetTimerDuration, bar, duration, interp.Immediate, direction.RemainingTime)
	if bar.SetToTargetValue then bar:SetToTargetValue() end
end

local CAST_END = {
	UNIT_SPELLCAST_STOP = true,
	UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_FAILED_QUIET = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_EMPOWER_STOP = true,
}

local function OnEvent(_, event)
	if event == "RUNE_POWER_UPDATE" or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_SPECIALIZATION_CHANGED" then
		UpdatePips()
		UpdatePrimary()
		return
	end
	if event == "SPELL_UPDATE_COOLDOWN" then
		UpdateGCD()
		return
	end
	if CAST_END[event] then
		Reveal(RB.cast, false)
		UpdateGCD()
		return
	end
	if event == "UNIT_SPELLCAST_START" then
		ShowCast(false, false)
		UpdateGCD()
		return
	end
	if event == "UNIT_SPELLCAST_CHANNEL_START" then
		ShowCast(true, false)
		UpdateGCD()
		return
	end
	if event == "UNIT_SPELLCAST_EMPOWER_START" then
		ShowCast(true, true)
		UpdateGCD()
		return
	end
	if event and event:find("SPELLCAST", 1, true) then
		RefreshCast()
		return
	end
	UpdatePrimary()
	UpdatePips()
end

function RB:Apply()
	RB._pipSig = nil
	local db = DB()
	local width = db.width or 380
	local function place(frame, key, cfg, show)
		frame:SetWidth(cfg.width or width)
		frame:SetHeight(cfg.height)
		Soul:Place(frame, "ResourceBars:" .. key, {
			point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y,
		})
		if key ~= "cast" and key ~= "pips" then
			Reveal(frame, show and true or false)
		end
	end
	place(self.primary, "primary", db.primary, db.showPrimary)
	place(self.pips, "pips", db.pips, db.showPips)
	place(self.cast, "cast", db.cast, false)
	place(self.gcd, "gcd", db.gcd, db.showGCD)
	Soul:ShowBorder(self.primary, false)
	Soul:ShowBorder(self.cast, false)
	Soul:ShowBorder(self.gcd, false)
	local r, g, b = Soul:Accent()
	local gcdColor = db.gcd.color
	if type(gcdColor) == "table" then
		r, g, b = gcdColor[1], gcdColor[2], gcdColor[3]
	end
	self.gcd.Bar:SetStatusBarColor(r, g, b)
	self.cast.Bar:SetStatusBarTexture(Soul:StatusbarTexture())
	self.primary.Bar:SetStatusBarTexture(Soul:StatusbarTexture())
	self.gcd.Bar:SetStatusBarTexture(Soul:StatusbarTexture())
	for i = 1, MAX_PIPS do
		self.pipBars[i]:SetStatusBarTexture(Soul:StatusbarTexture())
	end
	local primarySize = db.primary.textSize or 0
	if primarySize <= 0 then primarySize = math.max(10, math.floor((db.primary.height or 12) * 0.9)) end
	Soul:ApplyFont(self.primary.Text, primarySize, "OUTLINE")
	self.primary.Text:SetShown(db.primary.showText ~= false)
	local castSize = db.cast.textSize or 0
	if castSize <= 0 then castSize = math.max(10, math.floor((db.cast.height or 16) * 0.6)) end
	Soul:ApplyFont(self.cast.Text, castSize, "OUTLINE")
	local castH = db.cast.height or 16
	self.cast.Icon:SetSize(castH, castH)
	self.cast.Icon:SetShown(db.cast.showIcon ~= false)
	self.cast.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	UpdatePrimary()
	UpdatePips()
	RefreshCast()
	UpdateGCD()
	if Soul.Blizz then Soul.Blizz.Refresh() end
end

function RB:OnInitialize()
	Soul:RegisterModuleDB("ResourceBars", Soul.Defaults.ResourceBars)
end

function RB:OnEnable()
	local db = DB()
	self.primary = MakeBar("SoulUIResourcePrimary", db.primary.height)
	local text = self.primary.Bar:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(text, 11, "OUTLINE")
	text:SetPoint("RIGHT", -4, 0)
	text:SetTextColor(1, 1, 1)
	self.primary.Text = text

	self.pips = CreateFrame("Frame", "SoulUIResourcePips", UIParent)
	self.pips:SetHeight(db.pips.height)
	self.pips:EnableMouse(false)
	self.pipBars = {}
	-- Each pip is a tile (border + empty color) holding an inset status bar.
	-- The bar's own background is the empty color, so an unfilled tile reads
	-- as flat gray and a filled one as solid class color.
	for i = 1, MAX_PIPS do
		local tile = CreateFrame("Frame", nil, self.pips)
		tile:EnableMouse(false)
		Soul:Round(tile)
		local pip = Soul:StatusBar(tile)
		pip:EnableMouse(false)
		pip.tile = tile
		local gloss = pip:CreateTexture(nil, "OVERLAY", nil, 1)
		gloss:SetPoint("TOPLEFT")
		gloss:SetPoint("TOPRIGHT")
		gloss:SetColorTexture(1, 1, 1, 0.12)
		gloss:Hide()
		pip.gloss = gloss
		local count = pip:CreateFontString(nil, "OVERLAY", nil, 7)
		count:SetPoint("CENTER", pip, "CENTER", 0, 0)
		count:SetTextColor(1, 1, 1)
		count:SetAlpha(0)
		pip.Count = count
		self.pipBars[i] = pip
	end

	self.cast = MakeBar("SoulUIResourceCast", db.cast.height)
	local icon = self.cast:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPRIGHT", self.cast, "TOPLEFT", -2, 0)
	icon:SetSize(db.cast.height, db.cast.height)
	self.cast.Icon = icon
	local castText = self.cast.Bar:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(castText, 11, "OUTLINE")
	castText:SetPoint("LEFT", 4, 0)
	castText:SetPoint("RIGHT", -4, 0)
	castText:SetJustifyH("LEFT")
	castText:SetTextColor(1, 1, 1)
	self.cast.Text = castText
	local shield = self.cast:CreateTexture(nil, "OVERLAY", nil, 7)
	shield:SetAllPoints()
	shield:SetColorTexture(0.7, 0.7, 0.75, 0.35)
	shield:SetAlpha(0)
	self.cast.Shield = shield

	self.gcd = MakeBar("SoulUIResourceGCD", db.gcd.height)

	local units = {
		"UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
		"UNIT_POWER_POINT_CHARGE",
		"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
		"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
		"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
		"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
		"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
	}
	for i = 1, #units do
		pcall(self.RegisterUnitEvent, self, units[i], OnEvent, "player")
	end
	self:RegisterEvent("RUNE_POWER_UPDATE", OnEvent)
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", OnEvent)
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", OnEvent)
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnEvent)

	local movers = {
		{ key = "primary", label = "Primary Power", frame = self.primary, flag = "showPrimary" },
		{ key = "pips", label = "Class Pips", frame = self.pips, flag = "showPips" },
		{ key = "cast", label = "Player Cast", frame = self.cast, flag = "showCast" },
		{ key = "gcd", label = "GCD", frame = self.gcd, flag = "showGCD" },
	}
	for i = 1, #movers do
		local info = movers[i]
		Soul:RegisterMover({
			key = "ResourceBars:" .. info.key,
			label = info.label,
			getFrame = function() return info.frame end,
			getEnabled = function() return DB()[info.flag] end,
			setEnabled = function(on)
				DB()[info.flag] = on and true or false
				RB:Apply()
			end,
			fallback = function()
				local cfg = DB()[info.key]
				return { point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y }
			end,
			onResize = function(width, height)
				local cfg = DB()[info.key]
				cfg.width = math.floor(width + 0.5)
				cfg.height = math.floor(height + 0.5)
				RB:Apply()
			end,
			getColor = function()
				local cfg = DB()[info.key]
				if type(cfg.color) == "table" then return cfg.color[1], cfg.color[2], cfg.color[3] end
				if info.key == "pips" then return PipFill() end
				if info.key == "gcd" then return Soul:Accent() end
				return 0.2, 0.6, 1
			end,
			setColor = function(r, g, b)
				DB()[info.key].color = { r, g, b }
				if info.key == "pips" then DB().pips.colorMode = "custom" end
				RB:Apply()
			end,
			page = "resources",
		})
	end

	Soul:On("ProfileChanged", function() RB:Apply() end)
	Soul:On("ThemeChanged", function() RB:Apply() end)
	self:Apply()
end
