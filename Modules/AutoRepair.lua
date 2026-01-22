--[[
    InventoryManager - Modules/AutoRepair.lua
    Automatic repair at merchants
]]

local addonName, IM = ...

local AutoRepair = {}
IM:RegisterModule("AutoRepair", AutoRepair)

-- Track if we've already repaired at this merchant
local hasRepairedThisVisit = false

function AutoRepair:OnEnable()
    -- Register for merchant events
    IM:RegisterEvent("MERCHANT_SHOW", function()
        hasRepairedThisVisit = false
        self:OnMerchantShow()
    end)

    IM:RegisterEvent("MERCHANT_CLOSED", function()
        hasRepairedThisVisit = false
    end)
end

-- Called when merchant window opens
function AutoRepair:OnMerchantShow()
    -- Check if auto-repair is enabled
    if not IM.db.global.autoRepairEnabled then
        return
    end

    -- Check if merchant can repair
    if not CanMerchantRepair() then
        return
    end

    -- Don't repair twice in one visit
    if hasRepairedThisVisit then
        return
    end

    -- Small delay to let UI settle
    C_Timer.After(0.1, function()
        self:Repair()
    end)
end

-- Perform repair
function AutoRepair:Repair()
    -- Check if merchant can repair
    if not CanMerchantRepair() then
        IM:Print("This merchant cannot repair items")
        return false
    end

    -- Get repair cost
    local repairCost, canRepair = GetRepairAllCost()

    if not canRepair or repairCost == 0 then
        IM:Debug("No items need repair")
        return false
    end

    local db = IM.db.global.repair
    local usedGuildFunds = false
    local success = false

    -- Try guild funds first if enabled
    if db.useGuildFunds then
        local canUseGuildFunds = CanGuildBankRepair and CanGuildBankRepair()
        if canUseGuildFunds then
            -- Check if guild has enough funds
            local guildBankMoney = GetGuildBankMoney and GetGuildBankMoney() or 0
            if guildBankMoney >= repairCost then
                RepairAllItems(true) -- true = use guild bank
                usedGuildFunds = true
                success = true
            end
        end
    end

    -- Fall back to personal gold if guild funds failed or disabled
    if not success and (db.fallbackToPersonal or not db.useGuildFunds) then
        local playerMoney = GetMoney()
        if playerMoney >= repairCost then
            RepairAllItems(false) -- false = use personal gold
            success = true
        else
            IM:Print("Not enough gold to repair! Need: " .. IM:FormatMoney(repairCost))
            return false
        end
    end

    if success then
        hasRepairedThisVisit = true
        local source = usedGuildFunds and "guild bank" or "personal gold"
        IM:Print("Repaired all items for " .. IM:FormatMoney(repairCost) .. " (" .. source .. ")")
        return true
    end

    return false
end

-- Manual repair trigger (from slash command)
function AutoRepair:ManualRepair()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        IM:Print("You must be at a merchant to repair")
        return false
    end

    hasRepairedThisVisit = false
    return self:Repair()
end

-- Get current repair cost
function AutoRepair:GetRepairCost()
    if not CanMerchantRepair() then
        return 0, false
    end
    return GetRepairAllCost()
end
