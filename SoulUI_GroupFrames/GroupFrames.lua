if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI
local GF = Soul:NewModule("GroupFrames", "SoulUI_GroupFrames")

local styled = {}
local unitToButton = {}
local buttonUnit = {}
local originalParent = {}
local hiddenParent
local roleAPI = true

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

local function Secure(key, fn)
	if InCombatLockdown() then
		Soul:RunAfterCombat(key, fn)
	else
		fn()
	end
end

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

local function ButtonFor(unit)
	local list = unitToButton[unit]
	if not list then return nil end
	for i = 1, #list do
		if list[i]:IsShown() then return list[i] end
	end
	return nil
end

local function StyleAuraButton(button)
	button:SetSize(14, 14)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	if button.SetIcon then button:SetIcon(icon) end
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
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

local function ConfigureAuras(button, cfg)
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
	if not button._soulDispelGlow and not InCombatLockdown() then
		-- Outline the whole frame while the unit has a debuff you can cleanse.
		button._soulDispelGlow = Soul.Auras.Highlight(button, button:GetAttribute("unit"), "HARMFUL|RAID_PLAYER_DISPELLABLE", { 0.8, 0.35, 1 }, 2)
	end
	Soul.Auras.SetShown(button._soulDispelGlow, cfg.dispelGlow ~= false)
	if not cfg.showAuras then
		container:Hide()
		return
	end
	container:ClearAllPoints()
	container:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 1)
	container:SetSize(cfg.width or 80, 16)
	if container.SetMouseMotionEnabled then
		pcall(container.SetMouseMotionEnabled, container, false)
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
	container:Show()
end

local function LayoutChrome(button, cfg)
	local health = button.Health
	local power = button.Power
	health:ClearAllPoints()
	health:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
	if cfg.showPower then
		local thickness = cfg.powerHeight or 4
		health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, thickness)
		power:ClearAllPoints()
		power:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
		power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		power:SetHeight(thickness)
		power:Show()
	else
		health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		power:Hide()
	end
	local size = cfg.font or 12
	Soul:ApplyFont(button.Name, size, "OUTLINE")
	Soul:ApplyFont(button.HealthText, size, "OUTLINE")
	if button._soulDispelGlow then
		Soul.Auras.Refit(button._soulDispelGlow, button)
		Soul.Auras.SetShown(button._soulDispelGlow, cfg.dispelGlow ~= false)
	end
	local container = button._soulAuras
	if container then
		if cfg.showAuras then
			container:ClearAllPoints()
			container:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 1)
			container:SetSize(cfg.width or 80, 16)
			container:Show()
		else
			container:Hide()
		end
	end
end

local function UpdateRole(button, unit)
	local icon = button.Role
	if not icon or not roleAPI or not UnitFrameUtil or not UnitFrameUtil.UpdateUnitFrameRoleIcon then
		return
	end
	local ok = pcall(UnitFrameUtil.UpdateUnitFrameRoleIcon, icon, unit)
	if not ok then
		roleAPI = false
		icon:Hide()
	end
end

local function UpdateButton(button, cfg)
	local unit = button:GetAttribute("unit")
	if type(unit) ~= "string" or not UnitExists(unit) then return end
	cfg = cfg or button._soulCfg
	if not cfg then return end
	local health = button.Health
	local dead = UnitIsDeadOrGhost(unit)
	local connected = UnitIsConnected(unit)
	local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
	local curve = CurveConstants and CurveConstants.ScaleTo100
	if not Soul.Secret.IsSecret(dead) and dead then
		health:SetMinMaxValues(0, 100)
		health:SetValue(0)
		health:SetStatusBarColor(0.35, 0.35, 0.35)
		button.HealthText:SetText("Dead")
	elseif not Soul.Secret.IsSecret(connected) and not connected then
		health:SetMinMaxValues(0, 100)
		health:SetValue(100)
		health:SetStatusBarColor(0.4, 0.4, 0.4)
		button.HealthText:SetText("Off")
	else
		if curve then
			health:SetMinMaxValues(0, 100)
			if interp then
				health:SetValue(UnitHealthPercent(unit, true, curve), interp)
			else
				health:SetValue(UnitHealthPercent(unit, true, curve))
			end
			button.HealthText:SetFormattedText("%.0f", UnitHealthPercent(unit, true, curve))
		else
			health:SetMinMaxValues(0, UnitHealthMax(unit))
			if interp then
				health:SetValue(UnitHealth(unit), interp)
			else
				health:SetValue(UnitHealth(unit))
			end
		end
		if type(cfg.color) == "table" then
			health:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3])
		else
			Soul:ColorUnitHealth(health, unit)
		end
		local afk = UnitIsAFK and UnitIsAFK(unit)
		if not Soul.Secret.IsSecret(afk) and afk then
			button.HealthText:SetText("AFK")
		end
	end
	local name = UnitName(unit)
	button.Name:SetText(name or "")
	if cfg.showPower and button.Power:IsShown() then
		local kind = UnitPowerType(unit)
		button.Power:SetStatusBarColor(Soul:PowerColor(kind))
		if not Soul.Secret.IsSecret(kind) and type(kind) == "number" and curve then
			button.Power:SetMinMaxValues(0, 100)
			button.Power:SetValue(UnitPowerPercent(unit, kind, true, curve))
		elseif not Soul.Secret.IsSecret(kind) and type(kind) == "number" then
			button.Power:SetMinMaxValues(0, UnitPowerMax(unit, kind))
			button.Power:SetValue(UnitPower(unit, kind))
		end
	end
	local index = GetRaidTargetIndex(unit)
	if not Soul.Secret.IsSecret(index) and type(index) == "number" and index > 0 then
		SetRaidTargetIconTexture(button.RaidIcon, index)
		button.RaidIcon:Show()
	else
		button.RaidIcon:Hide()
	end
	local isTarget = UnitIsUnit(unit, "target")
	Soul.Secret.AlphaFromBool(button.TargetMark, isTarget, 1, 0)
	local inRange, checked = UnitInRange(unit)
	if Soul.Secret.IsSecret(checked) or checked then
		if not Soul.Secret.Present(inRange) then
			button:SetAlpha(1)
		else
			Soul.Secret.AlphaFromBool(button, inRange, 1, 0.45)
		end
	else
		button:SetAlpha(1)
	end
	UpdateRole(button, unit)
	local r, g, b = Soul:Accent()
	button.TargetMark:SetColorTexture(r, g, b, 1)
