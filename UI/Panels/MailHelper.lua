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
        "|cff666666Shows popup with matched items when you open a mailbox|r"
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

    content:AdvanceY(configCard:GetContentHeight() + UI.layout.spacing)

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
    nameInput:SetSize(UI.layout.inputWidthMedium, UI.layout.rowHeightSmall)
    nameInput:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", rulesCard._leftPadding, inputY)
    nameInput:SetFontObject("GameFontNormalSmall")
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(20)
    nameInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    nameInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    nameInput:SetBackdropBorderColor(unpack(UI.colors.border))
    nameInput:SetTextInsets(6, 6, 0, 0)
    nameInput:SetTextColor(unpack(UI.colors.text))

    local namePlaceholder = nameInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    namePlaceholder:SetPoint("LEFT", 6, 0)
    namePlaceholder:SetText("Rule Name...")
    namePlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)

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
    filterInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    filterInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    filterInput:SetBackdropBorderColor(unpack(UI.colors.border))
    filterInput:SetTextInsets(6, 6, 0, 0)
    filterInput:SetTextColor(unpack(UI.colors.text))

    local filterPlaceholder = filterInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterPlaceholder:SetPoint("LEFT", 6, 0)
    filterPlaceholder:SetText("7 or 7_8")
    filterPlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)

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
    recipientInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    recipientInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    recipientInput:SetBackdropBorderColor(unpack(UI.colors.border))
    recipientInput:SetTextInsets(6, 6, 0, 0)
    recipientInput:SetTextColor(unpack(UI.colors.text))

    local recipientPlaceholder = recipientInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipientPlaceholder:SetPoint("LEFT", 6, 0)
    recipientPlaceholder:SetText("Recipient Alt Name")
    recipientPlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)

    -- Dropdown button
    local dropdownBtn = CreateFrame("Button", nil, rulesCard, "BackdropTemplate")
    dropdownBtn:SetSize(UI.layout.rowHeightSmall, UI.layout.rowHeightSmall)
    dropdownBtn:SetPoint("LEFT", recipientInput, "RIGHT", 2, 0)
    dropdownBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    dropdownBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
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
            dropdownMenu:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = UI.layout.borderSize,
            })
            dropdownMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
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
        self:SetBackdropColor(0.25, 0.25, 0.25, 1)
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)
    dropdownBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 1)
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
    noRulesLabel:SetText("|cff888888No rules configured. Add one above.|r")
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
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = UI.layout.borderSize,
            })
            row:SetBackdropColor(0.12, 0.12, 0.12, 1)
            row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

            local enableBox = CreateFrame("CheckButton", nil, row, "BackdropTemplate")
            enableBox:SetSize(UI.layout.iconSizeSmall, UI.layout.iconSizeSmall)
            enableBox:SetPoint("LEFT", 4, 0)
            enableBox:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = UI.layout.borderSize,
            })
            enableBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
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
            label:SetText((rule.name or "Unnamed") .. " |cff888888→ " .. altName .. " | " .. filterText .. "|r")

            local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            removeBtn:SetSize(UI.layout.buttonHeightSmall, UI.layout.buttonHeightSmall)
            removeBtn:SetPoint("RIGHT", -2, 0)
            removeBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
            removeBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)
            removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            removeBtn.text:SetPoint("CENTER")
            removeBtn.text:SetText("|cffff6666X|r")
            removeBtn:SetScript("OnClick", function()
                if IM.modules.MailHelper then IM.modules.MailHelper:RemoveRule(i) end
                IM:RefreshAllUI()
            end)
            removeBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.5, 0.1, 0.1, 1)
                self.text:SetText("|cffff0000X|r")
            end)
            removeBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.3, 0.1, 0.1, 1)
                self.text:SetText("|cffff6666X|r")
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

    content:AdvanceY(rulesCard:GetContentHeight() + UI.layout.spacing)

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

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.spacing)

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
