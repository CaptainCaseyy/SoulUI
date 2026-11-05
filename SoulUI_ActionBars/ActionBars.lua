if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI

local hooked = {}
local hidden

local PARK_FRAMES = {
	"MultiBarBottomLeft",
	"MultiBarBottomRight",
	"MultiBarRight",
	"MultiBarLeft",
	"MultiBar5",
	"MultiBar6",
	"MultiBar7",
}

local QUIET_BUTTONS = {
	{ "ActionButton", 12 },
	{ "MultiBarBottomLeftButton", 12 },
	{ "MultiBarBottomRightButton", 12 },
	{ "MultiBarRightButton", 12 },
	{ "MultiBarLeftButton", 12 },
	{ "MultiBar5Button", 12 },
	{ "MultiBar6Button", 12 },
	{ "MultiBar7Button", 12 },
}

local LEAN = {
	"ACTIONBAR_UPDATE_STATE",
	"ACTIONBAR_UPDATE_USABLE",
	"PLAYER_ENTERING_WORLD",
	"UPDATE_SHAPESHIFT_FORM",
	"SPELL_UPDATE_CHARGES",
	"UPDATE_INVENTORY_ALERTS",
	"PLAYER_EQUIPMENT_CHANGED",
	"PLAYER_TARGET_CHANGED",
}

local PAGE_CONDITION = "[vehicleui] 12; [possessbar] 12; [overridebar] 14; [shapeshift] 13; [bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; [bonusbar:5] 11; [bonusbar:4] 10; [bonusbar:3] 9; [bonusbar:2] 8; [bonusbar:1] 7; 1"

local PAGE_SNIPPET = [=[
local page = tonumber(newstate) or 1
self:SetAttribute("actionpage", page)
self:ChildUpdate("page", page)
local main = self:GetFrameRef("MainActionBar")
if main then
	main:SetAttribute("actionpage", page)
end
]=]

local CHILD_SNIPPET = [=[
local page = tonumber(message) or 1
local index = self:GetAttribute("index") or 1
self:SetAttribute("action", (page - 1) * 12 + index)
]=]

local BARS = {
	{ key = "main", label = "Main Bar", paged = true, bind = "ACTIONBUTTON" },
	{ key = "bar2", label = "Bottom Left", first = 61, bind = "MULTIACTIONBAR1BUTTON" },
	{ key = "bar3", label = "Bottom Right", first = 49, bind = "MULTIACTIONBAR2BUTTON" },
	{ key = "bar4", label = "Right Bar", first = 25, bind = "MULTIACTIONBAR3BUTTON" },
	{ key = "bar5", label = "Left Bar", first = 37, bind = "MULTIACTIONBAR4BUTTON" },
	{ key = "bar6", label = "Extra Bar 1", first = 145, bind = "MULTIACTIONBAR5BUTTON" },
	{ key = "bar7", label = "Extra Bar 2", first = 157, bind = "MULTIACTIONBAR6BUTTON" },
	{ key = "bar8", label = "Extra Bar 3", first = 169, bind = "MULTIACTIONBAR7BUTTON" },
}

local function HiddenParent()
	if hidden then return hidden end
	hidden = CreateFrame("Frame", "SoulUI_HiddenBars")
	hidden:Hide()
	hidden:SetSize(1, 1)
	return hidden
end

local function ParkFrame(frame)
	if not frame or hooked[frame] then return end
	local parent = HiddenParent()
	local ok = pcall(frame.SetParent, frame, parent)
	if not ok then return end
	hooked[frame] = true
	frame:HookScript("OnShow", function(self)
		local function back()
			pcall(self.SetParent, self, parent)
		end
		if InCombatLockdown() then
			Soul:RunAfterCombat("bars:park:" .. (self:GetName() or "bar"), back)
		else
			back()
		end
	end)
end

local function QuietButton(button)
	if not button or hooked[button] then return end
	hooked[button] = true
	pcall(button.UnregisterAllEvents, button)
	pcall(button.EnableMouse, button, false)
	pcall(button.SetAlpha, button, 0)
	if button.SetAttributeNoHandler then
		pcall(button.SetAttributeNoHandler, button, "statehidden", true)
	end
end

