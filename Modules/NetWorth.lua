--[[
    InventoryManager - Modules/NetWorth.lua
    Character and account-wide net worth tracking.

    Features:
    - Gold balance snapshots on login/logout
    - Inventory valuation (bags + bank)
    - Account-wide aggregation
    - Faction/realm grouping

    @module Modules.NetWorth
]]

local addonName, IM = ...

local NetWorth = {}
IM:RegisterModule("NetWorth", NetWorth)

-- Cache for inventory valuation
local _inventoryCache = nil
local _inventoryCacheTime = 0
local CACHE_TTL = 300 -- 5 minute cache

function NetWorth:OnEnable()
    IM:Debug("[NetWorth] OnEnable called")

    -- Debounce timer for UI refresh (avoid spamming on rapid changes)
    local uiRefreshPending = false
    local function QueueUIRefresh()
        if not uiRefreshPending then
            uiRefreshPending = true
            C_Timer.After(0.3, function()
                uiRefreshPending = false
                if IM.RefreshAllUI then
                    IM:RefreshAllUI()
                end
            end)
        end
    end

    -- Update character data on login
    IM:RegisterEvent("PLAYER_ENTERING_WORLD", function(event, isInitialLogin, isReloadingUi)
        self:OnPlayerLogin(isInitialLogin)
    end)

    -- Update on any gold change (looting, selling, mail, etc.)
    IM:RegisterEvent("PLAYER_MONEY", function()
        C_Timer.After(0.1, function()
            IM:UpdateCharacterGold()
            self:InvalidateInventoryCache()
            self:UpdateInventoryValue(false) -- Recalculate inventory (items sold = less inventory)
            QueueUIRefresh()
        end)
    end)

    -- Update on logout (if possible)
    IM:RegisterEvent("PLAYER_LOGOUT", function()
        self:OnPlayerLogout()
    end)

    -- Also save on leaving world (character switch, disconnect, etc.)
    IM:RegisterEvent("PLAYER_LEAVING_WORLD", function()
        IM:UpdateCharacterGold()
        IM:Debug("[NetWorth] PLAYER_LEAVING_WORLD - gold saved")
    end)

    -- Update when bags change (debounced)
    local bagUpdatePending = false
    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        if not bagUpdatePending then
            bagUpdatePending = true
            C_Timer.After(1, function()
                bagUpdatePending = false
                self:InvalidateInventoryCache()
                self:UpdateInventoryValue(false)
                QueueUIRefresh()
            end)
        end
    end)

    -- Update when bank opens (can now scan bank and warband gold)
    IM:RegisterEvent("BANKFRAME_OPENED", function()
        C_Timer.After(0.5, function()
            self:UpdateInventoryValue(true) -- Include bank
            self:UpdateWarbandBankGold()
            QueueUIRefresh()
        end)
    end)

    -- Update when account/warbound bank tab changes
    IM:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", function()
        C_Timer.After(0.5, function()
            self:UpdateInventoryValue(true)
            self:UpdateWarbandBankGold()
            QueueUIRefresh()
        end)
    end)

    -- Track warband bank gold changes (deposit/withdraw)
    if C_Bank and C_Bank.FetchDepositedMoney then
        -- ACCOUNT_MONEY fires when warband bank gold changes
        IM:RegisterEvent("ACCOUNT_MONEY", function()
            C_Timer.After(0.2, function()
                self:UpdateWarbandBankGold()
                QueueUIRefresh()
            end)
        end)
    end

    IM:Debug("[NetWorth] Module enabled")
end

-- Called on player login
function NetWorth:OnPlayerLogin(isInitialLogin)
    -- Ensure character data exists and is updated
    local charData = IM:GetCharacterData()

    -- Delay gold capture to ensure GetMoney() returns valid value
    -- 2 seconds is safer than 0.5s for heavy addon loads
    C_Timer.After(2, function()
        IM:UpdateCharacterGold()
        IM:Debug("[NetWorth] Gold updated: " .. GetMoney())
    end)

    if isInitialLogin then
        -- Initial inventory scan (bags only, bank not accessible yet)
        C_Timer.After(2, function()
            self:UpdateInventoryValue(false)
        end)
        IM:Debug("[NetWorth] Initial login - character data updated")
    end
end

-- Called on logout
function NetWorth:OnPlayerLogout()
    -- Final gold snapshot
    IM:UpdateCharacterGold()
    IM:Debug("[NetWorth] Logout - final snapshot saved")
end

-- Invalidate inventory cache
function NetWorth:InvalidateInventoryCache()
    _inventoryCache = nil
    _inventoryCacheTime = 0
end

