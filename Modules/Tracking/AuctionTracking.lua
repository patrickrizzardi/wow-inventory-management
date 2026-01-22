--[[
    InventoryManager - Modules/Tracking/AuctionTracking.lua
    Tracks auction house transactions: sales, purchases, deposits, fees, refunds.

    Events:
    - AUCTION_HOUSE_SHOW: Enter AH context
    - AUCTION_HOUSE_CLOSED: Leave AH context
    - AUCTION_HOUSE_SHOW_NOTIFICATION: Sale/expiry notifications
    - CHAT_MSG_SYSTEM: Auction sold messages (fallback)
    - CHAT_MSG_MONEY: Gold from auction sales
    - PLAYER_MONEY: Track gold changes for deposits/purchases

    Transaction Types:
    - ah_sold: Item sold at auction (income)
    - ah_bought: Item purchased from auction (expense)
    - ah_deposit: Deposit paid when posting (expense)
    - ah_refund: Deposit refunded when auction expires (income)
    - ah_fee: AH cut on sales (expense, 5%)

    @module Modules.Tracking.AuctionTracking
]]

local addonName, IM = ...

local AuctionTracking = {}
IM:RegisterModule("AuctionTracking", AuctionTracking)

-- State tracking
local _atAuctionHouse = false
local _pendingAuctionSale = nil
local _pendingDeposit = nil  -- { itemID, itemLink, quantity, goldBefore, timestamp }
local _pendingPurchase = nil -- { itemID, itemLink, quantity, cost, timestamp }
local _lastGold = 0

-- AH notification types (from Enum.AuctionHouseNotification)
local NOTIFICATION_AUCTION_SOLD = 4
local NOTIFICATION_AUCTION_EXPIRED = 2

function AuctionTracking:OnEnable()
    -- Skip if AH tracking disabled
    if not IM.db.global.ledger.trackAH then
        IM:Debug("[AuctionTracking] Disabled in settings")
        return
    end

    local module = self
    IM:Debug("[AuctionTracking] Registering events")

    -- AH context
    IM:RegisterEvent("AUCTION_HOUSE_SHOW", function()
        module:OnAuctionHouseShow()
    end)

    IM:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
        module:OnAuctionHouseClosed()
    end)

    -- AH notifications (sales, expiries)
    IM:RegisterEvent("AUCTION_HOUSE_SHOW_NOTIFICATION", function(event, notificationType, itemID, quantity)
        module:OnAuctionNotification(notificationType, itemID, quantity)
    end)

    -- Fallback: Chat messages for auction sales
    IM:RegisterEvent("CHAT_MSG_SYSTEM", function(event, message)
        module:OnSystemMessage(message)
    end)

    -- Gold received from auctions
    IM:RegisterEvent("CHAT_MSG_MONEY", function(event, message)
        module:OnMoneyMessage(message)
    end)

    -- Track gold changes for deposits/purchases while at AH
    IM:RegisterEvent("PLAYER_MONEY", function()
        module:OnPlayerMoney()
    end)

    -- Hook posting functions for deposit tracking
    self:HookPostingFunctions()

    -- Hook purchase functions
    self:HookPurchaseFunctions()

    IM:Debug("[AuctionTracking] Module enabled")
end

function AuctionTracking:OnAuctionHouseShow()
    _atAuctionHouse = true
    _lastGold = GetMoney()
    IM:Debug("[AuctionTracking] Auction house opened, gold: " .. _lastGold)
end

function AuctionTracking:OnAuctionHouseClosed()
    _atAuctionHouse = false
    _pendingDeposit = nil
    _pendingPurchase = nil
    _lastGold = 0
    IM:Debug("[AuctionTracking] Auction house closed")
end

-- Track gold changes while at AH for deposits and purchases
function AuctionTracking:OnPlayerMoney()
    if not _atAuctionHouse then
        return
    end

    local currentGold = GetMoney()
    local goldDelta = currentGold - _lastGold

    -- Check for pending deposit (gold spent after posting)
    if _pendingDeposit and goldDelta < 0 and (time() - _pendingDeposit.timestamp) < 2 then
        local depositCost = math.abs(goldDelta)

        IM:AddTransaction("ah_deposit", {
            itemID = _pendingDeposit.itemID,
            itemLink = _pendingDeposit.itemLink,
            quantity = _pendingDeposit.quantity,
            value = -depositCost, -- Negative = expense
            source = "AH Deposit",
        })

        IM:Debug("[AuctionTracking] Deposit logged: " .. IM:FormatMoney(depositCost) ..
                 " for " .. (_pendingDeposit.itemLink or "item"))

        _pendingDeposit = nil
    end

    -- Check for pending purchase (gold spent after buying)
    if _pendingPurchase and goldDelta < 0 and (time() - _pendingPurchase.timestamp) < 2 then
        local purchaseCost = math.abs(goldDelta)

        IM:AddTransaction("ah_bought", {
            itemID = _pendingPurchase.itemID,
            itemLink = _pendingPurchase.itemLink,
            quantity = _pendingPurchase.quantity,
            value = -purchaseCost, -- Negative = expense
            source = "Auction House",
        })

        -- Backwards compatibility
        if _pendingPurchase.itemID then
            IM:AddAuctionBoughtHistoryEntry(
                _pendingPurchase.itemID,
                _pendingPurchase.itemLink,
                _pendingPurchase.quantity,
                purchaseCost
            )
        end

        IM:Debug("[AuctionTracking] Purchase logged: " .. (_pendingPurchase.itemLink or "item") ..
                 " for " .. IM:FormatMoney(purchaseCost))

        _pendingPurchase = nil
    end

    _lastGold = currentGold
