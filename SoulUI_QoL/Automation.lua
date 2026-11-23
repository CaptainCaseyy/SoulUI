if SoulUI_Blocked or not SoulUI then return end

-- Loot, items, cinematics, Blizzard popups, NPC dialog and quests, logging.

local Soul = SoulUI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local C_Container, C_Timer = C_Container, C_Timer
local GetTime, IsShiftKeyDown, InCombatLockdown = GetTime, IsShiftKeyDown, InCombatLockdown
local type, ipairs = type, ipairs

local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or ((NUM_BAG_SLOTS or 4) + 1)

------------------------------------------------------------------------------
-- Faster auto loot: take every slot at once when auto loot applies.
------------------------------------------------------------------------------

local lastLoot = 0

Q:Feature({
	key = "fastLoot",
	events = {
		LOOT_READY = function()
			local now = GetTime()
			if now - lastLoot < 0.3 then return end
			-- Auto loot applies when the setting and the modifier disagree.
			if GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then return end
			lastLoot = now
			for i = GetNumLootItems(), 1, -1 do
				local _, _, _, _, _, locked = GetLootSlotInfo(i)
				if not locked then LootSlot(i) end
			end
		end,
	},
})

------------------------------------------------------------------------------
-- Bind-on-pickup and roll confirmations
------------------------------------------------------------------------------

Q:Feature({
	key = "confirmBoP",
	events = {
		LOOT_BIND_CONFIRM = function(_, slot)
			if not slot then return end
			ConfirmLootSlot(slot)
			Q.HidePopup("LOOT_BIND")
		end,
	},
})

local function ConfirmRoll(_, rollID, rollType)
	if not rollID or not rollType then return end
	ConfirmLootRoll(rollID, rollType)
	Q.HidePopup("CONFIRM_LOOT_ROLL")
end

Q:Feature({
	key = "confirmRolls",
	events = {
		CONFIRM_LOOT_ROLL = ConfirmRoll,
		CONFIRM_DISENCHANT_ROLL = ConfirmRoll,
	},
})

------------------------------------------------------------------------------
-- Type DELETE for you in the "delete this good item?" popup.
------------------------------------------------------------------------------

local DELETE_POPUPS = { "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM" }

Q:Feature({
	key = "fillDelete",
	events = {
		DELETE_ITEM_CONFIRM = function()
			C_Timer.After(0, function()
				local word = DELETE_ITEM_CONFIRM_STRING
				if type(word) ~= "string" then return end
				for _, which in ipairs(DELETE_POPUPS) do
					local box = Q.PopupEditBox(Q.FindPopup(which))
					if box then
						box:SetText(word)
						return
					end
				end
			end)
		end,
	},
})

------------------------------------------------------------------------------
-- Open containers (bags, caches, parcels) as they arrive. Out of combat,
-- one per pass, never while the mailbox, a vendor, the bank or trade is open.
------------------------------------------------------------------------------

-- busy: named windows. interaction: any NPC interaction window by type
-- (guild bank, void storage, warband bank ... where a used item would move).
local open = { busy = {}, interaction = {}, pending = false, looting = false }
local OPEN_WINDOWS = {
	"MerchantFrame", "BankFrame", "MailFrame", "SendMailFrame", "TradeFrame",
	"AuctionHouseFrame", "GuildBankFrame", "AccountBankPanel",
}

local function IsLockedBox(bag, slot)
	if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) or type(LOCKED) ~= "string" then return false end
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	local lines = data and data.lines
	if type(lines) ~= "table" then return false end
	for i = 1, #lines do
		local text = lines[i].leftText
		if text == LOCKED then return true end
	end
	return false
end

local function Busy()
	if InCombatLockdown() or open.looting then return true end
	for _, on in pairs(open.busy) do
		if on then return true end
	end
	for _, on in pairs(open.interaction) do
		if on then return true end
	end
	-- The flags above are only kept while the feature is on. A window that
	-- was already open when it was switched on is caught here: using a
	-- container at a vendor would sell it, at a bank it would move it.
	for i = 1, #OPEN_WINDOWS do
		local frame = _G[OPEN_WINDOWS[i]]
		if frame and frame.IsShown and frame:IsShown() then return true end
	end
	return false
end

local function OpenOne()
	open.pending = false
	if not Q.on.autoOpen or Busy() then return end
	for bag = 0, LAST_BAG do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.hasLoot and not info.isLocked and not IsLockedBox(bag, slot) then
				C_Container.UseContainerItem(bag, slot)
				return
			end
		end
	end
end

local function ScheduleOpen()
	if open.pending then return end
	open.pending = true
	C_Timer.After(0.4, OpenOne)
end

local function Mark(key, on)
	return function()
		open.busy[key] = on
		if not on then ScheduleOpen() end
	end
