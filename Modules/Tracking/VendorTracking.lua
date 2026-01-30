--[[
    InventoryManager - Modules/Tracking/VendorTracking.lua
    Tracks vendor transactions: sells, purchases, buybacks.

    Methods:
    - Hook BuyMerchantItem: Track purchases
    - Hook BuybackItem: Track buybacks
    - PLAYER_MONEY + bag snapshot: Track sells (gold delta + item removal detection)

    @module Modules.Tracking.VendorTracking
]]

local addonName, IM = ...

local VendorTracking = {}
IM:RegisterModule("VendorTracking", VendorTracking)

-- State tracking
local _atVendor = false
local _vendorName = nil

-- Sell tracking via gold + bag changes
local _lastGold = 0
local _bagSnapshot = {}  -- {[bagID] = {[slotID] = {itemID, itemLink, stackCount, sellPrice}}}

function VendorTracking:OnEnable()
    local module = self
    IM:Debug("[VendorTracking] Registering events and hooks")

    -- Track when we're at a vendor
    IM:RegisterEvent("MERCHANT_SHOW", function()
        module:OnMerchantShow()
    end)

    IM:RegisterEvent("MERCHANT_CLOSED", function()
        module:OnMerchantClosed()
    end)

    -- Track gold changes (fires on ANY gold change)
    IM:RegisterEvent("PLAYER_MONEY", function()
        module:OnPlayerMoney()
    end)

    -- Note: We intentionally DON'T re-snapshot on BAG_UPDATE_DELAYED
    -- because we need the snapshot to persist until PLAYER_MONEY fires
    -- The order of events is: item sold -> BAG_UPDATE_DELAYED -> PLAYER_MONEY
    -- If we re-snapshot on BAG_UPDATE_DELAYED, the item will already be gone

    -- Hook purchase function
    self:HookPurchases()

    -- Hook buyback function
    self:HookBuybacks()

    IM:Debug("[VendorTracking] Module enabled")
end

function VendorTracking:OnMerchantShow()
    _atVendor = true
    _vendorName = UnitName("npc") or "Vendor"
    _lastGold = GetMoney()

    -- Take snapshot of all bag contents
    self:SnapshotBags()

    IM:Debug("[VendorTracking] Merchant opened: " .. _vendorName .. ", gold: " .. _lastGold)
end

function VendorTracking:OnMerchantClosed()
    IM:Debug("[VendorTracking] Merchant closed, was at vendor: " .. tostring(_atVendor))
    _atVendor = false
    _vendorName = nil
    wipe(_bagSnapshot)
end

-- Snapshot all bag contents for comparison
function VendorTracking:SnapshotBags()
    wipe(_bagSnapshot)

    for bagID = 0, 4 do
        _bagSnapshot[bagID] = {}
        local numSlots = C_Container.GetContainerNumSlots(bagID)

        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(info.itemID)
                _bagSnapshot[bagID][slotID] = {
                    itemID = info.itemID,
                    itemLink = info.hyperlink,
                    stackCount = info.stackCount or 1,
                    sellPrice = sellPrice or 0,
                }
            end
        end
    end

    IM:Debug("[VendorTracking] Bag snapshot taken")
end

