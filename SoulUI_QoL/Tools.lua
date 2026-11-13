if SoulUI_Blocked or not SoulUI then return end

-- Shift-drag for a few Blizzard windows, /way pins, a chat cover, target
-- distance, rested, healthstone ready, unspent talents, floating combat text
-- font, a movement cooldown, a cursor trail and a GCD ring.

local Soul = SoulUI
local UI = Soul.UI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local floor, sqrt = math.floor, math.sqrt
local type, pcall = type, pcall

------------------------------------------------------------------------------
-- Shift-drag windows. Blizzard places these panels itself each time one
-- opens, so the saved spot is put back after it shows and after the panel
-- layout runs. Nothing is written into Blizzard's frames: the "hooked" marks
-- live in a local table.
------------------------------------------------------------------------------

-- window -> the Blizzard addon that creates it (false: part of the base UI).
-- WhenLoaded runs at once for an addon that is already loaded.
local SHIFT = {
	CharacterFrame = false,
	PlayerSpellsFrame = "Blizzard_PlayerSpells",
	ProfessionsFrame = "Blizzard_Professions",
	WorldMapFrame = "Blizzard_WorldMap",
	PVEFrame = "Blizzard_GroupFinder",
	FriendsFrame = false,
	CommunitiesFrame = "Blizzard_Communities",
}

local shiftHooked = {}
local panelHooked = false

local function Positions()
	local db = DB()
	if type(db.shifterPos) ~= "table" then db.shifterPos = {} end
	return db.shifterPos
end

local function ApplyShifted(frame, name)
	if not Q.on.shifter or InCombatLockdown() then return end
	if frame.IsProtected and frame:IsProtected() then return end
	local pos = Positions()[name]
	if type(pos) ~= "table" then return end
	frame:ClearAllPoints()
	frame:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
end

local function ApplyAllShown()
	for name, frame in pairs(shiftHooked) do
		if frame:IsShown() then ApplyShifted(frame, name) end
	end
end

local function HookShift(name)
	local frame = _G[name]
	if not frame or shiftHooked[name] or not frame.HookScript then return end
	shiftHooked[name] = frame
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:HookScript("OnDragStart", function(self)
		if Q.on.shifter and IsShiftKeyDown() and not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	frame:HookScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if not Q.on.shifter then return end
		local point, _, rel, x, y = self:GetPoint(1)
		if point then Positions()[name] = { point = point, rel = rel, x = x, y = y } end
	end)
	frame:HookScript("OnShow", function(self)
		ApplyShifted(self, name)
		-- The panel manager places the window after OnShow; put it back next frame.
		C_Timer.After(0, function() if self:IsShown() then ApplyShifted(self, name) end end)
	end)
end

Q:Feature({
	key = "shifter",
	enable = function()
		for name, addon in pairs(SHIFT) do
			if _G[name] or not addon then
				HookShift(name)
			else
				Q.WhenLoaded(addon, function() HookShift(name) end)
			end
		end
		if not panelHooked and UpdateUIPanelPositions then
			panelHooked = true
			hooksecurefunc("UpdateUIPanelPositions", ApplyAllShown)
		end
		ApplyAllShown()
	end,
})

------------------------------------------------------------------------------
-- /way x y: a map pin on the current zone.
------------------------------------------------------------------------------

local function PlaceWay(x, y)
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if type(map) ~= "number" or not C_Map.SetUserWaypoint or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then
		Soul:Print("This map cannot take a pin.")
		return
	end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then
		Soul:Print("This map cannot take a pin.")
		return
	end
	if x > 1 or y > 1 then
		x, y = x / 100, y / 100
	end
	if x < 0 or x > 1 or y < 0 or y > 1 then
		Soul:Print("Coordinates go from 0 to 100.")
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	Soul:Print(string.format("Pin set at %.1f, %.1f", x * 100, y * 100))
end

SLASH_SOULWAY1 = "/way"
SLASH_SOULWAY2 = "/soulway"
SlashCmdList.SOULWAY = function(msg)
	if not DB().waypoints then
		Soul:Print("Turn on map pins under Quality of Life.")
		return
	end
	local x, y = tostring(msg or ""):match("(%d+%.?%d*)[%s,]+(%d+%.?%d*)")
	if not x then
		Soul:Print("Usage: /way 45.2 67.8")
		return
	end
	PlaceWay(tonumber(x), tonumber(y))
end

Q:Feature({ key = "waypoints" })

------------------------------------------------------------------------------
-- Chat cover
------------------------------------------------------------------------------

local cover

