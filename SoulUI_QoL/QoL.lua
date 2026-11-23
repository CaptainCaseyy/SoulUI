if SoulUI_Blocked or not SoulUI then return end

-- SoulUI QoL: a list of small features. Each feature is a table:
--   key          the boolean in the QoL settings that turns it on
--   isOn(db)     optional, replaces db[key]
--   events       { EVENT = function(feature, ...) }  registered only while on
--   unitEvents   { EVENT = { "unit", ... } }          those events use RegisterUnitEvent
--   enable(f)    runs when the feature turns on (hooks, frames, CVars)
--   disable(f)   runs when it turns off
--   refresh(f)   runs on every Apply while on (a setting of the feature changed)
-- Q:Apply() turns features on and off from the live settings and rewires the
-- event registrations, so every toggle in /soul works without a reload.
-- Several features can listen to one event; one dispatcher calls each.

local Soul = SoulUI
local Q = Soul:NewModule("QoL", "SoulUI_QoL")

local pairs, ipairs, type, pcall, wipe, unpack = pairs, ipairs, type, pcall, wipe, unpack
local math_floor, math_max, math_min = math.floor, math.max, math.min
local string_format = string.format

Q.features = {}
Q.on = {}

local active = {} -- event -> { feature, ... } while on
local registered = {} -- plain events registered on the module frame
local unitRegistered = {} -- event -> { unit, ... }
local displays = {}

local function DB()
	return Soul:ModuleDB("QoL")
end
Q.DB = DB

function Q.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

local function Safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then Soul:Print("QoL:", err) end
	return ok
end
Q.Safe = Safe

------------------------------------------------------------------------------
-- Features and the event dispatcher
------------------------------------------------------------------------------

