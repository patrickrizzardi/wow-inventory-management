--[[
    InventoryManager - UI/BagUI/CategoryView.lua
    Category and subcategory rendering with equipment slot ordering.
    Organizes bag items into logical groups.
]]

local addonName, IM = ...
local UI = IM.UI

-- Ensure BagUI namespace exists
UI.BagUI = UI.BagUI or {}
local BagUI = UI.BagUI

BagUI.CategoryView = {}
local CategoryView = BagUI.CategoryView

-- Equipment slot order (for subcategory mode)
local EQUIPMENT_SLOT_ORDER = {
    "INVTYPE_HEAD",
    "INVTYPE_NECK",
    "INVTYPE_SHOULDER",
    "INVTYPE_CHEST",
    "INVTYPE_ROBE",
    "INVTYPE_CLOAK",
    "INVTYPE_WRIST",
    "INVTYPE_HAND",
    "INVTYPE_WAIST",
    "INVTYPE_LEGS",
    "INVTYPE_FEET",
    "INVTYPE_FINGER",
    "INVTYPE_TRINKET",
    "INVTYPE_WEAPON",
    "INVTYPE_SHIELD",
    "INVTYPE_2HWEAPON",
    "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND",
    "INVTYPE_HOLDABLE",
    "INVTYPE_RANGED",
    "INVTYPE_RANGEDRIGHT",
    "INVTYPE_THROWN",
}

-- Build lookup table for slot order
local SLOT_ORDER_MAP = {}
for i, slot in ipairs(EQUIPMENT_SLOT_ORDER) do
    SLOT_ORDER_MAP[slot] = i
end

-- ============================================================================
-- MAIN REFRESH
-- ============================================================================

