if SoulUI_Blocked or not SoulUI then return end

-- Pull timer, world-marker buttons, a ready-check buff count, and your keystone.

local Soul = SoulUI
local UI = Soul.UI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local floor, pcall, type = math.floor, pcall, type

local UNITS = { "player" }
for i = 1, 4 do UNITS[#UNITS + 1] = "party" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end

------------------------------------------------------------------------------
-- Pull timer. /soulpull 10  counts down and says it in party or raid chat.
------------------------------------------------------------------------------

local pull
local pullEnds
local pullRun = 0 -- a new /soulpull stops the previous countdown loop

local function PullDisplay()
	pull = pull or Q:Display("pull", {
		label = "Pull timer", feature = "pullTimer", sizeKey = "pullSize", defaultSize = 24,
		x = 0, y = 180, minSize = 14, maxSize = 48, ratio = 1.2,
		build = function(d) Q.TextDisplay(d) end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(floor(size * 8), floor(size * 1.4))
		end,
		sample = function(d)
			d.text:SetTextColor(1, 0.85, 0.4)
			d.text:SetText("Pull 10")
		end,
		paint = function(d)
			if not pullEnds or pullEnds <= GetTime() then d.frame:Hide() end
		end,
	})
	return pull
end

local function PullTick(run)
	local d = pull
	if not d or not pullEnds or run ~= pullRun then return end
	if not Q.on.pullTimer then
		pullEnds = nil
		d.frame:Hide()
		return
	end
	local left = pullEnds - GetTime()
	if left <= 0 then
		pullEnds = nil
		d.frame:Hide()
		if IsInGroup() then Q.SendGroup("Pull") end
		return
	end
	d.text:SetTextColor(1, 0.85, 0.4)
	d.text:SetFormattedText("Pull %.0f", left)
	d.frame:Show()
	C_Timer.After(0.1, function() PullTick(run) end)
end

local function StartPull(seconds)
	if not DB().pullTimer then
		Soul:Print("Turn on the pull timer under Quality of Life.")
		return
	end
	seconds = floor(tonumber(seconds) or 10)
	if seconds < 1 then seconds = 1 end
	if seconds > 30 then seconds = 30 end
	PullDisplay()
	pullEnds = GetTime() + seconds
	if IsInGroup() then Q.SendGroup("Pulling in " .. seconds) end
	pullRun = pullRun + 1
	PullTick(pullRun)
end

SLASH_SOULPULL1 = "/soulpull"
SlashCmdList.SOULPULL = function(msg) StartPull(msg) end

Q:Feature({
	key = "pullTimer",
	enable = function() PullDisplay() end,
})

------------------------------------------------------------------------------
-- World markers. Attributes are set once, out of combat, so the clicks
-- still work after a pull.
------------------------------------------------------------------------------

local markers

-- /wm numbers world markers in their own order. Each one is drawn with the
-- raid target icon of the same shape: 1 square, 2 triangle, 3 diamond,
-- 4 cross, 5 star, 6 circle, 7 moon, 8 skull.
local MARKER_ICON = { 6, 4, 3, 7, 1, 2, 5, 8 }
local MARKER_BAR_W, MARKER_BAR_H = 8 * 26 + 22, 26

local function MarkerBar()
	if markers then return markers end
	if InCombatLockdown() then return nil end
	local bar = CreateFrame("Frame", "SoulUIRaidMarkers", UIParent)
	bar:SetSize(MARKER_BAR_W, MARKER_BAR_H)
	bar:Hide()
	for i = 1, 8 do
		local b = CreateFrame("Button", "SoulUIWorldMarker" .. i, bar, "SecureActionButtonTemplate")
		b:SetSize(22, 22)
		b:SetPoint("LEFT", (i - 1) * 26, 0)
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", "/wm " .. i)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. MARKER_ICON[i])
		-- Secure buttons act on the down or the up press depending on the
		-- ActionButtonUseKeyDown setting; registering both covers either.
		b:RegisterForClicks("AnyUp", "AnyDown")
	end
	local clear = CreateFrame("Button", "SoulUIWorldMarkerClear", bar, "SecureActionButtonTemplate")
	clear:SetSize(22, 22)
	clear:SetPoint("LEFT", 8 * 26, 0)
	clear:SetAttribute("type", "macro")
	clear:SetAttribute("macrotext", "/cwm all")
	clear:RegisterForClicks("AnyUp", "AnyDown")
	local x = clear:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(x, 12)
	x:SetAllPoints()
	x:SetText("x")
	markers = Q:Display("markers", {
		label = "Raid markers", feature = "raidMarkers",
		x = 0, y = -220,
		build = function(d)
			bar:SetParent(d.frame)
			bar:ClearAllPoints()
			bar:SetPoint("CENTER")
			bar:Show()
			d.bar = bar
		end,
		-- Fixed size (no size setting): the mover matches the buttons.
		layout = function(d)
			d.frame:SetSize(MARKER_BAR_W, MARKER_BAR_H)
		end,
		sample = function(d) d.frame:Show() end,
		paint = function(d) d.frame:Show() end,
	})
	return markers
end

Q:Feature({
	key = "raidMarkers",
	enable = function()
		-- RunAfterCombat runs it now when out of combat.
		Soul:RunAfterCombat("qol:markers", function()
			MarkerBar()
			if markers then markers:Refresh() end
		end)
	end,
})

------------------------------------------------------------------------------
-- Ready check: how many helpful auras each person is showing.
-- A secret aura means the count is hidden instead of guessed.
------------------------------------------------------------------------------

local buffFrame

-- Counts helpful auras on a unit. Returns nil when the game hides them:
-- since 12.1 the index lookup raises an error while auras are restricted,
-- and an aura record can be secret, so both end in "hidden".
local function CountBuffs(unit)
	local count = 0
	for index = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
		if not aura then break end
		if Q.IsSecret(aura) or Q.IsSecret(aura.spellId) then return nil end
		count = count + 1
	end
	return count
end

local function BuffLines()
	local lines = {}
	-- In a raid the party tokens and "player" repeat raid members.
	local raid = IsInRaid()
	for i = 1, #UNITS do
		local unit = UNITS[i]
		local listed = (unit:sub(1, 4) == "raid") == raid
		if listed and UnitExists(unit) then
			local name = UnitName(unit)
			if Q.IsSecret(name) or type(name) ~= "string" then name = unit end
			local count, hidden = 0, false
			if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
				local ok, result = pcall(CountBuffs, unit)
				if ok and type(result) == "number" then
					count = result
				else
					hidden = true
				end
			end
			if hidden then
				lines[#lines + 1] = name .. "  buffs hidden"
			else
				lines[#lines + 1] = name .. "  " .. count .. " buffs"
			end
		end
	end
	return table.concat(lines, "\n")
end

local function ShowBuffs()
	if not buffFrame then
		buffFrame = CreateFrame("Frame", "SoulUIBuffCheck", UIParent)
		buffFrame:SetFrameStrata("DIALOG")
		buffFrame:SetSize(260, 280)
		buffFrame:SetPoint("CENTER", 280, 0)
		buffFrame:EnableMouse(true)
		UI.Fill(buffFrame, { 0.06, 0.06, 0.07, 0.96 })
		local title = buffFrame:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(title, 15)
		title:SetPoint("TOPLEFT", 12, -10)
		title:SetText("Buff check")
		buffFrame.body = buffFrame:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(buffFrame.body, 12)
		buffFrame.body:SetPoint("TOPLEFT", 12, -34)
		buffFrame.body:SetPoint("BOTTOMRIGHT", -12, 12)
		buffFrame.body:SetJustifyH("LEFT")
		buffFrame.body:SetJustifyV("TOP")
		local close = CreateFrame("Button", nil, buffFrame)
		close:SetSize(20, 20)
		close:SetPoint("TOPRIGHT", -6, -6)
		close:SetScript("OnClick", function() buffFrame:Hide() end)
		local x = close:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(x, 13)
		x:SetAllPoints()
		x:SetText("x")
		buffFrame:Hide()
	end
	buffFrame.body:SetText(BuffLines())
	buffFrame:Show()
end

Q:Feature({
	key = "buffCheck",
	events = {
		READY_CHECK = function() ShowBuffs() end,
	},
})

------------------------------------------------------------------------------
-- Your keystone. Other people's keys are not on a public API, so this
-- window is yours, and it can say the name and level in party chat.
------------------------------------------------------------------------------

local keyFrame

local function KeyText()
	if not (C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID) then
		return "Keystone data is not available."
	end
	local map = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
	local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
	if Q.IsSecret(map) or Q.IsSecret(level) or type(map) ~= "number" then
		return "No keystone in your bags."
	end
	local name = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(map)
	if Q.IsSecret(name) or type(name) ~= "string" then name = "Keystone" end
	if type(level) ~= "number" then level = 0 end
	return name .. "  +" .. level
end

local function ShowKeys()
	if not keyFrame then
		keyFrame = CreateFrame("Frame", "SoulUIKeys", UIParent)
		keyFrame:SetFrameStrata("DIALOG")
		keyFrame:SetSize(280, 120)
		keyFrame:SetPoint("CENTER", 0, 80)
		keyFrame:EnableMouse(true)
		UI.Fill(keyFrame, { 0.06, 0.06, 0.07, 0.96 })
		keyFrame.body = keyFrame:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(keyFrame.body, 16)
		keyFrame.body:SetPoint("TOPLEFT", 14, -16)
		keyFrame.body:SetPoint("TOPRIGHT", -14, -16)
		keyFrame.body:SetJustifyH("LEFT")
		local say = CreateFrame("Button", nil, keyFrame)
		say:SetSize(120, 24)
		say:SetPoint("BOTTOMLEFT", 14, 14)
		UI.Fill(say, { 1, 1, 1, 0.08 })
		local label = say:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(label, 12)
		label:SetAllPoints()
		label:SetText("Say in party")
		say:SetScript("OnClick", function()
			if IsInGroup() then Q.SendGroup(KeyText()) else Soul:Print(KeyText()) end
		end)
		local close = CreateFrame("Button", nil, keyFrame)
		close:SetSize(20, 20)
		close:SetPoint("TOPRIGHT", -6, -6)
		close:SetScript("OnClick", function() keyFrame:Hide() end)
		local x = close:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(x, 13)
		x:SetAllPoints()
		x:SetText("x")
		keyFrame:Hide()
	end
	keyFrame.body:SetText(KeyText())
	keyFrame:Show()
end

SLASH_SOULKEYS1 = "/soulkeys"
SlashCmdList.SOULKEYS = function()
	if not DB().partyKeys then
		Soul:Print("Turn on Party keystone under Quality of Life.")
		return
	end
	ShowKeys()
end

Q:Feature({
	key = "partyKeys",
	enable = function() end,
})
