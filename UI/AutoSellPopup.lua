--[[
    InventoryManager - UI/AutoSellPopup.lua
    Floating popup that shows when merchant opens with sellable items list.
]]

local addonName, IM = ...
local UI = IM.UI

UI.AutoSellPopup = {}

local AutoSellPopup = UI.AutoSellPopup
local _popup = nil

-- Quality colors for display
local QUALITY_COLORS = {
    [0] = "|cff9d9d9d", -- Poor (gray)
    [1] = "|cffffffff", -- Common (white)
    [2] = "|cff1eff00", -- Uncommon (green)
    [3] = "|cff0070dd", -- Rare (blue)
    [4] = "|cffa335ee", -- Epic (purple)
}

-- Create the popup frame
function AutoSellPopup:Create()
    if _popup then return _popup end

    local popup = CreateFrame("Frame", "InventoryManagerAutoSellPopup", UIParent, "BackdropTemplate")
    popup:SetSize(280, 260)
    popup:SetPoint("TOPLEFT", MerchantFrame or UIParent, "TOPRIGHT", UI.layout.cardSpacing, 0)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = UI.layout.borderSize,
    })
    popup:SetBackdropColor(unpack(UI.colors.background))
    popup:SetBackdropBorderColor(unpack(UI.colors.border))
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    popup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    popup:Hide()

    -- Register for Escape key closing
    tinsert(UISpecialFrames, "InventoryManagerAutoSellPopup")

    -- Title bar (inset by 1px for border, match content padding on sides)
    local titleBar = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    titleBar:SetHeight(UI.layout.iconSize)
    titleBar:SetPoint("TOPLEFT", UI.layout.borderSize, -UI.layout.borderSize)
    titleBar:SetPoint("TOPRIGHT", -UI.layout.borderSize, -UI.layout.borderSize)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    titleBar:SetBackdropColor(unpack(UI.colors.headerBar))

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", UI.layout.elementSpacing, 0)
    title:SetText(UI:ColorText("Auto-Sell", "accent"))

    -- Close button
    local closeBtnSize = UI.layout.iconSizeSmall
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(closeBtnSize, closeBtnSize)
    closeBtn:SetPoint("RIGHT", -2, 0)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeBtn.text:SetPoint("CENTER")
    closeBtn.text:SetText("|cffff6666X|r")
    closeBtn:SetScript("OnClick", function() popup:Hide() end)
    closeBtn:SetScript("OnEnter", function(self) self.text:SetText("|cffff0000X|r") end)
    closeBtn:SetScript("OnLeave", function(self) self.text:SetText("|cffff6666X|r") end)

    -- Summary section
    local summaryBox = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    summaryBox:SetHeight(50)
    summaryBox:SetPoint("TOPLEFT", UI.layout.elementSpacing, -(UI.layout.iconSize + UI.layout.paddingSmall))
    summaryBox:SetPoint("RIGHT", -UI.layout.elementSpacing, 0)
    summaryBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    summaryBox:SetBackdropColor(0.12, 0.12, 0.12, 1)

    local itemCountLabel = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemCountLabel:SetPoint("TOPLEFT", UI.layout.cardSpacing, -UI.layout.padding)
    popup.itemCountLabel = itemCountLabel

    local totalValueLabel = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalValueLabel:SetPoint("TOPLEFT", UI.layout.cardSpacing, -(UI.layout.rowHeightSmall + 2))
    totalValueLabel:SetTextColor(1, 0.84, 0, 1)
    popup.totalValueLabel = totalValueLabel

    -- Sell button (prominent)
    local sellBtn = UI:CreateButton(popup, "Sell All", UI.layout.buttonWidth, UI.layout.rowHeightSmall + 2)
    sellBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -UI.layout.cardSpacing, -(UI.layout.rowHeight + UI.layout.paddingSmall))
    sellBtn:SetScript("OnClick", function()
        if IM.modules.AutoSell then
            IM.modules.AutoSell:SellJunk()
        end
    end)
    popup.sellBtn = sellBtn

    -- Items header
    local itemsHeader = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemsHeader:SetPoint("TOPLEFT", UI.layout.elementSpacing, -UI.layout.buttonWidth)
    itemsHeader:SetText("Items to Sell")
    itemsHeader:SetTextColor(unpack(UI.colors.textDim))

    -- Items list container
    local itemsBox = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    itemsBox:SetPoint("TOPLEFT", UI.layout.elementSpacing, -(UI.layout.buttonWidth + UI.layout.iconSizeSmall))
    itemsBox:SetPoint("RIGHT", -UI.layout.elementSpacing, 0)
    itemsBox:SetPoint("BOTTOM", 0, 55)
    itemsBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    itemsBox:SetBackdropColor(0.08, 0.08, 0.08, 0.8)

    -- Scroll frame for items list
    local scrollFrame = CreateFrame("ScrollFrame", nil, itemsBox, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", UI.layout.paddingSmall, -UI.layout.paddingSmall)
    scrollFrame:SetPoint("BOTTOMRIGHT", -UI.layout.titleBarHeight, UI.layout.paddingSmall)
    popup.itemsScrollFrame = scrollFrame

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollContent)
    popup.itemsScrollContent = scrollContent

    -- Bottom bar
    local bottomBar = CreateFrame("Frame", nil, popup)
    bottomBar:SetHeight(50)
    bottomBar:SetPoint("BOTTOMLEFT", UI.layout.elementSpacing, UI.layout.paddingSmall)
    bottomBar:SetPoint("BOTTOMRIGHT", -UI.layout.elementSpacing, UI.layout.paddingSmall)

    -- Quality filter info
    local filterInfo = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterInfo:SetPoint("TOPLEFT", 0, -UI.layout.paddingSmall)
    filterInfo:SetTextColor(unpack(UI.colors.textDim))
    popup.filterInfo = filterInfo

    -- Edit settings button
    local editBtn = UI:CreateButton(bottomBar, "Settings", 70, UI.layout.buttonHeightSmall)
    editBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    editBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Config and IM.UI.Config.Show then
            IM.UI.Config:Show()
            C_Timer.After(0.1, function()
                if IM.UI.Config.SelectTab then
                    IM.UI.Config:SelectTab("Selling")
                end
                if IM.UI and IM.UI.Panels and IM.UI.Panels.Selling and IM.UI.Panels.Selling.SelectSubTabByName then
                    IM.UI.Panels.Selling:SelectSubTabByName("Auto-Sell")
                end
            end)
        end
    end)

    _popup = popup
    return popup
