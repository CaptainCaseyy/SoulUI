if SoulUI_Blocked or not SoulUI then return end

-- Module pages. Each control writes the module's live settings table and calls
-- the module's Apply, so the change shows on screen immediately.

local Soul = SoulUI
local W = Soul.Widgets

local function Mod(key) return Soul:GetModule(key) end

local function Missing(col, key, label)
	if Mod(key) then return false end
	W.Note(col, label .. " is turned off. Turn it on under General > Modules.")
	return true
end

local function Apply(key, scope)
	local mod = Mod(key)
	if mod and mod.Apply then mod:Apply(scope or "all") end
end

local function Bool(v) return v and true or false end

local function EditButton(col, text)
	W.Buttons(col, {
		{ text = text or "Move in Edit Mode", width = 180, click = function()
			Soul.Options.Close()
			Soul:OpenUnlock()
		end },
	})
end

------------------------------------------------------------------------------
-- Unit frames
------------------------------------------------------------------------------

local UNIT_OPTIONS = {
	{ value = "player", label = "Player" },
	{ value = "target", label = "Target" },
	{ value = "focus", label = "Focus" },
	{ value = "targettarget", label = "Target of Target" },
	{ value = "pet", label = "Pet" },
}

local ufState = { unit = "player" }

local function UF() return Soul:ModuleDB("UnitFrames") end
local function Unit() return UF().units[ufState.unit] end
local function ApplyUF() Apply("UnitFrames", "all") end

local function BuildUnitFrames(col)
	if Missing(col, "UnitFrames", "Unit Frames") then return end
	W.Row(col, {
		type = "toggle", label = "Hide Blizzard player, target, focus and pet frames",
		get = function() return UF().hideBlizzard end,
		set = function(v) UF().hideBlizzard = Bool(v) ApplyUF() end,
	})
	W.Selector(col, UNIT_OPTIONS, function() return ufState.unit end, function(v) ufState.unit = v end)
	local function off() return not Unit().enabled end

	W.Section(col, "Frame")
	W.Row2(col, {
		type = "toggle", label = "Enabled",
		get = function() return Unit().enabled end,
		set = function(v) Unit().enabled = Bool(v) ApplyUF() end,
	}, {
		type = "toggle", label = "Power bar", disabled = off,
		get = function() return Unit().showPower end,
		set = function(v) Unit().showPower = Bool(v) ApplyUF() end,
	})
	W.Row2(col, {
		type = "slider", label = "Width", min = 40, max = 600, step = 1, disabled = off,
		get = function() return Unit().width end,
		set = function(v) Unit().width = v ApplyUF() end,
	}, {
		type = "slider", label = "Health height", min = 8, max = 160, step = 1, disabled = off,
		get = function() return Unit().height end,
		set = function(v) Unit().height = v ApplyUF() end,
	})
	W.Row2(col, {
		type = "slider", label = "Power height", min = 2, max = 40, step = 1,
		disabled = function() return off() or not Unit().showPower end,
		get = function() return Unit().powerHeight end,
		set = function(v) Unit().powerHeight = v ApplyUF() end,
	}, {
		type = "toggle", label = "Custom health color", disabled = off,
		tooltip = "Off: class color for players, reaction color for NPCs.",
		get = function() local u = Unit() return type(u.color) == "table" end,
		set = function(v)
			if v then Unit().color = { 0.53, 0.53, 0.93 } else Unit().color = nil end
			Apply("UnitFrames", "colors")
		end,
	})
	W.Row(col, {
		type = "color", label = "Health color",
		disabled = function() local u = Unit() return off() or type(u.color) ~= "table" end,
		get = W.ColorGet(Unit, "color", 0.53, 0.53, 0.93),
		set = W.ColorSet(Unit, "color", function() Apply("UnitFrames", "colors") end),
	})

	W.Section(col, "Text")
	W.Row2(col, {
		type = "dropdown", label = "Layout", width = 170, disabled = off,
		items = {
			{ value = "corners", label = "Name top, health bottom" },
			{ value = "center", label = "One line" },
		},
		get = function() return Unit().textLayout or "corners" end,
		set = function(v) Unit().textLayout = v ApplyUF() end,
	}, {
		type = "dropdown", label = "Health text", width = 170, disabled = off,
		items = {
			{ value = "both", label = "925K | 100%" },
			{ value = "value", label = "925K" },
			{ value = "percent", label = "100%" },
			{ value = "none", label = "Hidden" },
		},
		get = function() return Unit().healthFormat or "both" end,
		set = function(v) Unit().healthFormat = v ApplyUF() end,
	})
	W.Row2(col, {
		type = "toggle", label = "Show name", disabled = off,
		get = function() return Unit().showName ~= false end,
		set = function(v) Unit().showName = Bool(v) ApplyUF() end,
	}, {
		type = "dropdown", label = "Name position", width = 170, disabled = off,
		items = {
			{ value = "inside", label = "Inside the bar" },
			{ value = "above", label = "Above the bar" },
		},
		get = function() return Unit().namePosition or "inside" end,
		set = function(v) Unit().namePosition = v ApplyUF() end,
	})
	W.Row2(col, {
		type = "slider", label = "Name size (0 = auto)", min = 0, max = 32, step = 1, disabled = off,
		get = function() return Unit().nameSize or 0 end,
		set = function(v) Unit().nameSize = v ApplyUF() end,
	}, {
		type = "slider", label = "Health size (0 = auto)", min = 0, max = 32, step = 1, disabled = off,
		get = function() return Unit().healthSize or 0 end,
		set = function(v) Unit().healthSize = v ApplyUF() end,
	})

	W.Section(col, "Cast bar")
	W.Row2(col, {
		type = "toggle", label = "Cast bar", disabled = off,
		tooltip = "The player's cast bar lives under Resources by default.",
		get = function() return Unit().showCast end,
		set = function(v) Unit().showCast = Bool(v) ApplyUF() end,
	}, {
		type = "slider", label = "Cast height", min = 8, max = 60, step = 1,
		disabled = function() return off() or not Unit().showCast end,
		get = function() return Unit().castHeight or 18 end,
		set = function(v) Unit().castHeight = v ApplyUF() end,
	})
	W.Row2(col, {
		type = "slider", label = "Cast width (0 = frame)", min = 0, max = 600, step = 1,
		disabled = function() return off() or not Unit().showCast end,
		get = function() return Unit().castWidth or 0 end,
		set = function(v) Unit().castWidth = v > 0 and v or nil ApplyUF() end,
	}, {
		type = "color", label = "Cast color",
		disabled = function() return off() or not Unit().showCast end,
		get = function()
			local c = Unit().castColor
			if type(c) == "table" then return c[1], c[2], c[3] end
			return Soul:Accent()
		end,
		set = W.ColorSet(Unit, "castColor", ApplyUF),
	})
	EditButton(col)
