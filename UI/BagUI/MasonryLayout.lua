--[[
    InventoryManager - UI/BagUI/MasonryLayout.lua
    Masonry layout algorithm for efficient category organization.
    Allows multiple categories to share rows when space permits.
]]

local addonName, IM = ...
local UI = IM.UI

-- Ensure BagUI namespace exists
UI.BagUI = UI.BagUI or {}
local BagUI = UI.BagUI

BagUI.MasonryLayout = {}
local MasonryLayout = BagUI.MasonryLayout

-- ============================================================================
-- DYNAMIC LAYOUT HELPERS
-- ============================================================================

-- Get item size dynamically from bag settings
function MasonryLayout:GetItemSize()
    -- Read from bag settings (user-configurable), fallback to UI constant
    local settings = BagUI:GetSettings()
    local iconSize = settings.iconSize or (IM.UI and IM.UI.layout and IM.UI.layout.iconSize) or 20
    return iconSize + 17  -- icon + border/padding (matches ItemButton size)
end

function MasonryLayout:GetCategoryPadding()
    -- Access via IM.UI to ensure we get the live reference
    return (IM.UI and IM.UI.layout and IM.UI.layout.cardSpacing) or 10
end

function MasonryLayout:GetRowPadding()
    -- Access via IM.UI to ensure we get the live reference
    return (IM.UI and IM.UI.layout and IM.UI.layout.elementSpacing) or 6
end

-- ============================================================================
-- MASONRY ALGORITHM
-- ============================================================================

