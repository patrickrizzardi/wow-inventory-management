--[[
    InventoryManager - Modules/MailHelper.lua
    Alt mail management - auto-fill and quick-send based on rules.

    Features:
    - Alt registry (auto-populated from character metadata)
    - Mail rules (send items matching filters to specific alts)
    - Auto-fill when mailbox opens (optional)
    - Queue management for pending items

    @module Modules.MailHelper
]]

local addonName, IM = ...

local MailHelper = {}
IM:RegisterModule("MailHelper", MailHelper)

-- Current mail queue
local _mailQueue = {}       -- { [altKey] = { items = {}, gold = 0 } }
local _atMailbox = false
local _currentRecipient = nil
local _PersistQueue
local _pendingScanAttempts = 0
local _pendingScanTimer = nil

-- Filter types supported
local FILTER_TYPES = {
    quality = {
        label = "Item Quality",
        values = {
            {value = 0, label = "Poor (Gray)"},
            {value = 1, label = "Common (White)"},
            {value = 2, label = "Uncommon (Green)"},
            {value = 3, label = "Rare (Blue)"},
            {value = 4, label = "Epic (Purple)"},
            {value = 5, label = "Legendary (Orange)"},
        },
        match = function(itemInfo, filterValue)
            local op, val = filterValue:match("([<>=]+)(%d+)")
            val = tonumber(val) or 0
            local quality = itemInfo.quality or 0
            if op == ">=" or op == "+" then return quality >= val
            elseif op == "<=" or op == "-" then return quality <= val
            elseif op == ">" then return quality > val
            elseif op == "<" then return quality < val
            else return quality == val end
        end,
    },
    classID = {
        label = "Item Class",
        values = {
            {value = 0, label = "Consumable"},
            {value = 1, label = "Container"},
            {value = 2, label = "Weapon"},
            {value = 4, label = "Armor"},
            {value = 5, label = "Reagent"},
            {value = 7, label = "Tradeskill"},
            {value = 9, label = "Recipe"},
            {value = 15, label = "Miscellaneous"},
        },
        -- Supports: "7" (class only), "7_8" (class+subclass), "7,0" (multiple), "7_8,7_5" (multiple with subclass)
        match = function(itemInfo, filterValue)
            -- Parse comma-separated entries
            for entry in filterValue:gmatch("[^,]+") do
                entry = entry:match("^%s*(.-)%s*$") -- trim whitespace
                local classID, subclassID = entry:match("^(%d+)_(%d+)$")
                if classID and subclassID then
                    -- Has subclass: e.g., "7_8"
                    classID = tonumber(classID)
                    subclassID = tonumber(subclassID)
                    if itemInfo.classID == classID and itemInfo.subclassID == subclassID then
                        return true
                    end
                else
                    -- Class only: e.g., "7"
                    classID = tonumber(entry)
                    if classID and itemInfo.classID == classID then
                        return true
                    end
                end
            end
            return false
        end,
    },
    name = {
        label = "Name Contains",
        match = function(itemInfo, filterValue)
            local name = itemInfo.name or ""
            return name:lower():find(filterValue:lower(), 1, true) ~= nil
        end,
    },
    vendorPrice = {
        label = "Vendor Price",
        match = function(itemInfo, filterValue)
            local op, val = filterValue:match("([<>=]+)(%d+)")
            val = tonumber(val) or 0
            local price = itemInfo.vendorPrice or 0
            if op == ">=" then return price >= val
            elseif op == "<=" then return price <= val
            elseif op == ">" then return price > val
            elseif op == "<" then return price < val
            else return price == val end
        end,
    },
    soulbound = {
        label = "Bind Status",
        values = {
            {value = "non-soulbound", label = "Non-Soulbound Only"},
            {value = "soulbound", label = "Soulbound Only"},
            {value = "boe", label = "Bind on Equip"},
            {value = "bop", label = "Bind on Pickup"},
        },
        match = function(itemInfo, filterValue)
            -- Check if item is bound using bag/slot info
            if not itemInfo.bagID or not itemInfo.slotID then return false end

            local itemLoc = ItemLocation:CreateFromBagAndSlot(itemInfo.bagID, itemInfo.slotID)
            if not itemLoc:IsValid() then return false end

            local isBound = C_Item.IsBound(itemLoc)

            -- Get bind type from tooltip for more specific checks
            local bindType = select(14, GetItemInfo(itemInfo.itemID)) or 0

            if filterValue == "non-soulbound" then
                return not isBound
            elseif filterValue == "soulbound" then
                return isBound
            elseif filterValue == "boe" then
                return bindType == 2 -- LE_ITEM_BIND_ON_EQUIP
            elseif filterValue == "bop" then
                return bindType == 1 -- LE_ITEM_BIND_ON_ACQUIRE
            end

            return false
        end,
    },
}

