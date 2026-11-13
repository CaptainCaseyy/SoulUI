if SoulUI_Blocked or not SoulUI then return end

-- Text trackers: combat timer, combat alert, low durability, FPS and
-- latency, secondary stats, group death alert. Each is movable in
-- /soul move (key "QoL:<name>") and sized with the mouse wheel there.

local Soul = SoulUI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local C_Timer = C_Timer
local GetTime, InCombatLockdown, UnitAffectingCombat = GetTime, InCombatLockdown, UnitAffectingCombat
local math_floor, string_format, select, type = math.floor, string.format, select, type

local inCombat = false

local function InCombatNow()
	local combat = UnitAffectingCombat("player")
	if Q.IsSecret(combat) then return InCombatLockdown() end
	return combat and true or InCombatLockdown()
end

local function Clock(seconds)
	seconds = math_floor(seconds)
	return string_format("%d:%02d", math_floor(seconds / 60), seconds % 60)
end

-- A short fade for alert text: full alpha, then out.
local function AddFade(display, hold)
	local group = display.frame:CreateAnimationGroup()
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetStartDelay(hold or 0.8)
	fade:SetDuration(0.7)
	group:SetScript("OnFinished", function()
		display.playing = false
		display.frame:Hide()
		display.frame:SetAlpha(1)
	end)
	display.fade = group
end

local function Flash(display, text, r, g, b)
	if not display then return end
	display:Refresh()
	if not Q.on[display.info.feature] then return end
	display.fade:Stop()
	display.frame:SetAlpha(1)
	display.text:SetText(text)
	if r then display.text:SetTextColor(r, g, b) end
	display.playing = true
	display.frame:Show()
	display.fade:Play()
end

------------------------------------------------------------------------------
-- Combat timer
------------------------------------------------------------------------------

local timer = { start = nil, stop = nil, last = 0, ticker = nil }
local timerDisplay

local function TimerTick()
	if timerDisplay and timer.start then
		timerDisplay.text:SetText(Clock(GetTime() - timer.start))
	end
end

local function StartTimer()
	timer.start = GetTime()
	timer.stop = nil
	if timer.ticker then timer.ticker:Cancel() end
	timer.ticker = C_Timer.NewTicker(0.25, TimerTick)
	if timerDisplay then timerDisplay:Refresh() end
end

local function StopTimer()
	if timer.ticker then
		timer.ticker:Cancel()
		timer.ticker = nil
	end
	if timer.start then
		timer.last = GetTime() - timer.start
		timer.stop = GetTime()
	end
	timer.start = nil
end

local function TimerDisplay()
	timerDisplay = timerDisplay or Q:Display("combatTimer", {
		label = "Combat timer", feature = "combatTimer", sizeKey = "combatTimerSize",
		x = 0, y = 200, minSize = 10, maxSize = 48, ratio = 1.4,
		build = function(d) Q.TextDisplay(d) end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(math_floor(size * 3.6), math_floor(size * 1.4))
		end,
		sample = function(d)
			d.text:SetTextColor(1, 1, 1)
			d.text:SetText("1:23")
		end,
		paint = function(d)
			if timer.start then
				d.text:SetTextColor(1, 1, 1)
				d.text:SetText(Clock(GetTime() - timer.start))
				d.frame:Show()
			elseif timer.stop and GetTime() - timer.stop < 4 then
				-- The final time stays up, dimmed, for a few seconds.
				d.text:SetTextColor(0.6, 0.6, 0.6)
				d.text:SetText(Clock(timer.last))
				d.frame:Show()
			else
				d.frame:Hide()
			end
		end,
	})
	return timerDisplay
end

Q:Feature({
	key = "combatTimer",
	events = {
		PLAYER_REGEN_DISABLED = function() StartTimer() end,
		PLAYER_REGEN_ENABLED = function()
			StopTimer()
			if DB().combatTimerPrint and timer.last >= 3 then
				Soul:Print("Combat lasted " .. Clock(timer.last) .. ".")
			end
			if timerDisplay then
				timerDisplay:Refresh()
				C_Timer.After(4.1, function() timerDisplay:Refresh() end)
			end
		end,
	},
	enable = function()
		TimerDisplay()
		if InCombatNow() and not timer.start then StartTimer() end
	end,
	disable = function()
		StopTimer()
		timer.stop = nil
	end,
})

------------------------------------------------------------------------------
-- Combat alert: "+ Combat" / "- Combat"
------------------------------------------------------------------------------

local alertDisplay

local function AlertDisplay()
	alertDisplay = alertDisplay or Q:Display("combatAlert", {
		label = "Combat alert", feature = "combatAlert", sizeKey = "combatAlertSize",
		x = 0, y = 260, minSize = 12, maxSize = 64, ratio = 1.4,
		build = function(d)
			Q.TextDisplay(d)
			AddFade(d)
		end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(math_floor(size * 6), math_floor(size * 1.4))
		end,
		sample = function(d)
			d.fade:Stop()
			d.frame:SetAlpha(1)
			d.text:SetTextColor(1, 0.35, 0.3)
			d.text:SetText("+ Combat")
		end,
		paint = function(d)
			if not d.playing then d.frame:Hide() end
		end,
	})
	return alertDisplay
