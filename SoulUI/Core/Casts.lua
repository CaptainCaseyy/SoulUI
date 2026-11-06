if SoulUI_Blocked then return end

-- Shared cast-bar coloring for enemy casts (nameplates, target, focus).
--
--   interruptible, your interrupt ready  -> "interruptible" color (gold)
--   interruptible, your interrupt on CD  -> "kick on cooldown" color (dark orange)
--   not interruptible                    -> "locked" color (gray) + padlock icon
--   game flags the spell as important    -> pulsing red outline
--   important AND not interruptible      -> "STUN" badge: the kick won't land, so
--                                           a stun / knock / incapacitate is the answer
--
-- notInterruptible and the important flag can be secret booleans in combat. They
-- are never compared in Lua: colors go through C_CurveUtil.EvaluateColorValueFromBoolean
-- (bool, ifTrue, ifFalse) per channel, and visibility through SetAlphaFromBoolean.
-- "Important AND locked" is two nested frames, each with its own boolean alpha,
-- so the badge's visible alpha is the product of both.
--
-- The STUN hint is advice, not a game fact: Blizzard marks dangerous spells as
-- important, and a stun stops most uninterruptible casts on trash. Bosses are
-- immune to stuns whatever the badge says.

local Soul = SoulUI
local Cast = {}
Soul.Cast = Cast

local DEFAULTS = {
	interruptible = { 1.0, 0.72, 0.10 },
	kickCooldown = { 0.80, 0.33, 0.20 },
	locked = { 0.55, 0.55, 0.60 },
	important = { 1.0, 0.18, 0.18 },
	showLock = true,
	showImportant = true,
	showStun = true,
	kickColoring = true,
}
Cast.DEFAULTS = DEFAULTS

-- Interrupts by class. The first one the player knows is "the kick".
local KICKS = {
	WARRIOR = { 6552 },
	ROGUE = { 1766 },
	PALADIN = { 96231, 31935 },
	DEATHKNIGHT = { 47528 },
	SHAMAN = { 57994 },
	MAGE = { 2139 },
	WARLOCK = { 119910, 19647, 132409 },
	DRUID = { 106839, 78675 },
	HUNTER = { 147362, 187707 },
	MONK = { 116705 },
	DEMONHUNTER = { 183752 },
	EVOKER = { 351338 },
	PRIEST = { 15487 },
}

local kickSpell
local kickBuilt = false

local function Known(spellID)
	if not C_SpellBook then return false end
	local bank = Enum and Enum.SpellBookSpellBank
	local check = C_SpellBook.IsSpellKnownOrInSpellBook or C_SpellBook.IsSpellKnown
	if not check then return false end
	local ok, known = pcall(check, spellID, bank and bank.Player)
	if ok and known == true then return true end
	if bank and bank.Pet then
		ok, known = pcall(check, spellID, bank.Pet)
		if ok and known == true then return true end
	end
	return false
end

local function BuildKick()
	kickBuilt = true
	kickSpell = nil
	local _, class = UnitClass("player")
	local list = type(class) == "string" and KICKS[class]
	if not list then return end
	for i = 1, #list do
		if Known(list[i]) then
			kickSpell = list[i]
			return
		end
	end
end

function Cast.KickSpell()
	if not kickBuilt then BuildKick() end
	return kickSpell
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELLS_CHANGED")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:RegisterEvent("UNIT_PET")
watcher:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_PET" and unit ~= "player" then return end
	kickBuilt = false
end)

function Cast.Settings()
	local theme = Soul:Theme()
	if type(theme.cast) ~= "table" then theme.cast = {} end
	local cfg = theme.cast
	for key, value in pairs(DEFAULTS) do
		if cfg[key] == nil then
			cfg[key] = type(value) == "table" and { value[1], value[2], value[3] } or value
		end
	end
	return cfg
end

-- flag ? a : b, without branching on a secret flag.
local function Mix(flag, a, b)
	if type(flag) == "nil" then return b end
	if Soul.Secret.IsSecret(flag) then
		local eval = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
		if not eval then return b end
		local ok, value = pcall(eval, flag, a, b)
		if ok then return value end
		return b
	end
	if flag then return a end
	return b
