--[[
    InventoryManager - UI/Panels/BagUI.lua
    Settings panel for custom bag UI configuration.
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.BagUI = {}

local BagUIPanel = UI.Panels.BagUI

function BagUIPanel:Create(parent)
    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- Check for other bag addons
    local otherBagAddon = IM.UI.BagUI and IM.UI.BagUI:GetDetectedBagAddon()

    -- ============================================================
    -- WARNING CARD (if other bag addon detected)
    -- ============================================================
    if otherBagAddon then
        local warningCard = UI:CreateCard(content, {
            title = "⚠️ Conflict Detected",
            description = "Another bag addon is installed: " .. otherBagAddon,
        })

        warningCard:AddText("|cffffaa00InventoryManager will try to take priority, but conflicts may occur.|r")
        warningCard:AddText(" ")
        warningCard:AddText("For best experience:")
        warningCard:AddText("• Keep only one bag addon enabled")
        warningCard:AddText("• If issues occur, disable " .. otherBagAddon)

        content:AdvanceY(warningCard:GetContentHeight() + UI.layout.cardSpacing)
    end

    -- ============================================================
    -- MAIN SETTINGS CARD
    -- ============================================================
    local mainCard = UI:CreateCard(content, {
        title = "Bag UI Settings",
        description = "Configure the custom InventoryManager bag interface.",
    })

    -- Enable custom bag UI
    local hintText = "Replaces Blizzard bags with InventoryManager's category-organized view"
    if otherBagAddon then
        hintText = "|cffffaa00Will attempt to override " .. otherBagAddon .. "|r"
    end
    
    local enableCheck = mainCard:AddCheckbox(
        "Enable custom bag UI",
        IM.db.global.bagUI and IM.db.global.bagUI.enabled,
        hintText
    )
    enableCheck.checkbox.OnValueChanged = function(self, value)
        if not IM.db.global.bagUI then
            IM.UI.BagUI:InitializeSettings()
        end
        IM.db.global.bagUI.enabled = value
        
        if value and otherBagAddon then
            IM:Print("Custom Bag UI: |cff00ff00ENABLED|r (will override " .. otherBagAddon .. ")")
            IM:Print("If you experience issues, disable " .. otherBagAddon)
        else
            IM:Print("Custom Bag UI: " .. (value and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
        end
        
        IM:Print("Close and reopen bags to see the change")
    end

    content:AdvanceY(mainCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- LAYOUT SETTINGS CARD
    -- ============================================================
    local layoutCard = UI:CreateCard(content, {
        title = "Layout Settings",
        description = "Customize how items are organized and displayed.",
    })

    -- Debounced refresh to avoid heavy reflow on every slider tick
    local layoutRefreshTimer = nil
    local function ScheduleLayoutRefresh()
        if layoutRefreshTimer then
            layoutRefreshTimer:Cancel()
        end
        layoutRefreshTimer = C_Timer.NewTimer(0.12, function()
            if IM.UI.BagUI then
                IM.UI.BagUI:ResizeForSettings()
                if IM.UI.BagUI.Refresh then
                    IM.UI.BagUI:Refresh()
                end
            end
        end)
    end

    local function ApplyLayoutNow()
        if layoutRefreshTimer then
            layoutRefreshTimer:Cancel()
            layoutRefreshTimer = nil
        end
        if IM.UI.BagUI then
            IM.UI.BagUI:ResizeForSettings()
            if IM.UI.BagUI.Refresh then
                IM.UI.BagUI:Refresh()
            end
        end
    end

    -- Number of columns
    local columnsY = layoutCard:AddContent(50)
    local columnsSlider = UI:CreateSlider(layoutCard, "Number of columns", 1, 4, 1, IM.db.global.bagUI and IM.db.global.bagUI.columns or 2)
    columnsSlider:SetPoint("TOPLEFT", layoutCard, "TOPLEFT", layoutCard._leftPadding, columnsY)
    columnsSlider.OnValueChanged = function(self, value)
        if not IM.db.global.bagUI then
            IM.UI.BagUI:InitializeSettings()
        end
        IM.db.global.bagUI.columns = value

        -- Debounce expensive layout work while dragging
        ScheduleLayoutRefresh()
    end
    if columnsSlider.slider then
        columnsSlider.slider:HookScript("OnMouseUp", function()
            ApplyLayoutNow()
        end)
    end

    -- Items per row
    local itemsY = layoutCard:AddContent(50)
    local itemsSlider = UI:CreateSlider(layoutCard, "Items per row", 4, 12, 1, IM.db.global.bagUI and IM.db.global.bagUI.itemsPerRow or 6)
    itemsSlider:SetPoint("TOPLEFT", layoutCard, "TOPLEFT", layoutCard._leftPadding, itemsY)
    itemsSlider.OnValueChanged = function(self, value)
        if not IM.db.global.bagUI then
            IM.UI.BagUI:InitializeSettings()
        end
        IM.db.global.bagUI.itemsPerRow = value

        -- Debounce expensive layout work while dragging
        ScheduleLayoutRefresh()
    end
    if itemsSlider.slider then
        itemsSlider.slider:HookScript("OnMouseUp", function()
            ApplyLayoutNow()
        end)
    end

    -- View mode dropdown
    local viewModeY = layoutCard:AddContent(40)
    local viewModeDropdown = UI:CreateDropdown(layoutCard, "View mode", {"Category", "Subcategory"}, IM.db.global.bagUI and IM.db.global.bagUI.viewMode == "subcategory" and 2 or 1)
    viewModeDropdown:SetPoint("TOPLEFT", layoutCard, "TOPLEFT", layoutCard._leftPadding, viewModeY)
    viewModeDropdown.OnValueChanged = function(self, index, value)
        if not IM.db.global.bagUI then
            IM.UI.BagUI:InitializeSettings()
        end
        IM.db.global.bagUI.viewMode = index == 2 and "subcategory" or "category"
        if IM.UI.BagUI and IM.UI.BagUI.Refresh then
            IM.UI.BagUI:Refresh()
        end
    end

    -- Set items checkbox
    local setsY = layoutCard:AddContent(35)
    local setsCheck = layoutCard:AddCheckbox(
        "Show Equipment Sets as separate category",
        IM.db.global.bagUI and IM.db.global.bagUI.showItemSets,
        "Groups equipment set items into their own category"
    )
    setsCheck:SetPoint("TOPLEFT", layoutCard, "TOPLEFT", layoutCard._leftPadding, setsY)
    setsCheck.checkbox.OnValueChanged = function(self, value)
        if not IM.db.global.bagUI then
            IM.UI.BagUI:InitializeSettings()
        end
        IM.db.global.bagUI.showItemSets = value
        if IM.UI.BagUI and IM.UI.BagUI.Refresh then
            IM.UI.BagUI:Refresh()
        end
    end

    -- Height slider
    local heightY = layoutCard:AddContent(50)
    local heightSlider = UI:CreateSlider(layoutCard, "Window height", 400, 900, 50, IM.db.global.bagUI and IM.db.global.bagUI.height or 500)
    heightSlider:SetPoint("TOPLEFT", layoutCard, "TOPLEFT", layoutCard._leftPadding, heightY)
    heightSlider.OnValueChanged = function(self, value)
        if not IM.db.global.bagUI then
            IM.UI.BagUI:InitializeSettings()
        end
        IM.db.global.bagUI.height = value
        
        -- Resize window
        if IM.UI.BagUI then
            IM.UI.BagUI:ResizeForSettings()
        end
    end

    content:AdvanceY(layoutCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Tips",
    })

    tipsCard:AddText("- Press B to toggle bags (same as Blizzard)")
    tipsCard:AddText("- Click gold to open Tracker Dashboard")
    tipsCard:AddText("- Click gear icon to open Settings")
    tipsCard:AddText("- |cffffb000Alt+Click|r item to add to whitelist (lock/protect)")
    tipsCard:AddText("- |cffffb000Ctrl+Alt+Click|r item to add to junk list (force sell)")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.cardSpacing)

    content:FinalizeHeight()
end
