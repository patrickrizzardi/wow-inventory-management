--[[
    InventoryManager - Modules/Tracking/RepairTracking.lua
    Tracks repair costs (personal and guild).

    Methods:
    - Hook RepairAllItems: Track repair cost and source
    - Check repair cost before calling, log after

    @module Modules.Tracking.RepairTracking
]]

local addonName, IM = ...

local RepairTracking = {}
IM:RegisterModule("RepairTracking", RepairTracking)

-- Track gold for repair cost calculation
local _goldBeforeRepair = nil
local _pendingRepairCost = nil

function RepairTracking:OnEnable()
    -- Skip if repair tracking disabled
    if not IM.db.global.ledger.trackRepairs then
        IM:Debug("[RepairTracking] Disabled in settings")
        return
    end

    IM:Debug("[RepairTracking] Hooking RepairAllItems")

    self:HookRepairFunction()

    IM:Debug("[RepairTracking] Module enabled")
end

function RepairTracking:HookRepairFunction()
    -- Track gold when merchant opens so we can calculate repair cost
    IM:RegisterEvent("MERCHANT_SHOW", function()
        _goldBeforeRepair = GetMoney()
        local repairCost, canRepair = GetRepairAllCost()
        _pendingRepairCost = canRepair and repairCost or 0
    end)

    -- Use hooksecurefunc to prevent taint - runs AFTER RepairAllItems
    hooksecurefunc("RepairAllItems", function(useGuildFunds)
        -- Get repair cost (may have been updated)
        local repairCost = _pendingRepairCost or 0

        if repairCost <= 0 then
            return
        end

        -- Check gold after to determine actual cost and source
        C_Timer.After(0.1, function()
            local goldAfter = GetMoney()
            local actualCost = (_goldBeforeRepair or goldAfter) - goldAfter

            -- Update baseline for next repair
            _goldBeforeRepair = goldAfter

            -- If gold didn't change (or changed less), guild paid
            local usedGuild = actualCost < repairCost * 0.5 -- Guild paid if we paid less than half

            if usedGuild then
                -- Guild paid (fully or partially)
                IM:AddTransaction("repair_guild", {
                    value = 0, -- No personal cost
                    source = "Guild Funds",
                })
                IM:Debug("[RepairTracking] Repair with guild funds: " .. IM:FormatMoney(repairCost))
            elseif actualCost > 0 then
                -- Personal funds
                IM:AddTransaction("repair", {
                    value = -actualCost, -- Negative = expense
                    source = "Personal",
                })
                IM:Debug("[RepairTracking] Personal repair: " .. IM:FormatMoney(actualCost))
            end
        end)
    end)
end

-- Get current repair cost (for UI display)
function RepairTracking:GetRepairCost()
    local cost, canRepair = GetRepairAllCost()
    return cost or 0, canRepair
end
