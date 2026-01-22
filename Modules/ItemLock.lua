--[[
    InventoryManager - Modules/ItemLock.lua
    Item lock/whitelist visual overlay and click handling.

    This module manages:
    - Visual overlays on item buttons (lock, sell, unsellable states)
    - Alt+Click to toggle item lock
    - Protection against selling/deleting locked items
    - Auto-buyback of accidentally sold locked items

    Uses UI.OverlayFactory for overlay creation and state management.

    @module Modules.ItemLock
]]

local addonName, IM = ...

local ItemLock = {}
IM:RegisterModule("ItemLock", ItemLock)

-- Debounce timer for overlay refresh batching
local pendingRefresh = false
local pendingBags = {} -- Track which bags need refresh

-- Request a debounced refresh (batches multiple rapid events)
local function _RequestRefresh(bagID)
    if bagID then
        pendingBags[bagID] = true
    else
        -- Full refresh requested
        wipe(pendingBags)
        pendingBags.full = true
    end

    if pendingRefresh then return end
    pendingRefresh = true

    C_Timer.After(0.05, function()
        pendingRefresh = false
        if pendingBags.full then
            ItemLock:RefreshAllOverlays()
        else
            for bid, _ in pairs(pendingBags) do
                ItemLock:RefreshBagOverlays(bid)
            end
        end
        wipe(pendingBags)
    end)
end

function ItemLock:OnEnable()
    -- Register for bag update events to refresh overlays (debounced)
    IM:RegisterEvent("BAG_UPDATE", function(event, bagID)
        _RequestRefresh(bagID)
    end)

    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        _RequestRefresh()
    end)

    -- Refresh when bags are opened
    IM:RegisterEvent("BAG_OPEN", function(event, bagID)
        C_Timer.After(0.1, function()
            _RequestRefresh()
        end)
    end)

    -- Also hook the bag frame OnShow for combined bags view
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function()
            C_Timer.After(0.1, function()
                _RequestRefresh()
            end)
        end)
    end

    -- Hook individual bag frames too
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", function()
                C_Timer.After(0.1, function()
                    _RequestRefresh()
                end)
            end)
        end
    end

    -- Refresh overlays when merchant opens (to show sellable borders)
    -- Single delayed refresh instead of multiple
    IM:RegisterEvent("MERCHANT_SHOW", function()
        C_Timer.After(0.2, function() _RequestRefresh() end)
    end)

    -- Refresh overlays when merchant closes (to hide sellable borders)
    IM:RegisterEvent("MERCHANT_CLOSED", function()
        C_Timer.After(0.1, function() _RequestRefresh() end)
    end)

    -- Hook item button clicks for Alt+Click to lock
    self:HookItemButtons()

    -- Hook to prevent manual selling of locked items at vendor
    self:HookMerchantSelling()

    -- Hook to prevent deletion of locked items
    self:HookDeletion()

    -- Refresh overlays when whitelist changes (from UI panel, slash command, etc.)
    IM:RegisterWhitelistCallback(function(itemID, added)
        _RequestRefresh()
    end)

    -- Refresh overlays when junk list changes
    IM:RegisterJunkListCallback(function(itemID, added)
        _RequestRefresh()
    end)
end

