if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI
local GF = Soul:NewModule("GroupFrames", "SoulUI_GroupFrames")

local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitIsConnected = UnitIsConnected
local UnitIsUnit = UnitIsUnit
local UnitInRange = UnitInRange
local UnitName = UnitName
local UnitClass = UnitClass
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitHealthPercent = UnitHealthPercent
local UnitHealthMissing = UnitHealthMissing
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitPowerType = UnitPowerType
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerPercent = UnitPowerPercent
local GetRaidTargetIndex = GetRaidTargetIndex
local GetReadyCheckStatus = GetReadyCheckStatus
local GetTime = GetTime
local issecretvalue = issecretvalue
local floor = math.floor

local styled = {}
local unitToButton = {}
local buttonUnit = {}
local originalParent = {}
local hiddenParent
local roleAPI = true

-- Ready check state (plain values, module wide).
local readyActive = false
local readyFinished = false
local readyHideAt = 0
local READY_TEXTURE = {
	ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
	notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
	waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

-- Status labels: text and color.
local STATE_DEAD = { "DEAD", 0.92, 0.36, 0.36 }
local STATE_GHOST = { "GHOST", 0.75, 0.75, 0.85 }
local STATE_OFFLINE = { "OFFLINE", 0.62, 0.62, 0.62 }

local CLICK = [=[
self:SetWidth(self:GetParent():GetAttribute("soul-width") or 80)
self:SetHeight(self:GetParent():GetAttribute("soul-height") or 36)
self:SetAttribute("type1", "target")
self:SetAttribute("*type1", "target")
self:SetAttribute("type2", "togglemenu")
self:SetAttribute("*type2", "togglemenu")
]=]

local function DB()
	return Soul:ModuleDB("GroupFrames")
end

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function Secure(key, fn)
	if InCombatLockdown() then
		Soul:RunAfterCombat(key, fn)
	else
		fn()
	end
end

------------------------------------------------------------------------------
-- Pixel grid
------------------------------------------------------------------------------

-- One physical pixel in UIParent units.
local function PX()
	local mult = Soul.Pixel and Soul.Pixel.mult
	if type(mult) ~= "number" or mult <= 0 then return 1 end
	return mult
end

-- Rounds a UIParent-unit length to a whole number of physical pixels.
local function Snap(value)
	if not Soul.Pixel then return value or 0 end
	return Soul.Pixel:Scale(value or 0)
end

local function Clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

-- Button size and gap, snapped so every border and gap lands on a pixel.
local function Metrics(cfg)
	local px = PX()
	local w = Snap(cfg.width or 80)
	local h = Snap(cfg.height or 36)
	if w < px * 8 then w = px * 8 end
	if h < px * 8 then h = px * 8 end
	local gap = Snap(cfg.spacing or 1)
	if gap < 0 then gap = 0 end
	return w, h, gap
end

------------------------------------------------------------------------------
-- Health text curve: alpha 1 while hurt, 0 at full health. Built once.
------------------------------------------------------------------------------

local FULL_FADE
do
	if C_CurveUtil and C_CurveUtil.CreateCurve then
		local ok, curve = pcall(C_CurveUtil.CreateCurve)
		if ok and curve then
			if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
				pcall(curve.SetType, curve, Enum.LuaCurveType.Linear)
			end
			local added = pcall(curve.AddPoint, curve, 0, 1)
			added = added and pcall(curve.AddPoint, curve, 0.995, 1)
			added = added and pcall(curve.AddPoint, curve, 1, 0)
			if added then FULL_FADE = curve end
		end
	end
end

------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------

local function Hidden()
	if hiddenParent then return hiddenParent end
	hiddenParent = CreateFrame("Frame", "SoulUI_HiddenGroup")
	hiddenParent:Hide()
	hiddenParent:SetSize(1, 1)
	return hiddenParent
end

local function HeaderButtons(header, fn)
	local kids = { header:GetChildren() }
	for i = 1, #kids do
		local child = kids[i]
		if child.IsObjectType and child:IsObjectType("Button") then
			fn(child)
		end
	end
end

local function Unlink(button)
	local unit = buttonUnit[button]
	local list = unit and unitToButton[unit]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == button then
			table.remove(list, i)
		end
	end
	buttonUnit[button] = nil
end

local function Link(button, unit)
	Unlink(button)
	if type(unit) ~= "string" then return end
	buttonUnit[button] = unit
	local list = unitToButton[unit]
	if not list then
		list = {}
		unitToButton[unit] = list
	end
	list[#list + 1] = button
end

-- Four 1px edge textures on the outside of `frame`.
local function MakeEdges(frame, sublevel)
	local edges = {}
	for i = 1, 4 do
		local t = frame:CreateTexture(nil, "OVERLAY", nil, sublevel)
		t:SetColorTexture(1, 1, 1, 1)
		edges[i] = t
	end
	return edges
end

local function SizeEdges(edges, frame, px)
	local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", frame, "TOPLEFT")
	top:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
	top:SetHeight(px)
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
	bottom:SetHeight(px)
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
	left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
	left:SetWidth(px)
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
	right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
	right:SetWidth(px)
end

local function ColorEdges(edges, r, g, b, a)
	for i = 1, 4 do
		edges[i]:SetVertexColor(r, g, b, a or 1)
	end
end

-- Class color for a group member. The fourth return is true when the color
-- came from a secret class token (only pass those values to widget APIs).
local function ClassColor(unit)
	local _, class = UnitClass(unit)
	if IsSecret(class) then
		if C_ClassColor and C_ClassColor.GetClassColor then
			local color = C_ClassColor.GetClassColor(class)
			if color then return color.r, color.g, color.b, true end
		end
		return nil
	end
	if type(class) ~= "string" then return nil end
	local color = RAID_CLASS_COLORS[class]
	if color then return color.r, color.g, color.b, false end
	return nil
end

------------------------------------------------------------------------------
-- Auras: dispel icons and the cleanse outline
------------------------------------------------------------------------------

local function StyleAuraButton(button)
	button:SetSize(14, 14)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	if button.SetIcon then button:SetIcon(icon) end
	local edge = button:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0, 0, 0, 1)
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
	if button.SetDurationCooldown then button:SetDurationCooldown(cooldown) end
	local count = button:CreateFontString(nil, "OVERLAY")
	Soul:ApplyFont(count, 10, "OUTLINE")
	count:SetPoint("BOTTOMRIGHT", 1, -1)
	if button.SetApplicationCount then button:SetApplicationCount(count) end
end

local function FindAuraContainer(button)
	local kids = { button:GetChildren() }
	for i = 1, #kids do
		local child = kids[i]
		if child.GetObjectType and child:GetObjectType() == "AuraContainer" then
			return child
		end
	end
	return nil
end

-- Out of combat only (called from LayoutChrome / ConfigureAuras).
local function PlaceAuras(button, cfg)
	local container = button._soulAuras
	if not container then return end
	if not cfg.showAuras then
		container:Hide()
		return
	end
	local w = Metrics(cfg)
	local px = PX()
	container:ClearAllPoints()
	if cfg.auraPosition == "above" then
		container:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, px)
	else
		-- Inside the frame, bottom-left corner, above the health bar.
		container:SetPoint("BOTTOMLEFT", button.Health, "BOTTOMLEFT", px * 3, px * 3)
		container:SetFrameLevel(button:GetFrameLevel() + 7)
	end
	container:SetSize(w, 16)
	container:Show()