local function QuietMain()
	local main = _G.MainActionBar or _G.MainMenuBar
	if not main then return end
	pcall(main.SetAlpha, main, 0)
	if not InCombatLockdown() then
		pcall(main.EnableMouse, main, false)
	end
	if not hooked[main] then
		hooked[main] = true
		main:HookScript("OnShow", function(self)
			pcall(self.SetAlpha, self, 0)
			if not InCombatLockdown() then
				pcall(self.EnableMouse, self, false)
			end
		end)
	end
	local kids = { main:GetChildren() }
	for i = 1, #kids do
		if not InCombatLockdown() then
			pcall(kids[i].EnableMouse, kids[i], false)
		end
	end
end

local function Park()
	for i = 1, #PARK_FRAMES do
		ParkFrame(_G[PARK_FRAMES[i]])
	end
	for i = 1, #QUIET_BUTTONS do
		local prefix = QUIET_BUTTONS[i][1]
		local count = QUIET_BUTTONS[i][2]
		for n = 1, count do
			QuietButton(_G[prefix .. n])
		end
	end
	QuietMain()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, _, name)
	if name == "Blizzard_ActionBar" or name == "Blizzard_OverrideActionBar" then
		Park()
	end
end)
Park()

local AB = Soul:NewModule("ActionBars", "SoulUI_ActionBars")
AB.buttons = {}
AB.bars = {}

local rangeOn = {}
local desat = { curve = nil, built = 0, haste = -1 }

local function DB()
	return Soul:ModuleDB("ActionBars")
end

local function Secure(key, fn)
	if InCombatLockdown() then
		Soul:RunAfterCombat(key, fn)
	else
		fn()
	end
end

local function IconOf(btn)
	return btn.icon or btn.Icon
end

local function ShortKey(key)
	if type(key) ~= "string" then return "" end
	key = key:gsub("CTRL%-", "C")
	key = key:gsub("ALT%-", "A")
	key = key:gsub("SHIFT%-", "S")
	key = key:gsub("META%-", "M")
	key = key:gsub("MOUSEWHEELUP", "MwU")
	key = key:gsub("MOUSEWHEELDOWN", "MwD")
	key = key:gsub("NUMPAD", "N")
	key = key:gsub("BUTTON", "M")
	return key
end

local function DesatCurve()
	if not C_CurveUtil or not C_CurveUtil.CreateCurve or not Enum or not Enum.LuaCurveType then
		return nil
	end
	local now = GetTime() or 0
	local haste = 0
	if GetHaste then
		local value = GetHaste()
		if not Soul.Secret.IsSecret(value) and type(value) == "number" then
			haste = value
		end
	end
	if desat.curve and (now - desat.built) < 2 then return desat.curve end
	if desat.curve and math.abs(haste - desat.haste) < 5 and (now - desat.built) < 10 then
		return desat.curve
	end
	local curve = C_CurveUtil.CreateCurve()
	local ok = pcall(function()
		curve:SetType(Enum.LuaCurveType.Step)
		local gcd = 1.5 / (1 + haste / 100)
		if gcd < 0.75 then gcd = 0.75 end
		gcd = math.floor((gcd + 0.15) / 0.05 + 0.5) * 0.05
		curve:AddPoint(0, 0)
		curve:AddPoint(gcd, 1)
	end)
	if not ok then return nil end
	desat.curve = curve
	desat.built = now
	desat.haste = haste
	return curve
end

local function Detach(btn)
	local hosts = { ActionBarButtonEventsFrame, ActionBarActionEventsFrame }
	for h = 1, #hosts do
		local list = hosts[h] and hosts[h].frames
		if type(list) == "table" then
			for i = #list, 1, -1 do
				if list[i] == btn then
					list[i] = nil
					break
				end
			end
		end
	end
end

local function WatchRange(btn, action)
	if rangeOn[btn] == action then return end
	rangeOn[btn] = action
	if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
		pcall(C_ActionBar.EnableActionRangeCheck, action, true)
	end
end

local function HideFrame(btn)
	local normal = btn.GetNormalTexture and btn:GetNormalTexture()
	if normal and normal.SetAlpha then normal:SetAlpha(0) end
	if btn.NormalTexture and btn.NormalTexture.SetAlpha then btn.NormalTexture:SetAlpha(0) end
	if btn.SlotBackground and btn.SlotBackground.SetAlpha then btn.SlotBackground:SetAlpha(0) end
	if btn.SlotArt and btn.SlotArt.SetAlpha then btn.SlotArt:SetAlpha(0) end
	if btn.FloatingBG and btn.FloatingBG.SetAlpha then btn.FloatingBG:SetAlpha(0) end