-- Hook to prevent/warn when selling locked items at merchant
function ItemLock:HookMerchantSelling()
    -- Track if we're currently buying back to prevent loops
    local isBuyingBack = false

    -- Function to check buyback list for locked items and buy them back
    local function _CheckAndBuybackLockedItems()
        if isBuyingBack then return end
        if not MerchantFrame or not MerchantFrame:IsShown() then return end

        for i = 1, 12 do
            -- Use GetBuybackItemLink which is more reliable across WoW versions
            local itemLink = GetBuybackItemLink(i)
            if itemLink then
                -- Extract itemID from the link
                local itemID = GetItemInfoInstant(itemLink)
                if itemID and IM:IsWhitelisted(itemID) then
                    -- Found a locked item in buyback - buy it back!
                    isBuyingBack = true

                    -- Get buyback cost for logging (may be nil for edge cases)
                    local _, _, price, quantity = GetBuybackItemInfo(i)
                    price = price or 0
                    quantity = quantity or 1

                    BuybackItem(i)
                    IM:ShowWarning("Protected item auto-recovered:\n\n" .. itemLink .. "\n\nLocked items cannot be sold.")

                    -- Log the buyback
                    IM:AddBuybackHistoryEntry(itemID, itemLink, quantity, price)

                    -- Reset flag and refresh overlays after a short delay
                    C_Timer.After(0.2, function()
                        isBuyingBack = false
                        ItemLock:RefreshAllOverlays()
                    end)
                    return
                end
            end
        end
    end

    -- Primary hook: UseContainerItem (standard sell method)
    hooksecurefunc(C_Container, "UseContainerItem", function(bagID, slotID)
        if not MerchantFrame or not MerchantFrame:IsShown() then return end
        C_Timer.After(0.1, _CheckAndBuybackLockedItems)
    end)

    -- Fallback hook: BAG_UPDATE while merchant is open
    -- This catches any sales that might not go through UseContainerItem
    IM:RegisterEvent("BAG_UPDATE", function()
        if MerchantFrame and MerchantFrame:IsShown() then
            C_Timer.After(0.15, _CheckAndBuybackLockedItems)
        end
    end)

    -- Also check on PLAYERBANKSLOTS_CHANGED for bank merchant interactions
    IM:RegisterEvent("MERCHANT_UPDATE", function()
        C_Timer.After(0.1, _CheckAndBuybackLockedItems)
    end)
end

-- Hook to prevent deletion of locked items
function ItemLock:HookDeletion()
    -- The delete confirmation dialogs in WoW:
    -- DELETE_ITEM, DELETE_GOOD_ITEM, DELETE_QUEST_ITEM, DELETE_GOOD_QUEST_ITEM
    -- We hook StaticPopup_Show to intercept these

    local originalStaticPopupShow = StaticPopup_Show

    StaticPopup_Show = function(which, text_arg1, text_arg2, data, insertedFrame)
        -- Check if this is a delete confirmation
        if which == "DELETE_ITEM" or which == "DELETE_GOOD_ITEM" or
           which == "DELETE_QUEST_ITEM" or which == "DELETE_GOOD_QUEST_ITEM" then
            -- Get the item on the cursor
            local cursorType, itemID = GetCursorInfo()
            if cursorType == "item" and itemID then
                -- Check if this item is locked
                if IM:IsWhitelisted(itemID) then
                    -- Clear the cursor and show warning popup
                    ClearCursor()
                    local itemLink = select(2, GetItemInfo(itemID))
                    local itemName = itemLink or ("Item #" .. itemID)
                    IM:ShowWarning("Cannot delete locked item:\n\n" .. itemName .. "\n\nUnlock it first (Alt+Click) to delete.")
                    return nil -- Block the popup
                end
            end
        end

        -- Call original for all other cases
        return originalStaticPopupShow(which, text_arg1, text_arg2, data, insertedFrame)
    end

    IM:Debug("ItemLock: Hooked StaticPopup_Show for deletion protection")
end

--[[
    Update overlay for a specific item button.
    Delegates to UI.OverlayFactory for overlay creation and state management.

    @param itemButton Frame - The item button to update
    @param bagID number - Bag ID (0-5 or reagent bag)
    @param slotID number - Slot ID within the bag
]]
function ItemLock:UpdateOverlay(itemButton, bagID, slotID)
    -- Delegate to OverlayFactory
    if IM.UI and IM.UI.OverlayFactory then
        IM.UI.OverlayFactory:Update(itemButton, bagID, slotID)
    end
end

