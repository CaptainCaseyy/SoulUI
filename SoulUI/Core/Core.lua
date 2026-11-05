if SoulUI_Blocked then return end

SoulUI = SoulUI or {}
local Soul = SoulUI

Soul.version = "0.5.0"
Soul.modules = {}
Soul.optionPages = {}
Soul._callbacks = {}
Soul._moduleDefaults = {}
Soul.loginDone = false

local function Scrub(value)
	if Soul.Secret and Soul.Secret.IsSecret(value) then
		return "<secret>"
	end
	return tostring(value)
end

function Soul:Print(...)
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return
	end
	local count = select("#", ...)
	local parts = {}
	for i = 1, count do
		parts[i] = Scrub(select(i, ...))
	end
	local chat = DEFAULT_CHAT_FRAME
	if chat then
		chat:AddMessage("|cff00edffSoulUI|r  " .. table.concat(parts, " "))
	end
end

function Soul:Debug(...)
	if self.db and self.db.account and self.db.account.debug then
		self:Print(...)
	end
end

function Soul:On(event, fn)
	local list = self._callbacks[event]
	if not list then
		list = {}
		self._callbacks[event] = list
	end
	list[#list + 1] = fn
end

function Soul:Fire(event, ...)
	local list = self._callbacks[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then
			self:Print("callback", event, err)
		end
	end
end

function Soul:GetModule(key)
	return self.modules[key]
end

function Soul:NewModule(key, addonName)
	local existing = self.modules[key]
	if existing then return existing end

	local mod = {
		key = key,
		addonName = addonName or ("SoulUI_" .. key),
		_handlers = {},
		_enabled = false,
	}

	-- Created while the child addon file is running, so the CPU profiler
	-- bills this frame to that addon rather than to SoulUI.
	local frame = CreateFrame("Frame")
	mod.frame = frame
	frame:SetScript("OnEvent", function(_, event, ...)
		local handler = mod._handlers[event]
		if handler then
			handler(mod, event, ...)
		end
	end)

	function mod:RegisterEvent(event, fn)
		self._handlers[event] = fn
		self.frame:RegisterEvent(event)
	end

	function mod:UnregisterEvent(event)
		self._handlers[event] = nil
		self.frame:UnregisterEvent(event)
	end

	-- frame:RegisterUnitEvent(event, unit) replaces that event's unit filter, so
	-- registering one event for several units on a single frame keeps only the
	-- last unit. Each unit token gets its own listener frame instead.
	mod._unitFrames = {}
	local function UnitListener(unit)
		local listener = mod._unitFrames[unit]
		if listener then return listener end
		listener = CreateFrame("Frame")
		listener:SetScript("OnEvent", function(_, event, ...)
			local handler = mod._handlers[event]
			if handler then
				handler(mod, event, ...)
			end
		end)
		mod._unitFrames[unit] = listener
		return listener
	end

	function mod:RegisterUnitEvent(event, fn, ...)
		self._handlers[event] = fn
		for i = 1, select("#", ...) do
			local unit = select(i, ...)
			if type(unit) == "string" then
				UnitListener(unit):RegisterUnitEvent(event, unit)
			end
		end
	end

	function mod:UnregisterUnitEvent(event, ...)
		for i = 1, select("#", ...) do
			local unit = select(i, ...)
			local listener = type(unit) == "string" and self._unitFrames[unit]
			if listener then listener:UnregisterEvent(event) end
		end
	end

	self.modules[key] = mod

	frame:RegisterEvent("ADDON_LOADED")
	mod._handlers.ADDON_LOADED = function(selfMod, _, name)
		if name ~= selfMod.addonName then return end
		selfMod.frame:UnregisterEvent("ADDON_LOADED")
		selfMod._handlers.ADDON_LOADED = nil
		if selfMod.OnInitialize then
			local ok, err = pcall(selfMod.OnInitialize, selfMod)
			if not ok then Soul:Print(key, "init failed:", err) end
		end
		if Soul.loginDone and selfMod.OnEnable and not selfMod._enabled then
			selfMod._enabled = true
			local ok, err = pcall(selfMod.OnEnable, selfMod)
			if not ok then Soul:Print(key, "enable failed:", err) end
		end
	end

	return mod
end

function Soul:EnableModules()
	for key, mod in pairs(self.modules) do
		if mod.OnEnable and not mod._enabled then
			mod._enabled = true
			local ok, err = pcall(mod.OnEnable, mod)
			if not ok then
				self:Print(key, "enable failed:", err)
			end
		end
	end
end

function Soul:RegisterPage(info)
	self.optionPages[#self.optionPages + 1] = info
	table.sort(self.optionPages, function(a, b)
		local ga, gb = a.groupOrder or 100, b.groupOrder or 100
		if ga == gb then
			return (a.order or 0) < (b.order or 0)
		end
		return ga < gb
	end)
end

-- page: optional page key ("actionbars", "resources", ...) to open on.
function Soul:OpenOptions(page)
	if InCombatLockdown() then
		self:Print("The editor closes during combat.")
		return
	end
	if page then self._optionsPage = page end
	-- Enter in chat closes every UISpecialFrames panel after the slash
	-- command runs. Opening next frame survives that close.
	if self._optionsPending then return end
	self._optionsPending = true
	C_Timer.After(0.2, function()
		Soul._optionsPending = nil
		if InCombatLockdown() then
			Soul:Print("The editor closes during combat.")
			return
		end
		if not C_AddOns.IsAddOnLoaded("SoulUI_Options") then
			local ok, reason = C_AddOns.LoadAddOn("SoulUI_Options")
			if not ok then
				Soul:Print("Options failed to load:", reason)
				return
			end
		end
		if Soul.Options and Soul.Options.Open then
			local wanted = Soul._optionsPage
			Soul._optionsPage = nil
			Soul.Options:Open(wanted)
		end
	end)
end

function Soul:CloseOptions()
	if self.Options and self.Options.Close then
		self.Options:Close()
	end
end

function SoulUI_CompartmentClick()
	SoulUI:OpenOptions()
end

local function Slash(msg)
	msg = msg or ""
	msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
	local command, rest = msg:match("^(%S*)%s*(.-)$")
	command = (command or ""):lower()

	if command == "" or command == "config" or command == "options" then
		Soul:OpenOptions()
	elseif command == "move" or command == "unlock" or command == "edit" then
		Soul:ToggleUnlock()
	elseif command == "reset" and (rest or ""):lower() == "layout" then
		Soul:ResetLayout()
	elseif command == "scale" then
		local value = tonumber(rest)
		if value and value >= 0.5 and value <= 2 then
			Soul.db.account.panelScale = value
			Soul:Print("Editor scale", value)
		else
			Soul:Print("Usage: /soul scale 0.5-2")
		end
	elseif command == "debug" then
		Soul.db.account.debug = not Soul.db.account.debug
		Soul:Print("debug", Soul.db.account.debug and "on" or "off")
	elseif command == "secret" then
		local off = (rest or ""):lower() == "off"
		local value = off and "0" or "1"
		SetCVar("addonCombatRestrictionsForced", value)
		SetCVar("addonEncounterRestrictionsForced", value)
		if off then
			Soul:Print("Forced combat restrictions cleared.")
		else
			Soul:Print("Forced combat restrictions on. Target a dummy and watch for errors. /soul secret off clears it.")
		end
	else
		Soul:Print("Commands: /soul, /soul move, /soul reset layout, /soul scale <0.5-2>, /soul debug, /soul secret, /soul secret off")
	end
end

SLASH_SOULUI1 = "/soul"
SLASH_SOULUI2 = "/soului"
SlashCmdList.SOULUI = Slash

local core = CreateFrame("Frame")
Soul._coreFrame = core
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("PLAYER_LOGOUT")
core:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "SoulUI" then
		Soul:InitDB()
		Soul:RunMigrations()
		core:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		Soul.loginDone = true
		if Soul.Pixel then Soul.Pixel:Refresh() end
		local function Start()
			if UIParent:GetWidth() < 400 then
				C_Timer.After(0, Start)
				return
			end
			if Soul.ApplyDefaultLayout then
				local ok, err = pcall(Soul.ApplyDefaultLayout, Soul)
				if not ok then Soul:Print("layout fit failed:", err) end
			end
			Soul:EnableModules()
			Soul:ApplySpecProfile()
			Soul:Fire("Ready")
		end
		Start()
		if Soul.db and Soul.db.account and not Soul.db.account.welcomed then
			Soul.db.account.welcomed = true
			Soul:Print("loaded. /soul opens the editor, /soul move unlocks frames. Party, raid, action bars, resources, and damage meters are included. Disable EllesmereUI while testing so the two UIs do not overlap.")
		end
	elseif event == "PLAYER_LOGOUT" then
		Soul:StripDefaults()
	end
end)
