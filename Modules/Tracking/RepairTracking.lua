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

-- Original function reference
local _originalRepairAllItems = nil

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
    -- Store original if not already hooked
    if not _originalRepairAllItems then
        _originalRepairAllItems = RepairAllItems
    end

    -- Replace with our wrapper
    RepairAllItems = function(useGuildFunds)
        -- Get repair cost before repairing
        local repairCost, canRepair = GetRepairAllCost()

        if not canRepair or repairCost <= 0 then
            -- Nothing to repair, just call original
            return _originalRepairAllItems(useGuildFunds)
        end

        -- Track gold before repair
        local goldBefore = GetMoney()

        -- Call original repair function
        _originalRepairAllItems(useGuildFunds)

        -- Check gold after to determine actual cost and source
        C_Timer.After(0.1, function()
            local goldAfter = GetMoney()
            local actualCost = goldBefore - goldAfter

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
    end
end

-- Get current repair cost (for UI display)
function RepairTracking:GetRepairCost()
    local cost, canRepair = GetRepairAllCost()
    return cost or 0, canRepair
end
