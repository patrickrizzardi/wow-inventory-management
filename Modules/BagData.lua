--[[
    InventoryManager - BagData.lua
    Central data layer for bag contents - caching, diffing, and event emission

    UI components consume this module's events instead of scanning bags directly.
    Provides granular events for efficient UI updates.

    Bag IDs covered:
    - 0 = Backpack (Enum.BagIndex.Backpack)
    - 1-4 = Bag slots
    - 5 = Reagent Bag (Enum.BagIndex.ReagentBag)

    Public Methods:
    - BagData:GetAllItems() - returns cached item list
    - BagData:GetItemAt(bagID, slotID) - returns cached item data
    - BagData:SearchByName(query) - searches cached names
    - BagData:ForceRefresh() - force full rescan

    Events emitted (via callbacks):
    - OnBagItemAdded(bagID, slotID, itemData)
    - OnBagItemRemoved(bagID, slotID, itemData)
    - OnBagItemChanged(bagID, slotID, oldData, newData)
]]

local addonName, IM = ...

local BagData = {}
IM:RegisterModule("BagData", BagData)

-- Private state
local _itemCache = {}           -- [bagID][slotID] = itemData
local _itemsByID = {}           -- [itemID] = { itemData, itemData, ... }
local _allItems = {}            -- flat list for iteration
local _callbacks = {
    OnBagItemAdded = {},
    OnBagItemRemoved = {},
    OnBagItemChanged = {},
}
local _pendingRefresh = false
local _initialized = false

-- Bag IDs to scan
local BAG_IDS = {
    0,  -- Backpack
    1, 2, 3, 4,  -- Regular bags
    5,  -- Reagent bag (Enum.BagIndex.ReagentBag)
}

local function _GetBagIDs()
    return BAG_IDS
end

local function _IsBagTracked(bagID)
    return bagID ~= nil and bagID >= 0 and bagID <= 5
end

-- Category mapping (classID -> display category)
local CLASS_TO_CATEGORY = {
    [0]  = "Consumables",
    [1]  = "Containers",
    [2]  = "Equipment",
    [3]  = "Gems",
    [4]  = "Equipment",
    [5]  = "Reagents",
    [7]  = "Trade Goods",
    [8]  = "Enhancements",
    [9]  = "Recipes",
    [12] = "Quest Items",
    [15] = "Miscellaneous",
    [16] = "Glyphs",
    [17] = "Battle Pets",
    [18] = "Miscellaneous",
}

-- SubClass overrides for finer categorization
local SUBCLASS_OVERRIDES = {
    [0] = {  -- Consumable subclasses
        [5] = "Food & Drink",
    },
    [15] = {  -- Miscellaneous subclasses
        [0] = "Junk",
        [1] = "Reagents",
        [2] = "Companions",
        [3] = "Holiday",
        [5] = "Mounts",
    },
}

local _equipmentSetIndex = {}  -- [itemID] = setName

local function _RebuildEquipmentSetIndex()
    wipe(_equipmentSetIndex)

    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then
        return
    end

    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
    if not setIDs then return end

    for _, setID in ipairs(setIDs) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
        local itemIDs = C_EquipmentSet.GetItemIDs(setID)
        if name and itemIDs then
            for _, itemID in pairs(itemIDs) do
                if itemID and itemID > 0 then
                    _equipmentSetIndex[itemID] = name
                end
            end
        end
    end
end

local function _GetGearSetCategory(itemID)
    local setName = _equipmentSetIndex[itemID]
    if setName then
        return "Gear: " .. setName
    end
    return nil
end

-- Equipment group mapping by equip location
local EQUIP_LOC_GROUP = {
    INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_WEAPON = "One-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND = "Off Hand",
    INVTYPE_RANGED = "Ranged",
    INVTYPE_RANGEDRIGHT = "Ranged",
    INVTYPE_THROWN = "Ranged",
    INVTYPE_SHIELD = "Off Hand",
    INVTYPE_HOLDABLE = "Off Hand",
    INVTYPE_HEAD = "Head",
    INVTYPE_NECK = "Neck",
    INVTYPE_SHOULDER = "Shoulders",
    INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest",
    INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet",
    INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands",
    INVTYPE_FINGER = "Rings",
    INVTYPE_TRINKET = "Trinkets",
    INVTYPE_CLOAK = "Back",
    INVTYPE_BODY = "Shirt",
    INVTYPE_TABARD = "Tabard",
}

-- Fire callbacks for an event
local function _FireCallbacks(eventName, ...)
    for _, callback in ipairs(_callbacks[eventName] or {}) do
        callback(...)
    end
end

