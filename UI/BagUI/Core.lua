--[[
    InventoryManager - UI/BagUI/Core.lua
    Main bag UI frame with header, content area, and footer.
    Uses DRY components from UI/Core.lua
]]

local addonName, IM = ...
local UI = IM.UI

UI.BagUI = UI.BagUI or {}
local BagUI = UI.BagUI

-- Ensure all submodules are accessible
BagUI.ItemButton = BagUI.ItemButton or {}
BagUI.MasonryLayout = BagUI.MasonryLayout or {}
BagUI.CategoryView = BagUI.CategoryView or {}

-- Frame references
local _bagFrame = nil
local _isVisible = false

-- ============================================================================
-- MAIN BAG FRAME
-- ============================================================================

function BagUI:Create()
    if _bagFrame then return _bagFrame end

    -- Calculate optimal width based on settings
    local settings = self:GetSettings()
    local columns = settings.columns or 2
    local itemsPerRow = settings.itemsPerRow or 6
    local height = settings.height or 500
    
    -- Calculate required width
    local itemSize = 37  -- iconSize (20) + border (17)
    local paddingSmall = IM.UI.layout.paddingSmall or 4
    local categoryPadding = IM.UI.layout.cardSpacing or 10
    local columnGap = categoryPadding * 2  -- 20px between columns
    
    -- Width = (itemSize * itemsPerRow) + (gaps between items) + (category padding) per column + gaps between columns
    local itemRowWidth = (itemSize * itemsPerRow) + (paddingSmall * (itemsPerRow - 1)) + (paddingSmall * 2)
    local totalWidth = (itemRowWidth * columns) + (columnGap * (columns - 1)) + (categoryPadding * 2) + 40
    
    -- Clamp to reasonable bounds
    totalWidth = math.max(totalWidth, 480)  -- Minimum
    totalWidth = math.min(totalWidth, 1200)  -- Maximum
    
    IM:Debug(string.format("[BagUI] Calculated width: %d (cols=%d, items/row=%d)", totalWidth, columns, itemsPerRow))

    -- Main frame using DRY CreatePanel (calculated width and height)
    local frame = UI:CreatePanel("InventoryManagerBagFrame", UIParent, totalWidth, height)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:Hide()
    
    -- Restore saved position or default to center
    if settings.position then
        frame:ClearAllPoints()
        frame:SetPoint(settings.position.point or "CENTER", 
                      UIParent, 
                      settings.position.relativePoint or "CENTER", 
                      settings.position.x or 0, 
                      settings.position.y or 0)
    else
        frame:SetPoint("CENTER")
    end
    
    -- Save position when moved
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        BagUI:SavePosition()
    end)

    -- Make it resizable
    frame:SetResizable(true)
    frame:SetResizeBounds(480, 400, 1200, 900)

    -- Header using DRY CreateHeader
    local header = UI:CreateHeader(frame, "InventoryManager Bags")
    
    -- Gear icon button (settings)
    local gearBtn = CreateFrame("Button", nil, header)
    gearBtn:SetSize(UI.layout.iconSize, UI.layout.iconSize)
    gearBtn:SetPoint("RIGHT", header.closeButton, "LEFT", -UI.layout.paddingSmall, 0)
    gearBtn:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    gearBtn:SetHighlightTexture("Interface\\Icons\\Trade_Engineering", "ADD")
    gearBtn:GetNormalTexture():SetTexCoord(0.1, 0.9, 0.1, 0.9)
    gearBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.ToggleConfig then
            IM.UI:ToggleConfig()
        end
    end)
    gearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Settings")
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    header.gearButton = gearBtn

    -- Content container (for categories and items)
    local contentContainer = CreateFrame("Frame", nil, frame)
    contentContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    contentContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, UI.layout.bottomBarHeight + UI.layout.padding)
    frame.contentContainer = contentContainer

    -- Scroll frame for categories using DRY CreateScrollFrame
    local scrollFrame = UI:CreateScrollFrame(contentContainer, nil, nil, true)
    frame.scrollFrame = scrollFrame
    frame.scrollContent = scrollFrame.content

    -- Footer bar (gold display)
    local footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    footer:SetHeight(UI.layout.bottomBarHeight)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    footer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    footer:SetBackdropColor(unpack(UI.colors.headerBar))
    footer:SetBackdropBorderColor(unpack(UI.colors.border))
    frame.footer = footer

    -- Gold display (clickable to open dashboard)
    local goldText = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldText:SetPoint("LEFT", UI.layout.padding, 0)
    goldText:SetTextColor(unpack(UI.colors.accent))
    footer.goldText = goldText

    -- Make gold clickable
    footer:EnableMouse(true)
    footer:SetScript("OnMouseUp", function(self, button)
        if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Toggle then
            IM.UI.Dashboard:Toggle()
        end
    end)
    footer:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Click to open Tracker Dashboard")
        GameTooltip:Show()
    end)
    footer:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Bag space display
    local bagSpaceText = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bagSpaceText:SetPoint("RIGHT", -UI.layout.padding, 0)
    bagSpaceText:SetTextColor(0.7, 0.7, 0.7)
    footer.bagSpaceText = bagSpaceText

    -- Resize grip (bottom-right corner) - HIDDEN (resizing via edges only)
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:Hide()  -- Hide the visible grip icon
    resizeGrip:SetScript("OnMouseDown", function(self)
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function(self)
        frame:StopMovingOrSizing()
        BagUI:OnResize()
    end)
    frame.resizeGrip = resizeGrip

    -- Store reference
    _bagFrame = frame

    -- Initialize item button pool with scrollContent as parent
    if BagUI.ItemButton then
        BagUI.ItemButton:Initialize(frame.scrollContent)
    end

    -- Register events
    self:RegisterEvents()

    return frame
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

