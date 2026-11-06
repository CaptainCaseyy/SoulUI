if SoulUI_Blocked then return end

-- One cast bar for every unit (0.7.0): player (Resources), unit frames and
-- nameplates all build theirs here, so the cast logic and the look live in one
-- place.
--
--   local cb = Soul.CastBar.New(parent, { enemy = true })
--   cb:SetUnit("target")
--   cb.allowed = function() return cfg.showCast end
--   cb:Layout(height, showIcon, fontSize)         -- width comes from the caller's anchors / SetWidth
--   cb:HandleEvent(event)                         -- forward UNIT_SPELLCAST_* for cb.unit
--   cb:Refresh()                                  -- unit changed / plate shown / settings changed
--   cb:SetPreview(on)                             -- edit-mode sample
--
-- Why it is reliable:
--   * An end event (STOP, FAILED, INTERRUPTED, ...) never hides blindly. It
--     re-asks the game whether the unit is still casting. Pressing a key mid
--     cast fires FAILED for the attempt, and with spell queueing the old cast's
--     STOP can land after the next START; both used to hide a live bar.
--   * A START whose duration object is not ready yet retries a few times on
--     the next frames instead of giving up.
--   * allowed() is checked on every path, so a disabled bar never appears.
--
-- Look: 1px black border, dark track, square icon flush left, fill with a
-- spark at its edge, name left, remaining time right. A finished cast fades
-- out; an interrupted one flashes red with "Interrupted".
--
-- Enemy bars color through Soul.Cast.Paint (interruptible / kick on cooldown /
-- locked, important outline, STUN badge). Friendly bars use getColor() or the
-- accent, gray while not interruptible. Secret values are never compared.

local Soul = SoulUI
local CB = {}
Soul.CastBar = CB

local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"

local START = {
	UNIT_SPELLCAST_START = "cast",
	UNIT_SPELLCAST_CHANNEL_START = "channel",
	UNIT_SPELLCAST_EMPOWER_START = "empower",
}
local FINISH = {
	UNIT_SPELLCAST_STOP = true,
	UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_FAILED_QUIET = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_EMPOWER_STOP = true,
}
CB.EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
}

function CB.IsCastEvent(event)
	return type(event) == "string" and event:find("UNIT_SPELLCAST", 1, true) == 1
end

local Present = function(v) return Soul.Secret.Present(v) end

local function TimeBinding(fontString)
	if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then return nil end
	local ok, binding = pcall(C_DurationUtil.CreateDurationTextBinding)
	if not ok or not binding then return nil end
	pcall(binding.SetFontString, binding, fontString)
	if C_StringUtil and C_StringUtil.CreateSecondsFormatter then
		local made, formatter = pcall(C_StringUtil.CreateSecondsFormatter)
		if made and formatter then pcall(binding.SetFormatter, binding, formatter) end
	end
	-- 0 can mean "do not tick" on a duration binding. 0.01 is every hundredth
	-- of a second, which reads as instant and still lets the binding own the text.
	pcall(binding.SetUpdateInterval, binding, 0.01)
	pcall(binding.SetZeroDurationText, binding, "")
	pcall(binding.SetExpiredText, binding, "")
	return binding
end

local methods = {}

