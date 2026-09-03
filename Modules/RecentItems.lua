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

    Blizzard's flags only cover items that arrived while you were NOT looking.
    Anything that lands while the bag is already open - dungeon loot with bags
    up - is never flagged, and a stack top-up is never flagged either because
    the slot already held that item. Both showed up as Recent "randomly
    missing" things. BagData already diffs bag contents, so those two gaps are
    closed by listening to it and keeping our own session-local flags
    alongside Blizzard's. Still no timestamps, no GUIDs and no persistence -
    "recent until you close the bag" needs none of it.

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

-- Our own flags, filling the two gaps in Blizzard's: [bagID][slotID] = true.
-- Session-local by design; they are cleared when the bag closes.
local _ownFlags = {}

-- A move is a remove followed immediately by an add of the same item, and it
-- must not read as an arrival or reorganising your bags lights every slot up.
local _recentlyRemoved = {}
local MOVE_WINDOW = 0.5

local function _SetOwnFlag(bagID, slotID, value)
    if bagID == nil or slotID == nil then return end
    _ownFlags[bagID] = _ownFlags[bagID] or {}
    _ownFlags[bagID][slotID] = value or nil
end

local function _GetOwnFlag(bagID, slotID)
    return _ownFlags[bagID] and _ownFlags[bagID][slotID] or false
end

local function _WasJustMoved(itemID)
    if not itemID then return false end
    local at = _recentlyRemoved[itemID]
    return at ~= nil and (GetTime() - at) < MOVE_WINDOW
end

function RecentItems:OnInitialize()
    wipe(_ownFlags)
    wipe(_recentlyRemoved)
end

function RecentItems:OnEnable()
    local module = self

    local BagData = IM:GetModule("BagData")
    if not BagData or not BagData.RegisterCallback then return end

    BagData:RegisterCallback("OnBagItemAdded", function(bagID, slotID, data)
        -- The first scan reports the entire inventory as added
        if not BagData:IsInitialScanComplete() then return end
        if data and _WasJustMoved(data.itemID) then return end

        _SetOwnFlag(bagID, slotID, true)
    end)

    BagData:RegisterCallback("OnBagItemChanged", function(bagID, slotID, oldData, newData)
        if not BagData:IsInitialScanComplete() then return end
        if not oldData or not newData then return end

        -- Stack grew: Blizzard does not flag this, but it IS an acquisition
        if newData.itemID == oldData.itemID
            and (newData.count or 0) > (oldData.count or 0) then
            _SetOwnFlag(bagID, slotID, true)
        elseif newData.itemID ~= oldData.itemID then
            -- A different item occupies the slot now: an arrival unless what
            -- landed is something that just left another slot (a move)
            if _WasJustMoved(newData.itemID) then
                _SetOwnFlag(bagID, slotID, nil)
            else
                _SetOwnFlag(bagID, slotID, true)
            end
        end
    end)

    BagData:RegisterCallback("OnBagItemRemoved", function(bagID, slotID, data)
        _SetOwnFlag(bagID, slotID, nil)
        if data and data.itemID then
            _recentlyRemoved[data.itemID] = GetTime()
        end
    end)
end

function RecentItems:IsEnabled()

    local settings = IM.db and IM.db.global and IM.db.global.bagUI
    if not settings then return true end

    -- Default on; only an explicit false disables it
    return settings.showRecentSection ~= false
end

function RecentItems:IsRecent(bagID, slotID)
    if bagID == nil or slotID == nil then return false end

    if _GetOwnFlag(bagID, slotID) then return true end

    if not _Available() then return false end
    local ok, isNew = pcall(C_NewItems.IsNewItem, bagID, slotID)
    return ok and isNew == true
end

function RecentItems:MarkSeen(bagID, slotID)
    if bagID == nil or slotID == nil then return end

    _SetOwnFlag(bagID, slotID, nil)

    if not _Available() or not C_NewItems.RemoveNewItem then return end
    pcall(C_NewItems.RemoveNewItem, bagID, slotID)
end

-- Clear every flag. Called when the bag window closes: the user has now seen
-- what arrived, so the items belong back in their normal categories.
function RecentItems:MarkAllSeen()
    wipe(_ownFlags)
    wipe(_recentlyRemoved)

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

-- Diagnostic: report what the client currently considers new, and whether the
-- API is even present. "No Recent section" has two very different causes -
-- nothing is flagged, or flagging works and our display path is broken - and
-- they are indistinguishable from the outside.
function RecentItems:Diagnose()
    if not _Available() then
        IM:PrintError("C_NewItems.IsNewItem is unavailable on this client build")
        return
    end

    local scanned, byBlizzard, byUs = 0, 0, 0
    for _, bagID in ipairs(_TrackedBags()) do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0
        for slotID = 1, slots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                scanned = scanned + 1

                local ours = _GetOwnFlag(bagID, slotID)
                local ok, theirs = pcall(C_NewItems.IsNewItem, bagID, slotID)
                theirs = ok and theirs == true

                if ours then byUs = byUs + 1 end
                if theirs then byBlizzard = byBlizzard + 1 end

                if ours or theirs then
                    IM:Print(string.format("  new (%s): bag %d slot %d - %s",
                        (ours and theirs and "both") or (ours and "tracked") or "blizzard",
                        bagID, slotID, tostring(info.hyperlink or info.itemID)))
                end
            end
        end
    end

    local BagData = IM:GetModule("BagData")
    IM:Print(string.format(
        "Recent: %d occupied slots | blizzard-flagged %d | our-tracked %d | section %s | bagdata %s",
        scanned, byBlizzard, byUs,
        self:IsEnabled() and "on" or "off",
        (BagData and BagData:IsInitialScanComplete()) and "ready" or "NOT READY"))
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