end

local function ConfigureAuras(button, cfg)
	if not button._soulDispelGlow and not InCombatLockdown() then
		-- Outline the inside of the frame while the unit has a debuff you can
		-- cleanse. 2px, tinted by debuff type, drawn inside the black border so
		-- it never fights the target / mouseover edge.
		button._soulDispelGlow = Soul.Auras.Highlight(button.GlowAnchor, button:GetAttribute("unit"),
			"HARMFUL|RAID_PLAYER_DISPELLABLE", { 0.8, 0.35, 1 }, PX() * 2)
	end
	Soul.Auras.SetShown(button._soulDispelGlow, cfg.dispelGlow ~= false)
	local container = button._soulAuras or FindAuraContainer(button)
	if not container and not InCombatLockdown() then
		if C_AddOns and C_AddOns.LoadAddOn then
			pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
		end
		local ok, created = pcall(CreateFrame, "AuraContainer", nil, button, "CustomAuraContainerTemplate")
		if ok then container = created end
	end
	if not container then return end
	button._soulAuras = container
	if container.SetMouseMotionEnabled then
		pcall(container.SetMouseMotionEnabled, container, false)
	end
	if container.SetMouseClickEnabled then
		pcall(container.SetMouseClickEnabled, container, false)
	end
	local unit = button:GetAttribute("unit")
	if container.SetUnit then
		pcall(container.SetUnit, container, unit or "none")
	end
	if container.AddAuraGroup and not button._soulAuraGroup then
		local ok = pcall(container.AddAuraGroup, container, "dispels", "HARMFUL|RAID_PLAYER_DISPELLABLE", {
			maxFrameCount = 3,
			initializeFrame = StyleAuraButton,
		})
		if ok then button._soulAuraGroup = true end
	end
	PlaceAuras(button, cfg)
end

------------------------------------------------------------------------------
-- Layout (out of combat only)
------------------------------------------------------------------------------

-- "inline": name left, health text right (wide party bars).
-- "stacked": name centered, health text under it (square-ish raid cells).
local function TextLayout(cfg, w, h)
	local mode = cfg.textLayout or "auto"
	if mode == "inline" or mode == "stacked" then return mode end
	if w >= h * 2.5 then return "inline" end
	return "stacked"
end

-- Sizes are in UIParent units, like the frame size.
local function FontSizes(cfg, layout, w, h)
	local size = cfg.font or 12
	if cfg.autoFont ~= false then
		local cap
		if layout == "inline" then
			cap = floor(h * 0.42)
		else
			cap = math.min(floor(h * 0.30), floor(w * 0.13))
		end
		if cap < size then size = cap end
	end
	size = Clamp(size, 8, 40)
	local sub = cfg.healthFont
	if type(sub) ~= "number" or sub <= 0 then
		sub = layout == "inline" and size - 1 or size - 2
	end
	return size, Clamp(sub, 8, 40)
end