function BagUI:RegisterEvents()
    -- Bag updates
    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        if _isVisible then
            BagUI:Refresh()
        end
    end)

    -- Gold changes
    IM:RegisterEvent("PLAYER_MONEY", function()
        if _isVisible then
            BagUI:UpdateGoldDisplay()
        end
    end)

    -- Equipment changes (for equipment sets)
    IM:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
        if _isVisible then
            BagUI:Refresh()
        end
    end)
end

-- ============================================================================
-- DISPLAY METHODS
-- ============================================================================

function BagUI:Show()
    if not _bagFrame then
        self:Create()
    end

    _bagFrame:Show()
    _isVisible = true
    self:Refresh()
    
    -- Play sound
    PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
end

function BagUI:Hide()
    if _bagFrame then
        _bagFrame:Hide()
        _isVisible = false
        
        -- Play sound
        PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
    end
end

function BagUI:Toggle()
    if _isVisible then
        self:Hide()
    else
        self:Show()
    end
end

function BagUI:IsShown()
    return _isVisible and _bagFrame and _bagFrame:IsShown()
end

-- ============================================================================
-- REFRESH & UPDATE
-- ============================================================================

function BagUI:Refresh()
    if not _bagFrame or not _isVisible then return end

    self:UpdateGoldDisplay()
    self:UpdateBagSpace()
    
    -- Refresh category view
    if BagUI.CategoryView then
        BagUI.CategoryView:Refresh(_bagFrame.scrollContent)
    end
end

function BagUI:UpdateGoldDisplay()
    if not _bagFrame then return end

    local money = GetMoney()
    _bagFrame.footer.goldText:SetText(IM:FormatMoney(money))
end

function BagUI:UpdateBagSpace()
    if not _bagFrame then return end

    -- Count regular bags
    local regularTotal = 0
    local regularFree = 0
    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        if numSlots > 0 then
            regularTotal = regularTotal + numSlots
            regularFree = regularFree + (C_Container.GetContainerNumFreeSlots(bagID) or 0)
        end
    end
    local regularUsed = regularTotal - regularFree
    
    -- Count reagent bag (if available)
    local reagentTotal = 0
    local reagentFree = 0
    local reagentUsed = 0
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
        reagentTotal = C_Container.GetContainerNumSlots(Enum.BagIndex.ReagentBag) or 0
        if reagentTotal > 0 then
            reagentFree = C_Container.GetContainerNumFreeSlots(Enum.BagIndex.ReagentBag) or 0
            reagentUsed = reagentTotal - reagentFree
        end
    end
    
    -- Calculate totals
    local totalSlots = regularTotal + reagentTotal
    local totalFree = regularFree + reagentFree
    local totalUsed = regularUsed + reagentUsed
    
    -- Format text with all three counts
    local text
    if reagentTotal > 0 then
        -- Show: Bags x/x | Reagent x/x | Total x/x
        text = string.format(
            "Bags: %d/%d  |  Reagent: %d/%d  |  Total: %d/%d",
            regularUsed, regularTotal,
            reagentUsed, reagentTotal,
            totalUsed, totalSlots
        )
    else
        -- Just show regular bags if no reagent bag
        text = string.format("Bags: %d/%d", regularUsed, regularTotal)
    end
    
    -- Dynamic threshold: warn when less than 10% free or less than 5 slots
    local threshold = math.max(math.floor(totalSlots * 0.1), 5)
    local color = totalFree < threshold and UI.colors.error or UI.colors.textDim
    
    _bagFrame.footer.bagSpaceText:SetTextColor(unpack(color))
    _bagFrame.footer.bagSpaceText:SetText(text)
