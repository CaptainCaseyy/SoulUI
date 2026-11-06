if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI
local NP = Soul:NewModule("Nameplates", "SoulUI_Nameplates")

-- Hot-path upvalues.
local pairs, type, pcall, floor, max = pairs, type, pcall, math.floor, math.max
local UnitHealth, UnitHealthMax, UnitHealthPercent = UnitHealth, UnitHealthMax, UnitHealthPercent
local UnitIsDeadOrGhost, UnitReaction, UnitIsPlayer, UnitClass = UnitIsDeadOrGhost, UnitReaction, UnitIsPlayer, UnitClass
local UnitIsTapDenied, UnitName, UnitExists, UnitClassification = UnitIsTapDenied, UnitName, UnitExists, UnitClassification
local GetRaidTargetIndex, InCombatLockdown = GetRaidTargetIndex, InCombatLockdown

local REACTION = {
	{ 0.85, 0.15, 0.15 },
	{ 0.85, 0.15, 0.15 },
	{ 0.90, 0.45, 0.10 },
	{ 0.85, 0.80, 0.20 },
}
local TAPPED = { 0.50, 0.50, 0.52 }
local BACKDROP = { 0.06, 0.06, 0.07, 0.90 }

local WATCH = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
}
local HEALTH_EVENT = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_FACTION = true }

-- Classification marks use the game's own nameplate atlases when they exist,
-- otherwise a small flat square in the same color.
local CLASS_MARK = {
	worldboss = { atlas = "nameplates-icon-elite-gold", r = 1, g = 0.78, b = 0.25 },
	elite = { atlas = "nameplates-icon-elite-gold", r = 1, g = 0.78, b = 0.25 },
	rareelite = { atlas = "nameplates-icon-elite-silver", r = 0.78, g = 0.82, b = 0.9 },
	rare = { atlas = "nameplates-icon-elite-silver", r = 0.78, g = 0.82, b = 0.9 },
}
for _, mark in pairs(CLASS_MARK) do
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(mark.atlas)
	if not info then mark.atlas = nil end
end

local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local pool = {}
local byUnit = {}
local hiddenBlizz = {}
local styleGen = 1
-- Last target pass, so a plate added later can be dimmed without a full pass.
local targetState = { dim = false, style = "both", alpha = 1 }

local function DB()
	return Soul:ModuleDB("Nameplates")
end

local function Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- One physical pixel in this plate's own units. Plates hang off WorldFrame,
-- not UIParent, so Soul.Pixel (UIParent based) is off whenever the UI scale
-- is not 1.
local function PlatePixel(visual)
	local _, height = GetPhysicalScreenSize()
	local scale = visual:GetEffectiveScale()
	if type(height) ~= "number" or height < 1 or type(scale) ~= "number" or scale <= 0 then
		return 1
	end
	return 768 / height / scale
end

local function Snap(value, px)
	return floor(value / px + 0.5) * px
end

------------------------------------------------------------------------------
-- Edges and arrows (plain textures and lines, no per-event tables)
------------------------------------------------------------------------------

local function Ring(parent, sub, r, g, b, a)
	local ring = {}
	for _, side in pairs({ "top", "bottom", "left", "right" }) do
		local t = parent:CreateTexture(nil, "OVERLAY", nil, sub)
		t:SetColorTexture(r, g, b, a)
		ring[side] = t
	end
	return ring
end

-- out = how far outside the region the ring sits (0 = drawn on its edge pixels).
local function PlaceRing(ring, region, px, out)
	local t, b, l, r = ring.top, ring.bottom, ring.left, ring.right
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", region, "TOPLEFT", -out, out)
	t:SetPoint("TOPRIGHT", region, "TOPRIGHT", out, out)
	t:SetHeight(px)
	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -out, -out)
	b:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", out, -out)
	b:SetHeight(px)
	l:ClearAllPoints()
	l:SetPoint("TOPLEFT", region, "TOPLEFT", -out, out - px)
	l:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -out, -out + px)
	l:SetWidth(px)
	r:ClearAllPoints()
	r:SetPoint("TOPRIGHT", region, "TOPRIGHT", out, out - px)
	r:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", out, -out + px)
	r:SetWidth(px)
end

local function ColorRing(ring, r, g, b, a)
	ring.top:SetColorTexture(r, g, b, a)
	ring.bottom:SetColorTexture(r, g, b, a)
	ring.left:SetColorTexture(r, g, b, a)
	ring.right:SetColorTexture(r, g, b, a)
