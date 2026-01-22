--[[
    InventoryManager - Database.lua
    SavedVariables management, defaults, and migrations
]]

local addonName, IM = ...

-- Database version for migrations
local DB_VERSION = 2

-- Default database structure
local defaults = {
    global = {
        -- Database version for migrations
        dbVersion = DB_VERSION,

        -- Debug mode
        debug = false,

        -- Feature toggles
        autoSellEnabled = true,
        autoRepairEnabled = true,
        useIMBags = true,                      -- Use InventoryManager bag UI (false = Blizzard bags)
        bagUI = {
            includeReagentBag = true,
            collapsedCategories = {},
            collapsedGroups = {},
            scale = 1,
            maxColumns = 10,
            maxRows = 12,
            itemColumns = 10,
            categoryColumns = 2,
            categoryRows = 14,
            groupingMode = "category",
            showGearSets = true,
            showItemLevel = false,
            windowPosition = nil,
            windowMode = "fixed",
            windowRows = 12,
        },

        -- Auto-sell filters
        autoSell = {
            maxQuality = 2,                    -- Sell Uncommon and below by default
            maxItemLevel = 0,                  -- 0 = disabled
            minSellPrice = 0,                  -- 0 = disabled (minimum copper value to sell)
            skipSoulbound = true,              -- Don't sell soulbound items (protect soulbound)
            skipWarbound = true,               -- Don't sell warbound/account-bound items
            onlySellSoulbound = false,         -- Only sell soulbound items (protect non-soulbound) - mutually exclusive with skipSoulbound
            skipUncollectedTransmog = true,    -- Don't sell items with uncollected appearances
        },


        -- Repair settings
        repair = {
            useGuildFunds = true,              -- Try guild funds first
            fallbackToPersonal = true,         -- Fall back to personal gold if guild fails
        },

        -- Whitelist (locked items - never sell/destroy)
        -- Format: [itemID] = true
        whitelist = {},

        -- Junk list (always sell/destroy regardless of filters)
        -- Format: [itemID] = true
        junkList = {},

        -- Category exclusions
        -- Items in these categories are never auto-sold/destroyed
        categoryExclusions = {
            consumables = true,        -- Food, potions, flasks
            questItems = true,         -- Quest-bound items
            craftingReagents = false,  -- Crafting materials
            tradeGoods = false,        -- Trade skill items
            recipes = true,            -- Recipes, patterns, schematics
            toys = true,               -- Toys
            pets = true,               -- Battle pets
            mounts = true,             -- Mount items
            currencyTokens = true,     -- Currency tokens in bags (Miscellaneous class)
            equipmentSets = true,      -- Items in any equipment set
            housingItems = true,       -- Player housing items (Plunderstorm, etc.)
        },

        -- Custom category exclusions (by classID.subclassID)
        -- Format: ["classID_subclassID"] = true
        customCategoryExclusions = {},

        -- Sell history (LEGACY - kept for migration, use transactions instead)
        sellHistory = {
            maxEntries = 100,          -- Maximum history entries to keep
            entries = {},              -- { timestamp, itemID, itemLink, quantity, sellPrice }
        },

        -- Ledger configuration (NEW in v2)
        ledger = {
            maxAgeDays = 30,           -- Purge entries older than this (0 = never purge)
            trackLoot = true,          -- Track item looting
            trackMail = true,          -- Track mail gold/items
            trackTrade = true,         -- Track trade gold
            trackQuests = true,        -- Track quest gold rewards
            trackRepairs = true,       -- Track repair costs
            trackAH = true,            -- Track auction house transactions
            trackWarbank = true,       -- Track warband bank deposits/withdrawals
            trackFlights = true,       -- Track flight path costs
            trackTransmog = true,      -- Track transmog costs
            trackBarber = true,        -- Track barbershop costs
            trackBMAH = true,          -- Track Black Market AH bids
            trackUnclaimed = true,     -- Track unclaimed/unknown gold changes
        },

        -- Unified transaction ledger (NEW in v2)
        -- Replaces sellHistory with optimized schema
        transactions = {
            entries = {},              -- See AddTransaction for entry schema
        },

        -- Character metadata for net worth tracking (NEW in v2)
        -- Format: ["CharName-RealmName"] = { gold, lastSeen, faction, class, level, inventoryValue, lastInventoryUpdate }
        characters = {},

        -- Warband Bank gold (manual entry - no API available)
        warbandBankGold = 0,              -- Gold in copper
        warbandBankGoldUpdated = 0,       -- Timestamp of last update

        -- Mail Helper configuration (NEW in v2)
        mailHelper = {
            enabled = true,            -- Enable mail helper features
            autoFillOnOpen = false,    -- Auto-fill mail when mailbox opens
            alts = {},                 -- ["CharName-RealmName"] = { faction, class, notes }
            rules = {},                -- Mail rules: { alt, filterType, filterValue, name, enabled }
        },

        -- Auction House protection
        auctionHouse = {
            blockLockedPost = false,   -- Show red warning border on locked items at AH
        },

        -- UI settings
        minimapButtonAngle = 220,          -- Minimap button position (degrees)
        ui = {
            showMinimapButton = true,      -- Show minimap button
            autoOpenOnMerchant = false,    -- Auto-open panel when merchant opens
            panelScale = 1.0,              -- UI scale
            showTooltipInfo = true,        -- Show category/status info in item tooltips
            -- Bag overlay toggles
            showLockOverlay = true,        -- Show lock icon on locked items
            showSellOverlay = true,        -- Show coin icon on sellable items
            showMailOverlay = true,        -- Show mail border on mail helper items
            showUnsellableIndicator = true, -- Show gray border + icon on items with no vendor value
        },

        -- Dashboard filter persistence
        dashboard = {
            ledgerTypeFilter = 1,          -- Index into type presets (1 = All Types)
            ledgerDateFilter = 5,          -- Index into date presets (5 = All Time)
            ledgerCharFilter = 1,          -- Index into character list (1 = All Characters)
            ledgerSearch = "",             -- Search text
        },

        -- Currency favorites (for quick access in Currency panel)
        -- Format: [currencyID] = true
        currencyFavorites = {},

        -- Cross-character inventory snapshots (for inventory search)
        -- ["CharName-RealmName"] = {
        --     timestamp = number,
        --     bags = { {itemID, link, quantity, bagID, slotID}, ... },
        --     bank = { ... },  -- Only populated when bank was open
        --     reagentBank = { ... },
        -- }
        inventorySnapshots = {},

        -- Warband bank inventory (shared across all characters)
        warbandBankInventory = {
            timestamp = 0,
            items = {},  -- { {itemID, link, quantity, tab, slotID}, ... }
        },
    },

    char = {
        -- Per-character overrides (future feature)
        -- These would override global settings if set
    },
}