function CB.New(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", opts.name, parent or UIParent)
	f:Hide()
	f:EnableMouse(false)
	Soul:Round(f)
	f.enemy = opts.enemy and true or false
	f.getColor = opts.getColor
	f.showIcon = true

	local back = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 1)

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.Icon = icon

	local bar = Soul:StatusBar(f)
	bar.bg:SetColorTexture(0.07, 0.075, 0.085, 1)
	f.Bar = bar

	local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
	spark:SetTexture(SPARK)
	spark:SetBlendMode("ADD")
	spark:SetWidth(10)
	spark:SetPoint("TOP", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 4)
	spark:SetPoint("BOTTOM", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, -4)
	spark:SetAlpha(0.85)
	f.Spark = spark

	local time = bar:CreateFontString(nil, "OVERLAY", nil, 2)
	time:SetPoint("RIGHT", -5, 0)
	time:SetJustifyH("RIGHT")
	time:SetWordWrap(false)
	time:SetTextColor(1, 1, 1)
	f.Time = time
	local text = bar:CreateFontString(nil, "OVERLAY", nil, 2)
	text:SetPoint("LEFT", 6, 0)
	text:SetPoint("RIGHT", time, "LEFT", -6, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	text:SetTextColor(1, 1, 1)
	f.Text = text
	f.TimeBinding = TimeBinding(time)

	-- Friendly casts that cannot be interrupted: a light wash over the fill.
	local shield = bar:CreateTexture(nil, "OVERLAY")
	shield:SetAllPoints()
	shield:SetColorTexture(1, 1, 1, 0.12)
	shield:SetAlpha(0)
	f.Shield = shield

	-- End of cast: hold, then fade (alpha only, so nothing re-lays out).
	local fade = f:CreateAnimationGroup()
	local out = fade:CreateAnimation("Alpha")
	out:SetFromAlpha(1)
	out:SetToAlpha(0)
	out:SetDuration(0.3)
	out:SetStartDelay(0.15)
	fade:SetScript("OnFinished", function()
		f:Hide()
		f:SetAlpha(1)
	end)
	f.Fade = fade
	f.FadeOut = out

	f:SetScript("OnHide", function(self)
		if self.TimeBinding then pcall(self.TimeBinding.Disable, self.TimeBinding) end
	end)
	-- A parent hide (Alt+Z, pet battle) disables the binding; resume it.
	f:SetScript("OnShow", function(self)
		if self._live and self._duration and self.TimeBinding then
			pcall(self.TimeBinding.SetDuration, self.TimeBinding, self._duration)
			pcall(self.TimeBinding.Enable, self.TimeBinding)
		end
	end)
	f.poll = opts.poll and true or false
	f.colorA = CreateColor(1, 1, 1, 1)
	f.colorLocked = CreateColor(0.48, 0.48, 0.52, 1)

	for name, fn in pairs(methods) do f[name] = fn end
	f:Layout(opts.height or 18, true)
	if f.enemy then Soul.Cast.Decorate(f, bar) end
	return f
end

-- height: bar height; icon square on the left when showIcon.
function methods:Layout(height, showIcon, fontSize)
	height = math.max(6, height or 18)
	self._height = height
	self.showIcon = showIcon ~= false
	local px = Soul.Pixel:Scale(1)
	self:SetHeight(height)
	self.Icon:ClearAllPoints()
	self.Bar:ClearAllPoints()
	if self.showIcon then
		self.Icon:SetPoint("TOPLEFT", px, -px)
		self.Icon:SetSize(height - 2 * px, height - 2 * px)
		self.Icon:Show()
		self.Bar:SetPoint("TOPLEFT", self.Icon, "TOPRIGHT", px, 0)
	else
		self.Icon:Hide()
		self.Bar:SetPoint("TOPLEFT", px, -px)
	end
	self.Bar:SetPoint("BOTTOMRIGHT", -px, px)
	self.Bar:SetStatusBarTexture(Soul:StatusbarTexture())
	local size = fontSize and fontSize > 0 and fontSize or math.max(9, math.min(15, math.floor(height * 0.55 + 0.5)))
	Soul:ApplyFont(self.Text, size, "OUTLINE")
	Soul:ApplyFont(self.Time, math.max(8, size - 1), "OUTLINE")
	self.Spark:SetWidth(math.max(6, math.floor(height * 0.6)))
	if self.enemy then Soul.Cast.Size(self, height) end
end

function methods:SetUnit(unit)
	self.unit = unit
end

function methods:Allowed()
	if not self.unit then return false end
	if self.allowed and not self.allowed() then return false end
	return true
end

local function CancelPoll(self)
	if self._ticker then
		self._ticker:Cancel()
		self._ticker = nil
	end
end

function methods:Stop()
	CancelPoll(self)
	self._live = false
	self._tries = 0
	self.Fade:Stop()
	self:SetAlpha(1)
	if self.enemy then Soul.Cast.Clear(self) end
	self:Hide()
end

-- Color for a live cast.
function methods:Paint(notInterruptible, spellID)
	if self.enemy then
		self.Shield:SetAlpha(0)
		Soul.Cast.Paint(self, self.Bar, notInterruptible, spellID, self.baseColor and self.baseColor())
		return
	end
	local r, g, b
	if self.getColor then r, g, b = self.getColor() end
	if not r then r, g, b = Soul:Accent() end
	self.colorA:SetRGBA(r, g, b, 1)
	local picked = Soul.Secret.PickColor(notInterruptible, self.colorA, self.colorLocked)
	if picked and picked.GetRGB then
		self.Bar:SetStatusBarColor(picked:GetRGB())
	else
		self.Bar:SetStatusBarColor(r, g, b)
	end
	Soul.Secret.AlphaFromBool(self.Shield, notInterruptible, 1, 0)
end

-- kind: "cast" | "channel" | "empower". Returns true when the bar is showing.
function methods:Start(kind)
	if not self:Allowed() then
		self:Stop()
		return false
	end
	local unit = self.unit
	local duration
	if kind == "empower" and UnitEmpoweredChannelDuration then
		local ok, value = pcall(UnitEmpoweredChannelDuration, unit)
		if ok then duration = value end
	end
	if not Present(duration) then
		if kind == "cast" then
			duration = UnitCastingDuration(unit)
		else
			duration = UnitChannelDuration(unit)
		end
	end
	if not Present(duration) then
		-- The duration object can trail the START event by a frame.
		self._tries = (self._tries or 0) + 1
		if self._tries <= 8 then
			C_Timer.After(0, function()
				if self.unit == unit and not self._preview and not self._live then
					self:Start(kind)
				end
			end)
		end
		return false
	end
	local name, texture, notInterruptible, spellID, _
	if kind == "cast" then
		name, _, texture, _, _, _, _, notInterruptible, spellID = UnitCastingInfo(unit)
	else
		name, _, texture, _, _, _, notInterruptible, spellID = UnitChannelInfo(unit)
	end
	local direction = Enum.StatusBarTimerDirection
	local interp = Enum.StatusBarInterpolation
	if not (self.Bar.SetTimerDuration and direction and interp) then
		self:Stop()
		return false
	end
	local which = kind == "cast" and direction.ElapsedTime or direction.RemainingTime
	if not pcall(self.Bar.SetTimerDuration, self.Bar, duration, interp.Immediate, which) then
		self:Stop()
		return false
	end
	if self.Bar.SetToTargetValue then self.Bar:SetToTargetValue() end
	self._tries = 0
	self.Fade:Stop()
	self:SetAlpha(1)
	self.Text:SetText(name or "")
	self.Text:SetTextColor(1, 1, 1)
	if self.showIcon then
		if Present(texture) then pcall(self.Icon.SetTexture, self.Icon, texture) end
		self.Icon:Show()
	end
	self.Spark:Show()
	self:Paint(notInterruptible, spellID)
	if self.TimeBinding then
		pcall(self.TimeBinding.SetDuration, self.TimeBinding, duration)
		pcall(self.TimeBinding.Enable, self.TimeBinding)
	end
	self._live = true
	self._duration = duration
	-- Units the game sends no cast events for (target of target) are polled
	-- while a cast is up, so the bar still ends.
	if self.poll and not self._ticker then
		self._ticker = C_Timer.NewTicker(0.05, function()
			if not self._live then CancelPoll(self) return end
			local unitNow = self.unit
			if not unitNow or not UnitExists(unitNow) or not (Present(UnitCastingInfo(unitNow)) or Present(UnitChannelInfo(unitNow))) then
				self:Finish(false)
			end
		end)
	end
	self:Show()
	return true
end

-- Asks the game what the unit is doing now. Returns true while casting.
function methods:Refresh()
	if self._preview then return true end
	if not self:Allowed() then
		self:Stop()
		return false
	end
	local unit = self.unit
	if not UnitExists(unit) then
		self:Stop()
		return false
	end
	if Present(UnitCastingInfo(unit)) then return self:Start("cast") end
	local channelName = UnitChannelInfo(unit)
	if Present(channelName) then
		local empowered = select(9, UnitChannelInfo(unit))
		local kind = (not Soul.Secret.IsSecret(empowered) and empowered == true) and "empower" or "channel"
		return self:Start(kind)
	end
	return false
end

-- The unit behind the bar changed (new target, plate reused): drop whatever
-- was showing, then show the new unit's cast if it has one.
function methods:Reset()
	if self._preview then return end
	self:Stop()
	self:Refresh()
end

-- The cast ended: fade, or flash red when interrupted.
function methods:Finish(interrupted)
	CancelPoll(self)
	self._live = false
	if self.TimeBinding then pcall(self.TimeBinding.Disable, self.TimeBinding) end
	if self.enemy then Soul.Cast.Clear(self) end
	if not self:IsShown() then
		self:Stop()
		return
	end
	self.Spark:Hide()
	self.Time:SetText("")
	if interrupted then
		self.Bar:SetStatusBarColor(0.85, 0.16, 0.16)
		self.Shield:SetAlpha(0)
		self.Text:SetText(INTERRUPTED or "Interrupted")
		self.FadeOut:SetStartDelay(0.45)
	else
		self.FadeOut:SetStartDelay(0.05)
	end
	self.Fade:Stop()
	self.Fade:Play()
end

function methods:HandleEvent(event)
	if self._preview then return end
	if not self:Allowed() then
		self:Stop()
		return
	end
	local kind = START[event]
	if kind then
		self._tries = 0
		self:Start(kind)
		return
	end
	if FINISH[event] then
		-- Still casting (a failed attempt, or the next queued spell)? Keep it.
		if self:Refresh() then return end
		-- Only a live cast finishes; a second end event during the fade
		-- (INTERRUPTED then STOP) must not cut the red flash short.
		if self._live then
			self:Finish(event == "UNIT_SPELLCAST_INTERRUPTED")
		elseif not self:IsShown() then
			self:Stop()
		end
		return
	end
	-- DELAYED, CHANNEL_UPDATE, EMPOWER_UPDATE, (NOT_)INTERRUPTIBLE: re-read.
	if not self:Refresh() and self._live then self:Finish(false) end
end

-- Edit-mode sample: icon, name, partial fill, time.
function methods:SetPreview(on)
	self._preview = on and true or false
	if not on then
		self:Stop()
		self:Refresh()
		return
	end
	self.Fade:Stop()
	self:SetAlpha(1)
	if self.TimeBinding then pcall(self.TimeBinding.Disable, self.TimeBinding) end
	self.Text:SetText("Spell name")
	self.Text:SetTextColor(1, 1, 1)
	self.Time:SetText("1.4")
	self.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	self.Bar:SetMinMaxValues(0, 1)
	self.Bar:SetValue(0.62)
	self.Spark:Show()
	self.Shield:SetAlpha(0)
	if self.enemy then
		Soul.Cast.Preview(self, self.Bar, "interruptible")
		local base = self.baseColor and self.baseColor()
		if base then self.Bar:SetStatusBarColor(base[1], base[2], base[3]) end
	else
		local r, g, b
		if self.getColor then r, g, b = self.getColor() end
		if not r then r, g, b = Soul:Accent() end
		self.Bar:SetStatusBarColor(r, g, b)
	end
	self:Show()
end
