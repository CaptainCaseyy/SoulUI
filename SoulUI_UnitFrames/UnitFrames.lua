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

local CAST_END = {
	UNIT_SPELLCAST_STOP = true,
	UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_FAILED_QUIET = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_EMPOWER_STOP = true,
}

local function DB()
	return Soul:ModuleDB("UnitFrames")
end

local function ColorHealth(bar, unit)
	local cfg = DB().units[unit]
	local color = cfg and cfg.color
	if type(color) == "table" then
		bar:SetStatusBarColor(color[1], color[2], color[3])
		return
	end
	Soul:ColorUnitHealth(bar, unit)
end

local function UpdateHealth(frame)
	local unit = frame._soulUnit
	local bar = frame.Health
	if not unit or not UnitExists(unit) then return end
	local dead = UnitIsDeadOrGhost(unit)
	local connected = UnitIsConnected(unit)
	if not Soul.Secret.IsSecret(dead) and dead then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		bar:SetStatusBarColor(0.35, 0.35, 0.35)
	elseif not Soul.Secret.IsSecret(connected) and not connected then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar:SetStatusBarColor(0.4, 0.4, 0.4)
	else
		local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
		bar:SetMinMaxValues(0, UnitHealthMax(unit))
		if interp then
			bar:SetValue(UnitHealth(unit), interp)
		else
			bar:SetValue(UnitHealth(unit))
		end
		ColorHealth(bar, unit)
	end
	local absorb = bar._absorb
	local over = bar._overAbsorb
	if UnitGetTotalAbsorbs and (absorb or over) then
		local width = bar:GetWidth()
		local maxHealth = UnitHealthMax(unit)
		local amount = UnitGetTotalAbsorbs(unit)
		if absorb then
			absorb:SetWidth(width)
			absorb:SetMinMaxValues(0, maxHealth)
			absorb:SetValue(amount)
		end
		if over then
			over:SetWidth(width)
			over:SetMinMaxValues(0, maxHealth)
			over:SetValue(amount)
		end
	end
	local format = (DB().units[unit] or {}).healthFormat or "both"
	local curve = CurveConstants and CurveConstants.ScaleTo100
	if format == "none" then
		frame.HealthText:SetText("")
	elseif format == "value" or not curve then
		frame.HealthText:SetFormattedText("%s", Soul:Abbrev(UnitHealth(unit)))
	elseif format == "percent" then
		frame.HealthText:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve))
	else
		frame.HealthText:SetFormattedText("%s | %.0f%%", Soul:Abbrev(UnitHealth(unit)), UnitHealthPercent(unit, true, curve))
	end
end

local function UpdatePower(frame)
	local unit = frame._soulUnit
	local bar = frame.Power
	if not unit or not bar:IsShown() or not UnitExists(unit) then return end
	bar:SetMinMaxValues(0, UnitPowerMax(unit))
	bar:SetValue(UnitPower(unit))
	bar:SetStatusBarColor(Soul:PowerColor(UnitPowerType(unit)))
end

local function UpdateName(frame)
	local unit = frame._soulUnit
	if not unit or not UnitExists(unit) then
		frame.Name:SetText("")
		return
	end
	local name = UnitName(unit)
	frame.Name:SetText(name or "")
end

local function TintCast(bar, notInterruptible)
	local r, g, b = Soul:Accent()
	local accent = CreateColor(r, g, b, 1)
	local grey = CreateColor(0.45, 0.45, 0.48, 1)
	local picked = Soul.Secret.PickColor(notInterruptible, accent, grey)
	if picked and picked.GetRGB then
		bar:SetStatusBarColor(picked:GetRGB())
	else
		bar:SetStatusBarColor(r, g, b)
	end
end

