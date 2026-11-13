if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}

-- Every feature is one boolean. Since 0.9.14 these are the owner's live
-- switches (the shipped default layout), so several helpers that act for the
-- player start on: repair, junk selling, loot confirmations, opening
-- containers, skipping cinematics, gossip and quests, accepting invites from
-- friends and guild, and summons. Declining duels and invites, accepting
-- resurrections, battleground release and anything that talks in chat start
-- off. The notes on the settings tabs say which is which; keep them in step.
SoulUI.Defaults.QoL = {
	-- Vendors
	autoRepair = true,
	repairGuild = true,
	autoSellJunk = true,
	trainAll = true,

	-- Loot and items
	fastLoot = true,
	confirmBoP = true,
	confirmRolls = true,
	fillDelete = true,
	autoOpen = true,
	autoUnwrap = true,
	autoKeystone = true,

	-- Cinematics and Blizzard popups
	skipCinematics = true,
	cinematicConfirm = true,
	hideTalkingHead = false,
	hideToasts = false,
	hideTutorials = true,
	hideErrors = true,
	hideErrorsCombatOnly = true,
	hideScreenshotMsg = false,

	-- NPCs and quests
	autoGossip = true,
	gossipInInstances = true,
	autoQuestAccept = true,
	autoQuestTurnIn = true,
	questSkipTrivial = true,

	-- Group and social
	declineDuels = false,
	declinePetDuels = false,
	declineGuildInvites = false,
	acceptInvites = true,
	acceptSummon = true,
	acceptRes = false,
	acceptResCombat = false,
	releaseBG = false,
	announceReset = false,

	-- Chat
	chatUrls = true,
	chatCopy = true,

	-- Logging and screenshots
	combatLog = false,
	achievementShot = false,

	-- Camera
	maxZoom = false,

	-- On-screen trackers (each is movable in /soul move)
	combatTimer = false,
	combatTimerPrint = true,
	combatTimerSize = 18,
	combatAlert = false,
	combatAlertSize = 24,
	durability = true,
	durabilityThreshold = 25,
	durabilitySize = 18,
	fps = false,
	fpsSize = 13,
	stats = false,
	statsSize = 13,
	deathAlert = false,
	deathAlertSound = true,
	deathAlertSize = 20,
	brez = true,
	brezSize = 36,
	sated = true,
	satedSize = 36,
	crosshair = false,
	crosshairCombat = true,
	crosshairSize = 24,
	crosshairColor = { 1, 1, 1 },
	cursorRing = false,
	cursorRingCombat = false,
	cursorRingSize = 48,
	charIlvl = false,
	mapCoords = false,

	-- Raid
	pullTimer = true,
	pullSize = 24,
	raidMarkers = false,
	buffCheck = false,
	partyKeys = true,

	-- Tools
	shifter = false,
	shifterPos = {},
	waypoints = true,
	chatCover = false,
	targetDistance = false,
	distanceSize = 13,
	rested = false,
	restedSize = 13,
	potionReady = false,
	potionSize = 36,
	unspentTalents = false,
	talentsSize = 13,
	combatText = false,
	moveAlert = false,
	moveSize = 36,
	cursorTrail = false,
	gcdRing = false,
	gcdRingSize = 40,

	-- Skins
	questSkin = false,
	minimapSquare = false,
	chatSkin = false,
}
