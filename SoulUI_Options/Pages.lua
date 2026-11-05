if SoulUI_Blocked or not SoulUI then return end

-- SoulUI group: General (look, modules, tools) and Profiles.

local Soul = SoulUI
local UI = Soul.UI
local W = Soul.Widgets

local OUTLINES = {
	{ value = "NONE", label = "None" },
	{ value = "OUTLINE", label = "Outline" },
	{ value = "THICKOUTLINE", label = "Thick outline" },
}

local MODULES = {
	{ addon = "SoulUI_UnitFrames", label = "Unit Frames" },
	{ addon = "SoulUI_Nameplates", label = "Nameplates" },
	{ addon = "SoulUI_GroupFrames", label = "Party and Raid" },
	{ addon = "SoulUI_ActionBars", label = "Action Bars" },
	{ addon = "SoulUI_ResourceBars", label = "Resources" },
	{ addon = "SoulUI_DamageMeters", label = "Damage Meters" },
}

-- Re-applies every module (fonts and textures are read at Apply time).
function Soul:ApplyAllModules()
	for _, mod in pairs(self.modules) do
		if mod.Apply then pcall(mod.Apply, mod, "all") end
	end
	self:Fire("ThemeChanged")
end

local function Theme() return Soul:Theme() end

StaticPopupDialogs["SOULUI_RELOAD"] = {
	text = "SoulUI needs to reload the interface for this change.",
	button1 = "Reload now",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function AddonEnabled(name)
	if not C_AddOns or not C_AddOns.GetAddOnEnableState then return true end
	local state = C_AddOns.GetAddOnEnableState(name, UnitName("player"))
	return state and state > 0
end

local function BuildLook(col)
	W.Note(col, "One accent color, font and bar texture shared by every SoulUI frame and by this window. Changes apply at once.")
	W.Section(col, "Accent")
	W.Row2(col, {
		type = "toggle", label = "Use class color",
		get = function() return Theme().accentUseClass end,
		set = function(v) Theme().accentUseClass = v and true or false Soul:Fire("ThemeChanged") end,
	}, {
		type = "color", label = "Accent color",
		get = function() local a = Theme().accent return a.r, a.g, a.b end,
		set = function(r, g, b) Theme().accent = { r = r, g = g, b = b } Soul:Fire("ThemeChanged") end,
		disabled = function() return Theme().accentUseClass end,
	})
	W.Section(col, "Text")
	W.Row2(col, {
		type = "font", label = "Font",
		get = function() return Theme().font end,
		set = function(v) Theme().font = v Soul:ApplyAllModules() end,
	}, {
		type = "dropdown", label = "Outline", items = OUTLINES, width = 150,
		get = function() return Theme().fontOutline or "OUTLINE" end,
		set = function(v) Theme().fontOutline = v Soul:ApplyAllModules() end,
	})
	W.Section(col, "Bars")
	W.Row(col, {
		type = "statusbar", label = "Bar texture",
		tooltip = "Used by unit frames, nameplates, group frames, resources and meters.",
		get = function() return Theme().statusbar end,
		set = function(v) Theme().statusbar = v Soul:ApplyAllModules() end,
	})
	W.Section(col, "Settings window")
	W.Row(col, {
		type = "slider", label = "Window scale", min = 0.6, max = 1.6, step = 0.05,
		get = function() return Soul.db.account.panelScale or 1 end,
		set = function(v)
			Soul.db.account.panelScale = v
			local frame = _G.SoulUI_OptionsFrame
			if frame then frame:SetScale(UI.PanelScale()) end
		end,
	})
end

local function CastCfg() return Soul.Cast.Settings() end
local function RefreshCasts()
	Soul:Fire("ThemeChanged")
end

local function CastColor(key)
	return {
		get = function() local c = CastCfg()[key] return c[1], c[2], c[3] end,
		set = function(r, g, b) CastCfg()[key] = { r, g, b } RefreshCasts() end,
	}
end

local function BuildCasts(col)
	W.Note(col, "Enemy cast bars on nameplates, target and focus. Interruptible casts use the first color; when your interrupt is on cooldown they switch to the second, so you know to leave it to someone else. Casts that cannot be interrupted turn gray with a lock. Spells the game marks as important get a red outline, and an important cast that cannot be interrupted gets a STUN badge: a stun, knockback or incapacitate is the answer (bosses are immune).")
	W.Section(col, "Colors")
	local interruptible = CastColor("interruptible")
	local cooldown = CastColor("kickCooldown")
	local locked = CastColor("locked")
	local important = CastColor("important")
	W.Row2(col, { type = "color", label = "Interruptible", get = interruptible.get, set = interruptible.set },
		{ type = "color", label = "Interrupt on cooldown", get = cooldown.get, set = cooldown.set,
			disabled = function() return not CastCfg().kickColoring end })
	W.Row2(col, { type = "color", label = "Not interruptible", get = locked.get, set = locked.set },
		{ type = "color", label = "Important outline", get = important.get, set = important.set,
			disabled = function() return not CastCfg().showImportant end })
	W.Section(col, "Signals")
	W.Row2(col, {
		type = "toggle", label = "Track my interrupt cooldown",
		tooltip = "Colors interruptible casts differently while your interrupt (Kick, Pummel, Counterspell...) is on cooldown.",
		get = function() return CastCfg().kickColoring end,
		set = function(v) CastCfg().kickColoring = v and true or false RefreshCasts() end,
	}, {
		type = "toggle", label = "Lock icon on uninterruptible",
		get = function() return CastCfg().showLock end,
		set = function(v) CastCfg().showLock = v and true or false RefreshCasts() end,
	})
	W.Row2(col, {
		type = "toggle", label = "Outline important casts",
		get = function() return CastCfg().showImportant end,
		set = function(v) CastCfg().showImportant = v and true or false RefreshCasts() end,
	}, {
		type = "toggle", label = "STUN badge",
		tooltip = "Shown when a cast is both important and uninterruptible.",
		get = function() return CastCfg().showStun end,
		set = function(v) CastCfg().showStun = v and true or false RefreshCasts() end,
	})
	W.Buttons(col, {
		{ text = "Reset cast colors", width = 180, click = function()
			Soul:Theme().cast = nil
			RefreshCasts()
		end },
	})
end

local function BuildModules(col)
	W.Note(col, "Turn whole modules on or off. The addon list changes, so a reload is needed. Turn EllesmereUI's matching modules off while SoulUI's are on, or both will draw.")
	W.Section(col, "Modules")
	for i = 1, #MODULES do
		local info = MODULES[i]
		W.Row(col, {
			type = "toggle", label = info.label,
			get = function() return AddonEnabled(info.addon) end,
			set = function(v)
				if v then
					C_AddOns.EnableAddOn(info.addon, UnitName("player"))
				else
					C_AddOns.DisableAddOn(info.addon, UnitName("player"))
				end
				StaticPopup_Show("SOULUI_RELOAD")
			end,
		})
	end
end

-- Every movable element, grouped by module, with a shown / hidden switch
-- (the same switch as the edit-mode inspector), plus Blizzard frames.
local GROUPS = {
	{ prefix = "UnitFrames", title = "Unit Frames" },
	{ prefix = "ResourceBars", title = "Resources" },
	{ prefix = "ActionBars", title = "Action Bars" },
	{ prefix = "GroupFrames", title = "Party and Raid" },
	{ prefix = "DamageMeters", title = "Damage Meters" },
	{ prefix = "Blizzard", title = "Blizzard Cooldown Manager" },
}

local function BlizzCfg() return Soul.Blizz.Settings() end
local function BlizzSet(key)
	return function(v)
		BlizzCfg()[key] = v and true or false
		Soul.Blizz.Refresh()
	end
end

local function ElementRow(element)
	return {
		type = "toggle", label = element.label or element.key,
		get = function()
			local ok, on = pcall(element.getEnabled)
			return ok and on and true or false
		end,
		set = function(v)
			if InCombatLockdown() then
				Soul:Print("Wait until combat ends to show or hide frames.")
				return
			end
			element.setEnabled(v and true or false)
		end,
	}
end

local function BuildVisibility(col)
	W.Note(col, "Hide any SoulUI element. Hidden elements still show as dim boxes in edit mode (/soul move), where you can select one and switch it back on.")
	if Soul.Blizz then
		W.Section(col, "Blizzard frames")
		W.Row2(col, {
			type = "toggle", label = "Hide Blizzard's cast bar",
			tooltip = "Hides Blizzard's player and pet cast bars while a SoulUI player cast bar is on (Resources or the player unit frame).",
			get = function() return BlizzCfg().hideCastBar end,
			set = BlizzSet("hideCastBar"),
		}, {
			type = "toggle", label = "Personal resource display",
			tooltip = "Blizzard's health, power and cast plate above your character.",
			get = function() return BlizzCfg().personalDisplay end,
			set = BlizzSet("personalDisplay"),
		})
		W.Row(col, {
			type = "toggle", label = "Blizzard Cooldown Manager",
			tooltip = "Blizzard's rows of spell and buff icons (Essential, Utility, Buff Icons, Buff Bars). When on, each row can be moved and hidden in edit mode.",
			get = function() return BlizzCfg().cooldownManager end,
			set = BlizzSet("cooldownManager"),
		})
	end
	for g = 1, #GROUPS do
		local group = GROUPS[g]
		local list = {}
		for key, element in pairs(Soul._movers) do
			if element.setEnabled and element.getEnabled and key:match("^([^:]+)") == group.prefix then
				list[#list + 1] = element
			end
		end
		if #list > 0 then
			table.sort(list, function(a, b) return a.key < b.key end)
			W.Section(col, group.title)
			for i = 1, #list, 2 do
				W.Row2(col, ElementRow(list[i]), list[i + 1] and ElementRow(list[i + 1]) or nil)
			end
		end
	end
end

local function BuildTools(col)
	W.Section(col, "Layout")
	W.Buttons(col, {
		{ text = "Open Edit Mode", width = 160, style = "accent", click = function()
			Soul.Options.Close()
			Soul:OpenUnlock()
		end },
		{ text = "Reset Layout", width = 160, click = function() Soul:ResetLayout() end,
			tooltip = "Puts every frame back on the SoulUI default layout for this screen size." },
	})
	W.Section(col, "Testing")
	W.Row(col, {
		type = "toggle", label = "Debug messages",
		get = function() return Soul.db.account.debug end,
		set = function(v) Soul.db.account.debug = v and true or false end,
	})
	W.Note(col, "Forced restrictions make the client hand out secret values outside combat, so a training dummy behaves like a raid boss. Turn them off when you are done.")
	W.Buttons(col, {
		{ text = "Force secret values", width = 180, click = function()
			SetCVar("addonCombatRestrictionsForced", "1")
			SetCVar("addonEncounterRestrictionsForced", "1")
			Soul:Print("Restrictions forced on. /soul secret off clears them.")
		end },
		{ text = "Clear secret values", width = 180, click = function()
			SetCVar("addonCombatRestrictionsForced", "0")
			SetCVar("addonEncounterRestrictionsForced", "0")
			Soul:Print("Restrictions cleared.")
		end },
	})
end

Soul:RegisterPage({
	key = "general",
	title = "General",
	description = "Accent color, font, bar texture, cast colors, hiding elements, modules and test tools.",
	group = "SoulUI",
	groupOrder = 1,
	order = 1,
	tabs = {
		{ key = "look", title = "Look", build = BuildLook },
		{ key = "casts", title = "Casts", build = BuildCasts, preview = function(...) return Soul.Previews.Casts(...) end },
		{ key = "visibility", title = "Hide & Show", build = BuildVisibility },
		{ key = "modules", title = "Modules", build = BuildModules },
		{ key = "tools", title = "Tools", build = BuildTools },
	},
})

------------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------------

local function Trim(text)
	return ((text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ProfileNames()
	local names = {}
	for i = 1, #Soul.db.profileOrder do
		local name = Soul.db.profileOrder[i]
		if Soul.db.profiles[name] then names[#names + 1] = name end
	end
	return names
end

local function BuildProfiles(col)
	W.Note(col, "A profile holds every setting and every frame position. Profiles are shared by all characters on this account. Export strings start with !SOUL1: and carry the whole profile.")
	W.Section(col, "Profiles")
	W.List(col, 10, function(rows)
		local names = ProfileNames()
		for i = 1, #rows do
			local row = rows[i]
			local name = names[i]
			if not row.text then
				row.text = UI.Text(row, 14, UI.C.text)
				row.text:SetPoint("LEFT", 16, 0)
				row.tag = UI.Text(row, 12, UI.C.dim)
				row.tag:SetPoint("LEFT", row.text, "RIGHT", 10, 0)
				row.delete = UI.Button(row, "Delete", 80, 26, function()
					local ok, err = Soul:DeleteProfile(row.name)
					if not ok then Soul:Print(err) end
					Soul.Options.Refresh()
				end, "danger")
				row.delete:SetPoint("RIGHT", -16, 0)
				row.copy = UI.Button(row, "Copy", 70, 26, function()
					local base = row.name .. " copy"
					local candidate, n = base, 2
					while Soul.db.profiles[candidate] do candidate = base .. " " .. n n = n + 1 end
					local ok, err = Soul:CreateProfile(candidate, row.name)
					if not ok then Soul:Print(err) end
					Soul.Options.Refresh()
				end)
				row.copy:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
				row.use = UI.Button(row, "Activate", 90, 26, function()
					Soul:SetProfile(row.name)
					Soul.Options.Refresh()
				end, "accent")
				row.use:SetPoint("RIGHT", row.copy, "LEFT", -6, 0)
			end
			row.name = name
			if name then
				local active = name == Soul.db.activeProfile
				row.text:SetText(name)
				row.tag:SetText(active and "active" or "")
				local r, g, b = Soul:Accent()
				row.tag:SetTextColor(r, g, b)
				row.use:SetShown(not active)
				row.delete:SetShown(not active)
				row.copy:Show()
				row:Show()
			else
				row:Hide()
			end
		end
	end)
	W.Input(col, "New profile", "Create", function(text, box)
		local name = Trim(text)
		local ok, err = Soul:CreateProfile(name)
		if not ok then Soul:Print(err) return end
		box:SetText("")
		Soul:SetProfile(name)
		Soul.Options.Refresh()
	end)

	W.Section(col, "Specializations")
	W.Note(col, "Pick a profile per specialization. Switching spec switches the profile (after combat). Leave it on None to keep the current profile.")
	local count = GetNumSpecializations and GetNumSpecializations() or 0
	for i = 1, count do
		local id, specName = GetSpecializationInfo(i)
		if id then
			W.Row(col, {
				type = "dropdown", label = specName or ("Spec " .. i), width = 220,
				items = function()
					local items = { { value = "", label = "None" } }
					local names = ProfileNames()
					for n = 1, #names do items[#items + 1] = { value = names[n], label = names[n] } end
					return items
				end,
				get = function() return Soul.db.specProfiles[id] or "" end,
				set = function(v)
					Soul.db.specProfiles[id] = v ~= "" and v or nil
					Soul:ApplySpecProfile()
				end,
			})
		end
	end

	W.Section(col, "Export")
	local export = W.TextArea(col, 110)
	W.Buttons(col, {
		{ text = "Export active profile", width = 200, style = "accent", click = function()
			local text = Soul:ExportProfile(Soul.db.activeProfile)
			if text then
				export.box:SetText(text)
				export.box:SetFocus()
				export.box:HighlightText()
				Soul:Print("Export string ready. Press Ctrl+C to copy it.")
			end
		end },
	})
	W.Section(col, "Import")
	local import = W.TextArea(col, 110)
	W.Buttons(col, {
		{ text = "Import string", width = 200, style = "accent", click = function()
			local ok, err = Soul:ImportProfile(import.box:GetText() or "")
			if not ok then
				Soul:Print(err or "Import failed.")
			else
				import.box:SetText("")
				Soul:Print("Profile imported and activated.")
				Soul.Options.Refresh()
			end
		end },
	})
end

Soul:RegisterPage({
	key = "profiles",
	title = "Profiles",
	description = "Switch, copy, share and assign profiles to specializations.",
	group = "SoulUI",
	groupOrder = 1,
	order = 2,
	build = BuildProfiles,
})
