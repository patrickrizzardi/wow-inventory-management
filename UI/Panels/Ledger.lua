--[[
    InventoryManager - UI/Panels/Ledger.lua
    Ledger info panel - describes the feature and links to Dashboard.
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Ledger = {}

local LedgerPanel = UI.Panels.Ledger

function LedgerPanel:Create(parent)
    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()

    local yOffset = 0

    -- Title
    local title = UI:CreateSectionHeader(content, "Transaction Ledger")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Feature description box
    local descBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    descBox:SetHeight(100)
    descBox:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    descBox:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    descBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    descBox:SetBackdropColor(0.12, 0.10, 0.06, 0.9)
    descBox:SetBackdropBorderColor(unpack(UI.colors.accent))

    local featureTitle = descBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -10)
    featureTitle:SetText(UI:ColorText("Gold Transaction History", "accent"))

    local featureDesc = descBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -30)
    featureDesc:SetPoint("RIGHT", descBox, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetSpacing(3)
    featureDesc:SetText(
        "Tracks all gold transactions across your characters:\n" ..
        "• Vendor sales and purchases\n" ..
        "• Auction House income and expenses\n" ..
        "• Mail sent and received gold\n" ..
        "• Quest rewards, loot, repairs, and trades"
    )
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 110

    -- Open Dashboard button
    local dashBtn = UI:CreateButton(content, "Open Dashboard", 140, 28)
    dashBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    dashBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Dashboard then
            IM.UI.Dashboard:Show()
            -- Select Ledger tab
            if IM.UI.Dashboard.SelectTab then
                C_Timer.After(0.1, function()
                    _G["InventoryManagerDashboard"].SelectTab("ledger")
                end)
            end
        end
    end)

    local dashDesc = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dashDesc:SetPoint("LEFT", dashBtn, "RIGHT", 10, 0)
    dashDesc:SetText("|cff888888or type |cffffff00/im d|r|cff888888 to open|r")

    yOffset = yOffset - 50

    -- Filter help section
    local filterTitle = UI:CreateSectionHeader(content, "Dashboard Filters")
    filterTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 25

    local filterBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    filterBox:SetHeight(130)
    filterBox:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    filterBox:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    filterBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    filterBox:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
    filterBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local filterDesc = filterBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterDesc:SetPoint("TOPLEFT", 10, -10)
    filterDesc:SetPoint("RIGHT", filterBox, "RIGHT", -10, 0)
    filterDesc:SetJustifyH("LEFT")
    filterDesc:SetSpacing(3)
    filterDesc:SetText(
        UI:ColorText("Type Filter:", "accent") .. " Show specific transaction types\n" ..
        "  All Types, Income Only, Expenses Only, Vendor, AH, Mail, etc.\n\n" ..
        UI:ColorText("Date Filter:", "accent") .. " Limit to time range\n" ..
        "  This Session, Today, This Week, This Month, All Time\n\n" ..
        UI:ColorText("Character Filter:", "accent") .. " Show one character's transactions\n\n" ..
        UI:ColorText("Search:", "accent") .. " Filter by item name, character, or source"
    )
    filterDesc:SetTextColor(0.8, 0.8, 0.8)

    yOffset = yOffset - 145

    -- Data management section
    local dataTitle = UI:CreateSectionHeader(content, "Data Management")
    dataTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Clear history button
    local clearBtn = UI:CreateButton(content, "Clear All History", 120, 24)
    clearBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("INVENTORYMANAGER_CLEAR_LEDGER")
    end)

    local clearDesc = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearDesc:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    clearDesc:SetText("|cffff6666Permanently deletes all transaction history|r")

    -- Clear confirmation popup
    StaticPopupDialogs["INVENTORYMANAGER_CLEAR_LEDGER"] = {
        text = "Clear ALL transaction history?\n\nThis cannot be undone.",
        button1 = "Yes, Clear",
        button2 = "Cancel",
        OnAccept = function()
            IM:ClearTransactions()
            IM:Print("Transaction history cleared.")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

function LedgerPanel:Refresh()
    -- No dynamic content to refresh in info panel
end
