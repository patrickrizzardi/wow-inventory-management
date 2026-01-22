--[[
    InventoryManager - UI/Panels/Dashboard.lua
    Settings panel for Dashboard features: Ledger, Net Worth, and Inventory Search.

    Design Standard (based on Currency panel):
    1. Feature Card - Amber-tinted box with accent border explaining the feature
    2. Settings Sections - Darker cards for grouped settings
    3. Tips Section - At the bottom with helpful hints
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Dashboard = {}

local DashboardPanel = UI.Panels.Dashboard

-- Store references to dynamic elements for refresh
local _dynamicElements = {}

-- Module-level references for cross-function access
local _refs = {
    purgeBtn = nil,
}

-- Helper to get purge button text based on retention
local function GetPurgeButtonText(days)
    if days > 0 then
        return "Purge >" .. days .. " Days"
    else
        return "Purge (N/A)"
    end
end

-- Refresh dynamic values (called on show and when data changes)
local function RefreshDynamicValues()
    if not _dynamicElements.charCountLabel then return end

    -- Character count
    local charCount = 0
    if IM.db and IM.db.global and IM.db.global.characters then
        for _ in pairs(IM.db.global.characters) do
            charCount = charCount + 1
        end
    end
    _dynamicElements.charCountLabel:SetText("Characters tracked: |cffffd700" .. charCount .. "|r")

    -- Warband bank gold
    local gold = IM:GetWarbandBankGold() or 0
    _dynamicElements.warbankLabel:SetText("Warband Bank Gold: |cffffd700" .. IM:FormatMoney(gold) .. "|r")

    -- Warband bank last updated
    local updated = IM:GetWarbandBankGoldUpdated()
    if updated and updated > 0 then
        _dynamicElements.warbankHint:SetText("|cff666666Last updated: " .. date("%m/%d %H:%M", updated) .. " - Open bank to refresh|r")
    else
        _dynamicElements.warbankHint:SetText("|cff666666Open the bank to fetch current value|r")
    end

    -- Snapshot count
    local snapshotCount = 0
    if IM.db and IM.db.global and IM.db.global.inventorySnapshots then
        for _ in pairs(IM.db.global.inventorySnapshots) do
            snapshotCount = snapshotCount + 1
        end
    end
    _dynamicElements.snapshotLabel:SetText("Characters with inventory data: |cffffd700" .. snapshotCount .. "|r")
end

-- Create the Dashboard settings panel
function DashboardPanel:Create(parent)
    -- Create scroll frame for all content (fill mode - resizes with panel)
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = 0

    -- ============================================================
    -- FEATURE CARD: Dashboard Overview
    -- ============================================================
    local featureCard = UI:CreateFeatureCard(content, yOffset, 80)

    local featureTitle = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -8)
    featureTitle:SetText(UI:ColorText("Dashboard & Tracking", "accent"))

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -26)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetText("Track gold, transactions, and inventory across all characters.")
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    -- Quick access buttons inside feature card
    local dashboardBtn = UI:CreateButton(featureCard, "Dashboard", 90, 22)
    dashboardBtn:SetPoint("BOTTOMLEFT", 10, 8)
    dashboardBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Dashboard then
            IM.UI.Dashboard:Show()
        end
    end)

    local networthBtn = UI:CreateButton(featureCard, "Net Worth", 80, 22)
    networthBtn:SetPoint("LEFT", dashboardBtn, "RIGHT", 4, 0)
    networthBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Dashboard then
            IM.UI.Dashboard:Show()
            C_Timer.After(0.1, function()
                if _G["InventoryManagerDashboard"] and _G["InventoryManagerDashboard"].SelectTab then
                    _G["InventoryManagerDashboard"].SelectTab("networth")
                end
            end)
        end
    end)

    local ledgerBtn = UI:CreateButton(featureCard, "Ledger", 60, 22)
    ledgerBtn:SetPoint("LEFT", networthBtn, "RIGHT", 4, 0)
    ledgerBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Dashboard then
            IM.UI.Dashboard:Show()
            C_Timer.After(0.1, function()
                if _G["InventoryManagerDashboard"] and _G["InventoryManagerDashboard"].SelectTab then
                    _G["InventoryManagerDashboard"].SelectTab("ledger")
                end
            end)
        end
    end)

    local inventoryBtn = UI:CreateButton(featureCard, "Inventory", 70, 22)
    inventoryBtn:SetPoint("LEFT", ledgerBtn, "RIGHT", 4, 0)
    inventoryBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Dashboard then
            IM.UI.Dashboard:Show()
            C_Timer.After(0.1, function()
                if _G["InventoryManagerDashboard"] and _G["InventoryManagerDashboard"].SelectTab then
                    _G["InventoryManagerDashboard"].SelectTab("inventory")
                end
            end)
        end
    end)

    yOffset = yOffset - 90  -- 80 card + 10 padding

    -- ============================================================
    -- SETTINGS CARD: Ledger Settings
    -- ============================================================
    local ledgerHeader = UI:CreateSectionHeader(content, "Ledger Settings")
    ledgerHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local ledgerCard = UI:CreateSettingsCard(content, yOffset, 210)  -- Increased for 4 rows of checkboxes

    -- Retention period row
    local retentionLabel = ledgerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    retentionLabel:SetPoint("TOPLEFT", 10, -10)
    retentionLabel:SetText("Retention Period:")
    retentionLabel:SetTextColor(unpack(UI.colors.text))

    local retentionDropdown = CreateFrame("Frame", "IM_DashboardRetentionDropdown", ledgerCard, "UIDropDownMenuTemplate")
    retentionDropdown:SetPoint("LEFT", retentionLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(retentionDropdown, 90)

    local retentionOptions = {
        { label = "7 Days", value = 7 },
        { label = "14 Days", value = 14 },
        { label = "30 Days", value = 30 },
        { label = "60 Days", value = 60 },
        { label = "90 Days", value = 90 },
        { label = "Forever", value = 0 },
    }

    -- Build label lookup to avoid closure capture issues in loop
    local retentionLabels = {}
    for _, opt in ipairs(retentionOptions) do
        retentionLabels[opt.value] = opt.label
    end

    local function RetentionDropdown_Init()
        local currentVal = IM.db.global.ledger.maxAgeDays
        for _, opt in ipairs(retentionOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.checked = (currentVal == opt.value)
            info.func = function(self)
                local selectedValue = self.value
                local selectedLabel = retentionLabels[selectedValue]
                IM.db.global.ledger.maxAgeDays = selectedValue
                UIDropDownMenu_SetText(retentionDropdown, selectedLabel)
                -- Update purge button via module-level reference
                -- Note: UI:CreateButton stores text in button.text (FontString), not button:SetText()
                if _refs.purgeBtn and _refs.purgeBtn.text then
                    _refs.purgeBtn.text:SetText(GetPurgeButtonText(selectedValue))
                    if selectedValue == 0 then
                        _refs.purgeBtn:Disable()
                    else
                        _refs.purgeBtn:Enable()
                    end
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(retentionDropdown, RetentionDropdown_Init)
    local currentRetention = IM.db.global.ledger.maxAgeDays
    UIDropDownMenu_SetText(retentionDropdown, retentionLabels[currentRetention] or "30 Days")

    -- Track transaction toggles (2 columns for better spacing)
    local trackLabel = ledgerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trackLabel:SetPoint("TOPLEFT", 10, -38)
    trackLabel:SetText("Track Transactions:")
    trackLabel:SetTextColor(unpack(UI.colors.text))

    local trackOptions = {
        { key = "trackLoot", label = "Loot" },
        { key = "trackMail", label = "Mail" },
        { key = "trackTrade", label = "Trade" },
        { key = "trackQuests", label = "Quests" },
        { key = "trackRepairs", label = "Repairs" },
        { key = "trackAH", label = "AH" },
        { key = "trackWarbank", label = "Warbank" },
    }

    local trackY = -54
    local col = 0
    for _, opt in ipairs(trackOptions) do
        local xOffset = 10 + (col * 120)  -- 120px spacing (was 100)
        local check = UI:CreateCheckbox(ledgerCard, opt.label, IM.db.global.ledger[opt.key], function(self)
            IM.db.global.ledger[opt.key] = self:GetChecked()
        end)
        check:SetPoint("TOPLEFT", ledgerCard, "TOPLEFT", xOffset, trackY)
        check:SetScale(0.9)

        col = col + 1
        if col >= 2 then  -- 2 columns (was 3) for better spacing
            col = 0
            trackY = trackY - 22
        end
    end

    -- Create purge button and store in module reference table
    local retentionDays = IM.db.global.ledger.maxAgeDays or 30
    local purgeBtn = UI:CreateButton(ledgerCard, GetPurgeButtonText(retentionDays), 130, 22)
    purgeBtn:SetPoint("BOTTOMLEFT", 10, 10)
    _refs.purgeBtn = purgeBtn  -- Store in module-level table for dropdown callback
    purgeBtn:SetScript("OnClick", function()
        local purged = IM:PurgeOldEntries()
        if purged and purged > 0 then
            IM:Print("Purged " .. purged .. " old ledger entries.")
        else
            IM:Print("No entries to purge.")
        end
    end)
    if retentionDays == 0 then
        purgeBtn:Disable()
    end

    local clearLedgerBtn = UI:CreateButton(ledgerCard, "Clear ALL", 90, 22)
    clearLedgerBtn:SetPoint("LEFT", purgeBtn, "RIGHT", 6, 0)
    clearLedgerBtn:SetScript("OnClick", function()
        StaticPopupDialogs["IM_CLEAR_LEDGER"] = {
            text = "Delete ALL ledger history? This cannot be undone.",
            button1 = "Yes",
            button2 = "Cancel",
            OnAccept = function()
                IM.db.global.transactions.entries = {}
                IM:Print("All ledger data cleared.")
                if IM.UI.Dashboard and IM.UI.Dashboard.RefreshContent then
                    IM.UI.Dashboard:RefreshContent()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("IM_CLEAR_LEDGER")
    end)

    yOffset = yOffset - 220  -- 210 card + 10 padding

    -- ============================================================
    -- SETTINGS CARD: Net Worth Settings
    -- ============================================================
    local networthHeader = UI:CreateSectionHeader(content, "Net Worth Settings")
    networthHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local networthCard = UI:CreateSettingsCard(content, yOffset, 110)

    -- Character count (dynamic)
    local charCountLabel = networthCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCountLabel:SetPoint("TOPLEFT", 10, -10)
    charCountLabel:SetText("Characters tracked: |cffffd7000|r")
    _dynamicElements.charCountLabel = charCountLabel

    -- Warband bank gold (dynamic)
    local warbankLabel = networthCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warbankLabel:SetPoint("TOPLEFT", 10, -28)
    warbankLabel:SetText("Warband Bank Gold: |cffffd7000g|r")
    _dynamicElements.warbankLabel = warbankLabel

    local warbankHint = networthCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warbankHint:SetPoint("TOPLEFT", 10, -44)
    warbankHint:SetText("|cff666666Open the bank to fetch current value|r")
    _dynamicElements.warbankHint = warbankHint

    -- Clear Net Worth button
    local clearNetworthBtn = UI:CreateButton(networthCard, "Clear Character Data", 150, 22)
    clearNetworthBtn:SetPoint("BOTTOMLEFT", 10, 10)
    clearNetworthBtn:SetScript("OnClick", function()
        StaticPopupDialogs["IM_CLEAR_NETWORTH"] = {
            text = "Delete ALL character tracking data? This cannot be undone.",
            button1 = "Yes",
            button2 = "Cancel",
            OnAccept = function()
                IM.db.global.characters = {}
                IM.db.global.warbandBankGold = 0
                IM.db.global.warbandBankGoldUpdated = 0
                IM:Print("All character tracking data cleared.")
                if IM.UI.Dashboard and IM.UI.Dashboard.RefreshContent then
                    IM.UI.Dashboard:RefreshContent()
                end
                RefreshDynamicValues()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("IM_CLEAR_NETWORTH")
    end)

    yOffset = yOffset - 120

    -- ============================================================
    -- SETTINGS CARD: Inventory Search Settings
    -- ============================================================
    local invHeader = UI:CreateSectionHeader(content, "Inventory Search Settings")
    invHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local invCard = UI:CreateSettingsCard(content, yOffset, 100)

    -- Snapshot count (dynamic)
    local snapshotLabel = invCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    snapshotLabel:SetPoint("TOPLEFT", 10, -10)
    snapshotLabel:SetText("Characters with inventory data: |cffffd7000|r")
    _dynamicElements.snapshotLabel = snapshotLabel

    -- Login hint
    local invHint = invCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    invHint:SetPoint("TOPLEFT", 10, -28)
    invHint:SetText("|cffccaa00Note: Log into each character to scan their inventory.|r")

    -- Rescan and Clear buttons
    local rescanBtn = UI:CreateButton(invCard, "Rescan Current", 120, 22)
    rescanBtn:SetPoint("BOTTOMLEFT", 10, 10)
    rescanBtn:SetScript("OnClick", function()
        if IM.modules.InventorySnapshot then
            IM.modules.InventorySnapshot:RescanCurrentCharacter()
            IM:Print("Inventory rescan triggered.")
            RefreshDynamicValues()
        end
    end)

    local clearInvBtn = UI:CreateButton(invCard, "Clear ALL", 90, 22)
    clearInvBtn:SetPoint("LEFT", rescanBtn, "RIGHT", 6, 0)
    clearInvBtn:SetScript("OnClick", function()
        StaticPopupDialogs["IM_CLEAR_INVENTORY"] = {
            text = "Delete ALL inventory snapshot data? This cannot be undone.",
            button1 = "Yes",
            button2 = "Cancel",
            OnAccept = function()
                IM.db.global.inventorySnapshots = {}
                IM.db.global.warbandBankInventory = { timestamp = 0, items = {} }
                IM:Print("All inventory snapshot data cleared.")
                if IM.UI.Dashboard and IM.UI.Dashboard.RefreshContent then
                    IM.UI.Dashboard:RefreshContent()
                end
                RefreshDynamicValues()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("IM_CLEAR_INVENTORY")
    end)

    yOffset = yOffset - 110

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
        "- Bags scan automatically on login and when changed\n" ..
        "- Bank/Warband bank update when you open them\n" ..
        "- Ledger tracks gold only, not item transfers (yet)\n" ..
        "- Use /im or the minimap button to open Dashboard\n" ..
        "|r"
    )

    yOffset = yOffset - 70

    -- Set content height for scroll frame
    content:SetHeight(math.abs(yOffset) + 20)

    -- Refresh dynamic values on scroll frame show
    scrollFrame:SetScript("OnShow", function()
        RefreshDynamicValues()
    end)

    -- Initial refresh
    RefreshDynamicValues()
end