end

local function PaintButton(btn)
	HideFrame(btn)
	local action = btn:GetAttribute("action")
	if type(action) ~= "number" then return end
	local icon = IconOf(btn)
	local count = btn.Count
	local name = btn.Name
	local cooldown = btn.cooldown or btn.Cooldown
	if not C_ActionBar then return end
	if C_ActionBar.HasAction then
		local has = C_ActionBar.HasAction(action)
		if not Soul.Secret.IsSecret(has) and not has then
			if icon then icon:SetTexture(nil) end
			if count then count:SetText("") end
			if name then name:SetText("") end
			if cooldown and cooldown.Clear then pcall(cooldown.Clear, cooldown) end
			if btn._soulEmpty then btn._soulEmpty:Show() end
			return
		end
		if btn._soulEmpty then btn._soulEmpty:Hide() end
	end
	WatchRange(btn, action)
	if icon and C_ActionBar.GetActionTexture then
		local texture = C_ActionBar.GetActionTexture(action)
		if Soul.Secret.Present(texture) then
			pcall(icon.SetTexture, icon, texture)
		end
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	if count and C_ActionBar.GetActionDisplayCount then
		local shown = C_ActionBar.GetActionDisplayCount(action)
		if not Soul.Secret.Present(shown) then
			count:SetText("")
		elseif Soul.Secret.IsSecret(shown) or (shown ~= 0 and shown ~= "" and shown ~= "0") then
			count:SetText(shown)
		else
			count:SetText("")
		end
	end
	if name and C_ActionBar.GetActionText then
		local text = C_ActionBar.GetActionText(action)
		if Soul.Secret.Present(text) then
			name:SetText(text)
		else
			name:SetText("")
		end
	end
	if icon and C_ActionBar.IsUsableAction then
		local usable, noPower = C_ActionBar.IsUsableAction(action)
		if not Soul.Secret.IsSecret(usable) and type(usable) ~= "nil" then
			if usable then
				icon:SetVertexColor(1, 1, 1)
			elseif not Soul.Secret.IsSecret(noPower) and noPower then
				icon:SetVertexColor(0.35, 0.35, 0.9)
			else
				icon:SetVertexColor(0.4, 0.4, 0.4)
			end
		end
	end
	if icon and C_ActionBar.IsActionInRange then
		local inRange = C_ActionBar.IsActionInRange(action)
		if not Soul.Secret.IsSecret(inRange) and inRange == false then
			icon:SetVertexColor(0.85, 0.15, 0.15)
		end
	end
	local duration = C_ActionBar.GetActionCooldownDuration and C_ActionBar.GetActionCooldownDuration(action)
	if cooldown then
		if duration then
			pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration)
		elseif cooldown.Clear then
			pcall(cooldown.Clear, cooldown)
		end
	end
	if btn.chargeCooldown and C_ActionBar.GetActionChargeDuration then
		local chargeDuration = C_ActionBar.GetActionChargeDuration(action)
		if chargeDuration then
			pcall(btn.chargeCooldown.SetCooldownFromDurationObject, btn.chargeCooldown, chargeDuration)
		elseif btn.chargeCooldown.Clear then
			pcall(btn.chargeCooldown.Clear, btn.chargeCooldown)
		end
	end
	if icon and Soul.Secret.Present(duration) and not Soul.Secret.IsSecret(duration) and duration.EvaluateTotalDuration then
		local curve = DesatCurve()
		if curve then
			pcall(icon.SetDesaturation, icon, duration:EvaluateTotalDuration(curve, 0))
		end
	elseif icon and C_ActionBar.GetActionCooldown then
		local info = C_ActionBar.GetActionCooldown(action)
		local open = info and not Soul.Secret.IsSecret(info) and not (issecrettable and issecrettable(info))
		if open and not (canaccesstable and not canaccesstable(info))
			and type(info.isActive) == "boolean" and type(info.isOnGCD) == "boolean" then
			icon:SetDesaturated(info.isActive and not info.isOnGCD)
		end
	end
	if icon and C_ActionBar.GetActionCharges then
		local charges = C_ActionBar.GetActionCharges(action)
		local open = charges and not Soul.Secret.IsSecret(charges) and not (issecrettable and issecrettable(charges))
		if open and not (canaccesstable and not canaccesstable(charges)) then
			local current = charges.currentCharges
			if not Soul.Secret.IsSecret(current) and type(current) == "number" and current > 0 then
				icon:SetDesaturated(false)
			end
		end
	end
