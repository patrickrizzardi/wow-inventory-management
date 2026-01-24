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
    
    -- Clear any existing category headers
    for _, child in ipairs({scrollContent:GetChildren()}) do
        if child._imCategoryHeader then
            child:Hide()
        end
    end
    
    -- Gather items from bags
    local items = self:GatherItems()
    
    -- Organize into categories
    local settings = BagUI:GetSettings()
    local categories
    if settings.viewMode == "subcategory" then
        categories = self:OrganizeBySubcategory(items)
    else
        categories = self:OrganizeByCategory(items)
    end
    
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
    local settings = BagUI:GetSettings()
    local itemSize = BagUI.MasonryLayout:GetItemSize()
    local minHeight = itemSize + 40  -- One row + padding
    scrollContent:SetHeight(math.max(totalHeight + 20, minHeight))
end

-- ============================================================================
-- ITEM GATHERING
-- ============================================================================

function CategoryView:GatherItems()
    local items = {}
    
    -- Scan regular bags (backpack + all equipped bags)
    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
            if itemInfo then
                table.insert(items, {
                    bagID = bagID,
                    slotID = slotID,
                    itemID = itemInfo.itemID,
                    iconFileID = itemInfo.iconFileID,
                    stackCount = itemInfo.stackCount,
                    quality = itemInfo.quality,
                    isLocked = itemInfo.isLocked,
                    hyperlink = itemInfo.hyperlink,
                })
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
                    table.insert(items, {
                        bagID = reagentBagID,
                        slotID = slotID,
                        itemID = itemInfo.itemID,
                        iconFileID = itemInfo.iconFileID,
                        stackCount = itemInfo.stackCount,
                        quality = itemInfo.quality,
                        isLocked = itemInfo.isLocked,
                        hyperlink = itemInfo.hyperlink,
                    })
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
    local equipmentSetItems = {}
    if settings.showItemSets then
        for _, item in ipairs(items) do
            if IM.Filters and IM.Filters.IsInEquipmentSet and IM.Filters:IsInEquipmentSet(item.itemID) then
                table.insert(equipmentSetItems, item)
            end
        end
    end
    
    -- Create "Equipment Sets" category first if we have items
    if #equipmentSetItems > 0 then
        local setCategory = {
            name = "Equipment Sets",
            items = equipmentSetItems,
            order = 0,  -- Always first
        }
        table.insert(categories, setCategory)
        categoryMap["Equipment Sets"] = setCategory
    end
    
    -- Categorize remaining items
    for _, item in ipairs(items) do
        -- Skip if already in equipment set category
        if settings.showItemSets and IM.Filters and IM.Filters.IsInEquipmentSet and IM.Filters:IsInEquipmentSet(item.itemID) then
            -- Already in equipment sets category
        else
            local categoryName = self:GetItemCategory(item)
            
            if not categoryMap[categoryName] then
                local category = {
                    name = categoryName,
                    items = {},
                    order = self:GetCategoryOrder(categoryName),
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
    
    for _, item in ipairs(items) do
        local categoryName = self:GetItemSubcategory(item)
        
        if not categoryMap[categoryName] then
            local category = {
                name = categoryName,
                items = {},
                order = self:GetSubcategoryOrder(categoryName, item),
            }
            table.insert(categories, category)
            categoryMap[categoryName] = category
        end
        
        table.insert(categoryMap[categoryName].items, item)
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

function CategoryView:GetItemCategory(item)
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(item.itemID)
    
    if classID then
        return IM.ITEM_CLASS_NAMES[classID] or "Other"
    end
    
    return "Other"
end

function CategoryView:GetItemSubcategory(item)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item.itemID)
    
    -- For equipment, use equipment slot
    if classID == IM.ITEM_CLASS.Armor or classID == IM.ITEM_CLASS.Weapon then
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(item.itemID)
        if equipLoc and equipLoc ~= "" then
            return _G[equipLoc] or equipLoc
        end
    end
    
    -- For other items, use subclass name
    if classID and subclassID then
        local subclassName = C_Item.GetItemSubClassInfo(classID, subclassID)
        if subclassName then
            return subclassName
        end
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
        ["Miscellaneous"] = 9,
        ["Other"] = 10,
    }
    
    return orderMap[categoryName] or 100
end

function CategoryView:GetSubcategoryOrder(subcategoryName, item)
    -- For equipment slots, use predefined order
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(item.itemID)
    if equipLoc and SLOT_ORDER_MAP[equipLoc] then
        return SLOT_ORDER_MAP[equipLoc]
    end
    
    -- Alphabetical for everything else
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
