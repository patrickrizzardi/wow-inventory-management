--[[
    InventoryManager - UI/MailPopup.lua
    Floating popup that shows when mailbox opens with pending mail queue.
]]

local addonName, IM = ...
local UI = IM.UI

UI.MailPopup = {}

local MailPopup = UI.MailPopup
local _popup = nil

-- Create the popup frame
function MailPopup:Create()
    if _popup then return _popup end

    local popup = CreateFrame("Frame", "InventoryManagerMailPopup", UIParent, "BackdropTemplate")
    popup:SetSize(280, 200)
    popup:SetPoint("TOPLEFT", MailFrame or UIParent, "TOPRIGHT", UI.layout.cardSpacing, 0)
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

    -- Register for Escape key closing (standard WoW pattern)
    tinsert(UISpecialFrames, "InventoryManagerMailPopup")

    -- Title bar (inset by 1px for border)
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
    title:SetText(UI:ColorText("Mail Helper", "accent"))

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

    -- Content area
    local content = CreateFrame("Frame", nil, popup)
    content:SetPoint("TOPLEFT", UI.layout.elementSpacing, -(UI.layout.iconSize + UI.layout.paddingSmall))
    content:SetPoint("BOTTOMRIGHT", -UI.layout.elementSpacing, UI.layout.bottomBarHeight)
    popup.content = content

    -- Status text (shown when no items)
    local statusText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", 0, 0)
    statusText:SetPoint("RIGHT", 0, 0)
    statusText:SetJustifyH("LEFT")
    popup.statusText = statusText

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -UI.layout.iconSize - 2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -UI.layout.iconSize, 0)
    popup.scrollFrame = scrollFrame

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollContent)
    popup.scrollContent = scrollContent

    -- Bottom buttons
    local bottomBar = CreateFrame("Frame", nil, popup)
    bottomBar:SetHeight(UI.layout.rowHeightSmall + 2)
    bottomBar:SetPoint("BOTTOMLEFT", UI.layout.elementSpacing, UI.layout.paddingSmall)
    bottomBar:SetPoint("BOTTOMRIGHT", -UI.layout.elementSpacing, UI.layout.paddingSmall)

    -- Add Rules button
    local addRulesBtn = UI:CreateButton(bottomBar, "Add Rules", 70, UI.layout.buttonHeightSmall)
    addRulesBtn:SetPoint("LEFT", 0, 0)
    addRulesBtn:SetScript("OnClick", function()
        -- Open InventoryManager to Mail Helper tab
        if IM.UI and IM.UI.Config and IM.UI.Config.Show then
            IM.UI.Config:Show()
            -- Find and click Mail Helper tab
            C_Timer.After(0.1, function()
                if IM.UI.Config.SelectTab then
                    IM.UI.Config:SelectTab("Mail Helper")
                end
            end)
        end
    end)
    popup.addRulesBtn = addRulesBtn

    -- Loot All button
    local lootAllBtn = UI:CreateButton(bottomBar, "Loot All", 60, UI.layout.buttonHeightSmall)
    lootAllBtn:SetPoint("LEFT", addRulesBtn, "RIGHT", 4, 0)
    lootAllBtn:SetScript("OnClick", function()
        if IM.modules.MailHelper then
            if IM.modules.MailHelper:IsLooting() then
                IM.modules.MailHelper:StopAutoLoot()
            else
                IM.modules.MailHelper:StartAutoLoot()
            end
        end
    end)
    popup.lootAllBtn = lootAllBtn

    -- Loot status text (shows progress during looting)
    local lootStatus = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootStatus:SetPoint("LEFT", lootAllBtn, "RIGHT", 6, 0)
    lootStatus:SetTextColor(0.7, 0.7, 0.7, 1)
    lootStatus:Hide()
    popup.lootStatus = lootStatus

    -- Send All button
    local sendAllBtn = UI:CreateButton(bottomBar, "Send All", 65, UI.layout.buttonHeightSmall)
    sendAllBtn:SetPoint("RIGHT", 0, 0)
    sendAllBtn:Hide()
    popup.sendAllBtn = sendAllBtn

    _popup = popup
    return popup
