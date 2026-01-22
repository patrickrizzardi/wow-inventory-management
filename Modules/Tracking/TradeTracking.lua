--[[
    InventoryManager - Modules/Tracking/TradeTracking.lua
    Tracks gold exchanged via player trading.

    Events:
    - TRADE_SHOW: Trade window opened
    - TRADE_CLOSED: Trade window closed
    - TRADE_ACCEPT_UPDATE: Trade acceptance changed
    - UI_INFO_MESSAGE: Check for ERR_TRADE_COMPLETE

    @module Modules.Tracking.TradeTracking
]]

local addonName, IM = ...

local TradeTracking = {}
IM:RegisterModule("TradeTracking", TradeTracking)

-- State tracking
local _inTrade = false
local _tradeTarget = nil
local _pendingGoldGiven = 0
local _pendingGoldReceived = 0

function TradeTracking:OnEnable()
    -- Skip if trade tracking disabled
    if not IM.db.global.ledger.trackTrade then
        IM:Debug("[TradeTracking] Disabled in settings")
        return
    end

    IM:Debug("[TradeTracking] Registering events")

    -- Trade window events
    IM:RegisterEvent("TRADE_SHOW", function()
        self:OnTradeShow()
    end)

    IM:RegisterEvent("TRADE_CLOSED", function()
        self:OnTradeClosed()
    end)

    IM:RegisterEvent("TRADE_ACCEPT_UPDATE", function(event, playerAccepted, targetAccepted)
        self:OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    end)

    -- Trade completion message
    IM:RegisterEvent("UI_INFO_MESSAGE", function(event, messageType, message)
        self:OnInfoMessage(messageType, message)
    end)

    -- Also track money changes during trade
    IM:RegisterEvent("TRADE_MONEY_CHANGED", function()
        self:OnTradeMoneyChanged()
    end)

    IM:RegisterEvent("TRADE_TARGET_ITEM_CHANGED", function()
        self:OnTradeMoneyChanged()
    end)

    IM:Debug("[TradeTracking] Module enabled")
end

function TradeTracking:OnTradeShow()
    _inTrade = true
    _tradeTarget = UnitName("NPC") or UnitName("target") or "Unknown"
    _pendingGoldGiven = 0
    _pendingGoldReceived = 0
    IM:Debug("[TradeTracking] Trade opened with: " .. _tradeTarget)
end

function TradeTracking:OnTradeClosed()
    _inTrade = false
    IM:Debug("[TradeTracking] Trade closed")
end

function TradeTracking:OnTradeMoneyChanged()
    if not _inTrade then return end

    -- Update pending amounts
    _pendingGoldGiven = GetPlayerTradeMoney() or 0
    _pendingGoldReceived = GetTargetTradeMoney() or 0
end

function TradeTracking:OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    if not _inTrade then return end

    -- Capture final gold amounts when both accept
    if playerAccepted and targetAccepted then
        _pendingGoldGiven = GetPlayerTradeMoney() or 0
        _pendingGoldReceived = GetTargetTradeMoney() or 0
        IM:Debug("[TradeTracking] Both accepted - giving: " .. _pendingGoldGiven .. ", receiving: " .. _pendingGoldReceived)
    end
end

function TradeTracking:OnInfoMessage(messageType, message)
    -- Check for trade complete message
    -- Use global string to be locale-independent
    local tradeCompleteMsg = ERR_TRADE_COMPLETE or "Trade complete"

    if message == tradeCompleteMsg then
        self:OnTradeComplete()
    end
end

function TradeTracking:OnTradeComplete()
    IM:Debug("[TradeTracking] Trade complete - given: " .. _pendingGoldGiven .. ", received: " .. _pendingGoldReceived)

    -- Log gold given
    if _pendingGoldGiven > 0 then
        IM:AddTransaction("trade_gold_sent", {
            value = -_pendingGoldGiven, -- Negative = expense
            source = _tradeTarget,
        })
        IM:Debug("[TradeTracking] Sent: " .. IM:FormatMoney(_pendingGoldGiven) .. " to " .. _tradeTarget)
    end

    -- Log gold received
    if _pendingGoldReceived > 0 then
        IM:AddTransaction("trade_gold_recv", {
            value = _pendingGoldReceived, -- Positive = income
            source = _tradeTarget,
        })
        IM:Debug("[TradeTracking] Received: " .. IM:FormatMoney(_pendingGoldReceived) .. " from " .. _tradeTarget)
    end

    -- Reset state
    _pendingGoldGiven = 0
    _pendingGoldReceived = 0
    _inTrade = false
end

-- Check if in trade
function TradeTracking:IsInTrade()
    return _inTrade
end

-- Get trade target name
function TradeTracking:GetTradeTarget()
    return _tradeTarget
end
