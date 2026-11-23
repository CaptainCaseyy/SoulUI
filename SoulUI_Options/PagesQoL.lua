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
	W.Note(col, "All four are on by default. Repair only spends gold on a repair, junk selling only sells gray items, and Train All only buys when you click it.")
	W.Section(col, "Vendors")
	W.Row2(col,
		Toggle("Repair at vendors", "autoRepair", "Repairs all gear when a repair vendor opens, and prints the cost."),
		Toggle("Use guild bank first", "repairGuild", "Tries the guild bank, then your own gold if the bank cannot cover it.", Off("autoRepair")))
	W.Row2(col,
		Toggle("Sell junk", "autoSellJunk", "Sells gray items that have a vendor price when a vendor opens. A few at a time, so a full bag does not freeze the game."),
		Toggle("Train all button", "trainAll", "Adds a Train All button on the trainer window. It learns every skill you can afford when you click it."))
end

local function BuildItems(col)
	if Missing(col) then return end
	W.Note(col, "These act for you without asking, and all of them are on by default. Turn off any you would rather do by hand.")
	W.Section(col, "Loot and items")
	W.Row2(col,
		Toggle("Faster loot", "fastLoot", "When auto loot applies, takes every item at once instead of one by one."),
		Toggle("Confirm bind on pickup", "confirmBoP", "Accepts the bind-on-pickup warning when you loot."))
	W.Row2(col,
		Toggle("Confirm loot rolls", "confirmRolls", "Accepts the bind warning after you choose need, greed or disenchant."),
		Toggle("Fill in DELETE", "fillDelete", "Types DELETE for you when destroying a good item. You still click to confirm."))
	W.Row2(col,
		Toggle("Open containers", "autoOpen", "Opens caches, clams and other containers in your bags, one at a time, out of combat. Locked boxes are skipped, and nothing opens while a vendor, bank, mailbox, auction house or trade window is open."),
		Toggle("Unwrap new mounts and pets", "autoUnwrap", "A new mount or pet is ready in the collection without the unwrap click."))
	W.Row(col, Toggle("Slot a keystone", "autoKeystone", "Puts your keystone into the Font of Power when you open it."))
end

local function BuildWorld(col)
	if Missing(col) then return end
	W.Note(col, "Skipping cinematics, hiding tutorials, hiding error text in combat, and the NPC and quest helpers are on by default. Hiding talking heads, event banners and the screenshot line, and the camera zoom, start off.")
	W.Section(col, "Cinematics and notices")
	W.Row2(col,
		Toggle("Skip cinematics", "skipCinematics", "Skips every movie and in-game cinematic that can be skipped, including ones you have not seen yet."),
		Toggle("Skip without asking", "cinematicConfirm", "When you press Escape during a cinematic or movie, it ends at once instead of asking 'are you sure'."))
	W.Row2(col,
		Toggle("Hide talking heads", "hideTalkingHead", "Closes the talking-head popup (NPC portrait and voice line) as soon as it starts."),
		Toggle("Hide event banners", "hideToasts", "Closes the large banners at the top of the screen: level up, new zone, renown and similar."))
	W.Row2(col,
		Toggle("Hide tutorials", "hideTutorials", "Turns off the game's tutorial tips. Turning this off puts your old setting back."),
		Toggle("Hide error text", "hideErrors", "Hides the red error text in the middle of the screen. Full bags, a full quest log and not enough gold still show."))
	W.Row2(col,
		Toggle("Errors only in combat", "hideErrorsCombatOnly", "Hides the error text only while you are in combat. Out of combat it shows as normal.", Off("hideErrors")),
		Toggle("Hide screenshot text", "hideScreenshotMsg", "Hides the 'screenshot saved' line."))
	W.Section(col, "NPCs and quests")
	W.Note(col, "Hold Shift while talking to an NPC and nothing is chosen or accepted for you.")
	W.Row2(col,
		Toggle("Pick the only gossip option", "autoGossip", "Chooses the dialog option when an NPC has only one. Skipped when the NPC has quests, or when the option is in red (a warning)."),
		Toggle("Also inside instances", "gossipInInstances", "The gossip helper also runs in dungeons and raids.", Off("autoGossip")))
	W.Row2(col,
		Toggle("Accept quests", "autoQuestAccept", "Accepts quests that are offered, and picks them from an NPC's list."),
		Toggle("Turn in quests", "autoQuestTurnIn", "Hands in finished quests. A choice of rewards, or a quest that costs gold, is left to you."))
	W.Row(col, Toggle("Skip trivial quests", "questSkipTrivial", "Gray (low level) quests are not picked from an NPC's list."))
	W.Section(col, "Camera")
	W.Row(col, Toggle("Maximum camera zoom", "maxZoom", "Raises the camera distance limit to the game's maximum. Turning this off puts your old setting back."))
end

