if SoulUI_Blocked or not SoulUI then return end

-- Chat: clickable links, copy chat, red error text, screenshot message.
-- Chat text can be secret during encounter lockdown. Every path checks
-- issecretvalue first and leaves a secret message alone.

local Soul = SoulUI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local UI = Soul.UI
local type, ipairs, math_max = type, ipairs, math.max
local table_concat = table.concat

------------------------------------------------------------------------------
-- Copy window (shared by links and chat copy)
------------------------------------------------------------------------------

local copy

local function BuildCopy()
	if copy then return copy end
	copy = UI.Window("SoulUIQoLCopy", "Copy", 620, 360)
	local holder = CreateFrame("Frame", nil, copy)
	holder:SetPoint("TOPLEFT", 12, -52)
	holder:SetPoint("BOTTOMRIGHT", -12, 12)
	UI.Fill(holder, { 0, 0, 0, 0.4 })
	UI.Edge(holder, 1, 1, 1, 0.12)
	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -8, 8)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetWidth(580)
	UI.SetFont(box, 13)
	box:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		copy:Hide()
	end)
	scroll:SetScrollChild(box)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math_max(0, box:GetHeight() - self:GetHeight())
		local value = self:GetVerticalScroll() - delta * 40
		if value < 0 then value = 0 elseif value > maxScroll then value = maxScroll end
		self:SetVerticalScroll(value)
	end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	copy.box = box
	copy.scroll = scroll
	return copy
end

local function ShowCopy(text, title, toBottom)
	local window = BuildCopy()
	window.title:SetText(title or "Copy")
	window:RestorePosition("CENTER", 0, 80)
	window:Show()
	window.box:SetText(text or "")
	window.box:SetFocus()
	window.box:HighlightText()
	if toBottom then
		C_Timer.After(0, function()
			local maxScroll = math_max(0, window.box:GetHeight() - window.scroll:GetHeight())
			window.scroll:SetVerticalScroll(maxScroll)
		end)
	else
		window.scroll:SetVerticalScroll(0)
	end
end
Q.ShowCopy = ShowCopy

------------------------------------------------------------------------------
-- Clickable web links in chat. Clicking one opens it in the copy box
-- (the game cannot open a browser).
------------------------------------------------------------------------------

local LINK_PREFIX = "addon:SoulUI:url:"

local URL_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
	"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local function Wrap(url)
	return "|cff4fc3f7|H" .. LINK_PREFIX .. url .. "|h[" .. url .. "]|h|r"
end

local function WrapSpaced(space, url)
	return space .. Wrap(url)
end

local function UrlFilter(_, _, message, ...)
	if not Q.on.chatUrls then return false end
	if type(message) ~= "string" or Q.IsSecret(message) then return false end
	if not message:find("://", 1, true) and not message:find("www.", 1, true) then return false end
	-- scheme://anything up to a space, a pipe or a bracket
	local changed = message:gsub("(%a[%w+.-]*://[^%s|%[%]]+)", Wrap)
	-- bare www. addresses that start a word (not ones already inside a link)
	if changed:find("www.", 1, true) then
		changed = (" " .. changed):gsub("(%s)(www%.[%w_-]+%.[^%s|%[%]]+)", WrapSpaced):sub(2)
	end
	if changed == message then return false end
	return false, changed, ...
end

local function AddFilter(event, fn)
	local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if add then add(event, fn) end
end

local function RemoveFilter(event, fn)
	local remove = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter
	if remove then remove(event, fn) end
end