local function ShowCast(frame, channel, empower)
	local unit = frame._soulUnit
	local cast = frame.Cast
	local duration
	if empower and UnitEmpoweredChannelDuration then
		duration = UnitEmpoweredChannelDuration(unit)
	elseif channel then
		duration = UnitChannelDuration(unit)
	else
		duration = UnitCastingDuration(unit)
	end
	if not Soul.Secret.Present(duration) then
		if not frame._soulCastTries then
			frame._soulCastTries = 1
			C_Timer.After(0, function()
				if frame._soulPreviewCast then return end
				ShowCast(frame, channel, empower)
			end)
		end
		return
	end
	frame._soulCastTries = nil
	local info, notInterruptible
	if channel or empower then
		info = { UnitChannelInfo(unit) }
		notInterruptible = info[7]
	else
		info = { UnitCastingInfo(unit) }
		notInterruptible = info[8]
	end
	local name, texture = info[1], info[3]
	cast.Text:SetText(name or "")
	if Soul.Secret.Present(texture) then
		pcall(cast.Icon.SetTexture, cast.Icon, texture)
		cast.Icon:Show()
	end
	local direction = Enum.StatusBarTimerDirection
	local interp = Enum.StatusBarInterpolation
	if not (cast.Bar.SetTimerDuration and direction and interp) then
		cast:Hide()
		return
	end
	local which = (channel or empower) and direction.RemainingTime or direction.ElapsedTime
	local ok = pcall(cast.Bar.SetTimerDuration, cast.Bar, duration, interp.Immediate, which)
	if not ok then
		cast:Hide()
		return
	end
	if cast.Bar.SetToTargetValue then
		cast.Bar:SetToTargetValue()
	end
	local cfg = frame._cfg
	local custom = cfg and type(cfg.castColor) == "table" and cfg.castColor or nil
	if unit == "player" or unit == "vehicle" or unit == "pet" then
		TintCast(cast.Bar, notInterruptible)
		if custom then cast.Bar:SetStatusBarColor(custom[1], custom[2], custom[3]) end
		Soul.Secret.AlphaFromBool(cast.Shield, notInterruptible, 1, 0)
	else
		-- Enemy casts: interruptible / kick on cooldown / locked, important
		-- outline and STUN badge (Core/Casts.lua). castColor replaces only the
		-- interruptible color.
		local spellID
		if channel or empower then spellID = info[8] else spellID = info[9] end
		cast.Shield:SetAlpha(0)
		Soul.Cast.Paint(cast, cast.Bar, notInterruptible, spellID, custom)
	end
	if cast.TimeBinding then
		pcall(cast.TimeBinding.SetDuration, cast.TimeBinding, duration)
		pcall(cast.TimeBinding.Enable, cast.TimeBinding)
	end
	cast:Show()
end

local function ShowCastPreview(frame)
	local cast = frame.Cast
	cast.Text:SetText("Spell name")
	if cast.TimeBinding then pcall(cast.TimeBinding.Disable, cast.TimeBinding) end
	if cast.Time then cast.Time:SetText("1.4") end
	cast.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	cast.Icon:Show()
	cast.Bar:SetMinMaxValues(0, 1)
	cast.Bar:SetValue(0.65)
	local cfg = frame._cfg
	if frame._soulUnit == "player" then
		if cfg and type(cfg.castColor) == "table" then
			cast.Bar:SetStatusBarColor(cfg.castColor[1], cfg.castColor[2], cfg.castColor[3])
		else
			local r, g, b = Soul:Accent()
			cast.Bar:SetStatusBarColor(r, g, b)
		end
	else
		Soul.Cast.Preview(cast, cast.Bar, "interruptible")
	end
	cast:Show()
end

local function RefreshCast(frame)
	local unit = frame._soulUnit
	local cfg = frame._cfg
	if frame._soulPreviewCast and cfg and cfg.showCast then
		ShowCastPreview(frame)
		return
	end
	if not cfg or not cfg.showCast or not unit or not UnitExists(unit) then
		frame.Cast:Hide()
		return
	end
	local casting = UnitCastingInfo(unit)
	if Soul.Secret.Present(casting) then
		ShowCast(frame, false, false)
		return
	end
	local channel = UnitChannelInfo(unit)
	if Soul.Secret.Present(channel) then
		ShowCast(frame, true, false)
	else
		frame.Cast:Hide()
	end
end

-- Purge outline only makes sense on something you can attack.
local function UpdatePurgeGlow(frame)
	if not frame.PurgeGlow then return end
	local unit = frame._soulUnit
	local db = DB()
	local magic, enrage = Soul.Auras.OffensiveDispel()
	local can = unit and UnitExists(unit) and UnitCanAttack("player", unit)
	local show = db.purgeGlow ~= false and (magic or enrage) and not Soul.Secret.IsSecret(can) and can and true or false
	Soul.Auras.SetShown(frame.PurgeGlow, show)
end

