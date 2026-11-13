if SoulUI_Blocked or not SoulUI then return end

-- Shift-drag for a few Blizzard windows, /way pins, a chat cover, target
-- distance, rested, potion ready, unspent talents, floating combat text
-- font, a movement cooldown, a cursor trail and a GCD ring.

local Soul = SoulUI
local UI = Soul.UI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local floor, sqrt = math.floor, math.sqrt
local issecret = issecretvalue or function() return false end

local SHIFT = {
	"CharacterFrame", "SpellBookFrame", "ProfessionsFrame", "WorldMapFrame",
	"PVEFrame", "FriendsFrame", "CommunitiesFrame",
}

local function Positions()
	local db = DB()
	if type(db.shifterPos) ~= "table" then db.shifterPos = {} end
	return db.shifterPos
end

local function ApplyShifted(frame, name)
	local pos = Positions()[name]
	if type(pos) ~= "table" or InCombatLockdown() then return end
	frame:ClearAllPoints()
	frame:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
end

Q:Feature({
	key = "shifter",
	enable = function()
		for i = 1, #SHIFT do
			local name = SHIFT[i]
			local frame = _G[name]
			if frame and not frame._soulShift then
				frame._soulShift = true
				frame:SetMovable(true)
				frame:RegisterForDrag("LeftButton")
				frame:HookScript("OnDragStart", function(self)
					if DB().shifter and IsShiftKeyDown() and not InCombatLockdown() then
						self:StartMoving()
					end
				end)
				frame:HookScript("OnDragStop", function(self)
					self:StopMovingOrSizing()
					if not DB().shifter then return end
					local point, _, rel, x, y = self:GetPoint(1)
					Positions()[name] = { point = point, rel = rel, x = x, y = y }
				end)
				frame:HookScript("OnShow", function(self) ApplyShifted(self, name) end)
			end
			if frame then ApplyShifted(frame, name) end
		end
	end,
})

local function PlaceWay(x, y)
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if type(map) ~= "number" or not C_Map.SetUserWaypoint or not CreateVector2D then
		Soul:Print("This map cannot take a pin.")
		return
	end
	if x > 1 then x = x / 100 end
	if y > 1 then y = y / 100 end
	local pos = CreateVector2D(x, y)
	local point = UiMapPoint and UiMapPoint.CreateFromVector2D and UiMapPoint.CreateFromVector2D(map, pos)
	if not point then
		point = { uiMapID = map, position = pos }
	end
	C_Map.SetUserWaypoint(point)
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
	local x, y = tostring(msg or ""):match("(%d+%.?%d*)%s+(%d+%.?%d*)")
	if not x then
		Soul:Print("Usage: /way 45.2 67.8")
		return
	end
	PlaceWay(tonumber(x), tonumber(y))
end

Q:Feature({ key = "waypoints", enable = function() end })

local cover

Q:Feature({
	key = "chatCover",
	enable = function()
		local chat = ChatFrame1
		if not chat or cover then
			if cover then cover:Show() end
			return
		end
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
			if DB().chatCover and not chat:IsMouseOver() then cover:Show() end
		end)
		cover:Show()
	end,
	disable = function()
		if cover then cover:Hide() end
	end,
})

local distance

local function DistanceDisplay()
	distance = distance or Q:Display("distance", {
		label = "Target distance", feature = "targetDistance", sizeKey = "fpsSize",
		x = 0, y = -140, minSize = 10, maxSize = 28, ratio = 1.2,
		build = function(d) Q.TextDisplay(d) end,
		layout = function(d, size)
			Soul:ApplyFont(d.text, size)
			d.frame:SetSize(floor(size * 6), floor(size * 1.3))
		end,
		sample = function(d)
			d.text:SetText("18 yd")
			d.frame:Show()
		end,
		paint = function(d) d.frame:Hide() end,
	})
	return distance
end

