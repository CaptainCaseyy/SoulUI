if SoulUI_Blocked or not SoulUI then return end

-- Vendors: auto repair (guild funds first), sell gray items, Train All.

local Soul = SoulUI
local Q = Soul:GetModule("QoL")
if not Q then return end

local DB = Q.DB
local C_Container, C_Item, C_Timer = C_Container, C_Item, C_Timer
local GetMoney, select, type = GetMoney, select, type

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or ((NUM_BAG_SLOTS or 4) + 1)

------------------------------------------------------------------------------
-- Auto repair
------------------------------------------------------------------------------

local repairOpen = false

local function PersonalRepair(cost)
	if GetMoney() < cost then
		Soul:Print("Not enough gold to repair (" .. Q.Money(cost) .. " needed).")
		return
	end
	RepairAllItems(false)
	Soul:Print("Repaired for " .. Q.Money(cost) .. ".")
end

local function GuildCanCover(cost)
	if not (DB().repairGuild and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()) then
		return false
	end
	-- Withdraw limit: -1 (or a huge number) means unlimited.
	local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
	if type(limit) == "number" and limit >= 0 and limit < cost then return false end
	-- The bank balance reads 0 until the guild bank has been seen this
	-- session, so 0 means "unknown" and the repair is tried anyway.
	local bank = GetGuildBankMoney and GetGuildBankMoney()
	if type(bank) == "number" and bank > 0 and bank < cost then return false end
	return true
end

local function TryRepair()
	if not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or type(cost) ~= "number" or cost <= 0 then return end
	if GuildCanCover(cost) then
		RepairAllItems(true)
		-- If the guild bank refused (empty bank), pay from our own gold.
		C_Timer.After(0.6, function()
			if not repairOpen then return end
			local left, still = GetRepairAllCost()
			if still and type(left) == "number" and left > 0 then
				PersonalRepair(left)
			else
				Soul:Print("Repaired for " .. Q.Money(cost) .. " (guild).")
			end
		end)
		return
	end
	PersonalRepair(cost)
end

Q:Feature({
	key = "autoRepair",
	events = {
		MERCHANT_SHOW = function()
			repairOpen = true
			TryRepair()
		end,
		MERCHANT_CLOSED = function() repairOpen = false end,
	},
	disable = function() repairOpen = false end,
})

------------------------------------------------------------------------------
-- Sell junk (gray items with a vendor price)
------------------------------------------------------------------------------

local sell = { open = false, ticker = nil, count = 0, value = 0, ticks = 0 }

local function StopSelling(report)
	if sell.ticker then
		sell.ticker:Cancel()
		sell.ticker = nil
	end
	if report and sell.count > 0 then
		Soul:Print("Sold " .. sell.count .. (sell.count == 1 and " junk item" or " junk items") .. " for " .. Q.Money(sell.value) .. ".")
	end
	sell.count, sell.value, sell.ticks = 0, 0, 0
end

local function ItemValue(info)
	if not info.itemID then return 0 end
	local price = select(11, C_Item.GetItemInfo(info.itemID))
	if type(price) ~= "number" then return 0 end
	return price * (info.stackCount or 1)
end

-- Sells up to `batch` unlocked gray items. Returns how many grays remain
-- (locked ones included), so the ticker knows when it is done.
local function SellPass(batch)
	local sold, remaining = 0, 0
	for bag = 0, LAST_BAG do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == POOR and not info.hasNoValue then
				remaining = remaining + 1
				if not info.isLocked and sold < batch then
					if not sell.open then return remaining end
					sell.value = sell.value + ItemValue(info)
					sell.count = sell.count + 1
					C_Container.UseContainerItem(bag, slot)
					sold = sold + 1
				end
			end
		end
	end
	return remaining - sold
end

local function StartSelling()
	StopSelling(false)
	sell.ticker = C_Timer.NewTicker(0.2, function()
		if not sell.open then
			StopSelling(true)
			return
		end
		sell.ticks = sell.ticks + 1
		local left = SellPass(8)
		-- 40 passes is 8 seconds; a vendor that never takes an item ends here.
		if left <= 0 or sell.ticks >= 40 then StopSelling(true) end
	end)
end

Q:Feature({
	key = "autoSellJunk",
	events = {
		MERCHANT_SHOW = function()
			sell.open = true
			StartSelling()
		end,
		MERCHANT_CLOSED = function()
			sell.open = false
			StopSelling(true)
		end,
		UI_ERROR_MESSAGE = function(_, _, message)
			if not sell.ticker or Q.IsSecret(message) then return end
			if message == ERR_VENDOR_DOESNT_BUY then
				sell.open = false
				-- Nothing sold here: no "Sold N junk items" report.
				StopSelling(false)
			end
		end,
	},
	disable = function()
		sell.open = false
		StopSelling(false)
	end,
})

------------------------------------------------------------------------------
-- Train All button at profession trainers
------------------------------------------------------------------------------

local trainButton

local function Trainable()
	local count, cost = 0, 0
	local money = GetMoney()
	for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
		local _, _, kind = GetTrainerServiceInfo(i)
		if kind == "available" then
			local price = GetTrainerServiceCost(i) or 0
			if cost + price <= money then
				count = count + 1
				cost = cost + price
			end
		end
	end
	return count, cost
end

local function UpdateTrainButton()
	if not trainButton then return end
	if not Q.on.trainAll then
		trainButton:Hide()
		return
	end
	trainButton:Show()
	local count = Trainable()
	trainButton:SetEnabled(count > 0)
end

local function TrainAll()
	local count, cost = 0, 0
	local money = GetMoney()
	for i = GetNumTrainerServices(), 1, -1 do
		local _, _, kind = GetTrainerServiceInfo(i)
		if kind == "available" then
			local price = GetTrainerServiceCost(i) or 0
			if cost + price <= money then
				BuyTrainerService(i)
				count = count + 1
				cost = cost + price
			end
		end
	end
	if count > 0 then
		Soul:Print("Learned " .. count .. (count == 1 and " skill" or " skills") .. " for " .. Q.Money(cost) .. ".")
	end
end

local function BuildTrainButton()
	if trainButton or not ClassTrainerFrame then return end
	trainButton = CreateFrame("Button", nil, ClassTrainerFrame, "UIPanelButtonTemplate")
	trainButton:SetSize(90, 22)
	if ClassTrainerTrainButton then
		trainButton:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -4, 0)
	else
		trainButton:SetPoint("BOTTOMRIGHT", ClassTrainerFrame, "BOTTOMRIGHT", -100, 4)
	end
	trainButton:SetText("Train All")
	trainButton:SetScript("OnClick", TrainAll)
	trainButton:SetScript("OnEnter", function(self)
		local count, cost = Trainable()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Train All")
		GameTooltip:AddLine(count .. " skills you can afford, " .. Q.Money(cost) .. " total.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	trainButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	UpdateTrainButton()
end

Q:Feature({
	key = "trainAll",
	events = {
		TRAINER_SHOW = function()
			BuildTrainButton()
			UpdateTrainButton()
		end,
		TRAINER_UPDATE = function() UpdateTrainButton() end,
	},
	enable = function()
		Q.WhenLoaded("Blizzard_TrainerUI", BuildTrainButton)
		UpdateTrainButton()
	end,
	disable = function() UpdateTrainButton() end,
})