-- Calculate inventory value (vendor prices)
-- @param includeBank boolean - Whether to include bank bags
-- @return number - Total value in copper
function NetWorth:CalculateInventoryValue(includeBank)
    local totalValue = 0
    local itemCount = 0

    -- Scan all bags including reagent bag
    for _, bagID in ipairs(IM:GetBagIDsToScan()) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                local sellPrice = select(11, GetItemInfo(info.itemID)) or 0
                local stackValue = sellPrice * (info.stackCount or 1)
                totalValue = totalValue + stackValue
                itemCount = itemCount + 1
            end
        end
    end

    -- Scan reagent bag if exists (bag 5 in retail)
    if C_Container.GetContainerNumSlots(5) then
        local numSlots = C_Container.GetContainerNumSlots(5)
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(5, slotID)
            if info and info.itemID then
                local sellPrice = select(11, GetItemInfo(info.itemID)) or 0
                local stackValue = sellPrice * (info.stackCount or 1)
                totalValue = totalValue + stackValue
                itemCount = itemCount + 1
            end
        end
    end

    -- Scan bank if requested and available
    if includeBank and BankFrame and BankFrame:IsShown() then
        -- Main bank slots (bag -1 in API)
        local bankBagID = -1
        local numSlots = C_Container.GetContainerNumSlots(bankBagID)
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bankBagID, slotID)
            if info and info.itemID then
                local sellPrice = select(11, GetItemInfo(info.itemID)) or 0
                local stackValue = sellPrice * (info.stackCount or 1)
                totalValue = totalValue + stackValue
                itemCount = itemCount + 1
            end
        end

        -- Bank bags (6-12 in retail)
        local numBankBagSlots = NUM_BANKBAGSLOTS or 7 -- Fallback if not defined
        for bagID = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + numBankBagSlots do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            for slotID = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bagID, slotID)
                if info and info.itemID then
                    local sellPrice = select(11, GetItemInfo(info.itemID)) or 0
                    local stackValue = sellPrice * (info.stackCount or 1)
                    totalValue = totalValue + stackValue
                    itemCount = itemCount + 1
                end
            end
        end

        -- Reagent bank if available
        if IsReagentBankUnlocked and IsReagentBankUnlocked() then
            local reagentBankID = -3 -- Reagent bank container ID
            local numSlots = C_Container.GetContainerNumSlots(reagentBankID)
            if numSlots then
                for slotID = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(reagentBankID, slotID)
                    if info and info.itemID then
                        local sellPrice = select(11, GetItemInfo(info.itemID)) or 0
                        local stackValue = sellPrice * (info.stackCount or 1)
                        totalValue = totalValue + stackValue
                        itemCount = itemCount + 1
                    end
                end
            end
        end

        -- Warbound/Account Bank tabs (TWW feature)
        if Enum and Enum.BagIndex and Enum.BagIndex.AccountBankTab_1 then
            for tabIndex = 1, 5 do
                local tabBagID = Enum.BagIndex["AccountBankTab_" .. tabIndex]
                if tabBagID then
                    local numSlots = C_Container.GetContainerNumSlots(tabBagID)
                    if numSlots and numSlots > 0 then
                        for slotID = 1, numSlots do
                            local info = C_Container.GetContainerItemInfo(tabBagID, slotID)
                            if info and info.itemID then
                                local sellPrice = select(11, GetItemInfo(info.itemID)) or 0
                                local stackValue = sellPrice * (info.stackCount or 1)
                                totalValue = totalValue + stackValue
                                itemCount = itemCount + 1
                            end
                        end
                    end
                end
            end
        end
    end

    IM:Debug("[NetWorth] Inventory scan: " .. itemCount .. " items, " .. IM:FormatMoney(totalValue))
    return totalValue, itemCount
end

-- Update inventory value and save to character data
function NetWorth:UpdateInventoryValue(includeBank)
    local value, count = self:CalculateInventoryValue(includeBank)

    local charData = IM:GetCharacterData()
    charData.inventoryValue = value
    charData.lastInventoryUpdate = time()

    -- Update cache
    _inventoryCache = value
    _inventoryCacheTime = time()

    IM:Debug("[NetWorth] Updated inventory value: " .. IM:FormatMoney(value))
    return value
end

-- Get current character's inventory value (cached)
function NetWorth:GetInventoryValue()
    -- Check cache
    if _inventoryCache and (time() - _inventoryCacheTime) < CACHE_TTL then
        return _inventoryCache
    end

    -- Recalculate
    return self:UpdateInventoryValue(false)
end

-- Get current character's net worth (gold + inventory)
function NetWorth:GetCharacterNetWorth()
    local gold = GetMoney()
    local inventory = self:GetInventoryValue()
    return gold + inventory