-- Deep copy a table (private helper)
local function _deepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = _deepCopy(v)
    end
    return copy
end

-- Merge defaults into existing table (preserves existing values)
local function _mergeDefaults(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            _mergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = _deepCopy(v)
        end
    end
end

-- Run database migrations (private helper)
local function _runMigrations(db)
    local currentVersion = db.global.dbVersion or 0

    -- Migration from version 0 to 1 (initial structure)
    if currentVersion < 1 then
        -- This is the initial version, no migration needed
        db.global.dbVersion = 1
        currentVersion = 1
    end

    -- Migration from version 1 to 2 (ledger system)
    if currentVersion < 2 then
        -- Migrate sellHistory.entries to transactions.entries
        if db.global.sellHistory and db.global.sellHistory.entries then
            db.global.transactions = db.global.transactions or { entries = {} }

            for _, oldEntry in ipairs(db.global.sellHistory.entries) do
                -- Convert old format to new optimized format
                local newEntry = {
                    ts = oldEntry.timestamp,
                    t = oldEntry.type or "sell",
                    char = (oldEntry.character or "Unknown") .. "-" .. (oldEntry.realm or "Unknown"),
                }

                -- Item transactions have item data
                if oldEntry.itemID then
                    newEntry.item = oldEntry.itemID
                    newEntry.link = oldEntry.itemLink
                    newEntry.qty = oldEntry.quantity or 1
                end

                -- Value (handle old sellPrice field)
                newEntry.val = oldEntry.value or oldEntry.sellPrice or 0

                -- Source if present
                if oldEntry.source then
                    newEntry.src = oldEntry.source
                end

                table.insert(db.global.transactions.entries, newEntry)
            end

            IM:Debug("Migrated " .. #db.global.sellHistory.entries .. " entries to new transaction format")
        end

        -- Initialize new tables if not present
        db.global.ledger = db.global.ledger or _deepCopy(defaults.global.ledger)
        db.global.characters = db.global.characters or {}
        db.global.mailHelper = db.global.mailHelper or _deepCopy(defaults.global.mailHelper)

        db.global.dbVersion = 2
        IM:Debug("Database migrated to version 2")
    end
end

-- Initialize the database
function IM:InitializeDatabase()
    -- Create SavedVariables if they don't exist
    if not InventoryManagerDB then
        InventoryManagerDB = _deepCopy(defaults)
        self:Debug("Created new database with defaults")
    else
        -- Merge in any missing defaults (for addon updates)
        _mergeDefaults(InventoryManagerDB, defaults)
        self:Debug("Merged defaults into existing database")
    end

    -- Run migrations
    _runMigrations(InventoryManagerDB)

    -- Store reference for easy access
    self.db = InventoryManagerDB

    -- Fire callback for modules that need to know database is ready
    if self.OnDatabaseReady then
        self:OnDatabaseReady()
    end
end

-- Reset database to defaults (called by user action)
function IM:ResetDatabase()
    InventoryManagerDB = _deepCopy(defaults)
    self.db = InventoryManagerDB
    self:Print("Database reset to defaults")
end

-- Reset a specific section to defaults
function IM:ResetSection(section)
    if defaults.global[section] then
        self.db.global[section] = _deepCopy(defaults.global[section])
        self:Print("Reset " .. section .. " to defaults")
    else
        self:PrintError("Unknown section: " .. section)
    end
end

-- Callback system for database changes
local _whitelistCallbacks = {}
local _junkListCallbacks = {}

-- Register callbacks for whitelist changes
function IM:RegisterWhitelistCallback(callback)
    table.insert(_whitelistCallbacks, callback)
end

-- Register callbacks for junk list changes
function IM:RegisterJunkListCallback(callback)
    table.insert(_junkListCallbacks, callback)
end

-- Fire whitelist change callbacks
local function _FireWhitelistCallbacks(itemID, added)
    for _, callback in ipairs(_whitelistCallbacks) do
        callback(itemID, added)
    end
end

-- Fire junk list change callbacks
local function _FireJunkListCallbacks(itemID, added)
    for _, callback in ipairs(_junkListCallbacks) do
        callback(itemID, added)
    end
end

-- Whitelist management
function IM:IsWhitelisted(itemID)
    return self.db.global.whitelist[itemID] == true
end

function IM:AddToWhitelist(itemID)
    self.db.global.whitelist[itemID] = true
    self:Debug("Added item " .. itemID .. " to whitelist")
    _FireWhitelistCallbacks(itemID, true)
end

function IM:RemoveFromWhitelist(itemID)
    self.db.global.whitelist[itemID] = nil
    self:Debug("Removed item " .. itemID .. " from whitelist")
    _FireWhitelistCallbacks(itemID, false)
end

function IM:ToggleWhitelist(itemID)
    if self:IsWhitelisted(itemID) then
        self:RemoveFromWhitelist(itemID)
        return false
    else
        self:AddToWhitelist(itemID)
        return true
    end
end

-- Junk list management
function IM:IsJunk(itemID)
    return self.db.global.junkList[itemID] == true
end

function IM:AddToJunkList(itemID)
    -- Remove from whitelist if present (can't be both)
    if self:IsWhitelisted(itemID) then
        self:RemoveFromWhitelist(itemID)
    end
    self.db.global.junkList[itemID] = true
    self:Debug("Added item " .. itemID .. " to junk list")
    _FireJunkListCallbacks(itemID, true)
end

function IM:RemoveFromJunkList(itemID)
    self.db.global.junkList[itemID] = nil
    self:Debug("Removed item " .. itemID .. " from junk list")
    _FireJunkListCallbacks(itemID, false)
end

function IM:ToggleJunkList(itemID)
    if self:IsJunk(itemID) then
        self:RemoveFromJunkList(itemID)
        return false
    else
        self:AddToJunkList(itemID)
        return true
    end
end

-- Transaction history management
-- Types: "sell", "buyback", "loot", "quest", "mail"

function IM:AddHistoryEntry(entryType, itemID, itemLink, quantity, value, source)
    local playerName = UnitName("player")
    local realmName = GetRealmName()

    local entry = {
        timestamp = time(),
        type = entryType,       -- "sell", "buyback", "loot", "quest", "mail"
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity,
        value = value or 0,     -- Gold value (positive for income, negative for expense)
        source = source,        -- Optional: mob name, quest name, etc.
        character = playerName, -- Character name who performed action
        realm = realmName,      -- Realm name
    }

    table.insert(self.db.global.sellHistory.entries, 1, entry)

    -- Trim to max entries
    local max = self.db.global.sellHistory.maxEntries
    while #self.db.global.sellHistory.entries > max do
        table.remove(self.db.global.sellHistory.entries)
    end
end

-- Convenience wrapper for sell entries (backwards compatible)
function IM:AddSellHistoryEntry(itemID, itemLink, quantity, sellPrice)
    self:AddHistoryEntry("sell", itemID, itemLink, quantity, sellPrice)
end

-- Add buyback entry
function IM:AddBuybackHistoryEntry(itemID, itemLink, quantity, cost)
    self:AddHistoryEntry("buyback", itemID, itemLink, quantity, -cost) -- Negative because we spent gold
end

-- Add loot entry
function IM:AddLootHistoryEntry(itemID, itemLink, quantity, source)
    self:AddHistoryEntry("loot", itemID, itemLink, quantity, 0, source)
end

-- Add vendor purchase entry
function IM:AddPurchaseHistoryEntry(itemID, itemLink, quantity, cost)
    self:AddHistoryEntry("purchase", itemID, itemLink, quantity, -cost, "vendor") -- Negative = spent gold
end

-- Add auction sold entry (you sold something and got gold)
function IM:AddAuctionSoldHistoryEntry(itemID, itemLink, quantity, goldReceived)
    self:AddHistoryEntry("auction_sold", itemID, itemLink, quantity, goldReceived, "auction")
end

-- Add auction bought entry (you bought something and spent gold)
function IM:AddAuctionBoughtHistoryEntry(itemID, itemLink, quantity, cost)
    self:AddHistoryEntry("auction_bought", itemID, itemLink, quantity, -cost, "auction") -- Negative = spent gold
end

function IM:GetSellHistory()
    return self.db.global.sellHistory.entries
end

function IM:ClearSellHistory()
    self.db.global.sellHistory.entries = {}
    self:Print("Transaction history cleared")
end

-- Get total gold earned from sells
function IM:GetTotalGoldEarned()
    local total = 0
    for _, entry in ipairs(self.db.global.sellHistory.entries) do
        if entry.type == "sell" or (not entry.type and entry.sellPrice) then
            -- Support old format (sellPrice) and new format (value)
            total = total + (entry.value or entry.sellPrice or 0)
        end
    end
    return total
end

-- Currency favorites management
function IM:IsCurrencyFavorite(currencyID)
    return self.db.global.currencyFavorites[currencyID] == true
end

function IM:AddCurrencyFavorite(currencyID)
    self.db.global.currencyFavorites[currencyID] = true
    self:Debug("Added currency " .. currencyID .. " to favorites")
end

function IM:RemoveCurrencyFavorite(currencyID)
    self.db.global.currencyFavorites[currencyID] = nil
    self:Debug("Removed currency " .. currencyID .. " from favorites")
end

function IM:ToggleCurrencyFavorite(currencyID)
    local result
    if self:IsCurrencyFavorite(currencyID) then
        self:RemoveCurrencyFavorite(currencyID)
        result = false
    else
        self:AddCurrencyFavorite(currencyID)
        result = true
    end
    -- Invalidate currency cache when favorites change
    if self.InvalidateCurrencyCache then
        self.InvalidateCurrencyCache()
    end
    return result
end

-- Get transaction stats by type
function IM:GetTransactionStats()
    local stats = {
        sells = { count = 0, value = 0 },
        buybacks = { count = 0, value = 0 },
        loots = { count = 0 },
        purchases = { count = 0, value = 0 },
        auctionSold = { count = 0, value = 0 },
        auctionBought = { count = 0, value = 0 },
    }

    for _, entry in ipairs(self.db.global.sellHistory.entries) do
        local entryType = entry.type or "sell" -- Default old entries to sell
        if entryType == "sell" then
            stats.sells.count = stats.sells.count + (entry.quantity or 1)
            stats.sells.value = stats.sells.value + (entry.value or entry.sellPrice or 0)
        elseif entryType == "buyback" then
            stats.buybacks.count = stats.buybacks.count + (entry.quantity or 1)
            stats.buybacks.value = stats.buybacks.value + math.abs(entry.value or 0)
        elseif entryType == "loot" then
            stats.loots.count = stats.loots.count + (entry.quantity or 1)
        elseif entryType == "purchase" then
            stats.purchases.count = stats.purchases.count + (entry.quantity or 1)
            stats.purchases.value = stats.purchases.value + math.abs(entry.value or 0)
        elseif entryType == "auction_sold" then
            stats.auctionSold.count = stats.auctionSold.count + (entry.quantity or 1)
            stats.auctionSold.value = stats.auctionSold.value + (entry.value or 0)
        elseif entryType == "auction_bought" then
            stats.auctionBought.count = stats.auctionBought.count + (entry.quantity or 1)
            stats.auctionBought.value = stats.auctionBought.value + math.abs(entry.value or 0)
        end
    end

    return stats
end

--------------------------------------------------------------------------------
-- NEW LEDGER SYSTEM (v2)
-- Unified transaction tracking with optimized schema
--------------------------------------------------------------------------------

--[[
    CHARACTER KEY FORMAT: "CharName-RealmName"

    Used as unique identifier for per-character data:
    - characters[charKey] = { gold, lastSeen, faction, class, level, inventoryValue }
    - inventorySnapshots[charKey] = { timestamp, bags, bank, reagentBank }
    - Transaction entries: entry.char = charKey

    Returns nil if player data not yet available (early load).
    CALLERS MUST handle nil return gracefully.
]]

-- Get character key in format "CharName-RealmName"
-- Returns nil if player info not yet available
function IM:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()

    -- Guard against early load before player data is available
    if not name or not realm or name == "Unknown" or realm == "" then
        return nil
    end

    return name .. "-" .. realm
end

-- Get or create character metadata entry
-- Returns nil if character key not available (early load)
function IM:GetCharacterData(charKey)
    charKey = charKey or self:GetCharacterKey()

    -- Guard against nil charKey (early load)
    if not charKey then
        return nil
    end

    if not self.db.global.characters[charKey] then
        -- Create new character entry
        local _, class = UnitClass("player")
        local faction = UnitFactionGroup("player")
        self.db.global.characters[charKey] = {
            gold = GetMoney(),
            lastSeen = time(),
            faction = faction,
            class = class,
            level = UnitLevel("player"),
            inventoryValue = 0,
            lastInventoryUpdate = 0,
        }
    end
    return self.db.global.characters[charKey]
end

-- Update character gold snapshot (with validation)
function IM:UpdateCharacterGold()
    local charData = self:GetCharacterData()

    -- Guard against early load
    if not charData then
        self:Debug("[NetWorth] Skipping gold update - character data not ready")
        return
    end

    local newGold = GetMoney()
    local oldGold = charData.gold or 0

    -- Validation: don't persist if new value is 0 but we had significant gold
    -- This prevents garbage values from early login from being saved
    if newGold == 0 and oldGold > 10000 then -- More than 1g
        self:Debug("[NetWorth] Skipping suspicious gold update: 0 (had " .. oldGold .. ")")
        return
    end

    charData.gold = newGold
    charData.lastSeen = time()
    charData.level = UnitLevel("player")
end

-- Add a transaction to the new ledger system
-- Entry types:
--   Item transactions: sell, buyback, purchase, loot, ah_sold, ah_bought, mail_item_recv, mail_item_sent
--   Gold-only: repair, repair_guild, ah_deposit, ah_refund, ah_fee, quest_gold,
--              mail_gold_recv, mail_gold_sent, trade_gold_recv, trade_gold_sent
function IM:AddTransaction(entryType, data)
    data = data or {}

    -- Guard against early load - defer transaction if character not ready
    local charKey = self:GetCharacterKey()
    if not charKey then
        self:Debug("[Ledger] Skipping transaction - character data not ready")
        return nil
    end

    local entry = {
        ts = time(),
        t = entryType,
        char = charKey,
        val = data.value or 0,
    }

    -- Item transactions include item data
    if data.itemID then
        entry.item = data.itemID
        entry.link = data.itemLink
        entry.qty = data.quantity or 1
    end

    -- Optional source
    if data.source then
        entry.src = data.source
    end

    -- Insert at beginning (newest first)
    table.insert(self.db.global.transactions.entries, 1, entry)

    -- Update character gold snapshot
    self:UpdateCharacterGold()

    self:Debug("[Ledger] Added " .. entryType .. " transaction: " .. (entry.val or 0) .. "c")

    return entry
end

--[[
    TRANSACTION ENTRY SCHEMA:
    {
        ts = number,          -- Unix timestamp
        t = string,           -- Type: "sell", "loot", "vendor_buy", "repair", "quest", etc.
        char = string,        -- Character key "CharName-RealmName"
        val = number,         -- Value in copper (positive = income, negative = expense/outflow)
        item = number?,       -- Optional: itemID for item transactions
        link = string?,       -- Optional: item link for item transactions
        qty = number?,        -- Optional: quantity (default 1)
        src = string?,        -- Optional: source (mob name, quest name, etc.)
    }

    TRANSACTION TYPES:
    Income: sell, loot, ah_sold, mail_gold_recv, quest, trade_gold_recv
    Expense: vendor_buy, repair, repair_guild, ah_bought, ah_deposit, mail_gold_sent, trade_gold_sent
    Transfers: warbank_deposit (neg), warbank_withdraw (pos) - own money moving, not income/expense
    Bank Items: bank_deposit, bank_withdraw (no gold value, just item tracking)
]]

-- Get transactions with optional filters and pagination
-- filters: { type, types, char, minDate, maxDate, search, limit, offset }
-- Returns: results table, totalCount (for pagination info)
function IM:GetTransactions(filters)
    filters = filters or {}
    local results = {}
    local totalMatched = 0
    local limit = filters.limit or 0  -- 0 = no limit
    local offset = filters.offset or 0

    for _, entry in ipairs(self.db.global.transactions.entries) do
        local include = true

        -- Filter by type
        if filters.type and entry.t ~= filters.type then
            include = false
        end

        -- Filter by type group (multiple types)
        if filters.types and include then
            local found = false
            for _, t in ipairs(filters.types) do
                if entry.t == t then
                    found = true
                    break
                end
            end
            include = found
        end

        -- Filter by character
        if filters.char and include then
            if entry.char ~= filters.char then
                include = false
            end
        end

        -- Filter by date range
        if filters.minDate and include then
            if entry.ts < filters.minDate then
                include = false
            end
        end

        if filters.maxDate and include then
            if entry.ts > filters.maxDate then
                include = false
            end
        end

        -- Search filter (item name)
        if filters.search and include and entry.link then
            local searchLower = filters.search:lower()
            local linkLower = entry.link:lower()
            if not linkLower:find(searchLower, 1, true) then
                include = false
            end
        end

        if include then
            totalMatched = totalMatched + 1

            -- Apply pagination: skip offset entries, then collect up to limit
            if totalMatched > offset then
                if limit == 0 or #results < limit then
                    table.insert(results, entry)
                end
            end
        end
    end

    return results, totalMatched
end

-- Transaction types that are transfers (not income/expense)
-- These are your own money moving between locations
local TRANSFER_TYPES = {
    warbank_deposit = true,   -- Gold moved TO warband bank
    warbank_withdraw = true,  -- Gold moved FROM warband bank
}

-- Get ledger statistics with optional filters
function IM:GetLedgerStats(filters)
    local transactions = self:GetTransactions(filters)

    local stats = {
        totalIncome = 0,
        totalExpense = 0,
        totalTransfersIn = 0,   -- Gold moved TO you from your other storage
        totalTransfersOut = 0,  -- Gold moved FROM you to your other storage
        netGold = 0,
        counts = {},
    }

    for _, entry in ipairs(transactions) do
        local val = entry.val or 0

        -- Track by type
        stats.counts[entry.t] = (stats.counts[entry.t] or 0) + 1

        -- Check if this is a transfer (own money moving between locations)
        if TRANSFER_TYPES[entry.t] then
            -- Transfers don't count toward income/expense
            if val > 0 then
                stats.totalTransfersIn = stats.totalTransfersIn + val
            else
                stats.totalTransfersOut = stats.totalTransfersOut + math.abs(val)
            end
        else
            -- Track income vs expense (actual gold entering/leaving your account)
            if val > 0 then
                stats.totalIncome = stats.totalIncome + val
            else
                stats.totalExpense = stats.totalExpense + math.abs(val)
            end
        end
    end

    stats.netGold = stats.totalIncome - stats.totalExpense
    stats.totalEntries = #transactions

    return stats
end

-- Purge old entries based on ledger.maxAgeDays setting
function IM:PurgeOldEntries()
    local maxAgeDays = self.db.global.ledger.maxAgeDays
    if maxAgeDays <= 0 then
        return 0 -- Purging disabled
    end

    local cutoffTime = time() - (maxAgeDays * 86400) -- 86400 seconds per day
    local entries = self.db.global.transactions.entries
    local purged = 0

    -- Remove entries older than cutoff (iterate backwards)
    for i = #entries, 1, -1 do
        if entries[i].ts < cutoffTime then
            table.remove(entries, i)
            purged = purged + 1
        end
    end

    if purged > 0 then
        self:Debug("[Ledger] Purged " .. purged .. " entries older than " .. maxAgeDays .. " days")
    end

    return purged
end

-- Clear all transactions
function IM:ClearTransactions()
    self.db.global.transactions.entries = {}
    self:Print("Transaction ledger cleared")
end

-- Get all known characters
function IM:GetAllCharacters()
    local chars = {}
    for charKey, data in pairs(self.db.global.characters) do
        table.insert(chars, {
            key = charKey,
            name = charKey:match("^(.+)-"),
            realm = charKey:match("-(.+)$"),
            gold = data.gold,
            faction = data.faction,
            class = data.class,
            level = data.level,
            lastSeen = data.lastSeen,
            inventoryValue = data.inventoryValue,
        })
    end

    -- Sort by last seen (most recent first)
    table.sort(chars, function(a, b)
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)

    return chars
end

-- Get account-wide gold total
function IM:GetAccountGold()
    local total = 0
    for _, data in pairs(self.db.global.characters) do
        total = total + (data.gold or 0)
    end
    return total
end

-- Get account-wide net worth (gold + inventory value + warband bank)
function IM:GetAccountNetWorth()
    local total = 0
    for _, data in pairs(self.db.global.characters) do
        total = total + (data.gold or 0) + (data.inventoryValue or 0)
    end
    -- Include warband bank gold
    total = total + (self.db.global.warbandBankGold or 0)
    return total
end

-- Get warband bank gold
function IM:GetWarbandBankGold()
    return self.db.global.warbandBankGold or 0
end

-- Set warband bank gold (manual entry)
function IM:SetWarbandBankGold(copper)
    self.db.global.warbandBankGold = copper or 0
    self.db.global.warbandBankGoldUpdated = time()
    self:Debug("[Database] Warband bank gold set to " .. (copper or 0))
end

-- Get warband bank gold last updated timestamp
function IM:GetWarbandBankGoldUpdated()
    return self.db.global.warbandBankGoldUpdated or 0
end