end

Soul:RegisterPage({
	key = "unitframes",
	title = "Unit Frames",
	description = "Player, target, focus, target of target and pet.",
	group = "Frames",
	groupOrder = 2,
	order = 1,
	build = BuildUnitFrames,
})

------------------------------------------------------------------------------
-- Nameplates
------------------------------------------------------------------------------

local function NP() return Soul:ModuleDB("Nameplates") end
local function ApplyNP() Apply("Nameplates") end

local function BuildNameplates(col)
	if Missing(col, "Nameplates", "Nameplates") then return end
	W.Note(col, "SoulUI draws enemy and neutral plates. Friendly plates, including friendly plates in dungeons, stay Blizzard's.")
	local function off() return not NP().enabled end
	W.Section(col, "Plates")
	W.Row2(col, {
		type = "toggle", label = "Enabled",
		get = function() return NP().enabled end,
		set = function(v) NP().enabled = Bool(v) ApplyNP() end,
	}, {
		type = "toggle", label = "Show names", disabled = off,
		get = function() return NP().showName end,
		set = function(v) NP().showName = Bool(v) ApplyNP() end,
	})
	W.Row2(col, {
		type = "slider", label = "Width", min = 40, max = 300, step = 1, disabled = off,
		get = function() return NP().width end,
		set = function(v) NP().width = v ApplyNP() end,
	}, {
		type = "slider", label = "Health height", min = 4, max = 48, step = 1, disabled = off,
		get = function() return NP().height end,
		set = function(v) NP().height = v ApplyNP() end,
	})
	W.Row2(col, {
		type = "toggle", label = "Cast bar", disabled = off,
		get = function() return NP().showCast end,
		set = function(v) NP().showCast = Bool(v) ApplyNP() end,
	}, {
		type = "slider", label = "Cast height", min = 4, max = 40, step = 1,
		disabled = function() return off() or not NP().showCast end,
		get = function() return NP().castHeight end,
		set = function(v) NP().castHeight = v ApplyNP() end,
	})
	W.Section(col, "Game settings")
	W.Row2(col, {
		type = "toggle", label = "Turn on enemy nameplates",
		get = function() return NP().manageCVars end,
		set = function(v) NP().manageCVars = Bool(v) ApplyNP() end,
	}, {
		type = "toggle", label = "Stack plates",
		tooltip = "Plates push apart instead of drawing over each other.",
		get = function() return NP().stack end,
		set = function(v) NP().stack = Bool(v) ApplyNP() end,
	})
	W.Row(col, {
		type = "toggle", label = "Show every friendly nameplate",
		get = function() return NP().showAll end,
		set = function(v) NP().showAll = Bool(v) ApplyNP() end,
	})
