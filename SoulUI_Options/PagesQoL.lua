if SoulUI_Blocked or not SoulUI then return end

-- Quality of life page. Every switch writes the live setting and calls Apply,
-- which turns that feature on or off without a reload.

local Soul = SoulUI
local W = Soul.Widgets

local function Mod() return Soul:GetModule("QoL") end
local function DB() return Soul:ModuleDB("QoL") end

local function Apply()
	local mod = Mod()
	if mod and mod.Apply then mod:Apply() end
end

local function Missing(col)
	if Mod() then return false end
	W.Note(col, "Quality of Life is turned off. Turn it on under General > Modules.")
	return true
end

local function Off(key)
	return function()
		if not Mod() then return true end
		if key and not DB()[key] then return true end
		return false
	end
end

local function Toggle(label, key, tooltip, disabled)
	return {
		type = "toggle", label = label, tooltip = tooltip, disabled = disabled,
		get = function() return DB()[key] and true or false end,
		set = function(v) DB()[key] = v and true or false Apply() end,
	}
end

local function Slider(label, key, lo, hi, step, tooltip, disabled)
	return {
		type = "slider", label = label, min = lo, max = hi, step = step or 1, tooltip = tooltip,
		disabled = disabled,
		get = function() return DB()[key] end,
		set = function(v) DB()[key] = v Apply() end,
	}
end

local function BuildVendors(col)
	if Missing(col) then return end
	W.Note(col, "Repair and selling gray items are on by default. They only spend gold on a repair, or sell items that are already junk.")
	W.Section(col, "Vendors")
	W.Row2(col,
		Toggle("Repair at vendors", "autoRepair", "Repairs all gear when a repair vendor opens."),
		Toggle("Use guild bank first", "repairGuild", "Tries the guild bank, then your own gold if the bank cannot cover it.", Off("autoRepair")))
	W.Row2(col,
		Toggle("Sell junk", "autoSellJunk", "Sells gray items that have a vendor price. A few at a time, so a full bag does not freeze the game."),
		Toggle("Train all button", "trainAll", "Adds a Train All button on the class trainer."))
end

local function BuildItems(col)
	if Missing(col) then return end
	W.Note(col, "These act for you. They start off. Hold Shift to skip one.")
	W.Section(col, "Loot and items")
	W.Row2(col,
		Toggle("Faster loot", "fastLoot", "Loots everything as soon as a corpse opens."),
		Toggle("Confirm bind on pickup", "confirmBoP", "Accepts the bind-on-pickup warning."))
	W.Row2(col,
		Toggle("Confirm loot rolls", "confirmRolls", "Confirms the roll warning when you need, greed or pass."),
		Toggle("Fill in DELETE", "fillDelete", "Types DELETE for you when destroying a rare item. You still confirm."))
	W.Row2(col,
		Toggle("Open containers", "autoOpen", "Opens clams, lockboxes you can open, and similar containers in your bags."),
		Toggle("Unwrap items", "autoUnwrap", "Uses items that only unwrap into something else."))
	W.Row(col, Toggle("Slot a keystone", "autoKeystone", "Puts a mythic keystone into the font when you click it."))
end

local function BuildWorld(col)
	if Missing(col) then return end
	W.Section(col, "Cinematics and notices")
	W.Row2(col,
		Toggle("Skip cinematics", "skipCinematics", "Skips movies and in-game cinematics."),
		Toggle("Confirm the skip", "cinematicConfirm", "Also answers the 'are you sure' skip dialog.", Off("skipCinematics")))
	W.Row2(col,
		Toggle("Hide talking heads", "hideTalkingHead", "Closes the talking-head popups."),
		Toggle("Hide loot toasts", "hideToasts", "Hides the achievement and loot toast banners."))
	W.Row2(col,
		Toggle("Hide tutorials", "hideTutorials", "Closes the tutorial boxes."),
		Toggle("Hide error text", "hideErrors", "Hides the red error text in the middle of the screen."))
	W.Row2(col,
		Toggle("Errors only in combat", "hideErrorsCombatOnly", "Keeps the error text out of combat.", Off("hideErrors")),
		Toggle("Hide screenshot text", "hideScreenshotMsg", "Hides the 'screenshot taken' line."))
	W.Section(col, "NPCs and quests")
	W.Note(col, "Hold Shift while talking to an NPC and nothing is chosen or accepted for you.")
	W.Row2(col,
		Toggle("Pick the only gossip option", "autoGossip", "Chooses a gossip option when there is only one."),
		Toggle("Also inside instances", "gossipInInstances", "The gossip helper also runs in dungeons and raids.", Off("autoGossip")))
	W.Row2(col,
		Toggle("Accept quests", "autoQuestAccept", "Accepts quests that are offered."),
		Toggle("Turn in quests", "autoQuestTurnIn", "Hands in quests. A choice of rewards, or a quest that costs gold, is left to you."))
	W.Row(col, Toggle("Skip trivial quests", "questSkipTrivial", "Does not auto-accept gray quests."))
	W.Section(col, "Camera")
	W.Row(col, Toggle("Maximum camera zoom", "maxZoom", "Raises the camera distance limit."))
end

