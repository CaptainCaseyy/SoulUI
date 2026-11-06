if SoulUI_Blocked then return end

-- Blizzard frames SoulUI replaces or manages (settings: profile.blizzard).
--
--   Player / pet cast bar     PlayerCastingBarFrame and PetCastingBarFrame are
--                             parked under a hidden parent while a SoulUI player
--                             cast bar is on, so only one cast bar shows.
--   Personal resource display the health/power/cast plate above your character
--                             (CVar nameplateShowSelf).
--   Cooldown Manager          Blizzard's spell/buff icon rows (CVar
--                             cooldownViewerEnabled). Each viewer gets an
--                             edit-mode mover; a viewer can be hidden on its own.
--
-- Parking (SetParent to a hidden frame) hides a frame no matter what Blizzard
-- does with Show/alpha. Blizzard re-parents the cast bar when Edit Mode applies
-- a layout, so a SetParent hook re-parks it on the next frame, outside
-- Blizzard's call. Nothing here runs in combat; changes wait for it to end.

local Soul = SoulUI
local Blizz = {}
Soul.Blizz = Blizz

local DEFAULTS = {
	hideCastBar = true,      -- hide Blizzard's player and pet cast bars while a SoulUI player cast bar is on
	personalDisplay = false, -- Blizzard's personal resource display above your character
	cooldownManager = false, -- Blizzard's Cooldown Manager rows
}

local VIEWERS = {
	{ name = "EssentialCooldownViewer", label = "Cooldowns: Essential" },
	{ name = "UtilityCooldownViewer", label = "Cooldowns: Utility" },
	{ name = "BuffIconCooldownViewer", label = "Cooldowns: Buff Icons" },
	{ name = "BuffBarCooldownViewer", label = "Cooldowns: Buff Bars" },
}
Blizz.VIEWERS = VIEWERS

function Blizz.Settings()
	local profile = Soul:ActiveProfile()
	if type(profile.blizzard) ~= "table" then profile.blizzard = {} end
	local cfg = profile.blizzard
	for key, value in pairs(DEFAULTS) do
		if cfg[key] == nil then cfg[key] = value end
	end
	if type(cfg.hiddenViewers) ~= "table" then cfg.hiddenViewers = {} end
	return cfg
end

------------------------------------------------------------------------------
-- Parking
------------------------------------------------------------------------------

local hidden = CreateFrame("Frame", "SoulUI_BlizzardParking", UIParent)
hidden:Hide()
hidden:EnableMouse(false)

local original = {}  -- frame -> parent before we parked it
local wanted = {}    -- frame -> true while it should stay parked
local hooked = {}
local guard = false

local Refresh

local function Park(frame)
	if frame:GetParent() == hidden then return end
	original[frame] = frame:GetParent()
	guard = true
	frame:SetParent(hidden)
	guard = false
end

local function Unpark(frame)
	if frame:GetParent() ~= hidden then return end
	guard = true
	frame:SetParent(original[frame] or UIParent)
	guard = false
end

local repark = false
local function QueueRefresh()
	if repark then return end
	repark = true
	C_Timer.After(0, function()
		repark = false
		Soul:RunAfterCombat("blizzard-refresh", Refresh)
	end)
end

local function Hook(frame)
	if hooked[frame] then return end
	hooked[frame] = true
	hooksecurefunc(frame, "SetParent", function(self, parent)
		if guard or parent == hidden then return end
		-- Blizzard moved it somewhere else: remember where, park again if needed.
		original[self] = parent
		if wanted[self] then QueueRefresh() end
	end)
end

local function SetParked(frame, park)
	if not frame or Soul:IsForeignFrame(frame) then return end
	Hook(frame)
	wanted[frame] = park and true or nil
	if park then Park(frame) else Unpark(frame) end
end

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

local function ModuleOn(key)
	return Soul._moduleDefaults and Soul._moduleDefaults[key] ~= nil
end

-- True while SoulUI draws a player cast bar of its own.
function Blizz.SoulCastShown()
	if ModuleOn("ResourceBars") and Soul:ModuleDB("ResourceBars").showCast then return true end
	if ModuleOn("UnitFrames") then
		local units = Soul:ModuleDB("UnitFrames").units
		local player = units and units.player
		if player and player.enabled and player.showCast then return true end
	end
	return false
end