-- Called when gold changes
function VendorTracking:OnPlayerMoney()
    if not _atVendor then
        return
    end

    local currentGold = GetMoney()
    local goldDelta = currentGold - _lastGold

    IM:Debug("[VendorTracking] PLAYER_MONEY: delta=" .. goldDelta .. " (was " .. _lastGold .. ", now " .. currentGold .. ")")

    -- If we gained gold, check what items were removed from bags
    if goldDelta > 0 then
        -- Find what's missing from our snapshot
        local soldItems = self:FindMissingItems()

        -- Filter out items with no sell price (can't have been sold for gold)
        local sellableItems = {}
        for _, item in ipairs(soldItems) do
            if item.sellPrice and item.sellPrice > 0 then
                table.insert(sellableItems, item)
            else
                IM:Debug("[VendorTracking] Skipping item with no sell price: " .. (item.itemLink or item.itemID))
            end
        end
        soldItems = sellableItems

        if #soldItems > 0 then
            IM:Debug("[VendorTracking] Found " .. #soldItems .. " sellable items missing from bags")

            -- Calculate expected value from items
            local expectedValue = 0
            for _, item in ipairs(soldItems) do
                expectedValue = expectedValue + (item.sellPrice * item.stackCount)
            end

            IM:Debug("[VendorTracking] Expected value: " .. expectedValue .. ", actual delta: " .. goldDelta)

            -- If the gold gained roughly matches expected sell value, log the sales
            -- Allow some tolerance for rounding/server quirks
            if goldDelta > 0 and expectedValue > 0 and math.abs(goldDelta - expectedValue) < (expectedValue * 0.1 + 1) then
                for _, item in ipairs(soldItems) do
                    local itemValue = item.sellPrice * item.stackCount
                    self:LogSellTransaction(item.itemID, item.itemLink, item.stackCount, itemValue)
                end
            else
                -- Gold gained but items don't match - might be single item, use gold delta
                IM:Debug("[VendorTracking] Value mismatch, using gold delta for " .. #soldItems .. " items")
                if #soldItems == 1 then
                    local item = soldItems[1]
                    self:LogSellTransaction(item.itemID, item.itemLink, item.stackCount, goldDelta)
                elseif expectedValue > 0 then
                    -- Multiple items, distribute gold proportionally
                    for _, item in ipairs(soldItems) do
                        local proportion = (item.sellPrice * item.stackCount) / expectedValue
                        local itemValue = math.floor(goldDelta * proportion)
                        self:LogSellTransaction(item.itemID, item.itemLink, item.stackCount, itemValue)
                    end
                else
                    -- Multiple items but can't calculate proportions - distribute evenly
                    local perItemValue = math.floor(goldDelta / #soldItems)
                    for _, item in ipairs(soldItems) do
                        self:LogSellTransaction(item.itemID, item.itemLink, item.stackCount, perItemValue)
                    end
                end
            end
        else
            IM:Debug("[VendorTracking] Gold gained but no items missing - might be buyback refund or other source")
        end
    end

    -- Update snapshot and gold tracker
    _lastGold = currentGold
    self:SnapshotBags()
end

-- Find items that were in our snapshot but are now gone
function VendorTracking:FindMissingItems()
    local missing = {}

    for bagID = 0, 4 do
        local snapshot = _bagSnapshot[bagID]
        if snapshot then
            for slotID, itemData in pairs(snapshot) do
                -- Check if item is still there
                local currentInfo = C_Container.GetContainerItemInfo(bagID, slotID)

                -- Item is missing or different
                if not currentInfo or not currentInfo.itemID or currentInfo.itemID ~= itemData.itemID then
                    IM:Debug("[VendorTracking] Missing item: bag " .. bagID .. " slot " .. slotID ..
                             " was " .. (itemData.itemLink or itemData.itemID))
                    table.insert(missing, itemData)
                elseif currentInfo.stackCount < itemData.stackCount then
                    -- Partial stack sold
                    local soldCount = itemData.stackCount - currentInfo.stackCount
                    IM:Debug("[VendorTracking] Partial stack sold: " .. soldCount .. " of " ..
                             (itemData.itemLink or itemData.itemID))
                    table.insert(missing, {
                        itemID = itemData.itemID,
                        itemLink = itemData.itemLink,
                        stackCount = soldCount,
                        sellPrice = itemData.sellPrice,
                    })
                end
            end
        end
    end

    return missing
end

-- Log a sell transaction
function VendorTracking:LogSellTransaction(itemID, itemLink, quantity, value)
    IM:Debug("[VendorTracking] LOGGING SELL: " .. (itemLink or "item " .. itemID) ..
             " x" .. quantity .. " for " .. IM:FormatMoney(value))

    IM:AddTransaction("sell", {
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity,
        value = value, -- Positive = income
        source = _vendorName or "Vendor",
    })

    -- Backwards compatibility
    IM:AddSellHistoryEntry(itemID, itemLink, quantity, value)

    -- Note: Not printing here since AutoSell already shows summary message
    -- Individual sell messages would be too spammy during batch sales
    IM:Debug("[VendorTracking] Sale complete: " .. (itemLink or "item") .. " x" .. quantity .. " for " .. IM:FormatMoney(value))
end

-- Hook vendor purchases (using hooksecurefunc to prevent taint)
function VendorTracking:HookPurchases()
    hooksecurefunc("BuyMerchantItem", function(index, quantity)
        -- Get item info (merchant frame still open after purchase)
        local itemLink = C_MerchantFrame and C_MerchantFrame.GetItemLink and C_MerchantFrame.GetItemLink(index) or (GetMerchantItemLink and GetMerchantItemLink(index))
        local price, stackCount
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(index)
            if info then
                price = info.price
                stackCount = info.stackCount
            end
        elseif GetMerchantItemInfo then
            _, _, price, stackCount = GetMerchantItemInfo(index)
        end
        local buyQuantity = quantity or stackCount or 1

        -- Log the purchase
        if itemLink and price then
            local itemID = GetItemInfoInstant(itemLink)
            if itemID then
                local totalCost = price * math.ceil(buyQuantity / (stackCount or 1))

                IM:AddTransaction("purchase", {
                    itemID = itemID,
                    itemLink = itemLink,
                    quantity = buyQuantity,
                    value = -totalCost, -- Negative = expense
                    source = _vendorName,
                })

                -- Backwards compatibility
                IM:AddPurchaseHistoryEntry(itemID, itemLink, buyQuantity, totalCost)

                IM:Debug("[VendorTracking] Purchase: " .. itemLink .. " x" .. buyQuantity .. " for " .. IM:FormatMoney(totalCost))
            end
        end
    end)
end

-- Hook buybacks (using hooksecurefunc to prevent taint)
function VendorTracking:HookBuybacks()
    hooksecurefunc("BuybackItem", function(index)
        -- Get item info (buyback tab still open after action)
        local itemLink = GetBuybackItemLink(index)
        local _, _, price, quantity = GetBuybackItemInfo(index)

        -- Log the buyback
        if itemLink and price then
            local itemID = GetItemInfoInstant(itemLink)
            if itemID then
                IM:AddTransaction("buyback", {
                    itemID = itemID,
                    itemLink = itemLink,
                    quantity = quantity or 1,
                    value = -price, -- Negative = expense
                    source = _vendorName,
                })

                -- Backwards compatibility
                IM:AddBuybackHistoryEntry(itemID, itemLink, quantity or 1, price)

                IM:Debug("[VendorTracking] Buyback: " .. itemLink .. " for " .. IM:FormatMoney(price))
            end
        end
    end)
end

-- Check if currently at vendor
function VendorTracking:IsAtVendor()
    return _atVendor
end

-- Get current vendor name
function VendorTracking:GetVendorName()
    return _vendorName
end
