--[[
    InventoryManager - UI/Panels/Categories.lua
    Category exclusions settings panel with scrolling
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Categories = {}

local CategoriesPanel = UI.Panels.Categories

function CategoriesPanel:Create(parent)
    -- Fix contradictory state on load: if both are true, prefer "protect" (safer default)
    if IM.db.global.autoSell.skipSoulbound and IM.db.global.autoSell.onlySellSoulbound then
        IM.db.global.autoSell.onlySellSoulbound = false
    end

    -- Create scroll panel
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = -10

    -- Feature Card
    local featureCard = UI:CreateFeatureCard(content, yOffset, 85)
    yOffset = yOffset - 95

    local featureTitle = UI:CreateSectionHeader(featureCard, "Category Exclusions")
    featureTitle:SetPoint("TOPLEFT", featureCard, "TOPLEFT", 15, -12)

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", featureCard, "TOPLEFT", 15, -35)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -15, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetText("Control which categories of items are protected from auto-sell. Items matching any exclusion will never be sold, regardless of other filters.")
    featureDesc:SetTextColor(unpack(UI.colors.text))

    -- Category Exclusions Settings Card (10 checkboxes need ~300px)
    local categoryCard = UI:CreateSettingsCard(content, yOffset, 310)
    yOffset = yOffset - 320

    local categoryTitle = UI:CreateSectionHeader(categoryCard, "Protected Categories")
    categoryTitle:SetPoint("TOPLEFT", categoryCard, "TOPLEFT", 15, -12)

    local cardYOffset = -40

    -- Category checkboxes
    local categories = {
        { key = "consumables", name = "Consumables", desc = "Food, potions, flasks" },
        { key = "questItems", name = "Quest Items", desc = "Items used for quests" },
        { key = "craftingReagents", name = "Crafting Reagents", desc = "Profession materials" },
        { key = "tradeGoods", name = "Trade Goods", desc = "Trade skill items" },
        { key = "recipes", name = "Recipes", desc = "Patterns, schematics, formulas" },
        { key = "toys", name = "Toys", desc = "Items in Toy Box" },
        { key = "pets", name = "Battle Pets", desc = "Pet cages and items" },
        { key = "mounts", name = "Mounts", desc = "Mount items" },
        { key = "currencyTokens", name = "Currency Tokens", desc = "Event tokens, valor, etc." },
        { key = "housingItems", name = "Housing Items", desc = "Player housing decorations" },
    }

    for _, cat in ipairs(categories) do
        local check = UI:CreateCheckbox(categoryCard, cat.name, IM.db.global.categoryExclusions[cat.key])
        check:SetPoint("TOPLEFT", categoryCard, "TOPLEFT", 15, cardYOffset)
        check.checkbox.OnValueChanged = function(self, value)
            IM.db.global.categoryExclusions[cat.key] = value
            IM:RefreshAllUI()
        end

        -- Description
        local catDesc = categoryCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catDesc:SetPoint("LEFT", check.label, "RIGHT", 10, 0)
        catDesc:SetText("(" .. cat.desc .. ")")
        catDesc:SetTextColor(unpack(UI.colors.textDim))

        cardYOffset = cardYOffset - 25
    end

    -- Item State Protection Settings Card
    local stateCard = UI:CreateSettingsCard(content, yOffset, 220)
    yOffset = yOffset - 230

    local stateTitle = UI:CreateSectionHeader(stateCard, "Item State Protection")
    stateTitle:SetPoint("TOPLEFT", stateCard, "TOPLEFT", 15, -12)

    local stateDesc = stateCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stateDesc:SetPoint("TOPLEFT", stateCard, "TOPLEFT", 15, -35)
    stateDesc:SetPoint("RIGHT", stateCard, "RIGHT", -15, 0)
    stateDesc:SetJustifyH("LEFT")
    stateDesc:SetText("Protect items based on their binding, collection status, or equipment set membership.")
    stateDesc:SetTextColor(unpack(UI.colors.textDim))

    cardYOffset = -60

    -- Equipment Sets
    local equipmentCheck = UI:CreateCheckbox(stateCard, "Protect items in equipment sets", IM.db.global.categoryExclusions.equipmentSets)
    equipmentCheck:SetPoint("TOPLEFT", stateCard, "TOPLEFT", 15, cardYOffset)
    equipmentCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.categoryExclusions.equipmentSets = value
        IM:RefreshAllUI()
    end
    cardYOffset = cardYOffset - 28

    -- Skip soulbound (protect soulbound items)
    local soulboundCheck = UI:CreateCheckbox(stateCard, "Protect soulbound items", IM.db.global.autoSell.skipSoulbound)
    soulboundCheck:SetPoint("TOPLEFT", stateCard, "TOPLEFT", 15, cardYOffset)
    cardYOffset = cardYOffset - 28

    -- Only sell soulbound (protect non-soulbound items) - mutually exclusive with above
    local onlySoulboundCheck = UI:CreateCheckbox(stateCard, "Only sell soulbound items", IM.db.global.autoSell.onlySellSoulbound)
    onlySoulboundCheck:SetPoint("TOPLEFT", stateCard, "TOPLEFT", 15, cardYOffset)

    -- Mutual exclusivity note
    local soulboundNote = stateCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soulboundNote:SetPoint("LEFT", onlySoulboundCheck.label, "RIGHT", 10, 0)
    soulboundNote:SetText("|cffff8800(mutually exclusive)|r")

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
    cardYOffset = cardYOffset - 28

    -- Skip warbound
    local warboundCheck = UI:CreateCheckbox(stateCard, "Protect warbound/account-bound items", IM.db.global.autoSell.skipWarbound)
    warboundCheck:SetPoint("TOPLEFT", stateCard, "TOPLEFT", 15, cardYOffset)
    warboundCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoSell.skipWarbound = value
        IM:RefreshAllUI()
    end
    cardYOffset = cardYOffset - 28

    -- Skip uncollected transmog
    local transmogCheck = UI:CreateCheckbox(stateCard, "Protect uncollected transmog appearances", IM.db.global.autoSell.skipUncollectedTransmog)
    transmogCheck:SetPoint("TOPLEFT", stateCard, "TOPLEFT", 15, cardYOffset)
    transmogCheck.checkbox.OnValueChanged = function(self, value)
        IM.db.global.autoSell.skipUncollectedTransmog = value
        IM:RefreshAllUI()
    end

    -- Custom Categories Settings Card
    local customCard = UI:CreateSettingsCard(content, yOffset, 240)
    yOffset = yOffset - 250

    local customTitle = UI:CreateSectionHeader(customCard, "Custom Category Exclusions")
    customTitle:SetPoint("TOPLEFT", customCard, "TOPLEFT", 15, -12)

    local customDesc = customCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customDesc:SetPoint("TOPLEFT", customCard, "TOPLEFT", 15, -35)
    customDesc:SetPoint("RIGHT", customCard, "RIGHT", -15, 0)
    customDesc:SetJustifyH("LEFT")
    customDesc:SetText("Add custom exclusions by classID (e.g., 7 = all tradeskill) or classID_subclassID (e.g., 7_8 = cooking only).")
    customDesc:SetTextColor(unpack(UI.colors.textDim))

    cardYOffset = -60

    -- Custom category input
    local customInput = CreateFrame("EditBox", nil, customCard, "BackdropTemplate")
    customInput:SetSize(150, 22)
    customInput:SetPoint("TOPLEFT", customCard, "TOPLEFT", 15, cardYOffset)
    customInput:SetFontObject("GameFontNormalSmall")
    customInput:SetAutoFocus(false)
    customInput:SetMaxLetters(10)
    customInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
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
        if self:GetText() == "" then
            inputPlaceholder:Show()
        end
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    customInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Add button for custom category
    local addBtn = UI:CreateButton(customCard, "Add", 60, 22)
    addBtn:SetPoint("LEFT", customInput, "RIGHT", 6, 0)

    cardYOffset = cardYOffset - 30

    -- Custom categories list container
    local customListContainer = CreateFrame("Frame", nil, customCard)
    customListContainer:SetSize(350, 100)
    customListContainer:SetPoint("TOPLEFT", customCard, "TOPLEFT", 15, cardYOffset)

    local function RefreshCustomList()
        -- Clear existing
        for _, child in pairs({customListContainer:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local listY = 0
        local hasEntries = false

        for key, _ in pairs(IM.db.global.customCategoryExclusions or {}) do
            hasEntries = true
            local row = CreateFrame("Frame", nil, customListContainer, "BackdropTemplate")
            row:SetSize(280, 24)
            row:SetPoint("TOPLEFT", 0, listY)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            row:SetBackdropColor(0.12, 0.12, 0.12, 1)
            row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

            -- Parse the key for display
            local classID, subclassID = key:match("^(%d+)_(%d+)$")
            local displayText = key
            if classID and subclassID then
                -- Format: classID_subclassID (e.g., "7_8")
                local classIDNum = tonumber(classID)
                local subclassIDNum = tonumber(subclassID)
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
                -- Format: classID only (e.g., "7")
                local classIDNum = tonumber(key)
                if classIDNum then
                    local className = IM.ITEM_CLASS_NAMES and IM.ITEM_CLASS_NAMES[classIDNum]
                    if className then
                        displayText = key .. " (" .. className .. " - All)"
                    end
                end
            end

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 8, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -30, 0)
            label:SetJustifyH("LEFT")
            label:SetText(displayText)
            label:SetTextColor(unpack(UI.colors.text))

            -- Remove button
            local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            removeBtn:SetSize(20, 20)
            removeBtn:SetPoint("RIGHT", -2, 0)
            removeBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
            })
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
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Remove this exclusion")
                GameTooltip:Show()
            end)
            removeBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.3, 0.1, 0.1, 1)
                self.text:SetText("|cffff6666X|r")
                GameTooltip:Hide()
            end)

            listY = listY - 26
        end

        -- Show empty state message
        if not hasEntries then
            local emptyMsg = customListContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyMsg:SetPoint("TOPLEFT", 0, 0)
            emptyMsg:SetText("No custom exclusions. Add one above.")
            emptyMsg:SetTextColor(0.5, 0.5, 0.5, 1)
            listY = -20
        end

        customListContainer:SetHeight(math.max(math.abs(listY), 20))
    end

    addBtn:SetScript("OnClick", function()
        local text = customInput:GetText()
        -- Accept both "7" (class only) and "7_8" (class+subclass) formats
        if text ~= "" and (text:match("^%d+$") or text:match("^%d+_%d+$")) then
            if not IM.db.global.customCategoryExclusions then
                IM.db.global.customCategoryExclusions = {}
            end
            IM.db.global.customCategoryExclusions[text] = true
            customInput:SetText("")
            customInput:ClearFocus()
            inputPlaceholder:Show()
            RefreshCustomList()
            IM:RefreshAllUI()
        else
            IM:Print("Invalid format. Use classID (e.g., 7) or classID_subclassID (e.g., 7_8)")
        end
    end)

    customInput:SetScript("OnEnterPressed", function(self)
        addBtn:Click()
    end)

    RefreshCustomList()

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
        "- Enable tooltip info in General to see classID_subclassID on items\n" ..
        "- Use classID alone (e.g., 7) for all items in a category\n" ..
        "- Use classID_subclassID (e.g., 7_8) for specific subclasses\n" ..
        "|r"
    )

    yOffset = yOffset - 60

    -- Set content height
    content:SetHeight(math.abs(yOffset) + 20)
end
