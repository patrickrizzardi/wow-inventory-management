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

-- Get sizing constants from BagUI (single source of truth)
local function _GetSizing()
    if BagUI.GetSizingConstants then
        return BagUI:GetSizingConstants()
    end
    -- Fallback if not available yet
    return {
        BUTTON_BORDER_PADDING = 17,
        ITEM_GAP = 4,
        CATEGORY_PADDING = 6,
        CATEGORY_GAP = 12,
        BLOCK_PADDING = 8,
    }
end

-- Get item size dynamically from bag settings
function MasonryLayout:GetItemSize()
    local settings = BagUI:GetSettings()
    local iconSize = settings.iconSize or 20
    local sizing = _GetSizing()
    return iconSize + sizing.BUTTON_BORDER_PADDING
end

function MasonryLayout:GetCategoryPadding()
    local sizing = _GetSizing()
    return sizing.CATEGORY_PADDING
end

function MasonryLayout:GetItemGap()
    local sizing = _GetSizing()
    return sizing.ITEM_GAP
end

function MasonryLayout:GetBlockPadding()
    local sizing = _GetSizing()
    return sizing.BLOCK_PADDING
end

--[[
    How many items fit across one category block, and how wide their area is.

    THE single answer to that question. It was previously computed twice - once
    in CalculateCategoryHeight from the block width, once in
    CalculateItemPositions from (block width - 4) - so the two could disagree
    by a column. When they did, the renderer wrapped an extra row that the
    reserved height knew nothing about, and the items hung outside the block.

    Both callers now go through here, so they cannot drift again.
]]
function MasonryLayout:GetItemAreaWidth(blockWidth)
    -- Items are inset by the left margin; mirror it on the right
    return blockWidth - (self:GetBlockPadding() * 2)
end

function MasonryLayout:GetItemsPerRow(blockWidth, maxPerRow)
    local itemSize = self:GetItemSize()
    local gap = self:GetItemGap()

    -- N items occupy N*size + (N-1)*gap, so solve for N including the gaps.
    -- The old floor(width / itemSize) ignored them and over-counted.
    local fits = math.floor((self:GetItemAreaWidth(blockWidth) + gap) / (itemSize + gap))

    return math.max(1, math.min(maxPerRow or 8, fits))
end

function MasonryLayout:GetCategoryGap()
    local sizing = _GetSizing()
    return sizing.CATEGORY_GAP or 12
end

function MasonryLayout:GetRowPadding()
    -- Vertical spacing between category groups. Shares one constant with the
    -- horizontal gap so blocks are separated by the same amount in both axes.
    return self:GetCategoryGap()
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
--[[
    Sections are full width and stacked, one per row.

    Categories used to be packed two-per-row into multiple columns so small
    ones did not each cost a whole row. That packing is what stopped items
    lining up: every category started its grid at its own x, so icons in one
    section never aligned with the section above it. A single full-width column
    puts every item on one shared grid, which is the alignment that reads as
    tidy. Width is set by itemsPerRow instead of a column count.
]]
function MasonryLayout:Calculate(categories, containerWidth, columns, itemsPerRow)
    columns = 1
    itemsPerRow = itemsPerRow or 8

    -- Get dynamic sizing from single source of truth
    local itemSize = self:GetItemSize()
    local categoryPadding = self:GetCategoryPadding()
    local columnGap = 0  -- single column
    local rowPadding = self:GetRowPadding()

    -- Debug: Verify we got valid values
    if not itemSize or not categoryPadding or not rowPadding then
        IM:Debug("[MasonryLayout] ERROR: Invalid sizing values!")
        -- Emergency fallbacks
        itemSize = itemSize or 37
        categoryPadding = categoryPadding or 6
        columnGap = columnGap or 12
        rowPadding = rowPadding or 6
    end

    local categoryGapHorizontal = self:GetCategoryGap()  -- Gap between categories sharing a row
    
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
    
    -- One category per row, full width. No packing: see the note on Calculate.
    local groups = {}
    for _, category in ipairs(categories) do
        table.insert(groups, { category })
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

    -- Get dynamic sizing from single source of truth
    local itemSize = self:GetItemSize()
    local itemGap = self:GetItemGap()

    -- Header height (category name)
    local headerHeight = (IM.UI.layout.rowHeightSmall or 24) + (IM.UI.layout.elementSpacing or 6)

    -- Same answer the renderer will use; see GetItemsPerRow
    local itemsPerRowActual = self:GetItemsPerRow(availableWidth, itemsPerRow)

    -- Calculate number of rows needed
    local numRows = math.ceil(itemCount / itemsPerRowActual)

    -- Calculate item area height (itemSize + gap for each row, minus gap after last row)
    local itemsHeight = numRows * itemSize + (numRows - 1) * itemGap

    -- Total height with bottom padding
    return headerHeight + itemsHeight + self:GetBlockPadding()
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

    -- Get dynamic sizing from single source of truth
    local itemSize = self:GetItemSize()
    local itemGap = self:GetItemGap()

    local itemsPerRowActual = self:GetItemsPerRow(availableWidth, itemsPerRow)

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
            currentY = currentY - (itemSize + itemGap)
            itemsInCurrentRow = 0
        else
            -- Next item in row
            currentX = currentX + itemSize + itemGap
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
