--[[
    InventoryManager - UI/Panels/AutoSell.lua
    Auto-sell filter settings panel
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.AutoSell = {}

local AutoSellPanel = UI.Panels.AutoSell

-- Quality options with colors
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

local _qualityDropdown = nil
local _updateStatsFunc = nil

function AutoSellPanel:Create(parent)
    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- ============================================================
    -- AUTO-SELL FILTERS CARD
    -- ============================================================
    local mainCard = UI:CreateCard(content, {
        title = "Auto-Sell Filters",
        description = "Automatically sell items when you visit a vendor based on quality and item level. Protection settings are in the Protections tab.",
    })

    local autoSellCheck = mainCard:AddCheckbox(
        "Enable Auto-Sell",
        IM.db.global.autoSellEnabled,
        "Automatically sells matching items when you open a vendor"
    )
    autoSellCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoSellEnabled = value
        IM:Print("Auto-Sell: " .. (value and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    end

    content:AdvanceY(mainCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- FILTER SETTINGS CARD
    -- ============================================================
    local filterCard = UI:CreateCard(content, {
        title = "Filter Settings",
        description = "Configure which items are eligible for auto-sell.",
    })

    -- Quality threshold dropdown
    local dropdownY = filterCard:AddContent(24)
    local qualityLabel = filterCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualityLabel:SetPoint("TOPLEFT", filterCard, "TOPLEFT", filterCard._leftPadding, dropdownY)
    qualityLabel:SetText("Maximum quality to sell:")
    qualityLabel:SetTextColor(unpack(UI.colors.text))

    local dropdownRowY = filterCard:AddContent(34)
    local qualityDropdown = CreateFrame("Frame", "InventoryManagerQualityDropdown", filterCard, "UIDropDownMenuTemplate")
    qualityDropdown:SetPoint("TOPLEFT", filterCard._leftPadding - 15, dropdownRowY + 4)
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
    local currentQuality = IM.db.global.autoSell.maxQuality or 2
    local currentData = QUALITY_DATA[currentQuality + 1] or QUALITY_DATA[3]
    UIDropDownMenu_SetText(qualityDropdown, currentData.color .. currentData.label .. "|r")

    -- Item level threshold
    local ilvlLabelY = filterCard:AddContent(24)
    local ilvlLabel = filterCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlLabel:SetPoint("TOPLEFT", filterCard, "TOPLEFT", filterCard._leftPadding, ilvlLabelY)
    ilvlLabel:SetText("Maximum item level to sell (0 = any level):")
    ilvlLabel:SetTextColor(unpack(UI.colors.text))

    local ilvlInputY = filterCard:AddContent(32)
    local ilvlInput = UI:CreateNumberInput(filterCard, nil, IM.db.global.autoSell.maxItemLevel, 0, 9999)
    ilvlInput:SetPoint("TOPLEFT", filterCard, "TOPLEFT", filterCard._leftPadding, ilvlInputY + 4)
    ilvlInput.OnValueChanged = function(self, value)
        IM.db.global.autoSell.maxItemLevel = value
        IM:RefreshAllUI()
    end

    content:AdvanceY(filterCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- CURRENT STATUS CARD
    -- ============================================================
    local statusCard = UI:CreateCard(content, {
        title = "Current Status",
    })

    local statsY = statusCard:AddContent(24)
    local statsLabel = statusCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsLabel:SetPoint("TOPLEFT", statusCard, "TOPLEFT", statusCard._leftPadding, statsY)
    statsLabel:SetTextColor(unpack(UI.colors.text))

    local function UpdateStats()
        local count, value = IM.Filters:GetAutoSellCount()
        statsLabel:SetText("Sellable items: " .. count .. " (Value: " .. IM:FormatMoney(value) .. ")")
    end

    _updateStatsFunc = UpdateStats
    parent:SetScript("OnShow", UpdateStats)
    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        if parent:IsVisible() then UpdateStats() end
    end)
    UpdateStats()
    AutoSellPanel.UpdateStats = UpdateStats

    content:AdvanceY(statusCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Auto-Sell Tips",
    })

    tipsCard:AddText("- Quality filter determines the maximum rarity to auto-sell")
    tipsCard:AddText("- Item level filter prevents selling higher-level gear")
    tipsCard:AddText("- Protected items (soulbound, transmog, etc.) are never sold")
    tipsCard:AddText("- Selling only triggers when you open a vendor window")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.cardSpacing)

    content:FinalizeHeight()
end