function MailHelper:OnEnable()
    local module = self  -- Capture for closures

    if not IM.db.global.mailHelper.enabled then
        IM:Debug("[MailHelper] Disabled in settings")
        return
    end

    IM:Debug("[MailHelper] Registering events")

    -- Restore persisted queue from SavedVariables
    if IM.db.global.mailHelper.pendingQueue then
        _mailQueue = IM.db.global.mailHelper.pendingQueue
        IM:Debug("[MailHelper] Restored " .. module:GetQueueSummary().totalItems .. " items from saved queue")
    end

    -- Mail context
    IM:RegisterEvent("MAIL_SHOW", function()
        module:OnMailShow()
    end)

    IM:RegisterEvent("MAIL_CLOSED", function()
        module:OnMailClosed()
    end)

    -- Hook MailFrame OnHide as backup (catches X button click)
    if MailFrame then
        MailFrame:HookScript("OnHide", function()
            module:OnMailClosed()
        end)
    end

    IM:RegisterEvent("MAIL_SEND_SUCCESS", function()
        module:OnMailSendSuccess()
    end)

    IM:RegisterEvent("MAIL_FAILED", function()
        module:OnMailFailed()
    end)

    IM:Debug("[MailHelper] Module enabled")
end

function MailHelper:OnMailShow()
    _atMailbox = true
    IM:Debug("[MailHelper] Mailbox opened")

    -- Check if mail helper is enabled
    if not IM.db.global.mailHelper.enabled then
        IM:Debug("[MailHelper] Disabled - skipping popup")
        return
    end

    -- Auto-scan and show popup if we have rules
    local rules = self:GetRules()
    if #rules > 0 then
        C_Timer.After(0.5, function()
            self:AutoFillQueue()
            if IM.UI and IM.UI.MailPopup then
                IM.UI.MailPopup:Show()
            end
        end)
    end
end

function MailHelper:OnMailClosed()
    _atMailbox = false
    _currentRecipient = nil

    -- Hide popup
    if IM.UI and IM.UI.MailPopup then
        IM.UI.MailPopup:Hide()
    end

    IM:Debug("[MailHelper] Mailbox closed")
end

function MailHelper:OnMailSendSuccess()
    -- Remove sent items from queue
    if _currentRecipient and _mailQueue[_currentRecipient] then
        -- Mark items as sent
        local queueData = _mailQueue[_currentRecipient]
        queueData.items = {}
        queueData.gold = 0
        _PersistQueue()
    end
    _currentRecipient = nil
    IM:Debug("[MailHelper] Mail sent successfully")
end

function MailHelper:OnMailFailed()
    _currentRecipient = nil
    IM:Debug("[MailHelper] Mail send failed")
end

-- Get all known alts (from character metadata + manual additions)
function MailHelper:GetAlts()
    local alts = {}
    local currentChar = IM:GetCharacterKey()

    -- Add from character metadata
    for charKey, data in pairs(IM.db.global.characters or {}) do
        if charKey ~= currentChar then
            alts[charKey] = {
                name = charKey:match("^(.+)-") or charKey,
                realm = charKey:match("-(.+)$") or "",
                faction = data.faction,
                class = data.class,
                level = data.level,
                source = "auto",
            }
        end
    end

    -- Add manual alts (override auto data)
    for charKey, data in pairs(IM.db.global.mailHelper.alts or {}) do
        if charKey ~= currentChar then
            alts[charKey] = alts[charKey] or {}
            alts[charKey].name = charKey:match("^(.+)-") or charKey
            alts[charKey].realm = charKey:match("-(.+)$") or ""
            alts[charKey].faction = data.faction or alts[charKey].faction
            alts[charKey].class = data.class or alts[charKey].class
            alts[charKey].notes = data.notes
            alts[charKey].source = "manual"
        end
    end

    return alts