end
Cast.Mix = Mix

-- Possibly-secret "your interrupt is ready" (nil when you have no interrupt).
function Cast.KickReady()
	local spell = Cast.KickSpell()
	if not spell or not C_Spell or not C_Spell.GetSpellCooldownDuration then return nil end
	local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spell)
	if not ok or not Soul.Secret.Present(duration) then return nil end
	if Soul.Secret.IsSecret(duration) or not duration.IsZero then return nil end
	local zok, ready = pcall(duration.IsZero, duration)
	if not zok then return nil end
	return ready
end

-- Final bar color for a cast. base (optional { r, g, b }) replaces the
-- interruptible color for one frame.
function Cast.Color(notInterruptible, base, ready)
	local cfg = Cast.Settings()
	local ir, ig, ib = cfg.interruptible[1], cfg.interruptible[2], cfg.interruptible[3]
	if type(base) == "table" then ir, ig, ib = base[1], base[2], base[3] end
	local r, g, b = ir, ig, ib
	if cfg.kickColoring then
		if type(ready) == "nil" then ready = Cast.KickReady() end
		if type(ready) ~= "nil" then
			local cd = cfg.kickCooldown
			r = Mix(ready, ir, cd[1])
			g = Mix(ready, ig, cd[2])
			b = Mix(ready, ib, cd[3])
		end
	end
	local lock = cfg.locked
	r = Mix(notInterruptible, lock[1], r)
	g = Mix(notInterruptible, lock[2], g)
	b = Mix(notInterruptible, lock[3], b)
	return r, g, b
end

-- Adds the lock icon, important outline and STUN badge to a cast frame.
-- bar is the StatusBar; host is the frame the decorations sit on.
function Cast.Decorate(host, bar)
	if host._soulCastDeco then return host._soulCastDeco end
	local deco = {}
	host._soulCastDeco = deco

	local lock = CreateFrame("Frame", nil, host)
	lock:SetFrameLevel(bar:GetFrameLevel() + 3)
	lock:SetAllPoints(bar)
	lock:SetAlpha(0)
	local lockIcon = lock:CreateTexture(nil, "OVERLAY")
	lockIcon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
	lockIcon:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	lockIcon:SetSize(14, 14)
	lockIcon:SetVertexColor(0.9, 0.9, 0.95)
	local lockEdge = Soul.UI and Soul.UI.Edge(lock, 0.75, 0.75, 0.8, 0.9, "OVERLAY")
	deco.lock = lock
	deco.lockIcon = lockIcon
	deco.lockEdge = lockEdge

	local glow = CreateFrame("Frame", nil, host)
	glow:SetFrameLevel(bar:GetFrameLevel() + 4)
	glow:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
	glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
	glow:SetAlpha(0)
	local pulse = CreateFrame("Frame", nil, glow)
	pulse:SetAllPoints()
	local edges = Soul.UI and Soul.UI.Edge(pulse, 1, 0.18, 0.18, 1, "OVERLAY")
	local innerHost = CreateFrame("Frame", nil, pulse)
	innerHost:SetPoint("TOPLEFT", 1, -1)
	innerHost:SetPoint("BOTTOMRIGHT", -1, 1)
	local inner = Soul.UI and Soul.UI.Edge(innerHost, 1, 0.18, 0.18, 0.6, "OVERLAY")
	local anim = pulse:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local fade = anim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.45)
	anim:Play()
	deco.glow = glow
	deco.glowEdges = edges
	deco.glowInner = inner

	-- STUN badge: holder alpha = locked, badge alpha = important.
	local stunHolder = CreateFrame("Frame", nil, host)
	stunHolder:SetFrameLevel(bar:GetFrameLevel() + 6)
	stunHolder:SetAllPoints(bar)
	stunHolder:SetAlpha(0)
	local badge = CreateFrame("Frame", nil, stunHolder)
	badge:SetPoint("LEFT", bar, "LEFT", 4, 0)
	badge:SetSize(38, 14)
	badge:SetAlpha(0)
	local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
	badgeBg:SetAllPoints()
	badgeBg:SetColorTexture(0.85, 0.12, 0.12, 0.95)
	local badgeText = badge:CreateFontString(nil, "OVERLAY")
	badgeText:SetPoint("CENTER", 0, 0)
	Soul:ApplyFont(badgeText, 10, "OUTLINE")
	badgeText:SetText("STUN")
	badgeText:SetTextColor(1, 1, 1)
	deco.stunHolder = stunHolder
	deco.badge = badge
	deco.badgeText = badgeText
	return deco
