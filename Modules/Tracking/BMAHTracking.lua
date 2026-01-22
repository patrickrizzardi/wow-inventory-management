--[[
    InventoryManager - Modules/Tracking/BMAHTracking.lua
    Tracks Black Market Auction House purchases.

    Events:
    - BLACK_MARKET_OPEN: Enter BMAH context
    - BLACK_MARKET_CLOSE: Leave BMAH context
    - PLAYER_MONEY: Gold change while at BMAH
    - BLACK_MARKET_ITEM_UPDATE: Bid updates

    Strategy:
    Hook C_BlackMarket.ItemPlaceBid to track bid amounts.
    Track gold changes at BMAH for actual purchases (when you win).

    Note: BMAH is different from regular AH - uses completely different API.
    Purchases at BMAH are typically for rare mounts, transmog, pets, etc.

    @module Modules.Tracking.BMAHTracking
]]

local addonName, IM = ...

local BMAHTracking = {}
IM:RegisterModule("BMAHTracking", BMAHTracking)

-- State tracking
local _atBMAH = false
local _lastGold = 0
local _pendingBid = nil -- { marketID, itemID, itemLink, bidAmount, timestamp }

function BMAHTracking:OnEnable()
    -- Skip if BMAH tracking disabled
    if not IM.db.global.ledger.trackBMAH then
        IM:Debug("[BMAHTracking] Disabled in settings")
        return
    end

    local module = self
    IM:Debug("[BMAHTracking] Registering events")

    -- BMAH window opened
    IM:RegisterEvent("BLACK_MARKET_OPEN", function()
        module:OnBMAHOpen()
    end)

    -- BMAH window closed
    IM:RegisterEvent("BLACK_MARKET_CLOSE", function()
        module:OnBMAHClose()
    end)

    -- Track gold changes while at BMAH
    IM:RegisterEvent("PLAYER_MONEY", function()
        module:OnPlayerMoney()
    end)

    -- Hook bid placement to track pending bids
    self:HookBidFunction()

    IM:Debug("[BMAHTracking] Module enabled")
end

function BMAHTracking:OnBMAHOpen()
    _atBMAH = true
    _lastGold = GetMoney()
    IM:Debug("[BMAHTracking] Black Market AH opened, gold: " .. _lastGold)
end

function BMAHTracking:OnBMAHClose()
    _atBMAH = false
    _lastGold = 0
    _pendingBid = nil
    IM:Debug("[BMAHTracking] Black Market AH closed")
end

function BMAHTracking:OnPlayerMoney()
    if not _atBMAH then
        return
    end

    local currentGold = GetMoney()
    local goldDelta = currentGold - _lastGold

    -- Gold spent at BMAH (negative delta = bid placed)
    if goldDelta < 0 then
        local cost = math.abs(goldDelta)

        -- Try to match with pending bid info
        local itemLink = nil
        local itemID = nil

        if _pendingBid and (time() - _pendingBid.timestamp) < 5 then
            -- Use pending bid info if recent
            itemLink = _pendingBid.itemLink
            itemID = _pendingBid.itemID
            IM:Debug("[BMAHTracking] Matched pending bid: " .. (itemLink or "unknown"))
        end

        IM:AddTransaction("bmah_bid", {
            itemID = itemID,
            itemLink = itemLink,
            value = -cost, -- Negative = expense
            source = "Black Market AH",
        })

        IM:Debug("[BMAHTracking] BMAH bid: " .. IM:FormatMoney(cost) .. " for " .. (itemLink or "unknown item"))

        _pendingBid = nil
    end

    _lastGold = currentGold
end

-- Hook the bid placement function to capture item info
function BMAHTracking:HookBidFunction()
    -- C_BlackMarket.ItemPlaceBid(marketID, bidAmount)
    if C_BlackMarket and C_BlackMarket.ItemPlaceBid then
        hooksecurefunc(C_BlackMarket, "ItemPlaceBid", function(marketID, bidAmount)
            self:OnBidPlaced(marketID, bidAmount)
        end)
        IM:Debug("[BMAHTracking] Hooked C_BlackMarket.ItemPlaceBid")
    else
        IM:Debug("[BMAHTracking] C_BlackMarket.ItemPlaceBid not available")
    end
end

-- Called when a bid is placed
function BMAHTracking:OnBidPlaced(marketID, bidAmount)
    -- Try to get item info for this market ID
    local itemInfo = nil
    if C_BlackMarket and C_BlackMarket.GetItemInfoByID then
        itemInfo = C_BlackMarket.GetItemInfoByID(marketID)
    end

    local itemID = nil
    local itemLink = nil

    if itemInfo then
        itemID = itemInfo.itemID
        itemLink = itemInfo.itemLink
    end

    _pendingBid = {
        marketID = marketID,
        itemID = itemID,
        itemLink = itemLink,
        bidAmount = bidAmount,
        timestamp = time(),
    }

    IM:Debug("[BMAHTracking] Bid placed: marketID=" .. tostring(marketID) ..
             ", amount=" .. tostring(bidAmount) ..
             ", item=" .. (itemLink or "unknown"))
end

-- Check if currently at BMAH
function BMAHTracking:IsAtBMAH()
    return _atBMAH
end