end

local function PaintAll(slot)
	for i = 1, #AB.buttons do
		local btn = AB.buttons[i]
		if slot == nil or btn:GetAttribute("action") == slot then
			PaintButton(btn)
		end
	end
end

local function TextSizes(btn)
	local db = DB()
	local size = btn._soulSize or 45
	local hotkey = db.hotkeySize or 0
	if hotkey <= 0 then hotkey = math.max(8, math.floor(size * 0.27 + 0.5)) end
	local count = db.countSize or 0
	if count <= 0 then count = math.max(8, math.floor(size * 0.3 + 0.5)) end
	local macro = db.macroSize or 0
	if macro <= 0 then macro = math.max(7, math.floor(size * 0.22 + 0.5)) end
	return hotkey, count, macro
end

local function RefreshText(btn)
	local db = DB()
	local cfg = btn._soulBar and db.bars[btn._soulBar]
	local hotkeySize, countSize, macroSize = TextSizes(btn)
	local hotkey = btn.HotKey
	if hotkey then
		Soul:ApplyFont(hotkey, hotkeySize, "OUTLINE")
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
		hotkey:SetJustifyH("RIGHT")
		hotkey:SetTextColor(1, 1, 1)
		local command = btn._soulBind
		local key = command and GetBindingKey(command)
		hotkey:SetText(ShortKey(key))
		hotkey:SetShown(not cfg or cfg.showHotkey ~= false)
	end
	if btn.Count then
		Soul:ApplyFont(btn.Count, countSize, "OUTLINE")
		btn.Count:ClearAllPoints()
		btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
		btn.Count:SetShown(not cfg or cfg.showCount ~= false)
	end
	if btn.Name then
		Soul:ApplyFont(btn.Name, macroSize, "OUTLINE")
		btn.Name:ClearAllPoints()
		btn.Name:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
		btn.Name:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
		btn.Name:SetShown(cfg and cfg.showMacro and true or false)
	end
end

local function RefreshHotkeys()
	for i = 1, #AB.buttons do
		RefreshText(AB.buttons[i])
	end
end

local function ApplyKeyDown()
	local down = GetCVar("ActionButtonUseKeyDown") == "1"
	local function run()
		for i = 1, #AB.buttons do
			AB.buttons[i]:SetAttribute("useOnKeyDown", down)
		end
	end
	Secure("bars:keydown", run)
end

local function BindHover(bar, btn)
	btn:HookScript("OnEnter", function()
		if bar._soulFade then bar:SetAlpha(1) end
	end)
	btn:HookScript("OnLeave", function()
		if not bar._soulFade then return end
		local fade = bar._soulFade
		local holder = bar._soulHolder
		C_Timer.After(0.05, function()
			if holder and not holder:IsMouseOver() then
				bar:SetAlpha(fade)
			end
		end)
	end)
end

local function Visibility(cfg)
	if not cfg.enabled then return "hide" end
	if cfg.visibility == "combat" then
		return "[petbattle] hide; [combat] show; hide"
	end
	if cfg.visibility == "nocombat" then
		return "[petbattle][combat] hide; show"
	end
	return "[petbattle] hide; show"
end

-- Button count, grid shape, pixel-snapped size and gap. "rows" means rows for a
-- horizontal bar and columns for a vertical one, so a 2-wide vertical bar works.
local function Grid(cfg)
	local count = cfg.buttons or 12
	if count < 1 then count = 1 end
	if count > 12 then count = 12 end
	local size = Soul.Pixel:Scale(cfg.size or 45)
	local gap = cfg.spacing or 1
	if gap < 0 then gap = 0 end
	gap = Soul.Pixel:Scale(gap)
	local lines = cfg.rows or 1
	if lines < 1 then lines = 1 end
	if lines > count then lines = count end
	-- 12 buttons on 5 lines only fills 4; size the holder for what is used.
	lines = math.ceil(count / math.ceil(count / lines))
	local cols, rows
	if cfg.vertical then
		cols = lines
		rows = math.ceil(count / lines)
	else
		rows = lines
		cols = math.ceil(count / lines)
	end
	return count, cols, rows, size, gap
end