local function LayoutChrome(button, cfg)
	local px = PX()
	local w, h = Metrics(cfg)
	local health = button.Health
	local power = button.Power
	local texture = Soul:StatusbarTexture()

	-- Backdrop: the button itself is the black frame; everything sits 1px in.
	button.Backdrop:SetColorTexture(0, 0, 0, 1)

	health:ClearAllPoints()
	health:SetPoint("TOPLEFT", button, "TOPLEFT", px, -px)
	if cfg.showPower then
		local thickness = Snap(cfg.powerHeight or 4)
		if thickness < px then thickness = px end
		-- 1px black separator between health and power.
		health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -px, thickness + px * 2)
		power:ClearAllPoints()
		power:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", px, px)
		power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -px, px)
		power:SetHeight(thickness)
		power:SetStatusBarTexture(texture)
		power:Show()
	else
		health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -px, px)
		power:Hide()
	end
	health:SetStatusBarTexture(texture)
	local fill = health:GetStatusBarTexture()
	if fill and fill.SetSnapToPixelGrid then
		fill:SetSnapToPixelGrid(false)
		fill:SetTexelSnappingBias(0)
	end

	-- Absorb overlay, clipped to the missing part of the bar.
	local absorb = button.Absorb
	absorb:SetStatusBarTexture(texture)
	absorb:SetWidth(math.max(px, w - px * 2))
	button.AbsorbClip:SetShown(cfg.showAbsorbs ~= false)

	button.Shade:SetShown(cfg.gradient ~= false)

	-- Inner frame for the cleanse outline (inside the black border).
	local glow = button.GlowAnchor
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", button, "TOPLEFT", px, -px)
	glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -px, px)
	glow:SetFrameLevel(button:GetFrameLevel() + 4)

	local overlay = button.Overlay
	overlay:SetFrameLevel(button:GetFrameLevel() + 8)
	button.HoverFrame:SetFrameLevel(overlay:GetFrameLevel() + 1)
	button.TargetFrame:SetFrameLevel(overlay:GetFrameLevel() + 2)
	SizeEdges(button.TargetEdges, overlay, px)
	SizeEdges(button.HoverEdges, overlay, px)
	ColorEdges(button.HoverEdges, 1, 1, 1, 0.85)
	local r, g, b = Soul:Accent()
	ColorEdges(button.TargetEdges, r, g, b, 1)

	-- Text and icons.
	local layout = TextLayout(cfg, w, h)
	local size, sub = FontSizes(cfg, layout, w, h)
	Soul:ApplyFont(button.Name, size, "OUTLINE")
	Soul:ApplyFont(button.HealthText, sub, "OUTLINE")
	local pad = Snap(4)
	local name, text, role, raid, ready = button.Name, button.HealthText, button.Role, button.RaidIcon, button.Ready
	name:ClearAllPoints()
	text:ClearAllPoints()
	role:ClearAllPoints()
	raid:ClearAllPoints()
	ready:ClearAllPoints()
	local showRole = cfg.showRole ~= false
	if layout == "inline" then
		local roleSize = Snap(Clamp(floor(h * 0.34), 10, 16))
		role:SetSize(roleSize, roleSize)
		role:SetPoint("LEFT", health, "LEFT", pad, 0)
		text:SetJustifyH("RIGHT")
		text:SetPoint("RIGHT", health, "RIGHT", -pad, 0)
		name:SetJustifyH("LEFT")
		if showRole then
			name:SetPoint("LEFT", role, "RIGHT", Snap(3), 0)
		else
			name:SetPoint("LEFT", health, "LEFT", pad, 0)
		end
		name:SetPoint("RIGHT", text, "LEFT", -pad, 0)
		raid:SetSize(roleSize, roleSize)
		raid:SetPoint("TOP", health, "TOP", 0, -Snap(2))
	else
		local roleSize = Snap(Clamp(floor(h * 0.22), 9, 14))
		role:SetSize(roleSize, roleSize)
		role:SetPoint("TOPLEFT", health, "TOPLEFT", Snap(2), -Snap(2))
		local textOn = (cfg.healthText or "percent") ~= "none"
		local lift = textOn and Snap(floor(size * 0.5)) or 0
		name:SetJustifyH("CENTER")
		name:SetPoint("LEFT", health, "LEFT", pad, lift)
		name:SetPoint("RIGHT", health, "RIGHT", -pad, lift)
		text:SetJustifyH("CENTER")
		text:SetPoint("TOP", name, "BOTTOM", 0, -Snap(1))
		raid:SetSize(roleSize, roleSize)
		raid:SetPoint("TOPRIGHT", health, "TOPRIGHT", -Snap(2), -Snap(2))
	end
	role:SetShown(showRole)
	local readySize = Snap(Clamp(floor(h * 0.5), 14, 26))
	ready:SetSize(readySize, readySize)
	ready:SetPoint("CENTER", health, "CENTER", 0, 0)

	if button._soulDispelGlow then
		Soul.Auras.Refit(button._soulDispelGlow, glow)
		Soul.Auras.SetShown(button._soulDispelGlow, cfg.dispelGlow ~= false)
	end
	PlaceAuras(button, cfg)
end

------------------------------------------------------------------------------
-- Updates (combat safe: no protected calls, no tables)
------------------------------------------------------------------------------

local function UpdateRole(button, unit, cfg)
	local icon = button.Role
	if not icon then return end
	if cfg.showRole == false then
		icon:SetAlpha(0)
		return
	end
	icon:SetAlpha(1)
	if not roleAPI or not UnitFrameUtil or not UnitFrameUtil.UpdateUnitFrameRoleIcon then
		return
	end
	local ok = pcall(UnitFrameUtil.UpdateUnitFrameRoleIcon, icon, unit)
	if not ok then
		roleAPI = false
		icon:SetAlpha(0)
	end