end

Q:Feature({
	key = "combatAlert",
	events = {
		PLAYER_REGEN_DISABLED = function() Flash(alertDisplay, "+ Combat", 1, 0.35, 0.3) end,
		PLAYER_REGEN_ENABLED = function() Flash(alertDisplay, "- Combat", 0.35, 1, 0.45) end,
	},
	enable = function() AlertDisplay() end,
})

------------------------------------------------------------------------------
-- Low durability warning (out of combat)
------------------------------------------------------------------------------

local durabilityDisplay

local function LowestDurability()
	local lowest
	for slot = 1, 18 do
		local current, maximum = GetInventoryItemDurability(slot)
		if current and maximum and not Q.IsSecret(current) and not Q.IsSecret(maximum) and maximum > 0 then
			local pct = current / maximum
			if not lowest or pct < lowest then lowest = pct end
		end
	end
	return lowest
end

local function DurabilityDisplay()
	durabilityDisplay = durabilityDisplay or Q:Display("durability", {
		label = "Durability warning", feature = "durability", sizeKey = "durabilitySize",
		x = 0, y = 150, minSize = 10, maxSize = 48, ratio = 1.4,
		build = function(d) Q.TextDisplay(d) end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(math_floor(size * 12), math_floor(size * 1.4))
		end,
		sample = function(d)
			d.text:SetTextColor(1, 0.3, 0.25)
			d.text:SetText("Low durability: 18%")
		end,
		paint = function(d)
			if inCombat then
				d.frame:Hide()
				return
			end
			local lowest = LowestDurability()
			local threshold = DB().durabilityThreshold or 25
			if lowest and lowest * 100 < threshold then
				d.text:SetTextColor(1, 0.3, 0.25)
				d.text:SetText(string_format("Low durability: %d%%", math_floor(lowest * 100)))
				d.frame:Show()
			else
				d.frame:Hide()
			end
		end,
	})
	return durabilityDisplay
end

local function RefreshDurability()
	if durabilityDisplay then durabilityDisplay:Refresh() end
end

Q:Feature({
	key = "durability",
	events = {
		UPDATE_INVENTORY_DURABILITY = RefreshDurability,
		PLAYER_ENTERING_WORLD = RefreshDurability,
		PLAYER_REGEN_DISABLED = function()
			inCombat = true
			RefreshDurability()
		end,
		PLAYER_REGEN_ENABLED = function()
			inCombat = false
			RefreshDurability()
		end,
	},
	enable = function()
		inCombat = InCombatNow()
		DurabilityDisplay()
	end,
})

------------------------------------------------------------------------------
-- FPS and latency
------------------------------------------------------------------------------

local fpsDisplay, fpsTicker

local function FpsColor(fps)
	if fps >= 60 then return "4fe08a" end
	if fps >= 30 then return "ffd34d" end
	return "ff5a4f"
end

local function FpsTick()
	if not fpsDisplay or not fpsDisplay.frame:IsShown() then return end
	local fps = math_floor((GetFramerate() or 0) + 0.5)
	local _, _, home, world = GetNetStats()
	fpsDisplay.text:SetFormattedText("|cff%s%d|r fps   %d ms", FpsColor(fps), fps, world or home or 0)
end

local function FpsDisplay()
	fpsDisplay = fpsDisplay or Q:Display("fps", {
		label = "FPS and latency", feature = "fps", sizeKey = "fpsSize",
		x = 0, y = 520, minSize = 8, maxSize = 32, ratio = 1.5,
		build = function(d) Q.TextDisplay(d) end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(math_floor(size * 9), math_floor(size * 1.5))
		end,
		sample = function(d) d.text:SetText("|cff4fe08a120|r fps   34 ms") end,
		paint = function(d)
			d.frame:Show()
			FpsTick()
		end,
	})
	return fpsDisplay
end

Q:Feature({
	key = "fps",
	enable = function()
		FpsDisplay()
		if fpsTicker then fpsTicker:Cancel() end
		fpsTicker = C_Timer.NewTicker(1, FpsTick)
	end,
	disable = function()
		if fpsTicker then
			fpsTicker:Cancel()
			fpsTicker = nil
		end
	end,
})

------------------------------------------------------------------------------
-- Secondary stats. These are secret in restricted content, so they only go
-- through string formatting (no math, no comparisons while secret).
------------------------------------------------------------------------------

local statsDisplay, statsTicker
local INTELLECT = LE_UNIT_STAT_INTELLECT or 4
local STATS_FORMAT = "|cffffd34dCrit|r  %.1f%%\n|cff4fe08aHaste|r  %.1f%%\n|cff63b3ffMastery|r  %.1f%%\n|cffc78bffVers|r  %.1f%%"

local function CritChance()
	local index = GetSpecialization and GetSpecialization()
	local primary = index and select(6, GetSpecializationInfo(index))
	if primary == INTELLECT and GetSpellCritChance then return GetSpellCritChance(2) end
	local _, class = UnitClass("player")
	if class == "HUNTER" and GetRangedCritChance then return GetRangedCritChance() end
	return GetCritChance and GetCritChance()
