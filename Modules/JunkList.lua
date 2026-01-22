--[[
    InventoryManager - Modules/JunkList.lua
    Junk item marking with visual overlay and click handling
]]

local addonName, IM = ...

local JunkList = {}
IM:RegisterModule("JunkList", JunkList)

-- Cache of overlay frames keyed by item button
local _overlayFrames = {}

-- Junk/trash icon texture
local JUNK_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

function JunkList:OnEnable()
    -- Register for bag update events to refresh overlays
    IM:RegisterEvent("BAG_UPDATE", function(event, bagID)
        self:RefreshBagOverlays(bagID)
    end)

    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        self:RefreshAllOverlays()
    end)

    -- Hook item button clicks for Ctrl+Alt+Click to mark as junk
    self:HookItemButtons()

    -- Refresh overlays when junk list changes (from UI panel, slash command, etc.)
    IM:RegisterJunkListCallback(function(itemID, added)
        self:RefreshAllOverlays()
    end)

    -- Refresh overlays when whitelist changes (locked items can't be junk)
    IM:RegisterWhitelistCallback(function(itemID, added)
        self:RefreshAllOverlays()
    end)
end

-- Create overlay frame for an item button
function JunkList:CreateOverlay(itemButton)
    if _overlayFrames[itemButton] then
        return _overlayFrames[itemButton]
    end

    local overlay = CreateFrame("Frame", nil, itemButton)
    overlay:SetAllPoints(itemButton)
    overlay:SetFrameLevel(itemButton:GetFrameLevel() + 10)

    -- Junk indicator border
    overlay.border = overlay:CreateTexture(nil, "OVERLAY")
    overlay.border:SetAllPoints()
    overlay.border:SetColorTexture(0.6, 0.6, 0.6, 0.3) -- Gray tint
    overlay.border:Hide()

    -- Junk icon (trash)
    overlay.junkIcon = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    overlay.junkIcon:SetSize(14, 14)
    overlay.junkIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    overlay.junkIcon:SetTexture(JUNK_ICON)
    overlay.junkIcon:Hide()

    overlay:Hide()

    _overlayFrames[itemButton] = overlay
    return overlay
end

-- Update overlay for a specific item button
function JunkList:UpdateOverlay(itemButton, bagID, slotID)
    local overlay = self:CreateOverlay(itemButton)

    -- Get item in this slot
    local info = C_Container.GetContainerItemInfo(bagID, slotID)

    if not info or not info.itemID then
        overlay:Hide()
        return
    end

    local itemID = info.itemID
    local isJunk = IM:IsJunk(itemID)
    local isLocked = IM:IsWhitelisted(itemID)

    -- Don't show junk indicator if locked (lock takes priority)
    if isJunk and not isLocked then
        overlay.border:Show()
        overlay.junkIcon:Show()
        overlay:Show()
    else
        overlay:Hide()
    end
end

-- Refresh overlays for a specific bag
function JunkList:RefreshBagOverlays(bagID)
    -- Get the container frame for this bag
    local containerFrame = _G["ContainerFrame" .. (bagID + 1)]
    if not containerFrame then return end

    local numSlots = C_Container.GetContainerNumSlots(bagID)
    for slotID = 1, numSlots do
        local itemButton = _G[containerFrame:GetName() .. "Item" .. slotID]
        if itemButton then
            self:UpdateOverlay(itemButton, bagID, slotID)
        end
    end
end

-- Refresh all bag overlays
function JunkList:RefreshAllOverlays()
    for _, bagID in ipairs(IM:GetBagIDsToScan()) do
        self:RefreshBagOverlays(bagID)
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

                -- Refresh overlay (also refresh lock overlay in case it changed)
                self:UpdateOverlay(itemButton, bagID, slotID)
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
