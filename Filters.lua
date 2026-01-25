--[[
    InventoryManager - Filters.lua
    Central filter evaluation logic for auto-sell
]]

local addonName, IM = ...

local Filters = {}
IM.Filters = Filters

-- ============================================================================
-- ITEM INFO CACHE (Performance optimization - Issue #6)
-- Caches GetItemInfo results with TTL to avoid redundant API calls
-- ============================================================================
local itemInfoCache = {}
local CACHE_TTL = 5 -- seconds

--[[
    Get cached item info, or fetch and cache if needed.
    Private helper for performance optimization.

    @param itemID number - The item ID to fetch info for
    @return ... - Multiple values from GetItemInfo (itemName, itemLink, quality, etc.)
    @private
]]
local function _GetCachedItemInfo(itemID)
    local now = GetTime()
    local cached = itemInfoCache[itemID]

    if cached and (now - cached.timestamp) < CACHE_TTL then
        return unpack(cached.data)
    end

    local data = {GetItemInfo(itemID)}
    if data[1] then -- itemName exists = valid data
        itemInfoCache[itemID] = {
            data = data,
            timestamp = now
        }
    end

    return unpack(data)
end

-- Clear expired cache entries periodically (every 30 seconds)
C_Timer.NewTicker(30, function()
    local now = GetTime()
    local expiredKeys = {}
    for itemID, entry in pairs(itemInfoCache) do
        if (now - entry.timestamp) > CACHE_TTL * 2 then
            table.insert(expiredKeys, itemID)
        end
    end
    for _, key in ipairs(expiredKeys) do
        itemInfoCache[key] = nil
    end
end)

-- Export for other modules to use (maintain public API)
IM.GetCachedItemInfo = _GetCachedItemInfo

-- Category classID mappings (from GetItemInfo)
-- Reference: https://wowpedia.fandom.com/wiki/ItemType
local ITEM_CLASS = {
    CONSUMABLE = 0,
    CONTAINER = 1,
    WEAPON = 2,
    GEM = 3,
    ARMOR = 4,
    REAGENT = 5,
    PROJECTILE = 6,
    TRADESKILL = 7,
    ITEM_ENHANCEMENT = 8,
    RECIPE = 9,
    KEY = 10,
    QUEST = 12,
    MISCELLANEOUS = 15,
    GLYPH = 16,
    BATTLEPET = 17,
}

-- Export ITEM_CLASS for tooltip use
IM.ITEM_CLASS = ITEM_CLASS

-- Category name lookup for tooltips
local ITEM_CLASS_NAMES = {
    [0] = "Consumable",
    [1] = "Container",
    [2] = "Weapon",
    [3] = "Gem",
    [4] = "Armor",
    [5] = "Crafting Reagent",
    [6] = "Projectile",
    [7] = "Trade Goods",
    [8] = "Item Enhancement",
    [9] = "Recipe",
    [10] = "Key",
    [12] = "Quest Item",
    [15] = "Miscellaneous",
    [16] = "Glyph",
    [17] = "Battle Pet",
}
IM.ITEM_CLASS_NAMES = ITEM_CLASS_NAMES

-- Miscellaneous subclasses for token detection
local MISC_SUBCLASS = {
    JUNK = 0,       -- Gray junk, but also some tokens
    REAGENT = 1,    -- Reagents
    COMPANION = 2,  -- Companion pets
    HOLIDAY = 3,    -- Holiday items
    OTHER = 4,      -- Tokens, currency items
    MOUNT = 5,      -- Mount items
}
IM.MISC_SUBCLASS = MISC_SUBCLASS

-- Cache for equipment set item IDs
local equipmentSetItems = {}
local equipmentSetItemToSets = {}  -- Maps itemID -> array of set names
local equipmentSetCacheDirty = true
local equipmentSetLastRefresh = 0
local EQUIPMENT_SET_THROTTLE = 0.5 -- seconds

-- Refresh equipment set cache (throttled)
local function _RefreshEquipmentSetCache()
    local now = GetTime()
    if now - equipmentSetLastRefresh < EQUIPMENT_SET_THROTTLE then
        -- Too soon, skip this refresh (will be marked dirty for later)
        return
    end
    equipmentSetLastRefresh = now

    wipe(equipmentSetItems)
    wipe(equipmentSetItemToSets)

    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
    local totalItems = 0
    for _, setID in ipairs(setIDs) do
        local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
        local itemIDs = C_EquipmentSet.GetItemIDs(setID)
        if itemIDs and setName then
            for _, itemID in pairs(itemIDs) do
                if itemID and itemID > 0 then
                    equipmentSetItems[itemID] = true
                    
                    -- Track which sets this item belongs to
                    if not equipmentSetItemToSets[itemID] then
                        equipmentSetItemToSets[itemID] = {}
                    end
                    table.insert(equipmentSetItemToSets[itemID], setName)
                    
                    totalItems = totalItems + 1
                end
            end
        end
    end

    equipmentSetCacheDirty = false
    IM:Debug("[Filters] Equipment set cache refreshed, " .. #setIDs .. " sets, " .. totalItems .. " items")
end

-- Listen for equipment set changes
IM:RegisterEvent("EQUIPMENT_SETS_CHANGED", function()
    equipmentSetCacheDirty = true
end)

-- Check if item is in any equipment set
function Filters:IsInEquipmentSet(itemID)
    if equipmentSetCacheDirty then
        _RefreshEquipmentSetCache()
    end
    return equipmentSetItems[itemID] == true
end

-- Get which equipment set(s) an item belongs to
-- @param itemID number - The item ID to check
-- @return table|nil - Array of set names, or nil if not in any set
function Filters:GetEquipmentSets(itemID)
    if equipmentSetCacheDirty then
        _RefreshEquipmentSetCache()
    end
    return equipmentSetItemToSets[itemID]
end

-- Check if item is protected by quality (heirloom, legendary, artifact)
function Filters:IsProtectedByQuality(quality)
    return quality >= IM.QUALITY_LEGENDARY or quality == IM.QUALITY_HEIRLOOM
end

-- Check if item is a toy (uses C_ToyBox API, not classID)
function Filters:IsToy(itemID)
    if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo then
        return false
    end
    -- GetToyInfo returns itemID, toyName, icon, isFavorite, hasFanfare, quality if it's a toy
    -- Returns nil if not a toy
    local success, toyItemID = pcall(C_ToyBox.GetToyInfo, itemID)
    if not success then
        return false
    end
    return toyItemID ~= nil and toyItemID > 0
end

-- Check if item is a mount (uses C_MountJournal API)
function Filters:IsMount(itemID)
    if not itemID or not C_MountJournal or not C_MountJournal.GetMountFromItem then
        return false
    end
    local success, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
    if not success then
        return false
    end
    return mountID ~= nil and mountID > 0
end

-- Check if item is a caged battle pet (uses C_PetJournal API)
function Filters:IsCagedPet(itemID)
    if not itemID or not C_PetJournal then
        return false
    end
    -- Caged pets have a specific pattern - check if it's a battle pet cage
    -- Battle pet cages are itemID 82800, but the actual pet data is in the item's hyperlink
    -- For now, check if the item is the standard pet cage
    return itemID == 82800
end

-- Check if item is excluded by category
-- Optimized order: cheap classID checks first, then expensive API calls
function Filters:IsExcludedByCategory(classID, subclassID, itemID)
    local db = IM.db.global.categoryExclusions

    -- TIER 1: Fast classID-based checks (simple number comparisons)

    -- Consumables (classID 0)
    if classID == ITEM_CLASS.CONSUMABLE and db.consumables then
        IM:Debug("[Filters] IsExcludedByCategory: Matched CONSUMABLE (classID 0)")
        return true
    end

    -- Quest items (classID 12)
    if classID == ITEM_CLASS.QUEST and db.questItems then
        IM:Debug("[Filters] IsExcludedByCategory: Matched QUEST ITEM (classID 12)")
        return true
    end

    -- Crafting reagents (classID 5)
    if classID == ITEM_CLASS.REAGENT and db.craftingReagents then
        IM:Debug("[Filters] IsExcludedByCategory: Matched CRAFTING REAGENT (classID 5)")
        return true
    end

    -- Trade goods (classID 7)
    if classID == ITEM_CLASS.TRADESKILL and db.tradeGoods then
        IM:Debug("[Filters] IsExcludedByCategory: Matched TRADE GOODS (classID 7)")
        return true
    end

    -- Recipes (classID 9)
    if classID == ITEM_CLASS.RECIPE and db.recipes then
        IM:Debug("[Filters] IsExcludedByCategory: Matched RECIPE (classID 9)")
        return true
    end

    -- Battle pets (classID 17)
    if classID == ITEM_CLASS.BATTLEPET and db.pets then
        IM:Debug("[Filters] IsExcludedByCategory: Matched BATTLE PET (classID 17)")
        return true
    end

    -- Currency tokens (classID 15 Miscellaneous, subclass 4 Other)
    if classID == ITEM_CLASS.MISCELLANEOUS and db.currencyTokens then
        if subclassID == MISC_SUBCLASS.OTHER then
            IM:Debug("[Filters] IsExcludedByCategory: Matched CURRENCY TOKEN (15_4)")
            return true
        end
    end

    -- Mount items (classID 15 Miscellaneous, subclass 5 Mount) - fallback for classID check
    if classID == ITEM_CLASS.MISCELLANEOUS and db.mounts then
        if subclassID == MISC_SUBCLASS.MOUNT then
            IM:Debug("[Filters] IsExcludedByCategory: Matched MOUNT (classID 15_5)")
            return true
        end
    end

    -- Housing items (classID 20) - Player housing category in TWW
    if classID == 20 and db.housingItems then
        IM:Debug("[Filters] IsExcludedByCategory: Matched HOUSING (classID 20_" .. tostring(subclassID or 0) .. ")")
        return true
    end

    -- Check custom category exclusions (supports both "7" and "7_8" formats)
    if IM.db.global.customCategoryExclusions then
        -- Check class-only match (e.g., "7" matches all tradeskill items)
        local classOnlyKey = tostring(classID)
        if IM.db.global.customCategoryExclusions[classOnlyKey] then
            IM:Debug("[Filters] IsExcludedByCategory: Custom exclusion matched class=" .. classOnlyKey)
            return true
        end
        -- Check class+subclass match (e.g., "7_8" matches only cooking)
        local fullKey = classID .. "_" .. (subclassID or 0)
        if IM.db.global.customCategoryExclusions[fullKey] then
            IM:Debug("[Filters] IsExcludedByCategory: Custom exclusion matched key=" .. fullKey)
            return true
        end
    end

    -- TIER 2: Expensive API-based checks (only if classID checks didn't match)
    -- These involve API calls so check last

    -- Toys (detected via C_ToyBox API)
    if db.toys and itemID and self:IsToy(itemID) then
        IM:Debug("[Filters] IsExcludedByCategory: Matched TOY (C_ToyBox API)")
        return true
    end

    -- Mounts (detected via C_MountJournal API)
    if db.mounts and itemID and self:IsMount(itemID) then
        IM:Debug("[Filters] IsExcludedByCategory: Matched MOUNT (C_MountJournal API)")
        return true
    end

    -- Caged battle pets (itemID 82800 is the pet cage container)
    if db.pets and itemID and self:IsCagedPet(itemID) then
        IM:Debug("[Filters] IsExcludedByCategory: Matched CAGED PET (itemID 82800)")
        return true
    end

    return false
end

-- Check if item has uncollected transmog appearance
function Filters:HasUncollectedTransmog(itemID)
    if not C_TransmogCollection or not C_TransmogCollection.PlayerHasTransmog then
        return false -- API not available
    end

    -- Only check for equipment items
    local _, _, _, _, _, itemType, _, _, equipLoc = _GetCachedItemInfo(itemID)
    if itemType ~= "Armor" and itemType ~= "Weapon" then
        return false
    end

    -- Exclude slots that don't have visible transmog appearances
    -- INVTYPE_TRINKET = Trinkets
    -- INVTYPE_FINGER = Rings
    -- INVTYPE_NECK = Necks
    if equipLoc == "INVTYPE_TRINKET" or equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_NECK" then
        return false
    end

    -- Returns true if player does NOT have this transmog
    return not C_TransmogCollection.PlayerHasTransmog(itemID)
end

-- Check if item is bound (soulbound or account-bound)
function Filters:IsItemBound(bagID, slotID)
    -- Use C_Item.IsBound if available (8.0+)
    if C_Item and C_Item.IsBound then
        local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
        if itemLocation and itemLocation:IsValid() then
            return C_Item.IsBound(itemLocation)
        end
    end

    -- Fallback to GetContainerItemInfo
    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    return info and info.isBound
end

--[[
    Check if item is soulbound (BoP - Binds on Pickup or already bound BoE).
    Returns true for soulbound items, false for account-bound/warbound/unbound.

    Bind types:
    - 1 = BoP (Binds on Pickup)
    - 2 = BoE (Binds on Equip) - if already bound, treated as soulbound
    - 3 = BoU (Binds on Use)
    - 4 = Quest Item

    @param bagID number - Bag ID
    @param slotID number - Slot ID within bag
    @param itemID number - Item ID
    @param bindType number - Bind type from GetItemInfo
    @return boolean - True if soulbound, false otherwise
]]
function Filters:IsSoulbound(bagID, slotID, itemID, bindType)
    -- First check if item is bound at all
    if not self:IsItemBound(bagID, slotID) then
        return false
    end

    -- Check bind type from item info
    -- bindType: 1 = BoP, 2 = BoE, 3 = BoU, 4 = Quest
    -- If bindType is 1 (BoP) or 4 (Quest), it's soulbound
    -- If bindType is 2 (BoE) and bound, it's also soulbound (was equipped)
    if bindType == 1 or bindType == 4 then
        return true
    end
    if bindType == 2 then
        -- BoE that's bound = soulbound (was equipped)
        return true
    end

    -- Check for account-bound items using C_Item.IsBoundToAccountUntilEquip
    if C_Item and C_Item.IsBoundToAccountUntilEquip then
        local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
        if itemLocation and itemLocation:IsValid() then
            if C_Item.IsBoundToAccountUntilEquip(itemLocation) then
                return false -- Account bound, not soulbound
            end
        end
    end

    -- Check tooltip for "Account Bound" or "Warbound" text
    local tooltipData = C_TooltipInfo and C_TooltipInfo.GetBagItem(bagID, slotID)
    if tooltipData and tooltipData.lines then
        for _, line in ipairs(tooltipData.lines) do
            local text = line.leftText or ""
            if text:find("Account Bound") or text:find("Warbound") or text:find("Binds to Blizzard Account") then
                return false -- Account/Warbound, not soulbound
            end
        end
    end

    -- Default: if bound and not detected as account-bound, treat as soulbound
    return true
end

-- Check if item is warbound/account-bound
function Filters:IsWarbound(bagID, slotID)
    -- Must be bound first
    if not self:IsItemBound(bagID, slotID) then
        return false
    end

    -- Check using C_Item.IsBoundToAccountUntilEquip
    if C_Item and C_Item.IsBoundToAccountUntilEquip then
        local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
        if itemLocation and itemLocation:IsValid() then
            if C_Item.IsBoundToAccountUntilEquip(itemLocation) then
                return true
            end
        end
    end

    -- Check tooltip for "Account Bound" or "Warbound" text
    local tooltipData = C_TooltipInfo and C_TooltipInfo.GetBagItem(bagID, slotID)
    if tooltipData and tooltipData.lines then
        for _, line in ipairs(tooltipData.lines) do
            local text = line.leftText or ""
            if text:find("Account Bound") or text:find("Warbound") or text:find("Binds to Blizzard Account") then
                return true
            end
        end
    end

    return false
end

--[[
    Main filter evaluation for auto-sell.
    Determines if an item should be sold based on configured filters and protections.

    Filter Priority (highest to lowest):
    1. Whitelist (locked items) - NEVER sell
    2. Junk List - ALWAYS sell (overrides all protections except whitelist)
    3. Mail Rules - Protect items destined for alts
    4. Protection Checks - Equipment sets, category exclusions
    5. Filter Checks - Soulbound, warbound, transmog, quality, item level, price

    Note: This does NOT check autoSellEnabled - that setting only controls
    automatic selling on merchant open, not whether items match sell criteria.
    The OnMerchantShow handler checks autoSellEnabled before calling SellJunk.

    @param bagID number - Bag ID
    @param slotID number - Slot ID within bag
    @param itemID number - Item ID
    @param itemLink string - Item link (optional, will use itemID if not provided)
    @return boolean shouldSell - True if item should be sold
    @return string reason - Reason for the decision
]]
function Filters:ShouldAutoSell(bagID, slotID, itemID, itemLink)
    local db = IM.db.global

    -- Debug: show custom exclusions on first call
    if not Filters._debuggedCustomExclusions then
        Filters._debuggedCustomExclusions = true
        local customs = {}
        for key, _ in pairs(db.customCategoryExclusions or {}) do
            table.insert(customs, key)
        end
        if #customs > 0 then
            IM:Debug("[Filters] Custom category exclusions: " .. table.concat(customs, ", "))
        end
    end

    -- Get item info (cached for performance)
    local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
          _, _, _, sellPrice, classID, subclassID, bindType = _GetCachedItemInfo(itemLink or itemID)

    if not itemName then
        IM:Debug("[Filters] ShouldAutoSell: " .. tostring(itemID) .. " - Item info not available")
        return false, "Item info not available"
    end

    -- Prefer the item instance's current item level (bag/slot) over GetItemInfo().
    -- This avoids incorrect ilvls for scaling/upgrade items and does NOT require hovering.
    local effectiveItemLevel = itemLevel
    if ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
        local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
        if itemLoc and itemLoc.IsValid and itemLoc:IsValid() then
            local ilvl = C_Item.GetCurrentItemLevel(itemLoc)
            if ilvl and ilvl > 0 then
                effectiveItemLevel = ilvl
            end
        end
    end

    IM:Debug("[Filters] Checking: " .. itemName ..
        " (quality=" .. tostring(itemQuality) ..
        ", ilvl=" .. tostring(effectiveItemLevel) ..
        ", class=" .. tostring(classID) .. "_" .. tostring(subclassID) ..
        ", price=" .. tostring(sellPrice) .. ")")

    -- WHITELIST CHECK (highest priority - NEVER sell whitelisted items)
    if IM:IsWhitelisted(itemID) then
        IM:Debug("[Filters]   -> Rejected: Whitelisted (locked)")
        return false, "Whitelisted"
    end

    -- JUNK LIST CHECK (second priority - ALWAYS sell junk items regardless of other protections)
    -- Only whitelist can override junk list
    if IM:IsJunk(itemID) then
        -- Only additional check: must have vendor value
        if sellPrice and sellPrice > 0 then
            IM:Debug("[Filters]   -> WILL SELL: On junk list (overrides all protections)")
            return true, "On junk list"
        else
            IM:Debug("[Filters]   -> Rejected: On junk list but no vendor value")
            return false, "No vendor value"
        end
    end

    -- MAIL RULE CHECK (third priority - protect items destined for alts)
    -- Check if item matches any mail rule (intended to be sent to alt, not sold)
    if IM.modules.MailHelper and IM.modules.MailHelper.ItemMatchesAnyRule then
        local matchesRule, altKey, ruleName = IM.modules.MailHelper:ItemMatchesAnyRule(itemID)
        if matchesRule then
            IM:Debug("[Filters]   -> Rejected: Matches mail rule '" .. (ruleName or "?") .. "' for " .. (altKey or "?"))
            return false, "Mail rule: " .. (ruleName or "sending to alt")
        end
    end

    -- PROTECTION CHECKS (for items NOT on junk list)

    -- Check equipment sets (if protection enabled)
    if db.categoryExclusions.equipmentSets and self:IsInEquipmentSet(itemID) then
        IM:Debug("[Filters]   -> Rejected: In equipment set")
        return false, "In equipment set"
    end

    -- Check category exclusions
    if self:IsExcludedByCategory(classID, subclassID, itemID) then
        IM:Debug("[Filters]   -> Rejected: Excluded category (" .. tostring(classID) .. "_" .. tostring(subclassID) .. ")")
        return false, "Excluded category"
    end

    -- FILTER CHECKS

    -- Check soulbound/non-soulbound filters (mutually exclusive)
    local isSoulbound = self:IsSoulbound(bagID, slotID, itemID, bindType)

    -- Option 1: Only sell soulbound items (protect non-soulbound)
    if db.autoSell.onlySellSoulbound then
        if not isSoulbound then
            IM:Debug("[Filters]   -> Rejected: Non-soulbound (only selling soulbound)")
            return false, "Non-soulbound"
        end
    -- Option 2: Protect soulbound items (don't sell them)
    elseif db.autoSell.skipSoulbound and isSoulbound then
        IM:Debug("[Filters]   -> Rejected: Soulbound")
        return false, "Soulbound"
    end

    -- Check warbound/account-bound filter
    if db.autoSell.skipWarbound and self:IsWarbound(bagID, slotID) then
        IM:Debug("[Filters]   -> Rejected: Warbound")
        return false, "Warbound"
    end

    -- Check transmog protection
    if db.autoSell.skipUncollectedTransmog and self:HasUncollectedTransmog(itemID) then
        IM:Debug("[Filters]   -> Rejected: Uncollected transmog")
        return false, "Uncollected transmog"
    end

    -- Check quality threshold
    if itemQuality > db.autoSell.maxQuality then
        IM:Debug("[Filters]   -> Rejected: Quality " .. tostring(itemQuality) .. " > maxQuality " .. tostring(db.autoSell.maxQuality))
        return false, "Quality too high"
    end

    -- Check item level threshold (if enabled)
    if db.autoSell.maxItemLevel > 0 and (effectiveItemLevel or 0) > db.autoSell.maxItemLevel then
        IM:Debug("[Filters]   -> Rejected: Item level too high")
        return false, "Item level too high"
    end

    -- Check minimum sell price (if enabled)
    if db.autoSell.minSellPrice > 0 and sellPrice < db.autoSell.minSellPrice then
        IM:Debug("[Filters]   -> Rejected: Sell price too low")
        return false, "Sell price too low"
    end

    -- Check if item has no vendor value
    if not sellPrice or sellPrice == 0 then
        IM:Debug("[Filters]   -> Rejected: No vendor value")
        return false, "No vendor value"
    end

    IM:Debug("[Filters]   -> WILL SELL: " .. itemName)
    return true, "Matches filters"
end

-- Helper to get all bag IDs to scan (including reagent bag if it exists)
-- Exposed globally for other modules to use
function IM:GetBagIDsToScan()
    local bags = {}
    -- Standard bags 0-4
    for i = 0, NUM_BAG_SLOTS do
        table.insert(bags, i)
    end
    -- Reagent bag (bag ID 5) - only exists in Dragonflight+
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
        table.insert(bags, Enum.BagIndex.ReagentBag)
    end
    return bags
end

-- Local alias for internal use
local function _GetBagIDsToScan()
    return IM:GetBagIDsToScan()
end

-- Get count of items that match auto-sell criteria
function Filters:GetAutoSellCount()
    local count = 0
    local totalValue = 0

    for _, bagID in ipairs(_GetBagIDsToScan()) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                local shouldSell = self:ShouldAutoSell(bagID, slotID, info.itemID, info.hyperlink)
                if shouldSell then
                    count = count + (info.stackCount or 1)
                    -- Only use sellPrice if item info is actually loaded (itemName exists)
                    local itemName, _, _, _, _, _, _, _, _, _, sellPrice = _GetCachedItemInfo(info.itemID)
                    if itemName and sellPrice then
                        totalValue = totalValue + (sellPrice * (info.stackCount or 1))
                    end
                end
            end
        end
    end

    return count, totalValue
end

-- Get list of items matching auto-sell criteria
function Filters:GetAutoSellItems()
    local items = {}
    local pendingItems = {}
    local pendingLookup = {}
    local bagsToScan = _GetBagIDsToScan()

    IM:Debug("[Filters] GetAutoSellItems: Scanning " .. #bagsToScan .. " bags (including reagent bag if available)")

    for _, bagID in ipairs(bagsToScan) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        IM:Debug("[Filters]   Bag " .. bagID .. " has " .. tostring(numSlots) .. " slots")
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                local shouldSell, reason = self:ShouldAutoSell(bagID, slotID, info.itemID, info.hyperlink)
                if shouldSell then
                    table.insert(items, {
                        bagID = bagID,
                        slotID = slotID,
                        itemID = info.itemID,
                        itemLink = info.hyperlink,
                        stackCount = info.stackCount or 1,
                        reason = reason,
                    })
                elseif reason == "Item info not available" then
                    if not pendingLookup[info.itemID] then
                        pendingLookup[info.itemID] = true
                        table.insert(pendingItems, info.itemID)
                        if C_Item then
                            if C_Item.RequestLoadItemDataByID then
                                C_Item.RequestLoadItemDataByID(info.itemID)
                            elseif C_Item.RequestLoadItemData and info.hyperlink then
                                C_Item.RequestLoadItemData(info.hyperlink)
                            end
                        end
                    end
                end
            end
        end
    end

    IM:Debug("[Filters] GetAutoSellItems: Found " .. #items .. " items to sell")
    if #pendingItems > 0 then
        IM:Debug("[Filters] GetAutoSellItems: Pending item info for " .. #pendingItems .. " items")
    end

    return items, pendingItems
end