local function SpellIcon(btn)
	local icon = IconOf(btn)
	if icon then return icon end
	local name = btn.GetName and btn:GetName()
	if name and _G[name .. "Icon"] then return _G[name .. "Icon"] end
	return nil
end

-- The 12.x template masks its icon with a fixed 45px rounded mask. While that
-- mask is attached the art keeps drawing at template size whatever the button
-- size is, which is what made icons spill out of their slots.
local function DropIconMask(btn)
	if btn._soulMaskGone then return end
	local icon = SpellIcon(btn)
	local mask = btn.IconMask
	if not icon or not mask then return end
	btn._soulMaskGone = true
	pcall(icon.RemoveMaskTexture, icon, mask)
	mask:Hide()
	mask:SetTexture(nil)
	mask:ClearAllPoints()
	mask:SetSize(0.001, 0.001)
end

local function Flat(texture, r, g, b, a)
	if not texture then return end
	texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetVertexColor(r, g, b, a)
	texture:ClearAllPoints()
	texture:SetAllPoints(texture:GetParent())
end

local function FitIcon(btn)
	local icon = SpellIcon(btn)
	if not icon then return end
	local inset = DB().showBorder and Soul.Pixel:Scale(1) or 0
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
	icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- Sizes the button for real (no SetScale). SetScale also scales SetPoint
-- offsets, which spread the old buttons apart until the holder cut them off.
local function Chrome(btn, size)
	if not size or size < 8 then size = 45 end
	btn._soulSize = size
	btn:SetScale(1)
	btn:SetSize(size, size)
	HideFrame(btn)
	DropIconMask(btn)
	FitIcon(btn)
	local icon = SpellIcon(btn)
	local cooldown = btn.cooldown or btn.Cooldown
	if cooldown then
		cooldown:ClearAllPoints()
		cooldown:SetAllPoints(icon or btn)
	end
	if btn.chargeCooldown then
		btn.chargeCooldown:ClearAllPoints()
		btn.chargeCooldown:SetAllPoints(icon or btn)
	end
	local r, g, b = Soul:Accent()
	if not btn._soulFlat then
		btn._soulFlat = true
		Flat(btn.GetHighlightTexture and btn:GetHighlightTexture(), 1, 1, 1, 0.16)
		Flat(btn.GetPushedTexture and btn:GetPushedTexture(), 1, 1, 1, 0.24)
	end
	Flat(btn.GetCheckedTexture and btn:GetCheckedTexture(), r, g, b, 0.35)
	if btn.Flash then
		btn.Flash:ClearAllPoints()
		btn.Flash:SetAllPoints(btn)
	end
	if btn.Border then
		btn.Border:ClearAllPoints()
		btn.Border:SetAllPoints(btn)
	end
	if btn.AutoCastOverlay then btn.AutoCastOverlay:SetAllPoints(btn) end
	local scale = size / 45
	if btn.SpellActivationAlert then btn.SpellActivationAlert:SetScale(scale) end
	if btn.TargetReticleAnimFrame then btn.TargetReticleAnimFrame:SetScale(scale) end
	if btn.AssistedCombatRotationFrame then btn.AssistedCombatRotationFrame:SetScale(scale) end
	Soul:ShowBorder(btn, DB().showBorder and true or false, 1)
	RefreshText(btn)
	if not btn._soulFitHook then
		btn._soulFitHook = true
		btn:HookScript("OnShow", function(self)
			if InCombatLockdown() then return end
			if self._soulSize then Chrome(self, self._soulSize) end
		end)
	end
end

