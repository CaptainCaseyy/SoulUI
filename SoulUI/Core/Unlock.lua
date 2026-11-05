if SoulUI_Blocked then return end

-- Edit mode (/soul move). Every registered element gets a mover overlay.
--
--   drag            move (snaps to other elements, the screen center and the grid)
--   shift + drag    lock to the axis you started moving along
--   mouse wheel     resize by one pixel step (elements that support resizing)
--   arrow keys      nudge the selected element 1 px (shift: 10 px)
--   right-click     open that element's settings page
--
-- Positions are { point, relPoint, relative, x, y } in UIParent units, saved in
-- profile.unlock.positions[key]. Edits write into the profile live; Cancel
-- restores the snapshot taken when edit mode opened (positions and module
-- settings, since resizing writes module settings).
--
-- Element contract (Soul:RegisterMover):
--   key, label, getFrame()            required
--   fallback() -> pos                 position when nothing is saved
--   onResize(w, h)                    write the new size into module settings
--   getColor() / setColor(r, g, b)    optional main color
--   onEdit(on)                        edit mode opened / closed (previews)
--   isHidden() -> bool                skip the mover entirely (not applicable)
--   getEnabled() / setEnabled(on)     shown / hidden switch (module setting). A hidden
--                                     element keeps a dim "ghost" mover so it can be
--                                     shown again from edit mode.
--   onReset()                         after Reset Position (elements without a fallback)
--   page                              settings page key (defaults by module)

local Soul = SoulUI
local UI = Soul.UI

Soul._movers = {}
Soul._moverFrames = {}
Soul.unlocking = false

local PAGE_BY_MODULE = {
	UnitFrames = "unitframes",
	ActionBars = "actionbars",
	ResourceBars = "resources",
	GroupFrames = "groupframes",
	DamageMeters = "meters",
	Nameplates = "nameplates",
	Blizzard = "general",
}

local POINT_LABEL = {
	CENTER = "Center", TOP = "Top", BOTTOM = "Bottom", LEFT = "Left", RIGHT = "Right",
	TOPLEFT = "Top left", TOPRIGHT = "Top right", BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right",
}

local SNAP = 6

local selected
local overlay, toolbar, inspector, keys
local session

local function Settings()
	local account = Soul.db and Soul.db.account
	if not account then return { grid = true, snap = true, gridSize = 32, shade = 0.35, ghosts = true } end
	if type(account.edit) ~= "table" then account.edit = {} end
	local edit = account.edit
	if edit.grid == nil then edit.grid = true end
	if edit.snap == nil then edit.snap = true end
	if type(edit.gridSize) ~= "number" then edit.gridSize = 32 end
	if type(edit.shade) ~= "number" then edit.shade = 0.35 end
	if edit.ghosts == nil then edit.ghosts = true end
	return edit
end

function Soul:RegisterMover(element)
	self._movers[element.key] = element
	if self.unlocking and not InCombatLockdown() then
		self:ShowMover(element.key)
	end
end

local SavedPos

-- True when following key's anchor chain (saved position or fallback) reaches
-- target. Anchoring target to such a key would be a loop SetPoint rejects.
local function DependsOn(key, target)
	local seen = {}
	while key and not seen[key] do
		if key == target then return true end
		seen[key] = true
		local element = Soul._movers[key]
		local pos = element and SavedPos(element)
		key = pos and pos.relative
	end
	return false
end

local function RelativeFrame(pos, frame, ownKey)
	if pos and pos.relative and ownKey and DependsOn(pos.relative, ownKey) then
		return UIParent
	end
	if pos and pos.relative and Soul._movers[pos.relative] then
		local getter = Soul._movers[pos.relative].getFrame
		local other = getter and getter()
		if other and other ~= frame then return other end
	end
	return UIParent
end

function Soul:Place(frame, key, fallback)
	local saved = self:GetUnlockPosition(key)
	local pos = saved or fallback
	if not pos then return end
	local function apply()
		local relative = RelativeFrame(pos, frame, key)
		-- Offsets are stored in UIParent units; SetPoint reads them in the
		-- frame's own scale (Blizzard frames such as the Cooldown Manager scale).
		local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		if not ratio or ratio <= 0 then ratio = 1 end
		frame:ClearAllPoints()
		frame:SetPoint(pos.point or "CENTER", relative, pos.relPoint or "CENTER", (pos.x or 0) / ratio, (pos.y or 0) / ratio)
	end
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
		self:RunAfterCombat("place:" .. key, apply)
	else
		apply()
	end
end

local function Cursor()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	if not scale or scale == 0 then scale = 1 end
	return x / scale, y / scale
end

-- Rect of a frame in UIParent units, whatever its own scale is.
local function RectOf(frame)
	local left, bottom, width, height = frame:GetRect()
	if not left or not width then return nil end
	local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return left * ratio, bottom * ratio, width * ratio, height * ratio
end