end

function BagUI:OnResize()
    if not _bagFrame then return end

    -- Save size and position
    self:SavePosition()

    -- Trigger category view to reflow
    if BagUI.CategoryView then
        BagUI.CategoryView:Refresh(_bagFrame.scrollContent)
    end
end

function BagUI:SavePosition()
    if not _bagFrame then return end
    
    local point, relativeTo, relativePoint, x, y = _bagFrame:GetPoint()
    
    if not IM.db.global.bagUI then
        self:InitializeSettings()
    end
    
    IM.db.global.bagUI.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
    
    IM:Debug(string.format("[BagUI] Saved position: %s %d, %d", point, x, y))
end

function BagUI:ResizeForSettings()
    if not _bagFrame then return end
    
    local settings = self:GetSettings()
    local columns = settings.columns or 2
    local itemsPerRow = settings.itemsPerRow or 6
    local height = settings.height or 500
    
    -- Calculate optimal width
    local itemSize = 37
    local paddingSmall = IM.UI.layout.paddingSmall or 4
    local categoryPadding = IM.UI.layout.cardSpacing or 10
    local columnGap = categoryPadding * 2
    
    local itemRowWidth = (itemSize * itemsPerRow) + (paddingSmall * (itemsPerRow - 1)) + (paddingSmall * 2)
    local totalWidth = (itemRowWidth * columns) + (columnGap * (columns - 1)) + (categoryPadding * 2) + 40
    
    -- Clamp to reasonable bounds
    totalWidth = math.max(totalWidth, 480)
    totalWidth = math.min(totalWidth, 1200)
    
    IM:Debug(string.format("[BagUI] Resizing to width: %d, height: %d (cols=%d, items/row=%d)", totalWidth, height, columns, itemsPerRow))
    
    _bagFrame:SetWidth(totalWidth)
    _bagFrame:SetHeight(height)
end

-- ============================================================================
-- SETTINGS
-- ============================================================================

function BagUI:GetSettings()
    return IM.db.global.bagUI or {}
end

function BagUI:InitializeSettings()
    if not IM.db.global.bagUI then
        -- Get default items per row based on bag size
        local totalSlots = 0
        
        -- Count regular bags
        for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
            totalSlots = totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
        end
        
        -- Count reagent bag (if available)
        if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
            totalSlots = totalSlots + (C_Container.GetContainerNumSlots(Enum.BagIndex.ReagentBag) or 0)
        end
        
        -- Calculate reasonable default: ~8 items per row for normal bags, scale up for larger
        local defaultItemsPerRow = math.min(math.ceil(totalSlots / 15), 12)
        defaultItemsPerRow = math.max(defaultItemsPerRow, 6)  -- Minimum 6, maximum 12
        
        IM.db.global.bagUI = {
            enabled = true,  -- Enabled by default
            columns = 2,  -- Default to 2 columns
            itemsPerRow = 6,  -- Default to 6 items per row
            viewMode = "category",  -- "category" or "subcategory"
            showItemSets = true,
            height = 500,  -- Default height
            position = {
                point = "BOTTOMRIGHT",
                relativePoint = "BOTTOMRIGHT",
                x = -120,
                y = 100,
            },
            scale = 1.0,
        }
    end
end

-- ============================================================================
-- BAG TOGGLE INTEGRATION
-- ============================================================================

function BagUI:HookBagToggle()
    local otherAddon = self:DetectOtherBagAddon()
    
    if otherAddon then
        IM:Debug("[BagUI] Other bag addon detected: " .. otherAddon .. ", hooking with priority override")
        
        -- Delay our hooks slightly so they run AFTER the other addon's hooks
        C_Timer.After(0.5, function()
            self:HookBagToggleWithPriority(otherAddon)
        end)
    else
        IM:Debug("[BagUI] No other bag addon detected, using normal hooks")
        self:HookBagToggleNormal()
    end
