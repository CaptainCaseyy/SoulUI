if SoulUI_Blocked or not SoulUI then return end

-- Bags page (SoulUI_Bags). Every control writes the live Bags settings and
-- calls the module's Apply, so an open bag window changes immediately.

local Soul = SoulUI
local W = Soul.Widgets

local function Mod() return Soul:GetModule("Bags") end
local function DB() return Soul:ModuleDB("Bags") end
local function Bool(v) return v and true or false end

local function Apply()
	local mod = Mod()
	if mod and mod.Apply then mod:Apply() end
end

local function Missing(col)
	if Mod() then return false end
	W.Note(col, "Bags is turned off. Turn it on under General > Modules.")
	return true
end

local function Off() return not DB().enabled end

local function Toggle(label, key, tooltip, disabled)
	return {
		type = "toggle", label = label, tooltip = tooltip, disabled = disabled or Off,
		get = function() return DB()[key] and true or false end,
		set = function(v) DB()[key] = Bool(v) Apply() end,
	}
end

local function Slider(label, key, lo, hi, step, tooltip, disabled)
	return {
		type = "slider", label = label, min = lo, max = hi, step = step or 1, tooltip = tooltip,
		disabled = disabled or Off,
		get = function() return DB()[key] end,
		set = function(v) DB()[key] = v Apply() end,
	}
end

local function Dropdown(label, key, items, tooltip, disabled)
	return {
		type = "dropdown", label = label, items = items, tooltip = tooltip, disabled = disabled or Off,
		get = function() return DB()[key] end,
		set = function(v) DB()[key] = v Apply() end,
	}
end

local SORT_ITEMS = {
	{ value = "quality", label = "Quality, then item level" },
	{ value = "ilvl", label = "Item level" },
	{ value = "name", label = "Name" },
	{ value = "type", label = "Item type" },
	{ value = "none", label = "Bag order" },
}

local EMPTY_ITEMS = {
	{ value = "one", label = "One slot with a count" },
	{ value = "all", label = "Every free slot" },
	{ value = "none", label = "Hidden" },
}

local ILVL_ITEMS = {
	{ value = "TOPLEFT", label = "Top left" },
	{ value = "TOP", label = "Top" },
	{ value = "TOPRIGHT", label = "Top right" },
	{ value = "CENTER", label = "Center" },
	{ value = "BOTTOMLEFT", label = "Bottom left" },
}

