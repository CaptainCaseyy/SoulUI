if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI
local UF = Soul:NewModule("UnitFrames", "SoulUI_UnitFrames")

local UNITS = { "player", "target", "focus", "targettarget", "pet" }
local LABELS = {
	player = "Player",
	target = "Target",
	focus = "Focus",
	targettarget = "Target of Target",
	pet = "Pet",
}

local BLIZZARD = { "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame" }
local blizzHooked = {}
local blizzGuard = {}

local function DB()
	return Soul:ModuleDB("UnitFrames")
end

local IsSecret = Soul.Secret.IsSecret
local AlphaFromBool = Soul.Secret.AlphaFromBool
local UnitExists, UnitHealth, UnitHealthMax, UnitHealthPercent = UnitExists, UnitHealth, UnitHealthMax, UnitHealthPercent
local UnitIsDeadOrGhost, UnitIsConnected, UnitIsPlayer, UnitClass = UnitIsDeadOrGhost, UnitIsConnected, UnitIsPlayer, UnitClass
local UnitPower, UnitPowerMax, UnitPowerType, UnitName = UnitPower, UnitPowerMax, UnitPowerType, UnitName
local UnitGetTotalAbsorbs, UnitGetTotalHealAbsorbs = UnitGetTotalAbsorbs, UnitGetTotalHealAbsorbs

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TEXT_R, TEXT_G, TEXT_B = 0.96, 0.96, 0.96
local GRAY_R, GRAY_G, GRAY_B = 0.42, 0.42, 0.44
local DEAD_TEXT = DEAD or "Dead"
local OFFLINE_TEXT = PLAYER_OFFLINE or "Offline"
local PAD_X = 6

-- Health-related events only touch health; power events only power; and so
-- on. Cast events go to the shared cast bar. Nothing recomputes everything
-- except a real refresh ("SHOW").
local HEALTH_EVENTS = {
	UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_ABSORB_AMOUNT_CHANGED = true,
	UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true, UNIT_FACTION = true, UNIT_CONNECTION = true,
}
local POWER_EVENTS = {
	UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true,
}

local function Pixel()
	local px = Soul.Pixel:Scale(1)
	if type(px) ~= "number" or px < 0.4 then px = 1 end
	return px
end

local function RGBA(color, r, g, b, a)
	if type(color) == "table" then
		return color[1] or r, color[2] or g, color[3] or b, color[4] or a
	end
	return r, g, b, a
end

-- Class color for a player unit, nil for NPCs. Secret class files go through
-- C_ClassColor, which accepts them; nothing here compares a secret.
local function ClassRGB(unit)
	local isPlayer = UnitIsPlayer(unit)
	if IsSecret(isPlayer) or not isPlayer then return nil end
	local _, class = UnitClass(unit)
	if IsSecret(class) then
		local color = C_ClassColor and C_ClassColor.GetClassColor(class)
		if color then return color:GetRGB() end
		return nil
	end
	local color = type(class) == "string" and RAID_CLASS_COLORS[class]
	if color then return color.r, color.g, color.b end
	return nil
end

local function ColorHealth(bar, key, unit)
	if not unit then return end
	-- Tapped mobs are gray even with a custom color, so "not your loot" reads
	-- the same on every frame.
	if UnitIsTapDenied then
		local tapped = UnitIsTapDenied(unit)
		if not IsSecret(tapped) and tapped then
			bar:SetStatusBarColor(0.45, 0.45, 0.45)
			return
		end
	end
	local cfg = DB().units[key]
	local color = cfg and cfg.color
	if type(color) == "table" then
		bar:SetStatusBarColor(color[1], color[2], color[3])
		return
	end
	Soul:ColorUnitHealth(bar, unit)
end

local function UpdateName(frame)
	local unit = frame._soulUnit
	if not unit or not UnitExists(unit) then
		frame.Name:SetText("")
		return
	end
	-- Long names truncate with "..." because the font string is anchored on
	-- both sides with word wrap off; no string work on a possibly secret name.
	frame.Name:SetText(UnitName(unit) or "")
	if frame._soulGray then
		frame.Name:SetTextColor(GRAY_R + 0.2, GRAY_G + 0.2, GRAY_B + 0.2)
		return
	end
	local cfg = DB().units[frame._soulKey]
	if cfg and cfg.nameClassColor then
		local r, g, b = ClassRGB(unit)
		if r then
			frame.Name:SetTextColor(r, g, b)
			return
		end
	end
	frame.Name:SetTextColor(TEXT_R, TEXT_G, TEXT_B)
end