Q:Feature({
	key = "chatCover",
	enable = function()
		local chat = ChatFrame1
		if not chat then return end
		if not cover then
			cover = CreateFrame("Button", nil, chat)
			cover:SetAllPoints()
			cover:SetFrameStrata("HIGH")
			UI.Fill(cover, { 0.04, 0.04, 0.05, 0.92 })
			local text = cover:CreateFontString(nil, "OVERLAY")
			Soul:ApplyFont(text, 12)
			text:SetPoint("CENTER")
			text:SetText("Chat covered")
			cover:SetScript("OnEnter", function(self) self:Hide() end)
			chat:HookScript("OnLeave", function()
				if Q.on.chatCover and not chat:IsMouseOver() then cover:Show() end
			end)
		end
		cover:Show()
	end,
	disable = function()
		if cover then cover:Hide() end
	end,
})

------------------------------------------------------------------------------
-- Target distance. The game only measures group members.
------------------------------------------------------------------------------

local distance, distanceTicker

local function DistanceDisplay()
	distance = distance or Q:Display("distance", {
		label = "Target distance", feature = "targetDistance", sizeKey = "distanceSize", defaultSize = 13,
		x = 0, y = -140, minSize = 10, maxSize = 28, ratio = 1.3,
		build = function(d) Q.TextDisplay(d) end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(floor(size * 6), floor(size * 1.3))
		end,
		sample = function(d) d.text:SetText("18 yd") end,
		paint = function(d) d.frame:Hide() end,
	})
	return distance
end

local function PaintDistance()
	local d = distance
	if not d or d.editing or not Q.on.targetDistance then return end
	if not UnitExists("target") or not UnitDistanceSquared then
		d.frame:Hide()
		return
	end
	local yards, checked = UnitDistanceSquared("target")
	-- checked is false (and the distance 0) for anyone outside the group.
	if Q.IsSecret(yards) or Q.IsSecret(checked) or type(yards) ~= "number" or checked ~= true then
		d.frame:Hide()
		return
	end
	d.text:SetText(floor(sqrt(yards) + 0.5) .. " yd")
	d.frame:Show()
end

Q:Feature({
	key = "targetDistance",
	events = {
		PLAYER_TARGET_CHANGED = PaintDistance,
	},
	enable = function()
		DistanceDisplay()
		if not distanceTicker then distanceTicker = C_Timer.NewTicker(0.2, PaintDistance) end
	end,
	disable = function()
		if distanceTicker then
			distanceTicker:Cancel()
			distanceTicker = nil
		end
	end,
})

------------------------------------------------------------------------------
-- Rested experience
------------------------------------------------------------------------------

local function RefreshRested()
	local d = Q:GetDisplay("rested")
	if d then d:Refresh() end
end

Q:Feature({
	key = "rested",
	events = {
		UPDATE_EXHAUSTION = RefreshRested,
		PLAYER_UPDATE_RESTING = RefreshRested,
		PLAYER_LEVEL_UP = RefreshRested,
		PLAYER_ENTERING_WORLD = RefreshRested,
	},
	enable = function()
		if Q:GetDisplay("rested") then return end
		Q:Display("rested", {
			label = "Rested", feature = "rested", sizeKey = "restedSize", defaultSize = 13,
			x = -200, y = 280, minSize = 10, maxSize = 24, ratio = 1.3,
			build = function(d) Q.TextDisplay(d) end,
			layout = function(d, size)
				Soul:ApplyFont(d.text, size)
				d.frame:SetSize(floor(size * 5), floor(size * 1.3))
			end,
			sample = function(d) d.text:SetText("Rested") end,
			paint = function(d)
				local amount = GetXPExhaustion and GetXPExhaustion()
				if type(amount) == "number" and not Q.IsSecret(amount) and amount > 0 then
					d.text:SetText("Rested")
					d.frame:Show()
				else
					d.frame:Hide()
				end
			end,
		})
	end,
})

------------------------------------------------------------------------------
-- Healthstone ready: the icon and its cooldown while you carry one.
------------------------------------------------------------------------------

local HEALTHSTONE = 5512
local QUESTION = 134400

local function RefreshPotion()
	local d = Q:GetDisplay("potion")
	if d then d:Refresh() end
end

