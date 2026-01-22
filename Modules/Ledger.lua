--[[
    InventoryManager - Modules/Ledger.lua
    Core ledger module for transaction formatting, export, and maintenance.

    Provides:
    - Entry formatting for UI display
    - Export to clipboard string
    - Periodic age-based purging
    - Character data updates on login

    Low-level transaction storage is in Database.lua
    This module provides higher-level formatting and maintenance.

    @module Modules.Ledger
]]

local addonName, IM = ...

local Ledger = {}
IM:RegisterModule("Ledger", Ledger)

-- Track session start time for "This Session" filter
local _sessionStartTime = time()

-- Transaction type metadata for display
local TRANSACTION_TYPES = {
    -- Item transactions
    sell            = { label = "SOLD",      color = "|cff00ff00", icon = nil },
    buyback         = { label = "BUYBACK",   color = "|cffff8800", icon = nil },
    purchase        = { label = "BOUGHT",    color = "|cffff6666", icon = nil },
    loot            = { label = "LOOT",      color = "|cff00ccff", icon = nil },
    ah_sold         = { label = "AH SOLD",   color = "|cff00ff88", icon = "Interface\\Icons\\INV_Hammer_20" },
    ah_bought       = { label = "AH BOUGHT", color = "|cffff4444", icon = "Interface\\Icons\\INV_Hammer_20" },
    mail_item_recv  = { label = "MAIL IN",   color = "|cffcc99ff", icon = "Interface\\Icons\\INV_Letter_15" },
    mail_item_sent  = { label = "MAIL OUT",  color = "|cffcc99ff", icon = "Interface\\Icons\\INV_Letter_15" },

    -- Gold-only transactions
    repair          = { label = "REPAIR",    color = "|cffff9900", icon = "Interface\\Icons\\Trade_BlackSmithing" },
    repair_guild    = { label = "REPAIR(G)", color = "|cff00ff00", icon = "Interface\\Icons\\Trade_BlackSmithing" },
    ah_deposit      = { label = "AH DEPOSIT",color = "|cffff6666", icon = "Interface\\Icons\\INV_Hammer_20" },
    ah_refund       = { label = "AH REFUND", color = "|cff00ff00", icon = "Interface\\Icons\\INV_Hammer_20" },
    ah_fee          = { label = "AH FEE",    color = "|cffff6666", icon = "Interface\\Icons\\INV_Hammer_20" },
    quest_gold      = { label = "QUEST",     color = "|cffffff00", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    mail_gold_recv  = { label = "MAIL GOLD", color = "|cff00ff00", icon = "Interface\\Icons\\INV_Letter_15" },
    mail_gold_sent  = { label = "SENT GOLD", color = "|cffff6666", icon = "Interface\\Icons\\INV_Letter_15" },
    trade_gold_recv = { label = "TRADE IN",  color = "|cff00ff00", icon = "Interface\\Icons\\Achievement_GuildPerk_BountifulBags" },
    trade_gold_sent = { label = "TRADE OUT", color = "|cffff6666", icon = "Interface\\Icons\\Achievement_GuildPerk_BountifulBags" },

    -- Warband bank transfers (gold - own money moving between locations, not income/expense)
    warbank_deposit = { label = "TRANSFER OUT",  color = "|cff88CCFF", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    warbank_withdraw= { label = "TRANSFER IN", color = "|cff88CCFF", icon = "Interface\\Icons\\INV_Misc_Coin_01" },

    -- Bank item transfers (items, no gold exchanged)
    bank_deposit    = { label = "BANK DEPOSIT",    color = "|cff888888", icon = nil },
    bank_withdraw   = { label = "BANK WITHDRAW",   color = "|cff888888", icon = nil },
    warbank_item_in = { label = "WARBANK DEPOSIT", color = "|cff888888", icon = nil },
    warbank_item_out= { label = "WARBANK WITHDRAW",color = "|cff888888", icon = nil },

    -- Guild bank transactions (gold - communal money, IS income/expense)
    guildbank_gold_in  = { label = "GBANK WITHDRAW", color = "|cff00ff00", icon = "Interface\\Icons\\INV_Misc_Bag_10_Green" },
    guildbank_gold_out = { label = "GBANK DEPOSIT",  color = "|cffff6666", icon = "Interface\\Icons\\INV_Misc_Bag_10_Green" },

    -- Guild bank item transfers (tracking only)
    guildbank_item_in  = { label = "GBANK WITHDRAW", color = "|cff40C040", icon = "Interface\\Icons\\INV_Misc_Bag_10_Green" },
    guildbank_item_out = { label = "GBANK DEPOSIT",  color = "|cff888888", icon = "Interface\\Icons\\INV_Misc_Bag_10_Green" },

    -- Travel costs
    flight             = { label = "FLIGHT",        color = "|cff88CCFF", icon = "Interface\\Icons\\Ability_Mount_GryphonRideWild" },

    -- Appearance/cosmetic costs
    transmog           = { label = "TRANSMOG",      color = "|cffcc66ff", icon = "Interface\\Icons\\INV_Arcane_SpectrumTrinket" },
    barber             = { label = "BARBER",        color = "|cffcc66ff", icon = "Interface\\Icons\\INV_Misc_Comb_01" },

    -- Black Market Auction House
    bmah_bid           = { label = "BMAH",          color = "|cffff9900", icon = "Interface\\Icons\\INV_Misc_Coin_17" },

    -- Unclaimed/Other transactions (catch-all for untracked gold changes)
    other_income       = { label = "OTHER IN",      color = "|cff888888", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    other_expense      = { label = "OTHER OUT",     color = "|cff888888", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

-- Fallback for unknown types
local DEFAULT_TYPE = { label = "OTHER", color = "|cff888888", icon = nil }

function Ledger:OnEnable()
    IM:Debug("[Ledger] OnEnable called")

    -- Update character data on login
    IM:RegisterEvent("PLAYER_ENTERING_WORLD", function(event, isInitialLogin, isReloadingUi)
        self:OnPlayerLogin(isInitialLogin, isReloadingUi)
    end)

    -- Update gold on money changes
    IM:RegisterEvent("PLAYER_MONEY", function()
        IM:UpdateCharacterGold()
    end)

    -- Periodic purge check (every 10 minutes)
    C_Timer.NewTicker(600, function()
        IM:PurgeOldEntries()
    end)

    -- Initial purge on load
    C_Timer.After(5, function()
        IM:PurgeOldEntries()
    end)

    IM:Debug("[Ledger] Module enabled")
end

-- Called when player logs in or reloads
function Ledger:OnPlayerLogin(isInitialLogin, isReloadingUi)
    -- Ensure character data exists
    IM:GetCharacterData()

    -- Update gold snapshot
    IM:UpdateCharacterGold()

    if isInitialLogin then
        IM:Debug("[Ledger] Initial login - character data updated")
    end
end

-- Get type metadata for display
function Ledger:GetTypeInfo(entryType)
    return TRANSACTION_TYPES[entryType] or DEFAULT_TYPE
end

-- Format a single transaction entry for UI display
function Ledger:FormatEntry(entry)
    local typeInfo = self:GetTypeInfo(entry.t)

    local formatted = {
        -- Raw data
        timestamp = entry.ts,
        type = entry.t,
        value = entry.val or 0,
        character = entry.char,

        -- Display data
        typeLabel = typeInfo.label,
        typeColor = typeInfo.color,
        typeIcon = typeInfo.icon,
        timestampFormatted = date("%m/%d %H:%M", entry.ts),

        -- Item data (if present)
        itemID = entry.item,
        itemLink = entry.link,
        quantity = entry.qty or 1,
        source = entry.src,

        -- Formatted value
        valueFormatted = entry.val and entry.val ~= 0 and IM:FormatMoney(math.abs(entry.val)) or "",
        isExpense = (entry.val or 0) < 0,
    }

    -- Parse character name and realm from key
    if entry.char then
        formatted.charName = entry.char:match("^(.+)-") or entry.char
        formatted.charRealm = entry.char:match("-(.+)$") or ""
    end

    return formatted
end

-- Get formatted entries for UI display
function Ledger:GetFormattedEntries(filters)
    local entries = IM:GetTransactions(filters)
    local formatted = {}

    for i, entry in ipairs(entries) do
        formatted[i] = self:FormatEntry(entry)
    end

    return formatted
end

-- Export transactions to string (for clipboard)
function Ledger:ExportToString(filters)
    local entries = IM:GetTransactions(filters)
    local lines = {
        "InventoryManager Transaction Ledger",
        "Exported: " .. date("%Y-%m-%d %H:%M:%S"),
        "Entries: " .. #entries,
        "",
        "Date/Time | Type | Character | Item | Qty | Value",
        string.rep("-", 80),
    }

    for _, entry in ipairs(entries) do
        local typeInfo = self:GetTypeInfo(entry.t)
        local itemName = "---"

        if entry.item then
            itemName = GetItemInfo(entry.item) or ("Item #" .. entry.item)
        elseif entry.src then
            itemName = entry.src
        end

        local valueStr = ""
        if entry.val and entry.val ~= 0 then
            -- Strip color codes for export
            valueStr = IM:FormatMoney(math.abs(entry.val))
            valueStr = valueStr:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if entry.val < 0 then
                valueStr = "-" .. valueStr
            end
        end

        local line = string.format("%s | %s | %s | %s | x%d | %s",
            date("%Y-%m-%d %H:%M", entry.ts),
            typeInfo.label,
            entry.char or "Unknown",
            itemName,
            entry.qty or 1,
            valueStr
        )
        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

-- Get summary string for display
function Ledger:GetSummaryString(filters)
    local stats = IM:GetLedgerStats(filters)

    local incomeStr = IM:FormatMoney(stats.totalIncome)
    local expenseStr = IM:FormatMoney(stats.totalExpense)
    local netStr = IM:FormatMoney(math.abs(stats.netGold))

    local netColor = stats.netGold >= 0 and "|cff00ff00+" or "|cffff0000-"

    return string.format("Income: %s | Expenses: %s | Net: %s%s|r (%d entries)",
        incomeStr, expenseStr, netColor, netStr, stats.totalEntries)
end

-- Get date filter presets
function Ledger:GetDatePresets()
    local now = time()
    -- Bug #10 fix: Use local midnight instead of UTC midnight
    local localDate = date("*t", now)
    localDate.hour = 0
    localDate.min = 0
    localDate.sec = 0
    local startOfToday = time(localDate)

    return {
        { label = "This Session", minDate = _sessionStartTime },
        { label = "Today", minDate = startOfToday },
        { label = "Last 7 Days", minDate = now - (7 * 86400) },
        { label = "Last 30 Days", minDate = now - (30 * 86400) },
        { label = "All Time", minDate = nil },
    }
end

-- Get type filter presets
function Ledger:GetTypePresets()
    return {
        { label = "All Types", types = nil },
        { label = "Vendor", types = {"sell", "buyback", "purchase"} },
        { label = "Auction House", types = {"ah_sold", "ah_bought", "ah_deposit", "ah_refund", "ah_fee"} },
        { label = "Black Market AH", types = {"bmah_bid"} },
        { label = "Mail", types = {"mail_item_recv", "mail_item_sent", "mail_gold_recv", "mail_gold_sent"} },
        { label = "Trade", types = {"trade_gold_recv", "trade_gold_sent"} },
        { label = "Loot", types = {"loot"} },
        { label = "Quest", types = {"quest_gold"} },
        { label = "Repair", types = {"repair", "repair_guild"} },
        { label = "Travel", types = {"flight"} },
        { label = "Cosmetic", types = {"transmog", "barber"} },
        { label = "Bank", types = {"bank_deposit", "bank_withdraw", "warbank_deposit", "warbank_withdraw", "warbank_item_in", "warbank_item_out", "guildbank_gold_in", "guildbank_gold_out", "guildbank_item_in", "guildbank_item_out"} },
        { label = "Other/Unknown", types = {"other_income", "other_expense"} },
    }
end

-- Get list of unique characters from transactions
function Ledger:GetCharactersFromTransactions()
    local charSet = {}
    local chars = {}

    for _, entry in ipairs(IM.db.global.transactions.entries) do
        if entry.char and not charSet[entry.char] then
            charSet[entry.char] = true
            table.insert(chars, entry.char)
        end
    end

    table.sort(chars)
    return chars
end
