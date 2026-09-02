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

-- Header frame pool (prevents frame leak that causes stack overflow)
local _headerPool = {}
local _activeHeaders = {}

-- Category surface pool. These are TEXTURES, not frames: textures in the
-- BACKGROUND draw layer always render beneath child frames, so the item
-- buttons can never end up hidden behind a category block.
local _surfacePool = {}
local _activeSurfaces = {}
local _emptyStateText = nil

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
-- HEADER POOL
-- ============================================================================

local function _AcquireHeader(scrollContent)
    local header = table.remove(_headerPool)
    if not header then
        header = CreateFrame("Frame", nil, scrollContent)
        header._imCategoryHeader = true
    else
        header:SetParent(scrollContent)
    end
    header:ClearAllPoints()
    header:Show()
    table.insert(_activeHeaders, header)
    return header
end

local function _AcquireSurface(scrollContent, texturePath, l, r, t, b)
    local tex = table.remove(_surfacePool)
    if not tex then
        tex = scrollContent:CreateTexture(nil, "BACKGROUND")
    end
    tex:SetTexture(texturePath or "Interface\\Buttons\\WHITE8X8")
    tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
    tex:ClearAllPoints()
    tex:Show()
    table.insert(_activeSurfaces, tex)
    return tex
end

--[[
    Draw a rounded filled rectangle into the scroll content.

    Same four-corners-plus-three-fills construction as UI:AttachRoundedSurface,
    but positioned by offset rather than anchored to a frame, because category
    blocks are drawn as pooled textures on the shared scroll content - a frame
    per block risks the item buttons ending up behind it.
]]
local function _DrawRoundedBlock(scrollContent, x, y, w, h, color, radius)
    if w <= radius * 2 or h <= radius * 2 then
        radius = math.max(math.floor(math.min(w, h) / 2) - 1, 0)
    end

    local CORNER = UI.ROUNDED_CORNER

    local function Place(tex, px, py, pw, ph)
        tex:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", px, py)
        tex:SetSize(pw, ph)
        tex:SetVertexColor(unpack(color))
    end

    if radius > 0 then
        Place(_AcquireSurface(scrollContent, CORNER, 0, 1, 0, 1), x, y, radius, radius)
        Place(_AcquireSurface(scrollContent, CORNER, 1, 0, 0, 1), x + w - radius, y, radius, radius)
        Place(_AcquireSurface(scrollContent, CORNER, 0, 1, 1, 0), x, y - h + radius, radius, radius)
        Place(_AcquireSurface(scrollContent, CORNER, 1, 0, 1, 0), x + w - radius, y - h + radius, radius, radius)

        Place(_AcquireSurface(scrollContent), x + radius, y, w - radius * 2, radius)
        Place(_AcquireSurface(scrollContent), x + radius, y - h + radius, w - radius * 2, radius)
    end

    Place(_AcquireSurface(scrollContent), x, y - radius, w, h - radius * 2)
end

local function _ReleaseAllSurfaces()
    for _, tex in ipairs(_activeSurfaces) do
        tex:Hide()
        tex:ClearAllPoints()
        table.insert(_surfacePool, tex)
    end
    wipe(_activeSurfaces)
end