end

local function ShowRing(ring, shown)
	ring.top:SetShown(shown)
	ring.bottom:SetShown(shown)
	ring.left:SetShown(shown)
	ring.right:SetShown(shown)
end

-- Two chevrons pointing at the bar from both sides: { l1, l2, r1, r2 }.
local function BuildArrows(visual)
	if not visual.CreateLine then return nil end
	local arrows = {}
	for i = 1, 4 do
		local line = visual:CreateLine(nil, "OVERLAY")
		line:Hide()
		arrows[i] = line
	end
	return arrows
end

local function PlaceArrows(arrows, health, gap, aw, hh, thick)
	if not arrows then return end
	-- Left chevron: ">" whose tip sits `gap` left of the bar.
	arrows[1]:SetStartPoint("LEFT", health, -gap - aw, hh)
	arrows[1]:SetEndPoint("LEFT", health, -gap, 0)
	arrows[2]:SetStartPoint("LEFT", health, -gap - aw, -hh)
	arrows[2]:SetEndPoint("LEFT", health, -gap, 0)
	-- Right chevron: "<".
	arrows[3]:SetStartPoint("RIGHT", health, gap + aw, hh)
	arrows[3]:SetEndPoint("RIGHT", health, gap, 0)
	arrows[4]:SetStartPoint("RIGHT", health, gap + aw, -hh)
	arrows[4]:SetEndPoint("RIGHT", health, gap, 0)
	for i = 1, 4 do arrows[i]:SetThickness(thick) end
end

local function ColorArrows(arrows, r, g, b)
	if not arrows then return end
	for i = 1, 4 do arrows[i]:SetColorTexture(r, g, b, 1) end
end

local function ShowArrows(arrows, shown)
	if not arrows then return end
	for i = 1, 4 do arrows[i]:SetShown(shown) end
end

------------------------------------------------------------------------------
-- Auras
------------------------------------------------------------------------------

-- Purge row and outline follow the setting: "auto" shows them only when you
-- know an offensive dispel (Purge, Dispel Magic, Spellsteal, Soothe,
-- Tranquilizing Shot...), "always" for everyone, "off" never.
local function PurgeWanted()
	local mode = DB().purge or "auto"
	if mode == "off" then return false end
	if mode == "always" then return true end
	local magic, enrage = Soul.Auras.OffensiveDispel()
	return magic or enrage
end

local function ApplyAuraVisibility(visual)
	local cfg = DB()
	Soul.Auras.SetShown(visual.Debuffs, cfg.showDebuffs ~= false)
	local purge = PurgeWanted()
	Soul.Auras.SetShown(visual.Purge, purge)
	Soul.Auras.SetShown(visual.PurgeGlow, purge and cfg.purgeGlow ~= false)
end

-- Aura rows follow the stack computed in ApplyStyle (_auraY, _purgeX).
-- Containers are only moved out of combat.
local function LayoutAuras(visual)
	if not visual._soulAuras or InCombatLockdown() then return end
	local health = visual.Health
	if visual.Debuffs then
		visual.Debuffs:ClearAllPoints()
		visual.Debuffs:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, visual._auraY or 3)
	end
	if visual.Purge then
		visual.Purge:ClearAllPoints()
		visual.Purge:SetPoint("LEFT", health, "RIGHT", visual._purgeX or 4, 0)
	end
	if visual.PurgeGlow then Soul.Auras.Refit(visual.PurgeGlow, health) end
end

-- Aura rows are built lazily the first time a plate is used out of combat
-- (and for any plate still missing them when combat ends), so login does not
-- build 90 containers at once. Sizes are fixed when the container is made.
local function EnsureAuras(visual)
	if visual._soulAuras or InCombatLockdown() then return end
	visual._soulAuras = true
	local health = visual.Health
	local cfg = DB()
	local debuffSize = cfg.debuffSize or 20
	local purgeSize = cfg.purgeSize or 20
	visual.Debuffs = Soul.Auras.Icons(visual, "none", {
		{ key = "mine", filter = "HARMFUL|PLAYER", max = cfg.debuffMax or 5, size = debuffSize },
	}, { point = "BOTTOMLEFT", relPoint = "TOPLEFT", x = 0, y = 3, width = cfg.width, height = debuffSize })
	visual.Purge = Soul.Auras.Icons(visual, "none", {
		{ key = "purge", filter = "HELPFUL|DISPELLABLE", max = 3, size = purgeSize, border = { 0.25, 0.65, 1 } },
	}, { width = purgeSize * 3 + 6, height = purgeSize })
	visual.PurgeGlow = Soul.Auras.Highlight(health, "none", "HELPFUL|DISPELLABLE", { 0.25, 0.65, 1 }, 2)
	LayoutAuras(visual)
