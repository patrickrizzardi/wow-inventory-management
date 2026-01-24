--[[
    InventoryManager - UI/Panels/Categories.lua
    Category exclusions settings panel (Protections tab)
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Categories = {}

local CategoriesPanel = UI.Panels.Categories

function CategoriesPanel:Create(parent)
    -- Fix contradictory state on load
    if IM.db.global.autoSell.skipSoulbound and IM.db.global.autoSell.onlySellSoulbound then
        IM.db.global.autoSell.onlySellSoulbound = false
    end

    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- ============================================================
    -- ITEM STATE PROTECTION CARD (First - most important)
    -- ============================================================
    local stateCard = UI:CreateCard(content, {
        title = "Item State Protection",
        description = "Protect items based on binding, collection status, or equipment set membership.",
    })

    -- Equipment Sets
    local equipmentCheck = stateCard:AddCheckbox(
        "Protect items in equipment sets",
        IM.db.global.categoryExclusions.equipmentSets,
        "Items saved in any gear set are protected"
    )
    equipmentCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.categoryExclusions.equipmentSets = value
        IM:RefreshAllUI()
    end

    -- Soulbound protection
    local soulboundCheck = stateCard:AddCheckbox(
        "Protect soulbound items",
        IM.db.global.autoSell.skipSoulbound
    )

    -- Only sell soulbound (mutually exclusive)
    local onlySoulboundCheck = stateCard:AddCheckbox(
        "Only sell soulbound items",
        IM.db.global.autoSell.onlySellSoulbound,
        "|cffff8800(mutually exclusive with above)|r"
    )

    -- Wire up mutual exclusivity
    soulboundCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoSell.skipSoulbound = value
        if value then
            IM.db.global.autoSell.onlySellSoulbound = false
            onlySoulboundCheck.checkbox:SetCheckedState(false)
        end
        IM:RefreshAllUI()
    end

    onlySoulboundCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoSell.onlySellSoulbound = value
        if value then
            IM.db.global.autoSell.skipSoulbound = false
            soulboundCheck.checkbox:SetCheckedState(false)
        end
        IM:RefreshAllUI()
    end

    -- Warbound protection
    local warboundCheck = stateCard:AddCheckbox(
        "Protect warbound/account-bound items",
        IM.db.global.autoSell.skipWarbound
    )
    warboundCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoSell.skipWarbound = value
        IM:RefreshAllUI()
    end

    -- Transmog protection
    local transmogCheck = stateCard:AddCheckbox(
        "Protect uncollected transmog appearances",
        IM.db.global.autoSell.skipUncollectedTransmog
    )
    transmogCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoSell.skipUncollectedTransmog = value
        IM:RefreshAllUI()
    end

    content:AdvanceY(stateCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- CUSTOM CATEGORY EXCLUSIONS CARD
    -- ============================================================
    local customCard = UI:CreateCard(content, {
        title = "Custom Category Exclusions",
        description = "Add custom exclusions by classID (e.g., 7 = all tradeskill) or classID_subclassID (e.g., 7_8 = cooking only).",
    })

    -- Input row
    local inputY = customCard:AddContent(32)
    local customInput = CreateFrame("EditBox", nil, customCard, "BackdropTemplate")
    customInput:SetSize(UI.layout.inputWidthLarge - 30, UI.layout.buttonHeightSmall)
    customInput:SetPoint("TOPLEFT", customCard, "TOPLEFT", customCard._leftPadding, inputY)
    customInput:SetFontObject("GameFontNormalSmall")
    customInput:SetAutoFocus(false)
    customInput:SetMaxLetters(10)
    customInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    customInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    customInput:SetBackdropBorderColor(unpack(UI.colors.border))
    customInput:SetTextInsets(6, 6, 0, 0)
    customInput:SetTextColor(unpack(UI.colors.text))

    local inputPlaceholder = customInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputPlaceholder:SetPoint("LEFT", 6, 0)
    inputPlaceholder:SetText("e.g., 7 or 7_8")
    inputPlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)

    customInput:SetScript("OnEditFocusGained", function(self)
        inputPlaceholder:Hide()
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)
    customInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then inputPlaceholder:Show() end
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)
    customInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = UI:CreateButton(customCard, "Add", 60, 22)
    addBtn:SetPoint("LEFT", customInput, "RIGHT", 8, 0)

    -- Custom list container (inside card)
    local customListContainer = CreateFrame("Frame", nil, customCard)
    customListContainer:SetPoint("TOPLEFT", customCard, "TOPLEFT", customCard._leftPadding, -customCard._contentHeight - 8)
    customListContainer:SetPoint("RIGHT", customCard, "RIGHT", -customCard._padding, 0)
    customListContainer:SetHeight(UI.layout.listInitialHeight)

    local function RefreshCustomList()
        for _, child in pairs({customListContainer:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local listYOff = 0
        local hasEntries = false

        for key, _ in pairs(IM.db.global.customCategoryExclusions or {}) do
            hasEntries = true
            local row = CreateFrame("Frame", nil, customListContainer, "BackdropTemplate")
            row:SetHeight(UI.layout.rowHeightSmall + 2)
            row:SetPoint("TOPLEFT", 0, listYOff)
            row:SetPoint("RIGHT", customListContainer, "RIGHT", 0, 0)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = UI.layout.borderSize,
            })
            row:SetBackdropColor(0.12, 0.12, 0.12, 1)
            row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

            local classID, subclassID = key:match("^(%d+)_(%d+)$")
            local displayText = key
            if classID and subclassID then
                local classIDNum, subclassIDNum = tonumber(classID), tonumber(subclassID)
                if classIDNum and subclassIDNum then
                    local className = IM.ITEM_CLASS_NAMES and IM.ITEM_CLASS_NAMES[classIDNum]
                    local subclassName = GetItemSubClassInfo(classIDNum, subclassIDNum)
                    if className then
                        displayText = key .. " (" .. className
                        if subclassName and subclassName ~= "" and subclassName ~= className then
                            displayText = displayText .. ": " .. subclassName
                        end
                        displayText = displayText .. ")"
                    end
                end
            else
                local classIDNum = tonumber(key)
                if classIDNum and IM.ITEM_CLASS_NAMES and IM.ITEM_CLASS_NAMES[classIDNum] then
                    displayText = key .. " (" .. IM.ITEM_CLASS_NAMES[classIDNum] .. " - All)"
                end
            end

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 8, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -30, 0)
            label:SetJustifyH("LEFT")
            label:SetText(displayText)

            local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            removeBtn:SetSize(UI.layout.buttonHeightSmall, UI.layout.buttonHeightSmall)
            removeBtn:SetPoint("RIGHT", -2, 0)
            removeBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
            removeBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)
            removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            removeBtn.text:SetPoint("CENTER")
            removeBtn.text:SetText("|cffff6666X|r")
            removeBtn:SetScript("OnClick", function()
                IM.db.global.customCategoryExclusions[key] = nil
                RefreshCustomList()
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

            listYOff = listYOff - 28
        end

        if not hasEntries then
            local noItems = customListContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noItems:SetPoint("TOPLEFT", 0, 0)
            noItems:SetText("|cff888888No custom exclusions.|r")
            listYOff = -24
        end

        local listHeight = math.max(math.abs(listYOff), 24)
        customListContainer:SetHeight(listHeight)
        return listHeight
    end

    addBtn:SetScript("OnClick", function()
        local text = customInput:GetText()
        if text == "" then return end
        if not (text:match("^%d+$") or text:match("^%d+_%d+$")) then
            IM:Print("Invalid format. Use classID (e.g., 7) or classID_subclassID (e.g., 7_8)")
            return
        end
        IM.db.global.customCategoryExclusions = IM.db.global.customCategoryExclusions or {}
        IM.db.global.customCategoryExclusions[text] = true
        customInput:SetText("")
        customInput:ClearFocus()
        inputPlaceholder:Show()
        RefreshCustomList()
        IM:RefreshAllUI()
    end)

    customInput:SetScript("OnEnterPressed", function() addBtn:Click() end)

    local listHeight = RefreshCustomList()
    customCard._contentHeight = customCard._contentHeight + listHeight + 16  -- Add bottom padding
    customCard:SetHeight(customCard:GetContentHeight())

    content:AdvanceY(customCard:GetContentHeight() + UI.layout.cardSpacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Tips",
    })

    tipsCard:AddText("- Enable tooltip info in General to see classID_subclassID on items")
    tipsCard:AddText("- Use classID alone (e.g., 7) for all items in that category")
    tipsCard:AddText("- Use classID_subclassID (e.g., 7_8) for specific subclasses")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.cardSpacing)

    content:FinalizeHeight()

    -- Refresh function
    local function FullRefresh()
        local listHeight = RefreshCustomList()
        -- Recalculate card height: title + desc + input row + list + padding
        customCard._contentHeight = 50 + 32 + listHeight + 16
        customCard:SetHeight(customCard:GetContentHeight())
    end

    parent:SetScript("OnShow", FullRefresh)
    CategoriesPanel.Refresh = FullRefresh
end

function CategoriesPanel:Refresh()
    if self._refresh then self._refresh() end
end