end

local function BoolAlpha(frame, flag)
	if type(flag) == "nil" then
		frame:SetAlpha(0)
	elseif Soul.Secret.IsSecret(flag) then
		if frame.SetAlphaFromBoolean then
			pcall(frame.SetAlphaFromBoolean, frame, flag, 1, 0)
		else
			frame:SetAlpha(0)
		end
	else
		frame:SetAlpha(flag and 1 or 0)
	end
end

local function Important(spellID)
	if not C_Spell or not C_Spell.IsSpellImportant or type(spellID) == "nil" then return nil end
	local ok, flag = pcall(C_Spell.IsSpellImportant, spellID)
	if ok then return flag end
	return nil
end

-- Colors the bar and drives the decorations for one cast.
function Cast.Paint(host, bar, notInterruptible, spellID, base)
	local cfg = Cast.Settings()
	local ok, r, g, b = pcall(Cast.Color, notInterruptible, base)
	if ok then
		bar:SetStatusBarColor(r, g, b)
	else
		local c = cfg.interruptible
		bar:SetStatusBarColor(c[1], c[2], c[3])
	end
	local deco = Cast.Decorate(host, bar)
	if cfg.showLock then BoolAlpha(deco.lock, notInterruptible) else deco.lock:SetAlpha(0) end
	local important = Important(spellID)
	local ic = cfg.important
	if deco.glowEdges then deco.glowEdges:SetColor(ic[1], ic[2], ic[3], 1) end
	if deco.glowInner then deco.glowInner:SetColor(ic[1], ic[2], ic[3], 0.6) end
	if cfg.showImportant then BoolAlpha(deco.glow, important) else deco.glow:SetAlpha(0) end
	if cfg.showStun then
		BoolAlpha(deco.stunHolder, notInterruptible)
		BoolAlpha(deco.badge, important)
	else
		deco.stunHolder:SetAlpha(0)
	end
	local state = host._soulCastState or {}
	state.notInterruptible, state.spellID, state.base, state.active = notInterruptible, spellID, base, true
	host._soulCastState = state
end

-- Re-colors an active cast (your interrupt came off cooldown mid-cast).
-- ready: KickReady() computed once by the caller for all bars.
function Cast.Recolor(host, bar, ready)
	local state = host._soulCastState
	if not state or not state.active or not host:IsShown() then return end
	local ok, r, g, b = pcall(Cast.Color, state.notInterruptible, state.base, ready)
	if ok then bar:SetStatusBarColor(r, g, b) end
end

function Cast.Clear(host)
	if host._soulCastState then host._soulCastState.active = false end
	local deco = host._soulCastDeco
	if not deco then return end
	deco.lock:SetAlpha(0)
	deco.glow:SetAlpha(0)
	deco.stunHolder:SetAlpha(0)
end

-- Sizes the lock icon and badge to a bar height.
function Cast.Size(host, height)
	local deco = host._soulCastDeco
	if not deco then return end
	local h = math.max(8, height or 14)
	deco.lockIcon:SetSize(h, h)
	deco.badge:SetSize(math.max(28, h * 2.6), h)
	Soul:ApplyFont(deco.badgeText, math.max(8, math.floor(h * 0.7)), "OUTLINE")
end

-- Cast sample for edit mode / previews.
function Cast.Preview(host, bar, kind)
	local cfg = Cast.Settings()
	local deco = Cast.Decorate(host, bar)
	local c = cfg.interruptible
	if kind == "locked" then c = cfg.locked end
	bar:SetStatusBarColor(c[1], c[2], c[3])
	deco.lock:SetAlpha(kind == "locked" and 1 or 0)
	deco.glow:SetAlpha(0)
	deco.stunHolder:SetAlpha(0)
end