local function UpdateAbsorbs(frame, unit)
	local bar = frame.Health
	local db = DB()
	local width = bar:GetWidth()
	if db.absorbs ~= false and UnitGetTotalAbsorbs then
		local maxHealth = UnitHealthMax(unit)
		local amount = UnitGetTotalAbsorbs(unit)
		local absorb, over = bar._absorb, bar._overAbsorb
		absorb:SetWidth(width)
		absorb:SetMinMaxValues(0, maxHealth)
		absorb:SetValue(amount)
		over:SetWidth(width)
		over:SetMinMaxValues(0, maxHealth)
		over:SetValue(amount)
	end
	if db.healAbsorbs ~= false and UnitGetTotalHealAbsorbs then
		local heal = bar._healAbsorb
		heal:SetWidth(width)
		heal:SetMinMaxValues(0, UnitHealthMax(unit))
		heal:SetValue(UnitGetTotalHealAbsorbs(unit))
	end
end

local function UpdateHealth(frame)
	local unit = frame._soulUnit
	local bar = frame.Health
	if not unit or not UnitExists(unit) then return end
	local cfg = DB().units[frame._soulKey] or {}
	local format = cfg.healthFormat or "both"
	-- Dead and connected are plain booleans (midnight-api.md 1.6); still
	-- guarded so a future change to secret cannot throw here.
	local dead = UnitIsDeadOrGhost(unit)
	local connected = UnitIsConnected(unit)
	local gray
	if not IsSecret(dead) and dead then
		gray = "dead"
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		bar:SetStatusBarColor(GRAY_R, GRAY_G, GRAY_B)
	elseif not IsSecret(connected) and not connected then
		gray = "offline"
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar:SetStatusBarColor(GRAY_R, GRAY_G, GRAY_B)
	else
		bar:SetMinMaxValues(0, UnitHealthMax(unit))
		bar:SetValue(UnitHealth(unit))
		ColorHealth(bar, frame._soulKey, unit)
	end
	if gray then
		bar._absorb:SetValue(0)
		bar._overAbsorb:SetValue(0)
		bar._healAbsorb:SetValue(0)
	else
		UpdateAbsorbs(frame, unit)
	end
	local wasGray = frame._soulGray
	frame._soulGray = gray and true or false
	if wasGray ~= frame._soulGray then UpdateName(frame) end

	local text = frame.HealthText
	local curve = CurveConstants and CurveConstants.ScaleTo100
	if format == "none" then
		text:SetText("")
	elseif gray then
		text:SetTextColor(GRAY_R + 0.2, GRAY_G + 0.2, GRAY_B + 0.2)
		text:SetText(gray == "dead" and DEAD_TEXT or OFFLINE_TEXT)
		return
	elseif format == "value" or not curve then
		text:SetFormattedText("%s", Soul:Abbrev(UnitHealth(unit)))
	elseif format == "percent" then
		text:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve))
	else
		text:SetFormattedText("%s | %.0f%%", Soul:Abbrev(UnitHealth(unit)), UnitHealthPercent(unit, true, curve))
	end
	text:SetTextColor(TEXT_R, TEXT_G, TEXT_B)
end

local function UpdatePower(frame)
	local unit = frame._soulUnit
	local bar = frame.Power
	if not unit or not bar:IsShown() or not UnitExists(unit) then return end
	bar:SetMinMaxValues(0, UnitPowerMax(unit))
	bar:SetValue(UnitPower(unit))
	bar:SetStatusBarColor(Soul:PowerColor(UnitPowerType(unit)))
end

-- Raid marker, leader crown, combat swords, and the "this is your target"
-- outline. Textures and alpha only, so all of it is safe in combat.
local function UpdateRaidIcon(frame)
	local icon = frame.RaidIcon
	local unit = frame._soulUnit
	if DB().raidIcon == false or not unit or not GetRaidTargetIndex then
		icon:Hide()
		return
	end
	local index = GetRaidTargetIndex(unit)
	if not IsSecret(index) and type(index) == "number" and index > 0 and index <= 8 then
		SetRaidTargetIconTexture(icon, index)
		icon:Show()
	else
		icon:Hide()
	end
end

local function UpdateLeader(frame)
	local icon = frame.LeaderIcon
	if not icon then return end
	local unit = frame._soulUnit
	if DB().leaderIcon == false or not unit or not UnitIsGroupLeader or not UnitExists(unit) then
		icon:SetAlpha(0)
		return
	end
	AlphaFromBool(icon, UnitIsGroupLeader(unit), 1, 0)
end

local function UpdateCombat(frame)
	local icon = frame.CombatIcon
	if not icon then return end
	if DB().combatIcon == false then
		icon:SetAlpha(0)
		return
	end
	AlphaFromBool(icon, UnitAffectingCombat("player"), 1, 0)
end

local function UpdateTargetMark(frame)
	local mark = frame.TargetMark
	if not mark then return end
	local unit = frame._soulUnit
	if DB().targetHighlight == false or not unit or not UnitExists("target") or not UnitExists(unit) then
		mark:SetAlpha(0)
		return
	end
	AlphaFromBool(mark, UnitIsUnit(unit, "target"), 1, 0)
