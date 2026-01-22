--[[
    InventoryManager - UI/Panels/MailHelper.lua
    Mail helper configuration panel - simplified rule-based mail routing.

    Design Standard:
    - Feature card (amber) at top with description
    - Settings cards (dark) for grouped options
    - Tips section at bottom
    - All elements use dynamic width (TOPLEFT + RIGHT anchoring)
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.MailHelper = {}

local MailHelperPanel = UI.Panels.MailHelper
local _refreshFunc = nil

-- Padding constants
local ROW_HEIGHT = 26

function MailHelperPanel:Create(parent)
    -- Create scroll frame for all content
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = 0

    -- ============================================================
    -- FEATURE CARD: Mail Helper Overview
    -- ============================================================
    local featureCard = UI:CreateFeatureCard(content, yOffset, 85)

    local featureTitle = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -8)
    featureTitle:SetText(UI:ColorText("Mail Helper", "accent"))

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -28)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetSpacing(2)
    featureDesc:SetText(
        "Auto-queue items for mailing to alts based on item class rules.\n" ..
        "Rules match items in your bags when you open a mailbox.\n" ..
        "Items appear in a popup for quick sending."
    )
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 95

    -- ============================================================
    -- SETTINGS CARD: Enable/Disable
    -- ============================================================
    local enableHeader = UI:CreateSectionHeader(content, "Configuration")
    enableHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local enableCard = UI:CreateSettingsCard(content, yOffset, 45)

    local enableCheck = UI:CreateCheckbox(enableCard, "Enable Mail Helper", IM.db.global.mailHelper.enabled)
    enableCheck:SetPoint("TOPLEFT", enableCard, "TOPLEFT", 10, -10)
    enableCheck.checkbox.OnValueChanged = function(self, checked)
        IM.db.global.mailHelper.enabled = checked

        -- Rebuild queue (will be empty if disabled)
        if IM.modules.MailHelper then
            IM.modules.MailHelper:AutoFillQueue()
        end

        -- Hide popup if disabling
        if not checked and IM.UI and IM.UI.MailPopup then
            IM.UI.MailPopup:Hide()
        end

        -- Refresh all UI elements
        IM:RefreshAllUI()
    end

    yOffset = yOffset - 55

    -- ============================================================
    -- SETTINGS CARD: Mail Rules
    -- ============================================================
    local rulesHeader = UI:CreateSectionHeader(content, "Mail Rules")
    rulesHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    -- This card will be dynamically sized based on rules count
    local rulesCard = UI:CreateSettingsCard(content, yOffset, 200)

    -- Description
    local rulesDesc = rulesCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rulesDesc:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", 10, -10)
    rulesDesc:SetPoint("RIGHT", rulesCard, "RIGHT", -10, 0)
    rulesDesc:SetJustifyH("LEFT")
    rulesDesc:SetWordWrap(true)
    rulesDesc:SetText("|cff888888Format: classID (e.g., 7 = all tradeskill) or classID_subclassID (e.g., 7_8 = cooking)|r")

    local cardYOffset = -32

    -- Input row container
    local inputContainer = CreateFrame("Frame", nil, rulesCard)
    inputContainer:SetHeight(56)
    inputContainer:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", 10, cardYOffset)
    inputContainer:SetPoint("RIGHT", rulesCard, "RIGHT", -10, 0)

    -- Row 1: Name and Filter inputs
    local nameInput = CreateFrame("EditBox", nil, inputContainer, "BackdropTemplate")
    nameInput:SetSize(120, 24)
    nameInput:SetPoint("TOPLEFT", 0, 0)
    nameInput:SetFontObject("GameFontNormalSmall")
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(20)
    nameInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
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

    -- Filter input
    local filterInput = CreateFrame("EditBox", nil, inputContainer, "BackdropTemplate")
    filterInput:SetSize(80, 24)
    filterInput:SetPoint("LEFT", nameInput, "RIGHT", 6, 0)
    filterInput:SetFontObject("GameFontNormalSmall")
    filterInput:SetAutoFocus(false)
    filterInput:SetMaxLetters(10)
    filterInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
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

    -- Row 2: Recipient with autocomplete dropdown
    local recipientContainer = CreateFrame("Frame", nil, inputContainer)
    recipientContainer:SetSize(180, 24)
    recipientContainer:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", 0, -4)

    local recipientInput = CreateFrame("EditBox", nil, recipientContainer, "BackdropTemplate")
    recipientInput:SetSize(150, 24)
    recipientInput:SetPoint("LEFT", 0, 0)
    recipientInput:SetFontObject("GameFontNormalSmall")
    recipientInput:SetAutoFocus(false)
    recipientInput:SetMaxLetters(30)
    recipientInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    recipientInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    recipientInput:SetBackdropBorderColor(unpack(UI.colors.border))
    recipientInput:SetTextInsets(6, 6, 0, 0)
    recipientInput:SetTextColor(unpack(UI.colors.text))

    local recipientPlaceholder = recipientInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipientPlaceholder:SetPoint("LEFT", 6, 0)
    recipientPlaceholder:SetText("Recipient Alt Name")
    recipientPlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)

    -- Dropdown button for alt list
    local dropdownBtn = CreateFrame("Button", nil, recipientContainer, "BackdropTemplate")
    dropdownBtn:SetSize(24, 24)
    dropdownBtn:SetPoint("LEFT", recipientInput, "RIGHT", 2, 0)
    dropdownBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dropdownBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    dropdownBtn:SetBackdropBorderColor(unpack(UI.colors.border))

    local dropdownArrow = dropdownBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropdownArrow:SetPoint("CENTER")
    dropdownArrow:SetText("v")
    dropdownArrow:SetTextColor(unpack(UI.colors.textDim))

    -- Dropdown menu (lazy created)
    local dropdownMenu = nil

    local function ShowAltDropdown(filterText)
        if not dropdownMenu then
            dropdownMenu = CreateFrame("Frame", nil, recipientContainer, "BackdropTemplate")
            dropdownMenu:SetFrameStrata("TOOLTIP")
            dropdownMenu:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            dropdownMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
            dropdownMenu:SetBackdropBorderColor(unpack(UI.colors.accent))
            dropdownMenu:SetPoint("TOP", recipientInput, "BOTTOM", 0, -2)
            dropdownMenu.buttons = {}
        end

        -- Clear existing buttons
        for _, btn in ipairs(dropdownMenu.buttons) do
            btn:Hide()
        end

        -- Get filtered alts
        local alts = IM.modules.MailHelper and IM.modules.MailHelper:GetAlts() or {}
        local filter = (filterText or ""):lower()
        local yOff = -2
        local count = 0
        local maxVisible = 6

        for altKey, altData in pairs(alts) do
            local altName = altData.name or altKey:match("^(.+)-") or altKey

            -- Filter by typed text
            if filter == "" or altName:lower():find(filter, 1, true) then
                count = count + 1
                if count <= maxVisible then
                    local btn = dropdownMenu.buttons[count]
                    if not btn then
                        btn = CreateFrame("Button", nil, dropdownMenu)
                        btn:SetHeight(20)
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

                    -- Display name with class color if available
                    local displayText = altName
                    if altData.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[altData.class] then
                        local classColor = RAID_CLASS_COLORS[altData.class]
                        displayText = classColor:WrapTextInColorCode(altName)
                    end
                    btn.text:SetText(displayText)
                    btn.text:SetTextColor(unpack(UI.colors.text))

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

        if count == 0 then
            dropdownMenu:Hide()
            return
        end

        dropdownMenu:SetSize(recipientInput:GetWidth(), math.abs(yOff) + 4)
        dropdownMenu:Show()
    end

    -- Dropdown button shows all alts
    dropdownBtn:SetScript("OnClick", function()
        if dropdownMenu and dropdownMenu:IsShown() then
            dropdownMenu:Hide()
        else
            ShowAltDropdown("")
        end
    end)

    dropdownBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.25, 1)
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)

    dropdownBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 1)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    -- EditBox scripts
    recipientInput:SetScript("OnEditFocusGained", function(self)
        recipientPlaceholder:Hide()
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)

    recipientInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then recipientPlaceholder:Show() end
        self:SetBackdropBorderColor(unpack(UI.colors.border))
        -- Delay hiding dropdown so click can register
        C_Timer.After(0.15, function()
            if dropdownMenu and not MouseIsOver(dropdownMenu) then
                dropdownMenu:Hide()
            end
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
                -- Show filtered dropdown as user types
                ShowAltDropdown(text)
            end
        end
    end)

    recipientInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if dropdownMenu then dropdownMenu:Hide() end
    end)

    -- Add button
    local addBtn = UI:CreateButton(inputContainer, "Add Rule", 70, 24)
    addBtn:SetPoint("LEFT", recipientContainer, "RIGHT", 6, 0)

    cardYOffset = cardYOffset - 64

    -- Rules list container
    local rulesContainer = CreateFrame("Frame", nil, rulesCard)
    rulesContainer:SetHeight(10)
    rulesContainer:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", 10, cardYOffset)
    rulesContainer:SetPoint("RIGHT", rulesCard, "RIGHT", -10, 0)

    -- "No rules" label
    local noRulesLabel = rulesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noRulesLabel:SetPoint("TOPLEFT", 0, 0)
    noRulesLabel:SetText("|cff888888No rules configured. Add one above.|r")
    noRulesLabel:Hide()

    local function RefreshRulesList()
        -- Clear existing children
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
                edgeSize = 1,
            })
            row:SetBackdropColor(0.12, 0.12, 0.12, 1)
            row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

            -- Enable checkbox (small, inline)
            local enableBox = CreateFrame("CheckButton", nil, row, "BackdropTemplate")
            enableBox:SetSize(16, 16)
            enableBox:SetPoint("LEFT", 4, 0)
            enableBox:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            enableBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
            enableBox:SetBackdropBorderColor(unpack(UI.colors.border))
            enableBox.check = enableBox:CreateTexture(nil, "OVERLAY")
            enableBox.check:SetSize(12, 12)
            enableBox.check:SetPoint("CENTER")
            enableBox.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            enableBox.check:SetShown(rule.enabled)
            enableBox:SetChecked(rule.enabled)
            enableBox:SetScript("OnClick", function(self)
                rule.enabled = self:GetChecked()
                self.check:SetShown(rule.enabled)
                if IM.modules.MailHelper then
                    IM.modules.MailHelper:UpdateRule(i, rule)
                end
                IM:RefreshAllUI()
            end)

            -- Build display text
            local filterText = rule.filterValue or "?"
            local classID, subclassID = (rule.filterValue or ""):match("^(%d+)_(%d+)$")
            if classID and subclassID then
                local className = IM.ITEM_CLASS_NAMES and IM.ITEM_CLASS_NAMES[tonumber(classID)]
                local subclassName = GetItemSubClassInfo(tonumber(classID), tonumber(subclassID))
                if className then
                    filterText = rule.filterValue .. " (" .. className
                    if subclassName and subclassName ~= "" then
                        filterText = filterText .. ": " .. subclassName
                    end
                    filterText = filterText .. ")"
                end
            else
                local classIDNum = tonumber(rule.filterValue)
                if classIDNum then
                    local className = IM.ITEM_CLASS_NAMES and IM.ITEM_CLASS_NAMES[classIDNum]
                    if className then
                        filterText = rule.filterValue .. " (" .. className .. ")"
                    end
                end
            end

            local altName = rule.alt and (rule.alt:match("^(.+)-") or rule.alt) or "?"

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", enableBox, "RIGHT", 6, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -30, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText((rule.name or "Unnamed") .. " |cff888888→ " .. altName .. " | " .. filterText .. "|r")
            label:SetTextColor(unpack(UI.colors.text))

            -- Remove button (red X)
            local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            removeBtn:SetSize(22, 22)
            removeBtn:SetPoint("RIGHT", -2, 0)
            removeBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
            removeBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)

            removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            removeBtn.text:SetPoint("CENTER")
            removeBtn.text:SetText("|cffff6666X|r")

            removeBtn:SetScript("OnClick", function()
                if IM.modules.MailHelper then
                    IM.modules.MailHelper:RemoveRule(i)
                end
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

        rulesContainer:SetHeight(math.max(math.abs(listY), 24))

        -- Update card height dynamically based on rules count
        local baseHeight = 96 + 24  -- desc + inputs area + padding
        local rulesHeight = math.max(math.abs(listY), 24)
        rulesCard:SetHeight(baseHeight + rulesHeight + 10)

        return math.abs(listY)
    end

    -- Add button logic
    addBtn:SetScript("OnClick", function()
        local name = nameInput:GetText()
        local filter = filterInput:GetText()
        local recipient = recipientInput:GetText()

        -- Validate filter format
        if filter == "" or not (filter:match("^%d+$") or filter:match("^%d+_%d+$")) then
            IM:Print("Invalid filter. Use classID (e.g., 7) or classID_subclassID (e.g., 7_8)")
            return
        end

        if recipient == "" then
            IM:Print("Please enter a recipient name")
            return
        end

        -- Add realm if not specified
        if not recipient:find("-") then
            recipient = recipient .. "-" .. GetRealmName()
        end

        if name == "" then name = "Rule " .. (#(IM.modules.MailHelper:GetRules() or {}) + 1) end

        if IM.modules.MailHelper then
            IM.modules.MailHelper:AddRule({
                name = name,
                alt = recipient,
                filterType = "classID",
                filterValue = filter,
                enabled = true,
            })

            -- Clear inputs
            nameInput:SetText("")
            filterInput:SetText("")
            recipientInput:SetText("")
            nameInput:ClearFocus()
            filterInput:ClearFocus()
            recipientInput:ClearFocus()
            namePlaceholder:Show()
            filterPlaceholder:Show()
            recipientPlaceholder:Show()

            -- Refresh all UI elements
            IM:RefreshAllUI()
        end
    end)

    -- Enter key to add
    nameInput:SetScript("OnEnterPressed", function() addBtn:Click() end)
    filterInput:SetScript("OnEnterPressed", function() addBtn:Click() end)
    recipientInput:SetScript("OnEnterPressed", function() addBtn:Click() end)

    -- Initial rules height calc
    local rulesHeight = RefreshRulesList()
    local initialCardHeight = 96 + 24 + rulesHeight + 10
    rulesCard:SetHeight(initialCardHeight)
    yOffset = yOffset - initialCardHeight - 10

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
        "- Hover any item to see its Class ID in the tooltip\n" ..
        "- Look for 'ID:' line (e.g., ID: 7_8 = classID=7, subclassID=8)\n" ..
        "- Use just classID (e.g., 7) to match ALL items in that category\n" ..
        "- The popup appears automatically when you open a mailbox\n" ..
        "|r"
    )

    yOffset = yOffset - 75

    -- Set content height
    content:SetHeight(math.abs(yOffset) + 20)

    -- Full refresh function
    local function FullRefresh()
        local rulesHeight = RefreshRulesList()
        local cardHeight = 96 + 24 + rulesHeight + 10
        rulesCard:SetHeight(cardHeight)

        -- Recalculate total content height
        local totalHeight = 95 + 24 + 55 + 24 + cardHeight + 10 + 22 + 75 + 20
        content:SetHeight(totalHeight)
    end

    _refreshFunc = FullRefresh

    -- Auto-refresh when shown
    parent:SetScript("OnShow", FullRefresh)

    -- Initial refresh
    C_Timer.After(0.1, FullRefresh)

    MailHelperPanel.Refresh = FullRefresh
end

function MailHelperPanel:Refresh()
    if _refreshFunc then
        _refreshFunc()
    end
end
