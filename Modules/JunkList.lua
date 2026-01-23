--[[
    InventoryManager - Modules/JunkList.lua
    Junk item marking and click handling.

    Note: Visual overlays are handled by UI.OverlayFactory (green sell overlay
    shows for junk items since they will be auto-sold). This module handles
    Ctrl+Alt+Click to toggle junk status and provides junk list management.
]]

local addonName, IM = ...

local JunkList = {}
IM:RegisterModule("JunkList", JunkList)

function JunkList:OnEnable()
    -- Hook item button clicks for Ctrl+Alt+Click to mark as junk
    self:HookItemButtons()

    -- Note: Overlay refresh is handled by ItemLock module which uses OverlayFactory
    -- JunkList just needs to trigger a refresh when junk status changes
    IM:RegisterJunkListCallback(function(itemID, added)
        -- Trigger overlay refresh via ItemLock
        if IM.modules.ItemLock then
            IM.modules.ItemLock:RequestRefresh()
        end
    end)
end

-- Refresh overlays for a specific bag (delegates to ItemLock/OverlayFactory)
function JunkList:RefreshBagOverlays(bagID)
    if IM.modules.ItemLock then
        IM.modules.ItemLock:RefreshBagOverlays(bagID)
    end
end

-- Refresh all bag overlays (delegates to ItemLock/OverlayFactory)
function JunkList:RefreshAllOverlays()
    if IM.modules.ItemLock then
        IM.modules.ItemLock:RefreshAllOverlays()
    end
end

-- Hook item button clicks
function JunkList:HookItemButtons()
    -- Modern WoW retail uses different button structure
    -- Hook for combined bags view (modern retail default)
    if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnClick then
        hooksecurefunc(ContainerFrameItemButtonMixin, "OnClick", function(itemButton, button)
            JunkList:OnItemButtonClick(itemButton, button)
        end)
    end

    -- Also refresh when container updates
    if ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            JunkList:RefreshAllOverlays()
        end)
    end
end

-- Handle item button click (modern retail)
function JunkList:OnItemButtonClick(itemButton, button)
    -- Ctrl+Alt+Click = Toggle junk
    if IsAltKeyDown() and IsControlKeyDown() and button == "LeftButton" then
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
                local isNowJunk = IM:ToggleJunkList(info.itemID)
                local itemName = GetItemInfo(info.itemID) or info.itemID

                if isNowJunk then
                    IM:Print("Marked as junk: " .. (info.hyperlink or itemName))
                else
                    IM:Print("Unmarked from junk: " .. (info.hyperlink or itemName))
                end

                -- Refresh overlay via ItemLock/OverlayFactory
                if IM.modules.ItemLock then
                    IM.modules.ItemLock:UpdateOverlay(itemButton, bagID, slotID)
                end
            end
        end
    end
end

-- Toggle junk on item by ID (for slash command)
function JunkList:ToggleJunkByID(itemID)
    return IM:ToggleJunkList(itemID)
end

-- Get all junk item IDs
function JunkList:GetJunkItems()
    local items = {}
    for itemID in pairs(IM.db.global.junkList) do
        table.insert(items, itemID)
    end
    return items
end

-- Clear all junk marks
function JunkList:ClearAllJunk()
    wipe(IM.db.global.junkList)
    self:RefreshAllOverlays()
    IM:Print("Junk list cleared")
end
