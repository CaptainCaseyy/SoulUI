if SoulUI_Blocked then return end

-- BigWigs, LittleWigs and RaiderIO keep their own frames, bars and tooltips.
-- SoulUI does not skin them, move them, or park them. Unit tooltips go through
-- the normal GameTooltip:SetUnit path so RaiderIO can add its score.

local Soul = SoulUI

local FOREIGN = { "BigWigs", "LittleWigs", "RaiderIO" }

function Soul:IsForeignFrame(frame)
	local name = frame and frame.GetName and frame:GetName()
	if type(name) ~= "string" then return false end
	for i = 1, #FOREIGN do
		local prefix = FOREIGN[i]
		if name:sub(1, #prefix) == prefix then return true end
	end
	return false
end

local function TooltipHovered()
	if GameTooltip and GameTooltip:IsShown() and GameTooltip:IsMouseOver() then return true end
	local extra = _G.RaiderIO_ProfileTooltip
	if extra and extra.IsShown and extra:IsShown() and extra:IsMouseOver() then return true end
	return false
end

function Soul:ShowUnitTooltip(owner, unit)
	if not owner or not unit or not GameTooltip or not GameTooltip_SetDefaultAnchor then return end
	if not UnitExists(unit) then return end
	GameTooltip_SetDefaultAnchor(GameTooltip, owner)
	GameTooltip:SetUnit(unit)
	GameTooltip:Show()
end

-- Wait a moment so the cursor can move onto the tooltip or RaiderIO's panel.
function Soul:HideUnitTooltip(owner)
	if not owner or not GameTooltip or not GameTooltip:IsOwned(owner) then return end
	C_Timer.After(0.15, function()
		if not GameTooltip:IsOwned(owner) then return end
		if owner:IsMouseOver() or TooltipHovered() then return end
		GameTooltip:Hide()
	end)
end
