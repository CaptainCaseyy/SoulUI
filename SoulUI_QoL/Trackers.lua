if SoulUI_Blocked or not SoulUI then return end

-- Icon trackers (battle res charges, Sated / Exhaustion lockout), the
-- crosshair, the cursor ring, item levels on the character sheet and
-- coordinates on the world map.

local Soul = SoulUI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local C_Timer = C_Timer
local math_floor, string_format, type, ipairs, pcall = math.floor, string.format, type, ipairs, pcall
local UnitAffectingCombat, InCombatLockdown = UnitAffectingCombat, InCombatLockdown

local REBIRTH = 20484 -- the shared raid / keystone battle res pool reads through Rebirth
local RING = "Interface\\AddOns\\SoulUI\\Media\\Textures\\Ring.tga"

local combat = false
local function InCombatNow()
	local value = UnitAffectingCombat("player")
	if Q.IsSecret(value) then return InCombatLockdown() end
	return value and true or InCombatLockdown()
end

-- Square icon with a 1px border, a cooldown swipe and a count.
local function BuildIcon(d)
	local frame = d.frame
	local border = frame:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 1)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	d.icon = icon
	local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	cd:SetPoint("TOPLEFT", 1, -1)
	cd:SetPoint("BOTTOMRIGHT", -1, 1)
	cd:SetDrawEdge(false)
	cd:SetHideCountdownNumbers(false)
	d.cd = cd
	local over = CreateFrame("Frame", nil, frame)
	over:SetAllPoints()
	over:SetFrameLevel(cd:GetFrameLevel() + 2)
	local count = over:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(count, 14)
	count:SetPoint("BOTTOMRIGHT", -2, 2)
	d.count = count
end

local function LayoutIcon(d, size)
	d.frame:SetSize(size, size)
	Soul:ApplyFont(d.count, math.max(9, math_floor(size * 0.42)))
end

local function SpellIcon(spellID)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
	return 136243
end

------------------------------------------------------------------------------
-- Battle res charges (keystones and boss encounters)
------------------------------------------------------------------------------

local brezDisplay

local function BrezActive()
	local inInstance, kind = IsInInstance()
	if not inInstance or (kind ~= "party" and kind ~= "raid") then return false end
	if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then return true end
	if IsEncounterInProgress and IsEncounterInProgress() then return true end
	return false
end

local function BrezDisplay()
	brezDisplay = brezDisplay or Q:Display("brez", {
		label = "Battle res charges", feature = "brez", sizeKey = "brezSize",
		x = -260, y = 160, minSize = 20, maxSize = 96, ratio = 1,
		build = BuildIcon,
		layout = LayoutIcon,
		sample = function(d)
			d.icon:SetTexture(SpellIcon(REBIRTH))
			d.count:SetText("2")
			d.cd:Clear()
		end,
		paint = function(d)
			local charges = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(REBIRTH)
			if not charges or not BrezActive() then
				d.frame:Hide()
				return
			end
			d.icon:SetTexture(SpellIcon(REBIRTH))
			-- currentCharges can be secret during an encounter: format only.
			d.count:SetFormattedText("%d", charges.currentCharges or 0)
			local duration = C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(REBIRTH)
			if duration then
				d.cd:SetCooldownFromDurationObject(duration)
			else
				d.cd:Clear()
			end
			d.frame:Show()
		end,
	})
	return brezDisplay
end

local function RefreshBrez()
	if brezDisplay then brezDisplay:Refresh() end
end

Q:Feature({
	key = "brez",
	events = {
		SPELL_UPDATE_CHARGES = RefreshBrez,
		ENCOUNTER_START = function() C_Timer.After(0.2, RefreshBrez) end,
		ENCOUNTER_END = RefreshBrez,
		CHALLENGE_MODE_START = function() C_Timer.After(0.5, RefreshBrez) end,
		CHALLENGE_MODE_COMPLETED = RefreshBrez,
		PLAYER_ENTERING_WORLD = RefreshBrez,
		ZONE_CHANGED_NEW_AREA = RefreshBrez,
	},
	enable = function() BrezDisplay() end,
})

------------------------------------------------------------------------------
-- Sated / Exhaustion lockout. These debuffs are on the never-secret list,
-- so the lookup by spell ID keeps working in combat.
------------------------------------------------------------------------------

local SATED = {
	57724, -- Sated
	57723, -- Exhaustion
	80354, -- Temporal Displacement
	95809, -- Insanity
	160455, -- Fatigued (pet)
	264689, -- Fatigued
	390435, -- Exhaustion (Evoker)
}

local satedDisplay
local satedPending = false

local function FindSated()
	local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if not get then return nil end
	for _, spellID in ipairs(SATED) do
		local ok, aura = pcall(get, spellID)
		if ok and aura then return aura, spellID end
	end
	return nil
end