end

Soul:RegisterPage({
	key = "nameplates",
	title = "Nameplates",
	description = "Enemy and neutral plates: size, cast bar, names and stacking.",
	group = "Frames",
	groupOrder = 2,
	order = 2,
	build = BuildNameplates,
})

------------------------------------------------------------------------------
-- Party and raid
------------------------------------------------------------------------------

local function GF() return Soul:ModuleDB("GroupFrames") end

local function GroupTab(kind)
	return function(col)
		if Missing(col, "GroupFrames", "Party and Raid") then return end
		local function cfg() return GF()[kind] end
		local function apply() Apply("GroupFrames") end
		local function off() return not cfg().enabled end
		if kind == "party" then
			W.Row(col, {
				type = "toggle", label = "Hide Blizzard party and raid frames",
				get = function() return GF().hideBlizzard end,
				set = function(v) GF().hideBlizzard = Bool(v) apply() end,
			})
		end
		W.Section(col, kind == "party" and "Party" or "Raid")
		W.Row2(col, {
			type = "toggle", label = "Enabled",
			get = function() return cfg().enabled end,
			set = function(v) cfg().enabled = Bool(v) apply() end,
		}, {
			type = "toggle", label = "Show yourself", disabled = off,
			get = function() return cfg().showPlayer end,
			set = function(v) cfg().showPlayer = Bool(v) apply() end,
		})
		W.Row2(col, {
			type = "slider", label = "Width", min = 40, max = 320, step = 1, disabled = off,
			get = function() return cfg().width end,
			set = function(v) cfg().width = v apply() end,
		}, {
			type = "slider", label = "Height", min = 16, max = 160, step = 1, disabled = off,
			get = function() return cfg().height end,
			set = function(v) cfg().height = v apply() end,
		})
		W.Row2(col, {
			type = "slider", label = "Spacing", min = 0, max = 30, step = 1, disabled = off,
			get = function() return cfg().spacing end,
			set = function(v) cfg().spacing = v apply() end,
		}, {
			type = "slider", label = "Name size", min = 8, max = 28, step = 1, disabled = off,
			get = function() return cfg().font or 12 end,
			set = function(v) cfg().font = v apply() end,
		})
		W.Row2(col, {
			type = "toggle", label = "Power bar", disabled = off,
			get = function() return cfg().showPower end,
			set = function(v) cfg().showPower = Bool(v) apply() end,
		}, {
			type = "slider", label = "Power height", min = 2, max = 20, step = 1,
			disabled = function() return off() or not cfg().showPower end,
			get = function() return cfg().powerHeight end,
			set = function(v) cfg().powerHeight = v apply() end,
		})
		W.Row2(col, {
			type = "toggle", label = "Dispel icons", disabled = off,
			get = function() return cfg().showAuras end,
			set = function(v) cfg().showAuras = Bool(v) apply() end,
		}, kind == "party" and {
			type = "toggle", label = "Show while solo", disabled = off,
			get = function() return cfg().showSolo end,
			set = function(v) cfg().showSolo = Bool(v) apply() end,
		} or nil)
		EditButton(col)
	end
end

Soul:RegisterPage({
	key = "groupframes",
	title = "Party and Raid",
	description = "Party frames in a party, raid frames in a raid.",
	group = "Frames",
	groupOrder = 2,
	order = 3,
	tabs = {
		{ key = "party", title = "Party", build = GroupTab("party") },
		{ key = "raid", title = "Raid", build = GroupTab("raid") },
	},
})

