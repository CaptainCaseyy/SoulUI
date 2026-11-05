if SoulUI_Blocked then return end

local Soul = SoulUI

local queue = {}
local queued = false
local combat = CreateFrame("Frame")
combat:Hide()
combat:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	queued = false
	local pending = queue
	queue = {}
	for _, fn in pairs(pending) do
		local ok, err = pcall(fn)
		if not ok then
			Soul:Print("after combat:", err)
		end
	end
end)

function Soul:RunAfterCombat(keyOrFn, maybeFn)
	local key, fn
	if type(keyOrFn) == "function" then
		fn = keyOrFn
		key = tostring(fn)
	else
		key, fn = keyOrFn, maybeFn
	end
	if type(fn) ~= "function" then return end
	if not InCombatLockdown() then
		local ok, err = pcall(fn)
		if not ok then Soul:Print(err) end
		return
	end
	queue[key] = fn
	if not queued then
		queued = true
		combat:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
end

local Ticker = {}
Soul.Ticker = Ticker

function Ticker:NewDriver(owner)
	local frame = owner or CreateFrame("Frame")
	local keys, fns, indexOf = {}, {}, {}
	local count = 0
	frame:Hide()
	frame:SetScript("OnUpdate", function()
		local i = 1
		while i <= count do
			local key = keys[i]
			local ok, err = pcall(fns[i])
			if not ok then Soul:Print("ticker:", err) end
			-- A callback that removes itself swap-drops a new key into this slot.
			if keys[i] == key then
				i = i + 1
			end
		end
	end)

	local driver = {}

	function driver:Add(key, fn)
		local at = indexOf[key]
		if at then
			fns[at] = fn
			return
		end
		count = count + 1
		keys[count] = key
		fns[count] = fn
		indexOf[key] = count
		frame:Show()
	end

	function driver:Remove(key)
		local at = indexOf[key]
		if not at then return end
		local last = count
		if at ~= last then
			keys[at] = keys[last]
			fns[at] = fns[last]
			indexOf[keys[at]] = at
		end
		keys[last] = nil
		fns[last] = nil
		indexOf[key] = nil
		count = last - 1
		if count == 0 then
			frame:Hide()
		end
	end

	return driver
end

local spec = CreateFrame("Frame")
spec:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
spec:SetScript("OnEvent", function(_, _, unit)
	if unit ~= "player" or not Soul.loginDone then return end
	Soul:ApplySpecProfile()
end)

local scale = CreateFrame("Frame")
scale:RegisterEvent("UI_SCALE_CHANGED")
scale:SetScript("OnEvent", function()
	if Soul.Pixel then Soul.Pixel:Refresh() end
	Soul:Fire("ThemeChanged")
end)