end

-- Handle auction house notifications
function AuctionTracking:OnAuctionNotification(notificationType, itemID, quantity)
    IM:Debug("[AuctionTracking] Notification: type=" .. tostring(notificationType) .. ", itemID=" .. tostring(itemID))

    if notificationType == NOTIFICATION_AUCTION_SOLD then
        -- Auction sold - store pending sale to match with money message
        local itemName, itemLink = GetItemInfo(itemID)
        _pendingAuctionSale = {
            itemID = itemID,
            itemLink = itemLink,
            quantity = quantity or 1,
            timestamp = time(),
        }
        IM:Debug("[AuctionTracking] Pending sale: " .. (itemLink or "item " .. itemID))

    elseif notificationType == NOTIFICATION_AUCTION_EXPIRED then
        -- Auction expired - deposit may be refunded (partially or fully)
        -- We'll track the refund via gold increase detection
        local itemName, itemLink = GetItemInfo(itemID)
        IM:Debug("[AuctionTracking] Auction expired: " .. (itemLink or "item " .. tostring(itemID)))
        -- Refund will be detected in PLAYER_MONEY as a gold increase while at AH
    end
end

-- Handle system messages for auction sales (fallback)
function AuctionTracking:OnSystemMessage(message)
    -- Look for auction sold messages containing item links
    local itemLink = IM:ExtractItemLinkFromMessage(message)
    if not itemLink then return end

    -- Check if this is an auction message
    if message:lower():find("auction") and message:lower():find("sold") then
        local itemID = GetItemInfoInstant(itemLink)
        if itemID and not _pendingAuctionSale then
            _pendingAuctionSale = {
                itemID = itemID,
                itemLink = itemLink,
                quantity = 1,
                timestamp = time(),
            }
            IM:Debug("[AuctionTracking] Pending sale from chat: " .. itemLink)
        end
    end
end

-- Handle money messages (match with pending auction sale)
function AuctionTracking:OnMoneyMessage(message)
    -- Extract gold amount using shared utility
    local totalCopper = IM:ParseMoneyFromMessage(message)

    if totalCopper <= 0 then return end

    -- Check if we have a pending auction sale (within 5 seconds)
    if _pendingAuctionSale and (time() - _pendingAuctionSale.timestamp) < 5 then
        -- Check if message mentions auction
        if message:lower():find("auction") then
            -- Calculate AH fee (5% of sale price, approximately)
            -- The money received is after the 5% cut
            local grossSale = math.floor(totalCopper / 0.95) -- Approximate original price
            local ahFee = grossSale - totalCopper

            -- Log the sale
            IM:AddTransaction("ah_sold", {
                itemID = _pendingAuctionSale.itemID,
                itemLink = _pendingAuctionSale.itemLink,
                quantity = _pendingAuctionSale.quantity,
                value = totalCopper, -- Net amount received
                source = "Auction House",
            })

            -- Log the fee separately
            if ahFee > 0 then
                IM:AddTransaction("ah_fee", {
                    value = -ahFee,
                    source = "AH Cut (5%)",
                })
            end

            -- Backwards compatibility
            IM:AddAuctionSoldHistoryEntry(
                _pendingAuctionSale.itemID,
                _pendingAuctionSale.itemLink,
                _pendingAuctionSale.quantity,
                totalCopper
            )

            IM:Debug("[AuctionTracking] Sale logged: " .. (_pendingAuctionSale.itemLink or "item") ..
                     " for " .. IM:FormatMoney(totalCopper) .. " (fee: " .. IM:FormatMoney(ahFee) .. ")")

            _pendingAuctionSale = nil
        end
    end
end

