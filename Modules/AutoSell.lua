--[[
    InventoryManager - Modules/AutoSell.lua
    Automatic selling of junk items at merchants
]]

local addonName, IM = ...

local AutoSell = {}
IM:RegisterModule("AutoSell", AutoSell)

-- Sell queue for processing items one at a time
local _sellQueue = {}
local _isSelling = false
local _sellTimer = nil

-- Track items merchant rejected (cleared when merchant closes)
local _rejectedItems = {}

-- Statistics for current sell session
local _sessionStats = {
    itemCount = 0,
    totalValue = 0,
}

-- Did the addon start the sale now running, or did the user? Set from SellJunk's isAutomatic
-- argument as the sale starts, because it cannot be inferred from anything else the sale carries.
-- FinishSelling reads it so that a hand-clicked Sell All does not sweep items that became eligible
-- after the click - items the user never saw on the list they were looking at.
local _currentSaleIsAutomatic = false

--[[
    Retry budgets for "the client has not sent item data yet".

    Two of them, and the split is the point. The automatic path spends its attempts while the
    player is looking at a vendor window and being told nothing; a player who then clicks Sell All
    is making a fresh, explicit request and must not be handed an empty budget and a "gave up
    waiting" message for attempts they never saw. An explicit action gets its own attempts.

    The automatic budget is refilled by both merchant events, so it cannot wedge. The manual budget
    is refilled by each click, which is what "your click, your attempts" means.
]]
local MAX_PENDING_ATTEMPTS = 10
local _pendingAttempts = {
    automatic = 0,
    manual = 0,
}

-- ============================================================================
-- ITEM DATA SIGNAL
-- ============================================================================

--[[
    One debounced "item data has settled" signal for everything on the auto-sell path.

    GET_ITEM_INFO_RECEIVED fires once per item, in bursts. Anything on this path that wants to
    know when a burst is over subscribes here instead of running a clock of its own; before this
    existed, the sell path and the Auto-Sell popup each polled the bags separately on the same
    burst of arriving data. One handler, one debounce, one broadcast.

    The deadline exists because "no further item data is coming" produces no event at all, so a
    listener with no clock would wait forever. Waiters are one-shot and are dropped when the
    merchant closes - a wait armed at one vendor must never fire a sale at the next one.
]]
local ITEM_DATA_DEBOUNCE = 0.3
local ITEM_DATA_DEADLINE = 2.0

local _itemDataListeners = {}
local _itemDataWaiters = {}
local _itemDataDeadline = nil
local _itemDataNotifyQueued = false
local _itemDataNotifyToken = 0

local function _NotifyItemData()
    _itemDataNotifyQueued = false
    -- Invalidates any debounce callback already in flight, so a deadline firing first cannot be
    -- followed by a second, redundant broadcast.
    _itemDataNotifyToken = _itemDataNotifyToken + 1

    if _itemDataDeadline then
        _itemDataDeadline:Cancel()
        _itemDataDeadline = nil
    end

    for _, listener in ipairs(_itemDataListeners) do
        listener()
    end

    if #_itemDataWaiters > 0 then
        local waiters = _itemDataWaiters
        _itemDataWaiters = {}
        for _, waiter in ipairs(waiters) do
            waiter()
        end
    end
end

-- Run callback once, as soon as the next burst of item data settles or the deadline expires.
local function _WaitForItemData(callback)
    table.insert(_itemDataWaiters, callback)
    if not _itemDataDeadline then
        _itemDataDeadline = C_Timer.NewTimer(ITEM_DATA_DEADLINE, function()
            _itemDataDeadline = nil
            _NotifyItemData()
        end)
    end
end

local function _CancelItemDataWaiters()
    wipe(_itemDataWaiters)
    if _itemDataDeadline then
        _itemDataDeadline:Cancel()
        _itemDataDeadline = nil
    end
end

-- Subscribe to the signal above for as long as the addon is loaded. The callback is told only that
-- item data arrived; whether it is still relevant (window shown, merchant open) is the caller's
-- own precondition to check.
function AutoSell:RegisterItemDataListener(callback)
    table.insert(_itemDataListeners, callback)
end

