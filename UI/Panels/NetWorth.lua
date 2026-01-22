--[[
    InventoryManager - UI/Panels/NetWorth.lua
    Net Worth info panel - describes the feature and links to Dashboard.
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.NetWorth = {}

local NetWorthPanel = UI.Panels.NetWorth

function NetWorthPanel:Create(parent)
    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()

    local yOffset = 0

    -- Title
    local title = UI:CreateSectionHeader(content, "Account Net Worth")
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
        edgeSize = 1,
    })
    descBox:SetBackdropColor(0.12, 0.10, 0.06, 0.9)
    descBox:SetBackdropBorderColor(unpack(UI.colors.accent))

    local featureTitle = descBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -10)
    featureTitle:SetText(UI:ColorText("Account-Wide Wealth Tracking", "accent"))

    local featureDesc = descBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -30)
    featureDesc:SetPoint("RIGHT", descBox, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetSpacing(3)
    featureDesc:SetText(
        "Tracks gold and inventory value across all characters:\n" ..
        "• Gold balance updated on login/logout\n" ..
        "• Inventory value (vendor prices) from bags and bank\n" ..
        "• Warband Bank gold (auto-updates when bank opened)\n" ..
        "• Characters sorted by net worth"
    )
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 110

    -- Open Dashboard button
    local dashBtn = UI:CreateButton(content, "Open Dashboard", 140, 28)
    dashBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    dashBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Dashboard then
            IM.UI.Dashboard:Show()
            -- Select Net Worth tab
            C_Timer.After(0.1, function()
                if _G["InventoryManagerDashboard"] and _G["InventoryManagerDashboard"].SelectTab then
                    _G["InventoryManagerDashboard"].SelectTab("networth")
                end
            end)
        end
    end)

    local dashDesc = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dashDesc:SetPoint("LEFT", dashBtn, "RIGHT", 10, 0)
    dashDesc:SetText("|cff888888or type |cffffff00/im d|r|cff888888 to open|r")

    yOffset = yOffset - 50

    -- How it works section
    local howTitle = UI:CreateSectionHeader(content, "How It Works")
    howTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 25

    local howBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    howBox:SetHeight(110)
    howBox:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    howBox:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    howBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    howBox:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
    howBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local howDesc = howBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    howDesc:SetPoint("TOPLEFT", 10, -10)
    howDesc:SetPoint("RIGHT", howBox, "RIGHT", -10, 0)
    howDesc:SetJustifyH("LEFT")
    howDesc:SetSpacing(3)
    howDesc:SetText(
        UI:ColorText("Gold:", "accent") .. " Captured automatically when you log in or out\n\n" ..
        UI:ColorText("Inventory:", "accent") .. " Scanned from bags on login, bank when opened\n" ..
        "Uses vendor sell prices for valuation\n\n" ..
        UI:ColorText("Warband Bank:", "accent") .. " Auto-updates when you open your bank\n" ..
        "(Open any bank to refresh Warband gold)"
    )
    howDesc:SetTextColor(0.8, 0.8, 0.8)

    yOffset = yOffset - 125

    -- Warband Bank section
    local warbandTitle = UI:CreateSectionHeader(content, "Warband Bank Gold")
    warbandTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Current value display
    local currentLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    currentLabel:SetText("Current value: ")
    currentLabel:SetTextColor(unpack(UI.colors.textDim))

    local currentValue = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentValue:SetPoint("LEFT", currentLabel, "RIGHT", 0, 0)
    content.warbandValue = currentValue

    yOffset = yOffset - 20

    -- Last updated
    local lastUpdatedLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lastUpdatedLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    lastUpdatedLabel:SetTextColor(unpack(UI.colors.textDim))
    content.lastUpdatedLabel = lastUpdatedLabel

    yOffset = yOffset - 25

    -- Info text
    local infoText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    infoText:SetText("|cff888888Open any bank to auto-update this value|r")

    -- Store content reference for refresh
    NetWorthPanel.content = content

    -- Initial refresh
    C_Timer.After(0.1, function()
        NetWorthPanel:Refresh()
    end)
end

function NetWorthPanel:Refresh()
    if not self.content then return end

    -- Update warband gold display
    local warbandGold = IM:GetWarbandBankGold()
    if self.content.warbandValue then
        self.content.warbandValue:SetText(IM:FormatMoney(warbandGold))
    end

    -- Update last updated timestamp
    local lastUpdated = IM:GetWarbandBankGoldUpdated()
    if self.content.lastUpdatedLabel then
        if lastUpdated and lastUpdated > 0 then
            self.content.lastUpdatedLabel:SetText("Last updated: " .. date("%Y-%m-%d %H:%M", lastUpdated))
        else
            self.content.lastUpdatedLabel:SetText("Last updated: Never")
        end
    end
end