end

local function UpdateIndicators(frame)
	UpdateRaidIcon(frame)
	UpdateLeader(frame)
	UpdateCombat(frame)
	UpdateTargetMark(frame)
end

-- Cast bars come from Core/CastBar.lua. Enemy units (target, focus, target of
-- target) color through Soul.Cast; player and pet use castColor or the accent.
local ENEMY_CAST = { target = true, focus = true, targettarget = true }

-- Purge outline only makes sense on something you can attack.
local function UpdatePurgeGlow(frame)
	if not frame.PurgeGlow then return end
	local unit = frame._soulUnit
	local db = DB()
	local magic, enrage = Soul.Auras.OffensiveDispel()
	local can = unit and UnitExists(unit) and UnitCanAttack("player", unit)
	local show = db.purgeGlow ~= false and (magic or enrage) and not IsSecret(can) and can and true or false
	Soul.Auras.SetShown(frame.PurgeGlow, show)
end

local function UpdateFrame(frame, event)
	if event == "SHOW" then
		UpdateHealth(frame)
		UpdatePower(frame)
		UpdateName(frame)
		UpdateIndicators(frame)
		UpdatePurgeGlow(frame)
		frame.Cast:SetUnit(frame._soulUnit)
		frame.Cast:Reset()
	elseif HEALTH_EVENTS[event] then
		UpdateHealth(frame)
	elseif POWER_EVENTS[event] then
		UpdatePower(frame)
	elseif event == "UNIT_NAME_UPDATE" then
		UpdateName(frame)
	elseif Soul.CastBar.IsCastEvent(event) then
		frame.Cast:HandleEvent(event)
	else
		UpdateHealth(frame)
		UpdatePower(frame)
		UpdateName(frame)
	end
end

-- Colors, textures and fonts that do not move anything: safe any time.
local function Skin(frame)
	local db = DB()
	local tex = Soul:StatusbarTexture()
	frame.Health:SetStatusBarTexture(tex)
	frame.Power:SetStatusBarTexture(tex)
	frame.Health._absorb:SetStatusBarTexture(WHITE)
	frame.Health._overAbsorb:SetStatusBarTexture(WHITE)
	frame.Health._healAbsorb:SetStatusBarTexture(WHITE)

	local br, bg, bb, ba = RGBA(db.borderColor, 0, 0, 0, 1)
	frame.Backdrop:SetColorTexture(br, bg, bb, ba)
	local r, g, b, a = RGBA(db.backdropColor, 0.06, 0.06, 0.07, 1)
	frame.Health.bg:SetColorTexture(r, g, b, a)
	frame.Power.bg:SetColorTexture(r * 0.75, g * 0.75, b * 0.75, a)

	frame.Gloss:SetAlpha(db.gloss == false and 0 or 1)
	frame.Health._absorbClip:SetAlpha(db.absorbs == false and 0 or 1)
	frame.Health._overClip:SetAlpha(1)
	frame.Health._overAbsorb:SetAlpha(db.absorbs == false and 0 or 1)
	frame.Health._healAbsorb:SetAlpha(db.healAbsorbs == false and 0 or 1)

	local shadow = db.textShadow ~= false
	for _, fs in ipairs(frame._soulTexts) do
		if shadow then
			fs:SetShadowColor(0, 0, 0, 0.85)
			fs:SetShadowOffset(1, -1)
		else
			fs:SetShadowOffset(0, 0)
		end
	end
end

local function AttachMenu(frame, unit)
	local proxyName = "SoulUI_Menu_" .. unit
	local proxy = CreateFrame("Button", proxyName, frame, "SecureActionButtonTemplate")
	proxy:SetSize(1, 1)
	proxy:SetPoint("TOPLEFT")
	proxy:SetAlpha(0)
	proxy:EnableMouse(false)
	proxy:SetAttribute("useparent-unit", true)
	proxy:SetAttribute("type", "togglemenu")
	proxy:SetAttribute("useOnKeyDown", false)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "macro")
	frame:SetAttribute("*macrotext2", "/click " .. proxyName)
	frame:RegisterForClicks("AnyUp")
end

local function Outline(parent, layer)
	local edges = {}
	for i = 1, 4 do
		local t = parent:CreateTexture(nil, layer or "OVERLAY", nil, 7)
		t:SetColorTexture(1, 1, 1, 1)
		edges[i] = t
	end
	return edges
end

local function SizeOutline(edges, frame, px)
	local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", frame, "TOPLEFT")
	top:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
	top:SetHeight(px)
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
	bottom:SetHeight(px)
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
	left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
	left:SetWidth(px)
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
	right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
	right:SetWidth(px)
end

local function OnEnter(self)
	self._soulHover = true
	if DB().hoverHighlight ~= false then self.Hover:SetAlpha(1) end
	if DB().tooltip ~= false and self._soulUnit then
		Soul:ShowUnitTooltip(self, self._soulUnit)
	end
