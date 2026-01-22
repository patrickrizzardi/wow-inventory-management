--[[
    InventoryManager - UI/Panels/AutoSell.lua
    Auto-sell filter settings panel
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.AutoSell = {}

local AutoSellPanel = UI.Panels.AutoSell

-- Quality options with colors (0-7 to cover all WoW qualities)
local QUALITY_DATA = {
    {index = 0, label = "Poor (Gray)", color = "|cff9d9d9d"},
    {index = 1, label = "Common (White)", color = "|cffffffff"},
    {index = 2, label = "Uncommon (Green)", color = "|cff1eff00"},
    {index = 3, label = "Rare (Blue)", color = "|cff0070dd"},
    {index = 4, label = "Epic (Purple)", color = "|cffa335ee"},
    {index = 5, label = "Legendary (Orange)", color = "|cffff8000"},
    {index = 6, label = "Artifact (Gold)", color = "|cffe6cc80"},
    {index = 7, label = "Heirloom (Light Blue)", color = "|cff00ccff"},
}

-- Store reference for refresh
local _qualityDropdown = nil
local _updateStatsFunc = nil

function AutoSellPanel:Create(parent)
    -- Create scroll panel
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = 0

    -- ============================================================
    -- FEATURE CARD: Auto-Sell Filters
    -- ============================================================
    local featureCard = UI:CreateFeatureCard(content, yOffset, 100)

    local featureTitle = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -8)
    featureTitle:SetText(UI:ColorText("Auto-Sell Filters", "accent"))

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -28)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetSpacing(2)
    featureDesc:SetText(
        "Automatically sell items when you visit a vendor based on quality and item level.\n" ..
        "Item protection settings (soulbound, transmog, etc.) are in the Protections tab."
    )
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 110

    -- ============================================================
    -- SETTINGS CARD: Enable Auto-Sell
    -- ============================================================
    local enableCard = UI:CreateSettingsCard(content, yOffset, 45)

    local autoSellCheck = UI:CreateCheckbox(enableCard, "Enable Auto-Sell", IM.db.global.autoSellEnabled)
    autoSellCheck:SetPoint("TOPLEFT", enableCard, "TOPLEFT", 10, -10)
    autoSellCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoSellEnabled = value
        IM:Print("Auto-Sell: " .. (value and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    end

    yOffset = yOffset - 55

    -- ============================================================
    -- SETTINGS CARD: Quality & Item Level Filters
    -- ============================================================
    local settingsCard = UI:CreateSettingsCard(content, yOffset, 140)

    local settingsTitle = settingsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsTitle:SetPoint("TOPLEFT", 10, -10)
    settingsTitle:SetText("Filter Settings")
    settingsTitle:SetTextColor(unpack(UI.colors.text))

    -- Quality threshold dropdown
    local qualityLabel = settingsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualityLabel:SetPoint("TOPLEFT", 10, -35)
    qualityLabel:SetText("Maximum quality to sell:")
    qualityLabel:SetTextColor(unpack(UI.colors.text))

    local qualityDropdown = CreateFrame("Frame", "InventoryManagerQualityDropdown", settingsCard, "UIDropDownMenuTemplate")
    qualityDropdown:SetPoint("TOPLEFT", 5, -49)
    UIDropDownMenu_SetWidth(qualityDropdown, 160)
    _qualityDropdown = qualityDropdown

    local function QualityDropdown_Init()
        local currentQuality = IM.db.global.autoSell.maxQuality or 2
        for _, data in ipairs(QUALITY_DATA) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = data.color .. data.label .. "|r"
            info.value = data.index
            info.checked = (currentQuality == data.index)
            info.func = function(self)
                IM.db.global.autoSell.maxQuality = self.value
                UIDropDownMenu_SetText(qualityDropdown, data.color .. data.label .. "|r")
                IM:RefreshAllUI()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(qualityDropdown, QualityDropdown_Init)
    -- Set initial text
    local currentQuality = IM.db.global.autoSell.maxQuality or 2
    local currentData = QUALITY_DATA[currentQuality + 1] or QUALITY_DATA[3]
    UIDropDownMenu_SetText(qualityDropdown, currentData.color .. currentData.label .. "|r")

    -- Item level threshold
    local ilvlInput = UI:CreateNumberInput(settingsCard, "Maximum item level to sell (0 = any level)", IM.db.global.autoSell.maxItemLevel, 0, 9999)
    ilvlInput:SetPoint("TOPLEFT", 10, -95)

    -- Item level input callback
    ilvlInput.OnValueChanged = function(self, value)
        IM.db.global.autoSell.maxItemLevel = value
        IM:RefreshAllUI()
    end

    yOffset = yOffset - 160

    -- ============================================================
    -- SETTINGS CARD: Current Status
    -- ============================================================
    local statusCard = UI:CreateSettingsCard(content, yOffset, 70)

    local statusTitle = statusCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusTitle:SetPoint("TOPLEFT", 10, -10)
    statusTitle:SetText("Current Status")
    statusTitle:SetTextColor(unpack(UI.colors.text))

    -- Sellable items count
    local statsLabel = statusCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsLabel:SetPoint("TOPLEFT", 10, -35)
    statsLabel:SetTextColor(unpack(UI.colors.text))

    -- Update stats function
    local function UpdateStats()
        local count, value = IM.Filters:GetAutoSellCount()
        statsLabel:SetText("Sellable items: " .. count .. " (Value: " .. IM:FormatMoney(value) .. ")")
    end

    -- Store reference for dropdown callback
    _updateStatsFunc = UpdateStats

    -- Auto-refresh when panel is shown
    parent:SetScript("OnShow", function()
        UpdateStats()
    end)

    -- Auto-refresh on bag updates (only when panel is visible)
    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        if parent:IsVisible() then
            UpdateStats()
        end
    end)

    -- Initial update
    UpdateStats()

    -- Expose for external refresh (e.g., when mail rules change)
    AutoSellPanel.UpdateStats = UpdateStats

    yOffset = yOffset - 90

    -- ============================================================
    -- SETTINGS CARD: Bag Overlays
    -- ============================================================
    local overlaysHeader = UI:CreateSectionHeader(content, "Bag Overlays")
    overlaysHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local overlaysCard = UI:CreateSettingsCard(content, yOffset, 130)

    local lockOverlayCheck = UI:CreateCheckbox(overlaysCard, "Show lock icon on locked items", IM.db.global.ui.showLockOverlay)
    lockOverlayCheck:SetPoint("TOPLEFT", overlaysCard, "TOPLEFT", 10, -10)
    lockOverlayCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showLockOverlay = value
        IM:RefreshAllUI()
    end

    local sellOverlayCheck = UI:CreateCheckbox(overlaysCard, "Show coin icon on sellable items", IM.db.global.ui.showSellOverlay)
    sellOverlayCheck:SetPoint("TOPLEFT", overlaysCard, "TOPLEFT", 10, -35)
    sellOverlayCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showSellOverlay = value
        IM:RefreshAllUI()
    end

    local mailOverlayCheck = UI:CreateCheckbox(overlaysCard, "Show mail border on mail helper items", IM.db.global.ui.showMailOverlay)
    mailOverlayCheck:SetPoint("TOPLEFT", overlaysCard, "TOPLEFT", 10, -60)
    mailOverlayCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showMailOverlay = value
        IM:RefreshAllUI()
    end

    local unsellableCheck = UI:CreateCheckbox(overlaysCard, "Show indicator on unsellable items", IM.db.global.ui.showUnsellableIndicator)
    unsellableCheck:SetPoint("TOPLEFT", overlaysCard, "TOPLEFT", 10, -85)
    unsellableCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showUnsellableIndicator = value
        IM:RefreshAllUI()
    end

    yOffset = yOffset - 140

    -- ============================================================
    -- TIPS SECTION
    -- ============================================================
    local tipsTitle = UI:CreateSectionHeader(content, "Auto-Sell Tips")
    tipsTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 22

    local tipsText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipsText:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    tipsText:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    tipsText:SetJustifyH("LEFT")
    tipsText:SetSpacing(2)
    tipsText:SetText(
        "|cffaaaaaa" ..
        "- Quality filter determines the maximum rarity to auto-sell (Poor/Common/Uncommon)\n" ..
        "- Item level filter prevents selling higher-level gear by accident\n" ..
        "- Protected items (soulbound, transmog appearances, etc.) are never sold\n" ..
        "- The sell action only triggers when you actually open a vendor window\n" ..
        "|r"
    )
    tipsText:SetTextColor(0.7, 0.7, 0.7)

    yOffset = yOffset - 80

    -- Set content height
    content:SetHeight(math.abs(yOffset) + 20)
end
