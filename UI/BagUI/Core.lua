--[[
    InventoryManager - UI/BagUI/Core.lua
    Main bag window frame, layout wiring, and bag UI interactions.

    Public Methods:
    - BagUI:Show() - Show the bag window
    - BagUI:Hide() - Hide the bag window
    - BagUI:Toggle() - Toggle visibility
    - BagUI:IsShown() - Check if visible
    - BagUI:GetFrame() - Get main frame
    - BagUI:GetContentFrame() - Get scroll content frame
    - BagUI:GetSearchText() - Get current search text
]]

local addonName, IM = ...
local UI = IM.UI

IM.UI.BagUI = IM.UI.BagUI or {}
local BagUI = IM.UI.BagUI

local BAG_TITLE = "InventoryManager Bags"
local SEARCH_PLACEHOLDER = "Search..."

local HEADER_HEIGHT = 28
local SEARCH_HEIGHT = 22
local FOOTER_HEIGHT = 26
local OUTER_PADDING = 10
local INNER_GAP = 6

local ITEM_SIZE = 36
local ITEM_SPACING = 4
local CATEGORY_GAP = 8
local SEARCH_TOP_GAP = 6
local SCROLL_FRAME_PADDING = 8
local CONTENT_PADDING = 4
local HEADER_ROW_ALLOWANCE = 20

local _frame = nil
local _initialized = false
local _callbacksRegistered = false
local _searchText = ""
local _lastContentHeight = 200

local function _GetSettings()
    local defaults = {
        scale = 1,
        itemColumns = 10,
        categoryColumns = 2,
        windowMode = "fixed",
        windowRows = 12,
    }
    if IM.db and IM.db.global and IM.db.global.bagUI then
        return IM.db.global.bagUI
    end
    return defaults
end

local function _CreateSearchBox(parent)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetHeight(SEARCH_HEIGHT)
    bg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    bg:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    bg:SetBackdropBorderColor(unpack(UI.colors.border))

    local editBox = CreateFrame("EditBox", nil, bg)
    editBox:SetFontObject("GameFontNormalSmall")
    editBox:SetAutoFocus(false)
    editBox:SetPoint("TOPLEFT", 6, 0)
    editBox:SetPoint("BOTTOMRIGHT", -6, 0)
    editBox:SetText(SEARCH_PLACEHOLDER)
    editBox:SetTextColor(unpack(UI.colors.textDim))

    editBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == SEARCH_PLACEHOLDER then
            self:SetText("")
            self:SetTextColor(unpack(UI.colors.text))
        end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self:SetText(SEARCH_PLACEHOLDER)
            self:SetTextColor(unpack(UI.colors.textDim))
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    bg.editBox = editBox
    return bg
end

local function _CreateFooterText(parent)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", OUTER_PADDING, 6)
    text:SetTextColor(unpack(UI.colors.textDim))
    return text
end

local function _CreateGoldButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(18)
    button:SetWidth(160)
    button:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -OUTER_PADDING, 6)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("RIGHT", button, "RIGHT", 0, 0)
    button.text:SetTextColor(unpack(UI.colors.text))
    button:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(UI.colors.accent))
    end)
    button:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(UI.colors.text))
    end)
    return button
end

local function _ApplyFixedHeight(frame, rows, scale, container)
    local scaleFactor = scale or 1
    local contentRows = math.max(1, rows or 12)
    local desiredScrollHeight = nil
    if container and container.GetHeightForItemRows then
        desiredScrollHeight = container:GetHeightForItemRows(contentRows)
    end
    if not desiredScrollHeight then
        desiredScrollHeight = (contentRows * (ITEM_SIZE + ITEM_SPACING)) - ITEM_SPACING
    end
    desiredScrollHeight = desiredScrollHeight / scaleFactor

    if frame.scrollContainer and frame.scrollContainer.scrollFrame then
        local scrollFrame = frame.scrollContainer.scrollFrame
        local delta = desiredScrollHeight - scrollFrame:GetHeight()
        frame:SetHeight(frame:GetHeight() + delta)
        _lastContentHeight = desiredScrollHeight
        return
    end

    local contentHeight = desiredScrollHeight + SCROLL_FRAME_PADDING
    _lastContentHeight = contentHeight
    local totalHeight = HEADER_HEIGHT + SEARCH_TOP_GAP + SEARCH_HEIGHT + INNER_GAP + FOOTER_HEIGHT + OUTER_PADDING + contentHeight
    frame:SetHeight(totalHeight)