------------------------------------------------------------------------------
-- Action bars
------------------------------------------------------------------------------

local BAR_OPTIONS = {
	{ value = "main", label = "Bar 1" },
	{ value = "bar2", label = "Bar 2" },
	{ value = "bar3", label = "Bar 3" },
	{ value = "bar4", label = "Bar 4" },
	{ value = "bar5", label = "Bar 5" },
	{ value = "bar6", label = "Bar 6" },
	{ value = "bar7", label = "Bar 7" },
	{ value = "bar8", label = "Bar 8" },
}

local VISIBILITY = {
	{ value = "always", label = "Always" },
	{ value = "combat", label = "In combat only" },
	{ value = "nocombat", label = "Out of combat only" },
}

local abState = { bar = "main" }
local function AB() return Soul:ModuleDB("ActionBars") end
local function Bar() return AB().bars[abState.bar] end
local function ApplyAB() Apply("ActionBars") end

local function BuildBarTab(col)
	if Missing(col, "ActionBars", "Action Bars") then return end
	W.Selector(col, BAR_OPTIONS, function() return abState.bar end, function(v) abState.bar = v end)
	local function off() return not Bar().enabled end
	W.Section(col, "Layout")
	W.Row2(col, {
		type = "toggle", label = "Enabled",
		get = function() return Bar().enabled end,
		set = function(v) Bar().enabled = Bool(v) ApplyAB() end,
	}, {
		type = "toggle", label = "Vertical", disabled = off,
		get = function() return Bar().vertical end,
		set = function(v) Bar().vertical = Bool(v) ApplyAB() end,
	})
	W.Row2(col, {
		type = "slider", label = "Buttons", min = 1, max = 12, step = 1, disabled = off,
		get = function() return Bar().buttons end,
		set = function(v) Bar().buttons = v ApplyAB() end,
	}, {
		type = "slider", label = "Rows (columns if vertical)", min = 1, max = 12, step = 1, disabled = off,
		get = function() return Bar().rows or 1 end,
		set = function(v) Bar().rows = v ApplyAB() end,
	})
	W.Row2(col, {
		type = "slider", label = "Button size", min = 12, max = 80, step = 1, disabled = off,
		get = function() return Bar().size end,
		set = function(v) Bar().size = v ApplyAB() end,
	}, {
		type = "slider", label = "Spacing", min = 0, max = 20, step = 1, disabled = off,
		get = function() return Bar().spacing end,
		set = function(v) Bar().spacing = v ApplyAB() end,
	})
	W.Section(col, "Visibility")
	W.Row2(col, {
		type = "dropdown", label = "Show", items = VISIBILITY, width = 170, disabled = off,
		get = function() return Bar().visibility or "always" end,
		set = function(v) Bar().visibility = v ApplyAB() end,
	}, {
		type = "toggle", label = "Fade until mouseover", disabled = off,
		get = function() return Bar().fade end,
		set = function(v) Bar().fade = Bool(v) ApplyAB() end,
	})
	W.Row(col, {
		type = "slider", label = "Faded opacity", min = 0, max = 1, step = 0.05,
		disabled = function() return off() or not Bar().fade end,
		get = function() return Bar().fadeAlpha or 0 end,
		set = function(v) Bar().fadeAlpha = v ApplyAB() end,
	})
	W.Section(col, "Text")
	W.Row2(col, {
		type = "toggle", label = "Keybinds", disabled = off,
		get = function() return Bar().showHotkey ~= false end,
		set = function(v) Bar().showHotkey = Bool(v) ApplyAB() end,
	}, {
		type = "toggle", label = "Charges and counts", disabled = off,
		get = function() return Bar().showCount ~= false end,
		set = function(v) Bar().showCount = Bool(v) ApplyAB() end,
	})
	W.Row(col, {
		type = "toggle", label = "Macro names", disabled = off,
		get = function() return Bar().showMacro end,
		set = function(v) Bar().showMacro = Bool(v) ApplyAB() end,
	})
	EditButton(col)
end

