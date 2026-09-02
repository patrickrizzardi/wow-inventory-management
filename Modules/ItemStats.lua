--[[
    InventoryManager - ItemStats.lua
    Secondary stat resolution for equippable items, with per-link caching.

    Item stats are only readable once the client has cached the item. Until then
    C_Item.GetItemStats returns nil - callers get nil and MUST re-query later.
    This module listens for GET_ITEM_INFO_RECEIVED and fires a debounced callback
    so consumers can re-render once the data lands.

    Public Methods:
    - ItemStats:GetSecondaries(itemLink) - sorted array of {key, name, value}, or nil if uncached
    - ItemStats:GetTopSecondary(itemLink) - highest-rated secondary stat name, or nil
    - ItemStats:GetSecondaryCombo(itemLink) - canonical "Crit / Mastery" grouping label, or nil
    - ItemStats:IsEquippable(itemID) - true for gear that can carry secondaries
    - ItemStats:RegisterRefreshCallback(fn) - called (debounced) when new item data arrives
]]

local addonName, IM = ...

local ItemStats = {}
IM:RegisterModule("ItemStats", ItemStats)

-- ============================================================================
-- STAT DEFINITIONS
-- ============================================================================

-- Canonical display order. Versatility's API key lacks the _SHORT suffix that
-- the other three carry - both spellings are accepted per stat to stay safe
-- across API changes.
local SECONDARY_STATS = {
    {
        id = "CRIT",
        keys = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_RATING" },
        name = STAT_CRITICAL_STRIKE or "Critical Strike",
        short = "Crit",
    },
    {
        id = "HASTE",
        keys = { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_RATING" },
        name = STAT_HASTE or "Haste",
        short = "Haste",
    },
    {
        id = "MASTERY",
        keys = { "ITEM_MOD_MASTERY_RATING_SHORT", "ITEM_MOD_MASTERY_RATING" },
        name = STAT_MASTERY or "Mastery",
        short = "Mastery",
    },
    {
        id = "VERSATILITY",
        keys = { "ITEM_MOD_VERSATILITY", "ITEM_MOD_VERSATILITY_SHORT" },
        name = STAT_VERSATILITY or "Versatility",
        short = "Vers",
    },
}

-- id -> canonical order, so combo labels are stable regardless of which stat is larger
local STAT_ORDER = {}
for i, stat in ipairs(SECONDARY_STATS) do
    STAT_ORDER[stat.id] = i
end

ItemStats.NO_SECONDARY = "No Secondary"
ItemStats.UNKNOWN = "Loading..."

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _statCache = {}       -- [itemLink] = { {id, name, short, value}, ... } (possibly empty)
local _cacheSize = 0
local MAX_CACHE_SIZE = 500

local _refreshCallbacks = {}
local _refreshTimer = nil
local _pendingItemData = false

local function _PruneCache()
    if _cacheSize <= MAX_CACHE_SIZE then return end
    wipe(_statCache)
    _cacheSize = 0
end

local function _NotifyRefresh()
    for _, callback in ipairs(_refreshCallbacks) do
        local ok, err = pcall(callback)
        if not ok then
            IM:Debug("[ItemStats] Refresh callback error: " .. tostring(err))
        end
    end
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function ItemStats:OnInitialize()
    wipe(_statCache)
    _cacheSize = 0
end

function ItemStats:OnEnable()
    local module = self

    -- Item data arriving late is the normal case for freshly looted gear.
    -- Coalesce the burst into one refresh instead of one per item.
    IM:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        _pendingItemData = true
        if _refreshTimer then return end

        _refreshTimer = C_Timer.NewTimer(0.3, function()
            _refreshTimer = nil
            if _pendingItemData then
                _pendingItemData = false
                module:InvalidateUnresolved()
                _NotifyRefresh()
            end
        end)
    end)
end

function ItemStats:RegisterRefreshCallback(callback)
    if type(callback) == "function" then
        table.insert(_refreshCallbacks, callback)
    end
end