-- Get category for an item
local function _GetItemCategory(itemID, quality, classID, subClassID)
    if not itemID then return "Miscellaneous", false end

    -- Check custom category first
    local CustomCategories = IM:GetModule("CustomCategories")
    if CustomCategories then
        local customCat = CustomCategories:GetCategoryForItem(itemID)
        if customCat then
            return customCat.name, true
        end
    end

    local gearCategory = _GetGearSetCategory(itemID)
    if gearCategory then
        return gearCategory, false
    end

    -- Get classID/subClassID via GetItemInfoInstant (cached, fast)
    if not classID then
        return "Miscellaneous", false
    end

    -- Check for junk quality
    if quality == 0 then
        return "Junk", false
    end

    -- Check subclass override first
    local subOverrides = SUBCLASS_OVERRIDES[classID]
    if subOverrides and subOverrides[subClassID] then
        return subOverrides[subClassID], false
    end

    -- Fall back to primary class mapping
    return CLASS_TO_CATEGORY[classID] or "Miscellaneous", false
end

local function _GetItemGroup(categoryName, itemType, itemSubType, itemEquipLoc)
    if categoryName == "Equipment" and itemEquipLoc then
        return EQUIP_LOC_GROUP[itemEquipLoc] or "Equipment"
    end

    if itemSubType and itemSubType ~= "" then
        return itemSubType
    end

    if itemType and itemType ~= "" then
        return itemType
    end

    return "Other"
end

-- Build item data for a slot
local function _BuildItemData(bagID, slotID)
    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)

    if not itemInfo then
        return nil
    end

    local itemID = itemInfo.itemID
    local itemLink = itemInfo.hyperlink
    local quality = itemInfo.quality or 0

    local itemType, itemSubType, itemEquipLoc, instantIcon, classID, subClassID
    if itemID then
        local _, instantType, instantSubType, instantEquipLoc, instantIconFile, instantClassID, instantSubClassID = GetItemInfoInstant(itemID)
        itemType = instantType
        itemSubType = instantSubType
        itemEquipLoc = instantEquipLoc
        instantIcon = instantIconFile
        classID = instantClassID
        subClassID = instantSubClassID
    end

    local itemName
    if itemLink or itemID then
        itemName = GetItemInfo(itemLink or itemID)
    end

    -- Get category
    local displayCategory, isCustomCategory = _GetItemCategory(itemID, quality, classID, subClassID)
    local displayGroup = _GetItemGroup(displayCategory, itemType, itemSubType, itemEquipLoc)

    -- Check IM status
    local isLocked = IM:IsWhitelisted(itemID)
    local isJunk = IM:IsJunk(itemID)

    -- Icon priority: GetItemInfoInstant > C_Item > C_Container
    local finalIcon = instantIcon
    if not finalIcon and C_Item and C_Item.GetItemIconByID and itemID then
        finalIcon = C_Item.GetItemIconByID(itemID)
    end
    if not finalIcon then
        finalIcon = itemInfo.iconFileID
    end

    return {
        bagID = bagID,
        slotID = slotID,
        itemID = itemID,
        itemLink = itemLink,
        name = itemName or "",
        itemType = itemType,
        itemSubType = itemSubType,
        itemEquipLoc = itemEquipLoc,
        classID = classID,
        subClassID = subClassID,
        quality = quality,
        count = itemInfo.stackCount or 1,
        icon = finalIcon,
        isLocked = isLocked,
        isJunk = isJunk,
        isCustomCategory = isCustomCategory,
        displayCategory = displayCategory,
        displayGroup = displayGroup,
        isBound = itemInfo.isBound,
        isLockable = itemInfo.isLocked,  -- WoW's item lock (being moved)
    }
end

-- Scan a single bag and diff against cache
local function _ScanBag(bagID)
    local numSlots = C_Container.GetContainerNumSlots(bagID)

    -- Initialize cache for this bag if needed
    if not _itemCache[bagID] then
        _itemCache[bagID] = {}
    end

    local currentSlots = {}

    -- Scan all slots
    for slotID = 1, numSlots do
        local newData = _BuildItemData(bagID, slotID)
        local oldData = _itemCache[bagID][slotID]

        currentSlots[slotID] = true

        if newData and not oldData then
            -- Item added
            _itemCache[bagID][slotID] = newData
            _FireCallbacks("OnBagItemAdded", bagID, slotID, newData)
        elseif not newData and oldData then
            -- Item removed
            _itemCache[bagID][slotID] = nil
            _FireCallbacks("OnBagItemRemoved", bagID, slotID, oldData)
        elseif newData and oldData then
            -- Check if changed (itemID or count)
            if newData.itemID ~= oldData.itemID or newData.count ~= oldData.count then
                _itemCache[bagID][slotID] = newData
                _FireCallbacks("OnBagItemChanged", bagID, slotID, oldData, newData)
            else
                -- Update cached data in case other properties changed (lock status, etc)
                _itemCache[bagID][slotID] = newData
            end
        end
    end

    -- Check for removed slots (bag size changed)
    for slotID, oldData in pairs(_itemCache[bagID]) do
        if not currentSlots[slotID] then
            _itemCache[bagID][slotID] = nil
            _FireCallbacks("OnBagItemRemoved", bagID, slotID, oldData)
        end
    end
end