end

local function _ApplyDynamicHeight(frame, contentHeight, scale)
    local scaleFactor = scale or 1
    local clampedHeight = math.max(120, (contentHeight or _lastContentHeight or 200) / scaleFactor)
    _lastContentHeight = clampedHeight

    local totalHeight = HEADER_HEIGHT + SEARCH_TOP_GAP + SEARCH_HEIGHT + INNER_GAP + FOOTER_HEIGHT + OUTER_PADDING + clampedHeight
    frame:SetHeight(totalHeight)
end

local function _ApplyWidth(frame, settings)
    local itemColumns = settings.itemColumns or 10
    local categoryColumns = settings.categoryColumns or 2
    local categoryWidth = (itemColumns * (ITEM_SIZE + ITEM_SPACING)) - ITEM_SPACING
    local totalWidth = (categoryWidth * categoryColumns) + (CATEGORY_GAP * (categoryColumns - 1)) + (OUTER_PADDING * 2) + 26
    frame:SetWidth(math.max(420, totalWidth))
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function BagUI:GetFrame()
    return _frame
end

function BagUI:GetContentFrame()
    if _frame and _frame.scrollContainer then
        return _frame.scrollContainer.content
    end
    return nil
end

function BagUI:GetSearchText()
    return _searchText or ""
end

function BagUI:IsShown()
    return _frame and _frame:IsShown()
end

function BagUI:ApplyLayoutSettings()
    if not _frame then return end

    local settings = _GetSettings()
    _frame:SetScale(settings.scale or 1)
    _ApplyWidth(_frame, settings)

    if self.Container and self.Container.Refresh then
        self.Container:Refresh(_searchText)
    end

    _ApplyFixedHeight(_frame, settings.windowRows or 12, settings.scale or 1, self.Container)
end

function BagUI:ApplyKeybindOverrides()
    local BagHooks = IM:GetModule("BagHooks")
    if BagHooks and BagHooks.Initialize then
        BagHooks:Initialize()
    end
    
    -- Create a secure button that we can bind to override bag keys
    if not self._keybindFrame then
        local frame = CreateFrame("Frame", "InventoryManagerBagKeyFrame", UIParent)
        frame:SetSize(1, 1)
        frame:Hide()
        
        local button = CreateFrame("Button", "InventoryManagerBagToggleBtn", frame, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function()
            if IM.UI and IM.UI.BagUI and IM.UI.BagUI.Toggle then
                IM.UI.BagUI:Toggle()
            end
        end)
        
        self._keybindFrame = frame
        self._keybindButton = button
    end
    
    -- Only apply overrides if IM bags are enabled
    if not (IM.db and IM.db.global and IM.db.global.useIMBags) then
        ClearOverrideBindings(self._keybindFrame)
        IM:Debug("[BagUI] Keybind overrides cleared (IM bags disabled)")
        return
    end
    
    -- Clear any existing overrides
    ClearOverrideBindings(self._keybindFrame)
    
    -- Get all bag-related keybinds and override them
    local bagBindings = {
        "OPENALLBAGS",
        "TOGGLEBACKPACK", 
        "TOGGLEBAG1",
        "TOGGLEBAG2", 
        "TOGGLEBAG3",
        "TOGGLEBAG4",
    }
    
    local overrideCount = 0
    for _, bindingName in ipairs(bagBindings) do
        local key1, key2 = GetBindingKey(bindingName)
        if key1 then
            SetOverrideBindingClick(self._keybindFrame, true, key1, "InventoryManagerBagToggleBtn", "LeftButton")
            overrideCount = overrideCount + 1
            IM:Debug("[BagUI] Override set for " .. key1 .. " (" .. bindingName .. ")")
        end
        if key2 then
            SetOverrideBindingClick(self._keybindFrame, true, key2, "InventoryManagerBagToggleBtn", "LeftButton")
            overrideCount = overrideCount + 1
            IM:Debug("[BagUI] Override set for " .. key2 .. " (" .. bindingName .. ")")
        end
    end
    
    -- Always force B to toggle IM bags
    SetOverrideBindingClick(self._keybindFrame, true, "B", "InventoryManagerBagToggleBtn", "LeftButton")
    overrideCount = overrideCount + 1

    IM:Debug("[BagUI] Applied " .. overrideCount .. " keybind overrides")