--[[
    Calculates optimal layout for categories in a masonry grid.
    Categories can share rows horizontally (max 2 per row) if they fit within itemsPerRow limit.
    
    @param categories: Array of {name, items} tables
    @param containerWidth: Available width for layout
    @param columns: Number of masonry columns
    @param itemsPerRow: Max items before wrapping within a category
    @return layout: Array of column data with positioned categories
]]
function MasonryLayout:Calculate(categories, containerWidth, columns, itemsPerRow)
    columns = columns or 1
    itemsPerRow = itemsPerRow or 8
    
    -- Get dynamic sizing
    local itemSize = self:GetItemSize()
    local categoryPadding = self:GetCategoryPadding()
    local rowPadding = self:GetRowPadding()
    
    -- Debug: Verify we got valid values
    if not itemSize or not categoryPadding or not rowPadding then
        IM:Debug("[MasonryLayout] ERROR: Invalid sizing values!")
        IM:Debug("  itemSize: " .. tostring(itemSize))
        IM:Debug("  categoryPadding: " .. tostring(categoryPadding))
        IM:Debug("  rowPadding: " .. tostring(rowPadding))
        IM:Debug("  UI: " .. tostring(UI))
        IM:Debug("  UI.layout: " .. tostring(UI and UI.layout))
        
        -- Emergency fallbacks
        itemSize = itemSize or 37
        categoryPadding = categoryPadding or 10
        rowPadding = rowPadding or 6
    end
    
    local columnGap = categoryPadding * 2  -- Gap between columns (20px)
    local categoryGapHorizontal = categoryPadding  -- Gap between categories sharing a row
    
    -- Calculate column width
    local totalPadding = categoryPadding * 2  -- Left and right padding
    local totalGaps = columnGap * (columns - 1)  -- Gaps between columns
    local columnWidth = math.floor((containerWidth - totalPadding - totalGaps) / columns)
    
    -- Safety check: ensure positive column width
    if columnWidth <= 0 then
        IM:Debug("[MasonryLayout] WARNING: Invalid column width!")
        columns = 1
        columnWidth = containerWidth - (categoryPadding * 2)
    end
    
    IM:Debug(string.format("[MasonryLayout] Layout: width=%d, cols=%d, colWidth=%d, padding=%d, itemsPerRow=%d", 
        containerWidth, columns, columnWidth, categoryPadding, itemsPerRow))
    
    -- Initialize columns
    local columnData = {}
    for i = 1, columns do
        columnData[i] = {}
    end
    
    -- Group categories that can share rows (max 2 per row, total items <= itemsPerRow)
    local groups = {}
    local currentGroup = {}
    local currentGroupItemCount = 0
    
    for _, category in ipairs(categories) do
        local itemCount = #category.items
        
        -- Can we add this category to current group?
        local canAddToGroup = #currentGroup < 2 and 
                              (currentGroupItemCount + itemCount) <= itemsPerRow
        
        if canAddToGroup and #currentGroup > 0 then
            -- Add to current group
            table.insert(currentGroup, category)
            currentGroupItemCount = currentGroupItemCount + itemCount
        else
            -- Start new group
            if #currentGroup > 0 then
                table.insert(groups, currentGroup)
            end
            currentGroup = {category}
            currentGroupItemCount = itemCount
        end
    end
    
    -- Don't forget the last group
    if #currentGroup > 0 then
        table.insert(groups, currentGroup)
    end
    
    IM:Debug(string.format("[MasonryLayout] Created %d groups from %d categories", #groups, #categories))
    
    -- Distribute groups across columns
    local columnHeights = {}
    for i = 1, columns do
        columnHeights[i] = 0
    end
    
    for _, group in ipairs(groups) do
        -- Find shortest column
        local shortestCol = 1
        local shortestHeight = columnHeights[1]
        for col = 2, columns do
            if columnHeights[col] < shortestHeight then
                shortestCol = col
                shortestHeight = columnHeights[col]
            end
        end
        
        -- Calculate layout for this group
        local groupHeight = 0
        if #group == 1 then
            -- Single category in group - full width
            local category = group[1]
            local categoryHeight = self:CalculateCategoryHeight(category, columnWidth, itemsPerRow)
            local x = categoryPadding + (shortestCol - 1) * (columnWidth + columnGap)
            
            table.insert(columnData[shortestCol], {
                category = category,
                x = x,
                y = -columnHeights[shortestCol],
                width = columnWidth,
                height = categoryHeight,
            })
            
            groupHeight = categoryHeight
        else
            -- Multiple categories sharing row - split width
            local numCatsInGroup = #group
            local categoryWidth = math.floor((columnWidth - (categoryGapHorizontal * (numCatsInGroup - 1))) / numCatsInGroup)
            
            for i, category in ipairs(group) do
                local x = categoryPadding + (shortestCol - 1) * (columnWidth + columnGap) + (i - 1) * (categoryWidth + categoryGapHorizontal)
                local categoryHeight = self:CalculateCategoryHeight(category, categoryWidth, itemsPerRow)
                
                table.insert(columnData[shortestCol], {
                    category = category,
                    x = x,
                    y = -columnHeights[shortestCol],
                    width = categoryWidth,
                    height = categoryHeight,
                })
                
                -- Group height is the tallest category in the group
                if categoryHeight > groupHeight then
                    groupHeight = categoryHeight
                end
            end
        end
        
        IM:Debug(string.format("  Group (%d categories) -> col %d: y=%d, h=%d", 
            #group, shortestCol, -columnHeights[shortestCol], groupHeight))
        
        -- Update column height
        columnHeights[shortestCol] = columnHeights[shortestCol] + groupHeight + rowPadding
    end
    
    -- Calculate total content height
    local totalHeight = 0
    for _, height in ipairs(columnHeights) do
        if height > totalHeight then
            totalHeight = height
        end
    end
    
    return columnData, totalHeight
end

-- ============================================================================
-- CATEGORY DIMENSIONS
-- ============================================================================

function MasonryLayout:CalculateCategoryHeight(category, availableWidth, itemsPerRow)
    local itemCount = #category.items
    if itemCount == 0 then
        return 0
    end
    
    -- Get dynamic sizing
    local itemSize = self:GetItemSize()
    
    -- Header height (category name) - use IM.UI for live reference
    local headerHeight = (IM.UI.layout.rowHeightSmall or 24) + (IM.UI.layout.elementSpacing or 6)
    
    -- Calculate how many items fit per row
    local itemsPerRowActual = math.min(itemsPerRow, math.floor(availableWidth / itemSize))
    if itemsPerRowActual < 1 then itemsPerRowActual = 1 end
    
    -- Calculate number of rows needed
    local numRows = math.ceil(itemCount / itemsPerRowActual)
    
    -- Calculate item area height
    local itemsHeight = numRows * itemSize + (numRows - 1) * (IM.UI.layout.paddingSmall or 4)
    
    -- Total height
    return headerHeight + itemsHeight + (IM.UI.layout.padding or 8)
end

-- ============================================================================
-- SINGLE ROW LAYOUT (For items within a category)
-- ============================================================================

--[[
    Calculates positions for items within a category.
    
    @param itemCount: Number of items to layout
    @param startX: Starting X position
    @param startY: Starting Y position
    @param availableWidth: Width available for items
    @param itemsPerRow: Max items per row
    @return positions: Array of {x, y} tables
]]
function MasonryLayout:CalculateItemPositions(itemCount, startX, startY, availableWidth, itemsPerRow)
    local positions = {}
    
    -- Get dynamic sizing
    local itemSize = self:GetItemSize()
    local paddingSmall = IM.UI.layout.paddingSmall or 4
    
    local itemsPerRowActual = math.min(itemsPerRow, math.floor(availableWidth / itemSize))
    if itemsPerRowActual < 1 then itemsPerRowActual = 1 end
    
    local currentX = startX
    local currentY = startY
    local itemsInCurrentRow = 0
    
    for i = 1, itemCount do
        table.insert(positions, {
            x = currentX,
            y = currentY,
        })
        
        itemsInCurrentRow = itemsInCurrentRow + 1
        
        if itemsInCurrentRow >= itemsPerRowActual then
            -- Start new row
            currentX = startX
            currentY = currentY - (itemSize + paddingSmall)
            itemsInCurrentRow = 0
        else
            -- Next item in row
            currentX = currentX + itemSize + paddingSmall
        end
    end
    
    return positions
end

-- ============================================================================
-- SETTINGS-BASED LAYOUT
-- ============================================================================

--[[
    Convenience method that uses settings from BagUI.
    
    @param categories: Array of {name, items} tables
    @param containerWidth: Available width
    @return layout: Column data
    @return totalHeight: Total content height
]]
function MasonryLayout:CalculateFromSettings(categories, containerWidth)
    local settings = BagUI:GetSettings()
    local columns = settings.columns or 1
    local itemsPerRow = settings.itemsPerRow or 8
    
    return self:Calculate(categories, containerWidth, columns, itemsPerRow)
end
