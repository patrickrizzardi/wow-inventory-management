--[[
    InventoryManager - Modules/TooltipInfo.lua
    Adds comprehensive category and protection information to item tooltips
]]

local addonName, IM = ...

local TooltipInfo = {}
IM:RegisterModule("TooltipInfo", TooltipInfo)

-- Quality names for display
local QUALITY_NAMES = {
    [0] = "Poor",
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Artifact",
    [7] = "Heirloom"
}

-- Category exclusion names (matches database keys)
local CATEGORY_NAMES = IM.CATEGORY_EXCLUSION_NAMES or {}

function TooltipInfo:OnEnable()
    self:HookTooltips()
end

-- Get category name from classID
function TooltipInfo:GetCategoryName(classID, subclassID)
    local className = IM.ITEM_CLASS_NAMES and IM.ITEM_CLASS_NAMES[classID] or ("Class " .. classID)

    -- Get subclass name if available
    local subclassName = GetItemSubClassInfo(classID, subclassID)
    if subclassName and subclassName ~= "" and subclassName ~= className then
        return className .. " - " .. subclassName
    end

    return className
end

-- Find item in bags and return bag/slot if found (for binding checks)
function TooltipInfo:FindItemInBags(itemID)
    for _, bagID in ipairs(IM:GetBagIDsToScan()) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID == itemID then
                return bagID, slotID
            end
        end
    end
    return nil, nil
end

-- Get all active category exclusions for an item
function TooltipInfo:GetCategoryExclusions(classID, subclassID, itemID)
    local exclusions = {}
    local db = IM.db.global.categoryExclusions

    -- Toys (via C_ToyBox API)
    if db.toys and itemID and IM.Filters and IM.Filters:IsToy(itemID) then
        table.insert(exclusions, CATEGORY_NAMES.toys)
    end

    -- Mounts (via C_MountJournal API)
    if db.mounts and itemID and IM.Filters and IM.Filters:IsMount(itemID) then
        table.insert(exclusions, CATEGORY_NAMES.mounts)
    end

    -- Caged battle pets (itemID 82800)
    if db.pets and itemID and IM.Filters and IM.Filters:IsCagedPet(itemID) then
        table.insert(exclusions, CATEGORY_NAMES.pets)
    end

    -- Consumables (classID 0)
    if classID == 0 and db.consumables then
        table.insert(exclusions, CATEGORY_NAMES.consumables)
    end

    -- Quest items (classID 12)
    if classID == 12 and db.questItems then
        table.insert(exclusions, CATEGORY_NAMES.questItems)
    end

    -- Crafting reagents (classID 5)
    if classID == 5 and db.craftingReagents then
        table.insert(exclusions, CATEGORY_NAMES.craftingReagents)
    end

    -- Trade goods (classID 7)
    if classID == 7 and db.tradeGoods then
        table.insert(exclusions, CATEGORY_NAMES.tradeGoods)
    end

    -- Recipes (classID 9)
    if classID == 9 and db.recipes then
        table.insert(exclusions, CATEGORY_NAMES.recipes)
    end

    -- Battle pets (classID 17)
    if classID == 17 and db.pets then
        table.insert(exclusions, CATEGORY_NAMES.pets)
    end

    -- Currency tokens (classID 15, subclass 4)
    if classID == 15 and subclassID == 4 and db.currencyTokens then
        table.insert(exclusions, CATEGORY_NAMES.currencyTokens)
    end

    -- Mounts (classID 15, subclass 5) - fallback for classID detection
    if classID == 15 and subclassID == 5 and db.mounts then
        -- Only add if not already added by API check
        local alreadyAdded = false
        for _, v in ipairs(exclusions) do
            if v == CATEGORY_NAMES.mounts then
                alreadyAdded = true
                break
            end
        end
        if not alreadyAdded then
            table.insert(exclusions, CATEGORY_NAMES.mounts)
        end
    end

    -- Housing items (classID 20, subclass 1 ONLY)
    if classID == 20 and subclassID == 1 and db.housingItems then
        table.insert(exclusions, CATEGORY_NAMES.housingItems)
    end

    -- Custom category exclusions (supports both "7" and "7_8" formats)
    if IM.db.global.customCategoryExclusions then
        local classOnlyKey = tostring(classID)
        if IM.db.global.customCategoryExclusions[classOnlyKey] then
            table.insert(exclusions, "Custom: " .. classOnlyKey)
        end
        local fullKey = classID .. "_" .. (subclassID or 0)
        if IM.db.global.customCategoryExclusions[fullKey] then
            table.insert(exclusions, "Custom: " .. fullKey)
        end
    end

    return exclusions
end

