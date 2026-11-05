if SoulUI_Blocked then return end

local Soul = SoulUI
local Secret = {}
Soul.Secret = Secret

function Secret.IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- True when an API handed back a real result. A call that returns nothing
-- becomes nil here; type() on that call throws "value expected, got no value".
function Secret.Present(value)
	if issecretvalue and issecretvalue(value) then return true end
	return value ~= nil
end

-- Nil when the value is missing or secret, so the caller can skip a memo
-- comparison. Never use the result as proof that a unit has no health.
function Secret.Plain(value)
	if Secret.IsSecret(value) then return nil end
	return value
end

function Secret.AlphaFromBool(region, flag, alphaTrue, alphaFalse)
	if alphaTrue == nil then alphaTrue = 1 end
	if alphaFalse == nil then alphaFalse = 0 end
	if type(flag) == "nil" then
		region:SetAlpha(alphaFalse)
		return
	end
	if Secret.IsSecret(flag) then
		if region.SetAlphaFromBoolean then
			region:SetAlphaFromBoolean(flag, alphaTrue, alphaFalse)
		end
		return
	end
	if flag then
		region:SetAlpha(alphaTrue)
	else
		region:SetAlpha(alphaFalse)
	end
end

-- 12.1 field reports put the "false" result in the second argument and the
-- "true" result in the third. If a test shows the colors swapped, swap the
-- call sites rather than this helper.
function Secret.PickColor(flag, ifFalse, ifTrue)
	if type(flag) == "nil" then return ifFalse end
	if Secret.IsSecret(flag) and C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean then
		return C_CurveUtil.EvaluateColorFromBoolean(flag, ifFalse, ifTrue)
	end
	if Secret.IsSecret(flag) then return ifFalse end
	if flag then return ifTrue end
	return ifFalse
end