local function _ReleaseAllHeaders()
    for _, header in ipairs(_activeHeaders) do
        header:Hide()
        header:ClearAllPoints()
        table.insert(_headerPool, header)
    end
    wipe(_activeHeaders)
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

    -- Release all category headers and surfaces back to their pools
    _ReleaseAllHeaders()
    _ReleaseAllSurfaces()

    -- Hide empty state from previous render
    if _emptyStateText then
        _emptyStateText:Hide()
    end

    -- Gather items from bags (filtered by search)
    local items = self:GatherItems()

    -- Handle empty state (no items or no search results)
    if #items == 0 then
        local searchFilter = BagUI:GetSearchFilter()

        if not _emptyStateText then
            _emptyStateText = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            _emptyStateText:SetPoint("CENTER", scrollContent, "CENTER", 0, 50)
        end

        if searchFilter and searchFilter ~= "" then
            _emptyStateText:SetText("|cff888888No items match \"" .. searchFilter .. "\"|r")
        else
            _emptyStateText:SetText("|cff888888No items in bags|r")
        end
        _emptyStateText:Show()

        -- Set minimal scroll content height
        local itemSize = BagUI.MasonryLayout:GetItemSize()
        scrollContent:SetHeight(itemSize + 40)
        return
    end

    -- Organize into categories (GetViewMode sanitizes stale saved modes)
    local categories = self:Organize(items, BagUI:GetViewMode())

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

    -- Debug: trace the width chain
    local scrollFrame = scrollContent:GetParent()
    local scrollContainer = scrollFrame and scrollFrame:GetParent() or nil
    local contentContainer = scrollContainer and scrollContainer:GetParent() or nil
    local bagFrame = contentContainer and contentContainer:GetParent() or nil

    IM:Debug(string.format("[CategoryView] Width chain: bagFrame=%d, contentContainer=%d, scrollContainer=%d, scrollFrame=%d, scrollContent=%d",
        bagFrame and bagFrame:GetWidth() or -1,
        contentContainer and contentContainer:GetWidth() or -1,
        scrollContainer and scrollContainer:GetWidth() or -1,
        scrollFrame and scrollFrame:GetWidth() or -1,
        containerWidth))

    -- Dynamic fallback based on parent frame width
    if containerWidth <= 0 then
        containerWidth = (scrollContent:GetParent() and scrollContent:GetParent():GetWidth() or 480) - 40
        IM:Debug(string.format("[CategoryView] Using fallback containerWidth=%d", containerWidth))
    end

    local columnData, totalHeight = BagUI.MasonryLayout:CalculateFromSettings(categories, containerWidth)

    -- Render categories and track actual content bounds
    local contentBounds = { maxX = 0, maxY = 0 }
    self:RenderCategories(scrollContent, columnData, contentBounds)

    -- Set scroll content size from actual rendered bounds
    local itemSize = BagUI.MasonryLayout:GetItemSize()
    local padding = IM.UI.layout.padding or 8

    -- Calculate actual required dimensions
    local requiredHeight = contentBounds.maxY + itemSize + padding

    IM:Debug(string.format("[CategoryView] Content bounds: maxX=%d, maxY=%d, containerWidth=%d, requiredHeight=%d",
        contentBounds.maxX, contentBounds.maxY, containerWidth, requiredHeight))

    -- Check for horizontal overflow - if content exceeds container, we need wider frame
    if contentBounds.maxX > containerWidth then
        IM:Debug(string.format("[CategoryView] WIDTH OVERFLOW: content=%d > container=%d", contentBounds.maxX, containerWidth))
        -- Signal that frame needs to be wider (will be handled by BagUI:OnContentOverflow)
        if BagUI.OnContentOverflow then
            BagUI:OnContentOverflow(contentBounds.maxX, containerWidth)
        end
    end

    scrollContent:SetHeight(math.max(requiredHeight, itemSize + 40))
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

    -- Match secondary stats, so "haste" or "crit / mastery" filters gear directly
    local ItemStats = IM:GetModule("ItemStats")
    if ItemStats and ItemStats:IsEquippable(item.itemID) then
        local combo = ItemStats:GetSecondaryCombo(item.hyperlink)
        if combo and combo:lower():find(filterLower, 1, true) then
            return true
        end

        local stats = ItemStats:GetSecondaries(item.hyperlink)
        if stats then
            for _, stat in ipairs(stats) do
                if stat.name:lower():find(filterLower, 1, true) then
                    return true
                end
            end
        end
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
-- VIEW MODES
-- ============================================================================

--[[
    Each view mode classifies one item into a group label plus that group's sort
    weight. Stat modes reclassify EQUIPPABLE GEAR ONLY - consumables, reagents and
    the rest keep their normal category and render below the stat groups, so the
    bag never hides items just because they have no secondaries.

    Group order convention:
      0-99    stat groups (canonical stat order)
      100+    normal categories in category/subcategory mode
      500+    normal categories rendered underneath a stat view
]]

local STAT_FALLBACK_ORDER = 500

-- Resolve a stat group label for gear, or nil when the item is not gear
local function _StatGroupFor(item, resolve)
    local ItemStats = IM:GetModule("ItemStats")
    if not ItemStats then return nil end
    if not ItemStats:IsEquippable(item.itemID) then return nil end

    -- nil means the client has not cached this item yet; ItemStats fires a
    -- refresh once the data lands, so bucket it visibly rather than silently
    return resolve(ItemStats, item.hyperlink) or ItemStats.UNKNOWN