-- Refresh overlays for a specific bag
function ItemLock:RefreshBagOverlays(bagID)
    local updated = 0

    -- Modern retail: ContainerFrame.Items table
    local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
    if containerFrame and containerFrame:IsShown() and containerFrame.Items then
        for _, itemButton in ipairs(containerFrame.Items) do
            if itemButton.GetBagID and itemButton.GetID then
                local btnBagID = itemButton:GetBagID()
                local btnSlotID = itemButton:GetID()
                if btnBagID and btnSlotID then
                    self:UpdateOverlay(itemButton, btnBagID, btnSlotID)
                    updated = updated + 1
                end
            end
        end
    end

    -- Try combined bags view (modern retail)
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() and ContainerFrameCombinedBags.Items then
        for _, itemButton in ipairs(ContainerFrameCombinedBags.Items) do
            if itemButton.GetBagID and itemButton.GetID then
                local btnBagID = itemButton:GetBagID()
                local btnSlotID = itemButton:GetID()
                if btnBagID == bagID and btnSlotID then
                    self:UpdateOverlay(itemButton, btnBagID, btnSlotID)
                    updated = updated + 1
                end
            end
        end
    end

    return updated
end

-- Fallback: Try to find all visible item buttons regardless of bag frame type
function ItemLock:RefreshAllOverlaysModern()
    local updated = 0

    -- Try combined bags
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags.Items then
        for _, itemButton in ipairs(ContainerFrameCombinedBags.Items) do
            if itemButton.GetBagID and itemButton.GetID then
                local bagID = itemButton:GetBagID()
                local slotID = itemButton:GetID()
                if bagID and slotID then
                    self:UpdateOverlay(itemButton, bagID, slotID)
                    updated = updated + 1
                end
            end
        end
    end

    -- Try individual container frames with Items table
    for i = 1, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf and cf:IsShown() and cf.Items then
            for _, btn in ipairs(cf.Items) do
                if btn.GetBagID and btn.GetID then
                    local bagID = btn:GetBagID()
                    local slotID = btn:GetID()
                    if bagID and slotID then
                        self:UpdateOverlay(btn, bagID, slotID)
                        updated = updated + 1
                    end
                end
            end
        end
    end

    return updated
end

-- Refresh all bag overlays
function ItemLock:RefreshAllOverlays()
    local totalUpdated = 0

    -- Scan all bags including reagent bag
    for _, bagID in ipairs(IM:GetBagIDsToScan()) do
        totalUpdated = totalUpdated + self:RefreshBagOverlays(bagID)
    end

    -- If nothing found, try modern fallback
    if totalUpdated == 0 then
        totalUpdated = self:RefreshAllOverlaysModern()
    end
end

-- Hook item button clicks
function ItemLock:HookItemButtons()
    -- Track which buttons we've hooked to avoid double-hooking
    -- Weak table prevents memory leaks from deleted buttons
    local hookedButtons = setmetatable({}, { __mode = "k" })

    -- Helper function to hook a single item button
    local function _HookButton(btn)
        if not btn or hookedButtons[btn] then return end
        hookedButtons[btn] = true

        -- Hook OnClick if it exists
        if btn.GetScript and btn:GetScript("OnClick") then
            btn:HookScript("OnClick", function(self, button)
                ItemLock:OnItemButtonClick(self, button)
            end)
        end

        -- Also hook OnMouseDown as backup
        if btn.HookScript then
            btn:HookScript("OnMouseDown", function(self, button)
                if IsAltKeyDown() and not IsControlKeyDown() and button == "LeftButton" then
                    ItemLock:OnItemButtonClick(self, button)
                end
            end)
        end
    end

    -- Hook combined bags items
    local function _HookCombinedBags()
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags.Items then
            for _, btn in ipairs(ContainerFrameCombinedBags.Items) do
                _HookButton(btn)
            end
        end
    end

    -- Hook individual container frame items
    local function _HookContainerFrames()
        for i = 1, 13 do
            local cf = _G["ContainerFrame" .. i]
            if cf and cf.Items then
                for _, btn in ipairs(cf.Items) do
                    _HookButton(btn)
                end
            end
        end
    end

    -- Hook for combined bags view (modern retail default)
    if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnClick then
        hooksecurefunc(ContainerFrameItemButtonMixin, "OnClick", function(itemButton, button)
            ItemLock:OnItemButtonClick(itemButton, button)
        end)
    end

    -- Fallback: Hook HandleModifiedItemClick
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(itemLink, itemLocation)
            C_Timer.After(0.05, function()
                ItemLock:RefreshAllOverlays()
            end)
        end)
    end

    -- Hook ContainerFrame_Update to catch new buttons
    if ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            _HookContainerFrames()
            ItemLock:RefreshAllOverlays()
        end)
    end

    -- Hook combined bags OnShow to catch its buttons
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function()
            C_Timer.After(0.1, function()
                _HookCombinedBags()
            end)
        end)

        -- Also hook its Update method if it exists
        if ContainerFrameCombinedBags.Update then
            hooksecurefunc(ContainerFrameCombinedBags, "Update", function()
                _HookCombinedBags()
            end)
        end
    end

    -- Hook individual container frames OnShow
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", function()
                C_Timer.After(0.1, function()
                    _HookContainerFrames()
                end)
            end)
        end
    end

    -- Initial hook attempt
    C_Timer.After(0.5, function()
        _HookCombinedBags()
        _HookContainerFrames()
    end)

    -- Register for PLAYER_ENTERING_WORLD to catch late loading
    IM:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(1, function()
            _HookCombinedBags()
            _HookContainerFrames()
        end)
    end)