local function OnLink(link)
	if type(link) ~= "string" or Q.IsSecret(link) then return end
	if link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return end
	ShowCopy(link:sub(#LINK_PREFIX + 1), "Copy link (Ctrl+C)")
end

local linkHooked = false

local function HookLinks()
	if linkHooked then return end
	linkHooked = true
	-- Links of type "addon" are handed to EventRegistry as "SetItemRef".
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("SetItemRef", function(_, link) OnLink(link) end, Q)
	end
	-- Fallback for clients that route it through SetItemRef only.
	if SetItemRef then
		hooksecurefunc("SetItemRef", function(link) OnLink(link) end)
	end
end

Q:Feature({
	key = "chatUrls",
	enable = function()
		HookLinks()
		for _, event in ipairs(URL_EVENTS) do AddFilter(event, UrlFilter) end
	end,
	disable = function()
		for _, event in ipairs(URL_EVENTS) do RemoveFilter(event, UrlFilter) end
	end,
})

------------------------------------------------------------------------------
-- Copy chat: a small button on each chat window copies its last lines.
------------------------------------------------------------------------------

local copyButtons = {}

local function Plain(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
	text = text:gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|T.-|t", "")
	text = text:gsub("|A.-|a", "")
	return text
end

local function CopyChat(chat)
	if not (chat and chat.GetNumMessages and chat.GetMessageInfo) then return end
	local count = chat:GetNumMessages() or 0
	local lines = {}
	for i = math_max(1, count - 299), count do
		local text = chat:GetMessageInfo(i)
		if type(text) == "string" and not Q.IsSecret(text) then
			lines[#lines + 1] = Plain(text)
		end
	end
	ShowCopy(table_concat(lines, "\n"), "Copy chat (Ctrl+A, Ctrl+C)", true)
end

local function BuildCopyButtons()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local chat = _G["ChatFrame" .. i]
		if chat and not copyButtons[chat] then
			local button = UI.IconButton(chat, "bars", 20, function() CopyChat(chat) end)
			button:SetPoint("TOPRIGHT", chat, "TOPRIGHT", 2, 2)
			button:SetFrameLevel(chat:GetFrameLevel() + 6)
			button:SetAlpha(0.35)
			button:HookScript("OnEnter", function(self) self:SetAlpha(1) end)
			button:HookScript("OnLeave", function(self) self:SetAlpha(0.35) end)
			copyButtons[chat] = button
		end
	end
end

Q:Feature({
	key = "chatCopy",
	enable = function()
		BuildCopyButtons()
		for _, button in pairs(copyButtons) do button:Show() end
	end,
	disable = function()
		for _, button in pairs(copyButtons) do button:Hide() end
	end,
})

------------------------------------------------------------------------------
-- Red error text ("Not enough rage", "Ability is not ready yet").
-- Important errors (bags full, quest log full) still show.
------------------------------------------------------------------------------

local IMPORTANT_KEYS = {
	"ERR_INV_FULL", "ERR_QUEST_LOG_FULL", "ERR_ITEM_MAX_COUNT", "ERR_BAG_FULL",
	"ERR_NOT_ENOUGH_MONEY", "ERR_LOOT_GONE", "ERR_REPAIR_NOT_ENOUGH_MONEY",
}
local important
local blizzErrorsOff = false

local function SetBlizzardErrors(show)
	local frame = UIErrorsFrame
	if not frame then return end
	if show and blizzErrorsOff then
		frame:RegisterEvent("UI_ERROR_MESSAGE")
		blizzErrorsOff = false
	elseif not show and not blizzErrorsOff then
		frame:UnregisterEvent("UI_ERROR_MESSAGE")
		blizzErrorsOff = true
	end
end

local function SyncErrors(inCombat)
	local hide = Q.on.hideErrors and (not DB().hideErrorsCombatOnly or inCombat) or false
	SetBlizzardErrors(not hide)
end

Q:Feature({
	key = "hideErrors",
	events = {
		PLAYER_REGEN_DISABLED = function() SyncErrors(true) end,
		PLAYER_REGEN_ENABLED = function() SyncErrors(false) end,
		UI_ERROR_MESSAGE = function(_, _, message)
			if not blizzErrorsOff or type(message) ~= "string" or Q.IsSecret(message) then return end
			if important and important[message] and UIErrorsFrame then
				UIErrorsFrame:AddMessage(message, 1, 0.1, 0.1)
			end
		end,
	},
	enable = function()
		if not important then
			important = {}
			for _, key in ipairs(IMPORTANT_KEYS) do
				local text = _G[key]
				if type(text) == "string" then important[text] = true end
			end
		end
	end,
	refresh = function()
		local combat = UnitAffectingCombat("player")
		SyncErrors(not Q.IsSecret(combat) and combat or InCombatLockdown())
	end,
	disable = function() SetBlizzardErrors(true) end,
})

------------------------------------------------------------------------------
-- "Screenshot saved" message
------------------------------------------------------------------------------

local screenshotOff = false

Q:Feature({
	key = "hideScreenshotMsg",
	enable = function()
		if ActionStatus and not screenshotOff then
			ActionStatus:UnregisterEvent("SCREENSHOT_SUCCEEDED")
			screenshotOff = true
		end
	end,
	disable = function()
		if ActionStatus and screenshotOff then
			ActionStatus:RegisterEvent("SCREENSHOT_SUCCEEDED")
			screenshotOff = false
		end
	end,
})
