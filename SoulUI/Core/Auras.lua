if SoulUI_Blocked then return end

-- Aura displays through Blizzard's AuraContainer (the only aura path that works
-- while auras are restricted in 12.1: Lua never reads aura data, the engine
-- fills buttons that match a filter string).
--
-- Two shapes:
--   Soul.Auras.Icons(parent, unit, groups)      a row of icons (dispels, purges, your debuffs)
--   Soul.Auras.Highlight(parent, unit, filter)  one frame-sized button with an outline that
--                                               exists only while an aura matches the filter
--
-- The highlight needs no Lua test of "is there a dispellable debuff": the
-- group's filter (RAID_PLAYER_DISPELLABLE, DISPELLABLE) decides, and the
-- engine shows or hides the button. The outline is also registered as a
-- dispel-type texture where the client supports it, so Magic, Curse, Poison,
-- Disease and Bleed tint it in their usual colors.
--
-- Containers cannot be created in combat. Build them at login / out of combat.

local Soul = SoulUI
local Auras = {}
Soul.Auras = Auras

local loaded = false
local function EnsureLoaded()
	if loaded then return end
	loaded = true
	if C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
end

local function NewContainer(parent)
	if InCombatLockdown() then return nil end
	EnsureLoaded()
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not container then return nil end
	if container.SetMouseMotionEnabled then pcall(container.SetMouseMotionEnabled, container, false) end
	if container.SetMouseClickEnabled then pcall(container.SetMouseClickEnabled, container, false) end
	return container
end

local function DispelStyle()
	local enum = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
	return enum and enum.PreserveAsset
end

-- Offensive dispels the player has right now (plain booleans: spellbook data).
local OFFENSIVE = {
	{ 370, "magic" },    -- Purge
	{ 378773, "magic" }, -- Greater Purge
	{ 528, "magic" },    -- Dispel Magic
	{ 32375, "magic" },  -- Mass Dispel
	{ 278326, "magic" }, -- Consume Magic
	{ 30449, "magic" },  -- Spellsteal
	{ 19505, "magic", true }, -- Devour Magic (felhunter)
	{ 19801, "both" },   -- Tranquilizing Shot
	{ 2908, "enrage" },  -- Soothe
}
local canMagic, canEnrage, built = false, false, false
local listeners = {}

local function Knows(spellID, pet)
	if not C_SpellBook then return false end
	local bank = Enum and Enum.SpellBookSpellBank
	local check = C_SpellBook.IsSpellKnownOrInSpellBook or C_SpellBook.IsSpellKnown
	if not check then return false end
	local ok, known = pcall(check, spellID, bank and (pet and bank.Pet or bank.Player))
	return ok and known == true
end

local function Rebuild()
	local oldMagic, oldEnrage = canMagic, canEnrage
	canMagic, canEnrage = false, false
	for i = 1, #OFFENSIVE do
		local entry = OFFENSIVE[i]
		if Knows(entry[1], entry[3]) then
			if entry[2] == "magic" or entry[2] == "both" then canMagic = true end
			if entry[2] == "enrage" or entry[2] == "both" then canEnrage = true end
		end
	end
	if built and (oldMagic ~= canMagic or oldEnrage ~= canEnrage) then
		for i = 1, #listeners do pcall(listeners[i]) end
	end
	built = true
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELLS_CHANGED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
watcher:RegisterEvent("UNIT_PET")
watcher:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_PET" and unit ~= "player" then return end
	Rebuild()
end)

-- canMagic, canEnrage
function Auras.OffensiveDispel()
	if not built then Rebuild() end
	return canMagic, canEnrage
end

