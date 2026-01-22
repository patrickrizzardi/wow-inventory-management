--[[
    InventoryManager - UI/BagUI/Container.lua
    Category layout and item slot orchestration for Bag UI.
]]

local addonName, IM = ...

IM.UI.BagUI = IM.UI.BagUI or {}
local BagUI = IM.UI.BagUI
local ItemSlot = BagUI.ItemSlot

local Container = {}
BagUI.Container = Container

local ITEM_SIZE = 36
local ITEM_SPACING = 4
local HEADER_HEIGHT = 16
local HEADER_GAP = 4
local CATEGORY_GAP = 8
local CONTENT_PADDING = 4

local _instance = nil

local function _GetSettings()
    if IM.db and IM.db.global and IM.db.global.bagUI then
        return IM.db.global.bagUI
    end
    return {
        itemColumns = 10,
        categoryColumns = 2,
        groupingMode = "category",
    }
end

local function _HasReagentBagSlots()
    local slots = C_Container.GetContainerNumSlots(5) or 0
    return slots > 0
end

local function _AcquireCategory(self)
    local category = table.remove(self.categoryPool)
    if not category then
        category = CreateFrame("Frame", nil, self)
        category.header = category:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        category.header:SetPoint("TOPLEFT", 0, 0)
        category.header:SetJustifyH("LEFT")
        category.header:SetWordWrap(false)
        category.header:SetTextColor(unpack(IM.UI.colors.accent))
        category.items = {}
    end
    category:Show()
    category.items = category.items or {}
    return category
end

local function _ReleaseCategories(self)
    if not self.activeCategories then
        return
    end
    for _, category in ipairs(self.activeCategories) do
        for _, slot in ipairs(category.items) do
            ItemSlot:Release(slot)
        end
        wipe(category.items)
        category:Hide()
        category:ClearAllPoints()
        table.insert(self.categoryPool, category)
    end
    wipe(self.activeCategories)
end

local function _GetCategoryName(itemData, groupingMode)
    if itemData.bagID == 5 then
        return "Reagent Bag"
    end
    if groupingMode == "subcategory" then
        local displayCategory = itemData.displayCategory or ""
        if displayCategory:find("^Gear:") then
            return displayCategory
        end
        return itemData.displayGroup or itemData.displayCategory or "Miscellaneous"
    end
    return itemData.displayCategory or "Miscellaneous"
end

local function _SortCategories(a, b)
    local aReagent = a.name == "Reagent Bag"
    local bReagent = b.name == "Reagent Bag"
    if aReagent ~= bReagent then
        return aReagent
    end
    if a.isCustom ~= b.isCustom then
        return a.isCustom
    end
    return (a.name or "") < (b.name or "")
end

local function _SortItems(a, b)
    if a.name ~= b.name then
        return (a.name or "") < (b.name or "")
    end
    return (a.itemID or 0) < (b.itemID or 0)
end

function Container:_EnsureInstance()
    local parent = BagUI and BagUI.GetContentFrame and BagUI:GetContentFrame()
    if not parent then
        return nil
    end

    if not _instance or not _instance.SetParent then
        _instance = self:Create(parent)
    else
        _instance:SetParent(parent)
        _instance:ClearAllPoints()
        _instance:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        _instance:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end

    return _instance
end

function Container:QueueRefresh()
    if self == Container then
        local instance = self:_EnsureInstance()
        if instance then
            return instance:QueueRefresh()
        end
        return
    end

    if self._refreshPending then return end
    self._refreshPending = true

    C_Timer.After(0.05, function()
        self._refreshPending = false
        self:Refresh(self.searchQuery)
    end)
end

function Container:ApplySearch(query)
    if self == Container then
        local instance = self:_EnsureInstance()
        if instance then
            return instance:ApplySearch(query)
        end
        return
    end

    self.searchQuery = query or ""
    local queryLower = self.searchQuery:lower()

    for _, category in ipairs(self.activeCategories) do
        for _, slot in ipairs(category.items) do
            local itemData = slot.itemData
            local match = true
            if queryLower ~= "" then
                local name = itemData and itemData.name or ""
                match = name:lower():find(queryLower, 1, true) ~= nil
            end
            ItemSlot:SetDimmed(slot, not match)
        end
    end
end