local function PointOn(frame, point)
	local left, bottom, width, height = RectOf(frame)
	if not left then return 0, 0 end
	local cx, cy = left + width / 2, bottom + height / 2
	if point == "TOP" then return cx, bottom + height end
	if point == "BOTTOM" then return cx, bottom end
	if point == "LEFT" then return left, cy end
	if point == "RIGHT" then return left + width, cy end
	if point == "TOPLEFT" then return left, bottom + height end
	if point == "TOPRIGHT" then return left + width, bottom + height end
	if point == "BOTTOMLEFT" then return left, bottom end
	if point == "BOTTOMRIGHT" then return left + width, bottom end
	return cx, cy
end

SavedPos = function(element)
	local saved = element and Soul:GetUnlockPosition(element.key)
	if type(saved) == "table" then return saved end
	local fallback = element and element.fallback and element.fallback()
	if type(fallback) == "table" then return Soul:Copy(fallback) end
	return { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
end

local function FrameOf(element)
	return element and element.getFrame and element.getFrame()
end

-- false when the element's own setting hides it (ghost mover).
local function IsOn(element)
	if not element or not element.getEnabled then return true end
	local ok, on = pcall(element.getEnabled)
	if not ok then return true end
	return on and true or false
end

-- Mover box: the frame's rect, or a fixed tag when a hidden frame has no size.
local function FitMover(mover, frame)
	mover:ClearAllPoints()
	if frame:GetNumPoints() == 0 then
		-- Never placed (disabled since login): put the tag at its saved spot.
		local element = mover.element
		local pos = SavedPos(element)
		mover:SetPoint(pos.point or "CENTER", RelativeFrame(pos, frame, element and element.key), pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
		mover:SetSize(150, 26)
		return
	end
	local w, h = frame:GetWidth(), frame:GetHeight()
	if (w or 0) < 4 or (h or 0) < 4 then
		mover:SetPoint("CENTER", frame, "CENTER")
		mover:SetSize(150, 26)
	else
		mover:SetAllPoints(frame)
	end
end

-- Rewrites pos.x / pos.y from where the frame sits now, keeping its anchor.
local function Capture(frame, pos, ownKey)
	local rel = RelativeFrame(pos, frame, ownKey)
	local fx, fy = PointOn(frame, pos.point or "CENTER")
	local rx, ry = PointOn(rel, pos.relPoint or "CENTER")
	pos.x = Soul.Pixel:Scale(fx - rx)
	pos.y = Soul.Pixel:Scale(fy - ry)
	return pos
end

local function Store(element, pos)
	Soul:ActiveProfile().unlock.positions[element.key] = pos
	if session then session.dirty = true end
	local frame = FrameOf(element)
	if frame then Soul:Place(frame, element.key, pos) end
end

local function Rehome(element)
	local frame = FrameOf(element)
	if not frame then return end
	local previous = SavedPos(element)
	local pos = {
		point = previous.point or "CENTER",
		relPoint = previous.relPoint or "CENTER",
		relative = previous.relative,
	}
	Capture(frame, pos, element.key)
	Store(element, pos)
end

local function ModuleOf(key)
	return key and key:match("^([^:]+)")
end

------------------------------------------------------------------------------
-- Overlay, grid and guides
------------------------------------------------------------------------------

local gridLines = {}

local function EnsureOverlay()
	if overlay then return overlay end
	overlay = CreateFrame("Frame", "SoulUI_EditOverlay", UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("BACKGROUND")
	overlay:SetFrameLevel(0)
	overlay:EnableMouse(false)
	overlay:Hide()
	overlay.shade = overlay:CreateTexture(nil, "BACKGROUND")
	overlay.shade:SetAllPoints()
	overlay.grid = CreateFrame("Frame", nil, overlay)
	overlay.grid:SetAllPoints()

	local guides = CreateFrame("Frame", nil, UIParent)
	guides:SetAllPoints(UIParent)
	guides:SetFrameStrata("FULLSCREEN_DIALOG")
	guides:SetFrameLevel(400)
	guides:EnableMouse(false)
	overlay.guides = guides
	local function Guide()
		local t = guides:CreateTexture(nil, "OVERLAY")
		t:Hide()
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
		return t
	end
	overlay.guideX = Guide()
	overlay.guideY = Guide()
	return overlay
end

local function DrawGrid()
	local edit = Settings()
	local frame = EnsureOverlay()
	frame.shade:SetColorTexture(0, 0, 0, edit.shade or 0.35)
	for i = 1, #gridLines do gridLines[i]:Hide() end
	if not edit.grid then return end
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local step = edit.gridSize or 32
	if step < 8 then step = 8 end
	local thin = Soul.Pixel.mult or 1
	local r, g, b = Soul:Accent()
	local used = 0
	local function Line(vertical, offset, strong)
		used = used + 1
		local t = gridLines[used]
		if not t then
			t = frame.grid:CreateTexture(nil, "ARTWORK")
			if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
			gridLines[used] = t
		end
		t:ClearAllPoints()
		if vertical then
			t:SetPoint("TOP", frame.grid, "TOP", offset, 0)
			t:SetPoint("BOTTOM", frame.grid, "BOTTOM", offset, 0)
			t:SetWidth(strong and thin * 2 or thin)
		else
			t:SetPoint("LEFT", frame.grid, "LEFT", 0, offset)
			t:SetPoint("RIGHT", frame.grid, "RIGHT", 0, offset)
			t:SetHeight(strong and thin * 2 or thin)
		end
		if strong then
			t:SetColorTexture(r, g, b, 0.55)
		else
			t:SetColorTexture(1, 1, 1, 0.07)
		end
		t:Show()
	end
	local n = math.floor(W / 2 / step)
	for i = -n, n do Line(true, i * step, i == 0) end
	n = math.floor(H / 2 / step)
	for i = -n, n do Line(false, i * step, i == 0) end
end

local function ShowGuides(gx, gy)
	local frame = EnsureOverlay()
	local thin = (Soul.Pixel.mult or 1) * 2
	local r, g, b = Soul:Accent()
	if gx then
		frame.guideX:ClearAllPoints()
		frame.guideX:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", gx - thin / 2, UIParent:GetHeight())
		frame.guideX:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", gx - thin / 2, 0)
		frame.guideX:SetWidth(thin)
		frame.guideX:SetColorTexture(r, g, b, 0.9)
		frame.guideX:Show()
	else
		frame.guideX:Hide()
	end
	if gy then
		frame.guideY:ClearAllPoints()
		frame.guideY:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, gy - thin / 2)
		frame.guideY:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", UIParent:GetWidth(), gy - thin / 2)
		frame.guideY:SetHeight(thin)
		frame.guideY:SetColorTexture(r, g, b, 0.9)
		frame.guideY:Show()
	else
		frame.guideY:Hide()
	end
end

-- Snaps a dragged rect (center cx, cy and half sizes) to the screen center,
-- the screen edges, other movers' edges and centers, then to the grid.
local function Snap(dragging, cx, cy, hw, hh)
	local edit = Settings()
	if not edit.snap or IsAltKeyDown() then return cx, cy, nil, nil end
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local xs = { W / 2, 0, W }
	local ys = { H / 2, 0, H }
	local dragKey = dragging.element and dragging.element.key
	for key, mover in pairs(Soul._moverFrames) do
		local saved = mover.element and SavedPos(mover.element)
		local child = saved and dragKey and DependsOn(saved.relative, dragKey)
		if mover ~= dragging and mover:IsShown() and not child then
			local l, b, w, h = mover:GetRect()
			if l and w then
				xs[#xs + 1] = l
				xs[#xs + 1] = l + w / 2
				xs[#xs + 1] = l + w
				ys[#ys + 1] = b
				ys[#ys + 1] = b + h / 2
				ys[#ys + 1] = b + h
			end
		end
	end
	local function Best(center, half, lines)
		local mine = { center - half, center, center + half }
		local bestD, guide
		for i = 1, 3 do
			for j = 1, #lines do
				local d = lines[j] - mine[i]
				if math.abs(d) < SNAP and (not bestD or math.abs(d) < math.abs(bestD)) then
					bestD, guide = d, lines[j]
				end
			end
		end
		return bestD, guide
	end
	local dx, gx = Best(cx, hw, xs)
	local dy, gy = Best(cy, hh, ys)
	if dx then cx = cx + dx end
	if dy then cy = cy + dy end
	if edit.grid then
		local step = edit.gridSize or 32
		if not dx then
			local left = cx - hw - W / 2
			local snapped = math.floor(left / step + 0.5) * step
			if math.abs(snapped - left) < SNAP then cx = cx + (snapped - left) end
		end
		if not dy then
			local top = cy + hh - H / 2
			local snapped = math.floor(top / step + 0.5) * step
			if math.abs(snapped - top) < SNAP then cy = cy + (snapped - top) end
		end
	end
	return cx, cy, gx, gy
end

------------------------------------------------------------------------------
-- Mover chrome
------------------------------------------------------------------------------

local function PaintMover(mover)
	local r, g, b = Soul:Accent()
	local on = mover == selected
	local hover = mover._hover
	if mover._ghost then
		mover.fill:SetColorTexture(0.1, 0.1, 0.11, on and 0.6 or (hover and 0.5 or 0.35))
		mover.outline:SetColor(0.55, 0.55, 0.6, on and 0.9 or (hover and 0.6 or 0.3))
		mover.label:SetTextColor(on and r or 0.6, on and g or 0.6, on and b or 0.62)
		mover.size:Hide()
		return
	end
	mover.fill:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, on and 0.55 or (hover and 0.45 or 0.32))
	mover.outline:SetColor(r, g, b, on and 1 or (hover and 0.8 or 0.45))
	mover.label:SetTextColor(on and r or 1, on and g or 1, on and b or 1)
	local frame = FrameOf(mover.element)
	if frame and (on or hover) then
		local _, _, w, h = RectOf(frame)
		if w then
			mover.size:SetFormattedText("%d x %d", math.floor(w + 0.5), math.floor(h + 0.5))
			mover.size:Show()
		end
	else
		mover.size:Hide()
	end
end

function Soul:RefreshEditorChrome()
	for _, mover in pairs(self._moverFrames) do
		if mover:IsShown() then PaintMover(mover) end
	end
end

local FillInspector

local function Select(mover)
	local previous = selected
	selected = mover
	if previous and previous ~= mover and previous:IsShown() then PaintMover(previous) end
	if mover then PaintMover(mover) end
	if FillInspector then FillInspector() end
end

local function ApplySize(element, width, height)
	local frame = FrameOf(element)
	if not frame or not element.onResize then return end
	if width < 8 then width = 8 end
	if height < 4 then height = 4 end
	element.onResize(Soul.Pixel:Scale(width), Soul.Pixel:Scale(height))
	if session then session.dirty = true end
	local mover = Soul._moverFrames[element.key]
	if mover then
		FitMover(mover, frame)
		PaintMover(mover)
	end
end

local function StepSize(value, dir)
	local px = Soul.Pixel.mult or 1
	for n = 1, 8 do
		local nextValue = Soul.Pixel:Scale(value + dir * px * n)
		if dir > 0 and nextValue > value + 0.05 then return nextValue end
		if dir < 0 and nextValue < value - 0.05 then return nextValue end
	end
	return Soul.Pixel:Scale(value + dir * px * 4)
end

local function OpenSettingsFor(element)
	local page = element.page or PAGE_BY_MODULE[ModuleOf(element.key) or ""]
	Soul:CommitUnlock(true)
	Soul:OpenOptions(page)
end

local function Nudge(dx, dy)
	if not selected or InCombatLockdown() then return end
	local element = selected.element
	local pos = SavedPos(element)
	local copy = Soul:Copy(pos)
	copy.x = Soul.Pixel:Scale((copy.x or 0) + dx)
	copy.y = Soul.Pixel:Scale((copy.y or 0) + dy)
	Store(element, copy)
	local frame = FrameOf(element)
	if frame then FitMover(selected, frame) end
	FillInspector()
end

local function StartDrag(mover)
	if InCombatLockdown() then return end
	local target = FrameOf(mover.element)
	if not target then return end
	Select(mover)
	local left, bottom, width, height = RectOf(target)
	if not left then return end
	local cx, cy = Cursor()
	mover.grabX = cx - (left + width / 2)
	mover.grabY = cy - (bottom + height / 2)
	mover.startX, mover.startY = cx, cy
	mover.axis = nil
	mover.moved = false
	mover:SetScript("OnUpdate", function(self)
		if not IsMouseButtonDown("LeftButton") or InCombatLockdown() then
			self:SetScript("OnUpdate", nil)
			ShowGuides(nil, nil)
			if self.moved then Rehome(self.element) end
			local live = FrameOf(self.element)
			if live then FitMover(self, live) end
			FillInspector()
			return
		end
		local frame = FrameOf(self.element)
		if not frame then return end
		local x, y = Cursor()
		if not self.moved then
			if math.abs(x - self.startX) < 3 and math.abs(y - self.startY) < 3 then return end
			self.moved = true
			self.axis = math.abs(x - self.startX) >= math.abs(y - self.startY) and "x" or "y"
		end
		if IsShiftKeyDown() then
			if self.axis == "x" then y = self.startY else x = self.startX end
		end
		local _, _, w, h = RectOf(frame)
		local hw, hh = w / 2, h / 2
		local ncx, ncy, gx, gy = Snap(self, x - self.grabX, y - self.grabY, hw, hh)
		local W, H = UIParent:GetWidth(), UIParent:GetHeight()
		if ncx - hw < 0 then ncx = hw elseif ncx + hw > W then ncx = W - hw end
		if ncy - hh < 0 then ncy = hh elseif ncy + hh > H then ncy = H - hh end
		local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", Soul.Pixel:Scale(ncx) / ratio, Soul.Pixel:Scale(ncy) / ratio)
		FitMover(self, frame)
		ShowGuides(gx, gy)
		if FillInspector and inspector and inspector:IsShown() then inspector.RefreshNumbers() end
	end)
end

function Soul:ShowMover(key)
	local element = self._movers[key]
	if not element then return end
	local frame = FrameOf(element)
	local mover = self._moverFrames[key]
	local ghost = not IsOn(element)
	if not frame or (element.isHidden and element.isHidden()) or (ghost and not Settings().ghosts) then
		if mover then mover:Hide() end
		if mover and mover == selected then Select(nil) end
		return
	end
	if not mover then
		mover = CreateFrame("Button", nil, UIParent)
		mover:SetFrameStrata("FULLSCREEN_DIALOG")
		mover:SetFrameLevel(100)
		mover:EnableMouse(true)
		mover:EnableMouseWheel(true)
		mover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		mover.fill = mover:CreateTexture(nil, "BACKGROUND")
		mover.fill:SetAllPoints()
		mover.outline = UI.Edge(mover, 0, 0.93, 1, 0.45, "OVERLAY")
		mover.label = UI.Text(mover, 12, UI.C.text, "CENTER")
		mover.label:SetPoint("CENTER", 0, 0)
		mover.size = UI.Text(mover, 10, UI.C.dim, "CENTER")
		mover.size:SetPoint("TOP", mover.label, "BOTTOM", 0, -1)
		mover.size:Hide()
		mover:SetScript("OnEnter", function(self) self._hover = true PaintMover(self) end)
		mover:SetScript("OnLeave", function(self) self._hover = false PaintMover(self) end)
		mover:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then StartDrag(self) end
		end)
		mover:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				OpenSettingsFor(self.element)
			elseif not self.moved then
				Select(self)
			end
		end)
		mover:SetScript("OnMouseWheel", function(self, delta)
			if InCombatLockdown() or not self.element.onResize then return end
			local target = FrameOf(self.element)
			if not target then return end
			Select(self)
			local dir = delta > 0 and 1 or -1
			local w, h = target:GetWidth(), target:GetHeight()
			if w < 1 then w = 1 end
			local nw = StepSize(w, dir)
			local nh = Soul.Pixel:Scale(h * (nw / w))
			if dir < 0 and nh >= h - 0.05 then nh = StepSize(h, -1)
			elseif dir > 0 and nh <= h + 0.05 then nh = StepSize(h, 1) end
			ApplySize(self.element, nw, nh)
			FillInspector()
		end)
		self._moverFrames[key] = mover
	end
	mover.element = element
	mover._ghost = ghost
	mover.label:SetText(ghost and ((element.label or key) .. "  (hidden)") or (element.label or key))
	FitMover(mover, frame)
	mover:Show()
	PaintMover(mover)
end

function Soul:HideMovers()
	for _, mover in pairs(self._moverFrames) do
		mover:SetScript("OnUpdate", nil)
		mover:Hide()
	end
	if overlay then
		overlay:Hide()
		ShowGuides(nil, nil)
	end
	if toolbar then toolbar:Hide() end
	if inspector then inspector:Hide() end
	if keys then keys:Hide() end
	UI.CloseMenu()
end

local function ShowAllMovers()
	for key in pairs(Soul._movers) do
		Soul:ShowMover(key)
	end
end

------------------------------------------------------------------------------
-- Toolbar
------------------------------------------------------------------------------

local function Label(parent, text, size)
	local font = UI.Text(parent, size or 12, UI.C.dim)
	font:SetText(text)
	return font
end

local function EnsureToolbar()
	if toolbar then return toolbar end
	toolbar = UI.Window("SoulUI_EditToolbar", "SoulUI  Edit Mode", 980, 92, { strata = "TOOLTIP", noClose = true })
	toolbar:SetFrameLevel(50)

	local hint = UI.Text(toolbar.bar, 11, UI.C.dim, "RIGHT")
	hint:SetPoint("RIGHT", -14, 0)
	hint:SetText("Drag: move   Shift: lock axis   Alt: no snap   Wheel: resize   Arrows: nudge   Right-click: settings")

	local row = CreateFrame("Frame", nil, toolbar)
	row:SetPoint("TOPLEFT", 0, -40)
	row:SetPoint("BOTTOMRIGHT")

	local gridSwitch = UI.Switch(row, function() return Settings().grid end, function(v)
		Settings().grid = v
		DrawGrid()
	end)
	gridSwitch:SetPoint("LEFT", 14, 0)
	local gridLabel = Label(row, "Grid")
	gridLabel:SetPoint("LEFT", gridSwitch, "RIGHT", 8, 0)

	local snapSwitch = UI.Switch(row, function() return Settings().snap end, function(v) Settings().snap = v end)
	snapSwitch:SetPoint("LEFT", gridLabel, "RIGHT", 18, 0)
	local snapLabel = Label(row, "Snap")
	snapLabel:SetPoint("LEFT", snapSwitch, "RIGHT", 8, 0)

	local sizes = {}
	for _, n in ipairs({ 8, 16, 24, 32, 48, 64 }) do sizes[#sizes + 1] = { value = n, label = n .. " px grid" } end
	local gridSize = UI.Dropdown(row, 110, sizes, function() return Settings().gridSize end, function(v)
		Settings().gridSize = v
		DrawGrid()
	end)
	gridSize:SetPoint("LEFT", snapLabel, "RIGHT", 18, 0)

	local shadeLabel = Label(row, "Dim")
	shadeLabel:SetPoint("LEFT", gridSize, "RIGHT", 18, 0)
	local shade = UI.Slider(row, 90, 0, 0.8, 0.05, function() return Settings().shade end, function(v)
		Settings().shade = v
		DrawGrid()
	end)
	shade:SetPoint("LEFT", shadeLabel, "RIGHT", 8, 0)

	local ghostSwitch = UI.Switch(row, function() return Settings().ghosts end, function(v)
		Settings().ghosts = v and true or false
		ShowAllMovers()
		FillInspector()
	end)
	ghostSwitch:SetPoint("LEFT", shade, "RIGHT", 18, 0)
	local ghostLabel = Label(row, "Hidden")
	ghostLabel:SetPoint("LEFT", ghostSwitch, "RIGHT", 8, 0)
	UI.Tip(ghostSwitch, "Hidden elements", "Show dim boxes for elements you have hidden, so you can select them and turn them back on.")

	local save = UI.Button(row, "Save & Exit", 110, 30, function() Soul:CommitUnlock() end, "accent")
	save:SetPoint("RIGHT", -14, 0)
	local cancel = UI.Button(row, "Cancel", 80, 30, function() Soul:CloseUnlock(true) end)
	cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
	local reset = UI.Button(row, "Reset Layout", 110, 30, function()
		Soul:ResetLayout()
		ShowAllMovers()
		FillInspector()
	end, "plain")
	reset:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
	UI.Tip(reset, "Reset Layout", "Puts every element back on the SoulUI default layout. Cancel still undoes it.")
	local settings = UI.Button(row, "Settings", 90, 30, function()
		Soul:CommitUnlock(true)
		Soul:OpenOptions()
	end, "plain")
	settings:SetPoint("RIGHT", reset, "LEFT", -8, 0)

	toolbar.Refresh = function()
		gridSwitch.Refresh()
		snapSwitch.Refresh()
		gridSize.Refresh()
		shade.Refresh()
		ghostSwitch.Refresh()
	end
	return toolbar
end

------------------------------------------------------------------------------
-- Inspector (selected element)
------------------------------------------------------------------------------

local function EnsureInspector()
	if inspector then return inspector end
	inspector = UI.Window("SoulUI_EditInspector", "Element", 300, 500, {
		strata = "TOOLTIP",
		onClose = function() Select(nil) end,
	})
	inspector:SetFrameLevel(60)
	local body = CreateFrame("Frame", nil, inspector)
	body:SetPoint("TOPLEFT", 16, -52)
	body:SetPoint("BOTTOMRIGHT", -16, 14)

	local function Heading(text, y)
		local font = UI.Text(body, 11, UI.C.faint)
		font:SetText(string.upper(text))
		font:SetPoint("TOPLEFT", 0, y)
		return font
	end
	local function Current()
		return selected and selected.element
	end

	Heading("Position", 0)
	local xLabel = Label(body, "X")
	xLabel:SetPoint("TOPLEFT", 0, -22)
	local xBox = UI.NumberBox(body, 80, function()
		local element = Current()
		return element and SavedPos(element).x or 0
	end, function(v)
		local element = Current()
		if not element or InCombatLockdown() then return end
		local pos = Soul:Copy(SavedPos(element))
		pos.x = Soul.Pixel:Scale(v)
		Store(element, pos)
	end)
	xBox:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)
	local yLabel = Label(body, "Y")
	yLabel:SetPoint("LEFT", xBox, "RIGHT", 18, 0)
	local yBox = UI.NumberBox(body, 80, function()
		local element = Current()
		return element and SavedPos(element).y or 0
	end, function(v)
		local element = Current()
		if not element or InCombatLockdown() then return end
		local pos = Soul:Copy(SavedPos(element))
		pos.y = Soul.Pixel:Scale(v)
		Store(element, pos)
	end)
	yBox:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)

	Heading("Size", -62)
	local wLabel = Label(body, "W")
	wLabel:SetPoint("TOPLEFT", 0, -84)
	local function Size(index)
		local frame = FrameOf(Current())
		if not frame then return 0 end
		local _, _, w, h = RectOf(frame)
		if index == 1 then return w or 0 end
		return h or 0
	end
	local wBox = UI.NumberBox(body, 80, function() return Size(1) end, function(v)
		local element = Current()
		if element then ApplySize(element, v, Size(2)) end
	end)
	wBox:SetPoint("LEFT", wLabel, "RIGHT", 8, 0)
	local hLabel = Label(body, "H")
	hLabel:SetPoint("LEFT", wBox, "RIGHT", 18, 0)
	local hBox = UI.NumberBox(body, 80, function() return Size(2) end, function(v)
		local element = Current()
		if element then ApplySize(element, Size(1), v) end
	end)
	hBox:SetPoint("LEFT", hLabel, "RIGHT", 8, 0)

	Heading("Anchor to", -124)
	local function AnchorItems()
		local items = { { value = "", label = "Screen" } }
		local list = {}
		local current = Current()
		for key, element in pairs(Soul._movers) do
			if not current or (key ~= current.key and not DependsOn(key, current.key)) then
				list[#list + 1] = { value = key, label = element.label or key }
			end
		end
		table.sort(list, function(a, b) return a.label < b.label end)
		for i = 1, #list do items[#items + 1] = list[i] end
		return items
	end
	local anchor = UI.Dropdown(body, 268, AnchorItems, function()
		local element = Current()
		return element and SavedPos(element).relative or ""
	end, function(value)
		local element = Current()
		if not element or InCombatLockdown() then return end
		local pos = Soul:Copy(SavedPos(element))
		pos.relative = value ~= "" and value or nil
		if not pos.relative then
			pos.point, pos.relPoint = "CENTER", "CENTER"
		end
		local frame = FrameOf(element)
		if frame then
			Capture(frame, pos, element.key)
			Store(element, pos)
		end
		FillInspector()
	end)
	anchor:SetPoint("TOPLEFT", 0, -144)

	local fromLabel = Label(body, "This point")
	fromLabel:SetPoint("TOPLEFT", 0, -184)
	local toLabel = Label(body, "Target point")
	toLabel:SetPoint("TOPLEFT", 140, -184)
	local function PointSetter(field)
		return function(point)
			local element = Current()
			if not element or InCombatLockdown() then return end
			local pos = Soul:Copy(SavedPos(element))
			pos[field] = point
			local frame = FrameOf(element)
			if frame then
				Capture(frame, pos, element.key)
				Store(element, pos)
			end
			FillInspector()
		end
	end
	local fromPicker = UI.PointPicker(body, 66, function()
		local element = Current()
		return element and SavedPos(element).point or "CENTER"
	end, PointSetter("point"))
	fromPicker:SetPoint("TOPLEFT", 0, -202)
	local toPicker = UI.PointPicker(body, 66, function()
		local element = Current()
		return element and SavedPos(element).relPoint or "CENTER"
	end, PointSetter("relPoint"))
	toPicker:SetPoint("TOPLEFT", 140, -202)
	local fromText = UI.Text(body, 11, UI.C.dim)
	fromText:SetPoint("TOPLEFT", fromPicker, "BOTTOMLEFT", 0, -4)
	local toText = UI.Text(body, 11, UI.C.dim)
	toText:SetPoint("TOPLEFT", toPicker, "BOTTOMLEFT", 0, -4)

	Heading("Nudge", -296)
	local function NudgeButton(text, x, dx, dy)
		local button = UI.Button(body, text, 34, 26, function()
			local step = IsShiftKeyDown() and 10 or 1
			Nudge(dx * step * (Soul.Pixel.mult or 1), dy * step * (Soul.Pixel.mult or 1))
		end)
		button:SetPoint("TOPLEFT", x, -316)
		return button
	end
	NudgeButton("<", 0, -1, 0)
	NudgeButton(">", 38, 1, 0)
	NudgeButton("^", 76, 0, 1)
	NudgeButton("v", 114, 0, -1)
	local colorLabel = Label(body, "Color")
	colorLabel:SetPoint("TOPLEFT", 180, -321)
	local swatch = UI.Swatch(body, function()
		local element = Current()
		if element and element.getColor then return element.getColor() end
		return 0.3, 0.3, 0.3
	end, function(r, g, b)
		local element = Current()
		if element and element.setColor and r then
			element.setColor(r, g, b)
			if session then session.dirty = true end
		end
	end)
	swatch:SetPoint("LEFT", colorLabel, "RIGHT", 8, 0)

	Heading("Visibility", -360)
	local shownSwitch = UI.Switch(body, function()
		return IsOn(Current())
	end, function(v)
		local element = Current()
		if not element or not element.setEnabled or InCombatLockdown() then return end
		element.setEnabled(v and true or false)
		if session then session.dirty = true end
		Soul:ShowMover(element.key)
		FillInspector()
	end)
	shownSwitch:SetPoint("TOPLEFT", 0, -380)
	local shownLabel = Label(body, "Shown")
	shownLabel:SetPoint("LEFT", shownSwitch, "RIGHT", 8, 0)
	local shownNote = UI.Text(body, 11, UI.C.faint)
	shownNote:SetPoint("LEFT", shownLabel, "RIGHT", 12, 0)

	local settingsButton = UI.Button(body, "Element Settings", 130, 30, function()
		local element = Current()
		if element then OpenSettingsFor(element) end
	end)
	settingsButton:SetPoint("BOTTOMLEFT", 0, 0)
	local resetButton = UI.Button(body, "Reset Position", 130, 30, function()
		local element = Current()
		if not element or InCombatLockdown() then return end
		Soul:ActiveProfile().unlock.positions[element.key] = nil
		local fallback = element.fallback and element.fallback()
		local frame = FrameOf(element)
		if frame and fallback then Soul:Place(frame, element.key, fallback) end
		if element.onReset then pcall(element.onReset) end
		if session then session.dirty = true end
		if selected and frame then FitMover(selected, frame) end
		FillInspector()
	end)
	resetButton:SetPoint("BOTTOMRIGHT", 0, 0)

	function inspector.RefreshNumbers()
		xBox.Refresh()
		yBox.Refresh()
		wBox.Refresh()
		hBox.Refresh()
	end

	function inspector.RefreshAll()
		local element = Current()
		if not element then return end
		inspector.title:SetText(element.label or element.key)
		inspector.RefreshNumbers()
		anchor.Refresh()
		fromPicker.Refresh()
		toPicker.Refresh()
		local pos = SavedPos(element)
		fromText:SetText(POINT_LABEL[pos.point or "CENTER"] or "")
		toText:SetText(POINT_LABEL[pos.relPoint or "CENTER"] or "")
		local canSize = element.onResize and true or false
		wBox:SetEnabled(canSize)
		hBox:SetEnabled(canSize)
		swatch:SetDisabled(not element.getColor)
		swatch.Refresh()
		shownSwitch:SetDisabled(not element.setEnabled)
		shownSwitch.Refresh()
		shownNote:SetText(element.setEnabled and "" or "always shown")
	end
	return inspector
end

FillInspector = function()
	if not inspector then return end
	if not selected or not selected.element or not Soul.unlocking then
		inspector:Hide()
		return
	end
	if not inspector:IsShown() then
		inspector:RestorePosition("TOPRIGHT", -60, -160)
		inspector:Show()
	end
	inspector.RefreshAll()
end

------------------------------------------------------------------------------
-- Keyboard nudge
------------------------------------------------------------------------------

local function EnsureKeys()
	if keys then return keys end
	keys = CreateFrame("Frame", nil, UIParent)
	keys:EnableKeyboard(true)
	keys:SetPropagateKeyboardInput(true)
	keys:Hide()
	keys:SetScript("OnKeyDown", function(self, key)
		local step = (IsShiftKeyDown() and 10 or 1) * (Soul.Pixel.mult or 1)
		local consumed = true
		if not selected or InCombatLockdown() then
			consumed = false
		elseif key == "LEFT" then Nudge(-step, 0)
		elseif key == "RIGHT" then Nudge(step, 0)
		elseif key == "UP" then Nudge(0, step)
		elseif key == "DOWN" then Nudge(0, -step)
		elseif key == "ESCAPE" then Select(nil)
		else consumed = false end
		if not InCombatLockdown() then
			self:SetPropagateKeyboardInput(not consumed)
		end
	end)
	return keys
end

------------------------------------------------------------------------------
-- Session
------------------------------------------------------------------------------

local function ShowSession()
	EnsureOverlay():Show()
	DrawGrid()
	local bar = EnsureToolbar()
	bar:RestorePosition("TOP", 0, -30)
	bar.Refresh()
	bar:Show()
	EnsureInspector()
	EnsureKeys():Show()
	for _, element in pairs(Soul._movers) do
		if element.onEdit then pcall(element.onEdit, true) end
	end
	ShowAllMovers()
	FillInspector()
end

function Soul:CommitUnlock(quiet)
	session = nil
	self:CloseUnlock(false)
	if not quiet then self:Print("Layout saved to this profile.") end
end

function Soul:CloseUnlock(revert)
	if not self.unlocking then return end
	self.unlocking = false
	if revert and session then
		local profile = self:ActiveProfile()
		profile.unlock.positions = session.positions
		if session.modules then
			for key, data in pairs(session.modules) do
				profile.modules[key] = data
			end
		end
		profile._layoutVersion = session.layoutVersion
		profile.blizzard = session.blizzard
	end
	local reverted = revert and session and session.dirty
	session = nil
	selected = nil
	for _, element in pairs(self._movers) do
		if element.onEdit then pcall(element.onEdit, false) end
	end
	self:HideMovers()
	if reverted then
		self:Fire("ProfileChanged", self.db.activeProfile)
		self:Print("Edit mode cancelled. Changes were undone.")
	end
end

function Soul:OpenUnlock()
	if InCombatLockdown() then
		self:Print("Edit mode is unavailable during combat.")
		return
	end
	if self.unlocking then return end
	self:CloseOptions()
	self.unlocking = true
	local profile = self:ActiveProfile()
	session = {
		positions = self:Copy(profile.unlock.positions),
		modules = self:Copy(profile.modules),
		layoutVersion = profile._layoutVersion,
		blizzard = self:Copy(profile.blizzard),
		dirty = false,
	}
	ShowSession()
end

function Soul:ToggleUnlock()
	if self.unlocking then
		self:CommitUnlock()
	else
		self:OpenUnlock()
	end
end

local resume = CreateFrame("Frame")
resume:RegisterEvent("PLAYER_REGEN_DISABLED")
resume:RegisterEvent("PLAYER_REGEN_ENABLED")
resume:SetScript("OnEvent", function(_, event)
	if not Soul.unlocking then return end
	if event == "PLAYER_REGEN_DISABLED" then
		for _, element in pairs(Soul._movers) do
			if element.onEdit then pcall(element.onEdit, false) end
		end
		Soul:HideMovers()
		Soul:Print("Edit mode paused for combat.")
	else
		C_Timer.After(0.5, function()
			if Soul.unlocking and not InCombatLockdown() then
				ShowSession()
			end
		end)
	end
end)
