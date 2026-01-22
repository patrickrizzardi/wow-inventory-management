--[[
    InventoryManager - UI/Panels/General.lua
    General settings panel - main feature toggles and UI options.

    Design Standard:
    - Feature card (amber) at top with description
    - Settings cards (dark) for grouped options
    - Tips section at bottom
    - All elements use dynamic width (TOPLEFT + RIGHT anchoring)
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.General = {}

local General = UI.Panels.General

function General:Create(parent)
    -- Create scroll frame for all content (fill mode - resizes with panel)
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = 0

    -- ============================================================
    -- FEATURE CARD: Overview
    -- ============================================================
    local featureCard = UI:CreateFeatureCard(content, yOffset, 70)

    local featureTitle = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -8)
    featureTitle:SetText(UI:ColorText("InventoryManager Settings", "accent"))

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -26)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetText("Configure auto-sell, auto-repair, UI options, and bag overlays.")
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 80

    -- ============================================================
    -- SETTINGS CARD: Main Features
    -- ============================================================
    local mainHeader = UI:CreateSectionHeader(content, "Main Features")
    mainHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local mainCard = UI:CreateSettingsCard(content, yOffset, 45)

    local autoRepairCheck = UI:CreateCheckbox(mainCard, "Enable Auto-Repair", IM.db.global.autoRepairEnabled)
    autoRepairCheck:SetPoint("TOPLEFT", mainCard, "TOPLEFT", 10, -10)
    autoRepairCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoRepairEnabled = value
        IM:Print("Auto-Repair: " .. (value and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    end

    yOffset = yOffset - 55

    -- ============================================================
    -- SETTINGS CARD: Repair Options
    -- ============================================================
    local repairHeader = UI:CreateSectionHeader(content, "Repair Options")
    repairHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local repairCard = UI:CreateSettingsCard(content, yOffset, 70)

    local guildFundsCheck = UI:CreateCheckbox(repairCard, "Use guild funds first", IM.db.global.repair.useGuildFunds)
    guildFundsCheck:SetPoint("TOPLEFT", repairCard, "TOPLEFT", 10, -10)
    guildFundsCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.repair.useGuildFunds = value
    end

    local fallbackCheck = UI:CreateCheckbox(repairCard, "Fallback to personal gold", IM.db.global.repair.fallbackToPersonal)
    fallbackCheck:SetPoint("TOPLEFT", repairCard, "TOPLEFT", 10, -35)
    fallbackCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.repair.fallbackToPersonal = value
    end

    yOffset = yOffset - 80

    -- ============================================================
    -- SETTINGS CARD: Developer
    -- ============================================================
    local devHeader = UI:CreateSectionHeader(content, "Developer")
    devHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local devCard = UI:CreateSettingsCard(content, yOffset, 100)

    local debugCheck = UI:CreateCheckbox(devCard, "Enable debug logging", IM.db.global.debug)
    debugCheck:SetPoint("TOPLEFT", devCard, "TOPLEFT", 10, -10)
    debugCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.debug = value
        IM:Print("Debug mode " .. (value and "enabled" or "disabled"))
    end

    local debugHint = devCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    debugHint:SetPoint("TOPLEFT", devCard, "TOPLEFT", 30, -32)
    debugHint:SetText("|cff666666Shows detailed logging in chat for troubleshooting|r")

    local copyDebugBtn = UI:CreateButton(devCard, "Copy Debug Log", 120, 24)
    copyDebugBtn:SetPoint("TOPLEFT", devCard, "TOPLEFT", 10, -58)
    copyDebugBtn:SetScript("OnClick", function()
        local text = IM:GetDebugLogString()
        local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        popup:SetSize(400, 300)
        popup:SetPoint("CENTER")
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        popup:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        popup:SetFrameStrata("DIALOG")

        local scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 10, -10)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 35)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject("GameFontNormalSmall")
        editBox:SetWidth(360)
        editBox:SetAutoFocus(true)
        editBox:SetText(text)
        editBox:HighlightText()
        editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
        editBox:SetScript("OnTextChanged", function(self)
            -- Calculate height based on line count
            local numLines = select(2, self:GetText():gsub("\n", "\n")) + 1
            local lineHeight = select(2, self:GetFont()) or 12
            local height = math.max(100, (numLines * lineHeight) + 20)
            self:SetHeight(height)
            scrollFrame:SetVerticalScroll(0)
        end)

        scrollFrame:SetScrollChild(editBox)

        local closeX = CreateFrame("Button", nil, popup)
        closeX:SetSize(18, 18)
        closeX:SetPoint("TOPRIGHT", -6, -6)
        closeX.text = closeX:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        closeX.text:SetPoint("CENTER")
        closeX.text:SetText("|cffff6666X|r")
        closeX:SetScript("OnClick", function() popup:Hide() end)
        closeX:SetScript("OnEnter", function(self)
            self.text:SetText("|cffff0000X|r")
        end)
        closeX:SetScript("OnLeave", function(self)
            self.text:SetText("|cffff6666X|r")
        end)

        local closeBtn = UI:CreateButton(popup, "Close", 60, 22)
        closeBtn:SetPoint("BOTTOM", 0, 5)
        closeBtn:SetScript("OnClick", function() popup:Hide() end)

        popup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide() end
        end)
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
        "- Use /im to open the settings panel\n" ..
        "- Use /im dashboard to open the Dashboard directly\n" ..
        "- Overlays update immediately when toggled\n" ..
        "|r"
    )

    yOffset = yOffset - 60

    -- Set content height for scroll frame
    content:SetHeight(math.abs(yOffset) + 20)
end
