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
local function Toggle(label, key, tooltip)
	return {
		type = "toggle", label = label, tooltip = tooltip,
		get = function() return DB()[key] and true or false end,
		set = function(v) DB()[key] = v and true or false Apply() end,
	}
end

local function BuildRaid(col)
	if Missing(col) then return end
	W.Note(col, "World marker buttons are set up once, so they keep working after combat starts. The pull timer types in party or raid chat.")
	W.Section(col, "Pull and markers")
	W.Row2(col,
		Toggle("Pull timer", "pullTimer", "Type /soulpull 10. It counts down in the middle of the screen and says it in chat."),
		Toggle("World markers", "raidMarkers", "Eight marker buttons and a clear button. Move the bar in edit mode."))
	W.Section(col, "Group")
	W.Row2(col,
		Toggle("Buff check", "buffCheck", "When a ready check starts, lists how many helpful auras each person is showing. Hidden auras are marked hidden instead of guessed."),
		Toggle("Your keystone", "partyKeys", "Shows the keystone in your bags. /soulkeys opens it. Other people's keys are not available from the game, so this is yours."))
end

local function BuildTools(col)
	if Missing(col) then return end
	W.Section(col, "Windows and map")
	W.Row2(col,
		Toggle("Shift-drag windows", "shifter", "Hold Shift and drag the character, spellbook, professions, map, group finder, or friends window. The spot is remembered."),
		Toggle("Map pins", "waypoints", "/way 45.2 67.8 drops a pin on the current map and tracks it."))
	W.Row2(col,
		Toggle("Cover chat", "chatCover", "Covers the main chat window until you mouse over it."),
		Toggle("Target distance", "targetDistance", "Yards to your target, when the game gives a plain number."))
	W.Section(col, "Reminders")
	W.Row2(col,
		Toggle("Rested", "rested", "Shows while you have rested experience."),
		Toggle("Healthstone ready", "potionReady", "Shows a healthstone icon and its cooldown."))
	W.Row2(col,
		Toggle("Unspent talents", "unspentTalents"),
		Toggle("Movement cooldown", "moveAlert", "Shows the first movement spell you know from a short list (Blink, Sprint, Heroic Leap, and a few others)."))
	W.Row2(col,
		Toggle("Floating combat text font", "combatText", "Uses the SoulUI font on the game's own scrolling combat text. It does not read the combat log."),
		Toggle("Cursor trail", "cursorTrail"))
	W.Row(col, Toggle("GCD ring on the cursor", "gcdRing", "A ring on the mouse that shows the global cooldown."))
end

local function BuildSkins(col)
	if Missing(col) then return end
	W.Note(col, "These restyle Blizzard's frames. They do not replace the quest tracker, the minimap, or chat.")
	W.Section(col, "Skins")
	W.Row2(col,
		Toggle("Quest tracker font", "questSkin", "Applies the SoulUI font to the objective tracker header."),
		Toggle("Square minimap", "minimapSquare", "A square mask and a thin border. Turning it off puts the old mask back when the game still has it."))
	W.Row(col, Toggle("Chat font and background", "chatSkin", "SoulUI font on the chat windows, and a darker background. Message text is left alone."))
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
