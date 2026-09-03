--[[
    InventoryManager - UI/Panels/MailHelper.lua
    Mail helper configuration panel - simplified rule-based mail routing.
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.MailHelper = {}

local MailHelperPanel = UI.Panels.MailHelper
local _refreshFunc = nil
local ROW_HEIGHT = 26

function MailHelperPanel:Create(parent)
    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- ============================================================
    -- CONFIGURATION CARD
    -- ============================================================
    local configCard = UI:CreateCard(content, {
        title = "Mail Helper",
        description = "Auto-queue items for mailing to alts based on item class rules.",
    })

    local enableCheck = configCard:AddCheckbox(
        "Enable Mail Helper",
        IM.db.global.mailHelper.enabled,
        UI:ColorText("Shows popup with matched items when you open a mailbox", "dim")
    )
    enableCheck.checkbox.OnValueChanged = function(self, checked)
        IM.db.global.mailHelper.enabled = checked
        if IM.modules.MailHelper then
            IM.modules.MailHelper:AutoFillQueue()
        end
        if not checked and IM.UI and IM.UI.MailPopup then
            IM.UI.MailPopup:Hide()
        end
        IM:RefreshAllUI()
    end

    content:AdvanceY(configCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- AUTO-LOOT SETTINGS CARD
    -- ============================================================
    local lootCard = UI:CreateCard(content, {
        title = "Auto-Loot Settings",
        description = "Automatically collect items and gold from your mailbox.",
    })

    local autoLootCheck = lootCard:AddCheckbox(
        "Auto-loot mail when mailbox opens",
        IM.db.global.mailHelper.autoLootOnOpen,
        UI:ColorText("Starts looting all mail automatically when you open a mailbox", "dim")
    )
    autoLootCheck.checkbox.OnValueChanged = function(self, checked)
        IM.db.global.mailHelper.autoLootOnOpen = checked
    end

    local skipCODCheck = lootCard:AddCheckbox(
        "Skip COD mail when looting",
        IM.db.global.mailHelper.skipCOD,
        UI:ColorText("Prevents accidentally paying for Cash-On-Delivery mail", "dim")
    )
    skipCODCheck.checkbox.OnValueChanged = function(self, checked)
        IM.db.global.mailHelper.skipCOD = checked
    end

    content:AdvanceY(lootCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- MAIL RULES CARD (with custom inputs and list)
    -- ============================================================
    local rulesCard = UI:CreateCard(content, {
        title = "Mail Rules",
        description = "Format: classID (e.g., 7 = all tradeskill) or classID_subclassID (e.g., 7_8 = cooking)",
    })

    -- Input row 1: Name and Filter
    local inputY = rulesCard:AddContent(32)
    
    local nameInput = CreateFrame("EditBox", nil, rulesCard, "BackdropTemplate")
    nameInput:SetSize(UI.layout.inputWidth, UI.layout.rowHeightSmall)
    nameInput:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", rulesCard._leftPadding, inputY)
    nameInput:SetFontObject("GameFontNormalSmall")
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(20)
    UI:MakeRounded(nameInput, UI.layout.radiusSmall)
    nameInput:SetBackdropColor(unpack(UI.colors.backgroundDark))
    nameInput:SetBackdropBorderColor(unpack(UI.colors.border))
    nameInput:SetTextInsets(6, 6, 0, 0)
    nameInput:SetTextColor(unpack(UI.colors.text))

    local namePlaceholder = nameInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    namePlaceholder:SetPoint("LEFT", 6, 0)
    namePlaceholder:SetText("Rule Name...")
    namePlaceholder:SetTextColor(unpack(UI.colors.textDisabled))

    nameInput:SetScript("OnEditFocusGained", function(self)
        namePlaceholder:Hide()
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)
    nameInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then namePlaceholder:Show() end
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Filter input (next to name)
    local filterInput = CreateFrame("EditBox", nil, rulesCard, "BackdropTemplate")
    filterInput:SetSize(UI.layout.inputWidthSmall, UI.layout.rowHeightSmall)
    filterInput:SetPoint("LEFT", nameInput, "RIGHT", 8, 0)
    filterInput:SetFontObject("GameFontNormalSmall")
    filterInput:SetAutoFocus(false)
    filterInput:SetMaxLetters(10)
    UI:MakeRounded(filterInput, UI.layout.radiusSmall)
    filterInput:SetBackdropColor(unpack(UI.colors.backgroundDark))
    filterInput:SetBackdropBorderColor(unpack(UI.colors.border))
    filterInput:SetTextInsets(6, 6, 0, 0)
    filterInput:SetTextColor(unpack(UI.colors.text))

    local filterPlaceholder = filterInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterPlaceholder:SetPoint("LEFT", 6, 0)
    filterPlaceholder:SetText("7 or 7_8")
    filterPlaceholder:SetTextColor(unpack(UI.colors.textDisabled))

    filterInput:SetScript("OnEditFocusGained", function(self)
        filterPlaceholder:Hide()
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)
    filterInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then filterPlaceholder:Show() end
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)
    filterInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Input row 2: Recipient with autocomplete
    local recipY = rulesCard:AddContent(32)
    
    local recipientInput = CreateFrame("EditBox", nil, rulesCard, "BackdropTemplate")
    recipientInput:SetSize(UI.layout.inputWidthLarge - 30, UI.layout.rowHeightSmall)
    recipientInput:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", rulesCard._leftPadding, recipY)
    recipientInput:SetFontObject("GameFontNormalSmall")
    recipientInput:SetAutoFocus(false)
    recipientInput:SetMaxLetters(30)
    UI:MakeRounded(recipientInput, UI.layout.radiusSmall)
    recipientInput:SetBackdropColor(unpack(UI.colors.backgroundDark))
    recipientInput:SetBackdropBorderColor(unpack(UI.colors.border))
    recipientInput:SetTextInsets(6, 6, 0, 0)
    recipientInput:SetTextColor(unpack(UI.colors.text))

    local recipientPlaceholder = recipientInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipientPlaceholder:SetPoint("LEFT", 6, 0)
    recipientPlaceholder:SetText("Recipient Alt Name")
    recipientPlaceholder:SetTextColor(unpack(UI.colors.textDisabled))

    -- Dropdown button
    local dropdownBtn = CreateFrame("Button", nil, rulesCard, "BackdropTemplate")
    dropdownBtn:SetSize(UI.layout.rowHeightSmall, UI.layout.rowHeightSmall)
    dropdownBtn:SetPoint("LEFT", recipientInput, "RIGHT", 2, 0)
    UI:MakeRounded(dropdownBtn, UI.layout.radiusSmall)
    dropdownBtn:SetBackdropColor(unpack(UI.colors.backgroundLight))
    dropdownBtn:SetBackdropBorderColor(unpack(UI.colors.border))

    local dropdownArrow = dropdownBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropdownArrow:SetPoint("CENTER")
    dropdownArrow:SetText("v")
    dropdownArrow:SetTextColor(unpack(UI.colors.textDim))

    local dropdownMenu = nil

    local function ShowAltDropdown(filterText)
        if not dropdownMenu then
            dropdownMenu = CreateFrame("Frame", nil, rulesCard, "BackdropTemplate")
            dropdownMenu:SetFrameStrata("TOOLTIP")
            UI:MakeRounded(dropdownMenu, UI.layout.radiusSmall)
            dropdownMenu:SetBackdropColor(UI.colors.backgroundDark[1], UI.colors.backgroundDark[2], UI.colors.backgroundDark[3], 0.98)
            dropdownMenu:SetBackdropBorderColor(unpack(UI.colors.accent))
            dropdownMenu:SetPoint("TOP", recipientInput, "BOTTOM", 0, -2)
            dropdownMenu.buttons = {}
        end

        for _, btn in ipairs(dropdownMenu.buttons) do btn:Hide() end

        local alts = IM.modules.MailHelper and IM.modules.MailHelper:GetAlts() or {}
        local filter = (filterText or ""):lower()
        local yOff = -2
        local count = 0

        for altKey, altData in pairs(alts) do
            local altName = altData.name or altKey:match("^(.+)-") or altKey
            if filter == "" or altName:lower():find(filter, 1, true) then
                count = count + 1
                if count <= 6 then
                    local btn = dropdownMenu.buttons[count]
                    if not btn then
                        btn = CreateFrame("Button", nil, dropdownMenu)
                        btn:SetHeight(UI.layout.iconSize)
                        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        btn.text:SetPoint("LEFT", 6, 0)
                        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
                        btn.highlight:SetAllPoints()
                        btn.highlight:SetColorTexture(unpack(UI.colors.accent))
                        btn.highlight:SetAlpha(0.3)
                        dropdownMenu.buttons[count] = btn
                    end
                    btn:SetPoint("TOPLEFT", dropdownMenu, "TOPLEFT", 2, yOff)
                    btn:SetPoint("RIGHT", dropdownMenu, "RIGHT", -2, 0)
                    local displayText = altName
                    if altData.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[altData.class] then
                        displayText = RAID_CLASS_COLORS[altData.class]:WrapTextInColorCode(altName)
                    end
                    btn.text:SetText(displayText)
                    btn.altKey = altKey
                    btn:SetScript("OnClick", function(self)
                        recipientInput:SetText(self.altKey)
                        recipientPlaceholder:Hide()
                        dropdownMenu:Hide()
                    end)
                    btn:Show()
                    yOff = yOff - 20
                end
            end
        end

        if count == 0 then dropdownMenu:Hide() return end
        dropdownMenu:SetSize(recipientInput:GetWidth(), math.abs(yOff) + 4)
        dropdownMenu:Show()
    end

    dropdownBtn:SetScript("OnClick", function()
        if dropdownMenu and dropdownMenu:IsShown() then dropdownMenu:Hide()
        else ShowAltDropdown("") end
    end)
    dropdownBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(UI.colors.surfaceRaised))
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)
    dropdownBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(UI.colors.backgroundLight))
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    recipientInput:SetScript("OnEditFocusGained", function(self)
        recipientPlaceholder:Hide()
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)
    recipientInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then recipientPlaceholder:Show() end
        self:SetBackdropBorderColor(unpack(UI.colors.border))
        C_Timer.After(0.15, function()
            if dropdownMenu and not MouseIsOver(dropdownMenu) then dropdownMenu:Hide() end
        end)
    end)
    recipientInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            local text = self:GetText()
            if text == "" then
                recipientPlaceholder:Show()
                if dropdownMenu then dropdownMenu:Hide() end
            else
                recipientPlaceholder:Hide()
                ShowAltDropdown(text)
            end
        end
    end)
    recipientInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if dropdownMenu then dropdownMenu:Hide() end
    end)

    -- Add button
    local addBtn = UI:CreateButton(rulesCard, "Add Rule", 70, 24)
    addBtn:SetPoint("LEFT", dropdownBtn, "RIGHT", 8, 0)

    -- Rules list container (inside card)
    local rulesContainer = CreateFrame("Frame", nil, rulesCard)
    rulesContainer:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", rulesCard._leftPadding, -rulesCard._contentHeight - 8)
    rulesContainer:SetPoint("RIGHT", rulesCard, "RIGHT", -rulesCard._padding, 0)
    rulesContainer:SetHeight(UI.layout.listInitialHeight)

    local noRulesLabel = rulesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noRulesLabel:SetPoint("TOPLEFT", 0, 0)
    noRulesLabel:SetText(UI:ColorText("No rules configured. Add one above.", "dim"))
    noRulesLabel:Hide()

    local function RefreshRulesList()
        for _, child in pairs({rulesContainer:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local rules = IM.modules.MailHelper and IM.modules.MailHelper:GetRules() or {}
        local listY = 0
        local hasEntries = false

        for i, rule in ipairs(rules) do
            hasEntries = true
            local row = CreateFrame("Frame", nil, rulesContainer, "BackdropTemplate")
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", 0, listY)
            row:SetPoint("RIGHT", rulesContainer, "RIGHT", 0, 0)
            UI:MakeRounded(row, UI.layout.radiusSmall)
            row:SetBackdropColor(unpack(UI.colors.background))
            row:SetBackdropBorderColor(unpack(UI.colors.borderLight))

            local enableBox = CreateFrame("CheckButton", nil, row, "BackdropTemplate")
            enableBox:SetSize(UI.layout.iconSizeSmall, UI.layout.iconSizeSmall)
            enableBox:SetPoint("LEFT", 4, 0)
            UI:MakeRounded(enableBox, UI.layout.radiusSmall)
            enableBox:SetBackdropColor(unpack(UI.colors.backgroundDark))
            enableBox:SetBackdropBorderColor(unpack(UI.colors.border))
            enableBox.check = enableBox:CreateTexture(nil, "OVERLAY")
            enableBox.check:SetSize(UI.layout.iconSizeSmall - 4, UI.layout.iconSizeSmall - 4)
            enableBox.check:SetPoint("CENTER")
            enableBox.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            enableBox.check:SetShown(rule.enabled)
            enableBox:SetChecked(rule.enabled)
            enableBox:SetScript("OnClick", function(self)
                rule.enabled = self:GetChecked()
                self.check:SetShown(rule.enabled)
                if IM.modules.MailHelper then IM.modules.MailHelper:UpdateRule(i, rule) end
                IM:RefreshAllUI()
            end)

            local filterText = rule.filterValue or "?"
            local classID, subclassID = (rule.filterValue or ""):match("^(%d+)_(%d+)$")
            if classID and subclassID then
                local className = IM.ITEM_CLASS_NAMES and IM.ITEM_CLASS_NAMES[tonumber(classID)]
                local subclassName = GetItemSubClassInfo(tonumber(classID), tonumber(subclassID))
                if className then
                    filterText = rule.filterValue .. " (" .. className
                    if subclassName and subclassName ~= "" then filterText = filterText .. ": " .. subclassName end
                    filterText = filterText .. ")"
                end
            else
                local classIDNum = tonumber(rule.filterValue)
                if classIDNum and IM.ITEM_CLASS_NAMES and IM.ITEM_CLASS_NAMES[classIDNum] then
                    filterText = rule.filterValue .. " (" .. IM.ITEM_CLASS_NAMES[classIDNum] .. ")"
                end
            end

            local altName = rule.alt and (rule.alt:match("^(.+)-") or rule.alt) or "?"
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", enableBox, "RIGHT", 6, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -30, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText((rule.name or "Unnamed") .. " " .. UI:ColorText("→ " .. altName .. " | " .. filterText, "dim"))

            local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            removeBtn:SetSize(UI.layout.buttonHeightSmall, UI.layout.buttonHeightSmall)
            removeBtn:SetPoint("RIGHT", -2, 0)
            UI:MakeRounded(removeBtn, UI.layout.radiusSmall, true)
            removeBtn:SetBackdropColor(UI.colors.error[1], UI.colors.error[2], UI.colors.error[3], 0.35)
            removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            removeBtn.text:SetPoint("CENTER")
            removeBtn.text:SetText(UI:ColorText("X", "error"))
            removeBtn:SetScript("OnClick", function()
                if IM.modules.MailHelper then IM.modules.MailHelper:RemoveRule(i) end
                IM:RefreshAllUI()
            end)
            removeBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(UI.colors.error[1], UI.colors.error[2], UI.colors.error[3], 0.75)
                self.text:SetText(UI:ColorText("X", "error"))
            end)
            removeBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(UI.colors.error[1], UI.colors.error[2], UI.colors.error[3], 0.35)
                self.text:SetText(UI:ColorText("X", "error"))
            end)

            listY = listY - (ROW_HEIGHT + 2)
        end

        if not hasEntries then
            noRulesLabel:Show()
            listY = -24
        else
            noRulesLabel:Hide()
        end

        local listHeight = math.max(math.abs(listY), 24)
        rulesContainer:SetHeight(listHeight)
        return listHeight
    end

    addBtn:SetScript("OnClick", function()
        local name = nameInput:GetText()
        local filter = filterInput:GetText()
        local recipient = recipientInput:GetText()

        if filter == "" or not (filter:match("^%d+$") or filter:match("^%d+_%d+$")) then
            IM:Print("Invalid filter. Use classID (e.g., 7) or classID_subclassID (e.g., 7_8)")
            return
        end
        if recipient == "" then IM:Print("Please enter a recipient name") return end
        if not recipient:find("-") then recipient = recipient .. "-" .. GetRealmName() end
        if name == "" then name = "Rule " .. (#(IM.modules.MailHelper:GetRules() or {}) + 1) end

        if IM.modules.MailHelper then
            IM.modules.MailHelper:AddRule({
                name = name, alt = recipient, filterType = "classID",
                filterValue = filter, enabled = true,
            })
            nameInput:SetText(""); filterInput:SetText(""); recipientInput:SetText("")
            nameInput:ClearFocus(); filterInput:ClearFocus(); recipientInput:ClearFocus()
            namePlaceholder:Show(); filterPlaceholder:Show(); recipientPlaceholder:Show()
            IM:RefreshAllUI()
        end
    end)

    nameInput:SetScript("OnEnterPressed", function() addBtn:Click() end)
    filterInput:SetScript("OnEnterPressed", function() addBtn:Click() end)
    recipientInput:SetScript("OnEnterPressed", function() addBtn:Click() end)

    -- Initial list refresh
    local rulesHeight = RefreshRulesList()
    rulesCard._contentHeight = rulesCard._contentHeight + rulesHeight + 16  -- Add padding
    rulesCard:SetHeight(rulesCard:GetContentHeight())

    content:AdvanceY(rulesCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Tips",
    })

    tipsCard:AddText("- Hover any item to see its Class ID in the tooltip")
    tipsCard:AddText("- Look for 'ID:' line (e.g., ID: 7_8 = classID=7, subclassID=8)")
    tipsCard:AddText("- Use just classID (e.g., 7) to match ALL items in that category")
    tipsCard:AddText("- The popup appears automatically when you open a mailbox")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.cardSpacing)

    content:FinalizeHeight()

    -- Full refresh function
    local function FullRefresh()
        local rulesHeight = RefreshRulesList()
        -- Recalculate card height: title + desc + inputs (64px) + list + padding
        rulesCard._contentHeight = 70 + 64 + rulesHeight + 16
        rulesCard:SetHeight(rulesCard:GetContentHeight())
    end

    _refreshFunc = FullRefresh
    parent:SetScript("OnShow", FullRefresh)
    C_Timer.After(0.1, FullRefresh)
    MailHelperPanel.Refresh = FullRefresh
end

function MailHelperPanel:Refresh()
    if _refreshFunc then _refreshFunc() end
end