function CategoryView:Refresh(scrollContent)
    if not scrollContent then return end

    -- Release all item buttons
    if BagUI.ItemButton then
        BagUI.ItemButton:ReleaseAll()
    end

    -- Clear any existing category headers and empty state message
    for _, child in ipairs({scrollContent:GetChildren()}) do
        if child._imCategoryHeader or child._imEmptyState then
            child:Hide()
        end
    end

    -- Gather items from bags (filtered by search)
    local items = self:GatherItems()

    -- Handle empty state (no items or no search results)
    if #items == 0 then
        local searchFilter = BagUI:GetSearchFilter()
        local emptyText = scrollContent._imEmptyText

        if not emptyText then
            emptyText = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            emptyText:SetPoint("CENTER", scrollContent, "CENTER", 0, 50)
            emptyText._imEmptyState = true
            scrollContent._imEmptyText = emptyText
        end

        if searchFilter and searchFilter ~= "" then
            emptyText:SetText("|cff888888No items match \"" .. searchFilter .. "\"|r")
        else
            emptyText:SetText("|cff888888No items in bags|r")
        end
        emptyText:Show()

        -- Set minimal scroll content height
        local itemSize = BagUI.MasonryLayout:GetItemSize()
        scrollContent:SetHeight(itemSize + 40)
        return
    end

    -- Hide empty state if we have items
    if scrollContent._imEmptyText then
        scrollContent._imEmptyText:Hide()
    end

    -- Organize into categories
    local settings = BagUI:GetSettings()
    local categories
    if settings.viewMode == "subcategory" then
        categories = self:OrganizeBySubcategory(items)
    else
        categories = self:OrganizeByCategory(items)
    end

    -- Filter out empty categories (shouldn't happen but safety check)
    local nonEmptyCategories = {}
    for _, cat in ipairs(categories) do
        if #cat.items > 0 then
            table.insert(nonEmptyCategories, cat)
        end
    end
    categories = nonEmptyCategories

    -- Calculate layout
    local containerWidth = scrollContent:GetWidth()
    -- Dynamic fallback based on parent frame width
    if containerWidth <= 0 then
        containerWidth = (scrollContent:GetParent() and scrollContent:GetParent():GetWidth() or 480) - 40
    end

    local columnData, totalHeight = BagUI.MasonryLayout:CalculateFromSettings(categories, containerWidth)

    -- Render categories
    self:RenderCategories(scrollContent, columnData)

    -- Update scroll content height (dynamic minimum based on one row)
    local itemSize = BagUI.MasonryLayout:GetItemSize()
    local minHeight = itemSize + 40  -- One row + padding
    scrollContent:SetHeight(math.max(totalHeight + 20, minHeight))
end

-- ============================================================================
-- SEARCH FILTER HELPERS
-- ============================================================================

-- Parse ilvl filter syntax: >400, >=400, <400, <=400, =400, 400
local function _ParseIlvlFilter(filter)
    -- Try to match comparison operators
    local op, num = filter:match("^([<>=]+)(%d+)$")
    if op and num then
        return op, tonumber(num)
    end

    -- Try plain number (exact match)
    local plainNum = filter:match("^(%d+)$")
    if plainNum then
        return "=", tonumber(plainNum)
    end

    return nil, nil
end

-- Check if item level matches filter
local function _MatchesIlvlFilter(itemIlvl, op, targetIlvl)
    if not itemIlvl or itemIlvl <= 0 then return false end

    if op == "=" then return itemIlvl == targetIlvl end
    if op == ">" then return itemIlvl > targetIlvl end
    if op == ">=" then return itemIlvl >= targetIlvl end
    if op == "<" then return itemIlvl < targetIlvl end
    if op == "<=" then return itemIlvl <= targetIlvl end

    return false
end

-- Get item level for an item
local function _GetItemLevel(bagID, slotID, itemLink)
    local effectiveILvl = nil

    -- Prefer instance-based ilvl from bag/slot
    if ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
        local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
        if itemLoc and itemLoc.IsValid and itemLoc:IsValid() then
            effectiveILvl = C_Item.GetCurrentItemLevel(itemLoc)
        end
    end

    -- Fallback to link-based
    if (not effectiveILvl or effectiveILvl <= 0) and itemLink and GetDetailedItemLevelInfo then
        effectiveILvl = GetDetailedItemLevelInfo(itemLink)
    end

    return effectiveILvl
end

-- Check if item matches search filter
local function _ItemMatchesFilter(item, filter)
    if not filter or filter == "" then return true end

    local filterLower = filter:lower()

    -- Check if it's an ilvl filter
    local op, targetIlvl = _ParseIlvlFilter(filter)
    if op and targetIlvl then
        local itemIlvl = _GetItemLevel(item.bagID, item.slotID, item.hyperlink)
        return _MatchesIlvlFilter(itemIlvl, op, targetIlvl)
    end

    -- Text filter - match item name, category, or subcategory
    local itemName = GetItemInfo(item.itemID)
    if itemName and itemName:lower():find(filterLower, 1, true) then
        return true
    end

    -- Match category
    local categoryName = CategoryView:GetItemCategory(item)
    if categoryName and categoryName:lower():find(filterLower, 1, true) then
        return true
    end

    -- Match subcategory
    local subcategoryName = CategoryView:GetItemSubcategory(item)
    if subcategoryName and subcategoryName:lower():find(filterLower, 1, true) then
        return true
    end

    return false
end

-- ============================================================================
-- ITEM GATHERING
-- ============================================================================

function CategoryView:GatherItems()
    local items = {}
    local searchFilter = BagUI:GetSearchFilter()

    -- Scan regular bags (backpack + all equipped bags)
    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
            if itemInfo then
                local item = {
                    bagID = bagID,
                    slotID = slotID,
                    itemID = itemInfo.itemID,
                    iconFileID = itemInfo.iconFileID,
                    stackCount = itemInfo.stackCount,
                    quality = itemInfo.quality,
                    isLocked = itemInfo.isLocked,
                    hyperlink = itemInfo.hyperlink,
                }
                -- Apply search filter
                if _ItemMatchesFilter(item, searchFilter) then
                    table.insert(items, item)
                end
            end
        end
    end

    -- Scan reagent bag (if available)
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
        local reagentBagID = Enum.BagIndex.ReagentBag
        local reagentSlots = C_Container.GetContainerNumSlots(reagentBagID)
        if reagentSlots and reagentSlots > 0 then
            for slotID = 1, reagentSlots do
                local itemInfo = C_Container.GetContainerItemInfo(reagentBagID, slotID)
                if itemInfo then
                    local item = {
                        bagID = reagentBagID,
                        slotID = slotID,
                        itemID = itemInfo.itemID,
                        iconFileID = itemInfo.iconFileID,
                        stackCount = itemInfo.stackCount,
                        quality = itemInfo.quality,
                        isLocked = itemInfo.isLocked,
                        hyperlink = itemInfo.hyperlink,
                    }
                    -- Apply search filter
                    if _ItemMatchesFilter(item, searchFilter) then
                        table.insert(items, item)
                    end
                end
            end
        end
    end

    return items
end

-- ============================================================================
-- CATEGORIZATION
-- ============================================================================

function CategoryView:OrganizeByCategory(items)
    local categories = {}
    local categoryMap = {}
    local settings = BagUI:GetSettings()
    
    -- Separate equipment set items if enabled
    local equipmentSetsByName = {}  -- Maps set name -> items
    if settings.showItemSets then
        IM:Debug("[CategoryView] showItemSets is enabled, checking " .. #items .. " items")
        for _, item in ipairs(items) do
            if IM.Filters and IM.Filters.GetEquipmentSets then
                local sets = IM.Filters:GetEquipmentSets(item.itemID)
                if sets then
                    -- Item can be in multiple sets, add to each
                    for _, setName in ipairs(sets) do
                        if not equipmentSetsByName[setName] then
                            equipmentSetsByName[setName] = {}
                        end
                        table.insert(equipmentSetsByName[setName], item)
                        IM:Debug("[CategoryView] Found equipment set item: " .. (item.itemID or "unknown") .. " in set '" .. setName .. "'")
                    end
                end
            end
        end
        
        local totalSets = 0
        local totalItems = 0
        for setName, setItems in pairs(equipmentSetsByName) do
            totalSets = totalSets + 1
            totalItems = totalItems + #setItems
        end
        IM:Debug("[CategoryView] Found " .. totalItems .. " equipment set items across " .. totalSets .. " sets")
    else
        IM:Debug("[CategoryView] showItemSets is DISABLED")
    end
    
    -- Create separate categories for each equipment set
    -- Sort items within each set by equipment slot
    local setIndex = 0
    for setName, setItems in pairs(equipmentSetsByName) do
        -- Sort items by equipment slot order
        table.sort(setItems, function(a, b)
            local _, _, _, equipLocA = C_Item.GetItemInfoInstant(a.itemID)
            local _, _, _, equipLocB = C_Item.GetItemInfoInstant(b.itemID)
            local orderA = (equipLocA and SLOT_ORDER_MAP[equipLocA]) or 999
            local orderB = (equipLocB and SLOT_ORDER_MAP[equipLocB]) or 999
            return orderA < orderB
        end)
        
        local category = {
            name = "Set: " .. setName,
            items = setItems,
            order = setIndex,  -- Sets always first, ordered by discovery
        }
        table.insert(categories, category)
        categoryMap["Set: " .. setName] = category
        setIndex = setIndex + 1
        IM:Debug("[CategoryView] Created equipment set category '" .. setName .. "' with " .. #setItems .. " items")
    end
    
    -- Categorize remaining items
    for _, item in ipairs(items) do
        -- Skip if already in equipment set category
        local skipItem = false
        if settings.showItemSets and IM.Filters and IM.Filters.GetEquipmentSets then
            local sets = IM.Filters:GetEquipmentSets(item.itemID)
            if sets and #sets > 0 then
                skipItem = true
            end
        end
        
        if not skipItem then
            local categoryName = self:GetItemCategory(item)
            
            if not categoryMap[categoryName] then
                local category = {
                    name = categoryName,
                    items = {},
                    order = self:GetCategoryOrder(categoryName) + 100,  -- Regular categories after sets
                }
                table.insert(categories, category)
                categoryMap[categoryName] = category
            end
            
            table.insert(categoryMap[categoryName].items, item)
        end
    end
    
    -- Sort categories by order
    table.sort(categories, function(a, b)
        return a.order < b.order
    end)
    
    return categories
end

function CategoryView:OrganizeBySubcategory(items)
    local categories = {}
    local categoryMap = {}
    local settings = BagUI:GetSettings()
    
    -- Separate equipment set items if enabled
    local equipmentSetsByName = {}  -- Maps set name -> items
    if settings.showItemSets then
        IM:Debug("[CategoryView:Subcategory] showItemSets is enabled, checking " .. #items .. " items")
        for _, item in ipairs(items) do
            if IM.Filters and IM.Filters.GetEquipmentSets then
                local sets = IM.Filters:GetEquipmentSets(item.itemID)
                if sets then
                    -- Item can be in multiple sets, add to each
                    for _, setName in ipairs(sets) do
                        if not equipmentSetsByName[setName] then
                            equipmentSetsByName[setName] = {}
                        end
                        table.insert(equipmentSetsByName[setName], item)
                        IM:Debug("[CategoryView:Subcategory] Found equipment set item: " .. (item.itemID or "unknown") .. " in set '" .. setName .. "'")
                    end
                end
            end
        end
        
        local totalSets = 0
        local totalItems = 0
        for setName, setItems in pairs(equipmentSetsByName) do
            totalSets = totalSets + 1
            totalItems = totalItems + #setItems
        end
        IM:Debug("[CategoryView:Subcategory] Found " .. totalItems .. " equipment set items across " .. totalSets .. " sets")
    else
        IM:Debug("[CategoryView:Subcategory] showItemSets is DISABLED")
    end
    
    -- Create separate categories for each equipment set
    -- Sort items within each set by equipment slot
    local setIndex = 0
    for setName, setItems in pairs(equipmentSetsByName) do
        -- Sort items by equipment slot order
        table.sort(setItems, function(a, b)
            local _, _, _, equipLocA = C_Item.GetItemInfoInstant(a.itemID)
            local _, _, _, equipLocB = C_Item.GetItemInfoInstant(b.itemID)
            local orderA = (equipLocA and SLOT_ORDER_MAP[equipLocA]) or 999
            local orderB = (equipLocB and SLOT_ORDER_MAP[equipLocB]) or 999
            return orderA < orderB
        end)
        
        local category = {
            name = "Set: " .. setName,
            items = setItems,
            order = setIndex,  -- Sets always first, ordered by discovery
        }
        table.insert(categories, category)
        categoryMap["Set: " .. setName] = category
        setIndex = setIndex + 1
        IM:Debug("[CategoryView:Subcategory] Created equipment set category '" .. setName .. "' with " .. #setItems .. " items")
    end
    
    -- Categorize remaining items
    for _, item in ipairs(items) do
        -- Skip if already in equipment set category
        local skipItem = false
        if settings.showItemSets and IM.Filters and IM.Filters.GetEquipmentSets then
            local sets = IM.Filters:GetEquipmentSets(item.itemID)
            if sets and #sets > 0 then
                skipItem = true
            end
        end
        
        if not skipItem then
            local categoryName = self:GetItemSubcategory(item)
            
            if not categoryMap[categoryName] then
                local category = {
                    name = categoryName,
                    items = {},
                    order = self:GetSubcategoryOrder(categoryName, item) + 100,  -- Regular categories after sets
                }
                table.insert(categories, category)
                categoryMap[categoryName] = category
            end
            
            table.insert(categoryMap[categoryName].items, item)
        end
    end
    
    -- Sort categories by order
    table.sort(categories, function(a, b)
        return a.order < b.order
    end)
    
    return categories
end

-- ============================================================================
-- CATEGORY LOGIC
-- ============================================================================

local function IsCurrencyToken(classID, subclassID)
    if not classID or not subclassID then
        return false
    end
    return IM.ITEM_CLASS and IM.MISC_SUBCLASS
        and classID == IM.ITEM_CLASS.MISCELLANEOUS
        and subclassID == IM.MISC_SUBCLASS.OTHER
end

function CategoryView:GetItemCategory(item)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item.itemID)
    
    if IsCurrencyToken(classID, subclassID) then
        return (IM.CATEGORY_EXCLUSION_NAMES and IM.CATEGORY_EXCLUSION_NAMES.currencyTokens) or "Currency Tokens"
    end

    if classID then
        return IM.ITEM_CLASS_NAMES[classID] or "Other"
    end
    
    return "Other"
end

function CategoryView:GetItemSubcategory(item)
    -- IMPORTANT: C_Item.GetItemInfoInstant() does NOT return equipLoc reliably
    -- We must use GetItemInfo() to get equipLoc for equipment items
    local _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID = GetItemInfo(item.itemID)
    
    if IsCurrencyToken(classID, subclassID) then
        return (IM.CATEGORY_EXCLUSION_NAMES and IM.CATEGORY_EXCLUSION_NAMES.currencyTokens) or "Currency Tokens"
    end

    -- Step 1: Check if it's equippable - use equipment slot
    if equipLoc and equipLoc ~= "" and equipLoc ~= "nil" and equipLoc ~= "INVTYPE_NON_EQUIP" and equipLoc ~= "INVTYPE_BAG" then
        local slotName = _G[equipLoc]
        if slotName and slotName ~= "" then
            return slotName
        end
    end
    
    -- Step 2: Not equipment - for armor/weapons without slots, return "Other"
    -- This prevents showing "Plate", "Mail", "Leather", "Cloth" as categories
    if classID == IM.ITEM_CLASS.Armor or classID == IM.ITEM_CLASS.Weapon then
        return "Other"
    end
    
    -- Step 3: For non-equipment items, get the subcategory name
    if classID and subclassID then
        local subclassName = C_Item.GetItemSubClassInfo(classID, subclassID)
        if subclassName and subclassName ~= "" then
            return subclassName
        end
    end
    
    -- Fallback: Use ITEM_CLASS_NAMES
    if classID and IM.ITEM_CLASS_NAMES[classID] then
        return IM.ITEM_CLASS_NAMES[classID]
    end
    
    return "Other"
end

function CategoryView:GetCategoryOrder(categoryName)
    -- Predefined order for main categories
    local orderMap = {
        ["Quest"] = 1,
        ["Consumable"] = 2,
        ["Trade Goods"] = 3,
        ["Weapon"] = 4,
        ["Armor"] = 5,
        ["Container"] = 6,
        ["Gem"] = 7,
        ["Recipe"] = 8,
        [(IM.CATEGORY_EXCLUSION_NAMES and IM.CATEGORY_EXCLUSION_NAMES.currencyTokens) or "Currency Tokens"] = 9,
        ["Miscellaneous"] = 10,
        ["Other"] = 11,
    }
    
    return orderMap[categoryName] or 100
end

function CategoryView:GetSubcategoryOrder(subcategoryName, item)
    -- Get equipLoc from GetItemInfo (not GetItemInfoInstant)
    local _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID = GetItemInfo(item.itemID)
    
    -- For equipment slots, use predefined order
    if equipLoc and equipLoc ~= "" and equipLoc ~= "nil" and equipLoc ~= "INVTYPE_NON_EQUIP" and SLOT_ORDER_MAP[equipLoc] then
        return SLOT_ORDER_MAP[equipLoc]
    end
    
    -- For non-equipment, order by classID
    if classID then
        local classOrder = {
            [0] = 100,  -- Consumable
            [1] = 200,  -- Container
            [3] = 300,  -- Gem
            [5] = 400,  -- Reagent
            [7] = 500,  -- Trade Goods
            [9] = 600,  -- Recipe
            [12] = 50,  -- Quest (high priority)
            [15] = 700, -- Miscellaneous
            [20] = 800, -- Player Housing
        }
        local baseOrder = classOrder[classID] or 900
        return baseOrder + (string.byte(subcategoryName, 1) or 0)
    end
    
    -- Fallback: alphabetical
    return 1000 + (string.byte(subcategoryName, 1) or 0)
end

-- ============================================================================
-- RENDERING
-- ============================================================================

function CategoryView:RenderCategories(scrollContent, columnData)
    if not scrollContent or not columnData then return end
    
    for colIndex, column in ipairs(columnData) do
        for _, categoryData in ipairs(column) do
            self:RenderCategory(scrollContent, categoryData)
        end
    end
end

function CategoryView:RenderCategory(scrollContent, categoryData)
    local category = categoryData.category
    local x = categoryData.x
    local y = categoryData.y
    local width = categoryData.width
    
    -- Create category header
    local header = CreateFrame("Frame", nil, scrollContent)
    header:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", x, y)
    header:SetSize(width, UI.layout.rowHeightSmall)
    header._imCategoryHeader = true
    
    local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerText:SetPoint("LEFT", UI.layout.paddingSmall, 0)
    headerText:SetText(category.name)
    headerText:SetTextColor(unpack(UI.colors.accent))
    
    -- Render items
    local itemStartY = y - (IM.UI.layout.rowHeightSmall or 24) - (IM.UI.layout.elementSpacing or 6)
    local itemStartX = x + (IM.UI.layout.paddingSmall or 4)
    
    IM:Debug(string.format("[CategoryView] Rendering '%s': headerY=%d, itemStartY=%d, itemStartX=%d", 
        category.name, y, itemStartY, itemStartX))
    
    local settings = BagUI:GetSettings()
    local positions = BagUI.MasonryLayout:CalculateItemPositions(
        #category.items,
        itemStartX,
        itemStartY,
        width - (IM.UI.layout.padding or 8),
        settings.itemsPerRow or 8
    )
    
    for i, item in ipairs(category.items) do
        local button = BagUI.ItemButton:Acquire()
        if button then
            BagUI.ItemButton:SetItem(button, item.bagID, item.slotID)
            
            if i == 1 then
                IM:Debug(string.format("  First item at: x=%d, y=%d", positions[i].x, positions[i].y))
            end
            
            BagUI.ItemButton:SetPosition(button, positions[i].x, positions[i].y)
        end
    end
end