-- Get all active item state protections
function TooltipInfo:GetItemStateProtections(itemID, itemLink, bagID, slotID, bindType)
    local protections = {}
    local db = IM.db.global

    -- Locked (whitelist) - always check
    if IM:IsWhitelisted(itemID) then
        table.insert(protections, "Locked (whitelist)")
    end

    -- Mail rule protection
    if IM.modules.MailHelper and IM.modules.MailHelper.ItemMatchesAnyRule then
        local matchesRule, altKey, ruleName = IM.modules.MailHelper:ItemMatchesAnyRule(itemID)
        if matchesRule then
            local altName = altKey and altKey:match("^(.+)-") or altKey or "alt"
            table.insert(protections, "Mail rule: " .. (ruleName or ("→ " .. altName)))
        end
    end

    -- Equipment Set (if enabled)
    if db.categoryExclusions.equipmentSets and IM.Filters and IM.Filters:IsInEquipmentSet(itemID) then
        table.insert(protections, "Equipment Set")
    end

    -- Binding-based protections require bag context
    if bagID and slotID then
        local isSoulbound = IM.Filters and IM.Filters.IsSoulbound and IM.Filters:IsSoulbound(bagID, slotID, itemID, bindType)

        -- Only sell soulbound items (treat non-soulbound as protected)
        if db.autoSell.onlySellSoulbound then
            if not isSoulbound then
                table.insert(protections, "Non-soulbound")
            end
        end

        -- Soulbound protection
        if db.autoSell.skipSoulbound then
            if isSoulbound then
                table.insert(protections, "Soulbound")
            end
        end

        -- Warbound/Account-bound protection
        if db.autoSell.skipWarbound then
            if IM.Filters:IsWarbound(bagID, slotID) then
                table.insert(protections, "Warbound")
            end
        end
    end

    -- Transmog protection (can check by itemID)
    if db.autoSell.skipUncollectedTransmog then
        if IM.Filters and IM.Filters:HasUncollectedTransmog(itemID) then
            table.insert(protections, "Uncollected Transmog")
        end
    end

    return protections
end

-- Get threshold protections
function TooltipInfo:GetThresholdProtections(itemQuality, itemLevel)
    local protections = {}
    local db = IM.db.global

    -- Quality threshold
    local maxQuality = db.autoSell.maxQuality
    if itemQuality and itemQuality > maxQuality then
        local maxQualityName = QUALITY_NAMES[maxQuality] or "Unknown"
        table.insert(protections, "Quality > " .. maxQualityName)
    end

    -- Item level threshold
    local maxItemLevel = db.autoSell.maxItemLevel
    if maxItemLevel > 0 and itemLevel and itemLevel > maxItemLevel then
        table.insert(protections, "iLvl > " .. maxItemLevel)
    end

    return protections
end

-- Check if tooltip info is enabled
function TooltipInfo:IsEnabled()
    return IM.db and IM.db.global and IM.db.global.ui and IM.db.global.ui.showTooltipInfo
end

