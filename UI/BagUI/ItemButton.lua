--[[
    InventoryManager - UI/BagUI/ItemButton.lua
    Secure item button pool using ContainerFrameItemButtonTemplate.
    Avoids taint by using Blizzard's secure button template.
]]

local addonName, IM = ...
local UI = IM.UI

-- Ensure BagUI namespace exists
UI.BagUI = UI.BagUI or {}
local BagUI = UI.BagUI

BagUI.ItemButton = {}
local ItemButton = BagUI.ItemButton

-- Button pool
local _buttonPool = {}
local _activeButtons = {}
local _nextButtonIndex = 1

-- Parent frame for buttons (must be set during init)
local _parentFrame = nil

-- ============================================================================
-- POOL SIZE CALCULATION
-- ============================================================================

-- Calculate pool size based on actual bag slots
local function CalculatePoolSize()
    local totalSlots = 0
    
    -- Regular bags (backpack + 4 bags)
    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        totalSlots = totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
    end
    
    -- Reagent bag (if it exists)
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
        local reagentSlots = C_Container.GetContainerNumSlots(Enum.BagIndex.ReagentBag)
        if reagentSlots then
            totalSlots = totalSlots + reagentSlots
        end
    end
    
    -- Buffer for future expansions (2x with 200 minimum)
    return math.max(totalSlots * 2, 200)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function ItemButton:Initialize(parentFrame)
    if #_buttonPool > 0 then return end  -- Already initialized
    
    _parentFrame = parentFrame
    
    -- Calculate pool size dynamically
    local poolSize = CalculatePoolSize()
    
    -- Pre-create button pool
    for i = 1, poolSize do
        local button = self:CreateButton(i)
        table.insert(_buttonPool, button)
    end
    
    IM:Debug("[BagUI.ItemButton] Initialized pool with " .. poolSize .. " buttons")
end

-- ============================================================================
-- BUTTON CREATION (SECURE)
-- ============================================================================

function ItemButton:CreateButton(index)
    -- CRITICAL: Use ContainerFrameItemButtonTemplate for secure handling
    -- This template provides built-in support for right-click, equip, use, etc.
    local button = CreateFrame("ItemButton", "InventoryManagerBagItem" .. index, _parentFrame, "ContainerFrameItemButtonTemplate")
    
    button:SetSize(UI.layout.iconSize + 17, UI.layout.iconSize + 17)  -- Standard item button size (37x37)
    button:Hide()
    
    -- Store reference to our bag/slot (for overlay system)
    button._imBagID = nil
    button._imSlotID = nil
    button._imIndex = index
    button._imTooltipSuppressed = false
    
    -- Hook into Blizzard's secure click handling (no taint)
    -- ContainerFrameItemButtonTemplate handles:
    -- - Right-click to use/equip
    -- - Shift-click for linking
    -- - Alt-click for our lock system
    -- - Ctrl-Alt-click for our junk system
    
    -- Add our custom click handlers (non-secure, but execute before Blizzard's)
    button:HookScript("OnClick", function(self, mouseButton)
        if not self._imBagID or not self._imSlotID then return end
        
        -- Alt+Click: Toggle lock
        if IsAltKeyDown() and not IsControlKeyDown() then
            if IM.modules.ItemLock then
                IM.modules.ItemLock:ToggleItemLock(self._imBagID, self._imSlotID)
            end
            return  -- Don't propagate
        end
        
        -- Ctrl+Alt+Click: Toggle junk
        if IsControlKeyDown() and IsAltKeyDown() then
            if IM.modules.JunkList then
                IM.modules.JunkList:ToggleJunk(self._imBagID, self._imSlotID)
            end
            return  -- Don't propagate
        end
        
        -- All other clicks (including right-click) are handled by Blizzard's secure code
    end)
    
    -- Suppress tooltip briefly after button is shown to prevent auto-tooltips on bag open
    -- Use C_Timer to hide tooltip AFTER Blizzard's OnEnter runs
    button:HookScript("OnEnter", function(self)
        if self._imTooltipSuppressed then
            C_Timer.After(0.01, function()
                if GameTooltip:IsOwned(self) then
                    GameTooltip:Hide()
                    IM:Debug("[ItemButton] Suppressed tooltip for button " .. (self._imIndex or "?"))
                end
            end)
        end
    end)
    
    -- Clear highlight on leave
    button:HookScript("OnLeave", function(self)
        self._imTooltipSuppressed = false  -- Allow tooltips on next enter
        GameTooltip:Hide()
    end)
    
    -- Create overlay frame for our indicators (lock, sell, mail, etc.)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)
    button._imOverlay = overlay
    
    return button
end

-- ============================================================================
-- BUTTON MANAGEMENT
-- ============================================================================

