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

-- Debug flag for button structure dump
local _debugDumped = false

-- ============================================================================
-- BUTTON CREATION (SECURE)
-- ============================================================================

function ItemButton:CreateButton(index)
    -- CRITICAL: Use ContainerFrameItemButtonTemplate for secure handling
    -- This template provides built-in support for right-click, equip, use, etc.
    local button = CreateFrame("ItemButton", "InventoryManagerBagItem" .. index, _parentFrame, "ContainerFrameItemButtonTemplate")

    -- Scale button to match desired icon size (scales all child textures including border)
    local iconSize = BagUI:GetSettings().iconSize or UI.layout.iconSize or 20
    local scale = (iconSize + 17) / 37  -- 37 = default ContainerFrameItemButtonTemplate size
    button:SetScale(scale)
    button:Hide()
    
    -- Hide the blue Battlepay glow texture
    if button.BattlepayItemTexture then
        button.BattlepayItemTexture:Hide()
        button.BattlepayItemTexture:SetAlpha(0)
    end
    
    -- Store reference to our bag/slot (for overlay system)
    button._imBagID = nil
    button._imSlotID = nil
    button._imIndex = index
    
    -- Create overlay frame for our indicators (lock, sell, mail, etc.)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)
    button._imOverlay = overlay

    -- NOTE: Alt+Click (lock) and Ctrl+Alt+Click (junk) are handled globally by
    -- ItemLock.lua and JunkList.lua via hooksecurefunc on ContainerFrameItemButtonMixin.OnClick
    -- Since our buttons inherit from ContainerFrameItemButtonTemplate, they're already covered.
    -- No duplicate hook needed here.

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

    -- Debug dump button structure (first item only, when debug enabled)
    if not _debugDumped and #_buttonPool > 0 and IM.db and IM.db.global and IM.db.global.debugMode then
        _debugDumped = true
        local btn = _buttonPool[1]
        IM:Debug("[ItemButton] === BUTTON STRUCTURE ===")
        for key, val in pairs(btn) do
            if type(val) == "table" and type(val.GetObjectType) == "function" then
                IM:Debug("[ItemButton]   KEY:", key, "=", val:GetObjectType())
            end
        end
        for i, region in ipairs({btn:GetRegions()}) do
            IM:Debug("[ItemButton]   REGION", i, ":", region:GetObjectType(), "-", region:GetName() or "(unnamed)")
        end
        IM:Debug("[ItemButton] === END ===")
    end

    -- Store our reference
    button._imBagID = bagID
    button._imSlotID = slotID
    
    -- CRITICAL: Set bag and slot IDs for Blizzard's secure handling
    -- The parent frame's ID must be the bagID
    -- The button's ID must be the slotID
    -- This allows ContainerFrameItemButtonTemplate to work properly
    
    -- Get or create virtual bag frame for this bagID
    -- ContainerFrameItemButtonTemplate requires parent:GetID() == bagID
    local scrollContent = _parentFrame  -- This is the scrollContent from Initialize
    scrollContent._imBagFrames = scrollContent._imBagFrames or {}
    
    local bagFrame = scrollContent._imBagFrames[bagID]
    if not bagFrame then
        -- Create virtual bag frame (tiny, just for ID lookup)
        bagFrame = CreateFrame("Frame", nil, scrollContent)
        bagFrame:SetID(bagID)
        bagFrame:SetSize(1, 1)
        bagFrame:SetPoint("TOPLEFT")
        bagFrame:Show()
        scrollContent._imBagFrames[bagID] = bagFrame
        IM:Debug("[ItemButton] Created virtual bagFrame for bagID " .. bagID)
    end
    
    -- Reparent button to correct bag frame
    if button:GetParent() ~= bagFrame then
        button:SetParent(bagFrame)
        IM:Debug(string.format("[ItemButton] Reparented button to bagFrame %d (from %s)", 
            bagID, button:GetParent() and button:GetParent():GetID() or "nil"))
    end
    
    -- CRITICAL: Set the IDs AFTER reparenting
    -- This ensures ContainerFrameItemButtonTemplate can find the right bag/slot
    button:SetID(slotID)
    bagFrame:SetID(bagID)  -- Re-set to make sure it's current
    
    IM:Debug(string.format("[ItemButton:SetItem] bag=%d slot=%d, parent:GetID()=%d, button:GetID()=%d", 
        bagID, slotID, button:GetParent():GetID(), button:GetID()))
    
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
                button.Count:ClearAllPoints()
                button.Count:SetPoint(
                    "TOPRIGHT",
                    button,
                    "TOPRIGHT",
                    UI.layout.itemCountOffsetX,
                    UI.layout.itemCountOffsetY
                )
                button.Count:SetText(count)
                button.Count:Show()
            else
                button.Count:Hide()
            end
        end
        
        -- Set item level text (for equippable gear)
        if not button._imItemLevel then
            button._imItemLevel = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button._imItemLevel:SetPoint(
                "BOTTOMRIGHT",
                button,
                "BOTTOMRIGHT",
                UI.layout.itemLevelOffsetX,
                UI.layout.itemLevelOffsetY
            )
            button._imItemLevel:SetTextColor(unpack(UI.colors.itemLevel))
            button._imItemLevel:SetFont(UI.fonts.default, UI.fontSizes.small, "OUTLINE")
        end
        
        -- Show ilvl for equippable items
        local itemLink = itemInfo.hyperlink
        local effectiveILvl = nil

        -- Prefer instance-based ilvl from bag/slot (does not require hovering)
        if ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
            local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
            if itemLoc and itemLoc.IsValid and itemLoc:IsValid() then
                effectiveILvl = C_Item.GetCurrentItemLevel(itemLoc)
            end
        end

        -- Fallback to link-based (less reliable for some scaling items)
        if (not effectiveILvl or effectiveILvl <= 0) and itemLink and GetDetailedItemLevelInfo then
            effectiveILvl = GetDetailedItemLevelInfo(itemLink)
        end

        if itemLink then
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)

            -- Show ilvl if item is equippable and has meaningful ilvl
            if effectiveILvl and effectiveILvl > 1 and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
                button._imItemLevel:SetText(effectiveILvl)
                button._imItemLevel:Show()
            else
                button._imItemLevel:Hide()
            end
        else
            button._imItemLevel:Hide()
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
    -- Position relative to the scrollContent (buttons are parented to virtual bag frames which are children of scrollContent)
    -- _parentFrame IS the scrollContent
    if _parentFrame then
        button:SetPoint("TOPLEFT", _parentFrame, "TOPLEFT", x, y)
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

-- ============================================================================
-- DYNAMIC RESIZING
-- ============================================================================

-- Default Blizzard button size (ContainerFrameItemButtonTemplate = 37x37)
local DEFAULT_BUTTON_SIZE = 37

function ItemButton:ResizeButton(button, newSize)
    if not button then return end
    -- Scale proportionally so all child textures (including border) scale too
    local scale = newSize / DEFAULT_BUTTON_SIZE
    button:SetScale(scale)
end

function ItemButton:ResizeAll()
    -- Scale all buttons in pool to match current icon size setting
    local iconSize = BagUI:GetSettings().iconSize or UI.layout.iconSize or 20
    local buttonSize = iconSize + 17
    local scale = buttonSize / DEFAULT_BUTTON_SIZE

    for _, button in ipairs(_buttonPool) do
        button:SetScale(scale)
    end

    IM:Debug(string.format("[BagUI.ItemButton] Scaled %d buttons to %.2fx (target: %dpx)", #_buttonPool, scale, buttonSize))
end