local function BuildGroup(col)
	if Missing(col) then return end
	W.Note(col, "Accepting group invites and summons is on by default. Declining, resurrection, battleground release, the reset message, logging and screenshots start off.")
	W.Section(col, "Invites and summons")
	W.Row2(col,
		Toggle("Decline duels", "declineDuels", "Declines every duel request and prints who sent it."),
		Toggle("Decline pet duels", "declinePetDuels", "Declines every pet battle duel request."))
	W.Row2(col,
		Toggle("Decline guild invites", "declineGuildInvites", "Declines every guild invite and prints who sent it."),
		Toggle("Accept group invites", "acceptInvites", "Accepts party and raid invites from friends, Battle.net friends and guild members. Not while you are queued or listed in the group finder."))
	W.Row2(col,
		Toggle("Accept summons", "acceptSummon", "Accepts a summon (warlock or meeting stone) right away, unless you are in combat."),
		Toggle("Accept resurrection", "acceptRes", "Accepts a resurrection, unless a boss fight is on or the caster is still in combat."))
	W.Row(col, Toggle("Accept resurrection in combat", "acceptResCombat", "Accepts a resurrection while you are still in combat.", Off("acceptRes")))
	W.Section(col, "Battlegrounds and resets")
	W.Row2(col,
		Toggle("Release in battlegrounds", "releaseBG", "Releases your spirit after you die in a battleground, unless a soulstone or similar self-resurrection is offered."),
		Toggle("Announce instance reset", "announceReset", "Posts the game's 'has been reset' line in party or raid chat when your reset works."))
	W.Section(col, "Logging")
	W.Row2(col,
		Toggle("Combat log in raids and keys", "combatLog", "Turns combat logging on in normal, heroic and mythic raids, mythic dungeons and keystones, and off when you leave. Also turns on advanced combat logging."),
		Toggle("Screenshot achievements", "achievementShot", "Takes a screenshot when you earn an achievement."))
end

local function BuildChat(col)
	if Missing(col) then return end
	W.Note(col, "Both are on by default.")
	W.Section(col, "Chat")
	W.Row2(col,
		Toggle("Clickable web links", "chatUrls", "Turns web addresses in chat into links. Clicking one opens it in a box you can copy from (the game cannot open a browser)."),
		Toggle("Copy chat", "chatCopy", "Adds a button on each chat window that opens the text so you can copy it."))
end

local function BuildTrackers(col)
	if Missing(col) then return end
	W.Note(col, "Each tracker can be moved and scaled in edit mode (/soul move). Turning one on shows it there even before it has something to say. Low durability, battle res and Sated are on by default; the rest start off.")
	W.Section(col, "Combat")
	W.Row2(col,
		Toggle("Combat timer", "combatTimer", "A timer while you are in combat."),
		Toggle("Print the length", "combatTimerPrint", "Prints how long the fight was when combat ends.", Off("combatTimer")))
	W.Row(col, Slider("Timer size", "combatTimerSize", 10, 48, 1, nil, Off("combatTimer")))
	W.Row2(col,
		Toggle("Combat alert", "combatAlert", "A short '+ Combat' and '- Combat' in the middle of the screen."),
		Slider("Alert size", "combatAlertSize", 12, 64, 1, nil, Off("combatAlert")))
	W.Row2(col,
		Toggle("Group death alert", "deathAlert", "Names a group member when they die. There is no combat log, so this watches health."),
		Toggle("Warning sound", "deathAlertSound", nil, Off("deathAlert")))
	W.Row(col, Slider("Death alert size", "deathAlertSize", 12, 56, 1, nil, Off("deathAlert")))
	W.Section(col, "Gear and performance")
	W.Row2(col,
		Toggle("Low durability", "durability", "Shows when a piece of gear is worn down."),
		Slider("Warn below %", "durabilityThreshold", 5, 80, 5, nil, Off("durability")))
	W.Row(col, Slider("Durability size", "durabilitySize", 10, 48, 1, nil, Off("durability")))
	W.Row2(col,
		Toggle("Frames per second", "fps"),
		Slider("FPS size", "fpsSize", 8, 32, 1, nil, Off("fps")))
	W.Row2(col,
		Toggle("Secondary stats", "stats", "Crit, haste, mastery and versatility."),
		Slider("Stats size", "statsSize", 8, 32, 1, nil, Off("stats")))
	W.Row2(col,
		Toggle("Item level on the character sheet", "charIlvl"),
		Toggle("Coordinates on the map", "mapCoords"))
	W.Section(col, "Raid")
	W.Row2(col,
		Toggle("Battle resurrection", "brez", "The shared battle-res charges and the time to the next one, during a keystone or a boss fight."),
		Slider("Icon size", "brezSize", 20, 96, 1, nil, Off("brez")))
	W.Row2(col,
		Toggle("Sated and Exhaustion", "sated", "Shows while you cannot benefit from Bloodlust or Heroism."),
		Slider("Sated size", "satedSize", 20, 96, 1, nil, Off("sated")))
	W.Section(col, "Cursor")
	W.Row2(col,
		Toggle("Crosshair", "crosshair", "A small crosshair in the middle of the screen."),
		Toggle("Only in combat", "crosshairCombat", nil, Off("crosshair")))
	W.Row(col, Slider("Crosshair size", "crosshairSize", 8, 128, 1, nil, Off("crosshair")))
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
