--[[
    InventoryManager - Modules/CategoryExclusions.lua
    Category-based item exclusions management
]]

local addonName, IM = ...

local CategoryExclusions = {}
IM:RegisterModule("CategoryExclusions", CategoryExclusions)

-- Category definitions with WoW classID mappings
-- Reference: https://wowpedia.fandom.com/wiki/ItemType
CategoryExclusions.categories = {
    consumables = {
        name = "Consumables",
        description = "Food, potions, flasks, and other consumable items",
        classID = 0, -- Consumable
        subclassIDs = nil, -- All subclasses
    },
    questItems = {
        name = "Quest Items",
        description = "Items used for quests",
        classID = 12, -- Quest
        subclassIDs = nil,
    },
    craftingReagents = {
        name = "Crafting Reagents",
        description = "Profession crafting materials",
        classID = 5, -- Reagent (Tradeskill in older API)
        subclassIDs = nil,
    },
    tradeGoods = {
        name = "Trade Goods",
        description = "Trade skill materials and products",
        classID = 7, -- Tradeskill
        subclassIDs = nil,
    },
    toys = {
        name = "Toys",
        description = "Toy items",
        classID = 15, -- Miscellaneous
        subclassIDs = {2}, -- Companion Pets is 2 in Miscellaneous, Toys is different
        -- Note: Toys might need special handling via C_ToyBox
    },
    pets = {
        name = "Battle Pets",
        description = "Battle pet items",
        classID = 17, -- Battlepet
        subclassIDs = nil,
    },
    mounts = {
        name = "Mounts",
        description = "Mount items",
        classID = 15, -- Miscellaneous
        subclassIDs = {5}, -- Mount subclass
    },
}

-- Check if an item is in an excluded category
function CategoryExclusions:IsExcluded(itemID, classID, subclassID)
    local db = IM.db.global.categoryExclusions

    for key, category in pairs(self.categories) do
        -- Check if this category is enabled for exclusion
        if db[key] then
            -- Check if item matches this category
            if classID == category.classID then
                -- If no specific subclasses, all items in this class are excluded
                if not category.subclassIDs then
                    return true, key
                end

                -- Check specific subclasses
                for _, subID in ipairs(category.subclassIDs) do
                    if subclassID == subID then
                        return true, key
                    end
                end
            end
        end
    end

    return false, nil
end

-- Get list of all category definitions
function CategoryExclusions:GetCategories()
    return self.categories
end

-- Toggle a category exclusion
function CategoryExclusions:Toggle(categoryKey)
    local db = IM.db.global.categoryExclusions
    db[categoryKey] = not db[categoryKey]
    return db[categoryKey]
end

-- Enable a category exclusion
function CategoryExclusions:Enable(categoryKey)
    IM.db.global.categoryExclusions[categoryKey] = true
end

-- Disable a category exclusion
function CategoryExclusions:Disable(categoryKey)
    IM.db.global.categoryExclusions[categoryKey] = false
end

-- Check if a category is currently excluded
function CategoryExclusions:IsEnabled(categoryKey)
    return IM.db.global.categoryExclusions[categoryKey] == true
end

-- Get human-readable list of enabled exclusions
function CategoryExclusions:GetEnabledList()
    local enabled = {}
    local db = IM.db.global.categoryExclusions

    for key, category in pairs(self.categories) do
        if db[key] then
            table.insert(enabled, category.name)
        end
    end

    return enabled
end