end

local function _ClassifyByStat(view, item, resolve)
    local label = _StatGroupFor(item, resolve)
    if label then
        local ItemStats = IM:GetModule("ItemStats")
        return label, ItemStats:GetGroupOrder(label)
    end

    -- Not gear: keep its normal category, ranked below every stat group
    local categoryName = view:GetItemCategory(item)
    return categoryName, STAT_FALLBACK_ORDER + view:GetCategoryOrder(categoryName)
end

local VIEW_MODES = {
    category = function(view, item)
        local name = view:GetItemCategory(item)
        return name, 100 + view:GetCategoryOrder(name)
    end,

    subcategory = function(view, item)
        local name = view:GetItemSubcategory(item)
        return name, 100 + view:GetSubcategoryOrder(name, item)
    end,

    topstat = function(view, item)
        return _ClassifyByStat(view, item, function(ItemStats, link)
            return ItemStats:GetTopSecondary(link)
        end)
    end,

    statcombo = function(view, item)
        return _ClassifyByStat(view, item, function(ItemStats, link)
            return ItemStats:GetSecondaryCombo(link)
        end)
    end,
}

CategoryView.VIEW_MODES = VIEW_MODES

function CategoryView:IsValidViewMode(modeName)
    return modeName ~= nil and VIEW_MODES[modeName] ~= nil
end

-- ============================================================================
-- ORGANIZATION
-- ============================================================================

-- Pull equipment-set items into their own categories. Returns the set categories
-- and a lookup of which items were consumed by them.
local function _ExtractEquipmentSets(items)
    local categories, claimed = {}, {}

    local settings = BagUI:GetSettings()
    if not settings.showItemSets then return categories, claimed end
    if not (IM.Filters and IM.Filters.GetEquipmentSets) then return categories, claimed end

    local byName = {}
    for _, item in ipairs(items) do
        local sets = IM.Filters:GetEquipmentSets(item.itemID)
        if sets and #sets > 0 then
            claimed[item] = true
            for _, setName in ipairs(sets) do
                byName[setName] = byName[setName] or {}
                table.insert(byName[setName], item)
            end
        end
    end

    local setIndex = 0
    for setName, setItems in pairs(byName) do
        table.sort(setItems, function(a, b)
            local _, _, _, equipLocA = C_Item.GetItemInfoInstant(a.itemID)
            local _, _, _, equipLocB = C_Item.GetItemInfoInstant(b.itemID)
            local orderA = (equipLocA and SLOT_ORDER_MAP[equipLocA]) or 999
            local orderB = (equipLocB and SLOT_ORDER_MAP[equipLocB]) or 999
            return orderA < orderB
        end)

        table.insert(categories, {
            name = "Set: " .. setName,
            items = setItems,
            order = setIndex,  -- sets always render first
        })
        setIndex = setIndex + 1
    end

    return categories, claimed
end