Q:Feature({
	key = "potionReady",
	events = {
		BAG_UPDATE_COOLDOWN = RefreshPotion,
		BAG_UPDATE_DELAYED = RefreshPotion,
	},
	enable = function()
		if Q:GetDisplay("potion") then return end
		Q:Display("potion", {
			label = "Healthstone ready", feature = "potionReady", sizeKey = "potionSize", defaultSize = 36,
			x = 240, y = 80, minSize = 20, maxSize = 64, ratio = 1,
			build = function(d)
				local icon = d.frame:CreateTexture(nil, "ARTWORK")
				icon:SetAllPoints()
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				d.icon = icon
				local cd = CreateFrame("Cooldown", nil, d.frame, "CooldownFrameTemplate")
				cd:SetAllPoints()
				d.cd = cd
			end,
			layout = function(d, size) d.frame:SetSize(size, size) end,
			sample = function(d)
				local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(HEALTHSTONE)
				d.icon:SetTexture(tex or QUESTION)
				d.cd:Clear()
			end,
			paint = function(d)
				local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HEALTHSTONE)
				if type(count) ~= "number" or Q.IsSecret(count) or count < 1 then
					d.frame:Hide()
					return
				end
				local tex = C_Item.GetItemIconByID and C_Item.GetItemIconByID(HEALTHSTONE)
				d.icon:SetTexture(tex or QUESTION)
				local start, duration
				if C_Item.GetItemCooldown then
					start, duration = C_Item.GetItemCooldown(HEALTHSTONE)
				end
				if not Q.IsSecret(start) and not Q.IsSecret(duration)
					and type(start) == "number" and type(duration) == "number" and duration > 0 and start > 0
					and C_DurationUtil and C_DurationUtil.CreateDuration then
					d.timer = d.timer or C_DurationUtil.CreateDuration()
					d.timer:SetTimeFromStart(start, duration)
					d.cd:SetCooldownFromDurationObject(d.timer)
				else
					d.cd:Clear()
				end
				d.frame:Show()
			end,
		})
	end,
})

------------------------------------------------------------------------------
-- Unspent talent points
------------------------------------------------------------------------------

local function RefreshTalents()
	local d = Q:GetDisplay("talents")
	if d then d:Refresh() end
end

Q:Feature({
	key = "unspentTalents",
	events = {
		PLAYER_TALENT_UPDATE = RefreshTalents,
		TRAIT_CONFIG_UPDATED = RefreshTalents,
		PLAYER_ENTERING_WORLD = RefreshTalents,
	},
	enable = function()
		if Q:GetDisplay("talents") then return end
		Q:Display("talents", {
			label = "Unspent talents", feature = "unspentTalents", sizeKey = "talentsSize", defaultSize = 13,
			x = 220, y = 260, minSize = 10, maxSize = 24, ratio = 1.3,
			build = function(d) Q.TextDisplay(d) end,
			layout = function(d, size)
				Soul:ApplyFont(d.text, size)
				d.frame:SetSize(floor(size * 8), floor(size * 1.3))
			end,
			sample = function(d) d.text:SetText("Unspent talents") end,
			paint = function(d)
				local talents = C_ClassTalents
				local unspent = talents and talents.HasUnspentTalentPoints and talents.HasUnspentTalentPoints()
				local hero = talents and talents.HasUnspentHeroTalentPoints and talents.HasUnspentHeroTalentPoints()
				if unspent == true or hero == true then
					d.text:SetText("Unspent talents")
					d.frame:Show()
				else
					d.frame:Hide()
				end
			end,
		})
	end,
})

------------------------------------------------------------------------------
-- Floating combat text font. Blizzard_CombatText loads on demand; the
-- original font of each string is kept so turning this off restores it.
------------------------------------------------------------------------------

local combatFonts = {} -- font string -> { path, size, flags }

local function SetCombatTextFont(on)
	for i = 1, 20 do
		local font = _G["CombatText" .. i]
		if font and font.SetFont and font.GetFont then
			if on then
				if not combatFonts[font] then
					local path, size, flags = font:GetFont()
					if path then combatFonts[font] = { path, size, flags } end
				end
				local saved = combatFonts[font]
				Soul:ApplyFont(font, saved and saved[2] or 18)
			elseif combatFonts[font] then
				local saved = combatFonts[font]
				font:SetFont(saved[1], saved[2], saved[3] or "")
			end
		end
	end
end

Q:Feature({
	key = "combatText",
	enable = function()
		Q.WhenLoaded("Blizzard_CombatText", function()
			if Q.on.combatText then SetCombatTextFont(true) end
		end)
	end,
	disable = function() SetCombatTextFont(false) end,
})

------------------------------------------------------------------------------
-- Movement cooldown: the first movement spell you know from a short list.
------------------------------------------------------------------------------

local MOVE_SPELLS = { 1953, 2983, 6544, 190784, 186257, 111771 }

local function RefreshMove()
	local d = Q:GetDisplay("move")
	if d then d:Refresh() end
end