local function LayoutBar(def)
	local pack = AB.bars[def.key]
	if not pack then return end
	local cfg = DB().bars[def.key]
	local count, cols, rows, size, gap = Grid(cfg)
	local width = cols * size + math.max(0, cols - 1) * gap
	local height = rows * size + math.max(0, rows - 1) * gap
	pack.holder:SetSize(width, height)
	if pack.holder.SetClipsChildren then pack.holder:SetClipsChildren(false) end
	pack.bar:ClearAllPoints()
	pack.bar:SetAllPoints(pack.holder)
	local emptyAlpha = DB().showEmpty == false and 0 or 0.85
	for i = 1, 12 do
		local btn = pack.buttons[i]
		btn._soulBar = def.key
		if i <= count then
			local col, row
			if cfg.vertical then
				col = math.floor((i - 1) / rows)
				row = (i - 1) % rows
			else
				col = (i - 1) % cols
				row = math.floor((i - 1) / cols)
			end
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", pack.bar, "TOPLEFT", col * (size + gap), -row * (size + gap))
			Chrome(btn, size)
			if btn._soulEmpty then
				local color = cfg.color
				if type(color) == "table" then
					btn._soulEmpty:SetColorTexture(color[1], color[2], color[3], emptyAlpha)
				else
					btn._soulEmpty:SetColorTexture(0.04, 0.04, 0.05, emptyAlpha)
				end
			end
			btn:Show()
		else
			btn:Hide()
		end
	end
	RegisterStateDriver(pack.bar, "visibility", Visibility(cfg))
	if cfg.fade and cfg.enabled then
		pack.bar._soulFade = cfg.fadeAlpha or 0
		pack.bar:SetAlpha(cfg.fadeAlpha or 0)
	else
		pack.bar._soulFade = nil
		pack.bar:SetAlpha(1)
	end
	Soul:Place(pack.holder, "ActionBars:" .. def.key, {
		point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y,
	})
end

