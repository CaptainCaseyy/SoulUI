if SoulUI_Blocked or not SoulUI then return end

-- Duels, invites, summons, resurrection, battleground release, reset notice.

local Soul = SoulUI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local C_Timer = C_Timer
local type = type

local function Name(value)
	if value == nil or Q.IsSecret(value) then return "someone" end
	return value
end

------------------------------------------------------------------------------
-- Decline duels, pet battle duels and guild invites
------------------------------------------------------------------------------

Q:Feature({
	key = "declineDuels",
	events = {
		DUEL_REQUESTED = function(_, name)
			CancelDuel()
			Q.HidePopup("DUEL_REQUESTED")
			Soul:Print("Declined a duel from " .. Name(name) .. ".")
		end,
	},
})

Q:Feature({
	key = "declinePetDuels",
	events = {
		PET_BATTLE_PVP_DUEL_REQUESTED = function(_, name)
			if not (C_PetBattles and C_PetBattles.CancelPVPDuel) then return end
			C_PetBattles.CancelPVPDuel()
			Q.HidePopup("PET_BATTLE_PVP_DUEL_REQUESTED")
			Soul:Print("Declined a pet battle duel from " .. Name(name) .. ".")
		end,
	},
})

Q:Feature({
	key = "declineGuildInvites",
	events = {
		GUILD_INVITE_REQUEST = function(_, inviter, guildName)
			DeclineGuild()
			if GuildInviteFrame and GuildInviteFrame:IsShown() then GuildInviteFrame:Hide() end
			Q.HidePopup("GUILD_INVITE")
			Soul:Print("Declined a guild invite from " .. Name(inviter) .. " (" .. Name(guildName) .. ").")
		end,
	},
})

------------------------------------------------------------------------------
-- Accept group invites from friends, Battle.net friends and guild members.
------------------------------------------------------------------------------

local function Queued()
	if GetLFGMode then
		for i = 1, (NUM_LE_LFG_CATEGORYS or 0) do
			if GetLFGMode(i) then return true end
		end
	end
	if C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() then return true end
	return false
end

local function Trusted(guid)
	if C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then return true end
	if IsGuildMember and IsGuildMember(guid) then return true end
	if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(guid) then return true end
	return false
end

Q:Feature({
	key = "acceptInvites",
	events = {
		PARTY_INVITE_REQUEST = function(_, name, _, _, _, _, _, inviterGUID)
			if type(inviterGUID) ~= "string" or Q.IsSecret(inviterGUID) then return end
			-- Accepting would drop a queue or a group listing.
			if Queued() then return end
			if not Trusted(inviterGUID) then return end
			AcceptGroup()
			Q.HidePopup("PARTY_INVITE")
			Soul:Print("Accepted a group invite from " .. Name(name) .. ".")
		end,
	},
})

------------------------------------------------------------------------------
-- Accept summons (out of combat only).
------------------------------------------------------------------------------

Q:Feature({
	key = "acceptSummon",
	events = {
		CONFIRM_SUMMON = function()
			local summon = C_SummonInfo
			if not (summon and summon.ConfirmSummon) then return end
			if InCombatLockdown() or UnitAffectingCombat("player") then return end
			local who = summon.GetSummonConfirmSummoner and summon.GetSummonConfirmSummoner()
			local area = summon.GetSummonConfirmAreaName and summon.GetSummonConfirmAreaName()
			summon.ConfirmSummon()
			Q.HidePopup("CONFIRM_SUMMON")
			Soul:Print("Accepted a summon from " .. Name(who) .. " to " .. Name(area) .. ".")
		end,
	},
})

------------------------------------------------------------------------------
-- Accept resurrections. Combat resurrections only when that is switched on.
------------------------------------------------------------------------------

local RES_POPUPS = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }

Q:Feature({
	key = "acceptRes",
	events = {
		RESURRECT_REQUEST = function(_, inviter)
			if not DB().acceptResCombat then
				if IsEncounterInProgress and IsEncounterInProgress() then return end
				if type(inviter) == "string" and not Q.IsSecret(inviter) then
					local busy = UnitAffectingCombat(inviter)
					if Q.IsSecret(busy) or busy then return end
				end
			end
			AcceptResurrect()
			C_Timer.After(1, function()
				if UnitIsDeadOrGhost("player") then return end
				for i = 1, #RES_POPUPS do Q.HidePopup(RES_POPUPS[i]) end
			end)
		end,
	},
})

------------------------------------------------------------------------------
-- Release in battlegrounds. Never when a self-resurrection (soulstone,
-- Reincarnation, ...) is on offer.
------------------------------------------------------------------------------

Q:Feature({
	key = "releaseBG",
	events = {
		PLAYER_DEAD = function()
			local _, instanceType = IsInInstance()
			if instanceType ~= "pvp" then return end
			C_Timer.After(0.6, function()
				if not UnitIsDeadOrGhost("player") or UnitIsGhost("player") then return end
				local options = C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions and C_DeathInfo.GetSelfResurrectOptions()
				if type(options) == "table" and #options > 0 then return end
				RepopMe()
			end)
		end,
	},
})

------------------------------------------------------------------------------
-- Tell the group when an instance reset worked.
------------------------------------------------------------------------------

local resetPattern

local function ResetPattern()
	if resetPattern ~= nil then return resetPattern end
	local text = INSTANCE_RESET_SUCCESS
	if type(text) ~= "string" then
		resetPattern = false
		return false
	end
	local escaped = text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	resetPattern = "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
	return resetPattern
end

Q:Feature({
	key = "announceReset",
	events = {
		CHAT_MSG_SYSTEM = function(_, text)
			if type(text) ~= "string" or Q.IsSecret(text) then return end
			if not IsInGroup() then return end
			local pattern = ResetPattern()
			if not pattern then return end
			local instance = text:match(pattern)
			if instance then Q.SendGroup(text) end
		end,
	},
})
