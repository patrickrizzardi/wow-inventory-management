--[[
    InventoryManager - Modules/Tracking/BarberTracking.lua
    Tracks gold spent at barbershop NPCs.

    Events:
    - BARBER_SHOP_OPEN: Enter barbershop context
    - BARBER_SHOP_CLOSE: Leave barbershop context
    - PLAYER_MONEY: Gold change while at barbershop

    Strategy:
    Track gold before/after barbershop window to detect costs.
    Barbershop costs are always expenses (negative gold delta).

    @module Modules.Tracking.BarberTracking
]]

local addonName, IM = ...

local BarberTracking = {}
IM:RegisterModule("BarberTracking", BarberTracking)

-- State tracking
local _atBarber = false
local _lastGold = 0

function BarberTracking:OnEnable()
    -- Skip if barber tracking disabled
    if not IM.db.global.ledger.trackBarber then
        IM:Debug("[BarberTracking] Disabled in settings")
        return
    end

    local module = self
    IM:Debug("[BarberTracking] Registering events")

    -- Barber shop opened
    IM:RegisterEvent("BARBER_SHOP_OPEN", function()
        module:OnBarberOpen()
    end)

    -- Barber shop closed
    IM:RegisterEvent("BARBER_SHOP_CLOSE", function()
        module:OnBarberClose()
    end)

    -- Track gold changes while at barber
    IM:RegisterEvent("PLAYER_MONEY", function()
        module:OnPlayerMoney()
    end)

    IM:Debug("[BarberTracking] Module enabled")
end

function BarberTracking:OnBarberOpen()
    _atBarber = true
    _lastGold = GetMoney()
    IM:Debug("[BarberTracking] Barbershop opened, gold: " .. _lastGold)
end

function BarberTracking:OnBarberClose()
    -- Final check for any pending gold changes
    if _atBarber then
        self:CheckGoldChange()
    end
    _atBarber = false
    _lastGold = 0
    IM:Debug("[BarberTracking] Barbershop closed")
end

function BarberTracking:OnPlayerMoney()
    if not _atBarber then
        return
    end

    self:CheckGoldChange()
end

-- Check for gold changes and log barber costs
function BarberTracking:CheckGoldChange()
    local currentGold = GetMoney()
    local goldDelta = currentGold - _lastGold

    -- Only log expenses (negative delta = gold spent)
    if goldDelta < 0 then
        local cost = math.abs(goldDelta)

        IM:AddTransaction("barber", {
            value = -cost, -- Negative = expense
            source = "Barbershop",
        })

        IM:Debug("[BarberTracking] Barber cost: " .. IM:FormatMoney(cost))
    end

    -- Update baseline for next change
    _lastGold = currentGold
end

-- Check if currently at barbershop
function BarberTracking:IsAtBarber()
    return _atBarber
end
