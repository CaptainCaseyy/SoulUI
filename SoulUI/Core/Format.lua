if SoulUI_Blocked then return end

local Soul = SoulUI

function Soul:Abbrev(value)
	-- Health is always secret, even in a city. type() and tostring() are the
	-- wrong test; AbbreviateNumbers is allowed to format a secret number.
	if self.Secret.IsSecret(value) then
		if AbbreviateNumbers then return AbbreviateNumbers(value) end
		return ""
	end
	if value == nil then return "" end
	if AbbreviateNumbers then return AbbreviateNumbers(value) end
	return tostring(value)
end