local function BuildBarStyle(col)
	if Missing(col, "ActionBars", "Action Bars") then return end
	W.Note(col, "Applies to every bar. Keys stay on the normal action-bar bindings, so empowered spells keep their press and release.")
	W.Section(col, "Buttons")
	W.Row2(col, {
		type = "toggle", label = "Pixel border",
		get = function() return AB().showBorder end,
		set = function(v) AB().showBorder = Bool(v) ApplyAB() end,
	}, {
		type = "toggle", label = "Show empty slots",
		get = function() return AB().showEmpty ~= false end,
		set = function(v) AB().showEmpty = Bool(v) ApplyAB() end,
	})
	W.Section(col, "Text size (0 = sized from the button)")
	W.Row2(col, {
		type = "slider", label = "Keybind", min = 0, max = 24, step = 1,
		get = function() return AB().hotkeySize or 0 end,
		set = function(v) AB().hotkeySize = v ApplyAB() end,
	}, {
		type = "slider", label = "Count", min = 0, max = 24, step = 1,
		get = function() return AB().countSize or 0 end,
		set = function(v) AB().countSize = v ApplyAB() end,
	})
	W.Row(col, {
		type = "slider", label = "Macro name", min = 0, max = 20, step = 1,
		get = function() return AB().macroSize or 0 end,
		set = function(v) AB().macroSize = v ApplyAB() end,
	})
end

Soul:RegisterPage({
	key = "actionbars",
	title = "Action Bars",
	description = "Eight bars of SoulUI buttons: layout, size, visibility and text.",
	group = "Combat",
	groupOrder = 3,
	order = 1,
	tabs = {
		{ key = "bars", title = "Bars", build = BuildBarTab },
		{ key = "style", title = "Style", build = BuildBarStyle },
	},
})

------------------------------------------------------------------------------
-- Resources
------------------------------------------------------------------------------

local function RB() return Soul:ModuleDB("ResourceBars") end
local function ApplyRB() Apply("ResourceBars") end

local function BuildPips(col)
	if Missing(col, "ResourceBars", "Resources") then return end
	W.Note(col, "Soul shards, combo points, holy power, chi, arcane charges, essence and runes. Destruction shows partial shards.")
	local function p() return RB().pips end
	local function off() return not RB().showPips end
	W.Section(col, "Class resource")
	W.Row2(col, {
		type = "toggle", label = "Enabled",
		get = function() return RB().showPips end,
		set = function(v) RB().showPips = Bool(v) ApplyRB() end,
	}, {
		type = "toggle", label = "Border", disabled = off,
		get = function() return p().border ~= false end,
		set = function(v) p().border = Bool(v) ApplyRB() end,
	})
	W.Row2(col, {
		type = "slider", label = "Width", min = 40, max = 800, step = 1, disabled = off,
		get = function() return p().width end,
		set = function(v) p().width = v ApplyRB() end,
	}, {
		type = "slider", label = "Height", min = 4, max = 80, step = 1, disabled = off,
		get = function() return p().height end,
		set = function(v) p().height = v ApplyRB() end,
	})
	W.Row2(col, {
		type = "slider", label = "Gap", min = 0, max = 20, step = 1, disabled = off,
		get = function() return p().gap or 2 end,
		set = function(v) p().gap = v ApplyRB() end,
	}, {
		type = "toggle", label = "Gloss", disabled = off,
		get = function() return p().gloss end,
		set = function(v) p().gloss = Bool(v) ApplyRB() end,
	})
	W.Section(col, "Colors")
	W.Row2(col, {
		type = "dropdown", label = "Fill", width = 160, disabled = off,
		items = { { value = "class", label = "Class color" }, { value = "custom", label = "Custom" } },
		get = function() return p().colorMode or "class" end,
		set = function(v)
			p().colorMode = v
			local pips = p()
			if v == "custom" and type(pips.color) ~= "table" then pips.color = { 0.53, 0.53, 0.93 } end
			ApplyRB()
		end,
	}, {
		type = "color", label = "Custom fill",
		disabled = function() return off() or p().colorMode ~= "custom" end,
		get = W.ColorGet(p, "color", 0.53, 0.53, 0.93),
		set = W.ColorSet(p, "color", ApplyRB),
	})
	W.Row(col, {
		type = "color", label = "Empty tile", disabled = off,
		get = W.ColorGet(p, "emptyColor", 0.17, 0.17, 0.17),
		set = W.ColorSet(p, "emptyColor", ApplyRB),
	})
	W.Section(col, "Count")
	W.Row2(col, {
		type = "toggle", label = "Show count", disabled = off,
		tooltip = "The number on the last full tile, like the 3 on the third shard.",
		get = function() return p().showCount ~= false end,
		set = function(v) p().showCount = Bool(v) ApplyRB() end,
	}, {
		type = "slider", label = "Count size (0 = auto)", min = 0, max = 40, step = 1,
		disabled = function() return off() or p().showCount == false end,
		get = function() return p().countSize or 0 end,
		set = function(v) p().countSize = v ApplyRB() end,
	})
	EditButton(col)