-- The one phrase for "the server has not sent this item's data yet", in chat and in the vendor
-- popup alike. UI/AutoSellPopup.lua calls this rather than wording it again: the popup saying
-- "still loading" while chat said "waiting on item data" is one condition described as two, and a
-- player reasonably reads two descriptions as two problems.
-- @param count number - Items whose data has not arrived
function AutoSell.PendingDataPhrase(count)
    return count .. " item(s) still loading"
end

-- @param verb string - "is waiting for" / "gave up waiting for"
local function _PendingDataMessage(count, verb)
    return "Auto-sell " .. verb .. " " .. AutoSell.PendingDataPhrase(count) ..
        " - nothing was sold. Reopen the merchant once the Auto-Sell list finishes loading."
end

--[[
    Does this bag slot still hold what the queue entry says it holds?

    The queue is built from one scan and drained over many frames, so the bags move underneath it:
    an item sold, a stack merged, a loot landing in a freed slot. Checked immediately before the
    slot is handed to the vendor, because that is the only moment the answer is still true.

    @param entry table - Queue entry carrying bagID, slotID and itemID
    @return boolean matches
    @return table|nil info - The container info, non-nil whenever matches is true
]]
local function _SlotStillHolds(entry)
    local info = C_Container.GetContainerItemInfo(entry.bagID, entry.slotID)
    if not info or not info.itemID or info.itemID ~= entry.itemID then
        return false, info
    end
    return true, info
end

function AutoSell:OnInitialize()
    IM:Debug("[AutoSell] Module initialized")
end

function AutoSell:OnEnable()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] OnEnable called, registering events...")

    -- Register for merchant events
    IM:RegisterEvent("MERCHANT_SHOW", function()
        IM:Debug("[AutoSell] MERCHANT_SHOW event received!")
        module:OnMerchantShow()
    end)

    IM:RegisterEvent("MERCHANT_CLOSED", function()
        module:OnMerchantClosed()
    end)

    -- The one item-data handler for the auto-sell path. See the ITEM DATA SIGNAL block above.
    IM:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if _itemDataNotifyQueued then return end
        _itemDataNotifyQueued = true

        local token = _itemDataNotifyToken
        C_Timer.After(ITEM_DATA_DEBOUNCE, function()
            if token ~= _itemDataNotifyToken then return end
            _NotifyItemData()
        end)
    end)

    -- No ITEM_LOCK_CHANGED handler - timer-only progression is more reliable

    IM:Debug("[AutoSell] Events registered successfully")
end

-- Called when merchant window opens
function AutoSell:OnMerchantShow()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] MERCHANT_SHOW fired, autoSellEnabled=" .. tostring(IM.db.global.autoSellEnabled))

    -- Fresh event, fresh budget: a previous visit that spent all its attempts waiting on item data
    -- must not leave this one unable to retry at all. Unconditional, including on a re-fire for an
    -- already-open window, so this can never wedge.
    _pendingAttempts.automatic = 0

    -- Always show the Auto-Sell popup when merchant opens
    if IM.UI and IM.UI.AutoSellPopup then
        C_Timer.After(0.1, function()
            IM.UI.AutoSellPopup:Show()
        end)
    end

    -- Check if auto-sell is enabled
    if not IM.db.global.autoSellEnabled then
        IM:Debug("[AutoSell] Auto-sell disabled, skipping")
        return
    end

    -- Small delay to let the vendor window settle, then sell. The setting checked above is the
    -- whole permission: switching auto-sell on is the user saying "sell at vendors without asking
    -- me", so there is nothing further to confirm at the vendor. A MERCHANT_SHOW re-fire for a
    -- window already on screen simply re-runs the same filter over the same bags.
    IM:Debug("[AutoSell] Scheduling sell in 0.2s...")
    C_Timer.After(0.2, function()
        if not MerchantFrame or not MerchantFrame:IsShown() then return end
        IM:Debug("[AutoSell] Timer fired, calling SellJunk")
        module:SellJunk(true)
    end)
end

-- Called when merchant window closes
function AutoSell:OnMerchantClosed()
    -- Cancel any pending sales
    self:CancelSelling()

    -- Drop anything waiting on item data. A wait armed at this vendor must not come due at the
    -- next one and start a sale nobody asked for there.
    _CancelItemDataWaiters()

    -- Clear rejected items list for next merchant
    wipe(_rejectedItems)

    -- The visit is over, so everything scoped to it goes with it.
    _pendingAttempts.automatic = 0
    _pendingAttempts.manual = 0

    -- Hide the Auto-Sell popup
    if IM.UI and IM.UI.AutoSellPopup then
        IM.UI.AutoSellPopup:Hide()
    end