end

local function Versatility()
	local rating = CR_VERSATILITY_DAMAGE_DONE
	if not rating or not GetCombatRatingBonus then return 0 end
	local fromRating = GetCombatRatingBonus(rating)
	local bonus = GetVersatilityBonus and GetVersatilityBonus(rating)
	if fromRating == nil then return 0 end
	if bonus == nil or Q.IsSecret(fromRating) or Q.IsSecret(bonus) then return fromRating end
	return fromRating + bonus
end

local function StatsTick()
	if not statsDisplay or not statsDisplay.frame:IsShown() then return end
	local crit = CritChance() or 0
	local haste = GetHaste and GetHaste() or 0
	local mastery = GetMasteryEffect and GetMasteryEffect() or 0
	statsDisplay.text:SetFormattedText(STATS_FORMAT, crit, haste, mastery, Versatility())
end

local function StatsDisplay()
	statsDisplay = statsDisplay or Q:Display("stats", {
		label = "Secondary stats", feature = "stats", sizeKey = "statsSize",
		x = -560, y = -300, minSize = 8, maxSize = 32, ratio = 5.6,
		build = function(d)
			local text = Q.TextDisplay(d, "LEFT")
			text:ClearAllPoints()
			text:SetPoint("TOPLEFT", 4, -2)
			text:SetSpacing(2)
		end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(math_floor(size * 9), math_floor(size * 5.6))
		end,
		sample = function(d) d.text:SetFormattedText(STATS_FORMAT, 24.3, 18.1, 52.6, 9.4) end,
		paint = function(d)
			d.frame:Show()
			StatsTick()
		end,
	})
	return statsDisplay
end

Q:Feature({
	key = "stats",
	enable = function()
		StatsDisplay()
		if statsTicker then statsTicker:Cancel() end
		statsTicker = C_Timer.NewTicker(1, StatsTick)
	end,
	disable = function()
		if statsTicker then
			statsTicker:Cancel()
			statsTicker = nil
		end
	end,
})

------------------------------------------------------------------------------
-- Group death alert: "<name> died" in their class color.
------------------------------------------------------------------------------

local GROUP_UNITS = { "player" }
for i = 1, 4 do GROUP_UNITS[#GROUP_UNITS + 1] = "party" .. i end
for i = 1, 40 do GROUP_UNITS[#GROUP_UNITS + 1] = "raid" .. i end

local deathDisplay
local dead = {} -- unit token -> true / false

local function DeadNow(unit)
	local isDead = UnitIsDeadOrGhost(unit)
	if Q.IsSecret(isDead) then return nil end
	if not isDead then return false end
	if UnitIsFeignDeath then
		local feign = UnitIsFeignDeath(unit)
		if Q.IsSecret(feign) then return nil end
		if feign then return false end
	end
	return true
end

local function Snapshot()
	wipe(dead)
	for i = 1, #GROUP_UNITS do
		local unit = GROUP_UNITS[i]
		if UnitExists(unit) then
			local state = DeadNow(unit)
			if state ~= nil then dead[unit] = state end
		end
	end
end

local function DeathDisplay()
	deathDisplay = deathDisplay or Q:Display("deathAlert", {
		label = "Group death alert", feature = "deathAlert", sizeKey = "deathAlertSize",
		x = 0, y = 230, minSize = 12, maxSize = 56, ratio = 1.4,
		build = function(d)
			Q.TextDisplay(d)
			AddFade(d, 2)
		end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(math_floor(size * 12), math_floor(size * 1.4))
		end,
		sample = function(d)
			d.fade:Stop()
			d.frame:SetAlpha(1)
			d.text:SetTextColor(0.96, 0.55, 0.73)
			d.text:SetText("Capcasey died")
		end,
		paint = function(d)
			if not d.playing then d.frame:Hide() end
		end,
	})
	return deathDisplay
end

Q:Feature({
	key = "deathAlert",
	unitEvents = { UNIT_HEALTH = GROUP_UNITS },
	events = {
		UNIT_HEALTH = function(_, unit)
			if type(unit) ~= "string" then return end
			local now = DeadNow(unit)
			if now == nil then return end
			local was = dead[unit]
			dead[unit] = now
			if not (now and was == false) then return end
			local display = deathDisplay
			if not display then return end
			Flash(display, "", 1, 1, 1)
			local name = UnitName(unit)
			display.text:SetFormattedText("%s died", name or "?")
			local _, classFile = UnitClass(unit)
			local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
			if color then display.text:SetTextColor(color:GetRGB()) end
			if DB().deathAlertSound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
				PlaySound(SOUNDKIT.RAID_WARNING, "Master")
			end
		end,
		GROUP_ROSTER_UPDATE = function() Snapshot() end,
		PLAYER_ENTERING_WORLD = function() Snapshot() end,
	},
	enable = function()
		DeathDisplay()
		Snapshot()
	end,
})