end

------------------------------------------------------------------------------
-- Unit data
------------------------------------------------------------------------------

local function Hostile(unit)
	local reaction = UnitReaction(unit, "player")
	-- A secret reaction means we cannot tell friend from foe. Leave Blizzard's plate alone.
	if Soul.Secret.IsSecret(reaction) or type(reaction) ~= "number" then
		return false
	end
	return reaction < 5
end

local function ColorBar(bar, unit)
	local tapped = UnitIsTapDenied(unit)
	if not Soul.Secret.IsSecret(tapped) and tapped then
		bar:SetStatusBarColor(TAPPED[1], TAPPED[2], TAPPED[3])
		return
	end
	local player = UnitIsPlayer(unit)
	if not Soul.Secret.IsSecret(player) and player then
		local _, class = UnitClass(unit)
		if Soul.Secret.IsSecret(class) then
			local color = C_ClassColor and C_ClassColor.GetClassColor(class)
			if color then
				bar:SetStatusBarColor(color:GetRGB())
				return
			end
		elseif type(class) == "string" then
			local color = RAID_CLASS_COLORS[class]
			if color then
				bar:SetStatusBarColor(color.r, color.g, color.b)
				return
			end
		end
	end
	local reaction = UnitReaction(unit, "player")
	if Soul.Secret.IsSecret(reaction) or type(reaction) ~= "number" then
		bar:SetStatusBarColor(0.85, 0.15, 0.15)
		return
	end
	local color = REACTION[reaction] or REACTION[2]
	bar:SetStatusBarColor(color[1], color[2], color[3])
end

local function UpdateHealth(visual)
	local unit = visual.unit
	if not unit then return end
	local bar = visual.Health
	local dead = UnitIsDeadOrGhost(unit)
	if not Soul.Secret.IsSecret(dead) and dead then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		return
	end
	bar:SetMinMaxValues(0, UnitHealthMax(unit))
	bar:SetValue(UnitHealth(unit))
	ColorBar(bar, unit)
	if visual._showPct then
		local curve = CurveConstants and CurveConstants.ScaleTo100
		if curve then
			visual.HealthText:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve))
		end
	end
end

local function UpdateName(visual)
	if not visual.unit then return end
	if not DB().showName then
		visual.Name:SetText("")
		return
	end
	-- Possibly secret: display only. Width is fixed and word wrap is off, so
	-- long names end in "..." without Lua measuring them.
	local name = UnitName(visual.unit)
	visual.Name:SetText(name or "")
end

-- Name sits after the classification mark when one is shown.
local function PlaceName(visual)
	local name = visual.Name
	local width = visual._w or 140
	local shift = 0
	if visual.Class:IsShown() then shift = (visual._classSize or 10) + 2 end
	name:ClearAllPoints()
	if visual._nameAbove then
		name:SetPoint("BOTTOMLEFT", visual.Health, "TOPLEFT", shift, visual._gap or 2)
		name:SetWidth(max(10, width - shift))
	else
		name:SetPoint("LEFT", visual.Health, "LEFT", 4 + shift, 0)
		name:SetWidth(max(10, width - 8 - shift - (visual._pctReserve or 0)))
	end
end

local function UpdateClassification(visual)
	local unit = visual.unit
	local icon = visual.Class
	local mark
	if unit and DB().showClassification ~= false and DB().showName then
		local kind = UnitClassification(unit)
		if not Soul.Secret.IsSecret(kind) and type(kind) == "string" then
			mark = CLASS_MARK[kind]
		end
	end
	if mark then
		if mark.atlas then
			icon:SetAtlas(mark.atlas)
			icon:SetVertexColor(1, 1, 1, 1)
		else
			icon:SetColorTexture(mark.r, mark.g, mark.b, 1)
		end
		icon:Show()
	else
		icon:Hide()
	end
	PlaceName(visual)
end