end

Q:Feature({
	key = "autoOpen",
	events = {
		BAG_UPDATE_DELAYED = ScheduleOpen,
		PLAYER_REGEN_ENABLED = ScheduleOpen,
		LOOT_OPENED = function() open.looting = true end,
		LOOT_CLOSED = function()
			open.looting = false
			ScheduleOpen()
		end,
		MAIL_SHOW = Mark("mail", true),
		MAIL_CLOSED = Mark("mail", false),
		MERCHANT_SHOW = Mark("merchant", true),
		MERCHANT_CLOSED = Mark("merchant", false),
		BANKFRAME_OPENED = Mark("bank", true),
		BANKFRAME_CLOSED = Mark("bank", false),
		TRADE_SHOW = Mark("trade", true),
		TRADE_CLOSED = Mark("trade", false),
		AUCTION_HOUSE_SHOW = Mark("auction", true),
		AUCTION_HOUSE_CLOSED = Mark("auction", false),
		PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(_, kind)
			if type(kind) == "number" then open.interaction[kind] = true end
		end,
		PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(_, kind)
			if type(kind) == "number" then open.interaction[kind] = nil end
			ScheduleOpen()
		end,
	},
	enable = ScheduleOpen,
	-- Events stop while off, so a vendor or bank closed meanwhile would
	-- leave its busy flag stuck and block opening until the next visit.
	disable = function()
		wipe(open.busy)
		wipe(open.interaction)
		open.looting = false
	end,
})

------------------------------------------------------------------------------
-- Clear the "new mount / new pet" fanfare so the journal does not wait for a
-- click to unwrap it.
------------------------------------------------------------------------------

Q:Feature({
	key = "autoUnwrap",
	events = {
		NEW_MOUNT_ADDED = function(_, mountID)
			local journal = C_MountJournal
			if not (mountID and journal and journal.ClearFanfare) then return end
			if journal.NeedsFanfare and not journal.NeedsFanfare(mountID) then return end
			journal.ClearFanfare(mountID)
		end,
		NEW_PET_ADDED = function(_, petGUID)
			local journal = C_PetJournal
			if not (petGUID and journal and journal.ClearFanfare) then return end
			if journal.PetNeedsFanfare and not journal.PetNeedsFanfare(petGUID) then return end
			journal.ClearFanfare(petGUID)
		end,
	},
})

------------------------------------------------------------------------------
-- Put the keystone in the Font of Power when it opens.
------------------------------------------------------------------------------

Q:Feature({
	key = "autoKeystone",
	events = {
		CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN = function()
			local mode = C_ChallengeMode
			if not (mode and mode.SlotKeystone) then return end
			if mode.HasSlottedKeystone and mode.HasSlottedKeystone() then return end
			if not (C_Item and C_Item.IsItemKeystoneByID) then return end
			for bag = 0, LAST_BAG do
				for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
					local info = C_Container.GetContainerItemInfo(bag, slot)
					if info and info.itemID and C_Item.IsItemKeystoneByID(info.itemID) then
						C_Container.PickupContainerItem(bag, slot)
						if CursorHasItem() then mode.SlotKeystone() end
						return
					end
				end
			end
		end,
	},
})

------------------------------------------------------------------------------
-- Cinematics and movies
------------------------------------------------------------------------------

local function CancelCinematic()
	if CinematicFrame_CancelCinematic then
		CinematicFrame_CancelCinematic()
	elseif CanCancelScene and CanCancelScene() and CancelScene then
		CancelScene()
	elseif StopCinematic then
		StopCinematic()
	end
end

local function StopMovie()
	if MovieFrame and MovieFrame:IsShown() and MovieFrame.StopMovie then
		MovieFrame:StopMovie()
	end
end

-- The "skip this cinematic?" dialogs: accept them as soon as they show.
local hookedDialogs = {}
local function HookDialog(dialog, action)
	if not dialog or hookedDialogs[dialog] or not dialog.HookScript then return end
	hookedDialogs[dialog] = true
	dialog:HookScript("OnShow", function(self)
		if not Q.on.cinematicConfirm then return end
		self:Hide()
		action()
	end)
end

local function HookSkipDialogs()
	HookDialog(CinematicFrame and CinematicFrame.closeDialog or CinematicFrameCloseDialog, CancelCinematic)
	HookDialog(MovieFrame and MovieFrame.CloseDialog, StopMovie)
end

Q:Feature({
	key = "cinematicConfirm",
	events = {
		CINEMATIC_START = function() C_Timer.After(0, HookSkipDialogs) end,
		PLAY_MOVIE = function() C_Timer.After(0, HookSkipDialogs) end,
	},
	enable = HookSkipDialogs,
})

