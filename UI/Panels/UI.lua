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
    -- SETTINGS CARD: Bag Overlays
    -- ============================================================
    local overlayHeader = UI:CreateSectionHeader(content, "Bag Overlays")
    overlayHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local overlayCard = UI:CreateSettingsCard(content, yOffset, 200)

    local overlayDesc = overlayCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlayDesc:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 10, -8)
    overlayDesc:SetPoint("RIGHT", overlayCard, "RIGHT", -10, 0)
    overlayDesc:SetJustifyH("LEFT")
    overlayDesc:SetText("|cff888888Visual indicators on items in your bags. Alt+Click to lock, Ctrl+Alt+Click to mark as junk.|r")

    -- Lock overlay (red) - whitelisted/protected items
    local lockOverlayCheck = UI:CreateCheckbox(overlayCard, "Show lock overlay (protected items)", IM.db.global.ui.showLockOverlay ~= false)
    lockOverlayCheck:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 10, -30)
    lockOverlayCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showLockOverlay = value
        IM:RefreshBagOverlays()
    end

    local lockHint = overlayCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockHint:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 30, -50)
    lockHint:SetText("|cffff6666Red border|r - Items that won't be auto-sold or deleted")

    -- Sell overlay (green) - items that will be auto-sold
    local sellOverlayCheck = UI:CreateCheckbox(overlayCard, "Show sell overlay (auto-sell items)", IM.db.global.ui.showSellOverlay ~= false)
    sellOverlayCheck:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 10, -70)
    sellOverlayCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showSellOverlay = value
        IM:RefreshBagOverlays()
    end

    local sellHint = overlayCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sellHint:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 30, -90)
    sellHint:SetText("|cff66ff66Green border|r - Items that will be sold at vendor")

    -- Mail overlay (blue) - items matching mail rules
    local mailOverlayCheck = UI:CreateCheckbox(overlayCard, "Show mail overlay (mail rule items)", IM.db.global.ui.showMailOverlay ~= false)
    mailOverlayCheck:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 10, -110)
    mailOverlayCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showMailOverlay = value
        IM:RefreshBagOverlays()
    end

    local mailHint = overlayCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mailHint:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 30, -130)
    mailHint:SetText("|cff6699ffBlue border|r - Items matching mail helper rules")

    -- Unsellable overlay (gray) - items with no vendor value
    local unsellableOverlayCheck = UI:CreateCheckbox(overlayCard, "Show unsellable indicator", IM.db.global.ui.showUnsellableIndicator ~= false)
    unsellableOverlayCheck:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 10, -150)
    unsellableOverlayCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showUnsellableIndicator = value
        IM:RefreshBagOverlays()
    end

    local unsellableHint = overlayCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unsellableHint:SetPoint("TOPLEFT", overlayCard, "TOPLEFT", 30, -170)
    unsellableHint:SetText("|cff888888Gray border|r - Items with no vendor value (can't be sold)")

    yOffset = yOffset - 210

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
        "- Overlays update automatically when you open bags or visit vendors\n" ..
        "- Lock overlay takes priority over other overlays\n" ..
        "- Tooltip info shows classID_subclassID and lock status\n" ..
        "- Minimap button can be hidden if you use /im\n" ..
        "|r"
    )

    yOffset = yOffset - 80

    content:SetHeight(math.abs(yOffset) + 20)
end