local function UpdateRaidMarker(visual)
	local icon = visual.Marker
	local unit = visual.unit
	if not unit or DB().raidMarker == "off" then
		icon:Hide()
		return
	end
	local index = GetRaidTargetIndex(unit)
	if type(index) == "nil" then
		icon:Hide()
		return
	end
	if Soul.Secret.IsSecret(index) then
		-- Blizzard's helper may cope with a secret index; if it throws, hide.
		local ok = SetRaidTargetIconTexture and pcall(SetRaidTargetIconTexture, icon, index)
		icon:SetShown(ok and true or false)
		return
	end
	if type(index) ~= "number" or index < 1 or index > 8 then
		icon:Hide()
		return
	end
	local col = (index - 1) % 4
	local row = floor((index - 1) / 4)
	icon:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
	icon:Show()
end

local function UpdateVisual(visual, event)
	if not event or event == "SHOW" then
		UpdateHealth(visual)
		UpdateName(visual)
		UpdateClassification(visual)
		UpdateRaidMarker(visual)
		visual.Cast:SetUnit(visual.unit)
		visual.Cast:Reset()
	elseif HEALTH_EVENT[event] then
		UpdateHealth(visual)
	elseif event == "UNIT_NAME_UPDATE" then
		UpdateName(visual)
	elseif event == "UNIT_CLASSIFICATION_CHANGED" then
		UpdateClassification(visual)
	elseif Soul.CastBar.IsCastEvent(event) then
		visual.Cast:HandleEvent(event)
	end
end

------------------------------------------------------------------------------
-- Style
------------------------------------------------------------------------------

-- Plate stack, top to bottom: raid marker (top mode), your debuffs, name
-- (above mode), health bar, cast bar. Purge row to the right of the health
-- bar, raid marker (left mode) to the left. One spacing value separates all
-- of them; chevrons get their own lane so nothing moves when you target.
local function ApplyStyle(visual)
	local cfg = DB()
	local px = PlatePixel(visual)
	visual._px = px
	visual._gen = styleGen
	local w = Snap(cfg.width or 140, px)
	local h = Snap(cfg.height or 16, px)
	local gap = max(px, Snap(cfg.spacing or 2, px))
	visual._w, visual._gap = w, gap
	visual:SetSize(w, h)
	if visual.SetClipsChildren then visual:SetClipsChildren(false) end

	local health = visual.Health
	health:ClearAllPoints()
	health:SetPoint("TOPLEFT")
	health:SetPoint("TOPRIGHT")
	health:SetHeight(h)
	health:SetStatusBarTexture(Soul:StatusbarTexture())
	health.bg:SetColorTexture(BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	PlaceRing(visual.Border, health, px, 0)

	-- Text.
	local nameAbove = cfg.namePos ~= "inside"
	local showName = cfg.showName and true or false
	visual._nameAbove = nameAbove
	local nameSize = cfg.nameSize or 0
	if nameSize <= 0 then
		if nameAbove then
			nameSize = Clamp(floor(h * 0.25 + 8.5), 9, 16)
		else
			nameSize = Clamp(h - 5, 8, 16)
		end
	end
	local pctSize = cfg.percentSize or 0
	if pctSize <= 0 then pctSize = Clamp(floor(h * 0.62 + 1.5), 8, 16) end
	local showPct = cfg.showPercent ~= false
	visual._showPct = showPct
	visual._pctReserve = showPct and floor(pctSize * 2.6 + 0.5) or 0
	Soul:ApplyFont(visual.Name, nameSize, "OUTLINE")
	Soul:ApplyFont(visual.HealthText, pctSize, "OUTLINE")
	visual.HealthText:SetShown(showPct)
	if not showPct then visual.HealthText:SetText("") end

	-- Classification mark beside the name.
	local classSize = nameAbove and nameSize or Clamp(h - 4, 8, nameSize + 2)
	visual._classSize = classSize
	local icon = visual.Class
	icon:ClearAllPoints()
	icon:SetSize(classSize, classSize)
	if nameAbove then
		icon:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, gap + 1)
	else
		icon:SetPoint("LEFT", health, "LEFT", 3, 0)
	end
	PlaceName(visual)

	-- Target indicator.
	local r, g, b = Soul:Accent()
	PlaceRing(visual.TargetRing, health, px, px)
	ColorRing(visual.TargetRing, r, g, b, 1)
	local style = cfg.targetStyle or "both"
	local arrowLane = 0
	if visual.Arrows then
		local hh = Snap(Clamp(h * 0.4, 4, 9), px)
		local aw = Snap(hh * 0.75, px)
		local thick = max(px, Snap(2, px))
		PlaceArrows(visual.Arrows, health, gap + px, aw, hh, thick)
		ColorArrows(visual.Arrows, r, g, b)
		if style == "arrows" or style == "both" then arrowLane = aw + gap + thick end
	end
	visual.Highlight:SetColorTexture(r, g, b, 0.6)

	-- Raid marker.
	local markerSize = cfg.raidMarkerSize or 0
	if markerSize <= 0 then markerSize = Clamp(h + 4, 14, 28) end
	local nameBlock = (showName and nameAbove) and (nameSize + gap) or 0
	local auraY = gap + nameBlock
	local marker = visual.Marker
	marker:ClearAllPoints()
	marker:SetSize(markerSize, markerSize)
	if cfg.raidMarker == "top" then
		local debuffBlock = cfg.showDebuffs ~= false and ((cfg.debuffSize or 20) + gap) or 0
		marker:SetPoint("BOTTOM", health, "TOP", 0, auraY + debuffBlock)
	else
		marker:SetPoint("RIGHT", health, "LEFT", -(gap + arrowLane), 0)
	end

	-- Cast bar under the health bar (the cast frame draws its own 1px edge).
	local cast = visual.Cast
	cast:ClearAllPoints()
	cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -gap)
	cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -gap)
	cast:Layout(cfg.castHeight, cfg.castIcon ~= false, cfg.castFont or 0)

	visual._auraY = auraY
	visual._purgeX = gap + 1 + arrowLane
	LayoutAuras(visual)
