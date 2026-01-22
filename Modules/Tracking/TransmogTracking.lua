--[[
    InventoryManager - Modules/Tracking/TransmogTracking.lua
    Tracks gold spent at transmog NPCs (appearance changes).

    Events:
    - TRANSMOGRIFY_OPEN: Enter transmog context
    - TRANSMOGRIFY_CLOSE: Leave transmog context
    - PLAYER_MONEY: Gold change while at transmog NPC

    Strategy:
    Track gold before/after transmog window to detect costs.
    Transmog costs are always expenses (negative gold delta).

    @module Modules.Tracking.TransmogTracking
]]

local addonName, IM = ...

local TransmogTracking = {}
IM:RegisterModule("TransmogTracking", TransmogTracking)

-- State tracking
local _atTransmog = false
local _lastGold = 0

function TransmogTracking:OnEnable()
    -- Skip if transmog tracking disabled
    if not IM.db.global.ledger.trackTransmog then
        IM:Debug("[TransmogTracking] Disabled in settings")
        return
    end

    local module = self
    IM:Debug("[TransmogTracking] Registering events")

    -- Transmog window opened
    IM:RegisterEvent("TRANSMOGRIFY_OPEN", function()
        module:OnTransmogOpen()
    end)

    -- Transmog window closed
    IM:RegisterEvent("TRANSMOGRIFY_CLOSE", function()
        module:OnTransmogClose()
    end)

    -- Track gold changes while at transmog
    IM:RegisterEvent("PLAYER_MONEY", function()
        module:OnPlayerMoney()
    end)

    IM:Debug("[TransmogTracking] Module enabled")
end

function TransmogTracking:OnTransmogOpen()
    _atTransmog = true
    _lastGold = GetMoney()
    IM:Debug("[TransmogTracking] Transmog window opened, gold: " .. _lastGold)
end

function TransmogTracking:OnTransmogClose()
    -- Final check for any pending gold changes
    if _atTransmog then
        self:CheckGoldChange()
    end
    _atTransmog = false
    _lastGold = 0
    IM:Debug("[TransmogTracking] Transmog window closed")
end

function TransmogTracking:OnPlayerMoney()
    if not _atTransmog then
        return
    end

    self:CheckGoldChange()
end

-- Check for gold changes and log transmog costs
function TransmogTracking:CheckGoldChange()
    local currentGold = GetMoney()
    local goldDelta = currentGold - _lastGold

    -- Only log expenses (negative delta = gold spent)
    if goldDelta < 0 then
        local cost = math.abs(goldDelta)

        IM:AddTransaction("transmog", {
            value = -cost, -- Negative = expense
            source = "Transmog",
        })

        IM:Debug("[TransmogTracking] Transmog cost: " .. IM:FormatMoney(cost))
    end

    -- Update baseline for next change
    _lastGold = currentGold
end

-- Check if currently at transmog NPC
function TransmogTracking:IsAtTransmog()
    return _atTransmog
end