end

-- Refresh the popup content
function AutoSellPopup:Refresh()
    if not _popup then return end

    -- Get sellable items
    local sellableItems = {}
    local totalValue = 0
    local itemCount = 0

    if IM.Filters and IM.Filters.GetAutoSellItems then
        sellableItems = IM.Filters:GetAutoSellItems()
        for _, item in ipairs(sellableItems) do
            totalValue = totalValue + (item.totalValue or 0)
            itemCount = itemCount + (item.stackCount or 1)
        end
    end

    -- Update summary
    if itemCount > 0 then
        _popup.itemCountLabel:SetText(UI:ColorText(itemCount .. " items", "accent") .. " to sell")
        _popup.totalValueLabel:SetText("Worth: " .. IM:FormatMoney(totalValue))
        _popup.sellBtn:Enable()
    else
        _popup.itemCountLabel:SetText("|cff888888No sellable items|r")
        _popup.totalValueLabel:SetText("")
        _popup.sellBtn:Disable()
    end

    -- Update filter info
    local quality = IM.db and IM.db.global and IM.db.global.autoSell and IM.db.global.autoSell.maxQuality or 2
    local qualityNames = {"Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary"}
    local qualityColor = QUALITY_COLORS[quality] or "|cffffffff"
    _popup.filterInfo:SetText("Selling: " .. qualityColor .. (qualityNames[quality + 1] or "Unknown") .. "|r and below")

    -- Build items list
    self:RefreshItems(sellableItems)
