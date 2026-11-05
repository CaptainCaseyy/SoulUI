if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI
local NP = Soul:NewModule("Nameplates", "SoulUI_Nameplates")

local REACTION = {
	{ 0.85, 0.15, 0.15 },
	{ 0.85, 0.15, 0.15 },
	{ 0.90, 0.45, 0.10 },
	{ 0.85, 0.80, 0.20 },
}

local WATCH = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FACTION",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
}

local CAST_END = {
	UNIT_SPELLCAST_STOP = true,
	UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_FAILED_QUIET = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_EMPOWER_STOP = true,
}

local pool = {}
local byUnit = {}
local hiddenBlizz = {}

local function DB()
	return Soul:ModuleDB("Nameplates")
end

local function Hostile(unit)
	local reaction = UnitReaction(unit, "player")
	-- A secret reaction means we cannot tell friend from foe. Leave Blizzard's plate alone.
	if Soul.Secret.IsSecret(reaction) or type(reaction) ~= "number" then
		return false
	end
	return reaction < 5
end

local function ColorBar(bar, unit)
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
	local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
	if interp then
		bar:SetValue(UnitHealth(unit), interp)
	else
		bar:SetValue(UnitHealth(unit))
	end
	ColorBar(bar, unit)
	local curve = CurveConstants and CurveConstants.ScaleTo100
	if curve then
		visual.HealthText:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve))
	end
end

local function UpdateName(visual)
	if not visual.unit then return end
	local cfg = DB()
	if not cfg.showName then
		visual.Name:SetText("")
		return
	end
	local name = UnitName(visual.unit)
	visual.Name:SetText(name or "")
end

local function ShowCast(visual, channel)
	local unit = visual.unit
	local duration
	if channel then
		duration = UnitChannelDuration(unit)
	else
		duration = UnitCastingDuration(unit)
	end
	if not Soul.Secret.Present(duration) then
		visual.Cast:Hide()
		return
	end
	local info, notInterruptible
	if channel then
		info = { UnitChannelInfo(unit) }
		notInterruptible = info[7]
	else
		info = { UnitCastingInfo(unit) }
		notInterruptible = info[8]
	end
	local name, texture = info[1], info[3]
	visual.CastText:SetText(name or "")
	if Soul.Secret.Present(texture) then
		pcall(visual.CastIcon.SetTexture, visual.CastIcon, texture)
	end
	local direction = Enum.StatusBarTimerDirection
	local interp = Enum.StatusBarInterpolation
	if not (visual.CastBar.SetTimerDuration and direction and interp) then
		visual.Cast:Hide()
		return
	end
	local which = channel and direction.RemainingTime or direction.ElapsedTime
	local ok = pcall(visual.CastBar.SetTimerDuration, visual.CastBar, duration, interp.Immediate, which)
	if not ok then
		visual.Cast:Hide()
		return
	end
	if visual.CastBar.SetToTargetValue then visual.CastBar:SetToTargetValue() end
	local r, g, b = Soul:Accent()
	local picked = Soul.Secret.PickColor(notInterruptible, CreateColor(r, g, b, 1), CreateColor(0.45, 0.45, 0.48, 1))
	if picked and picked.GetRGB then
		visual.CastBar:SetStatusBarColor(picked:GetRGB())
	end
	visual.Cast:Show()
end

local function RefreshCast(visual)
	local unit = visual.unit
	if not unit or not DB().showCast then
		visual.Cast:Hide()
		return
	end
	local casting = UnitCastingInfo(unit)
	if Soul.Secret.Present(casting) then
		ShowCast(visual, false)
		return
	end
	local channel = UnitChannelInfo(unit)
	if Soul.Secret.Present(channel) then
		ShowCast(visual, true)
	else
		visual.Cast:Hide()
	end
end

local function UpdateVisual(visual, event)
	UpdateHealth(visual)
	UpdateName(visual)
	if not event or event == "SHOW" or (type(event) == "string" and event:find("SPELLCAST", 1, true)) then
		if CAST_END[event] then
			visual.Cast:Hide()
		elseif event == "UNIT_SPELLCAST_START" then
			ShowCast(visual, false)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
			ShowCast(visual, true)
		else
			RefreshCast(visual)
		end
	end
end