Q:Feature({
	key = "skipCinematics",
	events = {
		CINEMATIC_START = function(_, canBeCancelled)
			if canBeCancelled == false then return end
			C_Timer.After(0.1, CancelCinematic)
		end,
		PLAY_MOVIE = function()
			C_Timer.After(0.1, StopMovie)
		end,
	},
})

------------------------------------------------------------------------------
-- Talking head (the NPC portrait and voice line in quests and dungeons)
------------------------------------------------------------------------------

local talkingHooked = false

local function CloseTalkingHead(frame)
	if frame.CloseImmediately then
		frame:CloseImmediately()
	else
		frame:Hide()
	end
end

local function HookTalkingHead()
	local frame = TalkingHeadFrame
	if talkingHooked or not frame or not frame.PlayCurrent then return end
	talkingHooked = true
	hooksecurefunc(frame, "PlayCurrent", function(self)
		if Q.on.hideTalkingHead then CloseTalkingHead(self) end
	end)
end

Q:Feature({
	key = "hideTalkingHead",
	enable = function()
		if TalkingHeadFrame then
			HookTalkingHead()
			if TalkingHeadFrame:IsShown() then CloseTalkingHead(TalkingHeadFrame) end
		else
			Q.WhenLoaded("Blizzard_TalkingHeadUI", HookTalkingHead)
		end
	end,
})

------------------------------------------------------------------------------
-- Event toasts (the big banners at the top: level up, zone, renown ...)
------------------------------------------------------------------------------

local toastHooked = false

local function CloseToasts(frame)
	if frame.CloseActiveToasts then
		frame:CloseActiveToasts()
	else
		frame:Hide()
	end
end

Q:Feature({
	key = "hideToasts",
	enable = function()
		local frame = EventToastManagerFrame
		if not frame then return end
		if not toastHooked then
			toastHooked = true
			frame:HookScript("OnShow", function(self)
				if Q.on.hideToasts then CloseToasts(self) end
			end)
		end
		if frame:IsShown() then CloseToasts(frame) end
	end,
})

------------------------------------------------------------------------------
-- CVar switches
------------------------------------------------------------------------------

Q:Feature({
	key = "hideTutorials",
	enable = function() Q.SetCVar("showTutorials", "0") end,
	disable = function() Q.RestoreCVar("showTutorials") end,
})

Q:Feature({
	key = "maxZoom",
	enable = function() Q.SetCVar("cameraDistanceMaxZoomFactor", "2.6") end,
	disable = function() Q.RestoreCVar("cameraDistanceMaxZoomFactor") end,
})

------------------------------------------------------------------------------
-- NPC dialog: pick the only option. Shift skips.
------------------------------------------------------------------------------

local lastGossipID, lastGossipTime = nil, 0
local AVAILABLE = Enum and Enum.GossipOptionStatus and Enum.GossipOptionStatus.Available or 0

Q:Feature({
	key = "autoGossip",
	events = {
		GOSSIP_SHOW = function()
			if IsShiftKeyDown() then return end
			local gossip = C_GossipInfo
			if not (gossip and gossip.GetOptions and gossip.SelectOption) then return end
			if not DB().gossipInInstances and IsInInstance() then return end
			-- An NPC with quests to hand in or take is left to the player (or to
			-- the quest helper below).
			if (gossip.GetNumAvailableQuests and gossip.GetNumAvailableQuests() or 0) > 0 then return end
			if (gossip.GetNumActiveQuests and gossip.GetNumActiveQuests() or 0) > 0 then return end
			local options = gossip.GetOptions()
			if type(options) ~= "table" or #options ~= 1 then return end
			local option = options[1]
			local id = option and option.gossipOptionID
			if not id then return end
			if option.selectOptionWhenOnlyOption then return end -- Blizzard picks these itself
			if option.status and option.status ~= AVAILABLE then return end
			local name = option.name
			-- Red text marks a warning (skips a story, costs something).
			if type(name) == "string" and (name:find("|cFFFF0000", 1, true) or name:find("|cffff0000", 1, true)) then return end
			-- Never loop on an option that reopens the same dialog.
			local now = GetTime()
			if id == lastGossipID and now - lastGossipTime < 3 then return end
			lastGossipID, lastGossipTime = id, now
			gossip.SelectOption(id)
		end,
	},
})

------------------------------------------------------------------------------
-- Quests: accept and hand in. One feature so the two never fight over the
-- same NPC dialog. Shift skips.
------------------------------------------------------------------------------

local function QuestDB()
	local db = DB()
	return db.autoQuestAccept, db.autoQuestTurnIn, db.questSkipTrivial
end

