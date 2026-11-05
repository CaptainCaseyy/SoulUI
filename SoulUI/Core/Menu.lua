if SoulUI_Blocked or not SoulUI then return end

local Soul = SoulUI

local hooked = false

local function OpenFromMenu()
	if GameMenuFrame and GameMenuFrame:IsShown() and HideUIPanel then
		HideUIPanel(GameMenuFrame)
	end
	Soul:OpenOptions()
end

local function ManualButton(frame)
	local button = _G.SoulUIGameMenuButton
	if not button then
		local created, made = pcall(CreateFrame, "Button", "SoulUIGameMenuButton", frame, "GameMenuButtonTemplate")
		if created and made then
			button = made
		else
			button = CreateFrame("Button", "SoulUIGameMenuButton", frame)
			button:SetSize(196, 28)
			local face = button:CreateTexture(nil, "BACKGROUND")
			face:SetAllPoints()
			face:SetColorTexture(0.12, 0.12, 0.14, 0.95)
			local label = button:CreateFontString(nil, "OVERLAY")
			Soul:ApplyFont(label, 14, "OUTLINE")
			label:SetPoint("CENTER")
			label:SetText("SoulUI")
			label:SetTextColor(0, 0.93, 1)
			button:SetScript("OnEnter", function() face:SetColorTexture(0, 0.35, 0.4, 1) end)
			button:SetScript("OnLeave", function() face:SetColorTexture(0.12, 0.12, 0.14, 0.95) end)
		end
		if button.SetText then button:SetText("SoulUI") end
		button:SetScript("OnClick", OpenFromMenu)
	end
	button:SetParent(UIParent)
	button:SetFrameStrata(frame:GetFrameStrata() or "FULLSCREEN_DIALOG")
	button:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
	local width = (frame:GetWidth() or 220) - 40
	if width < 150 then width = 180 end
	button:SetSize(width, 28)
	button:ClearAllPoints()
	button:SetPoint("TOP", frame, "BOTTOM", 0, -6)
	button:Show()
	if not frame._soulMenuHide then
		frame._soulMenuHide = true
		frame:HookScript("OnHide", function()
			if button then button:Hide() end
		end)
	end
	return button
end

local function AddButton(frame)
	if not frame or frame._soulButton then return end
	if frame.AddButton then
		local ok = pcall(frame.AddButton, frame, "SoulUI", OpenFromMenu)
		if ok then
			frame._soulButton = true
			if frame.Layout then
				pcall(frame.Layout, frame)
			end
			return
		end
	end
	ManualButton(frame)
	frame._soulButton = true
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
				self._soulButton = nil
				AddButton(self)
			end)
		end
		if GameMenuFrame.Layout then
			hooksecurefunc(GameMenuFrame, "Layout", function(self)
				if not self._soulButton then
					AddButton(self)
				end
			end)
		end
		GameMenuFrame:HookScript("OnShow", function(self)
			ManualButton(self)
			self._soulButton = true
		end)
	end
	if GameMenuFrame:IsShown() then
		AddButton(GameMenuFrame)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= "Blizzard_GameMenu" then return end
	InstallMenu()
end)
