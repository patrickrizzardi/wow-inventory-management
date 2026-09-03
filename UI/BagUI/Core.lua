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

-- Search filter state
local _searchFilter = ""
local _searchRefreshTimer = nil

-- Secure interaction tracking (to avoid taint from override bindings)
local _secureInteractionActive = false
local _secureInteractionTypes = {
    -- These interaction types use secure item handling - clear override bindings
    [53] = true,  -- ItemUpgrade
    [10] = true,  -- Banker (personal bank)
    [17] = true,  -- GuildBanker
    [21] = true,  -- Auctioneer
    [26] = true,  -- Transmogrifier
    -- Add more as needed
}

-- ============================================================================
-- SEARCH FILTER
-- ============================================================================

function BagUI:SetSearchFilter(text)
    text = text or ""
    if _searchFilter == text then return end

    _searchFilter = text

    -- Debounce refresh (0.15s delay)
    if _searchRefreshTimer then
        _searchRefreshTimer:Cancel()
    end
    _searchRefreshTimer = C_Timer.NewTimer(0.15, function()
        _searchRefreshTimer = nil
        if self:IsShown() then
            self:Refresh()
        end
    end)
end

function BagUI:GetSearchFilter()
    return _searchFilter
end

-- ============================================================================
-- VIEW MODE
-- ============================================================================

-- Header filter buttons. "subcategory" keeps its legacy db value so existing
-- saved settings keep working; the button just calls it what it is.
BagUI.VIEW_MODE_BUTTONS = {
    { mode = "category",   label = "Category",  tooltip = "Group by item class - Armor, Consumable, Quest, and so on." },
    { mode = "subcategory", label = "Slot",     tooltip = "Group gear by equipment slot - Head, Neck, Trinket, and so on." },
    { mode = "topstat",    label = "Top Stat",  tooltip = "Group gear by its highest secondary stat." },
    { mode = "statcombo",  label = "Stat Pair", tooltip = "Group gear by its full secondary combination, e.g. Crit / Mastery." },
}

function BagUI:GetViewMode()
    local mode = self:GetSettings().viewMode
    if BagUI.CategoryView and BagUI.CategoryView.IsValidViewMode then
        if not BagUI.CategoryView:IsValidViewMode(mode) then
            return "category"
        end
    end
    return mode or "category"
end

function BagUI:SetViewMode(mode)
    if not mode then return end
    if self:GetViewMode() == mode then return end

    if not IM.db.global.bagUI then
        self:InitializeSettings()
    end
    IM.db.global.bagUI.viewMode = mode

    self:UpdateFilterButtons()

    if self:IsShown() then
        self:Refresh()
    end
end

-- Paint the active mode's button; safe to call before the frame exists
function BagUI:UpdateFilterButtons(frame)
    frame = frame or _bagFrame
    if not frame or not frame.filterButtons then return end

    local active = self:GetViewMode()
    for _, row in ipairs(frame.filterButtons) do
        row:SetSelected(row._imViewMode == active)
    end
end

function BagUI:GetSettings()
    local settings = IM.db.global.bagUI or {}
    -- Ensure defaults for any missing keys (handles upgrades from older versions)
    if settings.iconSize == nil then settings.iconSize = 20 end
    return settings
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
        local defaultItemsPerRow = math.min(math.ceil(totalSlots / 12), 14)
        defaultItemsPerRow = math.max(defaultItemsPerRow, 8)
        
        IM.db.global.bagUI = {
            enabled = true,  -- Enabled by default
            itemsPerRow = 10,  -- Items before wrapping; also sets the window width
            viewMode = "category",  -- see BagUI.VIEW_MODE_BUTTONS for valid modes
            showItemSets = true,
            height = 500,  -- Default height
            iconSize = 20,  -- Item icon size (16-32)
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

-- Hidden button for keybind overrides
local _toggleButton = nil

function BagUI:GetToggleButton()
    if not _toggleButton then
        _toggleButton = CreateFrame("Button", "InventoryManagerBagToggleButton", UIParent, "SecureActionButtonTemplate")
        _toggleButton:SetScript("OnClick", function()
            if BagUI:IsEnabled() then
                BagUI:Toggle()
            end
        end)
        _toggleButton:Hide()
    end
    return _toggleButton
end

function BagUI:SetupBindingOverrides()
    if not self:IsEnabled() then return end

    local toggleBtn = self:GetToggleButton()

    -- All bag-related bindings we want to intercept
    local bagBindings = {
        "OPENALLBAGS",
        "TOGGLEBACKPACK",
        "TOGGLEBAG1",
        "TOGGLEBAG2",
        "TOGGLEBAG3",
        "TOGGLEBAG4",
    }

    local boundKeys = {}

    for _, binding in ipairs(bagBindings) do
        -- GetBindingKey returns all keys bound to this action
        local key1, key2 = GetBindingKey(binding)
        if key1 then
            SetOverrideBindingClick(toggleBtn, true, key1, "InventoryManagerBagToggleButton")
            table.insert(boundKeys, key1 .. " (" .. binding .. ")")
        end
        if key2 then
            SetOverrideBindingClick(toggleBtn, true, key2, "InventoryManagerBagToggleButton")
            table.insert(boundKeys, key2 .. " (" .. binding .. ")")
        end
    end

    if #boundKeys > 0 then
        IM:Debug("[BagUI] Override bindings set: " .. table.concat(boundKeys, ", "))
    else
        IM:Debug("[BagUI] No bag keybinds found to override")
    end
end

function BagUI:ClearBindingOverrides()
    local toggleBtn = self:GetToggleButton()
    ClearOverrideBindings(toggleBtn)
    IM:Debug("[BagUI] Override bindings cleared")
end

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

    -- Hook all ContainerFrame OnShow to suppress Blizzard bags when our BagUI is enabled.
    -- This catches vendors (Item Upgrade, etc.) that open bags directly without calling
    -- OpenAllBags/ToggleAllBags.
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", function(f)
                if self:IsEnabled() then
                    f:Hide()
                end
            end)
        end
    end
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function(f)
            if self:IsEnabled() then
                f:Hide()
            end
        end)
    end
    IM:Debug("[BagUI] Blizzard bag suppression hooks applied")