local function SetCVarIfKnown(name, value)
	local current = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name) or GetCVar(name)
	if current == nil then return end
	if current ~= value then Soul:SetOwnedCVar(name, value, "Blizzard") end
end

local viewerPlacing = false
local viewerHooked = {}
local viewerHome = {}   -- frame -> Blizzard's anchor before SoulUI moved it
local viewerMoved = {}  -- frame -> true once SoulUI moved it

local function PlaceViewer(frame, key)
	viewerPlacing = true
	if Soul:GetUnlockPosition(key) then
		viewerMoved[frame] = true
		Soul:Place(frame, key)
	elseif viewerMoved[frame] and viewerHome[frame] then
		-- Position cleared (Cancel, Reset Position): hand it back to Blizzard's spot.
		local home = viewerHome[frame]
		frame:ClearAllPoints()
		frame:SetPoint(home[1], home[2], home[3], home[4], home[5])
		viewerMoved[frame] = nil
	end
	viewerPlacing = false
end

local function HookViewer(frame, key)
	if viewerHooked[frame] then return end
	viewerHooked[frame] = true
	local point, relativeTo, relPoint, x, y = frame:GetPoint(1)
	if point then viewerHome[frame] = { point, relativeTo or UIParent, relPoint or point, x or 0, y or 0 } end
	-- Edit Mode re-anchors the viewers when it applies a layout. Put ours back
	-- (only for viewers the user placed in SoulUI's edit mode).
	hooksecurefunc(frame, "SetPoint", function()
		if viewerPlacing then return end
		if Soul.unlocking then
			viewerMoved[frame] = true -- dragged in SoulUI edit mode
			return
		end
		if not Soul:GetUnlockPosition(key) then
			-- Blizzard placed it and SoulUI holds no position: that is its home now.
			viewerMoved[frame] = nil
			local point, relativeTo, relPoint, x, y = frame:GetPoint(1)
			if point then viewerHome[frame] = { point, relativeTo or UIParent, relPoint or point, x or 0, y or 0 } end
			return
		end
		QueueRefresh()
	end)
end

Refresh = function()
	if InCombatLockdown() then
		Soul:RunAfterCombat("blizzard-refresh", Refresh)
		return
	end
	local cfg = Blizz.Settings()
	local hideCast = cfg.hideCastBar and Blizz.SoulCastShown()
	SetParked(_G.PlayerCastingBarFrame, hideCast)
	SetParked(_G.PetCastingBarFrame, hideCast)

	SetCVarIfKnown("nameplateShowSelf", cfg.personalDisplay and "1" or "0")
	SetCVarIfKnown("cooldownViewerEnabled", cfg.cooldownManager and "1" or "0")

	for i = 1, #VIEWERS do
		local info = VIEWERS[i]
		local frame = _G[info.name]
		if frame then
			local key = "Blizzard:" .. info.name
			HookViewer(frame, key)
			SetParked(frame, not cfg.cooldownManager or cfg.hiddenViewers[info.name])
			PlaceViewer(frame, key)
		end
	end
end
Blizz.Refresh = function() Soul:RunAfterCombat("blizzard-refresh", Refresh) end

------------------------------------------------------------------------------
-- Edit-mode movers for the Cooldown Manager viewers
------------------------------------------------------------------------------

local function RegisterViewers()
	for i = 1, #VIEWERS do
		local info = VIEWERS[i]
		if _G[info.name] then
			local name = info.name
			Soul:RegisterMover({
				key = "Blizzard:" .. name,
				label = info.label,
				page = "general",
				getFrame = function() return _G[name] end,
				onReset = function() Blizz.Refresh() end,
				getEnabled = function()
					local cfg = Blizz.Settings()
					return cfg.cooldownManager and not cfg.hiddenViewers[name]
				end,
				setEnabled = function(on)
					local cfg = Blizz.Settings()
					if on then
						cfg.cooldownManager = true
						cfg.hiddenViewers[name] = nil
					else
						cfg.hiddenViewers[name] = true
					end
					Blizz.Refresh()
				end,
			})
		end
	end
end

Soul:On("Ready", function()
	if C_AddOns and C_AddOns.LoadAddOn and not _G.EssentialCooldownViewer then
		pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
	end
	RegisterViewers()
	Blizz.Refresh()
	-- Modules apply their own settings after Ready; check the cast bar again.
	C_Timer.After(1, Blizz.Refresh)
end)
Soul:On("ProfileChanged", function() Blizz.Refresh() end)