function Container:Refresh(query)
    if self == Container then
        local instance = self:_EnsureInstance()
        if instance then
            return instance:Refresh(query)
        end
        return
    end

    local BagData = IM:GetModule("BagData")
    if not BagData then return end

    self.searchQuery = query or self.searchQuery or ""
    _ReleaseCategories(self)

    local settings = _GetSettings()
    local groupingMode = settings.groupingMode or "category"
    local maxItemColumns = math.max(1, settings.itemColumns or 10)
    local columnCount = math.max(1, settings.categoryColumns or 2)

    local categories = {}
    local items = BagData:GetAllItems()
    for _, itemData in ipairs(items) do
        local categoryName = _GetCategoryName(itemData, groupingMode)
        if not categories[categoryName] then
            categories[categoryName] = {
                name = categoryName,
                items = {},
                isCustom = itemData.isCustomCategory or false,
            }
        elseif itemData.isCustomCategory then
            categories[categoryName].isCustom = true
        end
        table.insert(categories[categoryName].items, itemData)
    end

    if _HasReagentBagSlots() and not categories["Reagent Bag"] then
        categories["Reagent Bag"] = {
            name = "Reagent Bag",
            items = {},
            isCustom = false,
        }
    end

    local categoryList = {}
    for _, category in pairs(categories) do
        table.sort(category.items, _SortItems)
        table.insert(categoryList, category)
    end
    table.sort(categoryList, _SortCategories)

    local regionWidth = (maxItemColumns * ITEM_SIZE) + ((maxItemColumns - 1) * ITEM_SPACING)
    local columnIndex = 1
    local columnSlotsUsed = 0
    local rowOffset = CONTENT_PADDING
    local currentRowHeight = 0
    local currentRowItemRows = 0
    local layoutRows = {}
    local rowIndex = 1

    for _, categoryData in ipairs(categoryList) do
        local itemCount = #categoryData.items
        local columns = math.min(maxItemColumns, math.max(1, itemCount))
        local rows = itemCount > 0 and math.ceil(itemCount / columns) or 0

        local height = HEADER_HEIGHT
        if rows > 0 then
            height = height + HEADER_GAP + (rows * ITEM_SIZE) + ((rows - 1) * ITEM_SPACING)
        end

        if columnSlotsUsed + columns > maxItemColumns then
            columnIndex = columnIndex + 1
            columnSlotsUsed = 0
        end
        if columnIndex > columnCount then
            if currentRowHeight > 0 then
                layoutRows[rowIndex] = {
                    itemRows = currentRowItemRows,
                }
                rowIndex = rowIndex + 1
            end
            rowOffset = rowOffset + currentRowHeight + CATEGORY_GAP
            currentRowHeight = 0
            currentRowItemRows = 0
            columnIndex = 1
            columnSlotsUsed = 0
        end

        local x = CONTENT_PADDING
            + ((columnIndex - 1) * (regionWidth + CATEGORY_GAP))
            + (columnSlotsUsed * (ITEM_SIZE + ITEM_SPACING))
        local y = rowOffset

        local categoryFrame = _AcquireCategory(self)
        local width = (columns * ITEM_SIZE) + ((columns - 1) * ITEM_SPACING)
        categoryFrame:SetSize(width, height)
        categoryFrame:ClearAllPoints()
        categoryFrame:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        categoryFrame.header:SetWidth(width)
        categoryFrame.header:SetText(string.format("%s (%d)", categoryData.name, itemCount))

        local col = 0
        local row = 0
        for _, itemData in ipairs(categoryData.items) do
            local slot = ItemSlot:Acquire(categoryFrame)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", categoryFrame, "TOPLEFT", col * (ITEM_SIZE + ITEM_SPACING), -(HEADER_HEIGHT + HEADER_GAP) - (row * (ITEM_SIZE + ITEM_SPACING)))
            ItemSlot:SetItem(slot, itemData)

            table.insert(categoryFrame.items, slot)

            col = col + 1
            if col >= columns then
                col = 0
                row = row + 1
            end
        end

        table.insert(self.activeCategories, categoryFrame)

        columnSlotsUsed = columnSlotsUsed + columns
        currentRowHeight = math.max(currentRowHeight, height)
        currentRowItemRows = math.max(currentRowItemRows, rows)
    end

    if currentRowHeight > 0 then
        layoutRows[rowIndex] = {
            itemRows = currentRowItemRows,
        }
    end

    local totalHeight = rowOffset + currentRowHeight + CONTENT_PADDING

    self:SetHeight(math.max(totalHeight, 1))
    self._layoutRows = layoutRows
    local parent = self:GetParent()
    if parent and parent.SetHeight then
        parent:SetHeight(self:GetHeight())
    end

    self:ApplySearch(self.searchQuery)

    if self.onLayoutChanged then
        self.onLayoutChanged(self:GetHeight())
    end
end

function Container:GetHeightForItemRows(targetRows)
    if not self._layoutRows or #self._layoutRows == 0 then
        return nil
    end

    local remaining = math.max(1, targetRows or 1)
    local height = CONTENT_PADDING

    for index, row in ipairs(self._layoutRows) do
        local rowItemRows = row.itemRows or 0
        local headerHeight = rowItemRows > 0 and (HEADER_HEIGHT + HEADER_GAP) or HEADER_HEIGHT

        if rowItemRows > 0 then
            local rowsToShow = math.min(remaining, rowItemRows)
            local itemsHeight = (rowsToShow * (ITEM_SIZE + ITEM_SPACING)) - ITEM_SPACING
            height = height + headerHeight + itemsHeight
            remaining = remaining - rowsToShow
        else
            height = height + headerHeight
        end

        if remaining <= 0 then
            break
        end

        height = height + CATEGORY_GAP
    end

    height = height + CONTENT_PADDING
    return math.max(height, 1)
end

function Container:Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    frame:SetHeight(1)

    frame.categoryPool = {}
    frame.activeCategories = {}
    frame.searchQuery = ""
    frame._refreshPending = false

    if Mixin then
        Mixin(frame, Container)
    else
        for key, value in pairs(Container) do
            if type(value) == "function" and frame[key] == nil then
                frame[key] = value
            end
        end
    end

    return frame
end