local function PaintDistance()
	local d = DistanceDisplay()
	if not UnitExists("target") or not UnitDistanceSquared then
		d.frame:Hide()
		return
	end
	local yards = UnitDistanceSquared("target")
	if Q.IsSecret(yards) or type(yards) ~= "number" then
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
		if not distance._ticker then
			distance._ticker = C_Timer.NewTicker(0.2, function()
				if DB().targetDistance then PaintDistance() end
			end)
		end
	end,
	disable = function()
		if distance and distance._ticker then
			distance._ticker:Cancel()
			distance._ticker = nil
		end
	end,
})

Q:Feature({
	key = "rested",
	enable = function()
		local d = Q:GetDisplay("rested") or Q:Display("rested", {
			label = "Rested", feature = "rested", sizeKey = "fpsSize",
			x = -200, y = 280, minSize = 10, maxSize = 24, ratio = 1.2,
			build = function(frame) Q.TextDisplay(frame) end,
			layout = function(frame, size)
				Soul:ApplyFont(frame.text, size)
				frame.frame:SetSize(floor(size * 5), floor(size * 1.3))
			end,
			sample = function(frame)
				frame.text:SetText("Rested")
				frame.frame:Show()
			end,
			paint = function(frame)
				local amount = GetXPExhaustion and GetXPExhaustion()
				if type(amount) == "number" and amount > 0 then
					frame.text:SetText("Rested")
					frame.frame:Show()
				else
					frame.frame:Hide()
				end
			end,
		})
		d:Refresh()
	end,
})

local HEALTHSTONE = 5512

Q:Feature({
	key = "potionReady",
	enable = function()
		Q:Display("potion", {
			label = "Potion ready", feature = "potionReady", sizeKey = "brezSize",
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
				d.icon:SetTexture(136243)
				d.frame:Show()
			end,
			paint = function(d)
				local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(HEALTHSTONE)
				d.icon:SetTexture(tex or 136243)
				local start, duration
				if C_Item and C_Item.GetItemCooldown then
					start, duration = C_Item.GetItemCooldown(HEALTHSTONE)
				end
				if Q.IsSecret(start) or Q.IsSecret(duration) then
					d.frame:Show()
					return
				end
				if type(start) == "number" and type(duration) == "number" and duration > 0 and start > 0 then
					if CooldownFrame_Set then CooldownFrame_Set(d.cd, start, duration, true) end
				end
				d.frame:Show()
			end,
		})
	end,
	events = {
		BAG_UPDATE_COOLDOWN = function()
			local d = Q:GetDisplay("potion")
			if d then d:Refresh() end
		end,
	},
})

Q:Feature({
	key = "unspentTalents",
	enable = function()
		Q:Display("talents", {
			label = "Unspent talents", feature = "unspentTalents", sizeKey = "fpsSize",
			x = 220, y = 260, minSize = 10, maxSize = 24, ratio = 1.2,
			build = function(d) Q.TextDisplay(d) end,
			layout = function(d, size)
				Soul:ApplyFont(d.text, size)
				d.frame:SetSize(floor(size * 8), floor(size * 1.3))
			end,
			sample = function(d)
				d.text:SetText("Unspent talents")
				d.frame:Show()
			end,
			paint = function(d)
				local unspent = C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints and C_ClassTalents.HasUnspentTalentPoints()
				if unspent == true then
					d.text:SetText("Unspent talents")
					d.frame:Show()
				else
					d.frame:Hide()
				end
			end,
		})
	end,
	events = {
		PLAYER_TALENT_UPDATE = function()
			local d = Q:GetDisplay("talents")
			if d then d:Refresh() end
		end,
		TRAIT_CONFIG_UPDATED = function()
			local d = Q:GetDisplay("talents")
			if d then d:Refresh() end
		end,
	},
})

Q:Feature({
	key = "combatText",
	enable = function()
		for i = 1, 20 do
			local font = _G["CombatText" .. i]
			if font and font.SetFont then Soul:ApplyFont(font, 18) end
		end
	end,
})

local MOVE_SPELLS = { 1953, 2983, 6544, 190784, 186257, 111771 }