local function SatedDisplay()
	satedDisplay = satedDisplay or Q:Display("sated", {
		label = "Sated lockout", feature = "sated", sizeKey = "satedSize",
		x = -210, y = 160, minSize = 20, maxSize = 96, ratio = 1,
		build = BuildIcon,
		layout = LayoutIcon,
		sample = function(d)
			d.icon:SetTexture(SpellIcon(57724))
			d.count:SetText("")
			d.cd:Clear()
		end,
		paint = function(d)
			local aura, spellID = FindSated()
			if not aura then
				d.frame:Hide()
				return
			end
			d.icon:SetTexture(aura.icon or SpellIcon(spellID))
			d.count:SetText("")
			local expires, duration = aura.expirationTime, aura.duration
			if expires and duration and not Q.IsSecret(expires) and not Q.IsSecret(duration)
				and expires > 0 and duration > 0 and C_DurationUtil and C_DurationUtil.CreateDuration then
				d.timer = d.timer or C_DurationUtil.CreateDuration()
				d.timer:SetTimeFromEnd(expires, duration)
				d.cd:SetCooldownFromDurationObject(d.timer)
			else
				d.cd:Clear()
			end
			d.frame:Show()
		end,
	})
	return satedDisplay
end

local function RefreshSated()
	satedPending = false
	if satedDisplay then satedDisplay:Refresh() end
end

Q:Feature({
	key = "sated",
	unitEvents = { UNIT_AURA = { "player" } },
	events = {
		-- The payload can be secret; it is never read. One check per frame.
		UNIT_AURA = function()
			if satedPending then return end
			satedPending = true
			C_Timer.After(0, RefreshSated)
		end,
		PLAYER_ENTERING_WORLD = RefreshSated,
	},
	enable = function() SatedDisplay() end,
})

------------------------------------------------------------------------------
-- Crosshair at the screen center (movable).
------------------------------------------------------------------------------

local crossDisplay

local function CrossDisplay()
	crossDisplay = crossDisplay or Q:Display("crosshair", {
		label = "Crosshair", feature = "crosshair", sizeKey = "crosshairSize",
		x = 0, y = 0, minSize = 8, maxSize = 128, ratio = 1, strata = "LOW",
		build = function(d)
			local frame = d.frame
			frame:EnableMouse(false)
			d.hBack = frame:CreateTexture(nil, "BACKGROUND")
			d.vBack = frame:CreateTexture(nil, "BACKGROUND")
			d.h = frame:CreateTexture(nil, "ARTWORK")
			d.v = frame:CreateTexture(nil, "ARTWORK")
			for _, tex in ipairs({ d.hBack, d.vBack, d.h, d.v }) do tex:SetPoint("CENTER") end
			d.hBack:SetColorTexture(0, 0, 0, 0.8)
			d.vBack:SetColorTexture(0, 0, 0, 0.8)
		end,
		layout = function(d, size)
			d.frame:SetSize(size, size)
			d.h:SetSize(size, 2)
			d.v:SetSize(2, size)
			d.hBack:SetSize(size + 2, 4)
			d.vBack:SetSize(4, size + 2)
			local c = DB().crosshairColor or { 1, 1, 1 }
			d.h:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
			d.v:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
		end,
		sample = function() end,
		paint = function(d)
			d.frame:SetShown(not DB().crosshairCombat or combat)
		end,
	})
	return crossDisplay
end

local function RefreshCross()
	if crossDisplay then crossDisplay:Refresh() end
end

Q:Feature({
	key = "crosshair",
	events = {
		PLAYER_REGEN_DISABLED = function()
			combat = true
			RefreshCross()
		end,
		PLAYER_REGEN_ENABLED = function()
			combat = false
			RefreshCross()
		end,
	},
	enable = function()
		combat = InCombatNow()
		CrossDisplay()
	end,
})

------------------------------------------------------------------------------
-- Cursor ring: an accent ring that follows the mouse. Its OnUpdate only
-- runs while the ring is shown.
------------------------------------------------------------------------------

local ring
local ringCombat = false

local function BuildRing()
	if ring then return ring end
	ring = CreateFrame("Frame", nil, UIParent)
	ring:SetFrameStrata("TOOLTIP")
	ring:EnableMouse(false)
	ring:Hide()
	local texture = ring:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	texture:SetTexture(RING)
	ring.texture = texture
	ring:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		if not scale or scale <= 0 then scale = 1 end
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	end)
	return ring
end

local function PaintRing()
	if not ring then return end
	local db = DB()
	if not Q.on.cursorRing or (db.cursorRingCombat and not ringCombat) then
		ring:Hide()
		return
	end
	local size = db.cursorRingSize or 48
	ring:SetSize(size, size)
	local r, g, b = Soul:Accent()
	ring.texture:SetVertexColor(r, g, b, 0.9)
	ring:Show()