end

local function NameColor(button, unit, cfg)
	local name = button.Name
	local dark = cfg.healthColor == "dark" and type(cfg.color) ~= "table"
	if dark or cfg.nameClassColor then
		local r, g, b, secret = ClassColor(unit)
		if r and not secret then
			name:SetTextColor(r, g, b)
			return
		end
	end
	name:SetTextColor(1, 1, 1)
end

local function ColorHealth(button, unit, cfg)
	local health = button.Health
	local bg = health.bg
	if type(cfg.color) == "table" then
		health:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3])
		bg:SetVertexColor(0.06, 0.06, 0.07, 1)
	elseif cfg.healthColor == "dark" then
		-- Dark fill; the missing part shows a dimmed class color.
		health:SetStatusBarColor(0.15, 0.15, 0.17)
		local r, g, b = ClassColor(unit)
		if r then
			bg:SetVertexColor(r, g, b, 0.55)
		else
			bg:SetVertexColor(0.55, 0.12, 0.12, 0.6)
		end
	else
		Soul:ColorUnitHealth(health, unit)
		bg:SetVertexColor(0.06, 0.06, 0.07, 1)
	end
	NameColor(button, unit, cfg)
end

-- Dead, ghost, offline: empty or gray bar, an uppercase label, gray name.
local function ShowState(button, state, fillValue)
	local health = button.Health
	health:SetMinMaxValues(0, 100)
	health:SetValue(fillValue)
	if state == STATE_OFFLINE then
		health:SetStatusBarColor(0.22, 0.22, 0.24)
		health.bg:SetVertexColor(0.1, 0.1, 0.11, 1)
	else
		health:SetStatusBarColor(0.2, 0.2, 0.22)
		health.bg:SetVertexColor(0.2, 0.05, 0.05, 1)
	end
	local text = button.HealthText
	text:SetAlpha(1)
	text:SetText(state[1])
	text:SetTextColor(state[2], state[3], state[4])
	button.Name:SetTextColor(0.6, 0.6, 0.62)
	button.Absorb:SetValue(0)
	button._soulState = state
end

local function UpdateHealth(button, unit, cfg)
	local health = button.Health
	local text = button.HealthText
	local connected = UnitIsConnected(unit)
	if not IsSecret(connected) and not connected then
		ShowState(button, STATE_OFFLINE, 100)
		return
	end
	local dead = UnitIsDeadOrGhost(unit)
	if not IsSecret(dead) and dead then
		local ghost = UnitIsGhost and UnitIsGhost(unit)
		if not IsSecret(ghost) and ghost then
			ShowState(button, STATE_GHOST, 0)
		else
			ShowState(button, STATE_DEAD, 0)
		end
		return
	end
	if button._soulState then
		button._soulState = nil
		ColorHealth(button, unit, cfg)
	end
	local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
	local curve = CurveConstants and CurveConstants.ScaleTo100
	local mode = cfg.healthText or "percent"
	text:SetTextColor(0.92, 0.92, 0.92)
	if curve then
		local pct = UnitHealthPercent(unit, true, curve)
		health:SetMinMaxValues(0, 100)
		if interp then
			health:SetValue(pct, interp)
		else
			health:SetValue(pct)
		end
		if mode == "none" then
			text:SetText("")
		elseif mode == "deficit" and UnitHealthMissing then
			text:SetFormattedText("-%s", Soul:Abbrev(UnitHealthMissing(unit)))
		else
			text:SetFormattedText("%.0f%%", pct)
		end
	else
		health:SetMinMaxValues(0, UnitHealthMax(unit))
		if interp then
			health:SetValue(UnitHealth(unit), interp)
		else
			health:SetValue(UnitHealth(unit))
		end
		if mode == "none" then
			text:SetText("")
		else
			text:SetFormattedText("%s", Soul:Abbrev(UnitHealth(unit)))
		end
	end
	-- Hide the number at full health (deficit text is always hidden then).
	if FULL_FADE and (mode == "deficit" or cfg.hideFullHealthText ~= false) then
		text:SetAlpha(UnitHealthPercent(unit, true, FULL_FADE))
	else
		text:SetAlpha(1)
	end
	local afk = UnitIsAFK and UnitIsAFK(unit)
	if not IsSecret(afk) and afk and mode ~= "none" then
		text:SetText("AFK")
		text:SetTextColor(0.95, 0.75, 0.3)
		text:SetAlpha(1)
	end
	if cfg.showAbsorbs ~= false and UnitGetTotalAbsorbs then
		local absorb = button.Absorb
		absorb:SetMinMaxValues(0, UnitHealthMax(unit))
		absorb:SetValue(UnitGetTotalAbsorbs(unit))
	end
end

local function UpdatePower(button, unit, cfg)
	if not cfg.showPower or not button.Power:IsShown() then return end
	local curve = CurveConstants and CurveConstants.ScaleTo100
	local kind = UnitPowerType(unit)
	button.Power:SetStatusBarColor(Soul:PowerColor(kind))
	if not IsSecret(kind) and type(kind) == "number" and curve then
		button.Power:SetMinMaxValues(0, 100)
		button.Power:SetValue(UnitPowerPercent(unit, kind, true, curve))
	elseif not IsSecret(kind) and type(kind) == "number" then
		button.Power:SetMinMaxValues(0, UnitPowerMax(unit, kind))
		button.Power:SetValue(UnitPower(unit, kind))
	end