end

local function BuildPlate(index)
	local visual = CreateFrame("Frame", nil, UIParent)
	visual.index = index
	visual:Hide()
	visual:EnableMouse(false)
	Soul:Round(visual)
	local health = Soul:StatusBar(visual)
	visual.Health = health
	-- "glow" target style: accent wash behind the bar.
	local highlight = visual:CreateTexture(nil, "BACKGROUND")
	highlight:SetPoint("TOPLEFT", health, "TOPLEFT", -2, 2)
	highlight:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 2, -2)
	highlight:Hide()
	visual.Highlight = highlight
	visual.Border = Ring(health, 7, 0, 0, 0, 1)
	visual.TargetRing = Ring(health, 6, 1, 1, 1, 1)
	ShowRing(visual.TargetRing, false)
	visual.Arrows = BuildArrows(visual)

	local name = health:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	if name.SetMaxLines then name:SetMaxLines(1) end
	name:SetTextColor(0.95, 0.95, 0.95)
	visual.Name = name
	local percent = health:CreateFontString(nil, "OVERLAY")
	percent:SetPoint("RIGHT", -4, 0)
	percent:SetJustifyH("RIGHT")
	percent:SetWordWrap(false)
	percent:SetTextColor(0.95, 0.95, 0.95)
	visual.HealthText = percent

	local class = health:CreateTexture(nil, "OVERLAY", nil, 2)
	class:Hide()
	visual.Class = class
	local marker = health:CreateTexture(nil, "OVERLAY", nil, 3)
	marker:SetTexture(RAID_ICONS)
	marker:Hide()
	visual.Marker = marker

	local cast = Soul.CastBar.New(visual, { enemy = true })
	cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
	cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -2)
	cast.allowed = function() return DB().showCast and visual.unit ~= nil end
	visual.Cast = cast
	visual.CastBar = cast.Bar
	pool[index] = visual
	return visual
end

------------------------------------------------------------------------------
-- Target indicator and dimming
------------------------------------------------------------------------------

local function ApplyTarget(visual, isTarget, dim, style, alpha)
	ShowRing(visual.TargetRing, isTarget and (style == "border" or style == "both"))
	ShowArrows(visual.Arrows, isTarget and (style == "arrows" or style == "both"))
	visual.Highlight:SetShown(isTarget and style == "glow")
	visual:SetAlpha(dim and alpha or 1)
end

local function TargetSettings()
	local cfg = DB()
	local alpha = cfg.nonTargetAlpha
	if type(alpha) ~= "number" then alpha = 1 end
	targetState.style = cfg.targetStyle or "both"
	targetState.alpha = Clamp(alpha, 0.2, 1)
end

local function MarkTarget()
	TargetSettings()
	local style, alpha = targetState.style, targetState.alpha
	local targetPlate = C_NamePlate.GetNamePlateForUnit("target", false)
	-- Dim the others only while the target is one of our (enemy) plates.
	local ours = false
	if targetPlate and UnitExists("target") then
		for _, visual in pairs(byUnit) do
			if visual.plate == targetPlate then ours = true break end
		end
	end
	targetState.dim = ours
	for _, visual in pairs(byUnit) do
		local isTarget = ours and visual.plate == targetPlate
		visual._isTarget = isTarget
		ApplyTarget(visual, isTarget, ours and not isTarget, style, alpha)
	end