local function BuildGroup(col)
	if Missing(col) then return end
	W.Section(col, "Invites and summons")
	W.Row2(col,
		Toggle("Decline duels", "declineDuels"),
		Toggle("Decline pet duels", "declinePetDuels"))
	W.Row2(col,
		Toggle("Decline guild invites", "declineGuildInvites"),
		Toggle("Accept group invites", "acceptInvites", "Accepts party and raid invites."))
	W.Row2(col,
		Toggle("Accept summons", "acceptSummon", "Accepts a warlock or meeting-stone summon."),
		Toggle("Accept resurrection", "acceptRes", "Accepts a resurrection out of combat."))
	W.Row(col, Toggle("Also during combat", "acceptResCombat", "Accepts a resurrection while you are still in combat.", Off("acceptRes")))
	W.Section(col, "Battlegrounds and resets")
	W.Row2(col,
		Toggle("Release in battlegrounds", "releaseBG", "Releases your spirit after you die in a battleground."),
		Toggle("Announce instance reset", "announceReset", "Says in party or raid chat when you reset the instance."))
	W.Section(col, "Logging")
	W.Row2(col,
		Toggle("Combat log in raids and keys", "combatLog", "Turns combat logging on in raids and mythic dungeons, and off when you leave."),
		Toggle("Screenshot achievements", "achievementShot", "Takes a screenshot when you earn an achievement."))
end

local function BuildChat(col)
	if Missing(col) then return end
	W.Section(col, "Chat")
	W.Row2(col,
		Toggle("Clickable web links", "chatUrls", "Turns http links in chat into links you can click."),
		Toggle("Copy chat", "chatCopy", "Adds a button on each chat window that opens the text so you can copy it."))
end

local function BuildTrackers(col)
	if Missing(col) then return end
	W.Note(col, "Each tracker can be moved and scaled in edit mode (/soul move). Turning one on shows it there even before it has something to say.")
	W.Section(col, "Combat")
	W.Row2(col,
		Toggle("Combat timer", "combatTimer", "A timer while you are in combat."),
		Toggle("Print the length", "combatTimerPrint", "Prints how long the fight was when combat ends.", Off("combatTimer")))
	W.Row(col, Slider("Timer size", "combatTimerSize", 10, 40, 1, nil, Off("combatTimer")))
	W.Row2(col,
		Toggle("Combat alert", "combatAlert", "A short '+ Combat' and '- Combat' in the middle of the screen."),
		Slider("Alert size", "combatAlertSize", 12, 48, 1, nil, Off("combatAlert")))
	W.Row2(col,
		Toggle("Group death alert", "deathAlert", "Names a group member when they die. There is no combat log, so this watches health."),
		Toggle("Warning sound", "deathAlertSound", nil, Off("deathAlert")))
	W.Row(col, Slider("Death alert size", "deathAlertSize", 12, 48, 1, nil, Off("deathAlert")))
	W.Section(col, "Gear and performance")
	W.Row2(col,
		Toggle("Low durability", "durability", "Shows when a piece of gear is worn down."),
		Slider("Warn below %", "durabilityThreshold", 5, 80, 5, nil, Off("durability")))
	W.Row(col, Slider("Durability size", "durabilitySize", 10, 36, 1, nil, Off("durability")))
	W.Row2(col,
		Toggle("Frames per second", "fps"),
		Slider("FPS size", "fpsSize", 10, 28, 1, nil, Off("fps")))
	W.Row2(col,
		Toggle("Secondary stats", "stats", "Crit, haste, mastery and versatility."),
		Slider("Stats size", "statsSize", 10, 28, 1, nil, Off("stats")))
	W.Row2(col,
		Toggle("Item level on the character sheet", "charIlvl"),
		Toggle("Coordinates on the map", "mapCoords"))
	W.Section(col, "Raid")
	W.Row2(col,
		Toggle("Battle resurrection", "brez", "The shared raid battle-res charges."),
		Slider("Icon size", "brezSize", 20, 64, 1, nil, Off("brez")))
	W.Row2(col,
		Toggle("Sated and Exhaustion", "sated", "Shows while you cannot benefit from Bloodlust or Heroism."),
		Slider("Sated size", "satedSize", 20, 64, 1, nil, Off("sated")))
	W.Section(col, "Cursor")
	W.Row2(col,
		Toggle("Crosshair", "crosshair", "A small crosshair in the middle of the screen."),
		Toggle("Only in combat", "crosshairCombat", nil, Off("crosshair")))
	W.Row(col, Slider("Crosshair size", "crosshairSize", 8, 64, 1, nil, Off("crosshair")))
	W.Row(col, {
		type = "color", label = "Crosshair color", disabled = Off("crosshair"),
		get = W.ColorGet(DB, "crosshairColor", 1, 1, 1),
		set = W.ColorSet(DB, "crosshairColor", Apply),
	})
	W.Row2(col,
		Toggle("Cursor ring", "cursorRing", "A ring that follows the mouse."),
		Toggle("Only in combat", "cursorRingCombat", nil, Off("cursorRing")))
	W.Row(col, Slider("Ring size", "cursorRingSize", 16, 128, 1, nil, Off("cursorRing")))
	W.Buttons(col, {
		{ text = "Move in Edit Mode", width = 180, click = function()
			Soul.Options.Close()
			Soul:OpenUnlock()
		end },
	})
end

Soul:RegisterPage({
	key = "qol",
	title = "Quality of Life",
	description = "Small helpers. Each one turns on and off immediately.",
	group = "Utility",
	groupOrder = 4,
	order = 2,
	addon = "SoulUI_QoL",
	tabs = {
		{ key = "vendors", title = "Vendors", build = BuildVendors },
		{ key = "items", title = "Items", build = BuildItems },
		{ key = "world", title = "World", build = BuildWorld },
		{ key = "group", title = "Group", build = BuildGroup },
		{ key = "chat", title = "Chat", build = BuildChat },
		{ key = "trackers", title = "Trackers", build = BuildTrackers },
	},
	reset = function()
		local defaults = Soul.Defaults and Soul.Defaults.QoL
		if not defaults or not Mod() then return end
		Soul:ActiveProfile().modules.QoL = Soul:Copy(defaults)
		Apply()
	end,
})