end

local function BuildCast(col)
	if Missing(col, "ResourceBars", "Resources") then return end
	local function c() return RB().cast end
	local function off() return not RB().showCast end
	W.Section(col, "Player cast bar")
	W.Row2(col, {
		type = "toggle", label = "Enabled",
		get = function() return RB().showCast end,
		set = function(v) RB().showCast = Bool(v) ApplyRB() end,
	}, {
		type = "toggle", label = "Spell icon", disabled = off,
		get = function() return c().showIcon ~= false end,
		set = function(v) c().showIcon = Bool(v) ApplyRB() end,
	})
	W.Row2(col, {
		type = "slider", label = "Width", min = 40, max = 800, step = 1, disabled = off,
		get = function() return c().width end,
		set = function(v) c().width = v ApplyRB() end,
	}, {
		type = "slider", label = "Height", min = 6, max = 60, step = 1, disabled = off,
		get = function() return c().height end,
		set = function(v) c().height = v ApplyRB() end,
	})
	W.Row2(col, {
		type = "slider", label = "Text size (0 = auto)", min = 0, max = 32, step = 1, disabled = off,
		get = function() return c().textSize or 0 end,
		set = function(v) c().textSize = v ApplyRB() end,
	}, {
		type = "color", label = "Fill color", disabled = off,
		get = function()
			local color = c().color
			if type(color) == "table" then return color[1], color[2], color[3] end
			return Soul:Accent()
		end,
		set = W.ColorSet(c, "color", ApplyRB),
	})
	EditButton(col)
end

local function BuildPower(col)
	if Missing(col, "ResourceBars", "Resources") then return end
	local function pw() return RB().primary end
	local function g() return RB().gcd end
	W.Section(col, "Primary power")
	W.Row2(col, {
		type = "toggle", label = "Enabled",
		get = function() return RB().showPrimary end,
		set = function(v) RB().showPrimary = Bool(v) ApplyRB() end,
	}, {
		type = "toggle", label = "Percent text",
		disabled = function() return not RB().showPrimary end,
		get = function() return pw().showText ~= false end,
		set = function(v) pw().showText = Bool(v) ApplyRB() end,
	})
	W.Row2(col, {
		type = "slider", label = "Width", min = 40, max = 800, step = 1,
		disabled = function() return not RB().showPrimary end,
		get = function() return pw().width end,
		set = function(v) pw().width = v ApplyRB() end,
	}, {
		type = "slider", label = "Height", min = 2, max = 40, step = 1,
		disabled = function() return not RB().showPrimary end,
		get = function() return pw().height end,
		set = function(v) pw().height = v ApplyRB() end,
	})
	W.Section(col, "Global cooldown")
	W.Row2(col, {
		type = "toggle", label = "Enabled",
		get = function() return RB().showGCD end,
		set = function(v) RB().showGCD = Bool(v) ApplyRB() end,
	}, {
		type = "slider", label = "Height", min = 1, max = 20, step = 1,
		disabled = function() return not RB().showGCD end,
		get = function() return g().height end,
		set = function(v) g().height = v ApplyRB() end,
	})
	EditButton(col)
end

Soul:RegisterPage({
	key = "resources",
	title = "Resources",
	description = "Class resource (shards, combo points, runes...), player cast bar, power and GCD.",
	group = "Combat",
	groupOrder = 3,
	order = 2,
	tabs = {
		{ key = "pips", title = "Class Resource", build = BuildPips },
		{ key = "cast", title = "Cast Bar", build = BuildCast },
		{ key = "power", title = "Power & GCD", build = BuildPower },
	},
})

------------------------------------------------------------------------------
-- Damage meters
------------------------------------------------------------------------------

