--[[
    InventoryManager - ZygorUpgrades.lua
    Reads Zygor Guides Viewer's gear-upgrade verdict so the bag overlays can show
    "+23%" on items that beat what the player is wearing.

    Zygor is an optional dependency with no public API. Everything here goes
    through ZGV.ItemScore.Upgrades:IsUpgrade, which exists in the retail, Forever and
    TBC Anniversary builds, behind one pcall: with Zygor missing, disabled, or changed
    underneath us, the answer is nil and nothing throws. Zygor's own settings are
    honoured - if its gear advice is off (or it is set to stop at max level), or its
    "mark upgrades in bags" option is off, this returns nil rather than overriding them.

    Public Methods:
    - ZygorUpgrades:GetUpgradePercent(itemLink) - percent better than the equipped
      item, or nil when Zygor is absent/off or the item is not an upgrade
]]

local addonName, IM = ...

local ZygorUpgrades = {}
IM:RegisterModule("ZygorUpgrades", ZygorUpgrades)

-- Zygor returns a quest item it protects as a 999999% "upgrade"; anything above this is
-- clamped so a real upgrade never prints a number wider than the slot.
local MAX_PERCENT = 999

-- Zygor's own labels in IsUpgrade's fifth return. The first is a protected quest item, which
-- is not gear. The other two mean "item data not loaded yet".
local COMMENT_QUEST_ITEM = "quest item"
local COMMENT_NOT_SCORED = "not scored"
local COMMENT_NO_LINK = "no link"

local function _IsEquippable(itemLink)
    local check = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
    -- No way to ask: let Zygor decide rather than hiding every upgrade.
    if not check then return true end
    return check(itemLink) and true or false
end

-- Runs inside pcall: any missing piece of Zygor's internals raises here and becomes nil.
local function _Query(itemLink)
    local upgrades = ZGV.ItemScore.Upgrades
    if not upgrades:IsEnabled() then return nil end
    if not ZGV.db.profile.markupgrades then return nil end

    local isUpgrade, _, change, _, comment = upgrades:IsUpgrade(itemLink)

    -- The first call for an item only starts Zygor's item load (ItemScore:GetItemDetails
    -- returns false and fills its cache from the load callback). For an item the client
    -- already has, that callback has run by the time the call returns, so asking again
    -- gets the real answer.
    if not isUpgrade and (comment == COMMENT_NOT_SCORED or comment == COMMENT_NO_LINK) then
        isUpgrade, _, change, _, comment = upgrades:IsUpgrade(itemLink)
    end

    if not isUpgrade or comment == COMMENT_QUEST_ITEM then return nil end
    if type(change) ~= "number" then return nil end
    return math.min(change, MAX_PERCENT)
end

function ZygorUpgrades:GetUpgradePercent(itemLink)
    if not ZGV or not itemLink then return nil end
    -- Cheap pre-filter: most bag slots are materials and consumables Zygor has no opinion on.
    if not _IsEquippable(itemLink) then return nil end

    local ok, percent = pcall(_Query, itemLink)
    if not ok then
        IM:Debug("[ZygorUpgrades] Zygor query failed:", percent)
        return nil
    end
    return percent
end
