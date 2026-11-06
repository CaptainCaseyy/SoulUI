if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI

-- Escape opens GameMenuFrame. SoulUI used to hang its own button under that
-- frame, so it sat in the gap below the menu and did not line up with the
-- other rows. The button is now the last row inside the menu, and the menu
-- grows to cover it.

local hooked = false
local pending = false

local function OpenFromMenu()
	if GameMenuFrame and GameMenuFrame:IsShown() and HideUIPanel then
		HideUIPanel(GameMenuFrame)
	end
	Soul:OpenOptions()
end

local function EnsureButton(menu)
	local button = _G.SoulUIGameMenuButton
	if not button then
		local created, made = pcall(CreateFrame, "Button", "SoulUIGameMenuButton", menu, "GameMenuButtonTemplate")
		if created and made then
			button = made
		else
			button = CreateFrame("Button", "SoulUIGameMenuButton", menu)
			local face = button:CreateTexture(nil, "BACKGROUND")
			face:SetAllPoints()
			face:SetColorTexture(0, 0, 0, 0.25)
			local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			label:SetPoint("CENTER")
			label:SetText("SoulUI")
			button:SetScript("OnEnter", function() face:SetColorTexture(1, 1, 1, 0.08) end)
			button:SetScript("OnLeave", function() face:SetColorTexture(0, 0, 0, 0.25) end)
		end
		if button.SetText then button:SetText("SoulUI") end
		button:SetScript("OnClick", OpenFromMenu)
	end
	if button:GetParent() ~= menu then
		button:SetParent(menu)
	end
	return button
end

-- The lowest wide button is the bottom row of the menu. The close box is
-- small and is ignored so SoulUI does not hang off that.
local function LowestRow(menu, ignore)
	local lowest, bottom
	local children = { menu:GetChildren() }
	for i = 1, #children do
		local child = children[i]
		if child ~= ignore and child.IsShown and child:IsShown() and child.GetObjectType and child:GetObjectType() == "Button" then
			local width = child.GetWidth and child:GetWidth() or 0
			local childBottom = child.GetBottom and child:GetBottom()
			if width > 100 and childBottom and (not bottom or childBottom < bottom) then
				lowest = child
				bottom = childBottom
			end
		end
	end
	return lowest
end

local function PlaceInMenu(menu)
	if not menu or menu._soulPlacing then return end
	menu._soulPlacing = true
	local button = EnsureButton(menu)
	local anchor = LowestRow(menu, button)
	local width = (menu:GetWidth() or 230) - 46
	local height = 28
	if anchor then
		local anchorWidth = anchor:GetWidth()
		local anchorHeight = anchor:GetHeight()
		if anchorWidth and anchorWidth > 40 then width = anchorWidth end
		if anchorHeight and anchorHeight > 16 then height = anchorHeight end
	end
	if width < 140 then width = 140 end
	button:SetSize(width, height)
	button:ClearAllPoints()
	if anchor then
		button:SetPoint("TOP", anchor, "BOTTOM", 0, -1)
	else
		button:SetPoint("BOTTOM", menu, "BOTTOM", 0, 18)
	end
	button:Show()
	-- Grow only by however much of the button is still outside the menu,
	-- so a second layout pass does not keep stretching it.
	local menuBottom = menu:GetBottom()
	local buttonBottom = button:GetBottom()
	if menuBottom and buttonBottom and buttonBottom < menuBottom + 10 then
		menu:SetHeight((menu:GetHeight() or 0) + (menuBottom + 10 - buttonBottom) + 8)
	end
	menu._soulPlacing = false
end

local function Schedule(menu)
	if not menu or menu._soulPlacing or pending then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		if menu:IsShown() then
			PlaceInMenu(menu)
		else
			local button = _G.SoulUIGameMenuButton
			if button then button:Hide() end
		end
	end)
end

local function InstallMenu()
	if Menu and Menu.ModifyMenu then
		local tags = { "MENU_GAME_MENU", "MENU_MAINMENU", "MENU_GAME" }
		for i = 1, #tags do
			pcall(Menu.ModifyMenu, tags[i], function(owner, root)
				local description = root or owner
				if not description or not description.CreateButton then return end
				if description.CreateDivider then
					description:CreateDivider()
				end
				description:CreateButton("SoulUI", OpenFromMenu)
			end)
		end
	end
	if not GameMenuFrame then return end
	if not hooked then
		hooked = true
		if GameMenuFrameMixin and GameMenuFrameMixin.InitButtons then
			hooksecurefunc(GameMenuFrameMixin, "InitButtons", function(self)
				Schedule(self)
			end)
		end
		if GameMenuFrame.Layout then
			hooksecurefunc(GameMenuFrame, "Layout", function(self)
				Schedule(self)
			end)
		end
		GameMenuFrame:HookScript("OnShow", function(self)
			Schedule(self)
		end)
		GameMenuFrame:HookScript("OnHide", function()
			local button = _G.SoulUIGameMenuButton
			if button then button:Hide() end
		end)
	end
	if GameMenuFrame:IsShown() then
		Schedule(GameMenuFrame)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= "Blizzard_GameMenu" then return end
	InstallMenu()
end)