Q:Feature({
	key = "autoQuest",
	isOn = function(db) return db.autoQuestAccept or db.autoQuestTurnIn end,
	events = {
		QUEST_DETAIL = function()
			local accept = QuestDB()
			if not accept or IsShiftKeyDown() then return end
			if QuestGetAutoAccept and QuestGetAutoAccept() then
				if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
			else
				AcceptQuest()
			end
		end,
		QUEST_ACCEPT_CONFIRM = function()
			local accept = QuestDB()
			if accept and not IsShiftKeyDown() and ConfirmAcceptQuest then ConfirmAcceptQuest() end
		end,
		GOSSIP_SHOW = function()
			if IsShiftKeyDown() then return end
			local accept, turnIn, skipTrivial = QuestDB()
			local gossip = C_GossipInfo
			if not gossip then return end
			if turnIn and gossip.GetActiveQuests then
				local list = gossip.GetActiveQuests()
				for i = 1, (type(list) == "table" and #list or 0) do
					local quest = list[i]
					if quest.isComplete and quest.questID then
						gossip.SelectActiveQuest(quest.questID)
						return
					end
				end
			end
			if accept and gossip.GetAvailableQuests then
				local list = gossip.GetAvailableQuests()
				for i = 1, (type(list) == "table" and #list or 0) do
					local quest = list[i]
					if quest.questID and not (skipTrivial and quest.isTrivial) then
						gossip.SelectAvailableQuest(quest.questID)
						return
					end
				end
			end
		end,
		QUEST_GREETING = function()
			if IsShiftKeyDown() then return end
			local accept, turnIn, skipTrivial = QuestDB()
			if turnIn then
				for i = 1, (GetNumActiveQuests() or 0) do
					local _, isComplete = GetActiveTitle(i)
					if isComplete then
						SelectActiveQuest(i)
						return
					end
				end
			end
			if accept then
				for i = 1, (GetNumAvailableQuests() or 0) do
					local isTrivial = GetAvailableQuestInfo(i)
					if not (skipTrivial and isTrivial) then
						SelectAvailableQuest(i)
						return
					end
				end
			end
		end,
		QUEST_PROGRESS = function()
			local _, turnIn = QuestDB()
			if not turnIn or IsShiftKeyDown() then return end
			-- Quests that take gold are left to the player.
			if (GetQuestMoneyToGet and GetQuestMoneyToGet() or 0) > 0 then return end
			if IsQuestCompletable() then CompleteQuest() end
		end,
		QUEST_COMPLETE = function()
			local _, turnIn = QuestDB()
			if not turnIn or IsShiftKeyDown() then return end
			-- A choice of rewards is always left to the player.
			local choices = GetNumQuestChoices() or 0
			if choices > 1 then return end
			GetQuestReward(choices)
		end,
	},
})

------------------------------------------------------------------------------
-- Combat logging in raids and mythic dungeons (for log upload sites).
------------------------------------------------------------------------------

local LOG_DIFFICULTY = {
	[8] = true, -- Mythic Keystone
	[23] = true, -- Mythic dungeon
	[14] = true, -- Normal raid
	[15] = true, -- Heroic raid
	[16] = true, -- Mythic raid
}
local logStarted = false

local function CheckLogging()
	if not LoggingCombat then return end
	local _, _, difficultyID = GetInstanceInfo()
	local want = LOG_DIFFICULTY[difficultyID or 0] or false
	local logging = LoggingCombat()
	if want and not logging then
		Q.SetCVar("advancedCombatLogging", "1")
		LoggingCombat(true)
		logStarted = true
		Soul:Print("Combat logging started.")
	elseif not want and logging and logStarted then
		LoggingCombat(false)
		logStarted = false
		Soul:Print("Combat logging stopped.")
	end
end

Q:Feature({
	key = "combatLog",
	events = {
		PLAYER_ENTERING_WORLD = function() C_Timer.After(1, CheckLogging) end,
		ZONE_CHANGED_NEW_AREA = CheckLogging,
		PLAYER_DIFFICULTY_CHANGED = CheckLogging,
		CHALLENGE_MODE_START = CheckLogging,
	},
	enable = CheckLogging,
	disable = function()
		if logStarted and LoggingCombat and LoggingCombat() then
			LoggingCombat(false)
			Soul:Print("Combat logging stopped.")
		end
		logStarted = false
		Q.RestoreCVar("advancedCombatLogging")
	end,
})

------------------------------------------------------------------------------
-- Screenshot when an achievement is earned.
------------------------------------------------------------------------------

Q:Feature({
	key = "achievementShot",
	events = {
		ACHIEVEMENT_EARNED = function(_, _, alreadyEarned)
			if alreadyEarned then return end
			-- Wait for the achievement toast to be on screen.
			C_Timer.After(1.2, function()
				if Screenshot then Screenshot() end
			end)
		end,
	},
})
