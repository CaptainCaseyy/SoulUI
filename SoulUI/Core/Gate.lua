-- First file in the toc. On a client older than 12.1 the rest of the addon
-- returns immediately and never assigns SoulUIDB, so the existing saved file
-- is written back unchanged.
local _, _, _, iface = GetBuildInfo()
iface = tonumber(iface) or 0
SoulUI_Blocked = (iface > 0 and iface < 120100) and true or false

if not SoulUI_Blocked then return end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
	local chat = DEFAULT_CHAT_FRAME
	if chat then
		chat:AddMessage("|cff00edffSoulUI|r  needs WoW 12.1 or newer, so it did not load. Saved settings were left untouched.")
	end
end)