local QUALITY_ITEMS = {
	{ value = 0, label = "Poor and up" },
	{ value = 1, label = "Common and up" },
	{ value = 2, label = "Uncommon and up" },
	{ value = 3, label = "Rare and up" },
	{ value = 4, label = "Epic and up" },
	{ value = 5, label = "Legendary" },
}

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function BuildWindow(col)
	if Missing(col) then return end
	W.Section(col, "Bags")
	W.Row(col, {
		type = "toggle", label = "Use SoulUI bags",
		tooltip = "Replaces Blizzard's bag windows with one SoulUI window. Turn it off to get the stock bags back right away.",
		get = function() return DB().enabled and true or false end,
		set = function(v) DB().enabled = Bool(v) Apply() end,
	})
	W.Buttons(col, {
		{ text = "Open bags", width = 150, disabled = Off, click = function()
			local mod = Mod()
			if mod and mod.Open then mod:Open() end
		end },
		{ text = "Move in Edit Mode", width = 180, click = function()
			Soul.Options.Close()
			Soul:OpenUnlock()
		end },
	})

	W.Section(col, "Layout")
	W.Row2(col,
		Dropdown("Style", "style", {
			{ value = "combined", label = "One bag, by category" },
			{ value = "bags", label = "One block per bag" },
			{ value = "list", label = "List" },
		}, "Combined is the category grid. Per bag keeps each bag together. List is one row per item."),
		Toggle("Category sidebar", "sidebar", "A column of category filters on the left of the combined and list views."))
	W.Row2(col,
		Toggle("Remember other characters", "offline", "After you open bags on a character, Alts in the footer lists what that character was carrying."),
		Toggle("Gold history", "goldHistory", "The Gold button in the footer shows recent gold changes on this character."))
	W.Row2(col,
		Toggle("Split stacks", "splitStack", "Shift-right-click a stack, type how many, and the game picks that stack up."),
		Toggle("Quick action", "quickAction", "A small button on the hovered item. Click it to cast the spell below on that item. Hidden in combat."))
	-- A spell id is typed, not dragged on a slider.
	local spellRow = W.Input(col, "Quick action spell id", "Set", function(text, box)
		local id = tonumber(text)
		if id and id >= 1 and id == math.floor(id) then
			DB().quickSpell = id
			Apply()
		end
		box:SetText(tostring(DB().quickSpell or 13262))
	end, 120)
	spellRow.box:SetText(tostring(DB().quickSpell or 13262))
	W.Note(col, "13262 is Disenchant. The quick action shows only for a spell you know.")
	W.Note(col, "Alt-click a slot to pin that item into the Pinned section.")
	W.Row2(col,
		Slider("Columns", "columns", 4, 24, 1, "How many slots fit across the window."),
		Slider("Slot size", "iconSize", 24, 64, 1, "Size of one item slot. The scroll wheel over the bags in edit mode changes it too."))
	W.Row2(col,
		Slider("Slot spacing", "spacing", 0, 12, 1),
		Slider("Section spacing", "sectionGap", 0, 32, 1, "Space between sections."))
	W.Row2(col,
		Slider("Padding", "padding", 4, 32, 1, "Space between the window edge and the slots."),
		{
			type = "slider", label = "Scale", min = 0.5, max = 2, step = 0.05, disabled = Off,
			tooltip = "On top of the settings window scale, which the bags follow so both look the same size.",
			get = function() return DB().scale end,
			set = function(v) DB().scale = v Apply() end,
		})
	W.Row2(col,
		{
			type = "slider", label = "Background opacity", min = 0.5, max = 1, step = 0.01, disabled = Off,
			get = function() return DB().bgAlpha end,
			set = function(v) DB().bgAlpha = v Apply() end,
		},
		Slider("Max height", "maxHeight", 360, 1200, 10,
			"The tallest the bag window grows. Past it, the items scroll (mouse wheel). Never more than 85% of the screen."))

	W.Section(col, "Header and footer")
	W.Row2(col,
		Toggle("Search box", "search", "Searches by name and by the game's search words (for example \"boe\" or \"reagent\")."),
		Toggle("Bag slots bar", "bagBar", "Shows your equipped bags under the header. The bag button in the header toggles it too."))
	W.Row2(col,
		Toggle("Tracked currencies", "currencies", "Shows the currencies you track in the currency tab (up to three)."),
		Toggle("Gold", "gold"))
	W.Row(col, Toggle("Clean up on open", "autoSort",
		"Runs the game's own bag sort each time the bags open (at most every 5 seconds, never in combat). The window already shows items in the sort order below without moving them."))
end

------------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------------