-- Group items for a view mode. One organizer for every mode - adding a mode means
-- adding a VIEW_MODES entry, never another copy of this function.
function CategoryView:Organize(items, modeName)
    local classify = VIEW_MODES[modeName] or VIEW_MODES.category

    local categories, claimed = _ExtractEquipmentSets(items)
    local categoryMap = {}

    for _, item in ipairs(items) do
        if not claimed[item] then
            local name, order = classify(self, item)
            name = name or "Other"

            local category = categoryMap[name]
            if not category then
                category = { name = name, items = {}, order = order or 999 }
                table.insert(categories, category)
                categoryMap[name] = category
            end

            table.insert(category.items, item)
        end
    end

    table.sort(categories, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.name < b.name
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

function CategoryView:RenderCategories(scrollContent, columnData, contentBounds)
    if not scrollContent or not columnData then return end

    for colIndex, column in ipairs(columnData) do
        for _, categoryData in ipairs(column) do
            self:RenderCategory(scrollContent, categoryData, contentBounds)
        end
    end
end

function CategoryView:RenderCategory(scrollContent, categoryData, contentBounds)
    local category = categoryData.category
    local x = categoryData.x
    local y = categoryData.y
    local width = categoryData.width

    -- Get sizing from MasonryLayout (single source of truth)
    local leftMarginExtra = BagUI.MasonryLayout:GetLeftMarginExtra()

    -- Calculate item positions FIRST so we can anchor header to first item
    local itemStartY = y - (IM.UI.layout.rowHeightSmall or 24) - (IM.UI.layout.elementSpacing or 6)
    local itemStartX = x + leftMarginExtra

    IM:Debug(string.format("[CategoryView] Rendering '%s': headerY=%d, itemStartY=%d, itemStartX=%d",
        category.name, y, itemStartY, itemStartX))

    local settings = BagUI:GetSettings()
    local itemSize = BagUI.MasonryLayout:GetItemSize()
    local positions = BagUI.MasonryLayout:CalculateItemPositions(
        #category.items,
        itemStartX,
        itemStartY,
        width - 4,  -- Reduced inner padding
        settings.itemsPerRow or 8
    )

    -- Render items first and track the first button for header anchoring
    local firstButton = nil
    for i, item in ipairs(category.items) do
        local button = BagUI.ItemButton:Acquire()
        if button then
            BagUI.ItemButton:SetItem(button, item.bagID, item.slotID)
            BagUI.ItemButton:SetPosition(button, positions[i].x, positions[i].y)

            if i == 1 then
                firstButton = button
                IM:Debug(string.format("  First item at: x=%d, y=%d", positions[i].x, positions[i].y))
            end

            -- Track content bounds (positions use negative Y, convert to positive distance from top)
            if contentBounds then
                local rightEdge = positions[i].x + itemSize
                local bottomEdge = math.abs(positions[i].y)  -- Convert negative Y to positive distance
                if rightEdge > contentBounds.maxX then contentBounds.maxX = rightEdge end
                if bottomEdge > contentBounds.maxY then contentBounds.maxY = bottomEdge end
            end
        end
    end

    -- Raised surface behind the category. Elevation here is lightness, not a
    -- shadow: the block sits a few percent above the window ground, with a
    -- lighter hairline on its top edge and a darker one beneath, which reads
    -- as light falling from above.
    local blockHeight = categoryData.height or 0
    if blockHeight > 0 then
        local pad = 2  -- must stay under half of SIZING.CATEGORY_GAP
        local radius = UI.layout.radiusBlock
        local bx, by = x - pad, y + pad
        local bw = width + (pad * 2)
        local bh = blockHeight + (pad * 2)

        _DrawRoundedBlock(scrollContent, bx, by, bw, bh, UI.colors.backgroundLight, radius)

        -- Rims are inset by the radius so they stop where the arc begins,
        -- instead of poking out past the rounded corners.
        local rimTop = _AcquireSurface(scrollContent)
        rimTop:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", bx + radius, by)
        rimTop:SetSize(math.max(bw - radius * 2, 1), 1)
        rimTop:SetVertexColor(unpack(UI.colors.rimTop))

        local rimBottom = _AcquireSurface(scrollContent)
        rimBottom:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", bx + radius, by - bh + 1)
        rimBottom:SetSize(math.max(bw - radius * 2, 1), 1)
        rimBottom:SetVertexColor(unpack(UI.colors.rimBottom))
    end

    -- Acquire category header from pool
    local header = _AcquireHeader(scrollContent)
    header:SetSize(width, UI.layout.rowHeightSmall)

    if firstButton then
        local headerGap = IM.UI.layout.elementSpacing or 6
        header:SetPoint("BOTTOMLEFT", firstButton, "TOPLEFT", -leftMarginExtra, headerGap)
    else
        header:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", x, y)
    end

    -- Header carries the hierarchy now: near-white and heavier, instead of a
    -- small amber label competing with every other amber thing in the window.
    if not header._imHeaderText then
        local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headerText:SetPoint("LEFT", UI.layout.paddingSmall, 0)
        header._imHeaderText = headerText
    end
    header._imHeaderText:SetText(string.upper(category.name))
    header._imHeaderText:SetTextColor(unpack(UI.colors.text))

    -- Item count reads as a quiet chip beside the name
    if not header._imHeaderCount then
        local countText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("LEFT", header._imHeaderText, "RIGHT", UI.layout.paddingSmall + 2, 0)
        header._imHeaderCount = countText
    end
    header._imHeaderCount:SetText(tostring(#category.items))
    header._imHeaderCount:SetTextColor(unpack(UI.colors.textDisabled))
end
