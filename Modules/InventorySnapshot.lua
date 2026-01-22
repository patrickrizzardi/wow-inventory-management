--[[
    InventoryManager - Modules/InventorySnapshot.lua
    Cross-character inventory scanning and search functionality.

    Provides:
    - Automatic bag/bank/warband bank scanning
    - Per-character snapshot storage
    - Cross-character item search

    Events:
    - PLAYER_ENTERING_WORLD: Initial bag scan
    - BAG_UPDATE_DELAYED: Debounced bag rescan
    - BANKFRAME_OPENED: Personal bank scan
    - PLAYERBANKSLOTS_CHANGED: Bank slot changes
    - PLAYERREAGENTBANKSLOTS_CHANGED: Reagent bank changes
    - PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED: Warband bank changes

    @module Modules.InventorySnapshot
]]

local addonName, IM = ...

local InventorySnapshot = {}
IM:RegisterModule("InventorySnapshot", InventorySnapshot)

-- Bag IDs
local BANK_CONTAINER = -1  -- Bank container
local BANK_BAG_SLOTS = { 6, 7, 8, 9, 10, 11, 12 }  -- Bank bags
local REAGENT_BANK = -3  -- Reagent bank

-- Use shared bag scanning function from Filters.lua (includes reagent bag)
-- Falls back to basic 0-4 if not yet initialized
local function GetBagIDsToScan()
    if IM.GetBagIDsToScan then
        return IM:GetBagIDsToScan()
    end
    -- Fallback
    local bags = {}
    for i = 0, (NUM_BAG_SLOTS or 4) do
        table.insert(bags, i)
    end
    return bags
end

-- Debounce timers
local _bagScanPending = false
local _bankScanPending = false
local _warbandScanPending = false

-- Track if bank is currently open
local _bankOpen = false
local _warbankOpen = false

-- Store module reference for closures
local module

function InventorySnapshot:OnEnable()
    module = self

    IM:Debug("[InventorySnapshot] Module loading")

    -- Helper function to scan with retry
    local function TryScanWithRetry(attempt)
        attempt = attempt or 1
        local ok, success = pcall(function() return module:ScanBags() end)
        if not ok then
            IM:Debug("[InventorySnapshot] Scan error: " .. tostring(success))
            success = false
        end
        if not success and attempt < 5 then
            -- Retry with exponential backoff: 2s, 4s, 8s, 16s
            local delay = 2 ^ attempt
            IM:Debug("[InventorySnapshot] Scan attempt " .. attempt .. " failed, retrying in " .. delay .. "s")
            C_Timer.After(delay, function()
                TryScanWithRetry(attempt + 1)
            end)
        elseif success then
            IM:Debug("[InventorySnapshot] Scanned bags successfully (attempt " .. attempt .. ")")
        else
            IM:Debug("[InventorySnapshot] Failed after 5 attempts")
        end
    end

    -- Scan bags on login
    IM:RegisterEvent("PLAYER_ENTERING_WORLD", function(event, isInitialLogin, isReloadingUi)
        IM:Debug("[InventorySnapshot] PLAYER_ENTERING_WORLD fired, scheduling scan")
        C_Timer.After(2, function()
            TryScanWithRetry(1)
        end)
    end)

    -- Also do an immediate scan after a short delay (in case PLAYER_ENTERING_WORLD already fired)
    C_Timer.After(3, function()
        if module then
            IM:Debug("[InventorySnapshot] Running delayed startup scan")
            TryScanWithRetry(1)
        end
    end)

    -- Debounced bag updates
    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        module:QueueBagScan()
        -- Also scan bank if it's open (catches deposits/withdrawals)
        if _bankOpen then
            IM:Debug("[InventorySnapshot] Bag changed while bank open, scanning bank too")
            module:QueueBankScan()
        end
        if _warbankOpen then
            IM:Debug("[InventorySnapshot] Bag changed while warband bank open, scanning warband too")
            module:QueueWarbandScan()
        end
    end)

    -- Bank events
    IM:RegisterEvent("BANKFRAME_OPENED", function()
        _bankOpen = true
        IM:Debug("[InventorySnapshot] Bank opened")
        C_Timer.After(0.3, function()
            module:ScanBank()
            module:ScanReagentBank()
        end)
    end)

    IM:RegisterEvent("BANKFRAME_CLOSED", function()
        -- Bank is already closed by the time this fires, can't scan anymore
        -- Just reset state - actual scanning happens via BAG_UPDATE_DELAYED while bank was open
        IM:Debug("[InventorySnapshot] Bank closed")
        _bankOpen = false
        _warbankOpen = false
    end)

    IM:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function()
        IM:Debug("[InventorySnapshot] PLAYERBANKSLOTS_CHANGED fired")
        module:QueueBankScan()
    end)

    -- Modern interaction events for account bank detection
    if Enum and Enum.PlayerInteractionType then
        IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(event, interactionType)
            if interactionType == Enum.PlayerInteractionType.AccountBanker then
                _warbankOpen = true
                IM:Debug("[InventorySnapshot] Warband bank opened via interaction")
                C_Timer.After(0.3, function()
                    module:ScanWarbandBank()
                end)
            end
        end)

        IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(event, interactionType)
            if interactionType == Enum.PlayerInteractionType.AccountBanker then
                -- Bank is already closed by the time this fires
                -- Just reset state - actual scanning happens via BAG_UPDATE_DELAYED while bank was open
                IM:Debug("[InventorySnapshot] Warband bank closed")
                _warbankOpen = false
            end
        end)
    end

    -- Warband bank slot events (TWW feature)
    if C_Bank and C_Bank.FetchDepositedMoney then
        IM:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", function()
            IM:Debug("[InventorySnapshot] PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED fired")
            module:QueueWarbandScan()
        end)
    end

    IM:Debug("[InventorySnapshot] Module enabled")