end

-- Handle item button click (modern retail)
function ItemLock:OnItemButtonClick(itemButton, button)
    -- Alt+Click = Toggle lock
    if IsAltKeyDown() and not IsControlKeyDown() and button == "LeftButton" then
        local bagID, slotID = itemButton:GetBagID(), itemButton:GetID()

        -- Fallback for different button types
        if not bagID and itemButton.GetBagID then
            bagID = itemButton:GetBagID()
        end
        if not slotID and itemButton.GetID then
            slotID = itemButton:GetID()
        end

        if bagID and slotID then
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                local isNowLocked = IM:ToggleWhitelist(info.itemID)
                local itemName = GetItemInfo(info.itemID) or info.itemID

                if isNowLocked then
                    IM:Print("Locked: " .. (info.hyperlink or itemName))
                else
                    IM:Print("Unlocked: " .. (info.hyperlink or itemName))
                end

                -- Refresh overlay
                self:UpdateOverlay(itemButton, bagID, slotID)
            end
        end
    end
end

-- Handle modified click on item button
function ItemLock:OnItemButtonModifiedClick(itemButton, button)
    -- Alt+Click = Toggle lock
    if IsAltKeyDown() and not IsControlKeyDown() and button == "LeftButton" then
        local bagID = itemButton:GetParent():GetID()
        local slotID = itemButton:GetID()

        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if info and info.itemID then
            local isNowLocked = IM:ToggleWhitelist(info.itemID)
            local itemName = GetItemInfo(info.itemID) or info.itemID

            if isNowLocked then
                IM:Print("Locked: " .. (info.hyperlink or itemName))
            else
                IM:Print("Unlocked: " .. (info.hyperlink or itemName))
            end

            -- Refresh overlay
            self:UpdateOverlay(itemButton, bagID, slotID)
        end
    end
end

-- Toggle lock on item by ID (for slash command)
function ItemLock:ToggleLockByID(itemID)
    return IM:ToggleWhitelist(itemID)
end

-- Get all locked item IDs
function ItemLock:GetLockedItems()
    local items = {}
    for itemID in pairs(IM.db.global.whitelist) do
        table.insert(items, itemID)
    end
    return items
end

-- Clear all locks (with confirmation)
function ItemLock:ClearAllLocks()
    wipe(IM.db.global.whitelist)
    self:RefreshAllOverlays()
    IM:Print("All item locks cleared")
end

-- Public function for other modules to request overlay refresh
function ItemLock:RequestRefresh()
    _RequestRefresh()
end

-- Global alias for convenience
function IM:RefreshBagOverlays()
    if self.modules.ItemLock then
        self.modules.ItemLock:RequestRefresh()
    end
end