end

local function OnLeave(self)
	self._soulHover = nil
	self.Hover:SetAlpha(0)
	Soul:HideUnitTooltip(self)
end

local function CreateUnitFrame(unit, parent)
	local created, frame = pcall(CreateFrame, "Button", "SoulUI_UF_" .. unit, parent, "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
	if not created then
		frame = CreateFrame("Button", "SoulUI_UF_" .. unit, parent, "SecureUnitButtonTemplate")
	end
	frame._soulUnit = unit
	frame._soulKey = unit -- config key; _soulUnit can follow the unit attribute
	frame:SetAttribute("unit", unit)
	if unit == "player" then
		frame:SetAttribute("toggleForVehicle", true)
	end
	AttachMenu(frame, unit)
	frame:SetClampedToScreen(true)
	Soul:Round(frame)
	if not ClickCastFrames then
		rawset(_G, "ClickCastFrames", {})
	end
	ClickCastFrames[frame] = true

	-- One solid layer behind everything: it shows as the 1px outline around
	-- the bars and as the 1px line between health and power.
	local backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	backdrop:SetAllPoints()
	backdrop:SetColorTexture(0, 0, 0, 1)
	frame.Backdrop = backdrop

	local health = Soul:StatusBar(frame)
	frame.Health = health
	-- Dispel outlines (Core/Auras.lua): a debuff you can cleanse on a friend,
	-- or a buff you can purge / soothe on an enemy target or focus.
	frame.DispelGlow = Soul.Auras.Highlight(health, unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", { 0.8, 0.35, 1 }, 2)
	if unit == "target" or unit == "focus" then
		frame.PurgeGlow = Soul.Auras.Highlight(health, unit, "HELPFUL|DISPELLABLE", { 0.25, 0.65, 1 }, 2)
	end
	local fill = health:GetStatusBarTexture()

	-- Soft shading on the fill only, so the empty part stays a clean flat dark.
	local gloss = health:CreateTexture(nil, "ARTWORK", nil, 7)
	gloss:SetPoint("TOPLEFT", fill, "TOPLEFT")
	gloss:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	gloss:SetTexture(WHITE)
	if gloss.SetGradient and CreateColor then
		pcall(gloss.SetGradient, gloss, "VERTICAL", CreateColor(0, 0, 0, 0.30), CreateColor(1, 1, 1, 0.08))
	else
		gloss:SetVertexColor(0, 0, 0, 0)
	end
	frame.Gloss = gloss

	-- Absorbs. Shields continue past the fill into the missing health (clipped
	-- at the bar's end); the part that does not fit shows as a light wash laid
	-- back from the right end over the fill. Heal absorbs eat leftward from the
	-- fill's edge in dark red. All values go straight into StatusBars.
	local clip = CreateFrame("Frame", nil, health)
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	clip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
	health._absorbClip = clip
	local absorb = CreateFrame("StatusBar", nil, clip)
	absorb:SetStatusBarTexture(WHITE)
	absorb:SetStatusBarColor(0.6, 0.85, 1, 0.5)
	absorb:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	absorb:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
	absorb:SetWidth(340)
	absorb:SetMinMaxValues(0, 1)
	absorb:SetValue(0)
	health._absorb = absorb

	local overClip = CreateFrame("Frame", nil, health)
	if overClip.SetClipsChildren then overClip:SetClipsChildren(true) end
	overClip:SetPoint("TOPLEFT", health, "TOPLEFT")
	overClip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	health._overClip = overClip
	local over = CreateFrame("StatusBar", nil, overClip)
	over:SetStatusBarTexture(WHITE)
	over:SetStatusBarColor(0.75, 0.9, 1, 0.22)
	over:SetReverseFill(true)
	over:SetPoint("TOPRIGHT", health, "TOPRIGHT")
	over:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
	over:SetWidth(340)
	over:SetMinMaxValues(0, 1)
	over:SetValue(0)
	health._overAbsorb = over
	local healAbsorb = CreateFrame("StatusBar", nil, overClip)
	healAbsorb:SetStatusBarTexture(WHITE)
	healAbsorb:SetStatusBarColor(0.45, 0.04, 0.08, 0.75)
	healAbsorb:SetReverseFill(true)
	healAbsorb:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
	healAbsorb:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	healAbsorb:SetWidth(340)
	healAbsorb:SetMinMaxValues(0, 1)
	healAbsorb:SetValue(0)
	health._healAbsorb = healAbsorb

	-- Text and hover sit on their own layer above the absorb bars, so a big
	-- shield never washes over the name or the numbers.
	local textLayer = CreateFrame("Frame", nil, health)
	textLayer:SetAllPoints(health)
	textLayer:SetFrameLevel(health:GetFrameLevel() + 6)
	frame.TextLayer = textLayer

	local hover = textLayer:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints(health)
	hover:SetColorTexture(1, 1, 1, 0.08)
	hover:SetBlendMode("ADD")
	hover:SetAlpha(0)
	frame.Hover = hover

	local name = textLayer:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT")
	name:SetJustifyV("MIDDLE")
	name:SetWordWrap(false)
	if name.SetMaxLines then name:SetMaxLines(1) end
	frame.Name = name

	local percent = textLayer:CreateFontString(nil, "OVERLAY")
	percent:SetJustifyH("RIGHT")
	percent:SetJustifyV("MIDDLE")
	percent:SetWordWrap(false)
	frame.HealthText = percent
	frame._soulTexts = { name, percent }

	local power = Soul:StatusBar(frame)
	frame.Power = power

	-- Indicators above everything (including the dispel outline).
	local marks = CreateFrame("Frame", nil, frame)
	marks:SetAllPoints(frame)
	marks:SetFrameLevel(health:GetFrameLevel() + 10)
	frame.Indicators = marks

	if unit ~= "target" then
		local targetMark = CreateFrame("Frame", nil, marks)
		targetMark:SetAllPoints(frame)
		targetMark:SetAlpha(0)
		targetMark._edges = Outline(targetMark)
		for i = 1, 4 do targetMark._edges[i]:SetVertexColor(1, 1, 1, 0.9) end
		frame.TargetMark = targetMark
	end

	local raid = marks:CreateTexture(nil, "OVERLAY")
	raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	raid:Hide()
	frame.RaidIcon = raid

	if unit == "player" or unit == "target" or unit == "focus" then
		local leader = marks:CreateTexture(nil, "OVERLAY")
		leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
		leader:SetAlpha(0)
		frame.LeaderIcon = leader
	end
	if unit == "player" then
		local combat = marks:CreateTexture(nil, "OVERLAY")
		combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
		combat:SetTexCoord(0.5, 1, 0, 0.49)
		combat:SetAlpha(0)
		frame.CombatIcon = combat
	end

	local cast = Soul.CastBar.New(UIParent, { enemy = ENEMY_CAST[unit], poll = unit == "targettarget" })
	cast:SetFrameStrata(frame:GetFrameStrata())
	cast:SetUnit(unit)
	cast.allowed = function()
		local cfg = DB().units[unit]
		return cfg and cfg.enabled and cfg.showCast and frame:IsShown() and true or false
	end
	cast.getColor = function()
		local cfg = DB().units[unit]
		local c = cfg and cfg.castColor
		if type(c) == "table" then return c[1], c[2], c[3] end
	end
	frame.Cast = cast

	Soul:Border(frame)
	frame:HookScript("OnEnter", OnEnter)
	frame:HookScript("OnLeave", OnLeave)
	frame:HookScript("OnShow", function(self) UpdateFrame(self, "SHOW") end)
	frame:HookScript("OnHide", function(self)
		if self._soulHover then OnLeave(self) end
		if self._soulPreviewCast then return end
		self.Cast:Stop()
	end)
	frame:HookScript("OnAttributeChanged", function(self, attr, value)
		if attr == "unit" and type(value) == "string" then
			self._soulUnit = value
			if self:IsShown() then UpdateFrame(self, "SHOW") end
		end
	end)
	frame.Update = UpdateFrame
	frame:Hide()
	return frame
end

local function SuppressBlizzard()
	local hide = DB().hideBlizzard
	for i = 1, #BLIZZARD do
		local name = BLIZZARD[i]
		local frame = _G[name]
		if frame and not blizzHooked[name] then
			blizzHooked[name] = true
			hooksecurefunc(frame, "Show", function(self)
				if blizzGuard[self] or not DB().hideBlizzard then return end
				if InCombatLockdown() then
					self:SetAlpha(0)
					Soul:RunAfterCombat("rehide-" .. name, function()
						if not DB().hideBlizzard then
							self:SetAlpha(1)
							return
						end
						self:SetAlpha(1)
						blizzGuard[self] = true
						self:Hide()
						blizzGuard[self] = nil
					end)
				else
					blizzGuard[self] = true
					self:Hide()
					blizzGuard[self] = nil
				end
			end)
		end
		if frame then
			Soul:RunAfterCombat("hide-" .. name, function()
				if not frame.UnregisterAllEvents then return end
				if DB().hideBlizzard then
					frame:UnregisterAllEvents()
					frame:Hide()
					frame:SetAlpha(1)
				else
					frame:SetAlpha(1)
				end
			end)
		end
	end
	if not hide then return end
end

local function Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- Places the name, health text and indicators. Regions only, no frame moves.
local function LayoutText(frame, live, px)
	local auto = Clamp(math.floor(live.height * 0.26 + 0.5), 10, 18)
	local nameSize = (live.nameSize or 0) > 0 and live.nameSize or auto
	local healthSize = (live.healthSize or 0) > 0 and live.healthSize or math.max(9, auto - 1)
	Soul:ApplyFont(frame.Name, nameSize, "OUTLINE")
	Soul:ApplyFont(frame.HealthText, healthSize, "OUTLINE")

	local name, text, health = frame.Name, frame.HealthText, frame.Health
	name:ClearAllPoints()
	text:ClearAllPoints()
	local layout = live.textLayout or "corners"
	-- Two corner lines need room for both; a short bar falls back to one line.
	local innerH = health:GetHeight()
	if type(innerH) ~= "number" or innerH <= 0 then innerH = live.height end
	if layout == "corners" and live.namePosition ~= "above" and innerH < nameSize + healthSize + 6 then
		layout = "center"
	end
	local padY = Clamp(math.floor(innerH * 0.08 + 0.5), 2, 5)
	if live.namePosition == "above" then
		name:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", px, 3)
		name:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -px, 3)
	elseif layout == "center" then
		name:SetPoint("LEFT", health, "LEFT", PAD_X, 0)
	else
		name:SetPoint("TOPLEFT", health, "TOPLEFT", PAD_X, -padY)
	end
	if layout == "center" then
		text:SetPoint("RIGHT", health, "RIGHT", -PAD_X, 0)
		if live.namePosition ~= "above" then
			name:SetPoint("RIGHT", text, "LEFT", -6, 0)
		end
	else
		text:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -PAD_X, padY)
		text:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", PAD_X, padY)
		if live.namePosition ~= "above" then
			name:SetPoint("TOPRIGHT", health, "TOPRIGHT", -PAD_X, -padY)
		end
	end
	name:SetShown(live.showName ~= false)

	-- Indicators straddle the top edge so they never cover text.
	local iconSize = Clamp(math.floor(live.height * 0.34 + 0.5), 12, 22)
	frame.RaidIcon:ClearAllPoints()
	frame.RaidIcon:SetSize(iconSize, iconSize)
	frame.RaidIcon:SetPoint("CENTER", frame, "TOP", 0, 0)
	if frame.LeaderIcon then
		local s = Clamp(math.floor(iconSize * 0.8 + 0.5), 10, 16)
		frame.LeaderIcon:ClearAllPoints()
		frame.LeaderIcon:SetSize(s, s)
		frame.LeaderIcon:SetPoint("CENTER", frame, "TOPLEFT", PAD_X + s / 2, 0)
	end
	if frame.CombatIcon then
		local s = Clamp(math.floor(iconSize * 0.9 + 0.5), 12, 20)
		frame.CombatIcon:ClearAllPoints()
		frame.CombatIcon:SetSize(s, s)
		frame.CombatIcon:SetPoint("CENTER", frame, "TOPRIGHT", -(PAD_X + s / 2), 0)
	end
	if frame.TargetMark then SizeOutline(frame.TargetMark._edges, frame.TargetMark, px) end
end

function UF:Layout(unit)
	local frame = self.frames[unit]
	if not frame then return end
	local cfg = DB().units[unit]
	frame._cfg = cfg
	Soul:RunAfterCombat("uf-layout-" .. unit, function()
		local live = DB().units[unit]
		frame._cfg = live
		if not live.enabled then
			UnregisterUnitWatch(frame)
			frame:Hide()
			frame.Cast:Stop()
			return
		end
		-- Frame = 1px outline + health + (1px line + power) + 1px outline.
		-- The outer size stays width x (height + powerHeight) as before, so
		-- saved sizes and the mover's resize math keep meaning the same.
		local px = Pixel()
		local showPower = live.showPower and true or false
		local height = live.height
		if showPower then
			height = height + live.powerHeight
		end
		frame:SetSize(live.width, height)
		local health, power = frame.Health, frame.Power
		health:ClearAllPoints()
		health:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
		health:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -px, -px)
		health:SetHeight(math.max(px, live.height - (showPower and px or 2 * px)))
		Soul.Auras.Refit(frame.DispelGlow, health)
		Soul.Auras.Refit(frame.PurgeGlow, health)
		Soul.Auras.SetShown(frame.DispelGlow, DB().dispelGlow ~= false)
		UpdatePurgeGlow(frame)
		power:SetShown(showPower)
		if showPower then
			power:ClearAllPoints()
			power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -px)
			power:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -px)
			power:SetHeight(math.max(px, live.powerHeight - 2 * px))
		end
		local level = health:GetFrameLevel()
		frame.TextLayer:SetFrameLevel(level + 6)
		frame.Indicators:SetFrameLevel(level + 10)
		LayoutText(frame, live, px)
		Soul:ShowBorder(frame, false)
		Skin(frame)
		local castH = live.castHeight or 16
		local castW = live.castWidth or live.width
		frame.Cast:SetWidth(castW)
		frame.Cast:Layout(castH, live.castIcon ~= false, live.castFont or 0)
		Soul:Place(frame, "UnitFrames:" .. unit, { point = "CENTER", relPoint = "CENTER", x = live.x, y = live.y })
		Soul:Place(frame.Cast, "UnitFrames:" .. unit .. ":cast", {
			point = "BOTTOM", relPoint = "TOP", x = 0, y = 4,
			relative = "UnitFrames:" .. unit,
		})
		RegisterUnitWatch(frame)
		if frame._soulPreviewCast and live.showCast then
			frame.Cast:SetPreview(true)
			return
		end
		if frame.Cast._preview then frame.Cast:SetPreview(false) end
		if frame:IsShown() then
			UpdateFrame(frame, "SHOW")
		else
			frame.Cast:Stop()
		end
	end)
