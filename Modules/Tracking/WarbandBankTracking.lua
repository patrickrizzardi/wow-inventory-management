--[[
    InventoryManager - Modules/Tracking/WarbandBankTracking.lua
    Tracks gold deposits/withdrawals to/from warband (account) bank.

    Events:
    - ACCOUNT_MONEY: Fires when warband bank gold changes

    @module Modules.Tracking.WarbandBankTracking
]]

local addonName, IM = ...

local WarbandBankTracking = {}
IM:RegisterModule("WarbandBankTracking", WarbandBankTracking)

-- State tracking
local _lastWarbandGold = nil
local _initialized = false

function WarbandBankTracking:OnEnable()
    -- Store module reference for use in closures
    local module = self

    -- Skip if warband tracking disabled
    if not IM.db or not IM.db.global or not IM.db.global.ledger then
        IM:Debug("[WarbandBankTracking] Database not ready")
        return
    end

    if not IM.db.global.ledger.trackWarbank then
        IM:Debug("[WarbandBankTracking] Disabled in settings")
        return
    end

    -- Check if C_Bank API is available (TWW feature)
    if not C_Bank then
        IM:Debug("[WarbandBankTracking] C_Bank not available")
        return
    end

    if not C_Bank.FetchDepositedMoney then
        IM:Debug("[WarbandBankTracking] C_Bank.FetchDepositedMoney not available")
        return
    end

    IM:Debug("[WarbandBankTracking] Registering events")

    -- Initialize with current warband gold
    _lastWarbandGold = IM:GetWarbandBankGold() or 0

    -- Track warband bank gold changes
    IM:RegisterEvent("ACCOUNT_MONEY", function()
        module:OnAccountMoneyChanged()
    end)

    -- Also initialize on bank open
    IM:RegisterEvent("BANKFRAME_OPENED", function()
        C_Timer.After(0.3, function()
            module:InitializeWarbandGold()
        end)
    end)

    -- Initialize now as well (in case bank was already opened before)
    module:InitializeWarbandGold()

    _initialized = true
    IM:Debug("[WarbandBankTracking] Module enabled")
end

-- Initialize warband gold reference
function WarbandBankTracking:InitializeWarbandGold()
    if C_Bank and C_Bank.FetchDepositedMoney and Enum and Enum.BankType then
        local currentGold = C_Bank.FetchDepositedMoney(Enum.BankType.Account)
        if currentGold and currentGold >= 0 then
            _lastWarbandGold = currentGold
            -- Save to database for Net Worth tracking
            IM:SetWarbandBankGold(currentGold)
            IM:Debug("[WarbandBankTracking] Initialized warband gold: " .. IM:FormatMoney(currentGold))
        end
    end
end

-- Handle warband bank gold changes
function WarbandBankTracking:OnAccountMoneyChanged()
    if not C_Bank or not C_Bank.FetchDepositedMoney or not Enum or not Enum.BankType then
        IM:Debug("[WarbandBankTracking] Missing API in OnAccountMoneyChanged")
        return
    end

    local currentGold = C_Bank.FetchDepositedMoney(Enum.BankType.Account)

    if not currentGold or currentGold < 0 then
        IM:Debug("[WarbandBankTracking] Invalid gold value")
        return
    end

    -- Calculate delta
    local previousGold = _lastWarbandGold or 0
    local delta = currentGold - previousGold

    -- Update reference and save to database
    _lastWarbandGold = currentGold
    IM:SetWarbandBankGold(currentGold)
    
    -- CRITICAL: Update character gold since PLAYER_MONEY might not fire for warband transactions
    IM:UpdateCharacterGold()

    -- Skip if no meaningful change
    if math.abs(delta) < 1 then
        return
    end

    IM:Debug("[WarbandBankTracking] Gold changed: " .. previousGold .. " -> " .. currentGold .. " (delta: " .. delta .. ")")

    if delta > 0 then
        -- Deposit (player put gold INTO warband bank)
        -- From character's perspective, this is an expense
        IM:AddTransaction("warbank_deposit", {
            value = -delta, -- Negative = expense for character
            source = "Warband Bank",
        })
        IM:Debug("[WarbandBankTracking] Deposited: " .. IM:FormatMoney(delta))
    else
        -- Withdrawal (player took gold FROM warband bank)
        -- From character's perspective, this is income
        IM:AddTransaction("warbank_withdraw", {
            value = math.abs(delta), -- Positive = income for character
            source = "Warband Bank",
        })
        IM:Debug("[WarbandBankTracking] Withdrew: " .. IM:FormatMoney(math.abs(delta)))
    end
end

-- Get last known warband gold
function WarbandBankTracking:GetLastWarbandGold()
    return _lastWarbandGold or 0
end

-- Check if at warband bank (for unclaimed gold tracking)
function WarbandBankTracking:IsAtWarbandBank()
    -- Warband bank uses BANKFRAME_OPENED which sets a state
    -- However, we don't have a dedicated _atWarbandBank flag
    -- Since ACCOUNT_MONEY fires regardless of context, we return false
    -- The ACCOUNT_MONEY event handles its own tracking
    return false
end
