--[[
    InventoryManager - UI/Panels/UI.lua
    UI settings panel - general UI options and bag overlays.
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.UI = {}

local UIPanel = UI.Panels.UI

function UIPanel:Create(parent)
    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- ============================================================
    -- UI OPTIONS CARD
    -- ============================================================
    local uiCard = UI:CreateCard(content, {
        title = "UI Options",
        description = "Configure InventoryManager UI behavior and bag overlays.",
    })

    -- Minimap button checkbox
    local minimapCheck = uiCard:AddCheckbox("Show minimap button", IM.db.global.ui.showMinimapButton)
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

    -- Auto-open checkbox
    local autoOpenCheck = uiCard:AddCheckbox("Auto-open panel at merchant", IM.db.global.ui.autoOpenOnMerchant)
    autoOpenCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.autoOpenOnMerchant = value
    end

    -- Tooltip checkbox with hint
    local tooltipCheck = uiCard:AddCheckbox(
        "Show InventoryManager info in tooltips",
        IM.db.global.ui.showTooltipInfo,
        "|cff666666Shows category, classID_subclassID, and lock status|r"
    )
    tooltipCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showTooltipInfo = value
    end

    content:AdvanceY(uiCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- BAG OVERLAYS CARD
    -- ============================================================
    local overlayCard = UI:CreateCard(content, {
        title = "Bag Overlays",
        description = "Visual indicators on items in your bags. Alt+Click to lock, Ctrl+Alt+Click to mark as junk.",
    })

    -- Lock overlay (red)
    local lockCheck = overlayCard:AddCheckbox(
        "Show lock overlay (protected items)",
        IM.db.global.ui.showLockOverlay ~= false,
        "|cffff6666Red border|r - Items that won't be auto-sold or deleted"
    )
    lockCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showLockOverlay = value
        IM:RefreshAllUI()
    end

    -- Sell overlay (green)
    local sellCheck = overlayCard:AddCheckbox(
        "Show sell overlay (auto-sell items)",
        IM.db.global.ui.showSellOverlay ~= false,
        "|cff66ff66Green border|r - Items that will be sold at vendor"
    )
    sellCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showSellOverlay = value
        IM:RefreshAllUI()
    end

    -- Mail overlay (blue)
    local mailCheck = overlayCard:AddCheckbox(
        "Show mail overlay (mail rule items)",
        IM.db.global.ui.showMailOverlay ~= false,
        "|cff6699ffBlue border|r - Items matching mail helper rules"
    )
    mailCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showMailOverlay = value
        IM:RefreshAllUI()
    end

    -- Unsellable overlay (gray)
    local unsellableCheck = overlayCard:AddCheckbox(
        "Show unsellable indicator",
        IM.db.global.ui.showUnsellableIndicator ~= false,
        "|cff888888Gray border|r - Items with no vendor value (can't be sold)"
    )
    unsellableCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.ui.showUnsellableIndicator = value
        IM:RefreshAllUI()
    end

    content:AdvanceY(overlayCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Tips",
    })

    tipsCard:AddText("- Overlays update automatically when you open bags or visit vendors")
    tipsCard:AddText("- Lock overlay takes priority over other overlays")
    tipsCard:AddText("- Tooltip info shows classID_subclassID and lock status")
    tipsCard:AddText("- Minimap button can be hidden if you use /im")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.cardSpacing)

    content:FinalizeHeight()
end