end

function UF:Apply(scope)
	if scope == "colors" then
		for i = 1, #UNITS do
			local frame = self.frames[UNITS[i]]
			if frame then
				Skin(frame)
				if frame:IsShown() then
					frame.Cast.Bar:SetStatusBarTexture(Soul:StatusbarTexture())
					frame.Cast.Spark:SetBlendMode("ADD")
					UpdateFrame(frame, "SHOW")
				end
			end
		end
		return
	end
	for i = 1, #UNITS do
		self:Layout(UNITS[i])
	end
	SuppressBlizzard()
	if Soul.Blizz then Soul.Blizz.Refresh() end
end

function UF:OnInitialize()
	Soul:RegisterModuleDB("UnitFrames", Soul.Defaults.UnitFrames)
end

function UF:OnEnable()
	local hider = CreateFrame("Frame", "SoulUI_PetBattleHider", UIParent, "SecureHandlerStateTemplate")
	hider:SetSize(1, 1)
	hider:SetPoint("CENTER")
	hider:EnableMouse(false)
	pcall(RegisterStateDriver, hider, "visibility", "[petbattle] hide; show")
	self.hider = hider
	self.frames = {}

	for i = 1, #UNITS do
		local unit = UNITS[i]
		local frame = CreateUnitFrame(unit, hider)
		self.frames[unit] = frame
		local unitKey = unit
		Soul:RegisterMover({
			key = "UnitFrames:" .. unitKey,
			label = LABELS[unitKey],
			getFrame = function() return frame end,
			getEnabled = function() return DB().units[unitKey].enabled end,
			setEnabled = function(on)
				DB().units[unitKey].enabled = on and true or false
				UF:Layout(unitKey)
				if Soul.Blizz then Soul.Blizz.Refresh() end
			end,
			fallback = function()
				local cfg = DB().units[unitKey]
				return { point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y }
			end,
			onResize = function(width, height, dir)
				local cfg = DB().units[unitKey]
				local healthH = height
				if cfg.showPower then
					healthH = height - (cfg.powerHeight or 0)
				end
				if dir == 1 or dir == -1 then
					cfg.width = Soul:ScaleStep(cfg.width or width, dir, 40, 800)
					cfg.height = Soul:ScaleStep(cfg.height or healthH, dir, 8, 200)
				else
					cfg.width = Soul:QuantizeSize(cfg.width, width, nil, 40, 800)
					cfg.height = Soul:QuantizeSize(cfg.height, healthH, nil, 8, 200)
				end
				UF:Layout(unitKey)
			end,
			getColor = function()
				local cfg = DB().units[unitKey]
				if type(cfg.color) == "table" then return cfg.color[1], cfg.color[2], cfg.color[3] end
				local live = UF.frames[unitKey]
				if live and live.Health.GetStatusBarColor then
					local r, g, b = live.Health:GetStatusBarColor()
					if type(r) == "number" and not Soul.Secret.IsSecret(r) then return r, g, b end
				end
				return 0.6, 0.2, 0.8
			end,
			setColor = function(r, g, b)
				DB().units[unitKey].color = { r, g, b }
				local live = UF.frames[unitKey]
				if live and live:IsShown() then UpdateHealth(live) end
			end,
		})
		Soul:RegisterMover({
			key = "UnitFrames:" .. unitKey .. ":cast",
			label = LABELS[unitKey] .. " Cast Bar",
			getEnabled = function() return DB().units[unitKey].showCast end,
			setEnabled = function(on)
				DB().units[unitKey].showCast = on and true or false
				UF:Layout(unitKey)
				if Soul.Blizz then Soul.Blizz.Refresh() end
			end,
			getFrame = function() return frame.Cast end,
			fallback = function()
				return {
					point = "BOTTOM", relPoint = "TOP", x = 0, y = 4,
					relative = "UnitFrames:" .. unitKey,
				}
			end,
			onResize = function(width, height, dir)
				local cfg = DB().units[unitKey]
				local oldW = cfg.castWidth or cfg.width or width
				local oldH = cfg.castHeight or 16
				if dir == 1 or dir == -1 then
					cfg.castWidth = Soul:ScaleStep(oldW, dir, 40, 800)
					cfg.castHeight = Soul:ScaleStep(oldH, dir, 8, 80)
				else
					cfg.castWidth = Soul:QuantizeSize(oldW, width, nil, 40, 800)
					cfg.castHeight = Soul:QuantizeSize(oldH, height, nil, 8, 80)
				end
				UF:Layout(unitKey)
			end,
			getColor = function()
				if ENEMY_CAST[unitKey] then
					local c = Soul.Cast.Settings().interruptible
					return c[1], c[2], c[3]
				end
				local cfg = DB().units[unitKey]
				if type(cfg.castColor) == "table" then return cfg.castColor[1], cfg.castColor[2], cfg.castColor[3] end
				return Soul:Accent()
			end,
			setColor = function(r, g, b)
				if ENEMY_CAST[unitKey] then
					-- Enemy colors are shared (General > Casts): change the interruptible one.
					Soul.Cast.Settings().interruptible = { r, g, b }
					Soul:Fire("ThemeChanged")
				else
					DB().units[unitKey].castColor = { r, g, b }
				end
				if frame._soulPreviewCast and DB().units[unitKey].showCast then frame.Cast:SetPreview(true) end
			end,
			onEdit = function(on)
				frame._soulPreviewCast = on and true or false
				UF:Layout(unitKey)
			end,
		})
	end

	local function OnEvent(_, event, unit)
		if event == "PLAYER_TARGET_CHANGED" then
			local target = UF.frames.target
			local tot = UF.frames.targettarget
			if target and target:IsShown() then UpdateFrame(target, "SHOW") end
			if tot and tot:IsShown() then UpdateFrame(tot, "SHOW") end
			for n = 1, #UNITS do
				local frame = UF.frames[UNITS[n]]
				if frame and frame.TargetMark and frame:IsShown() then UpdateTargetMark(frame) end
			end
			return
		end
		if event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
			for n = 1, #UNITS do
				local frame = UF.frames[UNITS[n]]
				if frame and frame:IsShown() then
					UpdateRaidIcon(frame)
					UpdateLeader(frame)
				end
			end
			return
		end
		if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
			local player = UF.frames.player
			if player then UpdateCombat(player) end
			return
		end
		if event == "PLAYER_FOCUS_CHANGED" then
			local focus = UF.frames.focus
			if focus and focus:IsShown() then UpdateFrame(focus, "SHOW") end
			return
		end
		if event == "UNIT_TARGET" and unit == "target" then
			local tot = UF.frames.targettarget
			if tot and tot:IsShown() then UpdateFrame(tot, "SHOW") end
			return
		end
		if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_FOCUS_CHANGED" then
			for n = 1, #UNITS do
				local frame = UF.frames[UNITS[n]]
				if frame and frame:IsShown() then UpdateFrame(frame, "SHOW") end
			end
			return
		end
		local token = unit
		if token == "vehicle" then token = "player" end
		local frame = UF.frames[token]
		if frame and frame:IsShown() then
			UpdateFrame(frame, event)
		end
	end

	local watch = {
		"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_FACTION", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
		"UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
		"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
		"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
		"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
		"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
	}
	for i = 1, #watch do
		for n = 1, #UNITS do
			pcall(self.RegisterUnitEvent, self, watch[i], OnEvent, UNITS[n])
		end
		pcall(self.RegisterUnitEvent, self, watch[i], OnEvent, "vehicle")
	end
	pcall(self.RegisterUnitEvent, self, "UNIT_POWER_FREQUENT", OnEvent, "player")
	pcall(self.RegisterUnitEvent, self, "UNIT_TARGET", OnEvent, "target")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", OnEvent)
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnEvent)
	self:RegisterEvent("RAID_TARGET_UPDATE", OnEvent)
	self:RegisterEvent("PARTY_LEADER_CHANGED", OnEvent)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", OnEvent)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", OnEvent)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", OnEvent)
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
		local ready
		for n = 1, #UNITS do
			local live = UF.frames[UNITS[n]]
			if live and live.Cast.enemy and live.Cast:IsShown() and live.Cast._soulCastState then
				ready = ready or Soul.Cast.KickReady()
				Soul.Cast.Recolor(live.Cast, live.Cast.Bar, ready)
			end
		end
	end)
	self:RegisterEvent("UNIT_PET", function(_, _, unit)
		if unit == "player" then
			local pet = UF.frames.pet
			if pet and pet:IsShown() then UpdateFrame(pet, "SHOW") end
		end
	end)

	Soul:On("ProfileChanged", function() UF:Apply("all") end)
	Soul:On("ThemeChanged", function() UF:Apply("colors") end)
	self:Apply("all")
end
