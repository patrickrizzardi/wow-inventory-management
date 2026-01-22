--[[
    InventoryManager - Modules/SellHistory.lua
    Transaction logging and history display
]]

local addonName, IM = ...

local SellHistory = {}
IM:RegisterModule("SellHistory", SellHistory)

-- Time constants
local SECONDS_PER_DAY = 86400

function SellHistory:OnEnable()
    IM:Debug("[SellHistory] OnEnable called - registering tracking events")
    -- Track loot events
    self:RegisterLootTracking()
    -- Track vendor purchases
    self:RegisterPurchaseTracking()
    -- Track auction house events
    self:RegisterAuctionTracking()
    IM:Debug("[SellHistory] All tracking events registered")
end

-- Register for loot events
function SellHistory:RegisterLootTracking()
    IM:Debug("[SellHistory] Registering loot tracking events")

    -- CHAT_MSG_LOOT fires when player loots items from corpses/chests
    IM:RegisterEvent("CHAT_MSG_LOOT", function(event, message, ...)
        self:OnLootMessage(message)
    end)

    -- Track quest reward items
    IM:RegisterEvent("QUEST_TURNED_IN", function(event, questID, xpReward, moneyReward)
        self:OnQuestTurnedIn(questID)
    end)

    IM:Debug("[SellHistory] Loot tracking events registered")
end

-- Handle quest turn-in (track quest rewards)
function SellHistory:OnQuestTurnedIn(questID)
    -- Get quest rewards - this requires checking what rewards were selected
    -- For now we log the quest completion; full reward tracking needs QUEST_LOG_UPDATE
    IM:Debug("[SellHistory] Quest turned in: " .. tostring(questID))

    -- Quest rewards are complex - the chosen reward is determined by the player
    -- We can only track this reliably via CHAT_MSG_LOOT which fires for quest rewards too
end

-- Parse loot message and log it
function SellHistory:OnLootMessage(message)
    -- Debug: log all loot messages received
    IM:Debug("[SellHistory] CHAT_MSG_LOOT received: " .. tostring(message))

    -- Extract item link from message - try multiple patterns for different WoW versions
    -- Pattern 1: Standard colored item link
    local itemLink = message:match("|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r")
    -- Pattern 2: Simpler match for edge cases
    if not itemLink then
        itemLink = message:match("|Hitem:[^|]+|h%[[^%]]+%]|h")
    end

    if not itemLink then
        IM:Debug("[SellHistory] No item link found in message")
        return
    end

    -- Get item ID from link
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then
        -- Try extracting itemID directly from the link string
        local idFromLink = itemLink:match("|Hitem:(%d+)")
        if idFromLink then
            itemID = tonumber(idFromLink)
        end
    end

    if not itemID then
        IM:Debug("[SellHistory] Could not get itemID from link: " .. itemLink)
        return
    end

    -- Extract quantity (defaults to 1)
    local quantity = 1
    -- Try multiple quantity patterns used by WoW
    -- Patterns: "x2", "|rx2", " x2", or nothing (single item)
    local quantityMatch = message:match("x(%d+)%.?$") or message:match("|rx(%d+)") or message:match(" x(%d+)")
    if quantityMatch then
        quantity = tonumber(quantityMatch) or 1
    end

    -- Log the loot
    IM:Debug("[SellHistory] Logging loot: " .. itemLink .. " x" .. quantity .. " (itemID=" .. itemID .. ")")
    IM:AddLootHistoryEntry(itemID, itemLink, quantity, nil)
end

-- Register for vendor purchase events
function SellHistory:RegisterPurchaseTracking()
    -- Track when buying from merchants via MERCHANT_UPDATE and comparing bag contents
    -- This is tricky because there's no direct "item purchased" event
    -- We'll hook into BuyMerchantItem instead

    -- Store original function
    local originalBuyMerchantItem = BuyMerchantItem

    -- Replace with our wrapper
    BuyMerchantItem = function(index, quantity)
        -- Get item info before buying (use modern API with fallback)
        local itemLink = C_MerchantFrame and C_MerchantFrame.GetItemLink and C_MerchantFrame.GetItemLink(index) or (GetMerchantItemLink and GetMerchantItemLink(index))
        local price, stackCount
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(index)
            if info then
                price = info.price
                stackCount = info.stackCount
            end
        elseif GetMerchantItemInfo then
            _, _, price, stackCount = GetMerchantItemInfo(index)
        end
        local buyQuantity = quantity or stackCount or 1

        -- Call original
        originalBuyMerchantItem(index, quantity)

        -- Log the purchase
        if itemLink and price then
            local itemID = GetItemInfoInstant(itemLink)
            if itemID then
                local totalCost = price * math.ceil(buyQuantity / (stackCount or 1))
                IM:AddPurchaseHistoryEntry(itemID, itemLink, buyQuantity, totalCost)
                IM:Debug("Logged vendor purchase: " .. itemLink .. " x" .. buyQuantity)
            end
        end
    end
