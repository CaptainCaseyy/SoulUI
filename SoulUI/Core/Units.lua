if SoulUI_Blocked then return end

local Soul = SoulUI

local REACTION = {
	{ 0.85, 0.15, 0.15 },
	{ 0.85, 0.15, 0.15 },
	{ 0.90, 0.45, 0.10 },
	{ 0.85, 0.80, 0.20 },
	{ 0.20, 0.70, 0.25 },
	{ 0.20, 0.70, 0.25 },
	{ 0.20, 0.70, 0.25 },
	{ 0.20, 0.55, 0.85 },
}

local POWER = {
	[0] = { 0.15, 0.45, 0.95 },
	[1] = { 0.85, 0.15, 0.15 },
	[2] = { 0.90, 0.45, 0.15 },
	[3] = { 0.95, 0.85, 0.20 },
	[4] = { 0.95, 0.85, 0.20 },
	[6] = { 0.20, 0.70, 0.85 },
	[8] = { 0.30, 0.52, 0.90 },
	[9] = { 0.95, 0.90, 0.30 },
	[11] = { 0.00, 0.50, 1.00 },
	[12] = { 0.20, 0.85, 0.45 },
	[13] = { 0.55, 0.25, 0.85 },
	[16] = { 0.20, 0.55, 0.95 },
	[17] = { 0.80, 0.50, 0.20 },
	[18] = { 0.85, 0.65, 0.15 },
	[19] = { 0.20, 0.80, 0.85 },
}

function Soul:PowerColor(powerType)
	if Soul.Secret.IsSecret(powerType) or type(powerType) ~= "number" then
		return 0.15, 0.45, 0.95
	end
	local color = POWER[powerType]
	if not color then return 0.15, 0.45, 0.95 end
	return color[1], color[2], color[3]
end

function Soul:ColorUnitHealth(bar, unit)
	if not unit then return end
	if UnitIsTapDenied then
		local tapped = UnitIsTapDenied(unit)
		if not Soul.Secret.IsSecret(tapped) and tapped then
			bar:SetStatusBarColor(0.45, 0.45, 0.45)
			return
		end
	end
	local player = UnitIsPlayer(unit)
	if not Soul.Secret.IsSecret(player) and player then
		local _, class = UnitClass(unit)
		if Soul.Secret.IsSecret(class) then
			local color = C_ClassColor and C_ClassColor.GetClassColor(class)
			if color then
				bar:SetStatusBarColor(color:GetRGB())
				return
			end
		elseif type(class) == "string" then
			local color = RAID_CLASS_COLORS[class]
			if color then
				bar:SetStatusBarColor(color.r, color.g, color.b)
				return
			end
		end
	end
	local reaction = UnitReaction(unit, "player")
	if Soul.Secret.IsSecret(reaction) or type(reaction) ~= "number" then
		bar:SetStatusBarColor(0.85, 0.15, 0.15)
		return
	end
	local color = REACTION[reaction] or REACTION[2]
	bar:SetStatusBarColor(color[1], color[2], color[3])
end