Q:Feature({
	key = "moveAlert",
	enable = function()
		Q:Display("move", {
			label = "Movement cooldown", feature = "moveAlert", sizeKey = "brezSize",
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
				d.icon:SetTexture(136243)
				d.frame:Show()
			end,
			paint = function(d)
				local shown = false
				for i = 1, #MOVE_SPELLS do
					local id = MOVE_SPELLS[i]
					local known = IsPlayerSpell and IsPlayerSpell(id)
					if known == true then
						local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
						d.icon:SetTexture(tex or 136243)
						local duration = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id)
						if duration and d.cd.SetCooldownFromDurationObject then
							pcall(d.cd.SetCooldownFromDurationObject, d.cd, duration)
						end
						shown = true
						break
					end
				end
				d.frame:SetShown(shown)
			end,
		})
	end,
	events = {
		SPELL_UPDATE_COOLDOWN = function()
			local d = Q:GetDisplay("move")
			if d then d:Refresh() end
		end,
	},
})

local trail = {}

Q:Feature({
	key = "cursorTrail",
	enable = function()
		if trail.frame then trail.frame:Show() return end
		local host = CreateFrame("Frame", nil, UIParent)
		host:SetAllPoints()
		host:SetFrameStrata("TOOLTIP")
		host:EnableMouse(false)
		for i = 1, 8 do
			local tex = host:CreateTexture(nil, "ARTWORK")
			tex:SetSize(10, 10)
			tex:SetTexture("Interface\\AddOns\\SoulUI\\Media\\Textures\\Circle.tga")
			local r, g, b = Soul:Accent()
			tex:SetVertexColor(r, g, b, 0.15 * i / 8)
			trail[i] = tex
		end
		local last = 0
		host:SetScript("OnUpdate", function(_, elapsed)
			if not DB().cursorTrail then return end
			last = last + elapsed
			if last < 0.03 then return end
			last = 0
			local x, y = GetCursorPosition()
			local scale = UIParent:GetEffectiveScale()
			if not scale or scale == 0 then scale = 1 end
			x, y = x / scale, y / scale
			for i = 8, 2, -1 do
				local prev = trail[i - 1]
				local px, py = prev:GetCenter()
				if px then trail[i]:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px, py) end
			end
			trail[1]:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		end)
		trail.frame = host
	end,
	disable = function()
		if trail.frame then trail.frame:Hide() end
	end,
})

Q:Feature({
	key = "gcdRing",
	enable = function()
		local d = Q:GetDisplay("gcd") or Q:Display("gcd", {
			label = "GCD ring", feature = "gcdRing", sizeKey = "cursorRingSize",
			x = 0, y = 0, minSize = 24, maxSize = 96, ratio = 1,
			strata = "TOOLTIP",
			build = function(frame)
				local tex = frame.frame:CreateTexture(nil, "ARTWORK")
				tex:SetAllPoints()
				tex:SetTexture("Interface\\AddOns\\SoulUI\\Media\\Textures\\Ring.tga")
				local r, g, b = Soul:Accent()
				tex:SetVertexColor(r, g, b, 0.8)
				local cd = CreateFrame("Cooldown", nil, frame.frame, "CooldownFrameTemplate")
				cd:SetAllPoints()
				frame.cd = cd
			end,
			layout = function(frame, size) frame.frame:SetSize(size, size) end,
			sample = function(frame) frame.frame:Show() end,
			paint = function(frame) frame.frame:Show() end,
		})
		if d._follow then return end
		d._follow = CreateFrame("Frame")
		d._follow:SetScript("OnUpdate", function()
			if not DB().gcdRing then return end
			local x, y = GetCursorPosition()
			local scale = UIParent:GetEffectiveScale()
			if not scale or scale == 0 then scale = 1 end
			d.frame:ClearAllPoints()
			d.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
			local duration = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(61304)
			if duration and d.cd and d.cd.SetCooldownFromDurationObject then
				pcall(d.cd.SetCooldownFromDurationObject, d.cd, duration)
			end
		end)
	end,
})