Q:Feature({
	key = "moveAlert",
	events = {
		SPELL_UPDATE_COOLDOWN = RefreshMove,
		SPELLS_CHANGED = RefreshMove,
	},
	enable = function()
		if Q:GetDisplay("move") then return end
		Q:Display("move", {
			label = "Movement cooldown", feature = "moveAlert", sizeKey = "moveSize", defaultSize = 36,
			x = -280, y = -40, minSize = 20, maxSize = 64, ratio = 1,
			build = function(d)
				local icon = d.frame:CreateTexture(nil, "ARTWORK")
				icon:SetAllPoints()
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				d.icon = icon
				local cd = CreateFrame("Cooldown", nil, d.frame, "CooldownFrameTemplate")
				cd:SetAllPoints()
				d.cd = cd
			end,
			layout = function(d, size) d.frame:SetSize(size, size) end,
			sample = function(d)
				d.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(2983) or QUESTION)
				d.cd:Clear()
			end,
			paint = function(d)
				local shown = false
				for i = 1, #MOVE_SPELLS do
					local id = MOVE_SPELLS[i]
					if IsPlayerSpell and IsPlayerSpell(id) == true then
						local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
						d.icon:SetTexture(tex or QUESTION)
						-- A duration object is opaque, not a secret number; this
						-- cooldown frame is our own, so it accepts it.
						local duration = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id)
						if duration then
							pcall(d.cd.SetCooldownFromDurationObject, d.cd, duration)
						else
							d.cd:Clear()
						end
						shown = true
						break
					end
				end
				d.frame:SetShown(shown)
			end,
		})
	end,
})

------------------------------------------------------------------------------
-- Cursor trail. Its OnUpdate only runs while the feature is on.
------------------------------------------------------------------------------

local trail = {}

local function TintTrail()
	local r, g, b = Soul:Accent()
	for i = 1, #trail do trail[i]:SetVertexColor(r, g, b, 0.6 * (9 - i) / 8) end
end

Q:Feature({
	key = "cursorTrail",
	enable = function()
		if not trail.frame then
			local host = CreateFrame("Frame", nil, UIParent)
			host:SetAllPoints()
			host:SetFrameStrata("TOOLTIP")
			host:EnableMouse(false)
			host:Hide()
			for i = 1, 8 do
				local tex = host:CreateTexture(nil, "ARTWORK")
				tex:SetSize(12 - i, 12 - i)
				tex:SetTexture("Interface\\AddOns\\SoulUI\\Media\\Textures\\Circle.tga")
				trail[i] = tex
			end
			local last = 0
			host:SetScript("OnUpdate", function(_, elapsed)
				last = last + elapsed
				if last < 0.03 then return end
				last = 0
				local x, y = GetCursorPosition()
				local scale = UIParent:GetEffectiveScale()
				if not scale or scale == 0 then scale = 1 end
				x, y = x / scale, y / scale
				for i = 8, 2, -1 do
					local px, py = trail[i - 1]:GetCenter()
					if px then
						trail[i]:ClearAllPoints()
						trail[i]:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px, py)
					end
				end
				trail[1]:ClearAllPoints()
				trail[1]:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
			end)
			trail.frame = host
		end
		TintTrail()
		trail.frame:Show()
	end,
	disable = function()
		if trail.frame then trail.frame:Hide() end
	end,
})

------------------------------------------------------------------------------
-- GCD ring on the cursor. It follows the mouse, so it has no mover; its size
-- is set on the settings page. The cooldown is set when spell cooldowns
-- change, not every frame.
------------------------------------------------------------------------------

local GCD_SPELL = 61304
local gcd

local function GcdDisplay()
	gcd = gcd or Q:Display("gcd", {
		label = "GCD ring", feature = "gcdRing", sizeKey = "gcdRingSize", defaultSize = 40,
		noMover = true, strata = "TOOLTIP",
		build = function(d)
			d.frame:EnableMouse(false)
			local tex = d.frame:CreateTexture(nil, "ARTWORK")
			tex:SetAllPoints()
			tex:SetTexture("Interface\\AddOns\\SoulUI\\Media\\Textures\\Ring.tga")
			d.ring = tex
			local cd = CreateFrame("Cooldown", nil, d.frame, "CooldownFrameTemplate")
			cd:SetAllPoints()
			cd:SetHideCountdownNumbers(true)
			cd:SetDrawEdge(false)
			d.cd = cd
			d.frame:SetScript("OnUpdate", function(self)
				local x, y = GetCursorPosition()
				local scale = UIParent:GetEffectiveScale()
				if not scale or scale == 0 then scale = 1 end
				self:ClearAllPoints()
				self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
			end)
		end,
		layout = function(d, size)
			d.frame:SetSize(size, size)
			local r, g, b = Soul:Accent()
			d.ring:SetVertexColor(r, g, b, 0.8)
		end,
		paint = function(d) d.frame:Show() end,
	})
	return gcd
end

local function UpdateGcd()
	if not gcd then return end
	local duration = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(GCD_SPELL)
	if duration then
		pcall(gcd.cd.SetCooldownFromDurationObject, gcd.cd, duration)
	end
end

Q:Feature({
	key = "gcdRing",
	events = {
		SPELL_UPDATE_COOLDOWN = UpdateGcd,
	},
	enable = function() GcdDisplay() end,
})