end

local function StyleButton(button, cfg)
	if button._soulReady then
		button._soulCfg = cfg
		LayoutChrome(button, cfg)
		return
	end
	button._soulCfg = cfg
	local health = Soul:StatusBar(button)
	button.Health = health
	local name = health:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	name:SetTextColor(1, 1, 1)
	button.Name = name
	local pct = health:CreateFontString(nil, "OVERLAY")
	pct:SetJustifyH("RIGHT")
	pct:SetTextColor(1, 1, 1)
	pct:SetPoint("RIGHT", health, "RIGHT", -4, 0)
	button.HealthText = pct
	name:SetPoint("LEFT", health, "LEFT", 4, 0)
	name:SetPoint("RIGHT", pct, "LEFT", -4, 0)
	local power = Soul:StatusBar(button)
	button.Power = power
	local mark = health:CreateTexture(nil, "OVERLAY", nil, 6)
	mark:SetPoint("TOPLEFT", health, "TOPLEFT")
	mark:SetPoint("TOPRIGHT", health, "TOPRIGHT")
	mark:SetHeight(2)
	mark:SetAlpha(0)
	button.TargetMark = mark
	local raid = button:CreateTexture(nil, "OVERLAY")
	raid:SetSize(14, 14)
	raid:SetPoint("CENTER", button, "TOP", 0, -2)
	raid:Hide()
	button.RaidIcon = raid
	local role = button:CreateTexture(nil, "OVERLAY")
	role:SetSize(12, 12)
	role:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
	button.Role = role
	Soul:Border(button)
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
	button._soulReady = true
	styled[#styled + 1] = button
	LayoutChrome(button, cfg)
	ConfigureAuras(button, cfg)
	Link(button, button:GetAttribute("unit"))
end

local function GridSize(kind, cfg)
	local gap = cfg.spacing or 2
	if kind == "party" then
		if cfg.orientation == "horizontal" then
			return cfg.width * 5 + gap * 4, cfg.height
		end
		return cfg.width, cfg.height * 5 + gap * 4
	end
	return cfg.width * 5 + gap * 4, cfg.height * 8 + gap * 7
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
	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("templateType", "Button")
	header:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
	header:SetAttribute("initialConfigFunction", CLICK)
	header:SetAttribute("soul-width", cfg.width)
	header:SetAttribute("soul-height", cfg.height)
	header:SetAttribute("showPlayer", cfg.showPlayer and true or false)
	header:SetAttribute("showSolo", false)
	header:SetAttribute("sortMethod", "INDEX")
	header:SetAttribute("sortDir", "ASC")
	local gap = cfg.spacing or 2
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
		header:SetAttribute("columnSpacing", -gap)
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
	HeaderButtons(header, function(button)
		StyleButton(button, cfg)
		button:SetSize(cfg.width, cfg.height)
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
	pack.holder:SetSize(width, height)
	pack.header:ClearAllPoints()
	pack.header:SetPoint("TOPLEFT", pack.holder, "TOPLEFT", 0, 0)
	pack.header:SetSize(cfg.width, cfg.height)
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

local function RefreshShown()
	for i = 1, #styled do
		if styled[i]:IsShown() then UpdateButton(styled[i]) end
	end
end

local function OnUnit(_, event, unit)
	if event == "PLAYER_TARGET_CHANGED" or event == "RAID_TARGET_UPDATE" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ROLES_ASSIGNED" then
		if event == "GROUP_ROSTER_UPDATE" then
			Secure("group:roster", function()
				if GF.headers then
					StyleHeader(GF.headers.party.header, DB().party)
					StyleHeader(GF.headers.raid.header, DB().raid)
				end
				RefreshShown()
			end)
			return
		end
		RefreshShown()
		return
	end
	if type(unit) ~= "string" then return end
	local button = ButtonFor(unit)
	if button then UpdateButton(button) end
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
		"UNIT_IN_RANGE_UPDATE", "UNIT_FLAGS",
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

	local function GroupEdit(kind, across, down)
		return {
			onResize = function(width, height)
				local cfg = DB()[kind]
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