end

-- Add a manual alt
function MailHelper:AddAlt(name, realm, data)
    local key = name .. "-" .. realm
    IM.db.global.mailHelper.alts[key] = data or {}
    IM:Debug("[MailHelper] Added alt: " .. key)
end

-- Remove a manual alt
function MailHelper:RemoveAlt(key)
    IM.db.global.mailHelper.alts[key] = nil
    IM:Debug("[MailHelper] Removed alt: " .. key)
end

-- Get all mail rules
function MailHelper:GetRules()
    return IM.db.global.mailHelper.rules or {}
end

-- Refresh UI panels that depend on mail rules
local function _RefreshMailUI()
    -- ALWAYS rebuild queue when rules change (so bag overlays can detect matches)
    if IM.modules.MailHelper then
        IM.modules.MailHelper:AutoFillQueue()
    end

    -- Refresh bag overlays
    IM:RefreshBagOverlays()

    -- Refresh mail helper panel if it exists
    if IM.UI and IM.UI.Panels and IM.UI.Panels.MailHelper and IM.UI.Panels.MailHelper.Refresh then
        IM.UI.Panels.MailHelper:Refresh()
    end

    -- Refresh mail popup if shown
    if IM.UI and IM.UI.MailPopup and IM.UI.MailPopup:IsShown() then
        IM.UI.MailPopup:Refresh()
    end

    -- Refresh auto-sell stats (mail rules affect sellable count)
    if IM.UI and IM.UI.Panels and IM.UI.Panels.AutoSell and IM.UI.Panels.AutoSell.UpdateStats then
        IM.UI.Panels.AutoSell.UpdateStats()
    end
end

-- Add a mail rule
function MailHelper:AddRule(rule)
    table.insert(IM.db.global.mailHelper.rules, {
        alt = rule.alt,
        filterType = rule.filterType,
        filterValue = rule.filterValue,
        name = rule.name or "Unnamed Rule",
        enabled = rule.enabled ~= false,
    })
    IM:Debug("[MailHelper] Added rule: " .. (rule.name or "Unnamed"))
    _RefreshMailUI()
end

-- Update a mail rule
function MailHelper:UpdateRule(index, rule)
    if IM.db.global.mailHelper.rules[index] then
        IM.db.global.mailHelper.rules[index] = rule
        IM:Debug("[MailHelper] Updated rule at index " .. index)
        _RefreshMailUI()
    end
end

-- Remove a mail rule
function MailHelper:RemoveRule(index)
    table.remove(IM.db.global.mailHelper.rules, index)
    IM:Debug("[MailHelper] Removed rule at index " .. index)
    _RefreshMailUI()
end

-- Get filter types for UI
function MailHelper:GetFilterTypes()
    return FILTER_TYPES
end

-- Check if an item matches a rule filter
function MailHelper:ItemMatchesFilter(itemInfo, filterType, filterValue)
    local filter = FILTER_TYPES[filterType]
    if filter and filter.match then
        return filter.match(itemInfo, filterValue)
    end
    return false
end

-- Persist the mail queue to SavedVariables
_PersistQueue = function()
    IM.db.global.mailHelper.pendingQueue = _mailQueue
end