end

function BagUI:HookBagToggleNormal()
    -- Standard hooks when no other bag addon is present
    hooksecurefunc("ToggleAllBags", function()
        if self:IsEnabled() then
            -- Close Blizzard bags IMMEDIATELY (no timer delay)
            -- Regular bags
            for i = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                local frame = _G["ContainerFrame"..(i+1)]
                if frame and frame:IsShown() then
                    frame:Hide()
                end
            end
            
            -- Combined bags
            if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                ContainerFrameCombinedBags:Hide()
            end
            
            -- Reagent bag
            if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
                local reagentFrame = _G["ContainerFrame"..(NUM_BAG_SLOTS + 2)]
                if reagentFrame and reagentFrame:IsShown() then
                    reagentFrame:Hide()
                end
            end
            
            -- Toggle our UI
            self:Toggle()
        end
    end)
    
    IM:Debug("[BagUI] Normal bag toggle hooks applied")
end

function BagUI:HookBagToggleWithPriority(otherAddon)
    -- Aggressive hooks that take priority over other bag addons
    hooksecurefunc("ToggleAllBags", function()
        if not self:IsEnabled() then return end
        
        -- Use a slightly delayed close to override other addons
        C_Timer.After(0.05, function()
            -- Close regular Blizzard bags
            for i = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                local frame = _G["ContainerFrame"..(i+1)]
                if frame and frame:IsShown() then
                    frame:Hide()
                end
            end
            
            -- Close combined bags
            if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                ContainerFrameCombinedBags:Hide()
            end
            
            -- Close reagent bag
            if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
                local reagentFrame = _G["ContainerFrame"..(NUM_BAG_SLOTS + 2)]
                if reagentFrame and reagentFrame:IsShown() then
                    reagentFrame:Hide()
                end
            end
            
            -- Close BetterBags
            if otherAddon == "BetterBags" then
                if _G.BetterBags then
                    -- Try to close BetterBags frames
                    if _G.BetterBagsBagBackpack and _G.BetterBagsBagBackpack:IsShown() then
                        _G.BetterBagsBagBackpack:Hide()
                    end
                    if _G.BetterBagsBackpack and _G.BetterBagsBackpack:IsShown() then
                        _G.BetterBagsBackpack:Hide()
                    end
                end
            end
            
            -- Close AdiBags
            if otherAddon == "AdiBags" and _G.AdiBags and _G.AdiBags.frame then
                if _G.AdiBags.frame:IsShown() then
                    _G.AdiBags.frame:Hide()
                end
            end
            
            -- Close Bagnon
            if otherAddon == "Bagnon" and _G.Bagnon then
                for _, frameName in ipairs({"bags", "bank"}) do
                    local frame = _G.Bagnon[frameName]
                    if frame and frame:IsShown() then
                        frame:Hide()
                    end
                end
            end
            
            -- Close ArkInventory
            if otherAddon == "ArkInventory" then
                for loc = 1, 9 do
                    local frame = _G["ARKINV_Frame" .. loc]
                    if frame and frame:IsShown() then
                        frame:Hide()
                    end
                end
            end
            
            -- Show our UI
            if not self:IsShown() then
                self:Show()
            end
        end)
    end)
    
    IM:Debug("[BagUI] Priority bag toggle hooks applied (will close " .. otherAddon .. ")")
end

function BagUI:DetectOtherBagAddon()
    -- Check for popular bag addons
    local bagAddons = {
        "BetterBags",
        "AdiBags",
        "Bagnon",
        "ArkInventory",
        "Combuctor",
        "ElvUI",  -- ElvUI has its own bags
    }
    
    for _, addon in ipairs(bagAddons) do
        if C_AddOns.IsAddOnLoaded(addon) then
            IM:Debug("[BagUI] Detected bag addon: " .. addon)
            return addon
        end
    end
    
    return nil
end

function BagUI:GetDetectedBagAddon()
    return self:DetectOtherBagAddon()
end

function BagUI:IsEnabled()
    return IM.db.global.bagUI and IM.db.global.bagUI.enabled == true
end

-- ============================================================================
-- CONFLICT WARNING
-- ============================================================================