end

function BagUI:UpdateGold()
    if not _frame or not _frame.goldButton then return end
    local money = GetMoney() or 0
    _frame.goldButton.text:SetText(IM:FormatMoney(money))
end

function BagUI:UpdateBagStats()
    if not _frame or not _frame.statsText then return end

    local bagUsed, bagTotal = 0, 0
    for bagID = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0
        bagTotal = bagTotal + slots
        for slotID = 1, slots do
            if C_Container.GetContainerItemInfo(bagID, slotID) then
                bagUsed = bagUsed + 1
            end
        end
    end

    local reagentSlots = C_Container.GetContainerNumSlots(5) or 0
    local reagentUsed = 0
    if reagentSlots > 0 then
        for slotID = 1, reagentSlots do
            if C_Container.GetContainerItemInfo(5, slotID) then
                reagentUsed = reagentUsed + 1
            end
        end
    end

    local totalUsed = bagUsed + reagentUsed
    local totalSlots = bagTotal + reagentSlots

    _frame.statsText:SetText(string.format("Bag: %d/%d  |  Reagent: %d/%d  |  Total: %d/%d", bagUsed, bagTotal, reagentUsed, reagentSlots, totalUsed, totalSlots))
end

function BagUI:OpenNetWorth()
    if not IM.UI or not IM.UI.Dashboard then return end
    local dashboard = IM.UI.Dashboard
    dashboard:Show()
    local frame = dashboard:Create()
    if frame and frame.SelectTab then
        frame.SelectTab("networth")
    end
end

function BagUI:HandleBackgroundDrop()
    local cursorType, itemID = GetCursorInfo()
    if cursorType ~= "item" or not itemID then
        return
    end

    local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
    local reagentClassID = (Enum and Enum.ItemClass and Enum.ItemClass.Reagent) or 5
    local isReagent = classID == reagentClassID

    local function hasSpace(bagID)
        local slots = C_Container.GetContainerNumFreeSlots(bagID)
        return (slots and slots > 0) or false
    end

    local targetBag = nil
    if isReagent and hasSpace(5) then
        targetBag = 5
    else
        if hasSpace(0) then
            targetBag = 0
        else
            for bagID = 1, 4 do
                if hasSpace(bagID) then
                    targetBag = bagID
                    break
                end
            end
        end
    end

    if not targetBag then
        return
    end

    if targetBag == 0 then
        PutItemInBackpack()
    else
        local inventoryID = C_Container.ContainerIDToInventoryID(targetBag)
        if inventoryID then
            PutItemInBag(inventoryID)
        end
    end
end

