--[[
    InventoryManager - UI/Panels/General.lua
    General settings panel - main feature toggles and repair options.
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.General = {}

local General = UI.Panels.General

function General:Create(parent)
    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- ============================================================
    -- MAIN FEATURES CARD
    -- ============================================================
    local mainCard = UI:CreateCard(content, {
        title = "Main Features",
        description = "Configure auto-sell, auto-repair, and core addon features.",
    })

    local autoRepairCheck = mainCard:AddCheckbox(
        "Enable Auto-Repair",
        IM.db.global.autoRepairEnabled,
        "|cff666666Automatically repair gear when visiting a vendor|r"
    )
    autoRepairCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoRepairEnabled = value
        IM:Print("Auto-Repair: " .. (value and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    end

    content:AdvanceY(mainCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- REPAIR OPTIONS CARD
    -- ============================================================
    local repairCard = UI:CreateCard(content, {
        title = "Repair Options",
        description = "Configure how auto-repair handles guild and personal funds.",
    })

    local guildFundsCheck = repairCard:AddCheckbox(
        "Use guild funds first",
        IM.db.global.repair.useGuildFunds,
        "|cff666666Try to use guild bank funds before personal gold|r"
    )
    guildFundsCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.repair.useGuildFunds = value
    end

    local fallbackCheck = repairCard:AddCheckbox(
        "Fallback to personal gold",
        IM.db.global.repair.fallbackToPersonal,
        "|cff666666Use personal gold if guild funds unavailable|r"
    )
    fallbackCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.repair.fallbackToPersonal = value
    end

    content:AdvanceY(repairCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- DEVELOPER CARD
    -- ============================================================
    local devCard = UI:CreateCard(content, {
        title = "Developer",
        description = "Debug and troubleshooting options.",
    })

    local debugCheck = devCard:AddCheckbox(
        "Enable debug logging",
        IM.db.global.debug,
        "|cff666666Shows detailed logging in chat for troubleshooting|r"
    )
    debugCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.debug = value
        IM:Print("Debug mode " .. (value and "enabled" or "disabled"))
    end

    -- Add copy debug log button
    local btnY = devCard:AddContent(32)
    local copyDebugBtn = UI:CreateButton(devCard, "Copy Debug Log", 120, 24)
    copyDebugBtn:SetPoint("TOPLEFT", devCard, "TOPLEFT", devCard._leftPadding, btnY)
    copyDebugBtn:SetScript("OnClick", function()
        local text = IM:GetDebugLogString()
        local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        popup:SetSize(400, 300)
        popup:SetPoint("CENTER")
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = UI.layout.borderSize,
        })
        popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        popup:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        popup:SetFrameStrata("DIALOG")

        local scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", UI.layout.cardSpacing, -UI.layout.cardSpacing)
        scrollFrame:SetPoint("BOTTOMRIGHT", -UI.layout.bottomBarHeight, UI.layout.rowHeight + UI.layout.cardSpacing)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject("GameFontNormalSmall")
        editBox:SetWidth(360)
        editBox:SetAutoFocus(true)
        editBox:SetText(text)
        editBox:HighlightText()
        editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
        editBox:SetScript("OnTextChanged", function(self)
            local numLines = select(2, self:GetText():gsub("\n", "\n")) + 1
            local lineHeight = select(2, self:GetFont()) or 12
            local height = math.max(100, (numLines * lineHeight) + UI.layout.iconSize)
            self:SetHeight(height)
            scrollFrame:SetVerticalScroll(0)
        end)

        scrollFrame:SetScrollChild(editBox)

        local closeBtnSize = UI.layout.iconSize - 2
        local closeX = CreateFrame("Button", nil, popup)
        closeX:SetSize(closeBtnSize, closeBtnSize)
        closeX:SetPoint("TOPRIGHT", -UI.layout.elementSpacing, -UI.layout.elementSpacing)
        closeX.text = closeX:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        closeX.text:SetPoint("CENTER")
        closeX.text:SetText("|cffff6666X|r")
        closeX:SetScript("OnClick", function() popup:Hide() end)
        closeX:SetScript("OnEnter", function(self) self.text:SetText("|cffff0000X|r") end)
        closeX:SetScript("OnLeave", function(self) self.text:SetText("|cffff6666X|r") end)

        local closeBtn = UI:CreateButton(popup, "Close", 60, UI.layout.buttonHeightSmall)
        closeBtn:SetPoint("BOTTOM", 0, UI.layout.paddingSmall)
        closeBtn:SetScript("OnClick", function() popup:Hide() end)

        popup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide() end
        end)
    end)

    content:AdvanceY(devCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Tips",
    })

    tipsCard:AddText("- Use /im to open the settings panel")
    tipsCard:AddText("- Use /im dashboard to open the Dashboard directly")
    tipsCard:AddText("- Overlays update immediately when toggled")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.spacing)

    content:FinalizeHeight()
end
