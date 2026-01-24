--[[
    InventoryManager - UI/Panels/Dashboard.lua
    Settings panel for Dashboard features: Ledger, Net Worth, and Inventory Search.
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Dashboard = {}

local DashboardPanel = UI.Panels.Dashboard

-- Store references to dynamic elements for refresh
local _dynamicElements = {}
local _refs = { purgeBtn = nil }

-- Helper to get purge button text based on retention
local function GetPurgeButtonText(days)
    return days > 0 and ("Purge >" .. days .. " Days") or "Purge (N/A)"
end

-- Refresh dynamic values
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

function DashboardPanel:Create(parent)
    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- ============================================================
    -- DASHBOARD OVERVIEW CARD
    -- ============================================================
    local mainCard = UI:CreateCard(content, {
        title = "Dashboard & Tracking",
        description = "Track gold, transactions, and inventory across all characters.",
    })

    -- Quick access buttons
    local btnY = mainCard:AddContent(30)
    local dashboardBtn = UI:CreateButton(mainCard, "Dashboard", 90, 22)
    dashboardBtn:SetPoint("TOPLEFT", mainCard, "TOPLEFT", mainCard._leftPadding, btnY)
    dashboardBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Dashboard then IM.UI.Dashboard:Show() end
    end)

    local networthBtn = UI:CreateButton(mainCard, "Net Worth", 80, 22)
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

    local ledgerBtn = UI:CreateButton(mainCard, "Ledger", 60, 22)
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

    local inventoryBtn = UI:CreateButton(mainCard, "Inventory", 70, 22)
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

    content:AdvanceY(mainCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- LEDGER SETTINGS CARD
    -- ============================================================
    local ledgerCard = UI:CreateCard(content, {
        title = "Ledger Settings",
        description = "Configure transaction tracking and data retention.",
    })

    -- Retention period dropdown
    local retentionY = ledgerCard:AddContent(32)
    local retentionLabel = ledgerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    retentionLabel:SetPoint("TOPLEFT", ledgerCard, "TOPLEFT", ledgerCard._leftPadding, retentionY)
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
                IM.db.global.ledger.maxAgeDays = selectedValue
                UIDropDownMenu_SetText(retentionDropdown, retentionLabels[selectedValue])
                if _refs.purgeBtn and _refs.purgeBtn.text then
                    _refs.purgeBtn.text:SetText(GetPurgeButtonText(selectedValue))
                    if selectedValue == 0 then _refs.purgeBtn:Disable() else _refs.purgeBtn:Enable() end
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(retentionDropdown, RetentionDropdown_Init)
    UIDropDownMenu_SetText(retentionDropdown, retentionLabels[IM.db.global.ledger.maxAgeDays] or "30 Days")

    -- Track transaction toggles
    local trackLabelY = ledgerCard:AddContent(24)
    local trackLabel = ledgerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trackLabel:SetPoint("TOPLEFT", ledgerCard, "TOPLEFT", ledgerCard._leftPadding, trackLabelY)
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

    local trackY = ledgerCard:AddContent(90)  -- Space for 4 rows of checkboxes
    local col = 0
    local rowOffset = 0
    for _, opt in ipairs(trackOptions) do
        local xOffset = ledgerCard._leftPadding + (col * 120)
        local check = UI:CreateCheckbox(ledgerCard, opt.label, IM.db.global.ledger[opt.key])
        check:SetPoint("TOPLEFT", ledgerCard, "TOPLEFT", xOffset, trackY + rowOffset)
        check:SetScale(0.9)
        check.checkbox.OnValueChanged = function(self, value)
            IM.db.global.ledger[opt.key] = value
        end
        col = col + 1
        if col >= 2 then
            col = 0
            rowOffset = rowOffset - 22
        end
    end

    -- Purge and Clear buttons
    local purgeY = ledgerCard:AddContent(32)
    local retentionDays = IM.db.global.ledger.maxAgeDays or 30
    local purgeBtn = UI:CreateButton(ledgerCard, GetPurgeButtonText(retentionDays), 130, 22)
    purgeBtn:SetPoint("TOPLEFT", ledgerCard, "TOPLEFT", ledgerCard._leftPadding, purgeY)
    _refs.purgeBtn = purgeBtn
    purgeBtn:SetScript("OnClick", function()
        local purged = IM:PurgeOldEntries()
        IM:Print(purged and purged > 0 and ("Purged " .. purged .. " old entries.") or "No entries to purge.")
    end)
    if retentionDays == 0 then purgeBtn:Disable() end

    local clearLedgerBtn = UI:CreateButton(ledgerCard, "Clear ALL", 90, 22)
    clearLedgerBtn:SetPoint("LEFT", purgeBtn, "RIGHT", 6, 0)
    clearLedgerBtn:SetScript("OnClick", function()
        StaticPopupDialogs["IM_CLEAR_LEDGER"] = {
            text = "Delete ALL ledger history? This cannot be undone.",
            button1 = "Yes", button2 = "Cancel",
            OnAccept = function()
                IM.db.global.transactions.entries = {}
                IM:Print("All ledger data cleared.")
                if IM.UI.Dashboard and IM.UI.Dashboard.RefreshContent then IM.UI.Dashboard:RefreshContent() end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("IM_CLEAR_LEDGER")
    end)

    content:AdvanceY(ledgerCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- NET WORTH SETTINGS CARD
    -- ============================================================
    local networthCard = UI:CreateCard(content, {
        title = "Net Worth Settings",
        description = "Manage character tracking data.",
    })

    -- Dynamic labels
    local charY = networthCard:AddContent(20)
    local charCountLabel = networthCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCountLabel:SetPoint("TOPLEFT", networthCard, "TOPLEFT", networthCard._leftPadding, charY)
    _dynamicElements.charCountLabel = charCountLabel

    local warbankY = networthCard:AddContent(18)
    local warbankLabel = networthCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warbankLabel:SetPoint("TOPLEFT", networthCard, "TOPLEFT", networthCard._leftPadding, warbankY)
    _dynamicElements.warbankLabel = warbankLabel

    local warbankHintY = networthCard:AddContent(18)
    local warbankHint = networthCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warbankHint:SetPoint("TOPLEFT", networthCard, "TOPLEFT", networthCard._leftPadding, warbankHintY)
    _dynamicElements.warbankHint = warbankHint

    -- Clear button
    local clearNWY = networthCard:AddContent(32)
    local clearNetworthBtn = UI:CreateButton(networthCard, "Clear Character Data", 150, 22)
    clearNetworthBtn:SetPoint("TOPLEFT", networthCard, "TOPLEFT", networthCard._leftPadding, clearNWY)
    clearNetworthBtn:SetScript("OnClick", function()
        StaticPopupDialogs["IM_CLEAR_NETWORTH"] = {
            text = "Delete ALL character tracking data?",
            button1 = "Yes", button2 = "Cancel",
            OnAccept = function()
                IM.db.global.characters = {}
                IM.db.global.warbandBankGold = 0
                IM.db.global.warbandBankGoldUpdated = 0
                IM:Print("All character tracking data cleared.")
                if IM.UI.Dashboard and IM.UI.Dashboard.RefreshContent then IM.UI.Dashboard:RefreshContent() end
                RefreshDynamicValues()
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("IM_CLEAR_NETWORTH")
    end)

    content:AdvanceY(networthCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- INVENTORY SEARCH CARD
    -- ============================================================
    local invCard = UI:CreateCard(content, {
        title = "Inventory Search Settings",
        description = "Manage inventory snapshot data across characters.",
    })

    local snapY = invCard:AddContent(20)
    local snapshotLabel = invCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    snapshotLabel:SetPoint("TOPLEFT", invCard, "TOPLEFT", invCard._leftPadding, snapY)
    _dynamicElements.snapshotLabel = snapshotLabel

    local hintY = invCard:AddContent(18)
    local invHint = invCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    invHint:SetPoint("TOPLEFT", invCard, "TOPLEFT", invCard._leftPadding, hintY)
    invHint:SetText("|cffccaa00Note: Log into each character to scan their inventory.|r")

    local invBtnY = invCard:AddContent(32)
    local rescanBtn = UI:CreateButton(invCard, "Rescan Current", 120, 22)
    rescanBtn:SetPoint("TOPLEFT", invCard, "TOPLEFT", invCard._leftPadding, invBtnY)
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
            text = "Delete ALL inventory snapshot data?",
            button1 = "Yes", button2 = "Cancel",
            OnAccept = function()
                IM.db.global.inventorySnapshots = {}
                IM.db.global.warbandBankInventory = { timestamp = 0, items = {} }
                IM:Print("All inventory snapshot data cleared.")
                if IM.UI.Dashboard and IM.UI.Dashboard.RefreshContent then IM.UI.Dashboard:RefreshContent() end
                RefreshDynamicValues()
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("IM_CLEAR_INVENTORY")
    end)

    content:AdvanceY(invCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Tips",
    })

    tipsCard:AddText("- Bags scan automatically on login and when changed")
    tipsCard:AddText("- Bank/Warband bank update when you open them")
    tipsCard:AddText("- Ledger tracks gold only, not item transfers (yet)")
    tipsCard:AddText("- Use /im or the minimap button to open Dashboard")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.spacing)

    content:FinalizeHeight()

    -- Refresh on show
    scrollFrame:SetScript("OnShow", RefreshDynamicValues)
    RefreshDynamicValues()
end