function BagUI:Initialize()
    if _initialized then return end
    _initialized = true

    local frame = UI:CreatePanel("InventoryManagerBags", UIParent, 520, 560)
    frame:ClearAllPoints()
    if IM.db and IM.db.global and IM.db.global.bagUI and IM.db.global.bagUI.windowPosition then
        local pos = IM.db.global.bagUI.windowPosition
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableKeyboard(false)
    frame:SetPropagateKeyboardInput(true)
    frame:Hide()

    -- Add to special frames for ESC close
    if frame:GetName() then
        table.insert(UISpecialFrames, frame:GetName())
    end

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if IM.db and IM.db.global and IM.db.global.bagUI then
            local point, _, relativePoint, x, y = self:GetPoint()
            IM.db.global.bagUI.windowPosition = {
                point = point,
                relativePoint = relativePoint,
                x = x,
                y = y,
            }
        end
    end)

    local header = UI:CreateHeader(frame, BAG_TITLE)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local settingsButton = CreateFrame("Button", nil, header)
    settingsButton:SetSize(16, 16)
    settingsButton:SetPoint("RIGHT", header.closeButton, "LEFT", -6, 0)
    settingsButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsButton:SetPushedTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    settingsButton:SetScript("OnClick", function()
        if IM.UI and IM.UI.ShowConfig then
            IM.UI:ShowConfig()
            IM.UI:SelectTabByName("Bag UI")
        end
    end)

    local searchBox = _CreateSearchBox(frame)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", OUTER_PADDING, -HEADER_HEIGHT - 6)
    searchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -OUTER_PADDING, -HEADER_HEIGHT - 6)

    local scrollContainer = UI:CreateScrollFrame(frame, nil, nil, true)
    scrollContainer:ClearAllPoints()
    scrollContainer:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -INNER_GAP)
    scrollContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -OUTER_PADDING, FOOTER_HEIGHT + OUTER_PADDING)
    scrollContainer:SetBackdropColor(0.05, 0.05, 0.05, 0.2)

    local content = scrollContainer.content
    content:SetPoint("TOPLEFT", scrollContainer.scrollFrame, "TOPLEFT", 0, 0)

    -- Container will be created lazily when needed (after Container.lua loads)
    local containerFrame = nil

    local statsText = _CreateFooterText(frame)
    local goldButton = _CreateGoldButton(frame)
    goldButton:SetScript("OnClick", function() BagUI:OpenNetWorth() end)

    searchBox.editBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text == SEARCH_PLACEHOLDER then
            _searchText = ""
        else
            _searchText = text or ""
        end
        if BagUI.Container and BagUI.Container.ApplySearch then
            BagUI.Container:ApplySearch(_searchText)
        end
    end)

    scrollContainer:EnableMouse(true)
    scrollContainer:SetScript("OnReceiveDrag", function() BagUI:HandleBackgroundDrop() end)
    scrollContainer:SetScript("OnSizeChanged", function()
        if BagUI.Container and BagUI.Container.Refresh then
            BagUI.Container:Refresh(_searchText)
        end
    end)
    content:EnableMouse(true)
    content:SetScript("OnReceiveDrag", function() BagUI:HandleBackgroundDrop() end)

    frame.searchBox = searchBox
    frame.scrollContainer = scrollContainer
    frame.statsText = statsText
    frame.goldButton = goldButton

    _frame = frame

    local BagHooks = IM:GetModule("BagHooks")
    if BagHooks and BagHooks.SetBagUI then
        BagHooks:SetBagUI(self)
    end

    local bagUI = self
    if not _callbacksRegistered then
        _callbacksRegistered = true

        local BagData = IM:GetModule("BagData")
        if BagData then
            local function queueRefresh()
                if bagUI.Container then
                    bagUI.Container:QueueRefresh()
                end
                bagUI:UpdateBagStats()
            end

            BagData:RegisterCallback("OnBagItemAdded", queueRefresh)
            BagData:RegisterCallback("OnBagItemRemoved", queueRefresh)
            BagData:RegisterCallback("OnBagItemChanged", queueRefresh)
        end

        IM:RegisterEvent("PLAYER_MONEY", function()
            bagUI:UpdateGold()
        end)
    end

    self:ApplyLayoutSettings()
    self:UpdateGold()
    self:UpdateBagStats()
    
    -- Apply keybind overrides to intercept bag keys
    self:ApplyKeybindOverrides()
    
    -- Re-apply when bindings change
    IM:RegisterEvent("UPDATE_BINDINGS", function()
        if _initialized then
            self:ApplyKeybindOverrides()
        end
    end)

    IM:Debug("[BagUI] Initialized")