-- Add info to tooltip
function TooltipInfo:AddTooltipInfo(tooltip, itemID, itemLink)
    if not itemID then return end

    -- Check if tooltip info is enabled
    if not self:IsEnabled() then return end

    -- Get item info
    local itemName, _, itemQuality, baseItemLevel, _, itemType, itemSubType,
          _, _, _, sellPrice, classID, subclassID, bindType = GetItemInfo(itemLink or itemID)

    if not itemName then return end

    -- Prefer bag/slot context captured from the tooltip APIs (most accurate).
    local bagID = tooltip and tooltip._imBagID
    local slotID = tooltip and tooltip._imSlotID

    -- Fallback: try to find item in bags (less accurate if multiple copies exist).
    if not bagID or not slotID then
        bagID, slotID = self:FindItemInBags(itemID)
    end

    -- Determine current/effective item level without relying on hovering:
    -- Use instance-based APIs when we know the item location (bag slot or equipment slot).
    local itemLevel = baseItemLevel
    if ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
        local itemLoc = nil
        if bagID and slotID then
            itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
        elseif tooltip and tooltip._imEquipSlot then
            itemLoc = ItemLocation:CreateFromEquipmentSlot(tooltip._imEquipSlot)
        end

        if itemLoc and itemLoc.IsValid and itemLoc:IsValid() then
            local ilvl = C_Item.GetCurrentItemLevel(itemLoc)
            if ilvl and ilvl > 0 then
                itemLevel = ilvl
            end
        end
    end

    -- Check for special states
    local isWhitelisted = IM:IsWhitelisted(itemID)
    local isJunk = IM:IsJunk(itemID)
    local noVendorValue = (not sellPrice or sellPrice == 0)

    -- === BUILD TOOLTIP ===

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ff00[InventoryManager]|r", 0.5, 0.5, 0.5)

    -- Category info (always show)
    local categoryName = self:GetCategoryName(classID, subclassID)
    tooltip:AddDoubleLine("Category:", categoryName, 0.7, 0.7, 0.7, 1, 1, 1)

    -- ClassID/SubclassID for custom exclusions
    tooltip:AddDoubleLine("ID:", classID .. "_" .. (subclassID or 0), 0.5, 0.5, 0.5, 0.7, 0.7, 0.7)

    -- Priority order: Whitelist > Junk List > Other Protections
    -- Whitelist ALWAYS wins (item will never sell)
    if isWhitelisted then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cff00ffffLOCKED|r - Protected from all sales", 0, 1, 1)
        -- Don't show junk status or other protections - whitelist is absolute
    elseif isJunk then
        -- Junk list overrides all other protections
        if noVendorValue then
            tooltip:AddLine("|cffff8800JUNK|r - Marked but |cff888888no vendor value|r", 1, 0.5, 0)
        else
            tooltip:AddLine("|cffff8800JUNK|r - Will auto-sell (overrides protections)", 1, 0.5, 0)
        end
        -- Don't show other protections - junk list overrides them
    else
        -- No vendor value warning (only if not junk - junk already shows this)
        if noVendorValue then
            tooltip:AddLine("|cff888888No Vendor Value|r - Cannot sell to merchants", 0.5, 0.5, 0.5)
        end

        -- === PROTECTIONS (only shown if not whitelisted and not junk) ===
        local itemStateProtections = self:GetItemStateProtections(itemID, itemLink, bagID, slotID, bindType)
        local categoryExclusions = self:GetCategoryExclusions(classID, subclassID, itemID)
        local thresholdProtections = self:GetThresholdProtections(itemQuality, itemLevel)

        local hasProtections = #itemStateProtections > 0 or #categoryExclusions > 0 or #thresholdProtections > 0

        if hasProtections then
            tooltip:AddLine(" ")
            tooltip:AddLine("|cffff6666Protected from auto-sell:|r", 1, 0.4, 0.4)

            -- Item State Protections (cyan)
            for _, protection in ipairs(itemStateProtections) do
                tooltip:AddLine("  |cff00ffff" .. protection .. "|r", 0, 1, 1)
            end

            -- Category Exclusions (yellow)
            for _, category in ipairs(categoryExclusions) do
                tooltip:AddLine("  |cffffff00" .. category .. "|r (category)", 1, 1, 0)
            end

            -- Threshold Protections (orange)
            for _, threshold in ipairs(thresholdProtections) do
                tooltip:AddLine("  |cffff9900" .. threshold .. "|r (threshold)", 1, 0.6, 0)
            end
        end
    end

    tooltip:Show()
end

-- Hook tooltips using TooltipDataProcessor (modern API)
function TooltipInfo:HookTooltips()
    if self._imContextHooksApplied then
        -- Avoid double-hooking
        return
    end

    -- Capture context so we can use ItemLocation-based APIs (no guessing, no hovering needed).
    if GameTooltip and hooksecurefunc then
        hooksecurefunc(GameTooltip, "SetBagItem", function(tooltip, bag, slot)
            tooltip._imBagID = bag
            tooltip._imSlotID = slot
            tooltip._imEquipSlot = nil
        end)

        hooksecurefunc(GameTooltip, "SetInventoryItem", function(tooltip, unit, slot)
            tooltip._imBagID = nil
            tooltip._imSlotID = nil
            tooltip._imEquipSlot = slot
        end)

        GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
            tooltip._imBagID = nil
            tooltip._imSlotID = nil
            tooltip._imEquipSlot = nil
        end)
    end

    -- Use the modern TooltipDataProcessor if available (10.0.2+)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

            local itemID = data and data.id
            if not itemID then
                -- Try to get from tooltip
                local _, link = tooltip:GetItem()
                if link then
                    itemID = GetItemInfoInstant(link)
                end
            end

            if itemID then
                self:AddTooltipInfo(tooltip, itemID, data and data.hyperlink)
            end
        end)

        IM:Debug("TooltipInfo: Hooked via TooltipDataProcessor")
    else
        -- Fallback for older clients (unlikely needed for TWW)
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            local _, itemLink = tooltip:GetItem()
            if itemLink then
                local itemID = GetItemInfoInstant(itemLink)
                if itemID then
                    self:AddTooltipInfo(tooltip, itemID, itemLink)
                end
            end
        end)

        IM:Debug("TooltipInfo: Hooked via OnTooltipSetItem")
    end

    self._imContextHooksApplied = true
end