end

local function UpdateTarget(button, unit, cfg)
	if cfg.targetHighlight == false then
		button.TargetFrame:SetAlpha(0)
		return
	end
	Soul.Secret.AlphaFromBool(button.TargetFrame, UnitIsUnit(unit, "target"), 1, 0)
end

local function UpdateRange(button, unit, cfg)
	local faded = cfg.rangeAlpha
	if type(faded) ~= "number" then faded = 0.4 end
	local isPlayer = UnitIsUnit(unit, "player")
	if not IsSecret(isPlayer) and isPlayer then
		button:SetAlpha(1)
		return
	end
	local inRange, checked = UnitInRange(unit)
	if IsSecret(checked) or checked then
		if not Soul.Secret.Present(inRange) then
			button:SetAlpha(1)
		else
			Soul.Secret.AlphaFromBool(button, inRange, 1, faded)
		end
	else
		button:SetAlpha(1)
	end
end

local function UpdateReady(button, unit)
	local icon = button.Ready
	if not readyActive or not GetReadyCheckStatus then
		icon:SetAlpha(0)
		button._soulReadyStatus = nil
		return
	end
	-- After the check ends the icons stay frozen for a few seconds.
	if readyFinished then return end
	local status = GetReadyCheckStatus(unit)
	local path = not IsSecret(status) and type(status) == "string" and READY_TEXTURE[status]
	if not path then
		icon:SetAlpha(0)
		button._soulReadyStatus = nil
		return
	end
	button._soulReadyStatus = status
	icon:SetTexture(path)
	icon:SetAlpha(1)
end

-- Anyone still "waiting" when the check ends did not answer.
local function FinishReady(button)
	if button._soulReadyStatus == "waiting" then
		button.Ready:SetTexture(READY_TEXTURE.notready)
	end
end

local function UpdateRaidIcon(button, unit)
	local index = GetRaidTargetIndex(unit)
	if not IsSecret(index) and type(index) == "number" and index > 0 then
		SetRaidTargetIconTexture(button.RaidIcon, index)
		button.RaidIcon:SetAlpha(1)
	else
		button.RaidIcon:SetAlpha(0)
	end
end

local function UpdateButton(button, cfg)
	local unit = button:GetAttribute("unit")
	if type(unit) ~= "string" or not UnitExists(unit) then return end
	cfg = cfg or button._soulCfg
	if not cfg then return end
	button._soulState = nil
	ColorHealth(button, unit, cfg)
	UpdateHealth(button, unit, cfg)
	local name = UnitName(unit)
	button.Name:SetText(name or "")
	UpdatePower(button, unit, cfg)
	UpdateRaidIcon(button, unit)
	UpdateTarget(button, unit, cfg)
	UpdateRange(button, unit, cfg)
	UpdateRole(button, unit, cfg)
	UpdateReady(button, unit)
end

------------------------------------------------------------------------------
-- Building a button (out of combat only)
------------------------------------------------------------------------------

local function OnEnter(self)
	local cfg = self._soulCfg
	if cfg and cfg.hoverHighlight == false then return end
	self.HoverFrame:SetAlpha(1)
end

local function OnLeave(self)
	self.HoverFrame:SetAlpha(0)
end