local METER_TYPES = {
	{ value = "damage", label = "Damage Done" },
	{ value = "healing", label = "Healing Done" },
	{ value = "taken", label = "Damage Taken" },
	{ value = "avoidable", label = "Avoidable Damage" },
	{ value = "enemy", label = "Enemy Damage Taken" },
	{ value = "interrupts", label = "Interrupts" },
	{ value = "dispels", label = "Dispels" },
	{ value = "deaths", label = "Deaths" },
}

local function DMdb() return Soul:ModuleDB("DamageMeters") end
local function ApplyDM() Apply("DamageMeters") end

local function BuildMeters(col)
	if Missing(col, "DamageMeters", "Damage Meters") then return end
	W.Note(col, "Numbers come from the game's own combat meter (C_DamageMeter), already summed and ranked by the server, so the bars cost almost nothing to draw. Click a row out of combat for the spell breakdown.")
	local function off() return not DMdb().enabled end
	W.Section(col, "All windows")
	W.Row2(col, {
		type = "toggle", label = "Enabled",
		get = function() return DMdb().enabled end,
		set = function(v) DMdb().enabled = Bool(v) ApplyDM() end,
	}, {
		type = "toggle", label = "Fight clock", disabled = off,
		get = function() return DMdb().showClock ~= false end,
		set = function(v) DMdb().showClock = Bool(v) ApplyDM() end,
	})
	W.Row2(col, {
		type = "slider", label = "Width", min = 120, max = 500, step = 1, disabled = off,
		get = function() return DMdb().width end,
		set = function(v) DMdb().width = v ApplyDM() end,
	}, {
		type = "slider", label = "Rows", min = 3, max = 20, step = 1, disabled = off,
		get = function() return DMdb().rows end,
		set = function(v) DMdb().rows = v ApplyDM() end,
	})
	W.Row2(col, {
		type = "slider", label = "Row height", min = 10, max = 40, step = 1, disabled = off,
		get = function() return DMdb().rowHeight end,
		set = function(v) DMdb().rowHeight = v ApplyDM() end,
	}, {
		type = "slider", label = "Background opacity", min = 0, max = 1, step = 0.05, disabled = off,
		get = function() return DMdb().bgAlpha or 0.55 end,
		set = function(v) DMdb().bgAlpha = v ApplyDM() end,
	})
	W.Row(col, {
		type = "slider", label = "Updates per second", min = 1, max = 4, step = 1, disabled = off,
		get = function()
			local rate = DMdb().refresh or 0.25
			if type(rate) ~= "number" or rate <= 0 then return 4 end
			return math.max(1, math.min(4, math.floor(1 / rate + 0.5)))
		end,
		set = function(v) DMdb().refresh = 1 / v ApplyDM() end,
	})
	for i = 1, 3 do
		local index = i
		local function cfg() return DMdb().windows[index] end
		local function winOff() return off() or not cfg().enabled end
		W.Section(col, "Window " .. index)
		W.Row2(col, {
			type = "toggle", label = "Shown", disabled = off,
			get = function() return cfg().enabled end,
			set = function(v) cfg().enabled = Bool(v) ApplyDM() end,
		}, {
			type = "dropdown", label = "Mode", items = METER_TYPES, width = 180, disabled = winOff,
			get = function() return cfg().type end,
			set = function(v) cfg().type = v ApplyDM() end,
		})
		W.Row2(col, {
			type = "dropdown", label = "Segment", width = 180, disabled = winOff,
			items = { { value = "current", label = "Current fight" }, { value = "overall", label = "Overall" } },
			get = function() return cfg().segment end,
			set = function(v) cfg().segment = v ApplyDM() end,
		}, {
			type = "color", label = "Background tint", disabled = winOff,
			get = W.ColorGet(cfg, "color", 0.02, 0.02, 0.025),
			set = W.ColorSet(cfg, "color", ApplyDM),
		})
	end
	W.Section(col, "Data")
	W.Buttons(col, {
		{ text = "Reset meter data", width = 180, style = "danger", click = function()
			if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
				C_DamageMeter.ResetAllCombatSessions()
			end
			Soul:Print("Damage meters reset.")
		end },
	})
	EditButton(col)
end

Soul:RegisterPage({
	key = "meters",
	title = "Damage Meters",
	description = "Three meter windows: damage, healing, interrupts, deaths and more.",
	group = "Combat",
	groupOrder = 3,
	order = 3,
	build = BuildMeters,
})