function BagUI:ShowConflictWarning(addonName)
    -- Check if user wants to hide warnings
    if IM.db.global.bagUI and IM.db.global.bagUI.hideConflictWarning then
        return
    end
    
    -- Create warning popup
    local popupWidth = 450
    local popupHeight = 320
    local popup = UI:CreatePanel("IMBagConflictWarning", UIParent, popupWidth, popupHeight)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
    
    -- Override border color to orange warning
    popup:SetBackdropBorderColor(0.8, 0.3, 0.1, 1)
    
    -- Add header manually
    local header = UI:CreateHeader(popup, "⚠️ Bag Addon Conflict")
    
    -- Create scrollable container for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 80)  -- Leave room for buttons
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(popupWidth - (UI.layout.padding * 2), 1)  -- Height will be dynamic
    scrollFrame:SetScrollChild(content)
    
    -- Create card for content
    local card = UI:CreateCard(content, {
        title = "Conflict Detected",
        description = "InventoryManager will attempt to take priority",
    })
    
    -- Main message
    card:AddText(
        "|cffffaa00InventoryManager's custom bag UI is enabled, but " .. addonName .. " is also active.|r"
    )
    
    card:AddText(" ")  -- Spacer
    
    card:AddText(
        "IM will try to override " .. addonName .. " when you open bags. If you experience issues:"
    )
    
    card:AddText(" ")  -- Spacer
    
    card:AddText("• Disable " .. addonName .. " for best results")
    card:AddText("• Or disable IM's custom bag UI below")
    
    -- Position card
    card:SetPoint("TOPLEFT", content, "TOPLEFT", UI.layout.padding, -UI.layout.padding)
    card:SetPoint("TOPRIGHT", content, "TOPRIGHT", -UI.layout.padding, -UI.layout.padding)
    
    -- Update content height
    content:SetHeight(card:GetContentHeight() + (UI.layout.padding * 2))
    
    -- Don't show again checkbox
    local checkContainer = CreateFrame("Frame", nil, popup)
    checkContainer:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", UI.layout.padding, 45)
    checkContainer:SetSize(200, 24)
    
    local dontShowCheck = CreateFrame("CheckButton", nil, checkContainer, "UICheckButtonTemplate")
    dontShowCheck:SetPoint("LEFT", 0, 0)
    dontShowCheck:SetSize(24, 24)
    
    local dontShowLabel = checkContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dontShowLabel:SetPoint("LEFT", dontShowCheck, "RIGHT", 5, 0)
    dontShowLabel:SetText("Don't show again")
    dontShowLabel:SetTextColor(0.9, 0.9, 0.9)
    
    dontShowCheck:SetScript("OnClick", function(self)
        if not IM.db.global.bagUI then
            IM.db.global.bagUI = {}
        end
        IM.db.global.bagUI.hideConflictWarning = self:GetChecked()
    end)
    
    -- Buttons at bottom
    local okBtn = UI:CreateButton(popup, "OK", 120, 30)
    okBtn:SetPoint("BOTTOM", popup, "BOTTOM", -65, UI.layout.padding)
    okBtn:SetScript("OnClick", function()
        popup:Hide()
    end)
    
    local disableBtn = UI:CreateButton(popup, "Disable IM Bags", 120, 30)
    disableBtn:SetPoint("BOTTOM", popup, "BOTTOM", 65, UI.layout.padding)
    disableBtn:SetScript("OnClick", function()
        IM.db.global.bagUI.enabled = false
        IM:Print("Custom Bag UI disabled")
        popup:Hide()
    end)
    
    popup:Show()
    
    -- Also print to chat
    IM:Print("|cffff9900⚠️ Bag Conflict:|r " .. addonName .. " detected. IM will attempt to take priority.")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

IM:RegisterEvent("PLAYER_LOGIN", function()
    BagUI:InitializeSettings()
    
    -- Pre-create the frame but don't show it
    BagUI:Create()
    
    -- Hook bag toggle if custom UI is enabled
    BagUI:HookBagToggle()
    
    -- Show warning popup if conflict detected and user has it enabled
    C_Timer.After(2, function()
        local otherAddon = BagUI:GetDetectedBagAddon()
        if otherAddon and BagUI:IsEnabled() then
            BagUI:ShowConflictWarning(otherAddon)
        end
    end)
    
    IM:Debug("[BagUI] Initialized")
end)