-- Drop cached "no stats found" entries so they re-query now that data may exist.
-- Entries with real stats are stable and stay cached.
function ItemStats:InvalidateUnresolved()
    for link, stats in pairs(_statCache) do
        if #stats == 0 then
            _statCache[link] = nil
            _cacheSize = _cacheSize - 1
        end
    end
end

-- ============================================================================
-- QUERIES
-- ============================================================================

-- True when the item occupies a real equipment slot (so secondaries are meaningful)
function ItemStats:IsEquippable(itemID)
    if not itemID then return false end

    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" or equipLoc == "nil" then
        -- GetItemInfoInstant is unreliable for equipLoc on some items; fall back
        local _, _, _, _, _, _, _, _, fullEquipLoc = GetItemInfo(itemID)
        equipLoc = fullEquipLoc
    end

    if not equipLoc or equipLoc == "" or equipLoc == "nil" then return false end
    if equipLoc == "INVTYPE_NON_EQUIP" or equipLoc == "INVTYPE_BAG" then return false end

    return true
end

local function _ReadStats(itemLink)
    if not itemLink then return nil end

    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not getStats then return nil end

    local ok, statTable = pcall(getStats, itemLink)
    if not ok or not statTable then return nil end

    local found = {}
    for _, stat in ipairs(SECONDARY_STATS) do
        local value = nil
        for _, key in ipairs(stat.keys) do
            value = statTable[key]
            if value then break end
        end

        if value and value > 0 then
            table.insert(found, {
                id = stat.id,
                name = stat.name,
                short = stat.short,
                value = value,
            })
        end
    end

    -- Highest rating first; ties broken by canonical order so labels are deterministic
    table.sort(found, function(a, b)
        if a.value ~= b.value then
            return a.value > b.value
        end
        return STAT_ORDER[a.id] < STAT_ORDER[b.id]
    end)

    return found
end

-- Returns array of secondaries (highest first), an empty table when the item has
-- none, or nil when the item data has not been cached by the client yet.
function ItemStats:GetSecondaries(itemLink)
    if not itemLink then return nil end

    local cached = _statCache[itemLink]
    if cached then return cached end

    local stats = _ReadStats(itemLink)
    if not stats then return nil end

    _PruneCache()
    _statCache[itemLink] = stats
    _cacheSize = _cacheSize + 1

    return stats
end

-- Name of the single highest secondary, or nil when data is not available yet
function ItemStats:GetTopSecondary(itemLink)
    local stats = self:GetSecondaries(itemLink)
    if not stats then return nil end
    if #stats == 0 then return self.NO_SECONDARY end

    return stats[1].name
end

-- Grouping label for the item's secondaries, canonically ordered so that
-- Crit/Mastery and Mastery/Crit land in the same bucket.
function ItemStats:GetSecondaryCombo(itemLink)
    local stats = self:GetSecondaries(itemLink)
    if not stats then return nil end
    if #stats == 0 then return self.NO_SECONDARY end

    local ordered = {}
    for _, stat in ipairs(stats) do
        table.insert(ordered, stat)
    end
    table.sort(ordered, function(a, b)
        return STAT_ORDER[a.id] < STAT_ORDER[b.id]
    end)

    local parts = {}
    for _, stat in ipairs(ordered) do
        table.insert(parts, stat.short)
    end

    return table.concat(parts, " / ")
end

-- Sort weight for a stat group header, so groups appear in canonical stat order
function ItemStats:GetGroupOrder(label)
    if not label then return 900 end
    -- Kept under STAT_FALLBACK_ORDER (500) so these stay in the gear block,
    -- at its end, rather than sorting below the non-gear categories.
    if label == self.NO_SECONDARY then return 400 end
    if label == self.UNKNOWN then return 450 end

    -- Rank by the first stat named in the label
    for i, stat in ipairs(SECONDARY_STATS) do
        if label == stat.name then
            return i  -- single-stat labels (Top Stat mode) sort first
        end
        if label:find(stat.short, 1, true) == 1 then
            return 10 + (i * 10) + #label  -- combos grouped by leading stat
        end
    end

    return 460
end