-- Rebuild flat lists from cache
local function _RebuildLists()
    wipe(_allItems)
    wipe(_itemsByID)

    for bagID, slots in pairs(_itemCache) do
        for slotID, itemData in pairs(slots) do
            table.insert(_allItems, itemData)

            -- Index by itemID
            local itemID = itemData.itemID
            if itemID then
                if not _itemsByID[itemID] then
                    _itemsByID[itemID] = {}
                end
                table.insert(_itemsByID[itemID], itemData)
            end
        end
    end
end

-- Full refresh of all bags
function BagData:ForceRefresh()
    local bagIDs = _GetBagIDs()
    for _, bagID in ipairs(bagIDs) do
        _ScanBag(bagID)
    end
    _RebuildLists()
    IM:Debug("[BagData] Full refresh complete, " .. #_allItems .. " items")
end

-- Queue a debounced refresh
function BagData:QueueRefresh()
    if _pendingRefresh then return end
    _pendingRefresh = true

    C_Timer.After(0.1, function()
        _pendingRefresh = false
        self:ForceRefresh()
    end)
end

-- Public API

function BagData:GetAllItems()
    return _allItems
end

function BagData:GetItemAt(bagID, slotID)
    if _itemCache[bagID] then
        return _itemCache[bagID][slotID]
    end
    return nil
end

function BagData:GetItemsByID(itemID)
    return _itemsByID[itemID] or {}
end

function BagData:SearchByName(query)
    if not query or query == "" then
        return _allItems
    end

    local results = {}
    local queryLower = query:lower()

    for _, itemData in ipairs(_allItems) do
        if itemData.name and itemData.name:lower():find(queryLower, 1, true) then
            table.insert(results, itemData)
        end
    end

    return results
end

function BagData:GetItemCount()
    return #_allItems
end

-- Callback registration
function BagData:RegisterCallback(eventName, callback)
    if _callbacks[eventName] then
        table.insert(_callbacks[eventName], callback)
    end
end

function BagData:UnregisterCallback(eventName, callback)
    if not _callbacks[eventName] then return end

    for i, cb in ipairs(_callbacks[eventName]) do
        if cb == callback then
            table.remove(_callbacks[eventName], i)
            break
        end
    end
end

-- Update lock/junk status for an item
function BagData:RefreshItemStatus(itemID)
    local items = _itemsByID[itemID]
    if not items then return end

    local isLocked = IM:IsWhitelisted(itemID)
    local isJunk = IM:IsJunk(itemID)
    local sample = items[1]
    local displayCategory, isCustomCategory = _GetItemCategory(itemID, sample.quality, sample.classID, sample.subClassID)
    local displayGroup = _GetItemGroup(displayCategory, sample.itemType, sample.itemSubType, sample.itemEquipLoc)

    for _, itemData in ipairs(items) do
        local oldData = {
            isLocked = itemData.isLocked,
            isJunk = itemData.isJunk,
        }

        itemData.isLocked = isLocked
        itemData.isJunk = isJunk
        itemData.displayCategory = displayCategory
        itemData.isCustomCategory = isCustomCategory
        itemData.displayGroup = displayGroup

        -- Fire change event if status changed
        if oldData.isLocked ~= isLocked or oldData.isJunk ~= isJunk then
            _FireCallbacks("OnBagItemChanged", itemData.bagID, itemData.slotID, oldData, itemData)
        end
    end
end

function BagData:OnInitialize()
    -- Initialize cache structure
    for _, bagID in ipairs(BAG_IDS) do
        _itemCache[bagID] = {}
    end
end

function BagData:OnEnable()
    local module = self

    -- Register for bag update events
    IM:RegisterEvent("BAG_UPDATE", function(event, bagID)
        if _IsBagTracked(bagID) and _itemCache[bagID] then
            _ScanBag(bagID)
            _RebuildLists()
        else
            module:QueueRefresh()
        end
    end)

    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        module:QueueRefresh()
    end)

    IM:RegisterEvent("ITEM_LOCK_CHANGED", function(event, bagID, slotID)
        if bagID and slotID then
            _ScanBag(bagID)
            _RebuildLists()
        end
    end)

    IM:RegisterEvent("ITEM_UNLOCKED", function()
        module:QueueRefresh()
    end)

    IM:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(event, itemID)
        -- Item info loaded async, refresh items with this ID
        if itemID and _itemsByID[itemID] then
            module:QueueRefresh()
        end
    end)

    IM:RegisterEvent("EQUIPMENT_SETS_CHANGED", function()
        _RebuildEquipmentSetIndex()
        module:QueueRefresh()
    end)

    IM:RegisterEvent("PLAYER_MONEY", function()
        -- Gold changed - not directly relevant but some UIs want to know
        -- Could fire a separate event here if needed
    end)

    -- Listen for whitelist/junk changes
    IM:RegisterWhitelistCallback(function(itemID, added)
        module:RefreshItemStatus(itemID)
    end)

    IM:RegisterJunkListCallback(function(itemID, added)
        module:RefreshItemStatus(itemID)
    end)

    -- Initial scan after a short delay (let bags populate)
    C_Timer.After(0.5, function()
        if not _initialized then
            _initialized = true
            _RebuildEquipmentSetIndex()
            module:ForceRefresh()
        end
    end)
end