end

-- Register for auction house events
function SellHistory:RegisterAuctionTracking()
    -- AUCTION_HOUSE_AUCTION_CREATED - when you post an auction (not sold yet)
    -- AUCTION_HOUSE_SHOW_NOTIFICATION - auction sold notifications

    -- Track auction sales via chat messages (most reliable method)
    IM:RegisterEvent("CHAT_MSG_SYSTEM", function(event, message)
        self:OnAuctionSystemMessage(message)
    end)

    -- Track auction sales via chat messages (most reliable method)
    IM:RegisterEvent("CHAT_MSG_MONEY", function(event, message)
        -- "A]uction of [Item] sold." messages
        self:OnAuctionMoneyMessage(message)
    end)
end

-- Handle auction system messages
function SellHistory:OnAuctionSystemMessage(message)
    -- Wrap in pcall to guard against secret/protected values
    local ok = pcall(function()
        if type(message) ~= "string" then return end

        -- "Your auction of [Item] sold." - Locale dependent
        -- Try to extract auction sold info
        local itemLink = message:match("|c%x+|Hitem:.-|h%[.-%]|h|r")
        if itemLink and (message:find("auction") or message:find("Auction")) then
            -- This is likely an auction notification
            -- The exact gold amount is in a separate CHAT_MSG_MONEY event
            local itemID = GetItemInfoInstant(itemLink)
            if itemID then
                -- Store pending auction sale to match with money message
                self.pendingAuctionSale = {
                    itemID = itemID,
                    itemLink = itemLink,
                    timestamp = time()
                }
            end
        end
    end)
    -- Silently ignore errors from protected messages
end


-- Handle auction money messages
function SellHistory:OnAuctionMoneyMessage(message)
    -- Wrap in pcall to guard against secret/protected values
    local ok = pcall(function()
        if type(message) ~= "string" then return end

        -- "You receive X gold from auction." messages
        -- Extract gold amount
        local gold = message:match("(%d+) gold") or 0
        local silver = message:match("(%d+) silver") or 0
        local copper = message:match("(%d+) copper") or 0

        local totalCopper = (tonumber(gold) or 0) * 10000 + (tonumber(silver) or 0) * 100 + (tonumber(copper) or 0)

        if totalCopper > 0 and self.pendingAuctionSale and (time() - self.pendingAuctionSale.timestamp) < 5 then
            -- Match this money with the pending auction sale
            IM:AddAuctionSoldHistoryEntry(
                self.pendingAuctionSale.itemID,
                self.pendingAuctionSale.itemLink,
                1, -- Quantity unknown from messages
                totalCopper
            )
            IM:Debug("Logged auction sale: " .. self.pendingAuctionSale.itemLink .. " for " .. IM:FormatMoney(totalCopper))
            self.pendingAuctionSale = nil
        end
    end)
    -- Silently ignore errors from protected messages
end