local function UpdateFrame(frame, event)
	UpdateHealth(frame)
	UpdatePower(frame)
	UpdateName(frame)
	if event == "SHOW" then UpdatePurgeGlow(frame) end
	if event == "SHOW" or (type(event) == "string" and event:find("SPELLCAST", 1, true)) then
		if CAST_END[event] then
			frame._soulCastTries = nil
			Soul.Cast.Clear(frame.Cast)
			if frame._soulPreviewCast then
				ShowCastPreview(frame)
			else
				frame.Cast:Hide()
			end
		elseif event == "UNIT_SPELLCAST_START" then
			ShowCast(frame, false, false)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
			ShowCast(frame, true, false)
		elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
			ShowCast(frame, true, true)
		else
			RefreshCast(frame)
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

local function CreateUnitFrame(unit, parent)
	local created, frame = pcall(CreateFrame, "Button", "SoulUI_UF_" .. unit, parent, "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
	if not created then
		frame = CreateFrame("Button", "SoulUI_UF_" .. unit, parent, "SecureUnitButtonTemplate")
	end
	frame._soulUnit = unit
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

	local health = Soul:StatusBar(frame)
	health:SetPoint("TOPLEFT")
	health:SetPoint("TOPRIGHT")
	frame.Health = health
	-- Dispel outlines (Core/Auras.lua): a debuff you can cleanse on a friend,
	-- or a buff you can purge / soothe on an enemy target or focus.
	frame.DispelGlow = Soul.Auras.Highlight(health, unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", { 0.8, 0.35, 1 }, 2)
	if unit == "target" or unit == "focus" then
		frame.PurgeGlow = Soul.Auras.Highlight(health, unit, "HELPFUL|DISPELLABLE", { 0.25, 0.65, 1 }, 2)
	end
	local fill = health:GetStatusBarTexture()
	local clip = CreateFrame("Frame", nil, health)
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	clip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
	local absorb = CreateFrame("StatusBar", nil, clip)
	absorb:SetStatusBarTexture(Soul:StatusbarTexture())
	absorb:SetStatusBarColor(0.85, 0.93, 1, 0.85)
	absorb:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	absorb:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
	absorb:SetWidth(340)
	health._absorb = absorb
	local overClip = CreateFrame("Frame", nil, health)
	if overClip.SetClipsChildren then overClip:SetClipsChildren(true) end
	overClip:SetPoint("TOPLEFT", health, "TOPLEFT")
	overClip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	local over = CreateFrame("StatusBar", nil, overClip)
	over:SetStatusBarTexture(Soul:StatusbarTexture())
	over:SetStatusBarColor(1, 1, 1, 0.28)
	over:SetReverseFill(true)
	over:SetPoint("TOPRIGHT", health, "TOPRIGHT")
	over:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
	over:SetWidth(340)
	health._overAbsorb = over

	local shade = health:CreateTexture(nil, "ARTWORK", nil, 7)
	shade:SetAllPoints()
	shade:SetTexture("Interface\\Buttons\\WHITE8X8")
	if shade.SetGradient and CreateColor then
		pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.34), CreateColor(1, 1, 1, 0.10))
	end

	local name = health:CreateFontString(nil, "OVERLAY")
	name:SetPoint("LEFT", 8, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	name:SetWordWrap(false)
	frame.Name = name

	local percent = health:CreateFontString(nil, "OVERLAY")
	percent:SetPoint("RIGHT", -8, 0)
	percent:SetJustifyH("RIGHT")
	frame.HealthText = percent
	name:SetPoint("RIGHT", percent, "LEFT", -6, 0)

	local power = Soul:StatusBar(frame)
	frame.Power = power

	local cast = CreateFrame("Frame", nil, UIParent)
	cast:SetFrameStrata(frame:GetFrameStrata())
	cast:Hide()
	local icon = cast:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cast.Icon = icon
	local castBar = Soul:StatusBar(cast)
	cast.Bar = castBar
	local timeText = castBar:CreateFontString(nil, "OVERLAY")
	timeText:SetPoint("RIGHT", -6, 0)
	timeText:SetJustifyH("RIGHT")
	timeText:SetWordWrap(false)
	cast.Time = timeText
	local castText = castBar:CreateFontString(nil, "OVERLAY")
	castText:SetPoint("LEFT", 6, 0)
	castText:SetPoint("RIGHT", timeText, "LEFT", -4, 0)
	castText:SetJustifyH("LEFT")
	castText:SetWordWrap(false)
	cast.Text = castText
	if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
		local ok, binding = pcall(C_DurationUtil.CreateDurationTextBinding)
		if ok and binding then
			pcall(binding.SetFontString, binding, timeText)
			if C_StringUtil and C_StringUtil.CreateSecondsFormatter then
				local made, formatter = pcall(C_StringUtil.CreateSecondsFormatter)
				if made and formatter then pcall(binding.SetFormatter, binding, formatter) end
			end
			pcall(binding.SetUpdateInterval, binding, 0.1)
			pcall(binding.SetZeroDurationText, binding, "")
			pcall(binding.SetExpiredText, binding, "")
			cast.TimeBinding = binding
		end
	end
	local shield = castBar:CreateTexture(nil, "OVERLAY")
	shield:SetPoint("TOPRIGHT", -1, -1)
	shield:SetPoint("BOTTOMRIGHT", -1, 1)
	shield:SetWidth(3)
	shield:SetColorTexture(0.85, 0.85, 0.9, 0.95)
	shield:SetAlpha(0)
	cast.Shield = shield
	Soul:Border(cast)
	frame.Cast = cast

	Soul:Border(frame)
	frame:HookScript("OnShow", function(self) UpdateFrame(self, "SHOW") end)
	frame:HookScript("OnHide", function(self)
		if self._soulPreviewCast then return end
		self.Cast:Hide()
	end)
	cast:HookScript("OnHide", function(self)
		if self.TimeBinding then pcall(self.TimeBinding.Disable, self.TimeBinding) end
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
			frame.Cast:Hide()
			return
		end
		local height = live.height
		if live.showPower then
			height = height + live.powerHeight
		end
		frame:SetSize(live.width, height)
		frame.Health:SetHeight(live.height)
		Soul.Auras.Refit(frame.DispelGlow, frame.Health)
		Soul.Auras.Refit(frame.PurgeGlow, frame.Health)
		Soul.Auras.SetShown(frame.DispelGlow, DB().dispelGlow ~= false)
		UpdatePurgeGlow(frame)
		frame.Power:SetShown(live.showPower and true or false)
		if live.showPower then
			frame.Power:ClearAllPoints()
			frame.Power:SetPoint("TOPLEFT", frame.Health, "BOTTOMLEFT")
			frame.Power:SetPoint("TOPRIGHT", frame.Health, "BOTTOMRIGHT")
			frame.Power:SetHeight(live.powerHeight)
		end
		-- Text layout from the reference: name in the top-left corner, health
		-- in the bottom-right corner. "center" puts both on the middle line;
		-- small frames can lift the name above the bar.
		local auto = math.floor(live.height * 0.26 + 0.5)
		if auto < 10 then auto = 10 end
		if auto > 18 then auto = 18 end
		local nameSize = (live.nameSize or 0) > 0 and live.nameSize or auto
		local healthSize = (live.healthSize or 0) > 0 and live.healthSize or auto
		Soul:ApplyFont(frame.Name, nameSize, "OUTLINE")
		Soul:ApplyFont(frame.HealthText, healthSize, "OUTLINE")
		frame.Name:SetTextColor(1, 1, 1)
		frame.HealthText:SetTextColor(1, 1, 1)
		frame.Name:ClearAllPoints()
		frame.HealthText:ClearAllPoints()
		local layout = live.textLayout or "corners"
		if live.namePosition == "above" then
			frame.Name:SetPoint("BOTTOMLEFT", frame.Health, "TOPLEFT", 1, 2)
			frame.Name:SetPoint("BOTTOMRIGHT", frame.Health, "TOPRIGHT", -1, 2)
		elseif layout == "center" then
			frame.Name:SetPoint("LEFT", frame.Health, "LEFT", 6, 0)
		else
			frame.Name:SetPoint("TOPLEFT", frame.Health, "TOPLEFT", 5, -4)
		end
		if layout == "center" then
			frame.HealthText:SetPoint("RIGHT", frame.Health, "RIGHT", -6, 0)
			if live.namePosition ~= "above" then
				frame.Name:SetPoint("RIGHT", frame.HealthText, "LEFT", -6, 0)
			end
		else
			frame.HealthText:SetPoint("BOTTOMRIGHT", frame.Health, "BOTTOMRIGHT", -5, 4)
			if live.namePosition ~= "above" then
				frame.Name:SetPoint("TOPRIGHT", frame.Health, "TOPRIGHT", -5, -4)
			end
		end
		frame.Name:SetShown(live.showName ~= false)
		Soul:ShowBorder(frame, false)
		local castH = live.castHeight or 16
		local castW = live.castWidth or live.width
		frame.Cast:SetSize(castW, castH)
		frame.Cast.Icon:SetSize(castH, castH)
		Soul.Cast.Decorate(frame.Cast, frame.Cast.Bar)
		Soul.Cast.Size(frame.Cast, castH)
		frame.Cast.Bar:ClearAllPoints()
		frame.Cast.Bar:SetPoint("TOPLEFT", frame.Cast.Icon, "TOPRIGHT", 1, 0)
		frame.Cast.Bar:SetPoint("BOTTOMRIGHT")
		local castFont = math.floor((live.castHeight or 16) * 0.5)
		if castFont < 10 then castFont = 10 end
		if castFont > 14 then castFont = 14 end
		Soul:ApplyFont(frame.Cast.Text, castFont, "OUTLINE")
		Soul:ApplyFont(frame.Cast.Time, castFont, "OUTLINE")
		frame.Cast.Text:SetTextColor(0.95, 0.95, 0.95)
		frame.Cast.Time:SetTextColor(0.95, 0.95, 0.95)
		Soul:ShowBorder(frame.Cast, false)
		local tex = Soul:StatusbarTexture()
		frame.Health:SetStatusBarTexture(tex)
		frame.Power:SetStatusBarTexture(tex)
		frame.Cast.Bar:SetStatusBarTexture(tex)
		Soul:Place(frame, "UnitFrames:" .. unit, { point = "CENTER", relPoint = "CENTER", x = live.x, y = live.y })
		Soul:Place(frame.Cast, "UnitFrames:" .. unit .. ":cast", {
			point = "BOTTOM", relPoint = "TOP", x = 0, y = 4,
			relative = "UnitFrames:" .. unit,
		})
		RegisterUnitWatch(frame)
		if frame._soulPreviewCast and live.showCast then
			ShowCastPreview(frame)
		elseif frame:IsShown() then
			UpdateFrame(frame, "SHOW")
		else
			frame.Cast:Hide()
		end
	end)
end

function UF:Apply(scope)
	if scope == "colors" then
		for i = 1, #UNITS do
			local frame = self.frames[UNITS[i]]
			if frame and frame:IsShown() then
				local tex = Soul:StatusbarTexture()
				frame.Health:SetStatusBarTexture(tex)
				frame.Power:SetStatusBarTexture(tex)
				frame.Cast.Bar:SetStatusBarTexture(tex)
				UpdateFrame(frame, "SHOW")
			end
		end
		return
	end
	for i = 1, #UNITS do
		self:Layout(UNITS[i])
	end
	SuppressBlizzard()
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
			fallback = function()
				local cfg = DB().units[unitKey]
				return { point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y }
			end,
			onResize = function(width, height)
				local cfg = DB().units[unitKey]
				local healthH = height
				if cfg.showPower then
					healthH = height - (cfg.powerHeight or 0)
				end
				if healthH < 10 then healthH = 10 end
				cfg.width = math.floor(width + 0.5)
				cfg.height = math.floor(healthH + 0.5)
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
				if live then ColorHealth(live.Health, unitKey) end
			end,
		})
		Soul:RegisterMover({
			key = "UnitFrames:" .. unitKey .. ":cast",
			label = LABELS[unitKey] .. " Cast Bar",
			isHidden = function() return not DB().units[unitKey].showCast end,
			getFrame = function() return frame.Cast end,
			fallback = function()
				return {
					point = "BOTTOM", relPoint = "TOP", x = 0, y = 4,
					relative = "UnitFrames:" .. unitKey,
				}
			end,
			onResize = function(width, height)
				local cfg = DB().units[unitKey]
				cfg.castWidth = math.floor(width + 0.5)
				cfg.castHeight = math.max(10, math.floor(height + 0.5))
				UF:Layout(unitKey)
			end,
			getColor = function()
				local cfg = DB().units[unitKey]
				if type(cfg.castColor) == "table" then return cfg.castColor[1], cfg.castColor[2], cfg.castColor[3] end
				return Soul:Accent()
			end,
			setColor = function(r, g, b)
				DB().units[unitKey].castColor = { r, g, b }
				frame.Cast.Bar:SetStatusBarColor(r, g, b)
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
		"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_FACTION", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
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
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
		local ready
		for n = 1, #UNITS do
			local live = UF.frames[UNITS[n]]
			if live and live.Cast:IsShown() and live.Cast._soulCastState then
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
