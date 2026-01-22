--[[
    InventoryManager - UI/Panels/UI.lua
    UI settings panel - general UI options and bag overlays.
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.UI = {}

local UIPanel = UI.Panels.UI

function UIPanel:Create(parent)
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = 0

    local featureCard = UI:CreateFeatureCard(content, yOffset, 70)

    local featureTitle = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -8)
    featureTitle:SetText(UI:ColorText("UI Settings", "accent"))

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -26)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetText("Configure InventoryManager UI behavior and bag overlays.")
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 80

    -- ============================================================
    -- SETTINGS CARD: UI Options
    -- ============================================================
    local uiHeader = UI:CreateSectionHeader(content, "UI Options")
    uiHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local uiCard = UI:CreateSettingsCard(content, yOffset, 120)

    local minimapCheck = UI:CreateCheckbox(uiCard, "Show minimap button", IM.db.global.ui.showMinimapButton)
    minimapCheck:SetPoint("TOPLEFT", uiCard, "TOPLEFT", 10, -10)
    minimapCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showMinimapButton = value
        if IM.UI and IM.UI.MinimapButton then
            if value then
                IM.UI.MinimapButton:Show()
            else
                IM.UI.MinimapButton:Hide()
            end
        end
    end

    local autoOpenCheck = UI:CreateCheckbox(uiCard, "Auto-open panel at merchant", IM.db.global.ui.autoOpenOnMerchant)
    autoOpenCheck:SetPoint("TOPLEFT", uiCard, "TOPLEFT", 10, -35)
    autoOpenCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.autoOpenOnMerchant = value
    end

    local tooltipCheck = UI:CreateCheckbox(uiCard, "Show InventoryManager info in tooltips", IM.db.global.ui.showTooltipInfo)
    tooltipCheck:SetPoint("TOPLEFT", uiCard, "TOPLEFT", 10, -60)
    tooltipCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showTooltipInfo = value
    end

    local tooltipHint = uiCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tooltipHint:SetPoint("TOPLEFT", uiCard, "TOPLEFT", 30, -82)
    tooltipHint:SetText("|cff666666Shows category, classID_subclassID, and lock status|r")

    yOffset = yOffset - 130

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
        "- Tooltip info shows classID_subclassID and lock status\n" ..
        "- Minimap button can be hidden if you use /im\n" ..
        "|r"
    )

    yOffset = yOffset - 60

    content:SetHeight(math.abs(yOffset) + 20)
end
