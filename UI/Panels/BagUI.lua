--[[
    InventoryManager - UI/Panels/BagUI.lua
    Bag UI settings panel.
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.BagUI = {}

local BagUISettings = UI.Panels.BagUI

function BagUISettings:Create(parent)
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = 0

    local featureCard = UI:CreateFeatureCard(content, yOffset, 70)

    local featureTitle = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -8)
    featureTitle:SetText(UI:ColorText("Bag UI", "accent"))

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -26)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetText("Customize InventoryManager's bag layout and behavior.")
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 80

    local mainHeader = UI:CreateSectionHeader(content, "Bag Options")
    mainHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local mainCard = UI:CreateSettingsCard(content, yOffset, 420)

    local bagUIEnabled = UI:CreateCheckbox(mainCard, "Use InventoryManager bags (override B key)", IM.db.global.useIMBags)
    bagUIEnabled:SetPoint("TOPLEFT", mainCard, "TOPLEFT", 10, -10)
    bagUIEnabled.checkbox.OnValueChanged = function(self, value)
        IM.db.global.useIMBags = value
        local BagUI = IM.UI and IM.UI.BagUI
        if BagUI and BagUI.ApplyKeybindOverrides then
            BagUI:ApplyKeybindOverrides()
        end
        if not value and BagUI and BagUI.Hide then
            BagUI:Hide()
        end
        IM:Print("IM Bags: " .. (value and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    end

    local groupingOptions = { "Category", "Subcategory" }
    local groupingDefault = IM.db.global.bagUI.groupingMode == "subcategory" and 2 or 1
    local groupingDropdown = UI:CreateDropdown(mainCard, "Grouping mode", groupingOptions, groupingDefault)
    groupingDropdown:SetPoint("TOPLEFT", mainCard, "TOPLEFT", 10, -35)
    groupingDropdown.OnValueChanged = function(self, index, value)
        IM.db.global.bagUI.groupingMode = (index == 2) and "subcategory" or "category"
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Container then
            IM.UI.BagUI.Container:Refresh()
        end
    end

    local showGearSets = UI:CreateCheckbox(mainCard, "Show gear sets as categories", IM.db.global.bagUI.showGearSets ~= false)
    showGearSets:SetPoint("TOPLEFT", mainCard, "TOPLEFT", 10, -75)
    showGearSets.checkbox.OnValueChanged = function(self, value)
        IM.db.global.bagUI.showGearSets = value
        local BagData = IM:GetModule("BagData")
        if BagData then
            BagData:ForceRefresh()
        end
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Container then
            IM.UI.BagUI.Container:Refresh()
        end
    end

    local showItemLevel = UI:CreateCheckbox(mainCard, "Show item level on gear", IM.db.global.bagUI.showItemLevel == true)
    showItemLevel:SetPoint("TOPLEFT", mainCard, "TOPLEFT", 10, -100)
    showItemLevel.checkbox.OnValueChanged = function(self, value)
        IM.db.global.bagUI.showItemLevel = value
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Container then
            IM.UI.BagUI.Container:Refresh()
        end
    end

    local scaleSlider = UI:CreateSlider(mainCard, "Bag scale", 0.7, 1.3, 0.05, IM.db.global.bagUI.scale or 1)
    scaleSlider:SetPoint("TOPLEFT", mainCard, "TOPLEFT", 10, -130)
    scaleSlider.OnValueChanged = function(self, value)
        IM.db.global.bagUI.scale = value
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.ApplyLayoutSettings then
            IM.UI.BagUI:ApplyLayoutSettings()
        end
    end

    local columnsSlider = UI:CreateSlider(mainCard, "Items per row", 4, 16, 1, IM.db.global.bagUI.itemColumns or IM.db.global.bagUI.maxColumns or 10)
    columnsSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -12)
    columnsSlider.OnValueChanged = function(self, value)
        IM.db.global.bagUI.itemColumns = math.floor(value)
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.ApplyLayoutSettings then
            IM.UI.BagUI:ApplyLayoutSettings()
        end
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Container then
            IM.UI.BagUI.Container:Refresh()
        end
    end

    local categoryColumns = UI:CreateSlider(mainCard, "Category columns", 1, 4, 1, IM.db.global.bagUI.categoryColumns or 2)
    categoryColumns:SetPoint("TOPLEFT", columnsSlider, "BOTTOMLEFT", 0, -12)
    categoryColumns.OnValueChanged = function(self, value)
        IM.db.global.bagUI.categoryColumns = math.floor(value)
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.ApplyLayoutSettings then
            IM.UI.BagUI:ApplyLayoutSettings()
        end
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Container then
            IM.UI.BagUI.Container:Refresh()
        end
    end

    local windowRows = UI:CreateSlider(mainCard, "Window rows", 6, 30, 1, IM.db.global.bagUI.windowRows or IM.db.global.bagUI.maxRows or 12)
    windowRows:SetPoint("TOPLEFT", categoryColumns, "BOTTOMLEFT", 0, -12)
    windowRows.OnValueChanged = function(self, value)
        IM.db.global.bagUI.windowRows = math.floor(value)
        if IM.UI and IM.UI.BagUI and IM.UI.BagUI.ApplyLayoutSettings then
            IM.UI.BagUI:ApplyLayoutSettings()
        end
    end

    yOffset = yOffset - 440

    -- ============================================================
    -- TIPS SECTION
    -- ============================================================
    local tipsHeader = UI:CreateSectionHeader(content, "Tips")
    tipsHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 22

    local tipsText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipsText:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    tipsText:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    tipsText:SetJustifyH("LEFT")
    tipsText:SetSpacing(2)
    tipsText:SetText(
        "|cffaaaaaa" ..
        "- Drag the bag window to reposition it\n" ..
        "- Use category columns for a multi-column layout\n" ..
        "- Window rows controls visible item rows before scrolling\n" ..
        "|r"
    )

    yOffset = yOffset - 60

    content:SetHeight(math.abs(yOffset) + 20)
end
