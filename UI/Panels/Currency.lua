--[[
    InventoryManager - UI/Panels/Currency.lua
    Currency enhancement info panel - describes the search feature.
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Currency = {}

local CurrencyPanel = UI.Panels.Currency

function CurrencyPanel:Create(parent)
    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- Get the character info keybind dynamically
    local charKey = GetBindingKey("TOGGLECHARACTER0") or "C"

    -- ============================================================
    -- CURRENCY SEARCH CARD
    -- ============================================================
    local featureCard = UI:CreateCard(content, {
        title = "Currency Search Enhancement",
        description = "Adds a search bar to Blizzard's Currency tab.",
    })

    featureCard:AddText("Open Character Info (|cffffff00" .. charKey .. "|r) > Currency tab to use it.")
    featureCard:AddText("Matching currencies are highlighted, non-matches dimmed.")
    featureCard:AddText(" ", 8)  -- Spacer (keep explicit height)
    featureCard:AddText("|cff888888This feature has no configurable settings.|r")
    featureCard:AddText("|cff888888It automatically enhances the default Currency UI.|r")

    content:AdvanceY(featureCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Currency Tips",
    })

    tipsCard:AddText("- Right-click a currency to link it in chat")
    tipsCard:AddText("- Some currencies can be transferred between characters")
    tipsCard:AddText("- Use the backpack checkbox to show currencies on your backpack bar")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.spacing)

    content:FinalizeHeight()
end

function CurrencyPanel:Refresh()
    -- Nothing to refresh
end