end

-- Refresh the popup content
function MailPopup:Refresh()
    if not _popup then return end

    local scrollContent = _popup.scrollContent

    -- Clear scroll content
    for _, child in pairs({scrollContent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    -- Get queue summary
    local summary = nil
    if IM.modules.MailHelper then
        summary = IM.modules.MailHelper:GetQueueSummary()
    end

    if not summary or summary.totalItems == 0 then
        _popup.statusText:SetText("|cff888888No items queued.\nAdd rules in Settings > Mail Helper.|r")
        _popup.sendAllBtn:Hide()
        _popup.scrollFrame:Hide()
        _popup:SetHeight(100)
        return
    end

    _popup.scrollFrame:Show()

    -- Show summary
    _popup.statusText:SetText("|cff00ff00" .. summary.totalItems .. " items|r queued for |cffffff00" .. summary.totalAlts .. " alt(s)|r")

    -- Build detailed list per alt
    local yOffset = 0
    local queue = IM.modules.MailHelper:GetQueue()

    for altKey, queueData in pairs(queue) do
        if #queueData.items > 0 then
            local altName = altKey:match("^(.+)-") or altKey

            -- Alt header
            local altHeader = CreateFrame("Frame", nil, scrollContent, "BackdropTemplate")
            altHeader:SetHeight(UI.layout.buttonHeightSmall)
            altHeader:SetPoint("TOPLEFT", 0, yOffset)
            altHeader:SetPoint("RIGHT", 0, 0)
            altHeader:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
            altHeader:SetBackdropColor(0.15, 0.12, 0.05, 1) -- warm amber tint

            local altLabel = altHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            altLabel:SetPoint("LEFT", UI.layout.paddingSmall, 0)
            altLabel:SetText("|cffffff00" .. altName .. "|r |cff888888(" .. #queueData.items .. " items)|r")

            -- Send button for this alt
            local sendBtn = UI:CreateButton(altHeader, "Send", 40, UI.layout.iconSize - 2)
            sendBtn:SetPoint("RIGHT", -2, 0)
            sendBtn:SetScript("OnClick", function()
                if IM.modules.MailHelper then
                    IM.modules.MailHelper:SendToAlt(altKey)
                    C_Timer.After(1, function()
                        IM.modules.MailHelper:AutoFillQueue()
                        MailPopup:Refresh()
                    end)
                end
            end)

            yOffset = yOffset - UI.layout.rowHeightSmall

            -- Item rows (show all items)
            local itemRowHeight = UI.layout.iconSize
            local iconSize = UI.layout.iconSizeSmall
            for i, queueItem in ipairs(queueData.items) do
                local itemRow = CreateFrame("Frame", nil, scrollContent)
                itemRow:SetHeight(itemRowHeight)
                itemRow:SetPoint("TOPLEFT", UI.layout.padding, yOffset)
                itemRow:SetPoint("RIGHT", -UI.layout.paddingSmall, 0)

                -- Item icon
                local icon = itemRow:CreateTexture(nil, "OVERLAY")
                icon:SetSize(iconSize, iconSize)
                icon:SetPoint("LEFT", 0, 0)
                if queueItem.itemInfo and queueItem.itemInfo.itemID then
                    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(queueItem.itemInfo.itemID)
                    icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                end

                -- Item name
                local itemLabel = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                itemLabel:SetPoint("LEFT", icon, "RIGHT", UI.layout.paddingSmall, 0)
                itemLabel:SetPoint("RIGHT", -UI.layout.paddingSmall, 0)
                itemLabel:SetJustifyH("LEFT")
                local itemText = queueItem.itemInfo and queueItem.itemInfo.itemLink or "Unknown"
                if queueItem.itemInfo and queueItem.itemInfo.stackCount > 1 then
                    itemText = itemText .. " x" .. queueItem.itemInfo.stackCount
                end
                itemLabel:SetText(itemText)

                yOffset = yOffset - itemRowHeight
            end

            yOffset = yOffset - UI.layout.elementSpacing -- Gap between alts
        end
    end

    -- Update scroll content height
    scrollContent:SetHeight(math.abs(yOffset) + UI.layout.cardSpacing)

    -- Update popup height (max 350)
    local totalHeight = UI.layout.buttonWidth + math.abs(yOffset)
    _popup:SetHeight(math.min(totalHeight, 350))

    -- Show send all button
    _popup.sendAllBtn:Show()
    _popup.sendAllBtn:SetText("Send All")
    _popup.sendAllBtn:SetScript("OnClick", function()
        if IM.modules.MailHelper then
            for altKey, queueData in pairs(queue) do
                if #queueData.items > 0 then
                    IM.modules.MailHelper:SendToAlt(altKey)
                end
            end
            C_Timer.After(2, function()
                IM.modules.MailHelper:AutoFillQueue()
                MailPopup:Refresh()
            end)
        end
    end)
end

-- Show the popup
function MailPopup:Show()
    local popup = self:Create()

    -- Position next to mailbox if possible
    if MailFrame and MailFrame:IsShown() then
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 10, 0)
    end

    -- Auto-refresh on bag updates while popup is shown
    if not popup.bagUpdateRegistered then
        popup:RegisterEvent("BAG_UPDATE")
        popup:RegisterEvent("MAIL_CLOSED")
        popup:SetScript("OnEvent", function(self, event)
            if event == "MAIL_CLOSED" then
                MailPopup:Hide()
                return
            end
            if event == "BAG_UPDATE" and MailPopup:IsShown() then
                -- Debounce refreshes
                if self.refreshTimer then self.refreshTimer:Cancel() end
                self.refreshTimer = C_Timer.NewTimer(0.3, function()
                    if IM.modules.MailHelper then
                        IM.modules.MailHelper:AutoFillQueue()
                        MailPopup:Refresh()
                    end
                end)
            end
        end)
        popup.bagUpdateRegistered = true
    end

    -- Close popup when the Blizzard mail frame hides (X button)
    if MailFrame and not popup.mailFrameHooked then
        MailFrame:HookScript("OnHide", function()
            MailPopup:Hide()
        end)
        popup.mailFrameHooked = true
    end

    -- Refresh and show
    self:Refresh()
    popup:Show()
end

-- Hide the popup
function MailPopup:Hide()
    if _popup then
        _popup:Hide()
        -- Cancel any pending refresh
        if _popup.refreshTimer then
            _popup.refreshTimer:Cancel()
            _popup.refreshTimer = nil
        end
    end
end

-- Check if popup is shown
function MailPopup:IsShown()
    return _popup and _popup:IsShown()
end

-- ============================================================================
-- LOOTING STATE CALLBACKS
-- ============================================================================

-- Called when looting starts
function MailPopup:OnLootingStarted(total)
    if not _popup then return end

    _popup.lootAllBtn.text:SetText("Stop")
    _popup.lootStatus:SetText("0/" .. total)
    _popup.lootStatus:Show()

    -- Disable send buttons during looting
    _popup.sendAllBtn:Disable()
end

-- Called during looting to update progress
function MailPopup:OnLootingProgress(current, total)
    if not _popup then return end

    _popup.lootStatus:SetText(current .. "/" .. total)
end

-- Called when looting stops (cancelled or error)
function MailPopup:OnLootingStopped()
    if not _popup then return end

    _popup.lootAllBtn.text:SetText("Loot All")
    _popup.lootStatus:Hide()

    -- Re-enable send buttons
    _popup.sendAllBtn:Enable()

    -- Refresh to update mail list
    self:Refresh()
end

-- Called when looting completes successfully
function MailPopup:OnLootingComplete(count)
    if not _popup then return end

    _popup.lootAllBtn.text:SetText("Loot All")
    _popup.lootStatus:Hide()

    -- Re-enable send buttons
    _popup.sendAllBtn:Enable()

    -- Refresh to update mail list
    self:Refresh()
end
