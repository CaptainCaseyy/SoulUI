if SoulUI_Blocked or not SoulUI then return end

-- Extra quality-of-life tabs, attached after the main page has registered.

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
		return not DB()[key]
	end
end
local function Toggle(label, key, tooltip, disabled)
	return {
		type = "toggle", label = label, tooltip = tooltip, disabled = disabled,
		get = function() return DB()[key] and true or false end,
		set = function(v) DB()[key] = v and true or false Apply() end,
	}
end
local function Slider(label, key, lo, hi, tooltip, disabled)
	return {
		type = "slider", label = label, min = lo, max = hi, step = 1, tooltip = tooltip,
		disabled = disabled,
		get = function() return DB()[key] end,
		set = function(v) DB()[key] = v Apply() end,
	}
end

local function BuildRaid(col)
	if Missing(col) then return end
	W.Note(col, "The pull timer and the keystone window are on by default; they only act when you type their command. World markers and the buff check start off.")
	W.Section(col, "Pull and markers")
	W.Row2(col,
		Toggle("Pull timer", "pullTimer", "Type /soulpull 10 (1 to 30 seconds). It counts down in the middle of the screen and says it in party or raid chat."),
		Slider("Pull timer size", "pullSize", 14, 48, nil, Off("pullTimer")))
	W.Row(col, Toggle("World markers", "raidMarkers", "Eight world marker buttons and a clear button. They work in combat; the bar can only be moved or hidden out of combat. Move it in edit mode."))
	W.Section(col, "Group")
	W.Row2(col,
		Toggle("Buff check", "buffCheck", "When a ready check starts, lists how many helpful auras each person is showing. When the game hides auras (in combat or restricted content) that person is marked hidden instead of guessed."),
		Toggle("Your keystone", "partyKeys", "/soulkeys shows the keystone in your bags, with a button to say it in party chat. Other people's keys are not available from the game."))
end

local function BuildTools(col)
	if Missing(col) then return end
	W.Note(col, "Map pins are on by default (type /way). Everything else here starts off.")
	W.Section(col, "Windows and map")
	W.Row2(col,
		Toggle("Shift-drag windows", "shifter", "Hold Shift and drag the character, talents and spellbook, professions, map, group finder, friends or communities window. The spot is remembered. Not in combat."),
		Toggle("Map pins", "waypoints", "/way 45.2 67.8 drops a pin on your current zone map and tracks it."))
	W.Row2(col,
		Toggle("Cover chat", "chatCover", "Covers the main chat window until you mouse over it."),
		Toggle("Target distance", "targetDistance", "Yards to your target. The game only measures group members, so nothing shows for anyone else."))
	W.Row(col, Slider("Distance size", "distanceSize", 10, 28, nil, Off("targetDistance")))
	W.Section(col, "Reminders")
	W.Row2(col,
		Toggle("Rested", "rested", "Shows while you have rested experience."),
		Slider("Rested size", "restedSize", 10, 24, nil, Off("rested")))
	W.Row2(col,
		Toggle("Healthstone ready", "potionReady", "Shows a healthstone icon and its cooldown while you carry one."),
		Slider("Healthstone size", "potionSize", 20, 64, nil, Off("potionReady")))
	W.Row2(col,
		Toggle("Unspent talents", "unspentTalents", "Shows while you have talent points to spend."),
		Slider("Talents size", "talentsSize", 10, 24, nil, Off("unspentTalents")))
	W.Row2(col,
		Toggle("Movement cooldown", "moveAlert", "Shows the first movement spell you know from a short list (Blink, Sprint, Heroic Leap, Divine Steed, Aspect of the Cheetah, Demonic Gateway) and its cooldown."),
		Slider("Movement size", "moveSize", 20, 64, nil, Off("moveAlert")))
	W.Section(col, "Cursor and text")
	W.Row2(col,
		Toggle("Floating combat text font", "combatText", "Uses the SoulUI font on the game's own floating combat text (the text over your character). Turning it off puts the old font back."),
		Toggle("Cursor trail", "cursorTrail", "A short trail of dots in your accent color behind the mouse."))
	W.Row2(col,
		Toggle("GCD ring on the cursor", "gcdRing", "A ring on the mouse that sweeps with the global cooldown."),
		Slider("GCD ring size", "gcdRingSize", 24, 96, nil, Off("gcdRing")))
end

local function BuildSkins(col)
	if Missing(col) then return end
	W.Note(col, "These restyle Blizzard's frames and start off. They do not replace the quest tracker, the minimap, or chat, and turning one off puts the old look back.")
	W.Section(col, "Skins")
	W.Row2(col,
		Toggle("Quest tracker font", "questSkin", "Applies the SoulUI font to the objective tracker header and dims its background."),
		Toggle("Square minimap", "minimapSquare", "A square mask and a thin border, with the round frame art hidden."))
	W.Row(col, Toggle("Chat font and background", "chatSkin", "SoulUI font on the chat windows (each window keeps its size), and a darker background."))
end

local pages = Soul.optionPages
for i = 1, #pages do
	local page = pages[i]
	if page.key == "qol" and page.tabs then
		page.tabs[#page.tabs + 1] = { key = "raid", title = "Raid", build = BuildRaid }
		page.tabs[#page.tabs + 1] = { key = "tools", title = "Tools", build = BuildTools }
		page.tabs[#page.tabs + 1] = { key = "skins", title = "Skins", build = BuildSkins }
	end
end
