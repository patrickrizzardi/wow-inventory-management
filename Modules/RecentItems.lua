--[[
    InventoryManager - RecentItems.lua
    "Recently acquired" tracking, backed by Blizzard's own new-item flags.

    Blizzard already marks slots that received an item while the bags were
    closed - it is what drives the flash on the default bag UI - so this wraps
    C_NewItems rather than diffing bag contents and stamping timestamps.

    What that buys, and what it costs:
    - Moving items between your own bags does NOT flag them.
    - Logging in does NOT flag your whole inventory.
    - Loot, mail and vault/bank withdrawals DO flag, which is the point.
    - Topping up an existing stack does NOT flag: the slot already held that
      item. This is the one real gap versus tracking it ourselves, and it is
      deliberate - see git log --grep=RecentItems for the decision.

    The flags are cleared by Blizzard's ContainerFrame code, which this addon
    suppresses, so nothing would ever clear them on its own. MarkAllSeen is
    called when the bag closes: open the bag, see what is new, close it, and
    the items return to their normal categories.

    Public Methods:
    - RecentItems:IsEnabled() - whether the Recent section should be built
    - RecentItems:IsRecent(bagID, slotID) - true if the slot holds a new item
    - RecentItems:MarkSeen(bagID, slotID) - clear one slot's flag
    - RecentItems:MarkAllSeen() - clear every flag
    - RecentItems:HasAny() - true if anything is currently flagged
]]

local addonName, IM = ...

local RecentItems = {}
IM:RegisterModule("RecentItems", RecentItems)

-- Bags this addon displays; Blizzard's flags are keyed by bag and slot
local function _TrackedBags()
    local bags = { BACKPACK_CONTAINER }
    for bagID = 1, NUM_BAG_SLOTS do
        table.insert(bags, bagID)
    end
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
        table.insert(bags, Enum.BagIndex.ReagentBag)
    end
    return bags
end

local function _Available()
    return C_NewItems and C_NewItems.IsNewItem ~= nil
end

function RecentItems:IsEnabled()
    if not _Available() then return false end

    local settings = IM.db and IM.db.global and IM.db.global.bagUI
    if not settings then return true end

    -- Default on; only an explicit false disables it
    return settings.showRecentSection ~= false
end

function RecentItems:IsRecent(bagID, slotID)
    if not _Available() then return false end
    if bagID == nil or slotID == nil then return false end

    local ok, isNew = pcall(C_NewItems.IsNewItem, bagID, slotID)
    return ok and isNew == true
end

function RecentItems:MarkSeen(bagID, slotID)
    if not _Available() or not C_NewItems.RemoveNewItem then return end
    if bagID == nil or slotID == nil then return end

    pcall(C_NewItems.RemoveNewItem, bagID, slotID)
end

-- Clear every flag. Called when the bag window closes: the user has now seen
-- what arrived, so the items belong back in their normal categories.
function RecentItems:MarkAllSeen()
    if not _Available() then return end

    if C_NewItems.ClearAll then
        pcall(C_NewItems.ClearAll)
        return
    end

    -- Older clients: clear slot by slot
    for _, bagID in ipairs(_TrackedBags()) do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0
        for slotID = 1, slots do
            self:MarkSeen(bagID, slotID)
        end
    end
end

function RecentItems:HasAny()
    if not _Available() then return false end

    for _, bagID in ipairs(_TrackedBags()) do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0
        for slotID = 1, slots do
            if self:IsRecent(bagID, slotID) then
                return true
            end
        end
    end

    return false
end
