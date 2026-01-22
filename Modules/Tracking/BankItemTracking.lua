--[[
    InventoryManager - Modules/Tracking/BankItemTracking.lua
    Tracks item deposits/withdrawals to/from personal bank and warband bank.

    DETECTION STRATEGY:
    - Snapshot bags when bank opens
    - Track BAG_UPDATE_DELAYED events while bank is open
    - On each BAG_UPDATE_DELAYED, re-snapshot and compare to detect changes in real-time
    - This catches transfers as they happen, not just on bank close

    @module Modules.Tracking.BankItemTracking
]]

local addonName, IM = ...

local BankItemTracking = {}
IM:RegisterModule("BankItemTracking", BankItemTracking)

-- Bag IDs (0-4 are regular bags, 5 is reagent bag)
local BAG_SLOTS = { 0, 1, 2, 3, 4, 5 }

-- State
local _bagSnapshot = {}
local _bankOpen = false
local _detectedBankType = nil  -- "personal" or "warband"
local _pendingUpdate = false
local _bagUpdateHandler = nil

-- Private helper: Create a snapshot of player bags
local function _SnapshotBags()
    local snapshot = {}

    for _, bagID in ipairs(BAG_SLOTS) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                local key = info.itemID
                snapshot[key] = snapshot[key] or { quantity = 0, link = info.hyperlink }
                snapshot[key].quantity = snapshot[key].quantity + (info.stackCount or 1)
            end
        end
    end

    return snapshot
end

-- Private helper: Compare two bag snapshots and return changes
local function _CompareBagSnapshots(before, after)
    local changes = {}

    -- Find items that decreased (went to bank)
    for itemID, beforeData in pairs(before) do
        local afterQty = after[itemID] and after[itemID].quantity or 0
        local diff = beforeData.quantity - afterQty
        if diff > 0 then
            table.insert(changes, {
                itemID = itemID,
                itemLink = beforeData.link,
                quantity = diff,
                direction = "deposit",
            })
        end
    end

    -- Find items that increased (came from bank)
    for itemID, afterData in pairs(after) do
        local beforeQty = before[itemID] and before[itemID].quantity or 0
        local diff = afterData.quantity - beforeQty
        if diff > 0 then
            table.insert(changes, {
                itemID = itemID,
                itemLink = afterData.link,
                quantity = diff,
                direction = "withdraw",
            })
        end
    end

    return changes
end

-- Private helper: Process detected changes
local function _ProcessChanges(changes)
    if #changes == 0 then
        return
    end

    local bankType = _detectedBankType or "personal"
    local isWarband = (bankType == "warband")
    local bankName = isWarband and "Warband Bank" or "Bank"

    IM:Debug("[BankItemTracking] Processing " .. #changes .. " changes, type=" .. bankType)

    for _, change in ipairs(changes) do
        local transType
        local actionWord

        if change.direction == "deposit" then
            transType = isWarband and "warbank_item_in" or "bank_deposit"
            actionWord = "deposited"
        else
            transType = isWarband and "warbank_item_out" or "bank_withdraw"
            actionWord = "withdrew"
        end

        IM:AddTransaction(transType, {
            itemID = change.itemID,
            itemLink = change.itemLink,
            quantity = change.quantity,
            value = 0,
            source = bankName,
        })

        -- User-visible confirmation
        local itemName = change.itemLink or ("Item #" .. change.itemID)
        IM:Print(bankName .. ": " .. actionWord .. " " .. itemName .. " x" .. change.quantity)
    end
end

-- Private helper: Handle bag updates while bank is open
local function _OnBagUpdate()
    if not _bankOpen then
        return
    end

    -- Debounce: Only process once per frame
    if _pendingUpdate then
        return
    end
    _pendingUpdate = true

    -- Delay slightly to let bag state settle
    C_Timer.After(0.1, function()
        _pendingUpdate = false

        if not _bankOpen then
            return
        end

        -- Take new snapshot
        local newSnapshot = _SnapshotBags()

        -- Compare with current snapshot
        local changes = _CompareBagSnapshots(_bagSnapshot, newSnapshot)

        -- Process any changes found
        if #changes > 0 then
            _ProcessChanges(changes)
        end

        -- Update snapshot to new state for next comparison
        _bagSnapshot = newSnapshot
    end)
end

function BankItemTracking:OnEnable()
    local module = self  -- Capture for closures

    IM:Debug("[BankItemTracking] Registering events")

    -- Create bag update handler
    _bagUpdateHandler = function()
        _OnBagUpdate()
    end

    -- PRIMARY: Use interaction manager events (most reliable, provides bank type immediately)
    if Enum and Enum.PlayerInteractionType then
        IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(event, interactionType)
            if interactionType == Enum.PlayerInteractionType.Banker then
                _detectedBankType = "personal"
                IM:Debug("[BankItemTracking] Personal bank opened")
                module:OnBankOpened()
            elseif interactionType == Enum.PlayerInteractionType.AccountBanker then
                _detectedBankType = "warband"
                IM:Debug("[BankItemTracking] Warband bank opened")
                module:OnBankOpened()
            end
        end)

        IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(event, interactionType)
            if interactionType == Enum.PlayerInteractionType.Banker or
               interactionType == Enum.PlayerInteractionType.AccountBanker then
                IM:Debug("[BankItemTracking] Bank closed (interaction manager)")
                module:OnBankClosed()
            end
        end)
    end

    -- FALLBACK: Also use BANKFRAME_OPENED (fires for both personal and warband)
    IM:RegisterEvent("BANKFRAME_OPENED", function()
        if not _bankOpen then
            -- Try to detect type
            if C_Bank and C_Bank.IsAccountBankPanelShown and C_Bank.IsAccountBankPanelShown() then
                _detectedBankType = "warband"
            else
                _detectedBankType = "personal"
            end
            IM:Debug("[BankItemTracking] Bank opened (fallback) - type=" .. tostring(_detectedBankType))
            module:OnBankOpened()
        end
    end)

    IM:RegisterEvent("BANKFRAME_CLOSED", function()
        if _bankOpen then
            IM:Debug("[BankItemTracking] Bank closed (fallback)")
            module:OnBankClosed()
        end
    end)

    IM:Debug("[BankItemTracking] Module enabled")
end

function BankItemTracking:OnBankOpened()
    if _bankOpen then
        return
    end

    _bankOpen = true

    -- Take initial snapshot
    _bagSnapshot = _SnapshotBags()

    -- Count for debug
    local itemCount = 0
    local totalQty = 0
    for _, data in pairs(_bagSnapshot) do
        itemCount = itemCount + 1
        totalQty = totalQty + data.quantity
    end
    IM:Debug("[BankItemTracking] Initial snapshot: " .. itemCount .. " unique items, " .. totalQty .. " total")

    -- Register for bag updates while bank is open
    IM:RegisterEvent("BAG_UPDATE_DELAYED", _bagUpdateHandler)
end

function BankItemTracking:OnBankClosed()
    if not _bankOpen then
        return
    end

    -- Unregister bag update handler
    if _bagUpdateHandler then
        IM:UnregisterEvent("BAG_UPDATE_DELAYED", _bagUpdateHandler)
    end

    _bankOpen = false
    _bagSnapshot = {}
    _detectedBankType = nil

    IM:Debug("[BankItemTracking] Bank closed, handler unregistered")
end

-- Debug helpers
function BankItemTracking:IsBankOpen()
    return _bankOpen
end

function BankItemTracking:GetBankType()
    return _detectedBankType
end