local function CreateButton(def, pack, index)
	local name = "SoulUIAction_" .. def.key .. "_" .. index
	local ok, btn = pcall(CreateFrame, "CheckButton", name, pack.bar, "ActionBarButtonTemplate, SecureActionButtonTemplate")
	if not ok then
		Soul:Print("Action button template missing:", btn)
		return nil
	end
	local slot = def.paged and index or ((def.first or 1) + index - 1)
	btn:SetID(0)
	btn:SetAttribute("type", "action")
	btn:SetAttribute("action", slot)
	btn:SetAttribute("index", index)
	btn:SetAttribute("useOnKeyDown", GetCVar("ActionButtonUseKeyDown") == "1")
	btn._soulBind = def.bind .. index
	if def.paged then
		btn:SetAttribute("_childupdate-page", CHILD_SNIPPET)
	end
	btn:UnregisterAllEvents()
	for i = 1, #LEAN do
		btn:RegisterEvent(LEAN[i])
	end
	btn.UpdateButtonArt = function() end
	Detach(btn)
	local icon = IconOf(btn)
	if icon and not btn.chargeCooldown then
		local created, charge = pcall(CreateFrame, "Cooldown", nil, btn, "CooldownFrameTemplate")
		if created then
			charge:SetAllPoints(icon)
			if charge.SetDrawSwipe then charge:SetDrawSwipe(false) end
			if charge.SetDrawBling then charge:SetDrawBling(false) end
			if charge.SetHideCountdownNumbers then charge:SetHideCountdownNumbers(true) end
			btn.chargeCooldown = charge
		end
	end
	local empty = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
	empty:SetAllPoints()
	empty:SetColorTexture(0.04, 0.04, 0.05, 0.85)
	btn._soulEmpty = empty
	local highlight = btn.GetHighlightTexture and btn:GetHighlightTexture()
	if highlight then
		highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
		highlight:SetVertexColor(1, 1, 1, 0.18)
	end
	btn:HookScript("OnAttributeChanged", function(self, attribute)
		if attribute == "action" then PaintButton(self) end
	end)
	-- The template's own event handlers can re-anchor the icon and re-attach
	-- the mask; put both back after them.
	btn:HookScript("OnEvent", function(self)
		DropIconMask(self)
	end)
	BindHover(pack.bar, btn)
	AB.buttons[#AB.buttons + 1] = btn
	return btn
end

local function CreateBar(def)
	local holder = CreateFrame("Frame", "SoulUIBarHolder_" .. def.key, UIParent)
	holder:EnableMouse(false)
	local bar = CreateFrame("Frame", "SoulUIBar_" .. def.key, holder, "SecureHandlerStateTemplate")
	bar._soulHolder = holder
	local pack = { holder = holder, bar = bar, buttons = {}, def = def }
	if def.paged then
		local main = _G.MainActionBar
		if main then bar:SetFrameRef("MainActionBar", main) end
		bar:SetAttribute("_onstate-page", PAGE_SNIPPET)
		bar:SetAttribute("actionpage", 1)
	end
	for i = 1, 12 do
		local btn = CreateButton(def, pack, i)
		if not btn then return nil end
		pack.buttons[i] = btn
	end
	if def.paged then
		RegisterStateDriver(bar, "page", PAGE_CONDITION)
	end
	AB.bars[def.key] = pack
	return pack
end

local function OnDispatcher(_, event, arg1, arg2, arg3)
	if event == "ACTIONBAR_SLOT_CHANGED" then
		PaintAll(type(arg1) == "number" and arg1 or nil)
		return
	end
	if event == "ACTION_RANGE_CHECK_UPDATE" then
		if not Soul.Secret.IsSecret(arg2) and not Soul.Secret.IsSecret(arg3) and arg3 and arg2 == false then
			for i = 1, #AB.buttons do
				local btn = AB.buttons[i]
				if btn:GetAttribute("action") == arg1 then
					local icon = IconOf(btn)
					if icon then icon:SetVertexColor(0.85, 0.15, 0.15) end
				end
			end
		else
			PaintAll(type(arg1) == "number" and arg1 or nil)
		end
		return
	end
	if event == "UPDATE_BINDINGS" then
		RefreshHotkeys()
		return
	end
	if event == "CVAR_UPDATE" then
		ApplyKeyDown()
		RefreshHotkeys()
		return
	end
	PaintAll()
end

function AB:Apply()
	Secure("bars:apply", function()
		for i = 1, #BARS do
			LayoutBar(BARS[i])
		end
		PaintAll()
		RefreshHotkeys()
	end)
end

function AB:OnInitialize()
	Soul:RegisterModuleDB("ActionBars", Soul.Defaults.ActionBars)
end

function AB:OnEnable()
	Park()
	for i = 1, #BARS do
		if not CreateBar(BARS[i]) then return end
	end
	local events = {
		"ACTIONBAR_UPDATE_COOLDOWN",
		"SPELL_UPDATE_COOLDOWN",
		"ACTIONBAR_SLOT_CHANGED",
		"ACTIONBAR_UPDATE_USABLE",
		"ACTIONBAR_PAGE_CHANGED",
		"UPDATE_BONUS_ACTIONBAR",
		"UPDATE_VEHICLE_ACTIONBAR",
		"UPDATE_OVERRIDE_ACTIONBAR",
		"PLAYER_ENTERING_WORLD",
		"SPELL_UPDATE_CHARGES",
		"SPELL_UPDATE_ICON",
		"ACTION_RANGE_CHECK_UPDATE",
		"UPDATE_BINDINGS",
		"CVAR_UPDATE",
		"BAG_UPDATE_DELAYED",
	}
	for i = 1, #events do
		self:RegisterEvent(events[i], OnDispatcher)
	end
	for i = 1, #BARS do
		local def = BARS[i]
		local barKey = def.key
		Soul:RegisterMover({
			key = "ActionBars:" .. barKey,
			label = def.label,
			isHidden = function() return not DB().bars[barKey].enabled end,
			getFrame = function()
				local pack = AB.bars[barKey]
				return pack and pack.holder
			end,
			fallback = function()
				local cfg = DB().bars[barKey]
				return { point = "CENTER", relPoint = "CENTER", x = cfg.x, y = cfg.y }
			end,
			onResize = function(width, height)
				local cfg = DB().bars[barKey]
				local count, cols, rows, size, gap = Grid(cfg)
				local currentW = cols * size + gap * math.max(0, cols - 1)
				local currentH = rows * size + gap * math.max(0, rows - 1)
				local fromW = (width - gap * math.max(0, cols - 1)) / cols
				local fromH = (height - gap * math.max(0, rows - 1)) / rows
				local nextSize = (fromW + fromH) / 2
				if math.abs(nextSize - size) < 0.75 then
					if width > currentW + 0.05 or height > currentH + 0.05 then
						nextSize = size + 1
					elseif width < currentW - 0.05 or height < currentH - 0.05 then
						nextSize = size - 1
					else
						nextSize = size
					end
				end
				if nextSize < 12 then nextSize = 12 end
				if nextSize > 72 then nextSize = 72 end
				cfg.size = math.floor(nextSize + 0.5)
				LayoutBar(def)
			end,
			getColor = function()
				local cfg = DB().bars[barKey]
				if type(cfg.color) == "table" then return cfg.color[1], cfg.color[2], cfg.color[3] end
				return 0.04, 0.04, 0.05
			end,
			setColor = function(r, g, b)
				DB().bars[barKey].color = { r, g, b }
				LayoutBar(def)
			end,
		})
	end
	Soul:On("ProfileChanged", function() AB:Apply() end)
	Soul:On("ThemeChanged", function() RefreshHotkeys() end)
	self:Apply()
end