local function ApplyStyle(visual)
	local cfg = DB()
	visual:SetSize(cfg.width, cfg.height)
	if visual.SetClipsChildren then visual:SetClipsChildren(false) end
	visual.Health:ClearAllPoints()
	visual.Health:SetPoint("TOPLEFT")
	visual.Health:SetPoint("TOPRIGHT")
	visual.Health:SetHeight(cfg.height)
	visual.Name:SetWidth(math.max(20, cfg.width - 48))
	Soul:ApplyFont(visual.Name, math.max(10, cfg.height - 4), "OUTLINE")
	Soul:ApplyFont(visual.HealthText, math.max(9, cfg.height - 5), "OUTLINE")
	visual.Cast:SetHeight(cfg.castHeight)
	visual.CastIcon:SetSize(cfg.castHeight, cfg.castHeight)
	local tex = Soul:StatusbarTexture()
	visual.Health:SetStatusBarTexture(tex)
	visual.CastBar:SetStatusBarTexture(tex)
	local r, g, b = Soul:Accent()
	visual.Highlight:SetColorTexture(r, g, b, 0.95)
end

local function BuildPlate(index)
	local visual = CreateFrame("Frame", nil, UIParent)
	visual.index = index
	visual:Hide()
	visual:EnableMouse(false)
	Soul:Round(visual)
	local health = Soul:StatusBar(visual)
	visual.Health = health
	local highlight = visual:CreateTexture(nil, "BACKGROUND")
	highlight:SetPoint("TOPLEFT", health, "TOPLEFT", -2, 2)
	highlight:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 2, -2)
	highlight:Hide()
	visual.Highlight = highlight
	local name = health:CreateFontString(nil, "OVERLAY")
	name:SetPoint("LEFT", 4, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	name:SetTextColor(0.95, 0.95, 0.95)
	visual.Name = name
	local percent = health:CreateFontString(nil, "OVERLAY")
	percent:SetPoint("RIGHT", -4, 0)
	percent:SetJustifyH("RIGHT")
	percent:SetTextColor(0.95, 0.95, 0.95)
	visual.HealthText = percent
	local cast = CreateFrame("Frame", nil, visual)
	cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -1)
	cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -1)
	cast:Hide()
	cast:EnableMouse(false)
	local icon = cast:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	visual.CastIcon = icon
	local bar = Soul:StatusBar(cast)
	bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 1, 0)
	bar:SetPoint("BOTTOMRIGHT")
	visual.CastBar = bar
	local text = bar:CreateFontString(nil, "OVERLAY")
	text:SetPoint("LEFT", 4, 0)
	text:SetPoint("RIGHT", -4, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	text:SetTextColor(0.95, 0.95, 0.95)
	Soul:ApplyFont(text, 10, "OUTLINE")
	visual.CastText = text
	visual.Cast = cast
	Soul:Border(health)
	pool[index] = visual
	return visual
end

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
	visual.Highlight:Hide()
	if plate then RestorePlate(plate) end
end

local function MarkTarget()
	local targetPlate = C_NamePlate.GetNamePlateForUnit("target", false)
	for _, visual in pairs(byUnit) do
		if visual.plate and visual.plate == targetPlate then
			visual.Highlight:Show()
		else
			visual.Highlight:Hide()
		end
	end
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
	visual:SetParent(plate)
	visual:ClearAllPoints()
	visual:SetPoint("CENTER", plate, "CENTER", 0, 0)
	local level = plate:GetFrameLevel() or 1
	visual:SetFrameLevel(level + 5)
	ApplyStyle(visual)
	visual:Show()
	UpdateVisual(visual, "SHOW")
	MarkTarget()
end

function NP:RemovePlate(_, unit)
	local visual = byUnit[unit]
	if not visual then return end
	UnwatchUnit(unit)
	byUnit[unit] = nil
	Release(visual)
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
	for _, visual in pairs(byUnit) do
		ApplyStyle(visual)
		if visual.unit then
			UpdateVisual(visual, "SHOW")
		end
	end
	self:Rescan()
end

function NP:OnInitialize()
	Soul:RegisterModuleDB("Nameplates", Soul.Defaults.Nameplates)
end

function NP:OnEnable()
	for i = 1, 20 do
		BuildPlate(i)
	end
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(mod, _, unit) mod:AddPlate(_, unit) end)
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(mod, _, unit) mod:RemovePlate(_, unit) end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() MarkTarget() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(mod)
		local plates = C_NamePlate.GetNamePlates()
		if type(plates) ~= "table" then return end
		-- Existing plates are not re-fired after a reload. Ask each one.
		for i = 1, 40 do
			local unit = "nameplate" .. i
			if UnitExists(unit) then
				mod:AddPlate(nil, unit)
			end
		end
	end)
	Soul:On("ProfileChanged", function() NP:Apply() end)
	Soul:On("ThemeChanged", function() NP:Apply() end)
	self:ApplyCVars()
end