end

-- Queue a debounced bag scan
function InventorySnapshot:QueueBagScan()
    if _bagScanPending then return end
    _bagScanPending = true

    C_Timer.After(1, function()
        _bagScanPending = false
        module:ScanBags()
    end)
end

-- Queue a debounced bank scan
function InventorySnapshot:QueueBankScan()
    if _bankScanPending then return end
    _bankScanPending = true

    C_Timer.After(0.5, function()
        _bankScanPending = false
        module:ScanBank()
        module:ScanReagentBank()
    end)
end

-- Queue a debounced warband bank scan
function InventorySnapshot:QueueWarbandScan()
    if _warbandScanPending then return end
    _warbandScanPending = true

    C_Timer.After(0.5, function()
        _warbandScanPending = false
        module:ScanWarbandBank()
    end)
end

-- Scan a single container and return items
local function ScanContainer(bagID, location)
    local items = {}
    local numSlots = C_Container.GetContainerNumSlots(bagID)

    for slotID = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if info and info.itemID then
            table.insert(items, {
                itemID = info.itemID,
                link = info.hyperlink,
                quantity = info.stackCount or 1,
                bagID = bagID,
                slotID = slotID,
                location = location,
            })
        end
    end

    return items
end

-- Scan player bags
-- Uses same bag scanning approach as auto-sell (Filters.lua)
function InventorySnapshot:ScanBags()
    -- Ensure data structure exists
    if not IM.db or not IM.db.global then
        IM:Debug("[InventorySnapshot] Database not ready, skipping scan")
        return false
    end
    if not IM.db.global.inventorySnapshots then
        IM.db.global.inventorySnapshots = {}
    end

    local charKey = IM:GetCharacterKey()
    if not charKey then
        IM:Debug("[InventorySnapshot] No character key, skipping scan")
        return false
    end

    local snapshot = IM.db.global.inventorySnapshots[charKey] or {}

    -- Use same bag scanning approach as auto-sell system
    local bagsToScan = GetBagIDsToScan()
    local items = {}
    local totalSlots = 0

    for _, bagID in ipairs(bagsToScan) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        totalSlots = totalSlots + numSlots

        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                table.insert(items, {
                    itemID = info.itemID,
                    link = info.hyperlink,
                    quantity = info.stackCount or 1,
                    bagID = bagID,
                    slotID = slotID,
                    location = "bags",
                })
            end
        end
    end

    snapshot.bags = items
    snapshot.timestamp = time()

    IM.db.global.inventorySnapshots[charKey] = snapshot
    IM:Debug("[InventorySnapshot] Scanned " .. #bagsToScan .. " bags (" .. totalSlots .. " slots) for " .. charKey .. ": " .. #items .. " items")
    return true
end

-- Scan personal bank
function InventorySnapshot:ScanBank()
    if not IM.db or not IM.db.global then return end
    if not IM.db.global.inventorySnapshots then
        IM.db.global.inventorySnapshots = {}
    end

    local charKey = IM:GetCharacterKey()
    if not charKey then return end

    local snapshot = IM.db.global.inventorySnapshots[charKey] or {}

    local items = {}

    -- Main bank slots
    local bankItems = ScanContainer(BANK_CONTAINER, "bank")
    for _, item in ipairs(bankItems) do
        table.insert(items, item)
    end

    -- Bank bags
    for _, bagID in ipairs(BANK_BAG_SLOTS) do
        local bagItems = ScanContainer(bagID, "bank")
        for _, item in ipairs(bagItems) do
            table.insert(items, item)
        end
    end

    snapshot.bank = items
    snapshot.bankTimestamp = time()

    IM.db.global.inventorySnapshots[charKey] = snapshot

    IM:Debug("[InventorySnapshot] Scanned bank: " .. #items .. " items")
end

-- Scan reagent bank
function InventorySnapshot:ScanReagentBank()
    if not IM.db or not IM.db.global then return end
    if not IM.db.global.inventorySnapshots then
        IM.db.global.inventorySnapshots = {}
    end

    local charKey = IM:GetCharacterKey()
    if not charKey then return end

    local snapshot = IM.db.global.inventorySnapshots[charKey] or {}

    local items = ScanContainer(REAGENT_BANK, "reagentBank")

    snapshot.reagentBank = items
    snapshot.reagentBankTimestamp = time()

    IM.db.global.inventorySnapshots[charKey] = snapshot

    IM:Debug("[InventorySnapshot] Scanned reagent bank: " .. #items .. " items")
end

-- Scan warband (account) bank
function InventorySnapshot:ScanWarbandBank()
    if not C_Bank or not C_Bank.FetchPurchasedBankTabIDs then
        IM:Debug("[InventorySnapshot] Warband bank API not available")
        return
    end

    if not IM.db or not IM.db.global then return end

    local items = {}
    local tabIDs = C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)

    if tabIDs then
        local SLOTS_PER_TAB = 98  -- Account bank tabs have 98 slots
        for _, tabID in ipairs(tabIDs) do
            -- Scan each slot in the tab
            for slotID = 1, SLOTS_PER_TAB do
                local info = C_Container.GetContainerItemInfo(tabID, slotID)
                if info and info.itemID then
                    table.insert(items, {
                        itemID = info.itemID,
                        link = info.hyperlink,
                        quantity = info.stackCount or 1,
                        tabID = tabID,
                        slotID = slotID,
                        location = "warbandBank",
                    })
                end
            end
        end
    end

    IM.db.global.warbandBankInventory = {
        timestamp = time(),
        items = items,
    }

    IM:Debug("[InventorySnapshot] Scanned warband bank: " .. #items .. " items")
end

-- Get all items across all characters matching filters
-- filters: { search, character, location }
function InventorySnapshot:SearchItems(filters)
    filters = filters or {}
    local results = {}
    local searchLower = filters.search and filters.search:lower() or nil

    -- Search character inventories
    for charKey, snapshot in pairs(IM.db.global.inventorySnapshots) do
        -- Filter by character
        if not filters.character or filters.character == charKey then
            -- Search bags
            if snapshot.bags and (not filters.location or filters.location == "bags") then
                for _, item in ipairs(snapshot.bags) do
                    if self:ItemMatchesSearch(item, searchLower) then
                        local result = self:CreateSearchResult(item, charKey)
                        table.insert(results, result)
                    end
                end
            end

            -- Search bank
            if snapshot.bank and (not filters.location or filters.location == "bank") then
                for _, item in ipairs(snapshot.bank) do
                    if self:ItemMatchesSearch(item, searchLower) then
                        local result = self:CreateSearchResult(item, charKey)
                        table.insert(results, result)
                    end
                end
            end

            -- Search reagent bank
            if snapshot.reagentBank and (not filters.location or filters.location == "reagentBank") then
                for _, item in ipairs(snapshot.reagentBank) do
                    if self:ItemMatchesSearch(item, searchLower) then
                        local result = self:CreateSearchResult(item, charKey)
                        table.insert(results, result)
                    end
                end
            end
        end
    end

    -- Search warband bank
    if not filters.character or filters.character == "warband" then
        if not filters.location or filters.location == "warbandBank" then
            local warbandData = IM.db.global.warbandBankInventory
            if warbandData and warbandData.items then
                for _, item in ipairs(warbandData.items) do
                    if self:ItemMatchesSearch(item, searchLower) then
                        local result = self:CreateSearchResult(item, "Warband Bank")
                        table.insert(results, result)
                    end
                end
            end
        end
    end

    -- Sort by item name (from link)
    table.sort(results, function(a, b)
        local nameA = a.itemName or ""
        local nameB = b.itemName or ""
        return nameA < nameB
    end)

    return results
end

-- Check if item matches search text
function InventorySnapshot:ItemMatchesSearch(item, searchLower)
    if not searchLower or searchLower == "" then
        return true
    end

    -- Search in item link (contains name)
    if item.link then
        local linkLower = item.link:lower()
        if linkLower:find(searchLower, 1, true) then
            return true
        end
    end

    return false
end

-- Create a search result entry
function InventorySnapshot:CreateSearchResult(item, charKey)
    -- Parse item name from link
    local itemName = ""
    if item.link then
        itemName = item.link:match("%[(.-)%]") or ""
    end

    -- Parse character name from key
    local charName = charKey
    local charRealm = ""
    local charClass = nil

    if charKey ~= "Warband Bank" then
        charName = charKey:match("^(.+)-") or charKey
        charRealm = charKey:match("-(.+)$") or ""

        -- Get class from character data
        local charData = IM.db.global.characters[charKey]
        if charData then
            charClass = charData.class
        end
    end

    -- Get location label
    local locationLabel = "Bags"
    if item.location == "bank" then
        locationLabel = "Bank"
    elseif item.location == "reagentBank" then
        locationLabel = "Reagent Bank"
    elseif item.location == "warbandBank" then
        locationLabel = "Warband Bank"
    end

    return {
        itemID = item.itemID,
        itemLink = item.link,
        itemName = itemName,
        quantity = item.quantity,
        bagID = item.bagID,
        slotID = item.slotID,
        location = item.location,
        locationLabel = locationLabel,
        charKey = charKey,
        charName = charName,
        charRealm = charRealm,
        charClass = charClass,
    }
end

-- Get list of characters with snapshots
function InventorySnapshot:GetCharactersWithSnapshots()
    local chars = {}

    for charKey, snapshot in pairs(IM.db.global.inventorySnapshots) do
        local charName = charKey:match("^(.+)-") or charKey
        local charData = IM.db.global.characters[charKey]

        table.insert(chars, {
            key = charKey,
            name = charName,
            class = charData and charData.class,
            timestamp = snapshot.timestamp or 0,
            bagCount = snapshot.bags and #snapshot.bags or 0,
            bankCount = snapshot.bank and #snapshot.bank or 0,
        })
    end

    -- Sort by last update
    table.sort(chars, function(a, b)
        return a.timestamp > b.timestamp
    end)

    return chars
end

-- Get total item count for a character
function InventorySnapshot:GetItemCount(charKey, itemID)
    local count = 0
    local snapshot = IM.db.global.inventorySnapshots[charKey]

    if not snapshot then return 0 end

    -- Check bags
    if snapshot.bags then
        for _, item in ipairs(snapshot.bags) do
            if item.itemID == itemID then
                count = count + item.quantity
            end
        end
    end

    -- Check bank
    if snapshot.bank then
        for _, item in ipairs(snapshot.bank) do
            if item.itemID == itemID then
                count = count + item.quantity
            end
        end
    end

    -- Check reagent bank
    if snapshot.reagentBank then
        for _, item in ipairs(snapshot.reagentBank) do
            if item.itemID == itemID then
                count = count + item.quantity
            end
        end
    end

    return count
end

-- Get total count of an item across all characters
function InventorySnapshot:GetTotalItemCount(itemID)
    local count = 0

    for charKey, _ in pairs(IM.db.global.inventorySnapshots) do
        count = count + self:GetItemCount(charKey, itemID)
    end

    -- Also check warband bank
    local warbandData = IM.db.global.warbandBankInventory
    if warbandData and warbandData.items then
        for _, item in ipairs(warbandData.items) do
            if item.itemID == itemID then
                count = count + item.quantity
            end
        end
    end

    return count
end

-- Force rescan of current character
function InventorySnapshot:RescanCurrentCharacter()
    self:ScanBags()
    IM:Debug("[InventorySnapshot] Forced rescan of bags")
end