end

-- Cancel ongoing sell operation
function AutoSell:CancelSelling()
    _isSelling = false
    wipe(_sellQueue)
    if _sellTimer then
        _sellTimer:Cancel()
        _sellTimer = nil
    end
end

--[[
    Start selling whatever Filters:ShouldAutoSell approves right now.

    @param isAutomatic boolean|nil - True when the addon started this sale itself (the merchant-open
           path and its continuations: the item-data retry, the post-sale sweep). False/nil for a
           sale the user started by hand (the popup's "Sell All", /im sell). It has to be passed
           rather than inferred - both kinds build their list the same way - and FinishSelling's
           sweep keys on it.

    @param isRetry boolean|nil - True only for the module's own continuation after waiting on item
           data. It exists so a fresh manual click can be told apart from the tail of an earlier
           one, and refill the manual retry budget; a retry must not refill it or the budget would
           never run out.

    @return boolean started - True only when a queue was built and the sell loop began on this
            call. It does NOT mean anything was vendored: the merchant can refuse every entry.
            False for every early exit, including "waiting on item data" - a sale that may yet
            start from the retry has not started now.
    @return string|nil reason - Why not, when started is false: "no-merchant", "already-selling",
            "autosell-disabled", "waiting-on-data", "gave-up-waiting" or "nothing-to-sell".
]]
function AutoSell:SellJunk(isAutomatic, isRetry)
    local module = self  -- Capture for closures

    isAutomatic = isAutomatic and true or false

    IM:Debug("[AutoSell] SellJunk called" .. (isAutomatic and " (automatic)" or " (manual)"))

    -- A hand-clicked sale is an explicit request, so it brings its own attempts. See
    -- _pendingAttempts: the automatic path can empty its budget without the player ever seeing a
    -- message, and their first click must not be answered with "gave up waiting".
    if not isAutomatic and not isRetry then
        _pendingAttempts.manual = 0
    end

    local budget = isAutomatic and "automatic" or "manual"

    -- Check if at merchant
    if not MerchantFrame then
        IM:Debug("[AutoSell] SellJunk: MerchantFrame is nil")
        IM:Print("You must be at a merchant to sell items")
        return false, "no-merchant"
    end

    if not MerchantFrame:IsShown() then
        IM:Debug("[AutoSell] SellJunk: MerchantFrame not shown")
        IM:Print("You must be at a merchant to sell items")
        return false, "no-merchant"
    end

    --[[
        THE chokepoint for unattended selling: `autoSellEnabled` IS the permission.

        The setting is what the user switched on to say "sell at vendors without asking me", and it
        is the only thing standing between the filter and the vendor on an unattended sale. So it is
        read HERE, where the queue is built, and not only at the schedulers that start one.

        The difference is time. An automatic sale is not always started by the event that decided to
        run it: the item-data retry re-enters this function up to a whole retry budget's worth of
        deadlines later, and FinishSelling's sweep arms itself 0.2s ahead. A user who unticks
        auto-sell inside either window has withdrawn the permission the sale was scheduled under,
        and a check that lives only at the schedulers cannot see that. This one does, because every
        sale-start path must traverse it - which is what makes it unroutable-around rather than a
        hand-maintained list of call sites.

        Silent, deliberately: the player unticked the setting themselves, so a chat line explaining
        that the thing they just switched off did not happen is noise. Manual sales are not gated -
        Sell All is a sale the user is asking for by hand, and the setting governs the unattended
        path only.
    ]]
    if isAutomatic and not (IM.db and IM.db.global and IM.db.global.autoSellEnabled) then
        IM:Debug("[AutoSell] SellJunk: automatic sale refused - auto-sell is switched off")
        return false, "autosell-disabled"
    end

    -- Don't start if already selling: a second Sell All while the queue is still draining is
    -- answered rather than allowed to build a second queue over the same slots.
    if _isSelling then
        IM:Debug("[AutoSell] SellJunk: Already selling, skipping")
        return false, "already-selling"
    end

    IM:Debug("[AutoSell] SellJunk: Getting items to sell...")

    -- Get items to sell
    local items, pendingItems = IM.Filters:GetAutoSellItems(true)  -- verbose=true for actual selling
    IM:Debug("[AutoSell] SellJunk: GetAutoSellItems returned " .. #items .. " items")

    if #items == 0 then
        if pendingItems and #pendingItems > 0 then
            if _pendingAttempts[budget] < MAX_PENDING_ATTEMPTS then
                _pendingAttempts[budget] = _pendingAttempts[budget] + 1
                IM:Debug("[AutoSell] Waiting on item info (" .. #pendingItems .. " pending), " ..
                    budget .. " attempt " .. _pendingAttempts[budget])
                -- The shared item-data signal, so this and the Auto-Sell popup do not walk the
                -- bags independently on the same burst of arriving data.
                _WaitForItemData(function()
                    if MerchantFrame and MerchantFrame:IsShown() then
                        module:SellJunk(isAutomatic, true)
                    end
                end)
                return false, "waiting-on-data"
            end
            -- Budget spent with data still missing. Say so: a silent stop here looks exactly
            -- like "there was nothing to sell".
            IM:Print(_PendingDataMessage(#pendingItems, "gave up waiting for"))
            return false, "gave-up-waiting"
        end
        IM:Debug("[AutoSell] No items to sell")
        _pendingAttempts[budget] = 0
        return false, "nothing-to-sell"
    end
    _pendingAttempts[budget] = 0

    -- Reset session stats
    _sessionStats.itemCount = 0
    _sessionStats.totalValue = 0

    -- Build sell queue
    wipe(_sellQueue)
    for _, item in ipairs(items) do
        table.insert(_sellQueue, item)
    end

    IM:Debug("[AutoSell] Starting to sell " .. #_sellQueue .. " items")
    for i, item in ipairs(_sellQueue) do
        IM:Debug("[AutoSell]   Queue[" .. i .. "]: " .. (item.itemLink or item.itemID))
    end

    -- Start selling
    _isSelling = true
    _currentSaleIsAutomatic = isAutomatic
    self:ProcessNextItem()

    return true
end

-- Process the next item in the queue
function AutoSell:ProcessNextItem()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] ProcessNextItem called, _isSelling=" .. tostring(_isSelling) .. ", queueSize=" .. #_sellQueue)

    -- Safety check
    if not _isSelling then
        IM:Debug("[AutoSell] ProcessNextItem: Not selling, returning")
        return
    end

    -- Check if queue is empty
    if #_sellQueue == 0 then
        IM:Debug("[AutoSell] ProcessNextItem: Queue empty, finishing")
        module:FinishSelling()
        return
    end

    --[[
        The permission is re-read per item, not only where the queue was built.

        The drain is the longest of the three windows the setting has to survive: 0.15s per item
        plus a retry every time a slot is locked, so a full bag of junk is several seconds of
        selling with the merchant frame open and the settings panel reachable the whole time. A
        player who unticks auto-sell after the queue was built has withdrawn the only authorisation
        an unattended sale has, for every item still in it.

        Keyed on _currentSaleIsAutomatic for the same reason the chokepoint is: Sell All is a sale
        the user is asking for by hand and the setting governs the unattended path only.

        Not silent, unlike the chokepoint. There nothing had happened yet; here items have already
        gone to the vendor and more were queued, so stopping without a word is indistinguishable
        from the addon breaking mid-sale. FinishSelling reports the part that did sell, and the
        line below says why the rest did not.
    ]]
    if _currentSaleIsAutomatic and not (IM.db and IM.db.global and IM.db.global.autoSellEnabled) then
        local remaining = #_sellQueue
        wipe(_sellQueue)
        IM:Debug("[AutoSell] ProcessNextItem: stood down mid-drain - auto-sell is switched off")
        module:FinishSelling()
        IM:Print("Auto-sell was switched off during the sale - stopped with " .. remaining ..
            " item(s) left in your bags.")
        return
    end

    -- Check if merchant is still open
    if not MerchantFrame or not MerchantFrame:IsShown() then
        IM:Debug("[AutoSell] ProcessNextItem: Merchant closed, cancelling")
        module:CancelSelling()
        return
    end

    -- Get next item
    local item = table.remove(_sellQueue, 1)
    IM:Debug("[AutoSell] Processing: bag=" .. item.bagID .. " slot=" .. item.slotID .. " itemID=" .. item.itemID)

    -- Skip items the merchant already rejected this session
    if _rejectedItems[item.itemID] then
        IM:Debug("[AutoSell] SKIPPING rejected item (merchant won't buy): " .. (item.itemLink or item.itemID))
        module:ProcessNextItem()
        return
    end

    -- Verify the slot still holds what the queue entry says. The queue was built from one scan and
    -- the bags have been moving ever since - an earlier sale freed a slot, a loot landed in it -
    -- so this is checked per item, immediately before the vendor call below.
    local matches, info = _SlotStillHolds(item)
    if not matches then
        IM:Debug("[AutoSell] Slot no longer holds the queued item, skipping: expected itemID=" ..
            tostring(item.itemID) ..
            ", found itemID=" .. tostring(info and info.itemID))
        module:ProcessNextItem()
        return
    end

    -- Check if item is locked (being moved/processed)
    if info.isLocked then
        IM:Debug("[AutoSell] Item is locked, waiting...")
        -- Wait a bit and try again, but check merchant is still open
        C_Timer.After(0.1, function()
            -- Double-check both _isSelling flag AND merchant is still open
            if _isSelling and MerchantFrame and MerchantFrame:IsShown() then
                -- Put item back at front of queue
                table.insert(_sellQueue, 1, item)
                module:ProcessNextItem()
            else
                -- Merchant closed or selling cancelled - ensure clean state
                IM:Debug("[AutoSell] Sell cancelled during locked item retry, cleaning up")
                module:CancelSelling()
            end
        end)
        return
    end

    -- Verify the slot's contents still pass the filters (in case whitelist changed). Asked with the
    -- LIVE link out of the identity check above, never the one the queue was built with: the same
    -- itemID with different bonus IDs is a different item level, so a higher-ilvl variant swapped
    -- into the slot mid-queue passes the identity check and would then be judged against the queued
    -- variant's item level - bypassing the maxItemLevel ceiling for the item actually being sold.
    local shouldSell = IM.Filters:ShouldAutoSell(item.bagID, item.slotID, item.itemID, info.hyperlink, true)
    if not shouldSell then
        IM:Debug("[AutoSell] Item no longer passes filters: " .. (item.itemLink or item.itemID))
        module:ProcessNextItem()
        return
    end

    -- Get sell price for stats (display only - VendorTracking handles ledger logging)
    local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(item.itemID)
    if sellPrice then
        _sessionStats.itemCount = _sessionStats.itemCount + (info.stackCount or 1)
        _sessionStats.totalValue = _sessionStats.totalValue + (sellPrice * (info.stackCount or 1))
        -- Note: VendorTracking now handles logging via PLAYER_MONEY event
    end

    -- Sell the item by using it on merchant
    IM:Debug("[AutoSell] >>> SELLING: " .. (item.itemLink or item.itemID) .. " via C_Container.UseContainerItem(" .. item.bagID .. ", " .. item.slotID .. ")")

    local success, err = pcall(function()
        C_Container.UseContainerItem(item.bagID, item.slotID)
    end)

    if not success then
        IM:Debug("[AutoSell] <<< UseContainerItem error: " .. tostring(err))
        -- Retry after longer delay if busy
        _sellTimer = C_Timer.NewTimer(0.3, function()
            if _isSelling and MerchantFrame and MerchantFrame:IsShown() then
                -- Put item back for retry
                table.insert(_sellQueue, 1, item)
                module:ProcessNextItem()
            end
        end)
        return
    end

    IM:Debug("[AutoSell] <<< UseContainerItem returned")

    -- Timer-based progression: wait for sell to complete, then check result
    local checkBagID, checkSlotID, checkItemID = item.bagID, item.slotID, item.itemID
    _sellTimer = C_Timer.NewTimer(0.15, function()
        if not _isSelling or not MerchantFrame or not MerchantFrame:IsShown() then
            return
        end

        local checkInfo = C_Container.GetContainerItemInfo(checkBagID, checkSlotID)

        if not checkInfo or checkInfo.itemID ~= checkItemID then
            -- Item gone or different item = sold successfully
            IM:Debug("[AutoSell] Timer: Item sold successfully")
        else
            -- Same item still there = merchant rejected it
            IM:Debug("[AutoSell] Timer: Item rejected by merchant")
            _rejectedItems[checkItemID] = true
            -- Undo stats we added
            local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(checkItemID)
            if sellPrice then
                _sessionStats.itemCount = _sessionStats.itemCount - (checkInfo.stackCount or 1)
                _sessionStats.totalValue = _sessionStats.totalValue - (sellPrice * (checkInfo.stackCount or 1))
            end
        end

        -- Process next item
        module:ProcessNextItem()
    end)
end

-- Finish selling session
function AutoSell:FinishSelling()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] FinishSelling called, itemCount=" .. _sessionStats.itemCount .. ", totalValue=" .. _sessionStats.totalValue)
    _isSelling = false

    if _sessionStats.itemCount > 0 then
        -- The one buyback warning the player gets, so it is worded carefully: no count of buyback
        -- slots, because itemCount sums item units across stacks while a buyback entry is one
        -- stack, and no claim that everything just sold is still there - only the most recent
        -- entries are.
        IM:Print("Sold " .. _sessionStats.itemCount .. " items for " .. IM:FormatMoney(_sessionStats.totalValue) ..
            " - only the most recently sold items are still in this vendor's Buyback tab; earlier ones may already be gone.")
    else
        IM:Debug("[AutoSell] No items were sold")
    end

    -- Reset stats
    _sessionStats.itemCount = 0
    _sessionStats.totalValue = 0

    -- Refresh the Auto-Sell popup
    if IM.UI and IM.UI.AutoSellPopup and IM.UI.AutoSellPopup:IsShown() then
        IM.UI.AutoSellPopup:Refresh()
    end

    -- If additional items become eligible after item data loads, keep selling - but only ones the
    -- filter accepts NOW. Items still waiting on data are not swept in here; they are left to the
    -- wait-and-retry inside SellJunk, which is where the remaining attempts are counted.
    if MerchantFrame and MerchantFrame:IsShown() then
        local items, pendingItems = IM.Filters:GetAutoSellItems()

        -- Filter out rejected items
        local validItems = {}
        local filteredCount = 0
        for _, item in ipairs(items or {}) do
            if not _rejectedItems[item.itemID] then
                table.insert(validItems, item)
            else
                filteredCount = filteredCount + 1
            end
        end

        IM:Debug("[AutoSell] FinishSelling check: " .. #(items or {}) .. " found, " .. filteredCount .. " rejected, " .. #validItems .. " valid, " .. #(pendingItems or {}) .. " pending")

        -- The sweep continues an AUTOMATIC sale only. A hand-clicked Sell All sold the list the
        -- user was looking at; items that became eligible while it ran were never on that list, so
        -- sweeping them would vendor things they never saw. SellJunk re-reads the setting when the
        -- timer below comes due, so a sweep armed here still stands down if auto-sell is switched
        -- off inside those 0.2 seconds.
        if #validItems > 0 and _currentSaleIsAutomatic then
            C_Timer.After(0.2, function()
                if not _isSelling and MerchantFrame and MerchantFrame:IsShown() then
                    module:SellJunk(true)
                end
            end)
        elseif #validItems > 0 then
            -- Suppressing the sweep silently looks exactly like the addon breaking: the items are
            -- still in the bags, nothing was said, and the Auto-Sell popup only redraws itself
            -- when it happens to be open. Name the reason and give the next step.
            IM:Print(#validItems .. " more item(s) now match your auto-sell filters, but this sale " ..
                "was started by hand - click Sell All to sell them too.")
            IM:Debug("[AutoSell] Sweep suppressed: the sale was manual")
        elseif pendingItems and #pendingItems > 0 then
            IM:Debug("[AutoSell] Only pending items remain (" .. #pendingItems .. "), letting retry logic handle it")
        end
    end
end

-- Get count of sellable items (for UI display)
function AutoSell:GetSellableCount()
    return IM.Filters:GetAutoSellCount()
end

-- Check if currently selling
function AutoSell:IsSelling()
    return _isSelling
end

-- Get remaining items in queue
function AutoSell:GetQueueSize()
    return #_sellQueue
end