end

-- Refresh the sellable items list
function AutoSellPopup:RefreshItems(sellableItems)
    if not _popup or not _popup.itemsScrollContent then return end

    local scrollContent = _popup.itemsScrollContent

    -- Clear existing content
    for _, child in pairs({scrollContent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    if scrollContent.noDataLabel then
        scrollContent.noDataLabel:Hide()
    end

    local yOffset = 0
    local maxItems = 8  -- Show up to 8 items before "...and X more"

    local rowHeight = UI.layout.iconSize
    local iconSize = UI.layout.iconSizeSmall
    
    for i, item in ipairs(sellableItems) do
        if i > maxItems then break end

        local itemRow = CreateFrame("Frame", nil, scrollContent)
        itemRow:SetHeight(rowHeight)
        itemRow:SetPoint("TOPLEFT", 0, yOffset)
        itemRow:SetPoint("RIGHT", 0, 0)

        -- Item icon
        local icon = itemRow:CreateTexture(nil, "OVERLAY")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("LEFT", UI.layout.paddingSmall, 0)
        if item.itemID then
            local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(item.itemID)
            icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Item name with quantity
        local itemLabel = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemLabel:SetPoint("LEFT", icon, "RIGHT", UI.layout.paddingSmall, 0)
        itemLabel:SetPoint("RIGHT", -60, 0)
        itemLabel:SetJustifyH("LEFT")
        local itemText = item.itemLink or ("Item #" .. (item.itemID or "?"))
        if item.stackCount and item.stackCount > 1 then
            itemText = itemText .. " x" .. item.stackCount
        end
        itemLabel:SetText(itemText)

        -- Value
        local valueLabel = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueLabel:SetPoint("RIGHT", -UI.layout.paddingSmall, 0)
        valueLabel:SetTextColor(1, 0.84, 0, 1)
        if item.totalValue and item.totalValue > 0 then
            valueLabel:SetText(IM:FormatMoney(item.totalValue))
        end

        yOffset = yOffset - rowHeight
    end

    -- Show "...and X more" if there are more items
    if #sellableItems > maxItems then
        local moreLabel = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        moreLabel:SetPoint("TOPLEFT", UI.layout.paddingSmall, yOffset)
        moreLabel:SetText("|cff888888... and " .. (#sellableItems - maxItems) .. " more|r")
        yOffset = yOffset - rowHeight
    end

    -- If no items
    if #sellableItems == 0 then
        if not scrollContent.noDataLabel then
            scrollContent.noDataLabel = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            scrollContent.noDataLabel:SetPoint("TOPLEFT", UI.layout.paddingSmall, 0)
        end
        scrollContent.noDataLabel:SetText("|cff888888All items are protected or excluded|r")
        scrollContent.noDataLabel:Show()
        yOffset = -rowHeight
        scrollContent:SetHeight(math.max(math.abs(yOffset), 1))
        return
    end

    scrollContent:SetHeight(math.max(math.abs(yOffset), 1))
end

-- Show the popup
function AutoSellPopup:Show()
    local popup = self:Create()

    -- Position relative to MerchantFrame if visible
    if MerchantFrame and MerchantFrame:IsShown() then
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 10, 0)
    end

    self:Refresh()
    popup:Show()
end

-- Hide the popup
function AutoSellPopup:Hide()
    if _popup then
        _popup:Hide()
    end
end

-- Toggle the popup
function AutoSellPopup:Toggle()
    if _popup and _popup:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Check if popup is shown
function AutoSellPopup:IsShown()
    return _popup and _popup:IsShown()
end

-- Update selling status
function AutoSellPopup:UpdateStatus(message)
    if _popup then
        -- Could update a status label if needed
    end
end
