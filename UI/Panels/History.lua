--[[
    InventoryManager - UI/Panels/History.lua
    Transaction history panel with search
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.History = {}

local HistoryPanel = UI.Panels.History
local searchFilter = ""
local refreshListFunc = nil

function HistoryPanel:Create(parent)
    -- Create scroll frame for all content (fill mode - resizes with panel)
    local scrollFrame = UI:CreateScrollFrame(parent, nil, nil, true)

    local content = scrollFrame.content
    local yOffset = 0

    -- Title
    local title = UI:CreateSectionHeader(content, "Transaction History")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 22

    -- Stats
    local statsLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    statsLabel:SetTextColor(unpack(UI.colors.text))

    local statsLabel2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsLabel2:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset - 14)
    statsLabel2:SetTextColor(unpack(UI.colors.textDim))

    local function UpdateStats()
        local stats = IM:GetTransactionStats()
        -- Net sold = sells minus buybacks (since buybacks undo sells)
        local netSoldValue = stats.sells.value - stats.buybacks.value
        -- Auction net = sold minus bought
        local auctionNet = stats.auctionSold.value - stats.auctionBought.value
        statsLabel:SetText("|cff00ff00Vendor:|r " .. IM:FormatMoney(netSoldValue) .. " (" .. stats.sells.count .. ")  |cff00ff88AH:|r " .. IM:FormatMoney(auctionNet) .. " (" .. stats.auctionSold.count .. "/" .. stats.auctionBought.count .. ")")
        statsLabel2:SetText("|cffff8800Buyback:|r " .. stats.buybacks.count .. "  |cffff6666Purchased:|r " .. stats.purchases.count .. "  |cff00ccffLooted:|r " .. stats.loots.count)
    end
    UpdateStats()
    yOffset = yOffset - 40

    -- Search bar (dynamic width)
    local searchBox = CreateFrame("EditBox", nil, content, "BackdropTemplate")
    searchBox:SetHeight(22)
    searchBox:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    searchBox:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    searchBox:SetFontObject("GameFontNormalSmall")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    searchBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    searchBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    searchBox:SetBackdropBorderColor(unpack(UI.colors.border))
    searchBox:SetTextInsets(6, 20, 0, 0)
    searchBox:SetTextColor(unpack(UI.colors.text))

    -- Search placeholder
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText("Search items...")
    placeholder:SetTextColor(0.5, 0.5, 0.5, 1)

    -- Search icon
    local searchIcon = searchBox:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(12, 12)
    searchIcon:SetPoint("RIGHT", -4, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")

    -- Debounce timer for search
    local searchDebounceTimer = nil

    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            local text = self:GetText()
            placeholder:SetShown(text == "")

            -- Cancel pending search
            if searchDebounceTimer then
                searchDebounceTimer:Cancel()
            end

            -- Debounce search by 0.3 seconds
            searchDebounceTimer = C_Timer.NewTimer(0.3, function()
                searchFilter = text:lower()
                if refreshListFunc then
                    refreshListFunc()
                end
            end)
        end
    end)

    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    yOffset = yOffset - 30

    -- Item list container (dynamic height)
    local listContainer = CreateFrame("Frame", nil, content)
    listContainer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
    listContainer:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    listContainer:SetHeight(10) -- Will be updated dynamically

    -- Refresh function
    local function RefreshList()
        -- Clear existing entries
        for _, child in pairs({listContainer:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        -- Verify module exists and has the required method
        local formatted = {}
        if IM.modules.SellHistory and type(IM.modules.SellHistory.GetFormattedHistory) == "function" then
            formatted = IM.modules.SellHistory:GetFormattedHistory()
        end
        local listYOffset = 0
        local visibleCount = 0

        for i, entry in ipairs(formatted) do
            -- Apply search filter
            local showEntry = true
            if searchFilter ~= "" then
                local matchName = entry.itemName:lower():find(searchFilter, 1, true)
                local matchChar = entry.character:lower():find(searchFilter, 1, true)
                local matchType = entry.typeLabel:lower():find(searchFilter, 1, true)
                if not matchName and not matchChar and not matchType then
                    showEntry = false
                end
            end

            if showEntry then
                visibleCount = visibleCount + 1
                local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(entry.itemID)

                local row = CreateFrame("Frame", nil, listContainer, "BackdropTemplate")
                row:SetHeight(36)
                row:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 10, listYOffset)
                row:SetPoint("RIGHT", listContainer, "RIGHT", -10, 0)

                row:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                })
                row:SetBackdropColor(0.12, 0.12, 0.12, visibleCount % 2 == 0 and 0.5 or 0)

                -- Top row: Type badge, Character
                local typeBadge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                typeBadge:SetPoint("TOPLEFT", 4, -2)
                typeBadge:SetText(entry.typeColor .. entry.typeLabel .. "|r")

                local charLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                charLabel:SetPoint("LEFT", typeBadge, "RIGHT", 6, 0)
                charLabel:SetText("|cff88ccff" .. entry.character .. "|r")

                -- Timestamp (anchored to right, won't get cut off)
                local time = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                time:SetPoint("TOPRIGHT", -4, -2)
                time:SetText(entry.timestamp)
                time:SetTextColor(unpack(UI.colors.textDim))

                -- Bottom row: Icon, Name, Value
                local icon = row:CreateTexture(nil, "OVERLAY")
                icon:SetSize(18, 18)
                icon:SetPoint("BOTTOMLEFT", 4, 4)
                icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

                -- Value label (anchored to right first)
                local valueLabel = nil
                if entry.value and entry.value ~= 0 then
                    valueLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    valueLabel:SetPoint("BOTTOMRIGHT", -4, 6)
                    valueLabel:SetText(entry.valueFormatted)
                end

                -- Name (anchored between icon and value)
                local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                if valueLabel then
                    name:SetPoint("RIGHT", valueLabel, "LEFT", -6, 0)
                else
                    name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                end
                local displayName = entry.itemLink or entry.itemName or ("Item #" .. entry.itemID)
                if entry.quantity > 1 then
                    displayName = displayName .. " x" .. entry.quantity
                end
                name:SetText(displayName)
                name:SetJustifyH("LEFT")

                listYOffset = listYOffset - 38
            end
        end

        local listHeight = math.abs(listYOffset) + 10
        listContainer:SetHeight(math.max(listHeight, 100))
        content:SetHeight(math.abs(yOffset) + listHeight + 60)
        UpdateStats()
    end

    refreshListFunc = RefreshList

    -- Auto-refresh when panel is shown
    parent:SetScript("OnShow", function()
        RefreshList()
    end)

    -- Initial refresh
    C_Timer.After(0.1, RefreshList)

    -- Buttons at bottom
    local clearBtn = UI:CreateButton(content, "Clear History", 100, 24)
    clearBtn:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 10, -10)
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("INVENTORYMANAGER_CLEAR_HISTORY")
    end)

    local exportBtn = UI:CreateButton(content, "Copy to Clipboard", 120, 24)
    exportBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    exportBtn:SetScript("OnClick", function()
        if IM.modules.SellHistory then
            local text = IM.modules.SellHistory:ExportToString()
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

            local editBox = CreateFrame("EditBox", nil, popup)
            editBox:SetMultiLine(true)
            editBox:SetSize(380, 260)
            editBox:SetPoint("TOP", 0, -10)
            editBox:SetFontObject("GameFontNormalSmall")
            editBox:SetText(text)
            editBox:HighlightText()
            editBox:SetAutoFocus(true)

            local closeBtn = UI:CreateButton(popup, "Close", 60, 22)
            closeBtn:SetPoint("BOTTOM", 0, 5)
            closeBtn:SetScript("OnClick", function() popup:Hide() end)

            popup:SetScript("OnKeyDown", function(self, key)
                if key == "ESCAPE" then self:Hide() end
            end)
        end
    end)

    -- Clear confirmation popup
    StaticPopupDialogs["INVENTORYMANAGER_CLEAR_HISTORY"] = {
        text = "Are you sure you want to clear the transaction history?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            IM:ClearSellHistory()
            RefreshList()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    -- Store refresh function for auto-updates
    HistoryPanel.Refresh = RefreshList
end

-- Function to refresh the history list from outside
function HistoryPanel:Refresh()
    if refreshListFunc then
        refreshListFunc()
    end
end
