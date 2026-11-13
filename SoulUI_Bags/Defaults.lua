if SoulUI_Blocked or not SoulUI then return end

SoulUI.Defaults = SoulUI.Defaults or {}

-- Bags. The window grows up and to the left from its anchor (bottom right),
-- like the stock bags. Sizes are in panel pixels: the window uses the same
-- pixel-perfect scale as the settings window (General > window scale), times
-- `scale`.
SoulUI.Defaults.Bags = {
	enabled = true,          -- replace Blizzard's bag frames
	scale = 1,
	columns = 12,
	iconSize = 40,
	spacing = 4,
	sectionGap = 12,
	padding = 12,
	bgAlpha = 0.97,

	-- Sections
	categories = true,       -- group items into sections
	packSections = true,     -- small sections sit side by side
	sectionTitles = true,
	titleSize = 12,
	cats = {
		new = true,
		equipment = true,
		consumable = true,
		quest = true,
		reagent = true,
		gem = true,
		recipe = true,
		misc = true,
		junk = true,
	},
	emptyMode = "one",       -- "one" (one free slot with a count), "all", "none"
	sortMode = "quality",    -- "quality", "ilvl", "name", "type", "none"

	-- Item buttons
	countSize = 12,
	itemLevel = true,
	ilvlSize = 12,
	ilvlAnchor = "TOPLEFT",
	ilvlQualityColor = true,
	bindText = true,
	qualityBorders = true,
	qualityMin = 2,          -- Uncommon and better
	questMarks = true,
	newGlow = true,
	newGlowAccent = true,
	newGlowColor = { 1, 0.82, 0.32 },
	clearNewOnClose = true,
	junkGrey = true,

	-- Header and footer
	search = true,
	bagBar = false,
	currencies = true,
	gold = true,
	autoSort = false,        -- clean up (C_Container.SortBags) when the bags open

	-- Bank
	bank = true,             -- replace Blizzard's bank and warband bank window
	bankColumns = 14,

	-- Layout modes. combined = one categorized grid. bags = one block per bag.
	-- list = one row per item. The sidebar filters the combined view.
	style = "combined",
	sidebar = true,
	pins = {},               -- itemID -> true. Alt-click a slot to pin it.
	splitStack = true,       -- shift-right-click a stack to split it
	quickAction = false,     -- a button that casts a spell on the hovered item
	quickSpell = 13262,      -- Disenchant
	offline = true,          -- remember this character's bags for the alt list
	goldHistory = true,
}