end

-- Get net worth breakdown for all characters
function NetWorth:GetAccountBreakdown()
    local breakdown = {
        total = {
            gold = 0,
            inventory = 0,
            netWorth = 0,
        },
        warbandBank = {
            gold = IM:GetWarbandBankGold(),
            lastUpdated = IM:GetWarbandBankGoldUpdated(),
        },
        factions = {},
        realms = {},
        characters = {},
    }

    for charKey, data in pairs(IM.db.global.characters) do
        local name = charKey:match("^(.+)-") or charKey
        local realm = charKey:match("-(.+)$") or "Unknown"
        local faction = data.faction or "Unknown"

        local charGold = data.gold or 0
        local charInventory = data.inventoryValue or 0
        local charNetWorth = charGold + charInventory

        -- Add to totals
        breakdown.total.gold = breakdown.total.gold + charGold
        breakdown.total.inventory = breakdown.total.inventory + charInventory
        breakdown.total.netWorth = breakdown.total.netWorth + charNetWorth

        -- Add to faction breakdown
        if not breakdown.factions[faction] then
            breakdown.factions[faction] = {
                gold = 0,
                inventory = 0,
                netWorth = 0,
                realms = {},
            }
        end
        breakdown.factions[faction].gold = breakdown.factions[faction].gold + charGold
        breakdown.factions[faction].inventory = breakdown.factions[faction].inventory + charInventory
        breakdown.factions[faction].netWorth = breakdown.factions[faction].netWorth + charNetWorth

        -- Add to realm breakdown (within faction)
        if not breakdown.factions[faction].realms[realm] then
            breakdown.factions[faction].realms[realm] = {
                gold = 0,
                inventory = 0,
                netWorth = 0,
                characters = {},
            }
        end
        breakdown.factions[faction].realms[realm].gold = breakdown.factions[faction].realms[realm].gold + charGold
        breakdown.factions[faction].realms[realm].inventory = breakdown.factions[faction].realms[realm].inventory + charInventory
        breakdown.factions[faction].realms[realm].netWorth = breakdown.factions[faction].realms[realm].netWorth + charNetWorth

        -- Add character data
        local charInfo = {
            key = charKey,
            name = name,
            realm = realm,
            faction = faction,
            class = data.class,
            level = data.level,
            gold = charGold,
            inventory = charInventory,
            netWorth = charNetWorth,
            lastSeen = data.lastSeen,
        }
        table.insert(breakdown.factions[faction].realms[realm].characters, charInfo)
        table.insert(breakdown.characters, charInfo)
    end

    -- Sort characters by net worth (descending)
    table.sort(breakdown.characters, function(a, b)
        return a.netWorth > b.netWorth
    end)

    -- Sort characters within each realm
    for _, factionData in pairs(breakdown.factions) do
        for _, realmData in pairs(factionData.realms) do
            table.sort(realmData.characters, function(a, b)
                return a.netWorth > b.netWorth
            end)
        end
    end

    -- Add warband bank gold to total
    breakdown.total.netWorth = breakdown.total.netWorth + breakdown.warbandBank.gold

    return breakdown
end

-- Get formatted summary string
function NetWorth:GetSummaryString()
    local breakdown = self:GetAccountBreakdown()
    return string.format("Account Net Worth: %s (%s gold + %s inventory)",
        IM:FormatMoney(breakdown.total.netWorth),
        IM:FormatMoney(breakdown.total.gold),
        IM:FormatMoney(breakdown.total.inventory)
    )
end

-- Force refresh all data for current character
function NetWorth:RefreshCurrentCharacter()
    IM:UpdateCharacterGold()
    self:UpdateInventoryValue(BankFrame and BankFrame:IsShown())
end

-- Update Warband Bank gold from API (requires bank to be open)
function NetWorth:UpdateWarbandBankGold()
    -- C_Bank.FetchDepositedMoney(Enum.BankType.Account) returns warband gold in copper
    if C_Bank and C_Bank.FetchDepositedMoney and Enum and Enum.BankType and Enum.BankType.Account then
        local warbandGold = C_Bank.FetchDepositedMoney(Enum.BankType.Account)
        if warbandGold and warbandGold >= 0 then
            local oldValue = IM:GetWarbandBankGold()
            IM:SetWarbandBankGold(warbandGold)
            if warbandGold ~= oldValue then
                IM:Debug("[NetWorth] Warband Bank gold updated: " .. IM:FormatMoney(warbandGold))
            end
            return warbandGold
        end
    end
    return nil
end

-- Get Warband Bank gold (returns cached value, updated when bank is opened)
function NetWorth:GetWarbandBankGold()
    return IM:GetWarbandBankGold()
end