end

-- A plate that just appeared: a full pass only when it is the target.
local function MarkNewPlate(visual)
	if visual.plate == C_NamePlate.GetNamePlateForUnit("target", false) then
		MarkTarget()
		return
	end
	visual._isTarget = false
	ApplyTarget(visual, false, targetState.dim, targetState.style, targetState.alpha)
end

------------------------------------------------------------------------------
-- Plate lifecycle
------------------------------------------------------------------------------

local function RestorePlate(plate)
	if not plate or not hiddenBlizz[plate] then return end
	local unitFrame = plate.UnitFrame
	if unitFrame and not unitFrame:IsForbidden() then
		unitFrame:SetAlpha(1)
		if unitFrame.EnableMouse then unitFrame:EnableMouse(true) end
	end
	hiddenBlizz[plate] = nil
end

local function TakeOver(plate)
	local unitFrame = plate.UnitFrame
	if unitFrame and not unitFrame:IsForbidden() then
		unitFrame:SetAlpha(0)
		if unitFrame.EnableMouse then unitFrame:EnableMouse(false) end
		hiddenBlizz[plate] = true
	end
end

local function Acquire()
	for i = 1, #pool do
		if not pool[i].unit then
			return pool[i]
		end
	end
	return BuildPlate(#pool + 1)
end

local function Release(visual)
	if not visual then return end
	local plate = visual.plate
	visual:Hide()
	visual:ClearAllPoints()
	visual.unit = nil
	visual.plate = nil
	visual.Cast:Stop()
	visual.Cast:SetUnit(nil)
	visual._isTarget = false
	ApplyTarget(visual, false, false)
	visual.Marker:Hide()
	visual.Class:Hide()
	Soul.Auras.SetUnit(visual.Debuffs, "none")
	Soul.Auras.SetUnit(visual.Purge, "none")
	Soul.Auras.SetUnit(visual.PurgeGlow, "none")
	if plate then RestorePlate(plate) end
end

local function WatchUnit(unit)
	for i = 1, #WATCH do
		pcall(NP.RegisterUnitEvent, NP, WATCH[i], NP.OnUnitEvent, unit)
	end
end

local function UnwatchUnit(unit)
	for i = 1, #WATCH do
		pcall(NP.UnregisterUnitEvent, NP, WATCH[i], unit)
	end
end

function NP:OnUnitEvent(event, unit)
	local visual = byUnit[unit]
	if visual then
		UpdateVisual(visual, event)
	end
end

function NP:AddPlate(_, unit)
	local cfg = DB()
	if not cfg.enabled then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
	if not plate or plate:IsForbidden() then return end
	if not Hostile(unit) then
		RestorePlate(plate)
		return
	end
	local visual = byUnit[unit]
	if visual and visual.plate ~= plate then
		Release(visual)
		byUnit[unit] = nil
		visual = nil
	end
	if not visual then
		visual = Acquire()
		visual.unit = unit
		byUnit[unit] = visual
		WatchUnit(unit)
	end
	visual.plate = plate
	TakeOver(plate)
	-- Only Blizzard's UnitFrame is faded. The nameplate itself stays, so a boss
	-- mod can still attach icons to it. Our bar sits just above that frame.
	visual:SetParent(plate)
	visual:ClearAllPoints()
	visual:SetPoint("CENTER", plate, "CENTER", 0, 0)
	local level = plate:GetFrameLevel() or 1
	visual:SetFrameLevel(level + 2)
	-- Restyle only when settings changed or this plate's pixel size differs.
	if visual._gen ~= styleGen or visual._px ~= PlatePixel(visual) then
		ApplyStyle(visual)
	end
	EnsureAuras(visual)
	Soul.Auras.SetUnit(visual.Debuffs, unit)
	Soul.Auras.SetUnit(visual.Purge, unit)
	Soul.Auras.SetUnit(visual.PurgeGlow, unit)
	ApplyAuraVisibility(visual)
	visual:Show()
	UpdateVisual(visual, "SHOW")
	MarkNewPlate(visual)
end

function NP:RemovePlate(_, unit)
	local visual = byUnit[unit]
	if not visual then return end
	local wasTarget = visual._isTarget
	UnwatchUnit(unit)
	byUnit[unit] = nil
	Release(visual)
	-- The target's plate left the screen: stop dimming the rest.
	if wasTarget then MarkTarget() end
end

function NP:ApplyCVars()
	local cfg = DB()
	if not cfg.manageCVars then return end
	Soul:SetOwnedCVar("nameplateShowEnemies", "1", "Nameplates")
	Soul:SetOwnedCVar("nameplateShowAll", cfg.showAll and "1" or "0", "Nameplates")
	Soul:SetOwnedCVar("nameplateMotion", cfg.stack and "1" or "0", "Nameplates")
	if cfg.stack then
		Soul:SetOwnedCVar("nameplateOverlapH", "0.4", "Nameplates")
		Soul:SetOwnedCVar("nameplateOverlapV", "0.4", "Nameplates")
	end
end

function NP:Rescan()
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitExists(unit) then
			self:AddPlate(nil, unit)
		end
	end
end

function NP:Apply()
	self:ApplyCVars()
	styleGen = styleGen + 1
	if not DB().enabled then
		local units = {}
		for unit in pairs(byUnit) do
			units[#units + 1] = unit
		end
		for i = 1, #units do
			local unit = units[i]
			local visual = byUnit[unit]
			UnwatchUnit(unit)
			byUnit[unit] = nil
			Release(visual)
		end
		return
	end
	for i = 1, #pool do
		if not InCombatLockdown() then ApplyAuraVisibility(pool[i]) end
	end
	for _, visual in pairs(byUnit) do
		ApplyStyle(visual)
		if visual.unit then
			UpdateVisual(visual, "SHOW")
		end
	end
	self:Rescan()
	MarkTarget()
	if self.LayoutSample and self.sample and self.sample:IsShown() then
		self:LayoutSample()
	end
end

function NP:OnInitialize()
	Soul:RegisterModuleDB("Nameplates", Soul.Defaults.Nameplates)
end

function NP:OnEnable()
	for i = 1, 30 do
		BuildPlate(i)
	end
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		for _, visual in pairs(byUnit) do
			if not visual._soulAuras then
				EnsureAuras(visual)
				Soul.Auras.SetUnit(visual.Debuffs, visual.unit)
				Soul.Auras.SetUnit(visual.Purge, visual.unit)
				Soul.Auras.SetUnit(visual.PurgeGlow, visual.unit)
				ApplyAuraVisibility(visual)
			else
				-- Restyles during combat could not move the aura rows.
				LayoutAuras(visual)
			end
		end
	end)
	Soul.Auras.OnOffensiveChange(function()
		Soul:RunAfterCombat("np:purge", function()
			for i = 1, #pool do ApplyAuraVisibility(pool[i]) end
		end)
	end)
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(mod, _, unit) mod:AddPlate(_, unit) end)
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(mod, _, unit) mod:RemovePlate(_, unit) end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() MarkTarget() end)
	self:RegisterEvent("RAID_TARGET_UPDATE", function()
		for _, visual in pairs(byUnit) do UpdateRaidMarker(visual) end
	end)
	-- Your interrupt coming off cooldown recolors casts already on screen.
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
		local ready = Soul.Cast.KickReady()
		for _, visual in pairs(byUnit) do
			if visual.Cast:IsShown() then Soul.Cast.Recolor(visual.Cast, visual.CastBar, ready) end
		end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(mod)
		-- Existing plates are not re-fired after a reload. Ask each one.
		-- GetNamePlates is not required; nameplate1..40 covers the same set
		-- and does not throw if the nameplate API is missing.
		if not C_NamePlate then return end
		mod:Rescan()
	end)
	Soul:On("ProfileChanged", function() NP:Apply() end)
	Soul:On("ThemeChanged", function() NP:Apply() end)
	self:ApplyCVars()
	-- PLAYER_ENTERING_WORLD can already have fired by the time this addon
	-- enables. Scan whatever plates are on screen now, or the first login
	-- shows no nameplates until the next zone.
	self:Rescan()

	-- Edit-mode sample. Dragging it does not move plates in the world.
	-- Scrolling it changes the width, health height and cast height of every plate.
	local sample = CreateFrame("Frame", "SoulUINameplateSample", UIParent)
	sample:Hide()
	sample:EnableMouse(false)
	local sampleHealth = Soul:StatusBar(sample)
	sampleHealth:SetStatusBarTexture(Soul:StatusbarTexture())
	sampleHealth:SetMinMaxValues(0, 1)
	sampleHealth:SetValue(0.72)
	sampleHealth:SetStatusBarColor(0.85, 0.15, 0.15)
	local sampleName = sampleHealth:CreateFontString(nil, "OVERLAY")
	sampleName:SetPoint("LEFT", 4, 0)
	sampleName:SetJustifyH("LEFT")
	sampleName:SetTextColor(0.95, 0.95, 0.95)
	sampleName:SetText("Nameplate")
	local sampleCast = Soul.CastBar.New(sample, { enemy = true, name = "SoulUINameplateSampleCast" })
	sampleCast.allowed = function() return false end

	local function SizePixel()
		for key, visual in pairs(byUnit) do
			if key then return PlatePixel(visual) end
		end
		return PlatePixel(sample)
	end

	local function LayoutSample()
		local cfg = DB()
		local w = cfg.width or 140
		local h = cfg.height or 16
		local gap = cfg.spacing or 2
		if gap < 0 then gap = 0 end
		local showCast = cfg.showCast ~= false
		local castH = showCast and (cfg.castHeight or 12) or 0
		sampleHealth:ClearAllPoints()
		sampleHealth:SetPoint("TOPLEFT")
		sampleHealth:SetPoint("TOPRIGHT")
		sampleHealth:SetHeight(h)
		Soul:ApplyFont(sampleName, math.max(8, math.min(16, math.floor(h * 0.7 + 0.5))), "OUTLINE")
		sampleCast:ClearAllPoints()
		local stack = h
		if showCast then
			sampleCast:SetPoint("TOPLEFT", sampleHealth, "BOTTOMLEFT", 0, -gap)
			sampleCast:SetPoint("TOPRIGHT", sampleHealth, "BOTTOMRIGHT", 0, -gap)
			sampleCast:Layout(castH, cfg.castIcon ~= false, cfg.castFont or 0)
			sampleCast:SetPreview(true)
			stack = h + gap + (sampleCast:GetHeight() or castH)
		else
			sampleCast:SetPreview(false)
			sampleCast:Hide()
		end
		sample:SetSize(w, stack)
	end

	local function GhostsOn()
		local account = Soul.db and Soul.db.account
		local edit = account and account.edit
		if not edit or edit.ghosts == nil then return true end
		return edit.ghosts and true or false
	end

	local function Restyle()
		styleGen = styleGen + 1
		for key, visual in pairs(byUnit) do
			if key then ApplyStyle(visual) end
		end
		if sample:IsShown() then LayoutSample() end
	end

	NP.sample = sample
	NP.LayoutSample = LayoutSample

	Soul:RegisterMover({
		key = "Nameplates:sample",
		label = "Nameplates",
		getFrame = function() return sample end,
		getEnabled = function() return DB().enabled end,
		setEnabled = function(on)
			DB().enabled = on and true or false
			NP:Apply()
			if sample:IsShown() then LayoutSample() end
		end,
		fallback = function()
			return { point = "CENTER", relPoint = "CENTER", x = 0, y = 220 }
		end,
		onResize = function(width, height, dir)
			local cfg = DB()
			local px = SizePixel()
			local oldW = cfg.width or 140
			local oldH = cfg.height or 16
			local oldCast = cfg.castHeight or 12
			if dir == 1 or dir == -1 then
				cfg.width = Soul:ScaleStep(oldW, dir, 40, 300, px)
				cfg.height = Soul:ScaleStep(oldH, dir, 4, 48, px)
				if cfg.showCast ~= false then
					cfg.castHeight = Soul:ScaleStep(oldCast, dir, 6, 40, px)
				end
			else
				cfg.width = Soul:MatchSize(oldW, width, 40, 300, px)
				local castH = cfg.showCast ~= false and oldCast or 0
				local gap = cfg.spacing or 2
				local healthH = height - castH - (castH > 0 and gap or 0)
				cfg.height = Soul:MatchSize(oldH, healthH, 4, 48, px)
			end
			Restyle()
		end,
		onEdit = function(on)
			if on and (DB().enabled or GhostsOn()) then
				sample:Show()
				LayoutSample()
				Soul:Place(sample, "Nameplates:sample", {
					point = "CENTER", relPoint = "CENTER", x = 0, y = 220,
				})
			else
				sampleCast:SetPreview(false)
				sample:Hide()
			end
		end,
	})
end