local function StyleButton(button, cfg)
	if button._soulReady then
		button._soulCfg = cfg
		LayoutChrome(button, cfg)
		return
	end
	button._soulCfg = cfg

	local backdrop = button:CreateTexture(nil, "BACKGROUND", nil, -8)
	backdrop:SetAllPoints()
	backdrop:SetColorTexture(0, 0, 0, 1)
	button.Backdrop = backdrop

	local health = Soul:StatusBar(button)
	health.bg:SetColorTexture(1, 1, 1, 1)
	health.bg:SetVertexColor(0.06, 0.06, 0.07, 1)
	button.Health = health

	-- Absorbs: a bar that starts where the health fill ends, clipped so it
	-- never draws past the end of the bar.
	local fill = health:GetStatusBarTexture()
	local clip = CreateFrame("Frame", nil, health)
	if clip.SetClipsChildren then clip:SetClipsChildren(true) end
	clip:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	clip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
	local absorb = CreateFrame("StatusBar", nil, clip)
	absorb:SetStatusBarTexture(Soul:StatusbarTexture())
	absorb:SetStatusBarColor(0.72, 0.9, 1, 0.5)
	absorb:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	absorb:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
	absorb:SetWidth(100)
	absorb:SetMinMaxValues(0, 1)
	absorb:SetValue(0)
	button.Absorb = absorb
	button.AbsorbClip = clip

	-- Soft top-light / bottom-shade for depth.
	local shade = health:CreateTexture(nil, "ARTWORK", nil, 7)
	shade:SetAllPoints()
	shade:SetTexture("Interface\\Buttons\\WHITE8X8")
	if shade.SetGradient and CreateColor then
		pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.22), CreateColor(1, 1, 1, 0.07))
	else
		shade:SetVertexColor(0, 0, 0, 0)
	end
	button.Shade = shade

	local power = Soul:StatusBar(button)
	power.bg:SetColorTexture(0.06, 0.06, 0.07, 1)
	button.Power = power

	local glow = CreateFrame("Frame", nil, button)
	button.GlowAnchor = glow

	-- Overlay: highlight edges, icons and text above the bars and the outline.
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints(button)
	button.Overlay = overlay

	local hover = CreateFrame("Frame", nil, overlay)
	hover:SetAllPoints(overlay)
	hover:SetAlpha(0)
	button.HoverFrame = hover
	button.HoverEdges = MakeEdges(hover, 5)

	local target = CreateFrame("Frame", nil, overlay)
	target:SetAllPoints(overlay)
	target:SetAlpha(0)
	button.TargetFrame = target
	button.TargetEdges = MakeEdges(target, 6)

	local name = overlay:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	if name.SetMaxLines then name:SetMaxLines(1) end
	name:SetTextColor(1, 1, 1)
	button.Name = name

	local pct = overlay:CreateFontString(nil, "OVERLAY")
	pct:SetJustifyH("RIGHT")
	pct:SetWordWrap(false)
	pct:SetTextColor(0.92, 0.92, 0.92)
	button.HealthText = pct

	local raid = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
	raid:SetSize(14, 14)
	raid:SetAlpha(0)
	button.RaidIcon = raid

	local role = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
	role:SetSize(12, 12)
	button.Role = role

	local ready = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
	ready:SetSize(20, 20)
	ready:SetAlpha(0)
	button.Ready = ready

	button:RegisterForClicks("AnyUp")
	button:HookScript("OnAttributeChanged", function(self, attribute, value)
		if attribute ~= "unit" then return end
		Link(self, value)
		local container = self._soulAuras
		if container and container.SetUnit then
			pcall(container.SetUnit, container, value or "none")
		end
		Soul.Auras.SetUnit(self._soulDispelGlow, value)
		if self:IsShown() then UpdateButton(self) end
	end)
	button:HookScript("OnShow", function(self)
		UpdateButton(self)
	end)
	button:HookScript("OnEnter", OnEnter)
	button:HookScript("OnLeave", OnLeave)
	button._soulReady = true
	styled[#styled + 1] = button
	LayoutChrome(button, cfg)
	ConfigureAuras(button, cfg)
	Link(button, button:GetAttribute("unit"))
end

------------------------------------------------------------------------------
-- Headers
------------------------------------------------------------------------------

local function GridSize(kind, cfg)
	local w, h, gap = Metrics(cfg)
	if kind == "party" then
		if cfg.orientation == "horizontal" then
			return w * 5 + gap * 4, h
		end
		return w, h * 5 + gap * 4
	end
	return w * 5 + gap * 4, h * 8 + gap * 7
end

local function PartyRule(cfg)
	if not cfg.enabled then return "hide" end
	if cfg.showSolo then
		return "[petbattle] hide; [group:raid] hide; show"
	end
	return "[petbattle] hide; [group:party,nogroup:raid] show; hide"
end

local function RaidRule(cfg)
	if not cfg.enabled then return "hide" end
	return "[petbattle] hide; [group:raid] show; hide"
end

local function ConfigureHeader(header, kind, cfg)
	local w, h, gap = Metrics(cfg)
	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("templateType", "Button")
	header:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
	header:SetAttribute("initialConfigFunction", CLICK)
	header:SetAttribute("soul-width", w)
	header:SetAttribute("soul-height", h)
	header:SetAttribute("showPlayer", cfg.showPlayer and true or false)
	header:SetAttribute("showSolo", false)
	header:SetAttribute("sortMethod", "INDEX")
	header:SetAttribute("sortDir", "ASC")
	if kind == "party" then
		header:SetAttribute("showParty", true)
		header:SetAttribute("showRaid", false)
		-- Vertical (default): units stack downward from the top. Horizontal:
		-- a strip growing right.
		if cfg.orientation == "horizontal" then
			header:SetAttribute("point", "LEFT")
			header:SetAttribute("xOffset", gap)
			header:SetAttribute("yOffset", 0)
		else
			header:SetAttribute("point", "TOP")
			header:SetAttribute("xOffset", 0)
			header:SetAttribute("yOffset", -gap)
		end
		header:SetAttribute("maxColumns", 1)
		header:SetAttribute("unitsPerColumn", 5)
	else
		header:SetAttribute("showParty", false)
		header:SetAttribute("showRaid", true)
		header:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
		header:SetAttribute("point", "LEFT")
		header:SetAttribute("xOffset", gap)
		header:SetAttribute("yOffset", 0)
		header:SetAttribute("columnSpacing", gap)
		header:SetAttribute("columnAnchorPoint", "TOP")
		header:SetAttribute("unitsPerColumn", 5)
		header:SetAttribute("maxColumns", 8)
	end
end

local function Drive(header, rule)
	if InCombatLockdown() then
		Soul:RunAfterCombat("group:drive:" .. (header:GetName() or "header"), function()
			Drive(header, rule)
		end)
		return
	end
	RegisterStateDriver(header, "visibility", rule)
end

local function Prespawn(header, count)
	header:SetAttribute("startingIndex", -(count - 1))
	header:Show()
	header:SetAttribute("startingIndex", 1)
end

local function StyleHeader(header, cfg)
	local w, h = Metrics(cfg)
	HeaderButtons(header, function(button)
		button:SetSize(w, h)
		StyleButton(button, cfg)
		UpdateButton(button, cfg)
	end)
end

local BLIZZARD = {
	"CompactRaidFrameManager",
	"CompactRaidFrameContainer",
	"CompactPartyFrame",
	"PartyFrame",
}

local parked = {}

local function SuppressBlizzard()
	if InCombatLockdown() then
		Soul:RunAfterCombat("group:suppress", SuppressBlizzard)
		return
	end
	local parent = Hidden()
	for i = 1, #BLIZZARD do
		local frame = _G[BLIZZARD[i]]
		if frame then
			if not originalParent[frame] then
				originalParent[frame] = frame:GetParent()
			end
			frame:SetParent(parent)
			if not parked[frame] then
				parked[frame] = true
				frame:HookScript("OnShow", function(self)
					if not DB().hideBlizzard then return end
					if InCombatLockdown() then
						Soul:RunAfterCombat("group:suppress", SuppressBlizzard)
					else
						self:SetParent(parent)
					end
				end)
			end
		end
	end
end

local function RestoreBlizzard()
	if InCombatLockdown() then
		Soul:RunAfterCombat("group:restore", RestoreBlizzard)
		return
	end
	for frame, parent in pairs(originalParent) do
		frame:SetParent(parent or UIParent)
	end
end

local function LayoutKind(kind)
	local pack = GF.headers[kind]
	if not pack then return end
	local cfg = DB()[kind]
	local width, height = GridSize(kind, cfg)
	local w, h = Metrics(cfg)
	pack.holder:SetSize(width, height)
	pack.header:ClearAllPoints()
	pack.header:SetPoint("TOPLEFT", pack.holder, "TOPLEFT", 0, 0)
	pack.header:SetSize(w, h)
	ConfigureHeader(pack.header, kind, cfg)
	StyleHeader(pack.header, cfg)
	local rule = kind == "party" and PartyRule(cfg) or RaidRule(cfg)
	Drive(pack.header, rule)
	Soul:Place(pack.holder, "GroupFrames:" .. kind, {
		point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y,
	})
end

function GF:Apply(scope)
	local function run()
		LayoutKind("party")
		LayoutKind("raid")
		if scope == "colors" then
			for i = 1, #styled do
				if styled[i]:IsShown() then UpdateButton(styled[i]) end
			end
		end
		if DB().hideBlizzard then
			SuppressBlizzard()
		else
			RestoreBlizzard()
		end
	end
	Secure("group:apply", run)
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local function RefreshShown()
	for i = 1, #styled do
		if styled[i]:IsShown() then UpdateButton(styled[i]) end
	end
end

local function ForShown(fn)
	for i = 1, #styled do
		local button = styled[i]
		local unit = buttonUnit[button]
		local cfg = button._soulCfg
		if button:IsShown() and unit and cfg and UnitExists(unit) then
			fn(button, unit, cfg)
		end
	end
end

local function ButtonsFor(unit, fn)
	local list = unitToButton[unit]
	if not list then return end
	for i = 1, #list do
		local button = list[i]
		local cfg = button._soulCfg
		if button:IsShown() and cfg and UnitExists(unit) then
			fn(button, unit, cfg)
		end
	end
end

local function HealthOnly(button, unit, cfg)
	UpdateHealth(button, unit, cfg)
end

local function PowerOnly(button, unit, cfg)
	UpdatePower(button, unit, cfg)
end

local function RangeOnly(button, unit, cfg)
	UpdateRange(button, unit, cfg)
end

local function TargetOnly(button, unit, cfg)
	UpdateTarget(button, unit, cfg)
end

local function RaidIconOnly(button, unit)
	UpdateRaidIcon(button, unit)
end

local function ReadyOnly(button, unit)
	UpdateReady(button, unit)
end

local function Full(button)
	UpdateButton(button)
end

local HEALTH_EVENTS = {
	UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_ABSORB_AMOUNT_CHANGED = true,
}
local POWER_EVENTS = {
	UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true,
}

local function EndReady()
	if readyActive and GetTime() >= readyHideAt - 0.05 then
		readyActive = false
		readyFinished = false
		ForShown(ReadyOnly)
	end
end

local function OnUnit(_, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then
		ForShown(TargetOnly)
		return
	end
	if event == "RAID_TARGET_UPDATE" then
		ForShown(RaidIconOnly)
		return
	end
	if event == "READY_CHECK" then
		readyActive = true
		readyFinished = false
		readyHideAt = math.huge
		ForShown(ReadyOnly)
		return
	end
	if event == "READY_CHECK_CONFIRM" then
		if type(unit) == "string" then
			ButtonsFor(unit, ReadyOnly)
		else
			ForShown(ReadyOnly)
		end
		return
	end
	if event == "READY_CHECK_FINISHED" then
		if not readyActive then return end
		readyFinished = true
		ForShown(FinishReady)
		readyHideAt = GetTime() + 6
		C_Timer.After(6, EndReady)
		return
	end
	if event == "GROUP_ROSTER_UPDATE" then
		Secure("group:roster", function()
			if GF.headers and GF.headers.party then
				StyleHeader(GF.headers.party.header, DB().party)
				StyleHeader(GF.headers.raid.header, DB().raid)
			end
			RefreshShown()
		end)
		return
	end
	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ROLES_ASSIGNED" then
		RefreshShown()
		return
	end
	if type(unit) ~= "string" then return end
	if HEALTH_EVENTS[event] then
		ButtonsFor(unit, HealthOnly)
	elseif POWER_EVENTS[event] then
		ButtonsFor(unit, PowerOnly)
	elseif event == "UNIT_IN_RANGE_UPDATE" then
		ButtonsFor(unit, RangeOnly)
	else
		ButtonsFor(unit, Full)
	end
end

function GF:OnInitialize()
	Soul:RegisterModuleDB("GroupFrames", Soul.Defaults.GroupFrames)
end

local function MakeHeader(kind)
	local holder = CreateFrame("Frame", "SoulUI" .. kind .. "Holder", UIParent)
	holder:EnableMouse(false)
	local ok, header = pcall(CreateFrame, "Frame", "SoulUI" .. kind .. "Header", holder, "SecureGroupHeaderTemplate")
	if not ok then
		Soul:Print("Group frames need SecureGroupHeaderTemplate:", header)
		return nil
	end
	return { holder = holder, header = header }
end

function GF:OnEnable()
	self.headers = {}
	local party = MakeHeader("Party")
	local raid = MakeHeader("Raid")
	if not party or not raid then return end
	self.headers.party = party
	self.headers.raid = raid

	Secure("group:spawn", function()
		local db = DB()
		ConfigureHeader(party.header, "party", db.party)
		ConfigureHeader(raid.header, "raid", db.raid)
		Prespawn(party.header, 5)
		Prespawn(raid.header, 40)
		GF:Apply("all")
	end)

	local watch = {
		"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_CONNECTION",
		"UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
		"UNIT_IN_RANGE_UPDATE", "UNIT_FLAGS", "UNIT_ABSORB_AMOUNT_CHANGED",
		"PLAYER_FLAGS_CHANGED",
	}
	local tokens = { "player" }
	for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
	for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end
	for i = 1, #watch do
		for n = 1, #tokens do
			pcall(self.RegisterUnitEvent, self, watch[i], OnUnit, tokens[n])
		end
	end
	self:RegisterEvent("PLAYER_TARGET_CHANGED", OnUnit)
	self:RegisterEvent("RAID_TARGET_UPDATE", OnUnit)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", OnUnit)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnUnit)
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED", OnUnit)
	self:RegisterEvent("READY_CHECK", OnUnit)
	self:RegisterEvent("READY_CHECK_CONFIRM", OnUnit)
	self:RegisterEvent("READY_CHECK_FINISHED", OnUnit)

	local function GroupEdit(kind, across, down)
		return {
			onResize = function(width, height)
				local cfg = DB()[kind]
				local across, down = across, down
				-- A vertical party is one column of five.
				if kind == "party" and (cfg.orientation or "vertical") == "vertical" then
					across, down = 1, 5
				end
				local gap = cfg.spacing or 2
				local currentW = cfg.width * across + gap * math.max(0, across - 1)
				local currentH = cfg.height * down + gap * math.max(0, down - 1)
				if math.abs(width - currentW) < 3 and math.abs(height - currentH) < 3 then
					if math.abs(width - currentW) >= math.abs(height - currentH) then
						if width > currentW then cfg.width = cfg.width + 1
						elseif width < currentW then cfg.width = math.max(40, cfg.width - 1) end
					elseif height > currentH then
						cfg.height = cfg.height + 1
					elseif height < currentH then
						cfg.height = math.max(16, cfg.height - 1)
					end
				else
					local buttonW = (width - gap * math.max(0, across - 1)) / across
					local buttonH = (height - gap * math.max(0, down - 1)) / down
					if buttonW < 40 then buttonW = 40 end
					if buttonH < 16 then buttonH = 16 end
					cfg.width = math.floor(buttonW + 0.5)
					cfg.height = math.floor(buttonH + 0.5)
				end
				GF:Apply("all")
			end,
			getColor = function()
				local cfg = DB()[kind]
				if type(cfg.color) == "table" then return cfg.color[1], cfg.color[2], cfg.color[3] end
				return 0.2, 0.8, 0.3
			end,
			setColor = function(r, g, b)
				DB()[kind].color = { r, g, b }
				GF:Apply("all")
			end,
		}
	end
	local partyEdit = GroupEdit("party", 5, 1)
	local raidEdit = GroupEdit("raid", 5, 8)
	Soul:RegisterMover({
		key = "GroupFrames:party",
		label = "Party",
		getFrame = function() return party.holder end,
		getEnabled = function() return DB().party.enabled end,
		setEnabled = function(on)
			DB().party.enabled = on and true or false
			GF:Apply("all")
		end,
		fallback = function()
			local cfg = DB().party
			return { point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y }
		end,
		onResize = partyEdit.onResize,
		getColor = partyEdit.getColor,
		setColor = partyEdit.setColor,
	})
	Soul:RegisterMover({
		key = "GroupFrames:raid",
		label = "Raid",
		getFrame = function() return raid.holder end,
		getEnabled = function() return DB().raid.enabled end,
		setEnabled = function(on)
			DB().raid.enabled = on and true or false
			GF:Apply("all")
		end,
		fallback = function()
			local cfg = DB().raid
			return { point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y }
		end,
		onResize = raidEdit.onResize,
		getColor = raidEdit.getColor,
		setColor = raidEdit.setColor,
	})

	Soul:On("ProfileChanged", function() GF:Apply("all") end)
	Soul:On("ThemeChanged", function() GF:Apply("colors") end)
end