end

function BagUI:Show()
    IM:Debug("[BagUI] Show() called")
    if InCombatLockdown() then 
        IM:Debug("[BagUI] Show() blocked - combat lockdown")
        return 
    end

    if IM.db and IM.db.global and not IM.db.global.useIMBags then
        IM:Debug("[BagUI] Show() blocked - useIMBags is false")
        return
    end

    if not _initialized then
        IM:Debug("[BagUI] Show() - initializing first")
        self:Initialize()
    end

    if not _frame then 
        IM:Debug("[BagUI] Show() blocked - no frame!")
        return 
    end

    -- Create container if not yet created (lazy init after Container.lua loads)
    if not self.Container and IM.UI.BagUI.Container then
        local Container = IM.UI.BagUI.Container
        local content = self:GetContentFrame()
        if content and Container.Create then
            local containerFrame = Container:Create(content)
            containerFrame.onLayoutChanged = function(height)
                local settings = _GetSettings()
                if settings.windowMode == "dynamic" then
                    _ApplyDynamicHeight(_frame, height)
                end
            end
            self.Container = containerFrame
        end
    end

    local BagData = IM:GetModule("BagData")
    if BagData then
        BagData:ForceRefresh()
    end

    _frame:Show()
    IM:Debug("[BagUI] Frame shown, IsShown=" .. tostring(_frame:IsShown()) .. ", Alpha=" .. tostring(_frame:GetAlpha()))
    if _frame.searchBox and _frame.searchBox.editBox then
        _frame.searchBox.editBox:ClearFocus()
    end
    
    -- Force hide Blizzard bags if they're showing
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        IM:Debug("[BagUI] Hiding ContainerFrameCombinedBags")
        ContainerFrameCombinedBags:Hide()
    end
    for i = 1, 13 do
        local blizzFrame = _G["ContainerFrame" .. i]
        if blizzFrame and blizzFrame:IsShown() then
            IM:Debug("[BagUI] Hiding ContainerFrame" .. i)
            blizzFrame:Hide()
        end
    end
    
    self:UpdateGold()
    self:UpdateBagStats()
    if self.Container and self.Container.Refresh then
        self.Container:Refresh(_searchText)
    end

    if self.Container and self.Container.GetHeightForItemRows then
        local settings = _GetSettings()
        _ApplyFixedHeight(_frame, settings.windowRows or 12, settings.scale or 1, self.Container)
    end

    PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
end

-- Track when we intentionally hide to prevent polling from re-opening
local _intentionalHide = false
local _hideTime = 0

function BagUI:Hide()
    if InCombatLockdown() then return end

    if _frame and _frame:IsShown() then
        _intentionalHide = true
        _hideTime = GetTime()
        _frame:Hide()
        PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
        IM:Debug("[BagUI] Hide() - frame hidden, intentional flag set")
    end
end

function BagUI:WasIntentionallyHidden()
    -- Consider it intentional for 0.5 seconds after hiding
    if _intentionalHide and (GetTime() - _hideTime) < 0.5 then
        return true
    end
    _intentionalHide = false
    return false
end

function BagUI:Toggle()
    IM:Debug("[BagUI] Toggle() called, IsShown=" .. tostring(_frame and _frame:IsShown()))
    if InCombatLockdown() then return end

    if _frame and _frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Initialize on login if IM bags enabled
IM:RegisterEvent("PLAYER_LOGIN", function()
    if IM.db and IM.db.global and IM.db.global.useIMBags then
        C_Timer.After(0.5, function()
            BagUI:Initialize()
        end)
    end
end)