-- Get item info for a bag slot
function MailHelper:GetItemInfo(bagID, slotID)
    local containerInfo = C_Container.GetContainerItemInfo(bagID, slotID)
    if not containerInfo then return nil end

    local itemID = containerInfo.itemID
    local itemLink = containerInfo.hyperlink
    local stackCount = containerInfo.stackCount or 1

    local name, _, quality, _, _, _, _, _, _, _, vendorPrice, classID, subclassID = GetItemInfo(itemID)
    if not name then
        if C_Item then
            if C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(itemID)
            elseif C_Item.RequestLoadItemData and itemLink then
                C_Item.RequestLoadItemData(itemLink)
            end
        end
        return nil, true
    end

    return {
        itemID = itemID,
        itemLink = itemLink,
        name = name or "Unknown",
        quality = quality or 0,
        vendorPrice = vendorPrice or 0,
        classID = classID or 0,
        subclassID = subclassID or 0,
        stackCount = stackCount,
        bagID = bagID,
        slotID = slotID,
    }
end

-- Scan bags and build queue based on rules
function MailHelper:AutoFillQueue()
    wipe(_mailQueue)

    -- Check if mail helper is enabled
    if not IM.db.global.mailHelper.enabled then
        IM:Debug("[MailHelper] Disabled - skipping queue fill")
        return
    end

    local rules = self:GetRules()
    if #rules == 0 then
        IM:Debug("[MailHelper] No rules configured")
        return
    end

    -- Get current character key to skip rules that target self
    local currentChar = IM:GetCharacterKey()

    -- Scan all bags including reagent bag
    local pendingCount = 0
    for _, bagID in ipairs(IM:GetBagIDsToScan()) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local itemInfo, pending = self:GetItemInfo(bagID, slotID)
            if pending then
                pendingCount = pendingCount + 1
            end
            if itemInfo then
                -- Check against each rule
                for _, rule in ipairs(rules) do
                    -- Skip rules that target the current character (can't mail to self)
                    if rule.enabled and rule.alt and rule.alt ~= currentChar then
                        if self:ItemMatchesFilter(itemInfo, rule.filterType, rule.filterValue) then
                            -- Add to queue for this alt
                            _mailQueue[rule.alt] = _mailQueue[rule.alt] or { items = {}, gold = 0 }
                            table.insert(_mailQueue[rule.alt].items, {
                                bagID = bagID,
                                slotID = slotID,
                                itemInfo = itemInfo,
                                ruleName = rule.name,
                            })
                            break -- Only match first rule
                        end
                    end
                end
            end
        end
    end

    local totalItems = 0
    for altKey, data in pairs(_mailQueue) do
        totalItems = totalItems + #data.items
    end

    -- Persist queue to SavedVariables
    _PersistQueue()

    IM:Debug("[MailHelper] Auto-fill found " .. totalItems .. " items to queue")
    if pendingCount > 0 then
        _pendingScanAttempts = _pendingScanAttempts + 1
        if _pendingScanTimer then
            _pendingScanTimer:Cancel()
            _pendingScanTimer = nil
        end
        if _pendingScanAttempts <= 10 then
            _pendingScanTimer = C_Timer.NewTimer(0.2, function()
                if _atMailbox then
                    self:AutoFillQueue()
                end
            end)
        else
            _pendingScanAttempts = 0
        end
    else
        _pendingScanAttempts = 0
    end
end

-- Get current mail queue
function MailHelper:GetQueue()
    return _mailQueue
end

-- Get queue summary
function MailHelper:GetQueueSummary()
    local summary = {
        totalItems = 0,
        totalAlts = 0,
        alts = {},
    }

    for altKey, data in pairs(_mailQueue) do
        if #data.items > 0 then
            summary.totalAlts = summary.totalAlts + 1
            summary.totalItems = summary.totalItems + #data.items
            table.insert(summary.alts, {
                key = altKey,
                name = altKey:match("^(.+)-") or altKey,
                itemCount = #data.items,
            })
        end
    end

    return summary
end

-- Add item to queue for specific alt
function MailHelper:AddToQueue(altKey, bagID, slotID)
    local itemInfo = self:GetItemInfo(bagID, slotID)
    if not itemInfo then return false end

    _mailQueue[altKey] = _mailQueue[altKey] or { items = {}, gold = 0 }
    table.insert(_mailQueue[altKey].items, {
        bagID = bagID,
        slotID = slotID,
        itemInfo = itemInfo,
        ruleName = "Manual",
    })

    _PersistQueue()
    return true
end

-- Remove item from queue
function MailHelper:RemoveFromQueue(altKey, index)
    if _mailQueue[altKey] and _mailQueue[altKey].items[index] then
        table.remove(_mailQueue[altKey].items, index)
        _PersistQueue()
        return true
    end
    return false
end

-- Clear queue for alt
function MailHelper:ClearAltQueue(altKey)
    if _mailQueue[altKey] then
        _mailQueue[altKey] = { items = {}, gold = 0 }
        _PersistQueue()
    end
end

-- Clear entire queue
function MailHelper:ClearQueue()
    wipe(_mailQueue)
    _PersistQueue()
end

-- Send queued items to an alt (up to 12 items per mail)
function MailHelper:SendToAlt(altKey)
    if not _atMailbox then
        IM:Print("Must be at a mailbox to send mail")
        return false
    end

    local queueData = _mailQueue[altKey]
    if not queueData or #queueData.items == 0 then
        IM:Debug("[MailHelper] No items in queue for " .. altKey)
        return false
    end

    -- Get recipient name (just the character name, no realm if same realm)
    local altName = altKey:match("^(.+)-") or altKey
    local altRealm = altKey:match("-(.+)$") or ""
    local currentRealm = GetRealmName()

    local recipient = altName
    if altRealm ~= "" and altRealm ~= currentRealm then
        recipient = altName .. "-" .. altRealm
    end

    -- Attach up to 12 items
    local attached = 0
    local maxAttachments = ATTACHMENTS_MAX_SEND or 12

    -- Clear existing attachments and fields before queueing new ones
    ClearSendMail()

    for i, queueItem in ipairs(queueData.items) do
        if attached >= maxAttachments then break end

        -- Pick up and attach item
        C_Container.PickupContainerItem(queueItem.bagID, queueItem.slotID)
        if CursorHasItem() then
            ClickSendMailItemButton(attached + 1)
            attached = attached + 1
        end
    end

    if attached > 0 then
        _currentRecipient = altKey

        -- Set recipient and send
        local subject = "InventoryManager: " .. attached .. " items"
        SendMail(recipient, subject, "")

        IM:Debug("[MailHelper] Sending " .. attached .. " items to " .. recipient)
        return true
    end

    return false
end

-- Check if at mailbox
function MailHelper:IsAtMailbox()
    return _atMailbox
end

-- Get count of items queued for an alt
function MailHelper:GetAltQueueCount(altKey)
    if _mailQueue[altKey] then
        return #_mailQueue[altKey].items
    end
    return 0
end

-- Check if a specific bag slot is queued for mail
-- Returns: isQueued, altKey (the alt it's queued for)
function MailHelper:IsItemQueuedForMail(bagID, slotID)
    for altKey, queueData in pairs(_mailQueue) do
        for _, queueItem in ipairs(queueData.items) do
            if queueItem.bagID == bagID and queueItem.slotID == slotID then
                return true, altKey
            end
        end
    end
    return false, nil
end

-- Check if an item ID matches any mail rule (for protection logic)
-- This checks the rules, not the queue - useful for preventing auto-sell
function MailHelper:ItemMatchesAnyRule(itemID)
    if not itemID then return false end

    -- If mail helper is disabled, items don't match any rules
    if not IM.db.global.mailHelper.enabled then return false end

    local rules = self:GetRules()
    if #rules == 0 then return false end

    -- We need item info to check against rules
    local name, _, quality, _, _, _, _, _, _, _, vendorPrice, classID, subclassID = GetItemInfo(itemID)
    if not name then return false end  -- Item not cached yet

    local itemInfo = {
        itemID = itemID,
        name = name,
        quality = quality or 0,
        vendorPrice = vendorPrice or 0,
        classID = classID or 0,
        subclassID = subclassID or 0,
    }

    for _, rule in ipairs(rules) do
        if rule.enabled and rule.alt then
            if self:ItemMatchesFilter(itemInfo, rule.filterType, rule.filterValue) then
                return true, rule.alt, rule.name
            end
        end
    end

    return false
end
