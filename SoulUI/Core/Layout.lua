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
local LAYOUT_VERSION = 3

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

function Soul:BuildDefaultLayout(profile)
	local W = UIParent:GetWidth()
	local H = UIParent:GetHeight()
	if type(W) ~= "number" or type(H) ~= "number" or W < 400 or H < 300 then return false end

	profile.unlock = profile.unlock or {}
	profile.unlock.positions = profile.unlock.positions or {}
	local positions = profile.unlock.positions
	local modules = profile.modules or {}
	profile.modules = modules

	local g = Soul.Pixel:Scale(1)
	local B = math.floor(H * 0.0335 + 0.5)
	if B < 34 then B = 34 elseif B > 50 then B = 50 end
	local P = B + g

	-- Action rows.
	local row2Y = -H / 2 + H * 0.206 + B / 2
	local row1Y = row2Y + P
	local rowTop = row1Y + B / 2

	-- Shards and the player/target pair.
	local shardW = 6 * P - g
	local shardH = Round(0.68 * P)
	local base = rowTop + 2 * g
	local shardY = base + shardH / 2
	local barW = Round(4.67 * P)
	local barH = Round(1.41 * P)
	local playerX = -(3 * P + 0.7 * P) - barW / 2
	local playerY = base + barH / 2

	-- Pet and the tiny bar under it.
	local petW = Round(1.9 * P)
	local petH = Round(0.42 * P)
	local petX = -6.15 * P - petW / 2
	local petY = row2Y + B / 2 - petH / 2
	local tiny = math.max(12, math.floor((petW - 5 * g) / 6))
	local tinyH = tiny * 2 + g
	local tinyY = petY - petH / 2 - 2 * g - tinyH / 2

	-- Casts, focus, target of target.
	local castH = Round(0.45 * P)
	local castY = playerY + barH / 2 + 3 * g + castH / 2
	local smallW = Round(2.9 * P)
	local smallH = Round(0.7 * P)
	local smallY = castY + castH / 2 + Round(0.7 * P) + smallH / 2

	-- Left edge columns.
	local col = Round(0.77 * P)
	local leftX = -W / 2 + Round(0.2 * P) + col / 2

	-- Party column right of the left bar columns (vertical by default), raid
	-- top left.
	local partyX, partyY, partyW, partyH = Soul:DefaultPartySpot(W, H, P, g, col)
	local raidW = Round(1.9 * P)
	local raidH = Round(1.0 * P)

	-- Meters on the right edge.
	local meterW = Round(5.6 * P)
	local rowH = math.max(14, Round(0.42 * P))
	local meterRows = 6
	local block = 22 + meterRows * rowH + 8 + Round(0.3 * P)
	local meterX = W / 2 - Round(0.2 * P) - meterW / 2
	local meterTop = Round(1.5 * P)

	local units = Section(Section(modules, "UnitFrames"), "units")
	local function Unit(name, x, y, w, h, extra)
		local cfg = Section(units, name)
		cfg.x, cfg.y, cfg.width, cfg.height = Soul.Pixel:Scale(x), Soul.Pixel:Scale(y), w, h
		if extra then for k, v in pairs(extra) do cfg[k] = v end end
		Pos(positions, "UnitFrames:" .. name, x, y)
	end
	Unit("player", playerX, playerY, barW, barH, { showPower = false, showCast = false })
	Unit("target", -playerX, playerY, barW, barH, { showPower = false, showCast = true, castHeight = castH, castWidth = barW })
	Unit("pet", petX, petY, petW, petH, { showPower = false, showCast = false, namePosition = "above", healthFormat = "none" })
	Unit("focus", playerX - (barW - smallW) / 2, smallY, smallW, smallH, { showPower = false, showCast = true, castHeight = castH, castWidth = smallW })
	Unit("targettarget", -playerX + (barW - smallW) / 2, smallY, smallW, smallH, { showPower = false, showCast = false })
	-- Cast bars hang above their frame through a relative anchor; drop any
	-- stale absolute spot so they follow the frame again.
	positions["UnitFrames:target:cast"] = nil
	positions["UnitFrames:focus:cast"] = nil
	positions["UnitFrames:player:cast"] = nil

	local resources = Section(modules, "ResourceBars")
	local pips = Section(resources, "pips")
	pips.x, pips.y, pips.width, pips.height = 0, Soul.Pixel:Scale(shardY), shardW, shardH
	pips.gap = 2
	pips.colorMode = pips.colorMode or "class"
	Pos(positions, "ResourceBars:pips", 0, shardY)
	local cast = Section(resources, "cast")
	cast.x, cast.y, cast.width, cast.height = Soul.Pixel:Scale(playerX), Soul.Pixel:Scale(castY), barW, castH
	Pos(positions, "ResourceBars:cast", playerX, castY)
	local primary = Section(resources, "primary")
	local primaryY = row2Y - B / 2 - 3 * g - 5
	primary.x, primary.y, primary.width, primary.height = 0, Soul.Pixel:Scale(primaryY), shardW, 10
	Pos(positions, "ResourceBars:primary", 0, primaryY)
	local gcd = Section(resources, "gcd")
	local gcdY = row2Y - B / 2 - 2 * g - 2
	gcd.x, gcd.y, gcd.width, gcd.height = 0, Soul.Pixel:Scale(gcdY), 12 * P - g, 3
	Pos(positions, "ResourceBars:gcd", 0, gcdY)
	resources.showPips = true
	resources.showCast = true

	local bars = Section(Section(modules, "ActionBars"), "bars")
	local function Bar(key, x, y, settings)
		local cfg = Section(bars, key)
		for k, v in pairs(settings) do cfg[k] = v end
		cfg.x, cfg.y = Soul.Pixel:Scale(x), Soul.Pixel:Scale(y)
		Pos(positions, "ActionBars:" .. key, x, y)
	end
	Bar("main", 0, row1Y, { enabled = true, size = B, spacing = 1, buttons = 12, rows = 1, vertical = false, fade = false })
	Bar("bar2", 0, row2Y, { enabled = true, size = B, spacing = 1, buttons = 12, rows = 1, vertical = false, fade = false })
	local colY = Round(0.7 * P)
	Bar("bar3", leftX, colY, { enabled = true, size = col, spacing = 1, buttons = 12, rows = 1, vertical = true, fade = false })
	Bar("bar4", leftX + col + g, colY, { enabled = true, size = col, spacing = 1, buttons = 12, rows = 1, vertical = true, fade = false })
	Bar("bar5", leftX + 2 * (col + g), colY, { enabled = true, size = col, spacing = 1, buttons = 12, rows = 1, vertical = true, fade = false })
	Bar("bar6", petX - petW / 2 + (6 * tiny + 5 * g) / 2, tinyY, { enabled = true, size = tiny, spacing = 1, buttons = 12, rows = 2, vertical = false, fade = false })

	local group = Section(modules, "GroupFrames")
	local party = Section(group, "party")
	party.width, party.height, party.spacing, party.showPower = partyW, partyH, 2, false
	party.orientation = "vertical"
	party.x, party.y = Soul.Pixel:Scale(partyX), Soul.Pixel:Scale(partyY)
	Pos(positions, "GroupFrames:party", partyX, partyY)
	profile._partyVertical = true
	local raid = Section(group, "raid")
	raid.width, raid.height, raid.spacing, raid.showPower = raidW, raidH, 1, false
	local raidX = -W / 2 + Round(0.6 * P) + (raidW * 5 + g * 4) / 2
	local raidY = H / 2 - Round(2.65 * P) - (raidH * 8 + g * 7) / 2
	raid.x, raid.y = Soul.Pixel:Scale(raidX), Soul.Pixel:Scale(raidY)
	Pos(positions, "GroupFrames:raid", raidX, raidY)

	local meters = Section(modules, "DamageMeters")
	meters.width, meters.rows, meters.rowHeight = meterW, meterRows, rowH
	local windows = Section(meters, "windows")
	for i = 1, 3 do
		local window = Section(windows, i)
		local frameH = 22 + meterRows * rowH + 8
		local y = meterTop - (i - 1) * block - frameH / 2
		window.x, window.y = Soul.Pixel:Scale(meterX), Soul.Pixel:Scale(y)
		Pos(positions, "DamageMeters:" .. i, meterX, y)
	end

	profile._layoutVersion = LAYOUT_VERSION
	profile._layoutSize = { W, H }
	return true
end

-- Party column: right of the three left-edge bar columns, upper half.
function Soul:DefaultPartySpot(W, H, P, g, col)
	local partyW = Round(1.9 * P)
	local partyH = Round(1.3 * P)
	local columnsRight = -W / 2 + Round(0.2 * P) + 3 * (col + g)
	local partyX = columnsRight + Round(0.5 * P) + partyW / 2
	local stack = partyH * 5 + 2 * 4
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

-- Login: write the default layout once per layout version.
function Soul:ApplyDefaultLayout()
	local profile = self:ActiveProfile()
	if profile._layoutVersion == LAYOUT_VERSION then
		PartyVertical(profile)
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