-- Hook posting functions for deposit tracking
function AuctionTracking:HookPostingFunctions()
    local module = self

    -- Hook C_AuctionHouse.PostItem if available (retail)
    if C_AuctionHouse and C_AuctionHouse.PostItem then
        hooksecurefunc(C_AuctionHouse, "PostItem", function(itemLocation, duration, quantity, bid, buyout)
            module:OnPostItem(itemLocation, duration, quantity)
        end)
        IM:Debug("[AuctionTracking] Hooked C_AuctionHouse.PostItem")
    end

    -- Hook C_AuctionHouse.PostCommodity if available (retail)
    if C_AuctionHouse and C_AuctionHouse.PostCommodity then
        hooksecurefunc(C_AuctionHouse, "PostCommodity", function(itemLocation, duration, quantity, unitPrice)
            module:OnPostCommodity(itemLocation, duration, quantity)
        end)
        IM:Debug("[AuctionTracking] Hooked C_AuctionHouse.PostCommodity")
    end
end

-- Hook purchase functions for tracking buys
function AuctionTracking:HookPurchaseFunctions()
    local module = self

    -- Hook C_AuctionHouse.PlaceBid for item purchases (includes buyout)
    if C_AuctionHouse and C_AuctionHouse.PlaceBid then
        hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
            module:OnPlaceBid(auctionID, bidAmount)
        end)
        IM:Debug("[AuctionTracking] Hooked C_AuctionHouse.PlaceBid")
    end

    -- Hook C_AuctionHouse.ConfirmCommoditiesPurchase for commodity purchases
    if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
        hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
            module:OnConfirmCommodityPurchase(itemID, quantity)
        end)
        IM:Debug("[AuctionTracking] Hooked C_AuctionHouse.ConfirmCommoditiesPurchase")
    end
end

-- Called when posting an item auction
function AuctionTracking:OnPostItem(itemLocation, duration, quantity)
    -- Get item info from location
    local itemID = nil
    local itemLink = nil

    if itemLocation and C_Item and C_Item.GetItemID then
        itemID = C_Item.GetItemID(itemLocation)
        if itemID then
            itemLink = C_Item.GetItemLink(itemLocation)
        end
    end

    -- Set up pending deposit - will be resolved when PLAYER_MONEY fires
    _pendingDeposit = {
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity or 1,
        timestamp = time(),
    }

    IM:Debug("[AuctionTracking] Item posted: " .. (itemLink or "item") .. ", awaiting deposit")
end

-- Called when posting a commodity auction
function AuctionTracking:OnPostCommodity(itemLocation, duration, quantity)
    -- Get item info from location
    local itemID = nil
    local itemLink = nil

    if itemLocation and C_Item and C_Item.GetItemID then
        itemID = C_Item.GetItemID(itemLocation)
        if itemID then
            local itemName = GetItemInfo(itemID)
            itemLink = select(2, GetItemInfo(itemID))
        end
    end

    -- Set up pending deposit
    _pendingDeposit = {
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity or 1,
        timestamp = time(),
    }

    IM:Debug("[AuctionTracking] Commodity posted: qty=" .. tostring(quantity) .. ", awaiting deposit")
end

-- Called when placing a bid (or buyout) on an item auction
function AuctionTracking:OnPlaceBid(auctionID, bidAmount)
    -- Try to get item info from the auction
    -- This is tricky - we'll set up pending purchase and resolve with PLAYER_MONEY
    _pendingPurchase = {
        auctionID = auctionID,
        bidAmount = bidAmount,
        quantity = 1,
        timestamp = time(),
    }

    IM:Debug("[AuctionTracking] Bid placed: auctionID=" .. tostring(auctionID) ..
             ", amount=" .. tostring(bidAmount))
end

-- Called when confirming a commodity purchase
function AuctionTracking:OnConfirmCommodityPurchase(itemID, quantity)
    local itemName, itemLink = GetItemInfo(itemID)

    _pendingPurchase = {
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity or 1,
        timestamp = time(),
    }

    IM:Debug("[AuctionTracking] Commodity purchase: " .. (itemLink or "item " .. tostring(itemID)) ..
             " x" .. tostring(quantity))
end

-- Log an auction purchase (called externally when we detect a purchase)
function AuctionTracking:LogPurchase(itemID, itemLink, quantity, cost)
    IM:AddTransaction("ah_bought", {
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity,
        value = -cost, -- Negative = expense
        source = "Auction House",
    })

    -- Backwards compatibility
    IM:AddAuctionBoughtHistoryEntry(itemID, itemLink, quantity, cost)

    IM:Debug("[AuctionTracking] Purchase logged: " .. (itemLink or "item") .. " for " .. IM:FormatMoney(cost))
end

-- Check if at auction house
function AuctionTracking:IsAtAuctionHouse()
    return _atAuctionHouse
end