function ItemButton:Acquire()
    if _nextButtonIndex > #_buttonPool then
        IM:Debug("[BagUI.ItemButton] WARNING: Button pool exhausted! Need more buttons.")
        IM:Debug("[BagUI.ItemButton] Current pool size: " .. #_buttonPool .. ", next index: " .. _nextButtonIndex)
        return nil
    end
    
    local button = _buttonPool[_nextButtonIndex]
    _nextButtonIndex = _nextButtonIndex + 1
    table.insert(_activeButtons, button)
    
    return button
end

function ItemButton:ReleaseAll()
    -- Hide and clear all active buttons
    for _, button in ipairs(_activeButtons) do
        self:Clear(button)
        button:Hide()
        button:ClearAllPoints()
    end
    
    -- Reset tracking
    _activeButtons = {}
    _nextButtonIndex = 1
end

function ItemButton:Clear(button)
    if not button then return end
    
    button._imBagID = nil
    button._imSlotID = nil
    
    -- Clear Blizzard's item data (required for ContainerFrameItemButtonTemplate)
    button:SetID(0)
    if button:GetParent() then
        button:GetParent():SetID(0)
    end
    
    -- Clear overlay
    if button._imOverlay then
        for _, child in ipairs({button._imOverlay:GetChildren()}) do
            child:Hide()
        end
    end
end

-- ============================================================================
-- BUTTON SETUP
-- ============================================================================

function ItemButton:SetItem(button, bagID, slotID)
    if not button then return end
    
    -- Store our reference
    button._imBagID = bagID
    button._imSlotID = slotID
    
    -- CRITICAL: Set bag and slot IDs for Blizzard's secure handling
    -- The parent frame's ID must be the bagID
    -- The button's ID must be the slotID
    -- This allows ContainerFrameItemButtonTemplate to work properly
    
    -- Set button slot ID
    button:SetID(slotID)
    
    -- Create or update parent bag frame
    -- ContainerFrameItemButtonTemplate expects parent:GetID() to return bagID
    local parent = button:GetParent()
    
    -- Check if parent is already a virtual bag frame
    if parent._imBagFrame and parent:GetID() == bagID then
        -- Already correctly parented to the right bag frame, nothing to do
    elseif parent._imBagFrame and parent:GetID() ~= bagID then
        -- Parent is a bag frame but wrong bagID, need to find/create correct one
        local scrollContent = parent:GetParent()
        if scrollContent and scrollContent._imBagFrames then
            local bagFrame = scrollContent._imBagFrames[bagID]
            if bagFrame then
                button:SetParent(bagFrame)
            end
        end
    else
        -- Parent is not a bag frame, need to create bag frame structure
        local scrollContent = parent
        scrollContent._imBagFrames = scrollContent._imBagFrames or {}
        
        local bagFrame = scrollContent._imBagFrames[bagID]
        if not bagFrame then
            -- Create tiny virtual frame just for Blizzard security (bagID lookup)
            bagFrame = CreateFrame("Frame", "InventoryManagerBag" .. bagID, scrollContent)
            bagFrame:SetID(bagID)
            bagFrame._imBagFrame = true
            bagFrame:SetSize(1, 1)
            bagFrame:SetPoint("TOPLEFT")
            
            scrollContent._imBagFrames[bagID] = bagFrame
        end
        
        -- Reparent button
        button:SetParent(bagFrame)
    end
    
    -- Update Blizzard's button display
    -- This calls into ContainerFrameItemButtonTemplate's secure code
    if button.UpdateItemContextMatching then
        button:UpdateItemContextMatching()
    end
    
    -- CRITICAL: Actually set the item texture and info
    -- ContainerFrameItemButtonTemplate needs this data to display properly
    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
    if itemInfo then
        -- Set icon texture
        local texture = itemInfo.iconFileID
        if button.icon then
            button.icon:SetTexture(texture)
            button.icon:Show()
        end
        
        -- Set count
        local count = itemInfo.stackCount
        if button.Count then
            if count and count > 1 then
                button.Count:SetText(count)
                button.Count:Show()
            else
                button.Count:Hide()
            end
        end
        
        -- Set quality border
        local quality = itemInfo.quality
        if quality and quality > 1 then  -- Show border for uncommon+
            if button.IconBorder then
                local color = ITEM_QUALITY_COLORS[quality]
                if color then
                    button.IconBorder:SetVertexColor(color.r, color.g, color.b)
                    button.IconBorder:Show()
                else
                    button.IconBorder:Hide()
                end
            end
        else
            if button.IconBorder then
                button.IconBorder:Hide()
            end
        end
        
        -- Show button
        button:Show()
        
        -- Brief tooltip suppression to prevent auto-tooltip on bag open (0.1s)
        button._imTooltipSuppressed = true
        C_Timer.After(0.1, function()
            if button then
                button._imTooltipSuppressed = false
            end
        end)
    else
        -- Empty slot
        button:Hide()
    end
    
    -- Update our overlay (lock, sell, mail indicators)
    self:UpdateOverlay(button)
end

-- ============================================================================
-- OVERLAY SYSTEM
-- ============================================================================

function ItemButton:UpdateOverlay(button)
    if not button or not button._imBagID or not button._imSlotID then return end
    
    -- Use existing overlay factory
    if IM.UI.OverlayFactory then
        IM.UI.OverlayFactory:Update(button, button._imBagID, button._imSlotID)
    end
end

-- ============================================================================
-- POSITION BUTTON
-- ============================================================================

function ItemButton:SetPosition(button, x, y)
    if not button then return end
    
    button:ClearAllPoints()
    -- Position relative to the actual scrollContent (buttons are parented to virtual bag frames which are children of scrollContent)
    local scrollContent = _parentFrame and _parentFrame.scrollContent
    if scrollContent then
        button:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", x, y)
    else
        button:SetPoint("TOPLEFT", x, y)
    end
    button:Show()
end

-- ============================================================================
-- UTILITIES
-- ============================================================================

function ItemButton:GetButton(bagID, slotID)
    -- Find active button by bag/slot
    for _, button in ipairs(_activeButtons) do
        if button._imBagID == bagID and button._imSlotID == slotID then
            return button
        end
    end
    return nil
end

function ItemButton:GetActiveCount()
    return #_activeButtons
end
