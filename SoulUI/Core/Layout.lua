if SoulUI_Blocked then return end

local Soul = SoulUI

-- The default layout, measured off the owner's reference screenshot (a 1080p
-- stream). Everything is expressed in "pitches" P = one action button plus one
-- pixel, so the picture keeps its proportions at any resolution and UI scale:
--
--   * two 12-button rows centered on the screen, the lower row ~20% up from the
--     bottom edge
--   * five shard tiles centered above them, half the row width, 0.68P tall
--   * the player bar left of the shards (4.67P x 1.41P, 0.7P gap), bottoms
--     aligned with the shards; the target bar mirrors it on the right
--   * the pet bar left of the lower row, with a tiny 2x6 bar under it
--   * three vertical bar columns on the left edge, meters on the right edge
--
-- The layout is written into the profile once per LAYOUT_VERSION. After that
-- the profile is the user's: drags, resizes and editor changes are never
-- overwritten again unless they press "Reset layout" (Soul:ResetLayout()).
local LAYOUT_VERSION = 4

local function Round(value)
	return Soul.Pixel:Scale(math.floor(value + 0.5))
end

local function Pos(positions, key, x, y)
	positions[key] = { point = "CENTER", relPoint = "CENTER", x = Soul.Pixel:Scale(x), y = Soul.Pixel:Scale(y) }
end

local function Section(modules, key)
	if type(modules[key]) ~= "table" then modules[key] = {} end
	return modules[key]
end

-- Colton's live profile on 13 Nov 2026, captured from the Default profile.
-- Reset layout and a brand-new profile both start here.
local SNAPSHOT = {
	{ key = "ActionBars:main", x = -3.75, y = -306 },
	{ key = "ActionBars:bar2", x = -3.75, y = -376.5 },
	{ key = "ActionBars:bar3", x = -940.5, y = 50.25 },
	{ key = "ActionBars:bar4", x = -902.25, y = 50.25 },
	{ key = "ActionBars:bar5", x = -863.25, y = 50.25 },
	{ key = "ActionBars:bar6", x = -921.75, y = 588 },
	{ key = "UnitFrames:player", x = -303, y = -208.5 },
	{ key = "UnitFrames:target", x = 303, y = -208.5 },
	{ key = "UnitFrames:focus", x = -282, y = -149.25 },
	{ key = "UnitFrames:targettarget", x = 505.5, y = -236.25 },
	{ key = "UnitFrames:pet", x = 545.25, y = -516 },
	{ key = "UnitFrames:target:cast", x = -14.25, y = 63, point = "BOTTOM", relPoint = "TOP", relative = "UnitFrames:target" },
	{ key = "ResourceBars:pips", x = 0, y = -244.5 },
	{ key = "ResourceBars:cast", x = 1.5, y = -462 },
	{ key = "ResourceBars:primary", x = -6, y = -501 },
	{ key = "ResourceBars:gcd", x = 1.5, y = -494.25 },
	{ key = "GroupFrames:party", x = -395.25, y = 87 },
	{ key = "GroupFrames:raid", x = -476.25, y = 125.25 },
	{ key = "DamageMeters:1", x = 810, y = -206.25 },
	{ key = "DamageMeters:2", x = 809.25, y = -327.75 },
	{ key = "DamageMeters:3", x = 817.5, y = -462 },
	{ key = "Bags:main", x = -66.75, y = 0, point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT" },
	{ key = "Blizzard:EssentialCooldownViewer", x = -774, y = 415.5 },
	{ key = "Blizzard:UtilityCooldownViewer", x = -774.75, y = 392.25 },
	{ key = "Blizzard:BuffIconCooldownViewer", x = -699, y = 214.5 },
	{ key = "Blizzard:BuffBarCooldownViewer", x = -724.5, y = 331.5 },
}

function Soul:BuildDefaultLayout(profile)
	profile.unlock = profile.unlock or {}
	profile.unlock.positions = {}
	profile.unlock.editorAlpha = 0.24
	local positions = profile.unlock.positions
	for i = 1, #SNAPSHOT do
		local spot = SNAPSHOT[i]
		positions[spot.key] = {
			point = spot.point or "CENTER",
			relPoint = spot.relPoint or "CENTER",
			relative = spot.relative,
			x = spot.x,
			y = spot.y,
		}
	end
	profile._layoutVersion = LAYOUT_VERSION
	profile._layoutSize = { 1920, 1200 }
	profile._partyVertical = true
	profile._singleCast = true
	return true
end

-- Party column: right of the three left-edge bar columns, upper half.
function Soul:DefaultPartySpot(W, H, P, g, col)
	local partyW = Round(1.9 * P)
	local partyH = Round(1.3 * P)
	local columnsRight = -W / 2 + Round(0.2 * P) + 3 * (col + g)
	local partyX = columnsRight + Round(0.5 * P) + partyW / 2
	local stack = partyH * 5 + 1 * 4
	local partyY = H / 2 - Round(4.2 * P) - stack / 2
	return partyX, partyY, partyW, partyH
end

-- 0.4.0: party frames became vertical by default. Profiles that already had
-- the 0.3.0 layout switch once and move the party column next to the bars.
local function PartyVertical(profile)
	if profile._partyVertical then return end
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	if type(W) ~= "number" or W < 400 then return end
	profile._partyVertical = true
	local g = Soul.Pixel:Scale(1)
	local B = math.floor(H * 0.0335 + 0.5)
	if B < 34 then B = 34 elseif B > 50 then B = 50 end
	local P = B + g
	local col = Round(0.77 * P)
	local x, y, w, h = Soul:DefaultPartySpot(W, H, P, g, col)
	profile.modules = profile.modules or {}
	local group = Section(profile.modules, "GroupFrames")
	local party = Section(group, "party")
	party.orientation = "vertical"
	party.width, party.height = w, h
	party.x, party.y = Soul.Pixel:Scale(x), Soul.Pixel:Scale(y)
	profile.unlock = profile.unlock or {}
	profile.unlock.positions = profile.unlock.positions or {}
	Pos(profile.unlock.positions, "GroupFrames:party", x, y)
end

-- 0.5.0: the player cast bar is the Resources one at the bottom. Profiles that
-- also had the player (or pet) unit-frame cast bar on turn it off once; it can
-- be turned back on from edit mode or the Unit Frames page.
local function SingleCast(profile)
	if profile._singleCast then return end
	profile._singleCast = true
	local units = profile.modules and profile.modules.UnitFrames and profile.modules.UnitFrames.units
	if type(units) ~= "table" then return end
	if type(units.player) == "table" then units.player.showCast = false end
	if type(units.pet) == "table" then units.pet.showCast = false end
end

-- Login: write the default layout once per layout version.
function Soul:ApplyDefaultLayout()
	local profile = self:ActiveProfile()
	if profile._layoutVersion == LAYOUT_VERSION then
		PartyVertical(profile)
		SingleCast(profile)
		return
	end
	if self:BuildDefaultLayout(profile) then
		self:Print("Applied the SoulUI default layout. /soul move to adjust it.")
	end
end

-- Editor button: put every element back on the default layout.
function Soul:ResetLayout()
	if InCombatLockdown() then
		self:Print("Layout reset waits until combat ends.")
		self:RunAfterCombat("layout-reset", function() Soul:ResetLayout() end)
		return
	end
	local profile = self:ActiveProfile()
	profile._layoutVersion = nil
	if self:BuildDefaultLayout(profile) then
		self:Fire("ProfileChanged", self.db.activeProfile)
		self:Print("Layout reset to the SoulUI default.")
	end
end