end

Q:Feature({
	key = "cursorRing",
	events = {
		PLAYER_REGEN_DISABLED = function()
			ringCombat = true
			PaintRing()
		end,
		PLAYER_REGEN_ENABLED = function()
			ringCombat = false
			PaintRing()
		end,
	},
	enable = function()
		ringCombat = InCombatNow()
		BuildRing()
	end,
	refresh = PaintRing,
	disable = PaintRing,
})

Soul:On("ThemeChanged", PaintRing)

------------------------------------------------------------------------------
-- Item level on the character sheet slots.
------------------------------------------------------------------------------

local SLOT_BUTTONS = {
	"CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
	"CharacterChestSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
	"CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
	"CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
}
local SKIP_SLOT = { [4] = true, [19] = true } -- shirt, tabard

local levelLabels = {} -- slot button -> font string (side table, nothing written on the button)
local levelHooked = false

local function UpdateSlot(button)
	if not button or not button.GetID then return end
	local label = levelLabels[button]
	local slot = button:GetID()
	local show = Q.on.charIlvl and type(slot) == "number" and slot >= 1 and slot <= 17 and not SKIP_SLOT[slot]
	local level, quality
	if show and ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
		local location = ItemLocation:CreateFromEquipmentSlot(slot)
		if location and C_Item.DoesItemExist(location) then
			level = C_Item.GetCurrentItemLevel(location)
			quality = C_Item.GetItemQuality and C_Item.GetItemQuality(location)
		end
	end
	if not level or Q.IsSecret(level) or level <= 1 then
		if label then label:Hide() end
		return
	end
	if not label then
		label = button:CreateFontString(nil, "OVERLAY")
		Soul:ApplyFont(label, 12)
		label:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
		levelLabels[button] = label
	end
	local r, g, b = 1, 1, 1
	if quality and C_Item.GetItemQualityColor then
		local qr, qg, qb = C_Item.GetItemQualityColor(quality)
		if qr then r, g, b = qr, qg, qb end
	end
	label:SetTextColor(r, g, b)
	label:SetText(level)
	label:Show()
end

local function UpdateAllSlots()
	for _, name in ipairs(SLOT_BUTTONS) do
		local button = _G[name]
		if button then UpdateSlot(button) end
	end
end

Q:Feature({
	key = "charIlvl",
	events = {
		PLAYER_EQUIPMENT_CHANGED = function() C_Timer.After(0.2, UpdateAllSlots) end,
	},
	enable = function()
		if not levelHooked and PaperDollItemSlotButton_Update then
			levelHooked = true
			hooksecurefunc("PaperDollItemSlotButton_Update", UpdateSlot)
		end
		UpdateAllSlots()
	end,
	disable = UpdateAllSlots,
})

------------------------------------------------------------------------------
-- Player and cursor coordinates at the bottom of the world map.
------------------------------------------------------------------------------

local coords

local function CoordText(x, y)
	if not x or not y or Q.IsSecret(x) or Q.IsSecret(y) then return "--" end
	if x <= 0 and y <= 0 then return "--" end
	return string_format("%.1f, %.1f", x * 100, y * 100)
end

local function UpdateCoords()
	local map = WorldMapFrame
	if not coords or not map then return end
	local player = "--"
	local mapID = map.GetMapID and map:GetMapID()
	if mapID and C_Map and C_Map.GetPlayerMapPosition then
		local position = C_Map.GetPlayerMapPosition(mapID, "player")
		if position and position.GetXY then player = CoordText(position:GetXY()) end
	end
	local cursor = "--"
	local scroll = map.ScrollContainer
	if scroll and scroll.GetNormalizedCursorPosition and scroll:IsMouseOver() then
		local x, y = scroll:GetNormalizedCursorPosition()
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then cursor = CoordText(x, y) end
	end
	coords.text:SetText("Player  " .. player .. "      Cursor  " .. cursor)
end

local function BuildCoords()
	local map = WorldMapFrame
	if coords or not map then return end
	local anchor = map.ScrollContainer or map
	coords = CreateFrame("Frame", nil, map)
	coords:SetSize(320, 22)
	coords:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 4)
	coords:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
	coords:EnableMouse(false)
	local bg = coords:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.55)
	local text = coords:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(text, 12)
	text:SetPoint("CENTER")
	coords.text = text
	local elapsed = 0
	coords:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then return end
		elapsed = 0
		UpdateCoords()
	end)
	coords:SetShown(Q.on.mapCoords and true or false)
end

Q:Feature({
	key = "mapCoords",
	enable = function()
		if WorldMapFrame then
			BuildCoords()
		else
			Q.WhenLoaded("Blizzard_WorldMap", BuildCoords)
		end
		if coords then coords:Show() end
	end,
	disable = function()
		if coords then coords:Hide() end
	end,
})
