--[[
    InventoryManager - UI/BagIntegration.lua
    Integration with Blizzard default bags for overlay support.
    Custom IM Bag UI is handled separately in UI/BagUI/
]]

local addonName, IM = ...
local UI = IM.UI

local BagIntegration = {}
UI.BagIntegration = BagIntegration

local _hooksApplied = false

-- ============================================================================
-- BLIZZARD DEFAULT BAGS
-- ============================================================================

function BagIntegration:Initialize()
    if _hooksApplied then return end

    self:HookBlizzardBags()

    -- Universal events for overlay refresh
    local integration = self
    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        integration:RefreshAllOverlays()
    end)

    _hooksApplied = true
    IM:Debug("[BagIntegration] Initialized for Blizzard bags")
end

function BagIntegration:HookBlizzardBags()
    local integration = self

    -- Hook ContainerFrame_Update to add our overlays after items are set
    if ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            integration:OnContainerFrameUpdate(frame)
        end)
    end

    -- Hook for combined bags (Blizzard's combined bag view)
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function()
            C_Timer.After(0.1, function()
                integration:RefreshAllOverlays()
            end)
        end)

        if ContainerFrameCombinedBags.Update then
            hooksecurefunc(ContainerFrameCombinedBags, "Update", function()
                integration:RefreshAllOverlays()
            end)
        end
    end

    -- Hook individual container frames OnShow
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", function()
                C_Timer.After(0.1, function()
                    integration:RefreshAllOverlays()
                end)
            end)
        end
    end

    IM:Debug("[BagIntegration] Hooked Blizzard bags")
end

function BagIntegration:OnContainerFrameUpdate(frame)
    if not frame then return end

    local bagID = frame:GetID()
    if not bagID then return end

    -- Refresh overlays for this bag after a frame
    C_Timer.After(0, function()
        if IM.modules.ItemLock then
            IM.modules.ItemLock:RefreshBagOverlays(bagID)
        end
        if IM.modules.JunkList then
            IM.modules.JunkList:RefreshBagOverlays(bagID)
        end
    end)
end

-- Get item button from a container frame
function BagIntegration:GetItemButton(bagID, slotID)
    local containerFrame
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag and bagID == Enum.BagIndex.ReagentBag then
        containerFrame = _G["ContainerFrame" .. (NUM_BAG_SLOTS + 2)]
    else
        containerFrame = _G["ContainerFrame" .. (bagID + 1)]
    end
    if not containerFrame then return nil end

    local buttonName = containerFrame:GetName() .. "Item" .. slotID
    return _G[buttonName]
end

-- Force refresh all bag overlays
function BagIntegration:RefreshAllOverlays()
    if IM.modules.ItemLock then
        IM.modules.ItemLock:RefreshAllOverlays()
    end
    if IM.modules.JunkList then
        IM.modules.JunkList:RefreshAllOverlays()
    end
end

-- ============================================================================
-- IM BAG BUTTON (Cheddar Icon on Blizzard Bags)
-- ============================================================================

local _imBagButton = nil

-- Create the IM button that appears on bag frames
function BagIntegration:CreateIMButton()
    if _imBagButton then return _imBagButton end

    local button = CreateFrame("Button", "InventoryManagerBagButton", UIParent)
    button:SetSize(60, 60)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(100)
    button:Hide()

    -- Icon texture (custom cheddar icon)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture("Interface\\AddOns\\InventoryManager\\Textures\\cheddar-icon")

    -- Click handler
    button:SetScript("OnClick", function(self, mouseButton)
        if IsShiftKeyDown() then
            -- Shift+Click: Open Settings
            if IM.UI and IM.UI.ToggleConfig then
                IM.UI:ToggleConfig()
            else
                IM:Print("Settings not available")
            end
        else
            -- Regular Click: Open Dashboard/Net Worth
            if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Toggle then
                IM.UI.Dashboard:Toggle()
            else
                IM:Print("Dashboard not available")
            end
        end
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cffffb000InventoryManager|r", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffffffClick|r to open Tracker Dashboard", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffShift+Click|r to open Settings", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    _imBagButton = button
    return button
end

-- Position the IM button relative to a bag frame
function BagIntegration:PositionIMButton(bagFrame)
    if not _imBagButton then
        self:CreateIMButton()
    end

    if not bagFrame or not bagFrame:IsVisible() then
        _imBagButton:Hide()
        return
    end

    -- Position in top-right corner of bag frame
    _imBagButton:ClearAllPoints()
    _imBagButton:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -35, 10)
    _imBagButton:SetParent(bagFrame)
    _imBagButton:SetFrameStrata("HIGH")
    _imBagButton:Show()
end

-- Show/hide IM button based on bag visibility
function BagIntegration:UpdateIMButtonVisibility()
    if not _imBagButton then
        self:CreateIMButton()
    end

    -- Find the visible Blizzard bag frame
    local bagFrame = ContainerFrameCombinedBags or _G.ContainerFrame1

    if bagFrame and bagFrame:IsVisible() then
        self:PositionIMButton(bagFrame)
    else
        _imBagButton:Hide()
    end
end

-- Hook bag frames to show/hide IM button
function BagIntegration:HookIMButton()
    local integration = self

    -- Create the button
    self:CreateIMButton()

    -- Hook bag open/close events
    IM:RegisterEvent("BAG_OPEN", function()
        C_Timer.After(0.1, function()
            integration:UpdateIMButtonVisibility()
        end)
    end)

    IM:RegisterEvent("BAG_CLOSED", function()
        C_Timer.After(0.1, function()
            integration:UpdateIMButtonVisibility()
        end)
    end)

    -- Also check periodically while bags might be open
    C_Timer.NewTicker(0.5, function()
        if _imBagButton and _imBagButton:IsShown() then
            -- Button is showing, verify parent is still visible
            local parent = _imBagButton:GetParent()
            if parent and not parent:IsVisible() then
                _imBagButton:Hide()
            end
        end
    end)

    -- Hook Blizzard bags
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function()
            C_Timer.After(0.1, function()
                integration:PositionIMButton(ContainerFrameCombinedBags)
            end)
        end)
        ContainerFrameCombinedBags:HookScript("OnHide", function()
            if _imBagButton then _imBagButton:Hide() end
        end)
    end

    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", function()
                C_Timer.After(0.1, function()
                    integration:UpdateIMButtonVisibility()
                end)
            end)
        end
    end

    IM:Debug("[BagIntegration] IM button hooks applied")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Initialize when addon loads
IM:RegisterEvent("PLAYER_LOGIN", function()
    IM:Debug("[BagIntegration] PLAYER_LOGIN - Initializing")
    BagIntegration:Initialize()

    -- Initialize IM button after a short delay
    C_Timer.After(1, function()
        BagIntegration:HookIMButton()
    end)
end)
