--[[
    InventoryManager - CustomCategories.lua
    Custom category management for the Bag UI

    Allows users to create custom categories that override default
    classID-based categorization. Categories are assigned by itemID.

    Public Methods:
    - CustomCategories:CreateCategory(name) -> categoryID
    - CustomCategories:DeleteCategory(categoryID)
    - CustomCategories:RenameCategory(categoryID, newName)
    - CustomCategories:GetAllCategories() -> table
    - CustomCategories:GetByID(categoryID) -> category
    - CustomCategories:AssignItem(itemID, categoryID)
    - CustomCategories:UnassignItem(itemID)
    - CustomCategories:GetCategoryForItem(itemID) -> category or nil
    - CustomCategories:GetItemsInCategory(categoryID) -> table
    - CustomCategories:ReorderCategory(categoryID, newOrder)
]]

local addonName, IM = ...

local CustomCategories = {}
IM:RegisterModule("CustomCategories", CustomCategories)

-- Private state
local _callbacks = {
    OnCategoryCreated = {},
    OnCategoryDeleted = {},
    OnCategoryRenamed = {},
    OnItemAssigned = {},
    OnItemUnassigned = {},
}

-- Fire callbacks for an event
local function _FireCallbacks(eventName, ...)
    for _, callback in ipairs(_callbacks[eventName] or {}) do
        callback(...)
    end
end

-- Ensure database structure exists
local function _EnsureDB()
    if not IM.db then return false end

    if not IM.db.global.customCategories then
        IM.db.global.customCategories = {
            categories = {},
            itemAssignments = {},
            nextCategoryID = 1,
        }
    end

    return true
end

-- Get next available category ID
local function _GetNextID()
    if not _EnsureDB() then return nil end

    local id = IM.db.global.customCategories.nextCategoryID
    IM.db.global.customCategories.nextCategoryID = id + 1
    return id
end

-- Public API

function CustomCategories:CreateCategory(name)
    if not _EnsureDB() then return nil end
    if not name or name == "" then return nil end

    local id = _GetNextID()
    if not id then return nil end

    -- Find highest order
    local maxOrder = 0
    for _, cat in pairs(IM.db.global.customCategories.categories) do
        if cat.order > maxOrder then
            maxOrder = cat.order
        end
    end

    local category = {
        id = id,
        name = name,
        order = maxOrder + 1,
    }

    IM.db.global.customCategories.categories[id] = category

    IM:Debug("[CustomCategories] Created category: " .. name .. " (ID: " .. id .. ")")
    _FireCallbacks("OnCategoryCreated", category)

    return id
end

function CustomCategories:DeleteCategory(categoryID)
    if not _EnsureDB() then return false end
    if not categoryID then return false end

    local category = IM.db.global.customCategories.categories[categoryID]
    if not category then return false end

    -- Unassign all items from this category
    local itemAssignments = IM.db.global.customCategories.itemAssignments
    for itemID, catID in pairs(itemAssignments) do
        if catID == categoryID then
            itemAssignments[itemID] = nil
        end
    end

    -- Delete the category
    IM.db.global.customCategories.categories[categoryID] = nil

    IM:Debug("[CustomCategories] Deleted category: " .. category.name)
    _FireCallbacks("OnCategoryDeleted", categoryID, category)

    return true
end

function CustomCategories:RenameCategory(categoryID, newName)
    if not _EnsureDB() then return false end
    if not categoryID or not newName or newName == "" then return false end

    local category = IM.db.global.customCategories.categories[categoryID]
    if not category then return false end

    local oldName = category.name
    category.name = newName

    IM:Debug("[CustomCategories] Renamed category: " .. oldName .. " -> " .. newName)
    _FireCallbacks("OnCategoryRenamed", categoryID, oldName, newName)

    return true
end

function CustomCategories:GetAllCategories()
    if not _EnsureDB() then return {} end

    local result = {}
    for id, category in pairs(IM.db.global.customCategories.categories) do
        table.insert(result, category)
    end

    -- Sort by order
    table.sort(result, function(a, b)
        return (a.order or 0) < (b.order or 0)
    end)

    return result
end

function CustomCategories:GetByID(categoryID)
    if not _EnsureDB() then return nil end
    if not categoryID then return nil end

    return IM.db.global.customCategories.categories[categoryID]
end

function CustomCategories:AssignItem(itemID, categoryID)
    if not _EnsureDB() then return false end
    if not itemID or not categoryID then return false end

    -- Verify category exists
    if not IM.db.global.customCategories.categories[categoryID] then
        return false
    end

    local oldCategoryID = IM.db.global.customCategories.itemAssignments[itemID]
    IM.db.global.customCategories.itemAssignments[itemID] = categoryID

    -- Refresh BagData for this item
    local BagData = IM:GetModule("BagData")
    if BagData then
        BagData:RefreshItemStatus(itemID)
    end

    IM:Debug("[CustomCategories] Assigned item " .. itemID .. " to category " .. categoryID)
    _FireCallbacks("OnItemAssigned", itemID, categoryID, oldCategoryID)

    return true
end

function CustomCategories:UnassignItem(itemID)
    if not _EnsureDB() then return false end
    if not itemID then return false end

    local oldCategoryID = IM.db.global.customCategories.itemAssignments[itemID]
    if not oldCategoryID then return false end

    IM.db.global.customCategories.itemAssignments[itemID] = nil

    -- Refresh BagData for this item
    local BagData = IM:GetModule("BagData")
    if BagData then
        BagData:RefreshItemStatus(itemID)
    end

    IM:Debug("[CustomCategories] Unassigned item " .. itemID)
    _FireCallbacks("OnItemUnassigned", itemID, oldCategoryID)

    return true
end

function CustomCategories:GetCategoryForItem(itemID)
    if not _EnsureDB() then return nil end
    if not itemID then return nil end

    local categoryID = IM.db.global.customCategories.itemAssignments[itemID]
    if not categoryID then return nil end

    return IM.db.global.customCategories.categories[categoryID]
end

function CustomCategories:GetItemsInCategory(categoryID)
    if not _EnsureDB() then return {} end
    if not categoryID then return {} end

    local items = {}
    for itemID, catID in pairs(IM.db.global.customCategories.itemAssignments) do
        if catID == categoryID then
            table.insert(items, itemID)
        end
    end

    return items
end

function CustomCategories:ReorderCategory(categoryID, newOrder)
    if not _EnsureDB() then return false end
    if not categoryID or not newOrder then return false end

    local category = IM.db.global.customCategories.categories[categoryID]
    if not category then return false end

    -- Shift other categories
    for _, cat in pairs(IM.db.global.customCategories.categories) do
        if cat.id ~= categoryID and cat.order >= newOrder then
            cat.order = cat.order + 1
        end
    end

    category.order = newOrder

    return true
end

-- Callback registration
function CustomCategories:RegisterCallback(eventName, callback)
    if _callbacks[eventName] then
        table.insert(_callbacks[eventName], callback)
    end
end

function CustomCategories:UnregisterCallback(eventName, callback)
    if not _callbacks[eventName] then return end

    for i, cb in ipairs(_callbacks[eventName]) do
        if cb == callback then
            table.remove(_callbacks[eventName], i)
            break
        end
    end
end

function CustomCategories:OnInitialize()
    -- Nothing to do - database not ready yet
end

function CustomCategories:OnEnable()
    -- Ensure database structure
    _EnsureDB()
end