function Auras.OnOffensiveChange(fn)
	listeners[#listeners + 1] = fn
end

local function StyleIcon(button, size, border)
	button:SetSize(size, size)
	if button.EnableMouse then pcall(button.EnableMouse, button, false) end
	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 1)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if button.SetIcon then pcall(button.SetIcon, button, icon) end
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon)
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(size < 18) end
	if button.SetDurationCooldown then pcall(button.SetDurationCooldown, button, cooldown) end
	local count = button:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(count, math.max(8, math.floor(size * 0.5)), "OUTLINE")
	count:SetPoint("BOTTOMRIGHT", 1, -1)
	if button.SetApplicationCount then
		if not pcall(button.SetApplicationCount, button, count, {}) then
			pcall(button.SetApplicationCount, button, count)
		end
	end
	if border then
		-- Colored ring; dispel-typed where supported (Magic blue, enrage etc.).
		local ring = {}
		local function Edge(a1, a2, w, h)
			local t = button:CreateTexture(nil, "OVERLAY")
			t:SetPoint(a1)
			t:SetPoint(a2)
			if w then t:SetWidth(w) end
			if h then t:SetHeight(h) end
			t:SetColorTexture(1, 1, 1, 1)
			t:SetVertexColor(border[1], border[2], border[3], 1)
			ring[#ring + 1] = t
		end
		Edge("TOPLEFT", "TOPRIGHT", nil, 2)
		Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
		Edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
		Edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
		local style = DispelStyle()
		local add = button.AddDispelTypeTexture
		if style ~= nil and add then
			for i = 1, #ring do
				pcall(add, button, ring[i], { style = style, showWhenHarmful = true, showWhenHelpful = true, showWithoutDispelType = true })
			end
		end
	end
end

-- groups: list of { key, filter, max, size, border = { r, g, b } or nil }
-- opts: { anchor = point on parent, relPoint, x, y, grow = "RIGHT" | "LEFT" }
function Auras.Icons(parent, unit, groups, opts)
	local container = NewContainer(parent)
	if not container then return nil end
	opts = opts or {}
	container:SetPoint(opts.point or "BOTTOMLEFT", parent, opts.relPoint or "TOPLEFT", opts.x or 0, opts.y or 2)
	container:SetSize(opts.width or parent:GetWidth() or 100, opts.height or 20)
	if container.SetUnit then pcall(container.SetUnit, container, unit or "none") end
	container._soulGroups = {}
	for i = 1, #groups do
		local group = groups[i]
		if container.AddAuraGroup then
			local size = group.size or 18
			local border = group.border
			local ok = pcall(container.AddAuraGroup, container, group.key, group.filter, {
				maxFrameCount = group.max or 4,
				initializeFrame = function(button) StyleIcon(button, size, border) end,
			})
			container._soulGroups[group.key] = ok and true or false
		end
	end
	return container
end

-- One frame-sized outline that appears while `filter` matches an aura.
-- color: base outline color (dispel-typed textures override it).
function Auras.Highlight(parent, unit, filter, color, thickness)
	local container = NewContainer(parent)
	if not container then return nil end
	container:SetAllPoints(parent)
	if container.SetUnit then pcall(container.SetUnit, container, unit or "none") end
	color = color or { 1, 1, 1 }
	thickness = thickness or 2
	container._soulButtons = {}
	local function Init(button)
		local w, h = parent:GetWidth(), parent:GetHeight()
		if type(w) ~= "number" or w < 4 then w = 100 end
		if type(h) ~= "number" or h < 4 then h = 20 end
		button:SetSize(w, h)
		if button.EnableMouse then pcall(button.EnableMouse, button, false) end
		local textures = {}
		local function Edge(a1, a2, wid, hei)
			local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
			t:SetPoint(a1)
			t:SetPoint(a2)
			if wid then t:SetWidth(wid) end
			if hei then t:SetHeight(hei) end
			t:SetColorTexture(1, 1, 1, 1)
			t:SetVertexColor(color[1], color[2], color[3], 1)
			textures[#textures + 1] = t
		end
		Edge("TOPLEFT", "TOPRIGHT", nil, thickness)
		Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness)
		Edge("TOPLEFT", "BOTTOMLEFT", thickness, nil)
		Edge("TOPRIGHT", "BOTTOMRIGHT", thickness, nil)
		local wash = button:CreateTexture(nil, "OVERLAY", nil, 6)
		wash:SetAllPoints()
		wash:SetColorTexture(1, 1, 1, 1)
		wash:SetVertexColor(color[1], color[2], color[3], 0.18)
		textures[#textures + 1] = wash
		local style = DispelStyle()
		local add = button.AddDispelTypeTexture
		if style ~= nil and add then
			for i = 1, #textures do
				pcall(add, button, textures[i], { style = style, showWhenHarmful = true, showWhenHelpful = true, showWithoutDispelType = true })
			end
			-- The engine sets vertex colors; keep the wash faint.
			wash:SetAlpha(0.18)
		end
		container._soulButtons[#container._soulButtons + 1] = button
	end
	if container.AddAuraGroup then
		pcall(container.AddAuraGroup, container, "highlight", filter, {
			maxFrameCount = 1,
			initializeFrame = Init,
		})
	end
	return container
end

-- Re-fits highlight buttons after the parent changed size (out of combat only).
function Auras.Refit(container, parent)
	if not container or not container._soulButtons or InCombatLockdown() then return end
	local w, h = parent:GetWidth(), parent:GetHeight()
	for i = 1, #container._soulButtons do
		pcall(container._soulButtons[i].SetSize, container._soulButtons[i], w, h)
	end
end

function Auras.SetUnit(container, unit)
	if container and container.SetUnit then
		pcall(container.SetUnit, container, unit or "none")
	end
end

function Auras.SetShown(container, shown)
	if not container then return end
	pcall(container.SetShown, container, shown and true or false)
end