end

function BagUI:HookBagToggleNormal()
    -- Standard hooks when no other bag addon is present

    -- Hook ToggleAllBags (called when pressing B key)
    hooksecurefunc("ToggleAllBags", function()
        IM:Debug("[BagUI] ToggleAllBags hook fired, enabled=" .. tostring(self:IsEnabled()) .. ", secureInteraction=" .. tostring(IM:IsSecureInteractionActive()))
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

    -- Hook OpenAllBags (called when opening vendor/AH)
    hooksecurefunc("OpenAllBags", function(forceOpen)
        IM:Debug("[BagUI] OpenAllBags hook fired, enabled=" .. tostring(self:IsEnabled()) .. ", secureInteraction=" .. tostring(IM:IsSecureInteractionActive()))
        if self:IsEnabled() then
            -- Close Blizzard bags
            for i = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                local frame = _G["ContainerFrame"..(i+1)]
                if frame and frame:IsShown() then
                    frame:Hide()
                end
            end

            if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                ContainerFrameCombinedBags:Hide()
            end

            if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
                local reagentFrame = _G["ContainerFrame"..(NUM_BAG_SLOTS + 2)]
                if reagentFrame and reagentFrame:IsShown() then
                    reagentFrame:Hide()
                end
            end

            -- Show our UI
            if not self:IsShown() then
                self:Show()
            end
        end
    end)

    IM:Debug("[BagUI] Normal bag toggle hooks applied")
end

function BagUI:HookBagToggleWithPriority(otherAddon)
    -- Aggressive hooks that take priority over other bag addons
    
    local function CloseAllBagFrames()
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
    end
    
    -- Hook ToggleAllBags
    hooksecurefunc("ToggleAllBags", function()
        if not self:IsEnabled() then return end

        -- Use a slightly delayed close to override other addons
        C_Timer.After(0.05, function()
            CloseAllBagFrames()

            -- Show our UI
            if not self:IsShown() then
                self:Show()
            end
        end)
    end)

    -- Hook OpenAllBags (for vendor/AH)
    hooksecurefunc("OpenAllBags", function(forceOpen)
        if not self:IsEnabled() then return end

        C_Timer.After(0.05, function()
            CloseAllBagFrames()

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

    -- Stat grouping reads item data that often arrives after the bag is drawn;
    -- re-render once it lands so gear leaves the "Loading..." bucket.
    local ItemStats = IM:GetModule("ItemStats")
    if ItemStats then
        ItemStats:RegisterRefreshCallback(function()
            local mode = BagUI:GetViewMode()
            if (mode == "topstat" or mode == "statcombo") and BagUI:IsShown() then
                BagUI:Refresh()
            end
        end)
    end

    -- Pre-create the frame but don't show it
    BagUI:Create()

    -- Hook bag toggle if custom UI is enabled
    BagUI:HookBagToggle()

    -- Set up keybind overrides to intercept all bag-related keys
    BagUI:SetupBindingOverrides()

    -- Show warning popup if conflict detected and user has it enabled
    C_Timer.After(2, function()
        local otherAddon = BagUI:GetDetectedBagAddon()
        if otherAddon and BagUI:IsEnabled() then
            BagUI:ShowConflictWarning(otherAddon)
        end
    end)

    IM:Debug("[BagUI] Initialized")
end)

-- Re-apply overrides when user changes keybinds
IM:RegisterEvent("UPDATE_BINDINGS", function()
    if BagUI:IsEnabled() and not _secureInteractionActive then
        BagUI:ClearBindingOverrides()
        BagUI:SetupBindingOverrides()
    end
end)

-- Clear override bindings when secure interactions open (prevents taint)
IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(event, interactionType)
    if _secureInteractionTypes[interactionType] then
        _secureInteractionActive = true
        BagUI:ClearBindingOverrides()
        -- Also disable the toggle button entirely during secure interactions
        if _toggleButton then
            _toggleButton:SetScript("OnClick", nil)
            _toggleButton:Hide()
        end
        IM:Debug("[BagUI] Cleared override bindings for secure interaction type " .. interactionType)

        -- Show our bags when a secure vendor opens (Item Upgrade, AH, etc.)
        -- Blizzard bag suppression is handled by the ContainerFrame OnShow hooks.
        if BagUI:IsEnabled() and not BagUI:IsShown() then
            BagUI:Show()
            IM:Debug("[BagUI] Opened our bags for secure interaction type " .. interactionType)
        end
    end
end)

-- Restore override bindings when secure interactions close
IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(event, interactionType)
    if _secureInteractionTypes[interactionType] then
        _secureInteractionActive = false
        if BagUI:IsEnabled() then
            -- Close our bags (mirrors Blizzard closing theirs when vendor closes)
            if BagUI:IsShown() then
                BagUI:Hide()
            end
            -- Restore the toggle button's OnClick script
            if _toggleButton then
                _toggleButton:SetScript("OnClick", function()
                    if BagUI:IsEnabled() then
                        BagUI:Toggle()
                    end
                end)
            end
            BagUI:SetupBindingOverrides()
            IM:Debug("[BagUI] Restored override bindings after secure interaction closed")
        end
    end
end)
