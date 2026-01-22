--[[
    InventoryManager - UI/Panels/Currency.lua
    Currency enhancement info panel - no settings, just describes the feature.

    Design Standard:
    - Feature card (amber) at top with description
    - Settings cards (dark) for info sections
    - Tips section at bottom
    - All elements use dynamic width (TOPLEFT + RIGHT anchoring)
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Currency = {}

local CurrencyPanel = UI.Panels.Currency

function CurrencyPanel:Create(parent)
    -- Create scroll frame for all content
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = 0

    -- ============================================================
    -- FEATURE CARD: Currency Search
    -- ============================================================
    local featureCard = UI:CreateFeatureCard(content, yOffset, 100)

    local featureTitle = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -8)
    featureTitle:SetText(UI:ColorText("Currency Search Enhancement", "accent"))

    -- Get the character info keybind dynamically
    local charKey = GetBindingKey("TOGGLECHARACTER0") or "C"

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -28)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetSpacing(2)
    featureDesc:SetText(
        "Adds a search bar to Blizzard's Currency tab.\n" ..
        "Open Character Info (|cffffff00" .. charKey .. "|r) > Currency tab to use it.\n" ..
        "Matching currencies are highlighted, non-matches dimmed."
    )
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 110

    -- ============================================================
    -- SETTINGS CARD: No Settings Notice
    -- ============================================================
    local infoHeader = UI:CreateSectionHeader(content, "Configuration")
    infoHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local infoCard = UI:CreateSettingsCard(content, yOffset, 50)

    local infoText = infoCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("CENTER")
    infoText:SetText("|cff888888This feature has no configurable settings.\nIt automatically enhances the default Currency UI.|r")

    yOffset = yOffset - 60

    -- ============================================================
    -- TIPS SECTION
    -- ============================================================
    local tipsHeader = UI:CreateSectionHeader(content, "Currency Tips")
    tipsHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 22

    local tipsText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipsText:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    tipsText:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    tipsText:SetJustifyH("LEFT")
    tipsText:SetSpacing(2)
    tipsText:SetText(
        "|cffaaaaaa" ..
        "- Right-click a currency to link it in chat\n" ..
        "- Some currencies can be transferred between characters\n" ..
        "- Use the backpack checkbox to show currencies on your backpack bar\n" ..
        "|r"
    )

    yOffset = yOffset - 60

    -- Set content height
    content:SetHeight(math.abs(yOffset) + 20)
end

function CurrencyPanel:Refresh()
    -- Nothing to refresh
end