-- Get formatted history entries for display
function SellHistory:GetFormattedHistory()
    local history = IM:GetSellHistory()
    local formatted = {}

    for i, entry in ipairs(history) do
        local itemName = GetItemInfo(entry.itemID) or "Unknown Item"
        local timestamp = date("%m/%d %H:%M", entry.timestamp)
        local entryType = entry.type or "sell" -- Default old entries to sell
        local value = entry.value or entry.sellPrice or 0

        -- Type-specific formatting
        local typeLabel, typeColor
        if entryType == "sell" then
            typeLabel = "SOLD"
            typeColor = "|cff00ff00" -- Green
        elseif entryType == "buyback" then
            typeLabel = "BUYBACK"
            typeColor = "|cffff8800" -- Orange
            value = math.abs(value)
        elseif entryType == "loot" then
            typeLabel = "LOOT"
            typeColor = "|cff00ccff" -- Light blue
        elseif entryType == "quest" then
            typeLabel = "QUEST"
            typeColor = "|cffffff00" -- Yellow
        elseif entryType == "mail" then
            typeLabel = "MAIL"
            typeColor = "|cffcc99ff" -- Light purple
        elseif entryType == "purchase" then
            typeLabel = "BOUGHT"
            typeColor = "|cffff6666" -- Light red (spent gold)
            value = math.abs(value)
        elseif entryType == "auction_sold" then
            typeLabel = "AH SOLD"
            typeColor = "|cff00ff88" -- Bright green (earned gold)
        elseif entryType == "auction_bought" then
            typeLabel = "AH BOUGHT"
            typeColor = "|cffff4444" -- Red (spent gold)
            value = math.abs(value)
        else
            typeLabel = "OTHER"
            typeColor = "|cff888888"
        end

        table.insert(formatted, {
            index = i,
            timestamp = timestamp,
            type = entryType,
            typeLabel = typeLabel,
            typeColor = typeColor,
            itemID = entry.itemID,
            itemLink = entry.itemLink or itemName,
            itemName = itemName,
            quantity = entry.quantity or 1,
            value = value,
            valueFormatted = value > 0 and IM:FormatMoney(value) or "",
            source = entry.source,
            character = entry.character or "Unknown",
            realm = entry.realm or "",
        })
    end

    return formatted
end

-- Get history statistics
function SellHistory:GetStatistics()
    local history = IM:GetSellHistory()

    local stats = {
        totalEntries = #history,
        totalItems = 0,
        totalGold = 0,
        uniqueItems = {},
        mostSoldItem = nil,
        mostSoldCount = 0,
    }

    local itemCounts = {}

    for _, entry in ipairs(history) do
        -- Validate entry has required fields (guards against corrupted data)
        if entry and entry.quantity and entry.sellPrice and entry.itemID then
            stats.totalItems = stats.totalItems + entry.quantity
            stats.totalGold = stats.totalGold + entry.sellPrice

            -- Track unique items and most sold
            stats.uniqueItems[entry.itemID] = true
            itemCounts[entry.itemID] = (itemCounts[entry.itemID] or 0) + entry.quantity

            if itemCounts[entry.itemID] > stats.mostSoldCount then
                stats.mostSoldCount = itemCounts[entry.itemID]
                stats.mostSoldItem = entry.itemID
            end
        end
    end

    stats.uniqueItemCount = 0
    for _ in pairs(stats.uniqueItems) do
        stats.uniqueItemCount = stats.uniqueItemCount + 1
    end

    return stats
end

-- Export history to string (for clipboard)
function SellHistory:ExportToString()
    local history = IM:GetSellHistory()
    local lines = {"InventoryManager Sell History", "Exported: " .. date("%Y-%m-%d %H:%M:%S"), ""}

    for _, entry in ipairs(history) do
        local itemName = GetItemInfo(entry.itemID) or "Unknown"
        local timestamp = date("%Y-%m-%d %H:%M", entry.timestamp)
        local line = string.format("%s - %s x%d - %s",
            timestamp,
            itemName,
            entry.quantity,
            IM:FormatMoney(entry.sellPrice):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        )
        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

-- Get entries from a specific time range
function SellHistory:GetEntriesSince(timestamp)
    local history = IM:GetSellHistory()
    local filtered = {}

    for _, entry in ipairs(history) do
        if entry.timestamp >= timestamp then
            table.insert(filtered, entry)
        end
    end

    return filtered
end

-- Get today's sales
function SellHistory:GetTodaysSales()
    local today = time() - (time() % SECONDS_PER_DAY) -- Start of today (midnight UTC)
    return self:GetEntriesSince(today)
end

-- Get this session's total (since last login)
function SellHistory:GetSessionTotal()
    local sessionStart = IM.sessionStartTime or time()
    local entries = self:GetEntriesSince(sessionStart)

    local total = 0
    for _, entry in ipairs(entries) do
        total = total + entry.sellPrice
    end

    return total
end
