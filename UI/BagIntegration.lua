--[[
    InventoryManager - UI/BagIntegration.lua
    Integration with default WoW bags
]]

local addonName, IM = ...
local UI = IM.UI

local BagIntegration = {}
UI.BagIntegration = BagIntegration

-- Track if we've hooked the bags
local hooksApplied = false

-- Initialize bag integration
function BagIntegration:Initialize()
    if hooksApplied then return end

    -- Hook bag frame updates
    self:HookContainerFrames()

    -- Multiple events to catch bag opening
    IM:RegisterEvent("BAG_OPEN", function(event, bagID)
        self:OnBagOpened(bagID)
    end)

    IM:RegisterEvent("BAG_CLOSED", function(event, bagID)
        self:OnBagClosed(bagID)
    end)

    -- Also register for BAG_UPDATE_DELAYED for extra reliability
    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        self:RefreshAllOverlays()
    end)

    hooksApplied = true
    IM:Debug("Bag integration initialized")
end

-- Hook container frame updates
function BagIntegration:HookContainerFrames()
    -- Hook ContainerFrame_Update to add our overlays after items are set
    if ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            self:OnContainerFrameUpdate(frame)
        end)
    end
    
    -- Hook the actual Show method on frames (more reliable than OnShow script)
    if ContainerFrameCombinedBags then
        hooksecurefunc(ContainerFrameCombinedBags, "Show", function()
            IM:Debug("[BagIntegration] ContainerFrameCombinedBags:Show() called via hooksecurefunc")
            if IM.db and IM.db.global and IM.db.global.useIMBags then
                C_Timer.After(0, function()
                    if ContainerFrameCombinedBags:IsShown() then
                        IM:Debug("[BagIntegration] Hiding ContainerFrameCombinedBags from Show hook")
                        ContainerFrameCombinedBags:Hide()
                        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Show then
                            IM.UI.BagUI:Show()
                        end
                    end
                end)
            end
        end)
    end

    -- Hook for combined bags (Blizzard's combined bag view) - modern retail
    if ContainerFrameCombinedBags then
        IM:Debug("[BagIntegration] Hooking ContainerFrameCombinedBags OnShow")
        ContainerFrameCombinedBags:HookScript("OnShow", function()
            IM:Debug("[BagIntegration] ContainerFrameCombinedBags OnShow fired, useIMBags=" .. tostring(IM.db and IM.db.global and IM.db.global.useIMBags))
            if IM.db and IM.db.global and IM.db.global.useIMBags then
                IM:Debug("[BagIntegration] Hiding Blizzard bags, showing IM bags")
                ContainerFrameCombinedBags:Hide()
                -- Show IM bags instead
                if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Show then
                    local ok, err = pcall(function() IM.UI.BagUI:Show() end)
                    if not ok then
                        IM:Debug("[BagIntegration] Error showing IM bags: " .. tostring(err))
                    end
                else
                    IM:Debug("[BagIntegration] BagUI not available!")
                end
                return
            end
            C_Timer.After(0.1, function()
                self:RefreshAllOverlays()
            end)
        end)

        if ContainerFrameCombinedBags.Update then
            hooksecurefunc(ContainerFrameCombinedBags, "Update", function(frame)
                self:OnCombinedBagUpdate(frame)
            end)
        end
    end

    -- Hook individual container frames OnShow
    local hookedCount = 0
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            hookedCount = hookedCount + 1
            frame:HookScript("OnShow", function(self)
                IM:Debug("[BagIntegration] ContainerFrame" .. i .. " OnShow fired")
                if IM.db and IM.db.global and IM.db.global.useIMBags then
                    self:Hide()
                    -- Show IM bags instead
                    if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Show then
                        IM.UI.BagUI:Show()
                    end
                    return
                end
                C_Timer.After(0.1, function()
                    BagIntegration:RefreshAllOverlays()
                end)
            end)
        end
    end
    IM:Debug("[BagIntegration] Hooked " .. hookedCount .. " individual ContainerFrames")
end

-- Called when a container frame updates
function BagIntegration:OnContainerFrameUpdate(frame)
    if not frame then return end
    if IM.db and IM.db.global and IM.db.global.useIMBags then return end

    local bagID = frame:GetID()
    if not bagID then return end

    -- Refresh overlays for this bag
    if IM.modules.ItemLock then
        IM.modules.ItemLock:RefreshBagOverlays(bagID)
    end
    if IM.modules.JunkList then
        IM.modules.JunkList:RefreshBagOverlays(bagID)
    end
end

-- Called when combined bag view updates
function BagIntegration:OnCombinedBagUpdate(frame)
    if IM.db and IM.db.global and IM.db.global.useIMBags then return end
    -- Refresh all overlays
    if IM.modules.ItemLock then
        IM.modules.ItemLock:RefreshAllOverlays()
    end
    if IM.modules.JunkList then
        IM.modules.JunkList:RefreshAllOverlays()
    end
end

-- Called when a bag is opened
function BagIntegration:OnBagOpened(bagID)
    IM:Debug("[BagIntegration] BAG_OPEN event for bagID=" .. tostring(bagID))
    if IM.db and IM.db.global and IM.db.global.useIMBags then
        IM:Debug("[BagIntegration] useIMBags=true, hiding Blizzard and showing IM")
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
            ContainerFrameCombinedBags:Hide()
        end
        -- Show IM bags instead
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Show then
            IM.UI.BagUI:Show()
        end
        return
    end
    -- Refresh overlays for this bag
    C_Timer.After(0.1, function()
        if IM.modules.ItemLock then
            IM.modules.ItemLock:RefreshBagOverlays(bagID)
        end
        if IM.modules.JunkList then
            IM.modules.JunkList:RefreshBagOverlays(bagID)
        end
    end)
end

-- Called when a bag is closed
function BagIntegration:OnBagClosed(bagID)
    -- Nothing special needed when bags close
end

-- Get item button from a container frame
function BagIntegration:GetItemButton(bagID, slotID)
    -- Handle special bags (reagent bag, bank bags, etc.)
    local containerFrame
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag and bagID == Enum.BagIndex.ReagentBag then
        -- Reagent bag has special container frame index
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

-- Aggressive bag replacement using OnUpdate polling
local _pollingFrame = nil
local _lastPollTime = 0
local POLL_INTERVAL = 0.1

local function _StartPolling()
    if _pollingFrame then return end
    
    _pollingFrame = CreateFrame("Frame")
    _pollingFrame:SetScript("OnUpdate", function(self, elapsed)
        _lastPollTime = _lastPollTime + elapsed
        if _lastPollTime < POLL_INTERVAL then return end
        _lastPollTime = 0
        
        -- Only check if IM bags are enabled
        if not (IM.db and IM.db.global and IM.db.global.useIMBags) then return end
        
        -- Check if any Blizzard bag frames are showing
        local blizzardBagsShowing = false
        
        -- Check combined bags frame
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
            blizzardBagsShowing = true
            IM:Debug("[BagIntegration] Polling: ContainerFrameCombinedBags is showing, hiding")
            ContainerFrameCombinedBags:Hide()
        end
        
        -- Check individual container frames
        for i = 1, 13 do
            local frame = _G["ContainerFrame" .. i]
            if frame and frame:IsShown() then
                blizzardBagsShowing = true
                IM:Debug("[BagIntegration] Polling: ContainerFrame" .. i .. " is showing, hiding")
                frame:Hide()
            end
        end
        
        -- Also check the backpack button frame (different in some WoW versions)
        if BagItemAutoSortButton and BagItemAutoSortButton:IsShown() then
            -- This is just an indicator that bags might be open
        end
        
        -- Check if the main backpack is visible via API
        local backpackIsOpen = IsBagOpen and IsBagOpen(0)
        if backpackIsOpen and not blizzardBagsShowing then
            IM:Debug("[BagIntegration] Polling: IsBagOpen(0) is true but no frames detected as showing!")
            -- Force close all bags through Blizzard API
            if CloseAllBags then
                -- Use original if we captured it
                local BagHooks = IM:GetModule("BagHooks")
                if BagHooks and BagHooks:GetOriginal("CloseAllBags") then
                    BagHooks:GetOriginal("CloseAllBags")()
                end
            end
            blizzardBagsShowing = true
        end
        
        -- If Blizzard bags were showing, show IM bags instead (unless user just closed them)
        if blizzardBagsShowing and IM.UI and IM.UI.BagUI and IM.UI.BagUI.Show then
            if not IM.UI.BagUI:IsShown() then
                -- Check if user intentionally closed the bags recently
                if IM.UI.BagUI.WasIntentionallyHidden and IM.UI.BagUI:WasIntentionallyHidden() then
                    IM:Debug("[BagIntegration] Polling: Skipping show - was intentionally hidden")
                else
                    IM:Debug("[BagIntegration] Polling: Showing IM BagUI")
                    IM.UI.BagUI:Show()
                end
            end
        end
    end)
    
    IM:Debug("[BagIntegration] Polling started")
end

-- Initialize when addon loads
IM:RegisterEvent("PLAYER_LOGIN", function()
    IM:Debug("[BagIntegration] PLAYER_LOGIN - Initializing")
    IM:Debug("[BagIntegration] ContainerFrameCombinedBags exists: " .. tostring(ContainerFrameCombinedBags ~= nil))
    BagIntegration:Initialize()
    
    -- Start polling for bag visibility
    C_Timer.After(1, function()
        _StartPolling()
    end)
end)