function Q:Feature(def)
	self.features[#self.features + 1] = def
	return def
end

local function Dispatch(_, event, ...)
	local list = active[event]
	if not list then return end
	for i = 1, #list do
		local def = list[i]
		local fn = def.events and def.events[event]
		if fn then
			local ok, err = pcall(fn, def, ...)
			if not ok then Soul:Debug("QoL", def.key, event, err) end
		end
	end
end

function Q:IsOn(def, db)
	if def.isOn then return def.isOn(db) and true or false end
	return db[def.key] and true or false
end

function Q:Rewire()
	for _, list in pairs(active) do wipe(list) end
	local wantUnits
	for i = 1, #self.features do
		local def = self.features[i]
		if self.on[def.key] and def.events then
			for event in pairs(def.events) do
				local list = active[event]
				if not list then
					list = {}
					active[event] = list
				end
				list[#list + 1] = def
				local units = def.unitEvents and def.unitEvents[event]
				if units then
					wantUnits = wantUnits or {}
					local set = wantUnits[event]
					if not set then
						set = {}
						wantUnits[event] = set
					end
					for u = 1, #units do set[units[u]] = true end
				end
			end
		end
	end

	-- Unit events are re-registered from scratch (Apply is rare).
	for event, units in pairs(unitRegistered) do
		self:UnregisterUnitEvent(event, unpack(units))
		self._handlers[event] = nil
	end
	wipe(unitRegistered)
	if wantUnits then
		for event, set in pairs(wantUnits) do
			local list = {}
			for unit in pairs(set) do list[#list + 1] = unit end
			self:RegisterUnitEvent(event, Dispatch, unpack(list))
			unitRegistered[event] = list
		end
	end

	for event, list in pairs(active) do
		if not (wantUnits and wantUnits[event]) then
			if #list > 0 and not registered[event] then
				self:RegisterEvent(event, Dispatch)
				registered[event] = true
			elseif #list == 0 and registered[event] then
				self:UnregisterEvent(event)
				registered[event] = nil
			end
		end
	end
end

function Q:Apply()
	if not self._ready then return end
	local db = DB()
	for i = 1, #self.features do
		local def = self.features[i]
		local on = self:IsOn(def, db)
		if on ~= (self.on[def.key] == true) then
			self.on[def.key] = on
			local fn
			if on then fn = def.enable else fn = def.disable end
			if fn then Safe(fn, def) end
		end
		if on and def.refresh then Safe(def.refresh, def) end
	end
	self:Rewire()
	for _, display in pairs(displays) do
		self:PlaceDisplay(display)
		display:Refresh()
	end
end

------------------------------------------------------------------------------
-- Blizzard load-on-demand UI (trainer, world map, talking head ...)
------------------------------------------------------------------------------

local waiting = {}
local loader = CreateFrame("Frame")
loader:SetScript("OnEvent", function(_, _, name)
	local list = waiting[name]
	if not list then return end
	waiting[name] = nil
	for i = 1, #list do Safe(list[i]) end
	if next(waiting) == nil then loader:UnregisterEvent("ADDON_LOADED") end
end)

-- Runs fn now if the Blizzard addon is loaded, otherwise once it loads.
function Q.WhenLoaded(addonName, fn)
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addonName) then
		Safe(fn)
		return
	end
	local list = waiting[addonName]
	if not list then
		list = {}
		waiting[addonName] = list
	end
	list[#list + 1] = fn
	loader:RegisterEvent("ADDON_LOADED")
end

------------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------------

-- CVars go through the core so the first value is remembered for a restore.
function Q.SetCVar(name, value)
	Soul:SetOwnedCVar(name, value, "QoL")
end

function Q.RestoreCVar(name)
	local record = Soul.db and Soul.db.cvars and Soul.db.cvars[name]
	if type(record) == "table" and record.owner == "QoL" and record.original ~= nil then
		Soul:SetOwnedCVar(name, record.original, "QoL")
		-- Forget it: the next change records the value at that time, not a
		-- stale one from the first time the option was ever used.
		Soul.db.cvars[name] = nil
	end
end

-- 123456 copper -> "12g 34s 56c" (copper only below one gold).
function Q.Money(copper)
	copper = math_floor(tonumber(copper) or 0)
	local gold = math_floor(copper / 10000)
	local silver = math_floor((copper % 10000) / 100)
	local rest = copper % 100
	local text = ""
	if gold > 0 then text = string_format("|cffffd100%dg|r", gold) end
	if silver > 0 then text = text .. (text ~= "" and " " or "") .. string_format("|cffc7c7cf%ds|r", silver) end
	if gold == 0 and (rest > 0 or text == "") then
		text = text .. (text ~= "" and " " or "") .. string_format("|cffeda55f%dc|r", rest)
	end
	return text
end

-- The visible StaticPopup showing `which`, or nil.
function Q.FindPopup(which)
	if StaticPopup_FindVisible then
		local dialog = StaticPopup_FindVisible(which)
		if dialog then return dialog end
	end
	for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
		local dialog = _G["StaticPopup" .. i]
		if dialog and dialog:IsShown() and dialog.which == which then return dialog end
	end
	return nil
end

function Q.HidePopup(which)
	if StaticPopup_Hide then StaticPopup_Hide(which) end
end

function Q.PopupEditBox(dialog)
	if not dialog then return nil end
	if dialog.GetEditBox then
		local ok, box = pcall(dialog.GetEditBox, dialog)
		if ok and box then return box end
	end
	if dialog.editBox then return dialog.editBox end
	local name = dialog.GetName and dialog:GetName()
	return name and _G[name .. "EditBox"] or nil
end

-- Party, raid or instance chat, whichever applies. Quiet during the chat
-- lockdown of encounters and keystones.
function Q.SendGroup(text)
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
	local channel
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		channel = "INSTANCE_CHAT"
	elseif IsInRaid() then
		channel = "RAID"
	elseif IsInGroup() then
		channel = "PARTY"
	end
	if not channel then return end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if send then send(text, channel) end
end

function Q.Accent()
	return Soul:Accent()
end

------------------------------------------------------------------------------
-- On-screen displays. Each is a plain frame with a mover in /soul move.
--   info = { label, feature, sizeKey, x, y, minSize, maxSize, ratio,
--            build(d), layout(d, size), paint(d), sample(d), strata }
-- d:Refresh() hides it while the feature is off, shows the sample in edit
-- mode, and otherwise lets paint decide.
------------------------------------------------------------------------------

function Q:Display(key, info)
	local display = displays[key]
	if display then return display end
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata(info.strata or "MEDIUM")
	frame:SetSize(100, 20)
	frame:Hide()
	if frame.SetRoundLayoutToNearestPixel then frame:SetRoundLayoutToNearestPixel(true) end
	display = { key = key, frame = frame, info = info, editing = Soul.unlocking and true or false }

	function display:Size()
		local db = DB()
		local size = info.sizeKey and db[info.sizeKey]
		if type(size) ~= "number" then size = info.defaultSize or 16 end
		return size
	end

	function display:Refresh()
		-- A display that holds secure buttons (world markers) is protected:
		-- no show, hide or resize in combat. Try again when combat ends.
		if InCombatLockdown() and frame:IsProtected() then
			Soul:RunAfterCombat("qol:display:" .. key, function() display:Refresh() end)
			return
		end
		if not Q.on[info.feature] then
			frame:Hide()
			return
		end
		if info.layout then info.layout(self, self:Size()) end
		if self.editing and info.sample then
			info.sample(self)
			frame:Show()
		elseif info.paint then
			info.paint(self)
		end
	end

	if info.build then info.build(display) end
	displays[key] = display
	-- A display that follows the cursor has no fixed spot, so no mover.
	if info.noMover then return display end
	self:PlaceDisplay(display)

	Soul:RegisterMover({
		key = "QoL:" .. key,
		label = info.label,
		page = "qol",
		getFrame = function() return frame end,
		fallback = function()
			return { point = "CENTER", relPoint = "CENTER", x = info.x or 0, y = info.y or 0 }
		end,
		getEnabled = function() return DB()[info.feature] and true or false end,
		setEnabled = function(on)
			DB()[info.feature] = on and true or false
			Q:Apply()
		end,
		onResize = info.sizeKey and function(_, height, dir)
			local size = display:Size()
			local minSize, maxSize = info.minSize or 8, info.maxSize or 64
			if dir then
				size = size + dir * math_max(1, math_floor(size * 0.06 + 0.5))
			elseif type(height) == "number" and height > 0 then
				size = math_floor(height / (info.ratio or 1.3) + 0.5)
			end
			size = math_max(minSize, math_min(maxSize, size))
			DB()[info.sizeKey] = size
			display:Refresh()
		end or nil,
		onEdit = function(on)
			display.editing = on and true or false
			display:Refresh()
		end,
		onReset = function() Q:PlaceDisplay(display) end,
	})
	return display
end

function Q:PlaceDisplay(display)
	local info = display.info
	if info.noMover then return end
	Soul:Place(display.frame, "QoL:" .. display.key, {
		point = "CENTER", relPoint = "CENTER", x = info.x or 0, y = info.y or 0,
	})
end

function Q:GetDisplay(key)
	return displays[key]
end

-- One font string, centered, in the theme font.
function Q.TextDisplay(display, justify)
	local text = display.frame:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(text, 16)
	text:SetPoint("CENTER")
	text:SetJustifyH(justify or "CENTER")
	display.text = text
	return text
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

function Q:OnInitialize()
	Soul:RegisterModuleDB("QoL", Soul.Defaults.QoL)
end

function Q:OnEnable()
	self._ready = true
	self:Apply()
	Soul:On("ProfileChanged", function() Q:Apply() end)
	Soul:On("ThemeChanged", function()
		for _, display in pairs(displays) do display:Refresh() end
		-- Features that draw with the theme font or accent (skins, combat
		-- text font, cursor trail) re-apply through their refresh.
		Q:Apply()
	end)
end
