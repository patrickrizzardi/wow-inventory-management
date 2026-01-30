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
local _pendingAttempts = 0

-- Statistics for current sell session
local _sessionStats = {
    itemCount = 0,
    totalValue = 0,
}

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

    -- Listen for item lock changes (item being processed)
    IM:RegisterEvent("ITEM_LOCK_CHANGED", function(event, bagID, slotID)
        if _isSelling then
            module:ProcessNextItem()
        end
    end)

    IM:Debug("[AutoSell] Events registered successfully")
end

-- Called when merchant window opens
function AutoSell:OnMerchantShow()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] MERCHANT_SHOW fired, autoSellEnabled=" .. tostring(IM.db.global.autoSellEnabled))

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

    -- Small delay to let UI settle, then start selling
    IM:Debug("[AutoSell] Scheduling SellJunk in 0.2s...")
    C_Timer.After(0.2, function()
        IM:Debug("[AutoSell] Timer fired, calling SellJunk")
        module:SellJunk()
    end)
end

-- Called when merchant window closes
function AutoSell:OnMerchantClosed()
    -- Cancel any pending sales
    self:CancelSelling()

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

-- Start selling junk items
function AutoSell:SellJunk()
    IM:Debug("[AutoSell] SellJunk called")

    -- Check if at merchant
    if not MerchantFrame then
        IM:Debug("[AutoSell] SellJunk: MerchantFrame is nil")
        IM:Print("You must be at a merchant to sell items")
        return
    end

    if not MerchantFrame:IsShown() then
        IM:Debug("[AutoSell] SellJunk: MerchantFrame not shown")
        IM:Print("You must be at a merchant to sell items")
        return
    end

    -- Don't start if already selling
    if _isSelling then
        IM:Debug("[AutoSell] SellJunk: Already selling, skipping")
        return
    end

    IM:Debug("[AutoSell] SellJunk: Getting items to sell...")

    -- Get items to sell
    local items, pendingItems = IM.Filters:GetAutoSellItems()

    IM:Debug("[AutoSell] SellJunk: GetAutoSellItems returned " .. #items .. " items")

    if #items == 0 then
        if pendingItems and #pendingItems > 0 then
            _pendingAttempts = _pendingAttempts + 1
            IM:Debug("[AutoSell] Waiting on item info (" .. #pendingItems .. " pending), attempt " .. _pendingAttempts)
            if _pendingAttempts <= 10 then
                _sellTimer = C_Timer.NewTimer(0.2, function()
                    if MerchantFrame and MerchantFrame:IsShown() then
                        module:SellJunk()
                    end
                end)
            end
            return
        end
        IM:Debug("[AutoSell] No items to sell")
        _pendingAttempts = 0
        return
    end
    _pendingAttempts = 0

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
    self:ProcessNextItem()
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

    -- Check if merchant is still open
    if not MerchantFrame or not MerchantFrame:IsShown() then
        IM:Debug("[AutoSell] ProcessNextItem: Merchant closed, cancelling")
        module:CancelSelling()
        return
    end

    -- Get next item
    local item = table.remove(_sellQueue, 1)
    IM:Debug("[AutoSell] Processing: bag=" .. item.bagID .. " slot=" .. item.slotID .. " itemID=" .. item.itemID)

    -- Verify item still exists in that slot
    local info = C_Container.GetContainerItemInfo(item.bagID, item.slotID)
    if not info or not info.itemID then
        IM:Debug("[AutoSell] Item no longer in slot or has no itemID, skipping")
        module:ProcessNextItem()
        return
    end
    if info.itemID ~= item.itemID then
        -- Item moved or was removed, skip it
        IM:Debug("[AutoSell] Item moved (expected " .. item.itemID .. ", found " .. info.itemID .. "), skipping")
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

    -- Verify item still passes filters (in case whitelist changed)
    local shouldSell = IM.Filters:ShouldAutoSell(item.bagID, item.slotID, item.itemID, item.itemLink)
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
            if _isSelling then
                -- Put item back for retry
                table.insert(_sellQueue, 1, item)
                module:ProcessNextItem()
            end
        end)
        return
    end

    IM:Debug("[AutoSell] <<< UseContainerItem returned")

    -- Schedule next item (longer delay to prevent "object is busy" errors)
    _sellTimer = C_Timer.NewTimer(0.15, function()
        if _isSelling then
            module:ProcessNextItem()
        end
    end)
end

-- Finish selling session
function AutoSell:FinishSelling()
    IM:Debug("[AutoSell] FinishSelling called, itemCount=" .. _sessionStats.itemCount .. ", totalValue=" .. _sessionStats.totalValue)
    _isSelling = false

    if _sessionStats.itemCount > 0 then
        IM:Print("Sold " .. _sessionStats.itemCount .. " items for " .. IM:FormatMoney(_sessionStats.totalValue))
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

    -- If additional items become eligible after item data loads, keep selling
    if MerchantFrame and MerchantFrame:IsShown() then
        local items, pendingItems = IM.Filters:GetAutoSellItems()
        if (items and #items > 0) or (pendingItems and #pendingItems > 0) then
            C_Timer.After(0.2, function()
                if not _isSelling and MerchantFrame and MerchantFrame:IsShown() then
                    self:SellJunk()
                end
            end)
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
