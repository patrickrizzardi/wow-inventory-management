--[[
    InventoryManager - Modules/Tracking/UnclaimedGoldTracking.lua
    Catches gold changes not claimed by any other tracking module.

    Strategy:
    1. Listen for PLAYER_MONEY events
    2. When gold changes, set a pending flag with timestamp and amount
    3. Other modules call IM:ClaimGoldChange() when they handle a transaction
    4. After 0.5s delay, if no module claimed it, log as "other_income" or "other_expense"

    This catches:
    - Crafting costs
    - Profession training fees
    - Great Vault fees
    - Garrison/mission table costs
    - Any other gold sink/source we don't explicitly track

    Transaction Types:
    - other_income: Gold increased, unknown source
    - other_expense: Gold decreased, unknown sink

    @module Modules.Tracking.UnclaimedGoldTracking
]]

local addonName, IM = ...

local UnclaimedGoldTracking = {}
IM:RegisterModule("UnclaimedGoldTracking", UnclaimedGoldTracking)

-- State tracking
local _lastGold = 0
local _pendingChange = nil  -- { amount, timestamp, wasIncome }
local _claimedThisCycle = false
local CLAIM_TIMEOUT = 0.5  -- Seconds to wait for a claim

-- Minimum change to track (ignore tiny fluctuations)
local MIN_CHANGE_TO_TRACK = 1 -- 1 copper

function UnclaimedGoldTracking:OnInitialize()
    -- Initialize last gold value early if possible
    if GetMoney then
        _lastGold = GetMoney()
    end
end

function UnclaimedGoldTracking:OnEnable()
    -- Skip if unclaimed tracking disabled
    if not IM.db.global.ledger.trackUnclaimed then
        IM:Debug("[UnclaimedGoldTracking] Disabled in settings")
        return
    end

    local module = self
    IM:Debug("[UnclaimedGoldTracking] Registering events")

    -- Track ALL gold changes
    IM:RegisterEvent("PLAYER_MONEY", function()
        module:OnPlayerMoney()
    end)

    -- Also update baseline on login
    IM:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        _lastGold = GetMoney()
        IM:Debug("[UnclaimedGoldTracking] Reset baseline on login: " .. _lastGold)
    end)

    IM:Debug("[UnclaimedGoldTracking] Module enabled")
end

function UnclaimedGoldTracking:OnPlayerMoney()
    local currentGold = GetMoney()
    local delta = currentGold - _lastGold

    -- Skip if no meaningful change
    if math.abs(delta) < MIN_CHANGE_TO_TRACK then
        _lastGold = currentGold
        return
    end

    IM:Debug("[UnclaimedGoldTracking] PLAYER_MONEY: delta=" .. delta ..
             " (was " .. _lastGold .. ", now " .. currentGold .. ")")

    -- Check if we're in a context where another module should handle this
    if self:IsInTrackedContext() then
        IM:Debug("[UnclaimedGoldTracking] In tracked context, skipping")
        _lastGold = currentGold
        return
    end

    -- Set up pending change
    _pendingChange = {
        amount = delta,
        timestamp = GetTime(),
        wasIncome = delta > 0,
    }
    _claimedThisCycle = false

    -- Schedule check after timeout
    C_Timer.After(CLAIM_TIMEOUT, function()
        self:CheckUnclaimedChange()
    end)

    _lastGold = currentGold
end

-- Check if we're in a context where another module handles gold tracking
function UnclaimedGoldTracking:IsInTrackedContext()
    -- Vendor
    local vendorTracking = IM:GetModule("VendorTracking")
    if vendorTracking and vendorTracking:IsAtVendor() then
        return true
    end

    -- Auction House
    local auctionTracking = IM:GetModule("AuctionTracking")
    if auctionTracking and auctionTracking:IsAtAuctionHouse() then
        return true
    end

    -- Mailbox
    local mailTracking = IM:GetModule("MailTracking")
    if mailTracking and mailTracking:IsAtMailbox() then
        return true
    end

    -- Trade
    local tradeTracking = IM:GetModule("TradeTracking")
    if tradeTracking and tradeTracking:IsInTrade() then
        return true
    end

    -- Transmog
    local transmogTracking = IM:GetModule("TransmogTracking")
    if transmogTracking and transmogTracking:IsAtTransmog() then
        return true
    end

    -- Barber
    local barberTracking = IM:GetModule("BarberTracking")
    if barberTracking and barberTracking:IsAtBarber() then
        return true
    end

    -- Black Market AH
    local bmahTracking = IM:GetModule("BMAHTracking")
    if bmahTracking and bmahTracking:IsAtBMAH() then
        return true
    end

    -- Warband Bank
    local warbankTracking = IM:GetModule("WarbandBankTracking")
    if warbankTracking and warbankTracking:IsAtWarbandBank() then
        return true
    end

    -- Guild Bank
    local guildBankTracking = IM:GetModule("GuildBankTracking")
    if guildBankTracking and guildBankTracking:IsAtGuildBank() then
        return true
    end

    -- Flight Master (uses a different approach - hooks TakeTaxiNode)
    -- Flight costs are claimed immediately so we don't need to check context

    return false
end

-- Check if the pending change was claimed, log if not
function UnclaimedGoldTracking:CheckUnclaimedChange()
    if not _pendingChange then
        return
    end

    -- Already claimed by another module
    if _claimedThisCycle then
        IM:Debug("[UnclaimedGoldTracking] Change was claimed by another module")
        _pendingChange = nil
        return
    end

    -- Check if change is stale (more than 2 seconds old)
    local age = GetTime() - _pendingChange.timestamp
    if age > 2 then
        IM:Debug("[UnclaimedGoldTracking] Change is stale, ignoring")
        _pendingChange = nil
        return
    end

    -- Log as unclaimed income or expense
    local amount = _pendingChange.amount
    local transactionType = amount > 0 and "other_income" or "other_expense"

    IM:AddTransaction(transactionType, {
        value = amount, -- Positive for income, negative for expense
        source = "Unknown",
    })

    IM:Debug("[UnclaimedGoldTracking] Logged unclaimed " .. transactionType .. ": " ..
             IM:FormatMoney(math.abs(amount)))

    _pendingChange = nil
end

-- Called by other tracking modules to claim a gold change
-- This prevents the change from being logged as "other"
function IM:ClaimGoldChange()
    _claimedThisCycle = true
    IM:Debug("[UnclaimedGoldTracking] Gold change claimed")
end

-- Get pending change info (for debugging)
function UnclaimedGoldTracking:GetPendingChange()
    return _pendingChange
end

-- Force reset baseline (for debugging)
function UnclaimedGoldTracking:ResetBaseline()
    _lastGold = GetMoney()
    _pendingChange = nil
    _claimedThisCycle = false
end