local function BuildItems(col)
	if Missing(col) then return end
	local function noCats() return Off() or not DB().categories end

	W.Section(col, "Sections")
	W.Row2(col,
		Toggle("Group into categories", "categories", "Splits the bags into sections: new, equipment, consumables, quest, reagents and more."),
		Toggle("Pack small sections", "packSections", "Small sections sit side by side instead of each starting a new row.", noCats))
	-- Titles also head each bag in the per-bag style.
	local function noTitles() return Off() or (not DB().categories and DB().style ~= "bags") end
	W.Row2(col,
		Toggle("Section titles", "sectionTitles", nil, noTitles),
		Slider("Title size", "titleSize", 9, 18, 1, nil, noTitles))
	W.Row2(col,
		Dropdown("Order inside a section", "sortMode", SORT_ITEMS, "Only the order on screen. Items do not move inside your bags."),
		Dropdown("Free slots", "emptyMode", EMPTY_ITEMS, "One slot with a count keeps the window short. Drop an item on it to put it in that slot."))

	W.Section(col, "Categories")
	local mod = Mod()
	local list = mod and mod.CATEGORIES or {}
	local pending
	for i = 1, #list do
		local c = list[i]
		if c.tip then
			local spec = {
				type = "toggle", label = c.label, tooltip = c.tip, disabled = noCats,
				get = function() return DB().cats[c.key] and true or false end,
				set = function(v) DB().cats[c.key] = Bool(v) Apply() end,
			}
			if pending then
				W.Row2(col, pending, spec)
				pending = nil
			else
				pending = spec
			end
		end
	end
	if pending then W.Row2(col, pending) end
	W.Note(col, "A category that is off puts its items under Items.")

	W.Section(col, "Item slots")
	W.Row2(col,
		Toggle("Item level", "itemLevel", "Item level on weapons, armor and profession gear."),
		Slider("Item level size", "ilvlSize", 8, 20, 1, nil, function() return Off() or not DB().itemLevel end))
	W.Row2(col,
		Dropdown("Item level position", "ilvlAnchor", ILVL_ITEMS, nil, function() return Off() or not DB().itemLevel end),
		Toggle("Color item level by quality", "ilvlQualityColor", nil, function() return Off() or not DB().itemLevel end))
	W.Row2(col,
		Toggle("Bind text", "bindText", "BoE, BoU or WuE (warbound until equipped) on gear that is not bound yet."),
		Slider("Stack count size", "countSize", 8, 20, 1))
	W.Row2(col,
		Toggle("Quality borders", "qualityBorders", "Colors the slot border by item quality."),
		Dropdown("Border from", "qualityMin", QUALITY_ITEMS, nil, function() return Off() or not DB().qualityBorders end))
	W.Row2(col,
		Toggle("Quest items", "questMarks", "A gold border on quest items and a mark on items that start a quest."),
		Toggle("Grey out junk", "junkGrey", "Desaturates and dims poor quality items. A Sell junk button shows at a vendor."))

	W.Section(col, "New items")
	W.Row2(col,
		Toggle("Glow on new items", "newGlow", "A soft pulsing rim on items you just picked up. Hovering an item clears it."),
		Toggle("Clear new items when closing", "clearNewOnClose"))
	local function noGlow() return Off() or not DB().newGlow end
	W.Row2(col,
		Toggle("Use the accent color", "newGlowAccent", nil, noGlow),
		{
			type = "color", label = "Glow color",
			disabled = function() return noGlow() or DB().newGlowAccent end,
			get = W.ColorGet(DB, "newGlowColor", 1, 0.82, 0.32),
			set = W.ColorSet(DB, "newGlowColor", Apply),
		})
end

------------------------------------------------------------------------------
-- Bank
------------------------------------------------------------------------------

local function BuildBank(col)
	if Missing(col) then return end
	local function noBank() return Off() or not DB().bank end
	W.Section(col, "Bank")
	W.Row(col, Toggle("Use SoulUI bank", "bank",
		"Shows the bank and warband bank in a SoulUI window, one tab at a time. Blizzard's bank stays one click away (Blizzard bank) for buying tabs and tab settings."))
	W.Row(col, Slider("Bank columns", "bankColumns", 7, 24, 1, "A bank tab has 98 slots: 14 columns make 7 rows.", noBank))
	W.Note(col, "Right-clicking a bag item at the bank deposits into the bank Blizzard has active, usually the character bank. On the Warband side use Deposit warbound.")
	W.Buttons(col, {
		{ text = "Move in Edit Mode", width = 180, click = function()
			Soul.Options.Close()
			Soul:OpenUnlock()
		end },
	})
end

Soul:RegisterPage({
	key = "bags",
	title = "Bags",
	description = "One bag window with categories, search and sort, plus the bank and warband bank.",
	group = "Utility",
	groupOrder = 4,
	order = 1,
	addon = "SoulUI_Bags",
	tabs = {
		{ key = "window", title = "Window", build = BuildWindow },
		{ key = "items", title = "Items", build = BuildItems },
		{ key = "bank", title = "Bank", build = BuildBank },
	},
	reset = function()
		local defaults = Soul.Defaults and Soul.Defaults.Bags
		if not defaults or not Mod() then return end
		local modules = Soul:ActiveProfile().modules
		modules.Bags = Soul:Copy(defaults)
		Apply()
	end,
})
