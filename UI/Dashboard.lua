--[[
    InventoryManager - UI/Dashboard.lua
    Standalone floating dashboard showing Net Worth and Ledger summary.
]]

local addonName, IM = ...
local UI = IM.UI

UI.Dashboard = {}

local Dashboard = UI.Dashboard
local _dashboard = nil
local _activeTab = "networth"

-- Filter state (loaded from database on create)
local _ledgerFilters = {
    typeIndex = 1,
    dateIndex = 5,
    charIndex = 1,
    search = "",
}

-- Pagination state
local _paginationLimit = 10
local _searchDebounceTimer = nil
local _onSizeChangedTimer = nil

-- Frame pools for reusable UI elements
local _framePool = {
    networth = {},  -- Character row frames
    ledger = {},    -- Transaction row frames
    inventory = {}, -- Inventory row frames
}

-- Class colors for character display
local CLASS_COLORS = {
    WARRIOR = {0.78, 0.61, 0.43},
    PALADIN = {0.96, 0.55, 0.73},
    HUNTER = {0.67, 0.83, 0.45},
    ROGUE = {1.0, 0.96, 0.41},
    PRIEST = {1.0, 1.0, 1.0},
    DEATHKNIGHT = {0.77, 0.12, 0.23},
    SHAMAN = {0.0, 0.44, 0.87},
    MAGE = {0.41, 0.80, 0.94},
    WARLOCK = {0.58, 0.51, 0.79},
    MONK = {0.0, 1.0, 0.59},
    DRUID = {1.0, 0.49, 0.04},
    DEMONHUNTER = {0.64, 0.19, 0.79},
    EVOKER = {0.20, 0.58, 0.50},
}

-- Frame pooling helper functions (Performance Fix #4)
local function GetPooledFrame(poolKey, parent, template)
    local pool = _framePool[poolKey]
    for i, frame in ipairs(pool) do
        if not frame:IsShown() then
            frame:SetParent(parent)
            frame:Show()
            return frame
        end
    end
    -- No available frame, create new one
    local newFrame = CreateFrame("Frame", nil, parent, template or "BackdropTemplate")
    table.insert(pool, newFrame)
    return newFrame
end

local function ReleaseAllFrames(poolKey)
    local pool = _framePool[poolKey]
    for _, frame in ipairs(pool) do
        frame:Hide()
        frame:ClearAllPoints()
    end
end

-- Create the dashboard frame
function Dashboard:Create()
    if _dashboard then return _dashboard end

    local frame = CreateFrame("Frame", "InventoryManagerDashboard", UIParent, "BackdropTemplate")
    frame:SetSize(420, 440)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(UI.colors.background))
    frame:SetBackdropBorderColor(unpack(UI.colors.border))
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(350, 350, 800, 800)  -- Min 350x350, Max 800x800
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._userPositioned = true  -- Track that user moved the frame
    end)
    frame:Hide()

    -- Resize grip (bottom-right corner)
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function(self)
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function(self)
        frame:StopMovingOrSizing()
        frame._userPositioned = true
        -- Refresh content to update scroll widths
        C_Timer.After(0.05, function()
            if Dashboard.RefreshContent then
                Dashboard:RefreshContent()
            end
        end)
    end)

    -- Update scroll widths when frame size changes (Bug #6 fix: debounce with 0.05s defer)
    frame:SetScript("OnSizeChanged", function(self)
        -- Cancel previous timer to debounce rapid resize events
        if _onSizeChangedTimer then
            _onSizeChangedTimer:Cancel()
        end

        _onSizeChangedTimer = C_Timer.NewTimer(0.05, function()
            -- Update all scroll child widths
            if frame.networthContent and frame.networthContent.scrollFrame and frame.networthContent.charList then
                local w = frame.networthContent.scrollFrame:GetWidth()
                if w and w > 0 then
                    frame.networthContent.charList:SetWidth(w)
                end
            end
            if frame.ledgerContent and frame.ledgerContent.scrollFrame and frame.ledgerContent.transList then
                local w = frame.ledgerContent.scrollFrame:GetWidth()
                if w and w > 0 then
                    frame.ledgerContent.transList:SetWidth(w)
                end
            end
            if frame.inventoryContent and frame.inventoryContent.scrollFrame and frame.inventoryContent.resultsList then
                local w = frame.inventoryContent.scrollFrame:GetWidth()
                if w and w > 0 then
                    frame.inventoryContent.resultsList:SetWidth(w)
                end
            end
        end)
    end)

    -- Register for Escape key closing
    tinsert(UISpecialFrames, "InventoryManagerDashboard")

    -- Title bar (inset by 1px for border)
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(24)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    titleBar:SetBackdropColor(0.15, 0.12, 0.05, 1)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 8, 0)
    title:SetText(UI:ColorText("InventoryManager Dashboard", "accent"))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeBtn.text:SetPoint("CENTER")
    closeBtn.text:SetText("|cffff6666X|r")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:SetScript("OnEnter", function(self) self.text:SetText("|cffff0000X|r") end)
    closeBtn:SetScript("OnLeave", function(self) self.text:SetText("|cffff6666X|r") end)

    -- Tab bar (inset by 1px to sit inside border)
    local tabBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tabBar:SetHeight(28)
    tabBar:SetPoint("TOPLEFT", 1, -24)
    tabBar:SetPoint("TOPRIGHT", -1, -24)
    tabBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    tabBar:SetBackdropColor(0.1, 0.1, 0.1, 1)

    -- Create tabs
    local tabs = {}
    local tabData = {
        {id = "networth", label = "Net Worth"},
        {id = "ledger", label = "Ledger"},
        {id = "inventory", label = "Inventory"},
    }

    local function SelectTab(tabId)
        _activeTab = tabId
        for _, tab in pairs(tabs) do
            if tab.id == tabId then
                tab:SetBackdropColor(unpack(UI.colors.accent))
                tab.text:SetTextColor(0, 0, 0, 1)
            else
                tab:SetBackdropColor(0.15, 0.15, 0.15, 1)
                tab.text:SetTextColor(unpack(UI.colors.text))
            end
        end
        -- Show/hide content
        if frame.networthContent then
            frame.networthContent:SetShown(tabId == "networth")
        end
        if frame.ledgerContent then
            frame.ledgerContent:SetShown(tabId == "ledger")
        end
        if frame.inventoryContent then
            frame.inventoryContent:SetShown(tabId == "inventory")
        end
        -- Refresh active tab
        Dashboard:RefreshContent()
    end

    local tabX = 4
    local TAB_WIDTH = 80
    local TAB_SPACING = 2
    for _, data in ipairs(tabData) do
        local tab = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        tab:SetSize(TAB_WIDTH, 22)
        tab:SetPoint("LEFT", tabX, 0)
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        tab:SetBackdropBorderColor(unpack(UI.colors.border))

        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tab.text:SetPoint("CENTER")
        tab.text:SetText(data.label)

        tab.id = data.id
        tab:SetScript("OnClick", function() SelectTab(data.id) end)

        tabs[data.id] = tab
        tabX = tabX + TAB_WIDTH + TAB_SPACING
    end

    frame.tabs = tabs
    frame.SelectTab = SelectTab

    -- Content area
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", 8, -56)
    contentArea:SetPoint("BOTTOMRIGHT", -8, 36)
    frame.contentArea = contentArea

    -- Create Net Worth content
    self:CreateNetWorthContent(frame)

    -- Create Ledger content
    self:CreateLedgerContent(frame)

    -- Create Inventory content
    self:CreateInventoryContent(frame)

    -- Bottom bar with "Open Settings" button (inset by 1px for border)
    local bottomBar = CreateFrame("Frame", nil, frame)
    bottomBar:SetHeight(30)
    bottomBar:SetPoint("BOTTOMLEFT", 1, 1)
    bottomBar:SetPoint("BOTTOMRIGHT", -1, 1)

    local settingsBtn = UI:CreateButton(bottomBar, "Open Full Settings", 130, 24)
    settingsBtn:SetPoint("CENTER", 0, 4)
    settingsBtn:SetScript("OnClick", function()
        if IM.UI and IM.UI.Config and IM.UI.Config.Show then
            IM.UI.Config:Show()
            -- Navigate to appropriate tab
            C_Timer.After(0.1, function()
                if IM.UI.Config.SelectTab then
                    IM.UI.Config:SelectTab("Tracking")
                end
            end)
        end
        frame:Hide()
    end)

    -- Initialize with networth tab
    SelectTab("networth")

    _dashboard = frame
    return frame
end

-- Create Net Worth tab content
function Dashboard:CreateNetWorthContent(frame)
    local content = CreateFrame("Frame", nil, frame.contentArea)
    content:SetAllPoints()
    frame.networthContent = content

    -- Running total breakdown box
    local breakdownBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    breakdownBox:SetHeight(130)
    breakdownBox:SetPoint("TOPLEFT", 0, 0)
    breakdownBox:SetPoint("RIGHT", 0, 0)
    breakdownBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    breakdownBox:SetBackdropColor(0.12, 0.12, 0.12, 1)

    local headerLabel = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerLabel:SetPoint("TOPLEFT", 10, -6)
    headerLabel:SetText(UI:ColorText("ACCOUNT NET WORTH", "accent"))

    -- Row 1: Character Gold
    local charGoldLabel = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charGoldLabel:SetPoint("TOPLEFT", 10, -24)
    charGoldLabel:SetText("Character Gold:")
    charGoldLabel:SetTextColor(unpack(UI.colors.textDim))

    local charGoldValue = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charGoldValue:SetPoint("TOPRIGHT", -10, -24)
    charGoldValue:SetTextColor(1, 0.84, 0, 1)
    content.charGoldValue = charGoldValue

    -- Row 2: Warband Bank (with + prefix)
    local warbandLabel = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warbandLabel:SetPoint("TOPLEFT", 10, -40)
    warbandLabel:SetText("Warband Bank:")
    warbandLabel:SetTextColor(unpack(UI.colors.textDim))

    local warbandValue = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warbandValue:SetPoint("TOPRIGHT", -10, -40)
    warbandValue:SetTextColor(1, 0.84, 0, 1)
    content.warbandValue = warbandValue

    -- Divider line 1
    local divider1 = breakdownBox:CreateTexture(nil, "ARTWORK")
    divider1:SetHeight(1)
    divider1:SetPoint("TOPLEFT", 140, -54)
    divider1:SetPoint("RIGHT", -10, 0)
    divider1:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Row 3: Liquid Gold (subtotal)
    local liquidLabel = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    liquidLabel:SetPoint("TOPLEFT", 10, -60)
    liquidLabel:SetText("|cff00ff00Liquid Gold:|r")

    local liquidValue = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    liquidValue:SetPoint("TOPRIGHT", -10, -60)
    liquidValue:SetTextColor(0, 1, 0, 1)
    content.liquidValue = liquidValue

    -- Row 4: Inventory Value (with + prefix)
    local invLabel = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    invLabel:SetPoint("TOPLEFT", 10, -76)
    invLabel:SetText("Inventory Value:")
    invLabel:SetTextColor(unpack(UI.colors.textDim))

    local invValue = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    invValue:SetPoint("TOPRIGHT", -10, -76)
    invValue:SetTextColor(0.7, 0.7, 0.7, 1)
    content.invValue = invValue

    -- Divider line 2
    local divider2 = breakdownBox:CreateTexture(nil, "ARTWORK")
    divider2:SetHeight(1)
    divider2:SetPoint("TOPLEFT", 140, -90)
    divider2:SetPoint("RIGHT", -10, 0)
    divider2:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Row 5: Total Net Worth (final)
    local totalLabel = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalLabel:SetPoint("TOPLEFT", 10, -98)
    totalLabel:SetText(UI:ColorText("Total Net Worth:", "accent"))

    local totalValue = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalValue:SetPoint("TOPRIGHT", -10, -98)
    totalValue:SetTextColor(1, 0.84, 0, 1)
    content.totalValue = totalValue

    -- Inventory hint
    local invHint = breakdownBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    invHint:SetPoint("BOTTOMLEFT", 10, 4)
    invHint:SetText("|cff666666Inventory requires vendor price data (login to each character)|r")

    -- Characters header
    local charHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charHeader:SetPoint("TOPLEFT", 0, -138)
    charHeader:SetText("All Characters")
    charHeader:SetTextColor(unpack(UI.colors.textDim))

    -- Character count
    local charCount = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCount:SetPoint("TOPRIGHT", 0, -138)
    charCount:SetTextColor(unpack(UI.colors.textDim))
    content.charCount = charCount

    -- Character scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -154)
    scrollFrame:SetPoint("RIGHT", -24, 0)
    scrollFrame:SetPoint("BOTTOM", 0, 0)

    -- Style the scroll bar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
    end

    -- Scroll child (actual content container)
    local charList = CreateFrame("Frame", nil, scrollFrame)
    charList:SetWidth(380)
    charList:SetHeight(1) -- Will be set dynamically
    scrollFrame:SetScrollChild(charList)

    -- Update width when scroll frame is shown
    scrollFrame:SetScript("OnShow", function(self)
        local w = self:GetWidth()
        if w and w > 0 then
            charList:SetWidth(w)
        end
    end)

    content.scrollFrame = scrollFrame
    content.charList = charList
end

-- Create Ledger tab content
function Dashboard:CreateLedgerContent(frame)
    local content = CreateFrame("Frame", nil, frame.contentArea)
    content:SetAllPoints()
    content:Hide()
    frame.ledgerContent = content

    -- Load filter state from database
    if IM.db and IM.db.global and IM.db.global.dashboard then
        _ledgerFilters.typeIndex = IM.db.global.dashboard.ledgerTypeFilter or 1
        _ledgerFilters.dateIndex = IM.db.global.dashboard.ledgerDateFilter or 5
        _ledgerFilters.charIndex = IM.db.global.dashboard.ledgerCharFilter or 1
        _ledgerFilters.search = IM.db.global.dashboard.ledgerSearch or ""
    end

    local yOffset = 0

    -- Search row (above filters) - UX Fix #8: Persistent label
    local searchRow = CreateFrame("Frame", nil, content, "BackdropTemplate")
    searchRow:SetHeight(28)
    searchRow:SetPoint("TOPLEFT", 0, yOffset)
    searchRow:SetPoint("RIGHT", 0, 0)
    searchRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    searchRow:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    local searchLabel = searchRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("LEFT", 8, 0)
    searchLabel:SetText("Search Ledger:")
    searchLabel:SetTextColor(unpack(UI.colors.accent))

    local searchInput = CreateFrame("EditBox", nil, searchRow, "BackdropTemplate")
    searchInput:SetSize(320, 20)
    searchInput:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    searchInput:SetFontObject("GameFontNormalSmall")
    searchInput:SetAutoFocus(false)
    searchInput:SetMaxLetters(50)
    searchInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    searchInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    searchInput:SetBackdropBorderColor(unpack(UI.colors.border))
    searchInput:SetTextInsets(6, 6, 0, 0)
    searchInput:SetTextColor(unpack(UI.colors.text))
    searchInput:SetText(_ledgerFilters.search or "")

    local searchPlaceholder = searchInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchPlaceholder:SetPoint("LEFT", 6, 0)
    searchPlaceholder:SetText("Filter by item, source...")
    searchPlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)
    if _ledgerFilters.search and _ledgerFilters.search ~= "" then
        searchPlaceholder:Hide()
    end

    searchInput:SetScript("OnEditFocusGained", function(self)
        searchPlaceholder:Hide()
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)
    searchInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchPlaceholder:Show() end
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)
    searchInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            local text = self:GetText()
            if text == "" then
                searchPlaceholder:Show()
            else
                searchPlaceholder:Hide()
            end
            -- Debounce search (Bug #12: Closure scoping fix)
            if _searchDebounceTimer then
                _searchDebounceTimer:Cancel()
            end
            local module = Dashboard
            _searchDebounceTimer = C_Timer.NewTimer(0.3, function()
                _ledgerFilters.search = text
                _paginationLimit = 10  -- Reset pagination on search
                if IM.db and IM.db.global and IM.db.global.dashboard then
                    IM.db.global.dashboard.ledgerSearch = text
                end
                module:RefreshLedger()
            end)
        end
    end)
    content.searchInput = searchInput

    yOffset = yOffset - 30

    -- Filter row (dropdowns only)
    local filterRow = CreateFrame("Frame", nil, content, "BackdropTemplate")
    filterRow:SetHeight(32)
    filterRow:SetPoint("TOPLEFT", 0, yOffset)
    filterRow:SetPoint("RIGHT", 0, 0)
    filterRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    filterRow:SetBackdropColor(0.08, 0.08, 0.08, 0.8)

    -- Type filter dropdown
    local typeLabel = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLabel:SetPoint("LEFT", 8, 0)
    typeLabel:SetText("Type:")
    typeLabel:SetTextColor(unpack(UI.colors.textDim))

    local typeDropdown = CreateFrame("Frame", nil, filterRow, "UIDropDownMenuTemplate")
    typeDropdown:SetPoint("LEFT", typeLabel, "RIGHT", -12, -2)
    UIDropDownMenu_SetWidth(typeDropdown, 80)

    local function TypeDropdown_Init()
        local presets = {}
        if IM.modules.Ledger then
            presets = IM.modules.Ledger:GetTypePresets()
        end
        for i, preset in ipairs(presets) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = preset.label
            info.value = i
            info.checked = (_ledgerFilters.typeIndex == i)
            info.func = function(self)
                _ledgerFilters.typeIndex = self.value
                _paginationLimit = 10  -- Reset pagination on filter change
                if IM.db and IM.db.global and IM.db.global.dashboard then
                    IM.db.global.dashboard.ledgerTypeFilter = self.value
                end
                UIDropDownMenu_SetText(typeDropdown, preset.label)
                Dashboard:RefreshLedger()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(typeDropdown, TypeDropdown_Init)
    local typePresets = IM.modules.Ledger and IM.modules.Ledger:GetTypePresets() or {{label = "All Types"}}
    UIDropDownMenu_SetText(typeDropdown, typePresets[_ledgerFilters.typeIndex] and typePresets[_ledgerFilters.typeIndex].label or "All Types")
    content.typeDropdown = typeDropdown

    -- Date filter dropdown
    local dateDropdown = CreateFrame("Frame", nil, filterRow, "UIDropDownMenuTemplate")
    dateDropdown:SetPoint("LEFT", typeDropdown, "RIGHT", -24, 0)
    UIDropDownMenu_SetWidth(dateDropdown, 70)

    local function DateDropdown_Init()
        local presets = {}
        if IM.modules.Ledger then
            presets = IM.modules.Ledger:GetDatePresets()
        end
        for i, preset in ipairs(presets) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = preset.label
            info.value = i
            info.checked = (_ledgerFilters.dateIndex == i)
            info.func = function(self)
                _ledgerFilters.dateIndex = self.value
                _paginationLimit = 10  -- Reset pagination on filter change
                if IM.db and IM.db.global and IM.db.global.dashboard then
                    IM.db.global.dashboard.ledgerDateFilter = self.value
                end
                UIDropDownMenu_SetText(dateDropdown, preset.label)
                Dashboard:RefreshLedger()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(dateDropdown, DateDropdown_Init)
    local datePresets = IM.modules.Ledger and IM.modules.Ledger:GetDatePresets() or {{label = "All Time"}}
    UIDropDownMenu_SetText(dateDropdown, datePresets[_ledgerFilters.dateIndex] and datePresets[_ledgerFilters.dateIndex].label or "All Time")
    content.dateDropdown = dateDropdown

    -- Character filter dropdown
    local charDropdown = CreateFrame("Frame", nil, filterRow, "UIDropDownMenuTemplate")
    charDropdown:SetPoint("LEFT", dateDropdown, "RIGHT", -24, 0)
    UIDropDownMenu_SetWidth(charDropdown, 100)
    content.charDropdown = charDropdown

    local function CharDropdown_Init()
        -- All characters option
        local allInfo = UIDropDownMenu_CreateInfo()
        allInfo.text = "All Characters"
        allInfo.value = 1
        allInfo.checked = (_ledgerFilters.charIndex == 1)
        allInfo.func = function(self)
            _ledgerFilters.charIndex = 1
            _paginationLimit = 10  -- Reset pagination on filter change
            if IM.db and IM.db.global and IM.db.global.dashboard then
                IM.db.global.dashboard.ledgerCharFilter = 1
            end
            UIDropDownMenu_SetText(charDropdown, "All Characters")
            Dashboard:RefreshLedger()
        end
        UIDropDownMenu_AddButton(allInfo)

        -- Individual characters
        local chars = {}
        if IM.modules.Ledger then
            chars = IM.modules.Ledger:GetCharactersFromTransactions()
        end
        for i, charKey in ipairs(chars) do
            local charName = charKey:match("^(.+)-") or charKey
            local info = UIDropDownMenu_CreateInfo()
            info.text = charName
            info.value = i + 1  -- +1 because index 1 is "All Characters"
            info.checked = (_ledgerFilters.charIndex == i + 1)
            info.func = function(self)
                _ledgerFilters.charIndex = self.value
                _ledgerFilters.charKey = charKey  -- Store actual key for filtering
                _paginationLimit = 10  -- Reset pagination on filter change
                if IM.db and IM.db.global and IM.db.global.dashboard then
                    IM.db.global.dashboard.ledgerCharFilter = self.value
                end
                UIDropDownMenu_SetText(charDropdown, charName)
                Dashboard:RefreshLedger()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(charDropdown, CharDropdown_Init)
    -- Set initial text
    local chars = IM.modules.Ledger and IM.modules.Ledger:GetCharactersFromTransactions() or {}
    if _ledgerFilters.charIndex == 1 or #chars == 0 then
        UIDropDownMenu_SetText(charDropdown, "All Characters")
    else
        local charKey = chars[_ledgerFilters.charIndex - 1]
        if charKey then
            UIDropDownMenu_SetText(charDropdown, charKey:match("^(.+)-") or charKey)
            _ledgerFilters.charKey = charKey
        else
            UIDropDownMenu_SetText(charDropdown, "All Characters")
            _ledgerFilters.charIndex = 1
        end
    end

    yOffset = yOffset - 34

    -- Summary box (now shows filtered results)
    local summaryBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    summaryBox:SetHeight(56)
    summaryBox:SetPoint("TOPLEFT", 0, yOffset)
    summaryBox:SetPoint("RIGHT", 0, 0)
    summaryBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    summaryBox:SetBackdropColor(0.12, 0.12, 0.12, 1)

    local summaryLabel = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryLabel:SetPoint("TOPLEFT", 10, -8)
    summaryLabel:SetText(UI:ColorText("FILTERED SUMMARY", "accent"))

    local incomeLabel = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    incomeLabel:SetPoint("TOPLEFT", 10, -24)
    incomeLabel:SetText("|cff4DCC4DIncome:|r")  -- UX Fix #7: Consistent color (#4DCC4D)

    local incomeValue = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    incomeValue:SetPoint("LEFT", incomeLabel, "RIGHT", 6, 0)
    content.incomeValue = incomeValue

    local expenseLabel = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expenseLabel:SetPoint("TOPLEFT", 140, -24)
    expenseLabel:SetText("|cffE64D4DExpenses:|r")  -- UX Fix #7: Consistent color (#E64D4D)

    local expenseValue = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expenseValue:SetPoint("LEFT", expenseLabel, "RIGHT", 6, 0)
    content.expenseValue = expenseValue

    local netLabel = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    netLabel:SetPoint("TOPLEFT", 10, -40)
    netLabel:SetText("Net:")

    local netValue = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    netValue:SetPoint("LEFT", netLabel, "RIGHT", 6, 0)
    content.netValue = netValue

    local countLabel = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("TOPRIGHT", -10, -40)
    countLabel:SetTextColor(unpack(UI.colors.textDim))
    content.countLabel = countLabel

    -- UX Fix #5: Pagination status indicator
    local paginationStatus = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    paginationStatus:SetPoint("TOPLEFT", 140, -40)
    paginationStatus:SetTextColor(unpack(UI.colors.textDim))
    content.paginationStatus = paginationStatus

    -- Info button with tooltip explaining "Other" category
    local infoBtn = CreateFrame("Button", nil, summaryBox)
    infoBtn:SetSize(14, 14)
    infoBtn:SetPoint("BOTTOMRIGHT", -6, 4)
    infoBtn.text = infoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoBtn.text:SetPoint("CENTER")
    infoBtn.text:SetText("|cff888888?|r")
    infoBtn:SetScript("OnEnter", function(self)
        self.text:SetText(UI:ColorText("?", "accent"))
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ledger Tracking Info", 1, 0.84, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffcc66ff'Other'|r transactions include:", 1, 1, 1)
        GameTooltip:AddLine("  - Crafting costs (profession materials)", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("  - Profession training fees", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("  - Great Vault fees", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("  - Garrison/Mission Table costs", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("  - Any other untracked gold change", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888These are gold changes not claimed by|r", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("|cff888888any specific tracking module.|r", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function(self)
        self.text:SetText("|cff888888?|r")
        GameTooltip:Hide()
    end)

    yOffset = yOffset - 61

    -- Transactions header
    local transHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    transHeader:SetPoint("TOPLEFT", 0, yOffset)
    transHeader:SetText("Transactions")
    transHeader:SetTextColor(unpack(UI.colors.textDim))

    yOffset = yOffset - 16

    -- Transactions scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, yOffset)
    scrollFrame:SetPoint("RIGHT", -24, 0)
    scrollFrame:SetPoint("BOTTOM", 0, 0)

    -- Style the scroll bar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
    end

    -- Scroll child (actual content container)
    local transList = CreateFrame("Frame", nil, scrollFrame)
    transList:SetWidth(380)  -- Fixed width for scroll child
    transList:SetHeight(1) -- Will be set dynamically
    scrollFrame:SetScrollChild(transList)

    -- Update width when scroll frame is shown
    scrollFrame:SetScript("OnShow", function(self)
        local w = self:GetWidth()
        if w and w > 0 then
            transList:SetWidth(w)
        end
    end)

    content.scrollFrame = scrollFrame
    content.transList = transList

    -- Create persistent "no data" message (hidden by default)
    local noDataMsg = transList:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noDataMsg:SetPoint("TOPLEFT", 8, 0)
    noDataMsg:SetText("|cff888888No transactions match the selected filters.|r")
    noDataMsg:Hide()
    content.noDataMsg = noDataMsg
end

-- Inventory search filter state
local _inventoryFilters = {
    search = "",
    charIndex = 1,  -- 1 = All Characters
    locationIndex = 1,  -- 1 = All Locations
}
local _inventoryPaginationLimit = 15
local _inventorySearchDebounce = nil

-- Create Inventory tab content
function Dashboard:CreateInventoryContent(frame)
    local content = CreateFrame("Frame", nil, frame.contentArea)
    content:SetAllPoints()
    content:Hide()
    frame.inventoryContent = content

    local yOffset = 0

    -- Info box (explains feature)
    local infoBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    infoBox:SetHeight(52)
    infoBox:SetPoint("TOPLEFT", 0, yOffset)
    infoBox:SetPoint("RIGHT", 0, 0)
    infoBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    infoBox:SetBackdropColor(0.12, 0.10, 0.05, 1)

    local infoTitle = infoBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoTitle:SetPoint("TOPLEFT", 10, -6)
    infoTitle:SetText(UI:ColorText("CROSS-CHARACTER INVENTORY SEARCH", "accent"))

    local infoText = infoBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", 10, -20)
    infoText:SetText("|cff888888Search items across all characters' bags, banks, and warband bank.|r")

    local loginHint = infoBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    loginHint:SetPoint("BOTTOMLEFT", 10, 6)
    loginHint:SetText("|cff666666Log into each character to scan their inventory.|r")

    yOffset = yOffset - 58

    -- Search row
    local searchRow = CreateFrame("Frame", nil, content, "BackdropTemplate")
    searchRow:SetHeight(28)
    searchRow:SetPoint("TOPLEFT", 0, yOffset)
    searchRow:SetPoint("RIGHT", 0, 0)
    searchRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    searchRow:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    local searchLabel = searchRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("LEFT", 8, 0)
    searchLabel:SetText("Search Items:")  -- UX Fix #8: Persistent label
    searchLabel:SetTextColor(unpack(UI.colors.accent))

    local searchInput = CreateFrame("EditBox", nil, searchRow, "BackdropTemplate")
    searchInput:SetSize(320, 20)
    searchInput:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    searchInput:SetFontObject("GameFontNormalSmall")
    searchInput:SetAutoFocus(false)
    searchInput:SetMaxLetters(50)
    searchInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    searchInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    searchInput:SetBackdropBorderColor(unpack(UI.colors.border))
    searchInput:SetTextInsets(6, 6, 0, 0)
    searchInput:SetTextColor(unpack(UI.colors.text))

    local searchPlaceholder = searchInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchPlaceholder:SetPoint("LEFT", 6, 0)
    searchPlaceholder:SetText("Search by item name...")
    searchPlaceholder:SetTextColor(0.4, 0.4, 0.4, 1)

    searchInput:SetScript("OnEditFocusGained", function(self)
        searchPlaceholder:Hide()
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
    end)
    searchInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchPlaceholder:Show() end
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)
    searchInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            local text = self:GetText()
            if text == "" then
                searchPlaceholder:Show()
            else
                searchPlaceholder:Hide()
            end
            -- Debounce search (Bug #12: Closure scoping fix)
            if _inventorySearchDebounce then
                _inventorySearchDebounce:Cancel()
            end
            local module = Dashboard
            _inventorySearchDebounce = C_Timer.NewTimer(0.3, function()
                _inventoryFilters.search = text
                _inventoryPaginationLimit = 15  -- Reset pagination on search
                module:RefreshInventory()
            end)
        end
    end)
    content.searchInput = searchInput

    yOffset = yOffset - 30

    -- Filter row (dropdowns)
    local filterRow = CreateFrame("Frame", nil, content, "BackdropTemplate")
    filterRow:SetHeight(32)
    filterRow:SetPoint("TOPLEFT", 0, yOffset)
    filterRow:SetPoint("RIGHT", 0, 0)
    filterRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    filterRow:SetBackdropColor(0.08, 0.08, 0.08, 0.8)

    -- Character filter dropdown
    local charLabel = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charLabel:SetPoint("LEFT", 8, 0)
    charLabel:SetText("Character:")
    charLabel:SetTextColor(unpack(UI.colors.textDim))

    local charDropdown = CreateFrame("Frame", nil, filterRow, "UIDropDownMenuTemplate")
    charDropdown:SetPoint("LEFT", charLabel, "RIGHT", -12, -2)
    UIDropDownMenu_SetWidth(charDropdown, 100)

    local function CharDropdown_Init()
        -- All characters option
        local allInfo = UIDropDownMenu_CreateInfo()
        allInfo.text = "All Characters"
        allInfo.value = 1
        allInfo.checked = (_inventoryFilters.charIndex == 1)
        allInfo.func = function(self)
            _inventoryFilters.charIndex = 1
            _inventoryFilters.charKey = nil
            _inventoryPaginationLimit = 15
            UIDropDownMenu_SetText(charDropdown, "All Characters")
            Dashboard:RefreshInventory()
        end
        UIDropDownMenu_AddButton(allInfo)

        -- Warband Bank option
        local warbandInfo = UIDropDownMenu_CreateInfo()
        warbandInfo.text = "Warband Bank"
        warbandInfo.value = 2
        warbandInfo.checked = (_inventoryFilters.charIndex == 2)
        warbandInfo.func = function(self)
            _inventoryFilters.charIndex = 2
            _inventoryFilters.charKey = "warband"
            _inventoryPaginationLimit = 15
            UIDropDownMenu_SetText(charDropdown, "Warband Bank")
            Dashboard:RefreshInventory()
        end
        UIDropDownMenu_AddButton(warbandInfo)

        -- Individual characters
        local chars = {}
        if IM.modules.InventorySnapshot then
            chars = IM.modules.InventorySnapshot:GetCharactersWithSnapshots()
        end
        for i, charInfo in ipairs(chars) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = charInfo.name
            info.value = i + 2  -- +2 because 1=All, 2=Warband
            info.checked = (_inventoryFilters.charIndex == i + 2)
            info.func = function(self)
                _inventoryFilters.charIndex = self.value
                _inventoryFilters.charKey = charInfo.key
                _inventoryPaginationLimit = 15
                UIDropDownMenu_SetText(charDropdown, charInfo.name)
                Dashboard:RefreshInventory()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(charDropdown, CharDropdown_Init)
    UIDropDownMenu_SetText(charDropdown, "All Characters")
    content.charDropdown = charDropdown

    -- Location filter dropdown
    local locationDropdown = CreateFrame("Frame", nil, filterRow, "UIDropDownMenuTemplate")
    locationDropdown:SetPoint("LEFT", charDropdown, "RIGHT", -24, 0)
    UIDropDownMenu_SetWidth(locationDropdown, 90)

    local locationOptions = {
        {label = "All Locations", value = nil},
        {label = "Bags", value = "bags"},
        {label = "Bank", value = "bank"},
        {label = "Reagent Bank", value = "reagentBank"},
        {label = "Warband Bank", value = "warbandBank"},
    }

    local function LocationDropdown_Init()
        for i, opt in ipairs(locationOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = i
            info.checked = (_inventoryFilters.locationIndex == i)
            info.func = function(self)
                _inventoryFilters.locationIndex = self.value
                _inventoryFilters.location = opt.value
                _inventoryPaginationLimit = 15
                UIDropDownMenu_SetText(locationDropdown, opt.label)
                Dashboard:RefreshInventory()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(locationDropdown, LocationDropdown_Init)
    UIDropDownMenu_SetText(locationDropdown, "All Locations")
    content.locationDropdown = locationDropdown

    yOffset = yOffset - 34

    -- Results header
    local resultsHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultsHeader:SetPoint("TOPLEFT", 0, yOffset)
    resultsHeader:SetText("Results")
    resultsHeader:SetTextColor(unpack(UI.colors.textDim))
    content.resultsHeader = resultsHeader

    local resultCount = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultCount:SetPoint("TOPRIGHT", 0, yOffset)
    resultCount:SetTextColor(unpack(UI.colors.textDim))
    content.resultCount = resultCount

    yOffset = yOffset - 16

    -- Results scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, yOffset)
    scrollFrame:SetPoint("RIGHT", -24, 0)
    scrollFrame:SetPoint("BOTTOM", 0, 0)

    -- Style the scroll bar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
    end

    -- Scroll child (actual content container)
    local resultsList = CreateFrame("Frame", nil, scrollFrame)
    resultsList:SetWidth(380)
    resultsList:SetHeight(1)
    scrollFrame:SetScrollChild(resultsList)

    scrollFrame:SetScript("OnShow", function(self)
        local w = self:GetWidth()
        if w and w > 0 then
            resultsList:SetWidth(w)
        end
    end)

    content.scrollFrame = scrollFrame
    content.resultsList = resultsList

    -- Create persistent "no data" message (hidden by default)
    local noDataMsg = resultsList:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noDataMsg:SetPoint("TOPLEFT", 8, 0)
    noDataMsg:SetText("|cff888888No items found. Try a different search.|r")
    noDataMsg:Hide()
    content.noDataMsg = noDataMsg
    -- Note: No scanPrompt needed - we always show either summary (when empty) or search results
end

-- Refresh Inventory content
function Dashboard:RefreshInventory()
    local content = _dashboard.inventoryContent
    if not content then return end

    -- Clear results list (frames only, not font strings)
    local resultsList = content.resultsList
    if resultsList then
        for _, child in pairs({resultsList:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
    end

    -- Hide the no data message initially
    if content.noDataMsg then content.noDataMsg:Hide() end

    -- Determine if we should show summary or browse mode
    local showSummary = (not _inventoryFilters.search or _inventoryFilters.search == "") and _inventoryFilters.charIndex == 1
    local browseCharacter = (not _inventoryFilters.search or _inventoryFilters.search == "") and _inventoryFilters.charIndex > 1

    -- If no search and no character filter, show inventory summary
    if showSummary then

        -- Build summary
        local summary = {}
        local totalItems = 0

        if IM.db and IM.db.global and IM.db.global.inventorySnapshots then
            for charKey, snapshot in pairs(IM.db.global.inventorySnapshots) do
                local count = (snapshot.bags and #snapshot.bags or 0) +
                              (snapshot.bank and #snapshot.bank or 0) +
                              (snapshot.reagentBank and #snapshot.reagentBank or 0)
                totalItems = totalItems + count

                local charName = charKey:match("^(.+)-") or charKey
                local charData = IM.db.global.characters and IM.db.global.characters[charKey]
                local charClass = charData and charData.class

                table.insert(summary, {
                    key = charKey,
                    name = charName,
                    class = charClass,
                    count = count,
                    timestamp = snapshot.timestamp or 0,
                })
            end
        end

        -- Add warband bank
        local warbandData = IM.db.global.warbandBankInventory
        if warbandData and warbandData.items then
            totalItems = totalItems + #warbandData.items
            table.insert(summary, {
                key = "warband",
                name = "Warband Bank",
                class = nil,
                count = #warbandData.items,
                timestamp = warbandData.timestamp or 0,
            })
        end

        -- Sort by item count descending
        table.sort(summary, function(a, b) return a.count > b.count end)

        content.resultCount:SetText("(" .. totalItems .. " total items)")

        -- Show summary rows
        local yOffset = 0
        local ROW_HEIGHT = 32
        local ROW_SPACING = 2

        -- Header row
        local headerRow = CreateFrame("Frame", nil, resultsList, "BackdropTemplate")
        headerRow:SetHeight(24)
        headerRow:SetPoint("TOPLEFT", 0, yOffset)
        headerRow:SetPoint("RIGHT", 0, 0)
        headerRow:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
        headerRow:SetBackdropColor(0.15, 0.12, 0.05, 1)

        local headerText = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("LEFT", 8, 0)
        headerText:SetText(UI:ColorText("INVENTORY SUMMARY", "accent") .. " |cff888888(Click character to browse)|r")

        yOffset = yOffset - 28

        for i, charInfo in ipairs(summary) do
            local classColor = CLASS_COLORS[charInfo.class] or {0.7, 0.7, 0.7}

            local row = CreateFrame("Button", nil, resultsList, "BackdropTemplate")
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", 0, yOffset)
            row:SetPoint("RIGHT", 0, 0)
            row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
            local bgAlpha = i % 2 == 0 and 0.5 or 0.2
            row:SetBackdropColor(0.12, 0.12, 0.12, bgAlpha)

            -- Make row clickable - sets character filter and shows their items
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.2, 0.18, 0.1, 0.8)
            end)
            row:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.12, 0.12, 0.12, bgAlpha)
            end)
            row:SetScript("OnClick", function()
                -- Set the character filter
                if charInfo.key == "warband" then
                    _inventoryFilters.charIndex = 2
                    _inventoryFilters.charKey = "warband"
                    UIDropDownMenu_SetText(content.charDropdown, "Warband Bank")
                else
                    -- Find the index for this character in the dropdown
                    local chars = IM.modules.InventorySnapshot and IM.modules.InventorySnapshot:GetCharactersWithSnapshots() or {}
                    for idx, char in ipairs(chars) do
                        if char.key == charInfo.key then
                            _inventoryFilters.charIndex = idx + 2  -- +2 because 1=All, 2=Warband
                            _inventoryFilters.charKey = charInfo.key
                            UIDropDownMenu_SetText(content.charDropdown, charInfo.name)
                            break
                        end
                    end
                end
                _inventoryPaginationLimit = 15
                Dashboard:RefreshInventory()
            end)

            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameLabel:SetPoint("LEFT", 8, 0)
            if charInfo.key == "warband" then
                nameLabel:SetText(UI:ColorText(charInfo.name, "accent"))
            else
                nameLabel:SetText(string.format("|cff%02x%02x%02x%s|r",
                    math.floor(classColor[1] * 255),
                    math.floor(classColor[2] * 255),
                    math.floor(classColor[3] * 255),
                    charInfo.name))
            end

            local countLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            countLabel:SetPoint("RIGHT", -30, 0)
            countLabel:SetText("|cffffd700" .. charInfo.count .. "|r items")

            -- Arrow indicator
            local arrow = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            arrow:SetPoint("RIGHT", -8, 0)
            arrow:SetText("|cff888888>|r")

            yOffset = yOffset - (ROW_HEIGHT + ROW_SPACING)
        end

        if #summary == 0 then
            local noData = resultsList:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noData:SetPoint("TOPLEFT", 8, yOffset)
            noData:SetText("|cff888888No inventory data yet. Login to characters to scan.|r")
            yOffset = yOffset - 20
        end

        resultsList:SetHeight(math.abs(yOffset) + 10)
        return
    end

    -- Build filters
    local filters = {
        search = _inventoryFilters.search,
        character = _inventoryFilters.charKey,
        location = _inventoryFilters.location,
    }

    -- Get search results
    local results = {}
    if IM.modules.InventorySnapshot then
        results = IM.modules.InventorySnapshot:SearchItems(filters)
    end

    -- Update result count
    content.resultCount:SetText("(" .. #results .. " items)")

    -- Add browse mode header if browsing a character (no search, specific character)
    local yOffset = 0
    if browseCharacter then
        local headerRow = CreateFrame("Button", nil, resultsList, "BackdropTemplate")
        headerRow:SetHeight(24)
        headerRow:SetPoint("TOPLEFT", 0, yOffset)
        headerRow:SetPoint("RIGHT", 0, 0)
        headerRow:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
        headerRow:SetBackdropColor(0.15, 0.12, 0.05, 1)

        -- Back button
        headerRow:EnableMouse(true)
        headerRow:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.16, 0.05, 1)
        end)
        headerRow:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.12, 0.05, 1)
        end)
        headerRow:SetScript("OnClick", function()
            -- Reset to summary view
            _inventoryFilters.charIndex = 1
            _inventoryFilters.charKey = nil
            UIDropDownMenu_SetText(content.charDropdown, "All Characters")
            Dashboard:RefreshInventory()
        end)

        local backArrow = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        backArrow:SetPoint("LEFT", 8, 0)
        backArrow:SetText("|cff888888<|r")

        -- Get character name for display
        local charDisplayName = "Character"
        if _inventoryFilters.charKey == "warband" then
            charDisplayName = "Warband Bank"
        elseif _inventoryFilters.charKey then
            charDisplayName = _inventoryFilters.charKey:match("^(.+)-") or _inventoryFilters.charKey
        end

        local headerText = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("LEFT", 20, 0)
        headerText:SetText(UI:ColorText("BROWSING: " .. charDisplayName, "accent") .. " |cff888888(Click to go back)|r")

        yOffset = yOffset - 28
    end

    -- Show no results message
    if #results == 0 then
        if content.noDataMsg then
            content.noDataMsg:ClearAllPoints()
            content.noDataMsg:SetPoint("TOPLEFT", 8, yOffset - 8)
            content.noDataMsg:Show()
        end
        resultsList:SetHeight(math.abs(yOffset) + 30)
        return
    end

    if content.noDataMsg then content.noDataMsg:Hide() end

    -- Display results (with pagination)
    local ROW_HEIGHT = 48
    local ROW_SPACING = 2
    local maxResults = math.min(_inventoryPaginationLimit, #results)

    for i = 1, maxResults do
        local result = results[i]
        local classColor = CLASS_COLORS[result.charClass] or {0.7, 0.7, 0.7}

        local row = CreateFrame("Frame", nil, resultsList, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, yOffset)
        row:SetPoint("RIGHT", 0, 0)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.12, 0.12, 0.12, 1)
        row:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        -- Item icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("TOPLEFT", 8, -6)
        local iconTexture = C_Item.GetItemIconByID(result.itemID)
        if iconTexture then
            icon:SetTexture(iconTexture)
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Line 1: Item link + quantity
        local itemLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemLabel:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, 0)
        itemLabel:SetPoint("RIGHT", -10, 0)
        itemLabel:SetJustifyH("LEFT")
        local itemText = result.itemLink or ("[Item #" .. result.itemID .. "]")
        if result.quantity > 1 then
            itemText = itemText .. " |cffffffffx" .. result.quantity .. "|r"
        end
        itemLabel:SetText(itemText)

        -- Line 2: Character - Location
        local locationLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        locationLabel:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 0)
        locationLabel:SetTextColor(unpack(UI.colors.textDim))

        local charText
        if result.charKey == "Warband Bank" then
            charText = UI:ColorText("Warband Bank", "accent")
        else
            charText = string.format("|cff%02x%02x%02x%s|r",
                math.floor(classColor[1] * 255),
                math.floor(classColor[2] * 255),
                math.floor(classColor[3] * 255),
                result.charName)
        end
        locationLabel:SetText(charText .. " - " .. result.locationLabel)

        yOffset = yOffset - (ROW_HEIGHT + ROW_SPACING)
    end

    -- Show More button if there are more results (UX Fix #6: More prominent styling)
    if #results > _inventoryPaginationLimit then
        local showMoreBtn = CreateFrame("Button", nil, resultsList, "BackdropTemplate")
        showMoreBtn:SetHeight(28)
        showMoreBtn:SetPoint("TOPLEFT", 0, yOffset - 4)
        showMoreBtn:SetPoint("RIGHT", 0, 0)
        showMoreBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        showMoreBtn:SetBackdropColor(0.2, 0.17, 0.08, 1)
        showMoreBtn:SetBackdropBorderColor(unpack(UI.colors.accent))

        local showMoreText = showMoreBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        showMoreText:SetPoint("CENTER")
        showMoreText:SetText(UI:ColorText("Show More Items", "accent") .. " |cff888888(" .. (#results - _inventoryPaginationLimit) .. " remaining)|r")

        local module = Dashboard
        showMoreBtn:SetScript("OnClick", function()
            _inventoryPaginationLimit = _inventoryPaginationLimit + 15
            module:RefreshInventory()
        end)
        showMoreBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.22, 0.10, 1)
            showMoreText:SetText(UI:ColorText("► Show More Items", "accent") .. " |cffaaaaaa(" .. (#results - _inventoryPaginationLimit) .. " remaining)|r")
        end)
        showMoreBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.2, 0.17, 0.08, 1)
            showMoreText:SetText(UI:ColorText("Show More Items", "accent") .. " |cff888888(" .. (#results - _inventoryPaginationLimit) .. " remaining)|r")
        end)

        yOffset = yOffset - 32
    end

    -- Set scroll child height
    local totalHeight = math.abs(yOffset) + 10
    resultsList:SetHeight(totalHeight)

    -- Update resultsList width
    if content.scrollFrame then
        local scrollWidth = content.scrollFrame:GetWidth()
        if scrollWidth and scrollWidth > 0 then
            resultsList:SetWidth(scrollWidth)
        end
    end
end

-- Refresh content based on active tab
function Dashboard:RefreshContent()
    if not _dashboard then return end

    if _activeTab == "networth" then
        self:RefreshNetWorth()
    elseif _activeTab == "ledger" then
        self:RefreshLedger()
    elseif _activeTab == "inventory" then
        self:RefreshInventory()
    end
end

-- Refresh Net Worth content
function Dashboard:RefreshNetWorth()
    local content = _dashboard.networthContent
    if not content then return end

    -- Get breakdown data
    local breakdown = nil
    if IM.modules.NetWorth then
        breakdown = IM.modules.NetWorth:GetAccountBreakdown()
    else
        breakdown = {
            total = { gold = 0, inventory = 0, netWorth = 0 },
            warbandBank = { gold = 0 },
            characters = {},
        }
    end

    -- Calculate liquid gold (character gold + warband bank)
    local liquidGold = breakdown.total.gold + breakdown.warbandBank.gold

    -- Update running total breakdown
    content.charGoldValue:SetText(IM:FormatMoney(breakdown.total.gold))
    content.warbandValue:SetText("+ " .. IM:FormatMoney(breakdown.warbandBank.gold))
    content.liquidValue:SetText(IM:FormatMoney(liquidGold))
    content.invValue:SetText("+ " .. IM:FormatMoney(breakdown.total.inventory))
    content.totalValue:SetText(IM:FormatMoney(breakdown.total.netWorth))

    -- Update character count
    if content.charCount then
        content.charCount:SetText("(" .. #breakdown.characters .. " total)")
    end

    -- Clear and rebuild character list
    local charList = content.charList
    for _, child in pairs({charList:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    -- Show ALL characters with gold/inventory breakdown
    local yOffset = 0
    local ROW_HEIGHT = 40 -- Taller rows for two-line display
    local ROW_SPACING = 2

    for i, charInfo in ipairs(breakdown.characters) do
        local classColor = CLASS_COLORS[charInfo.class] or {1, 1, 1}

        local row = CreateFrame("Frame", nil, charList, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, yOffset)
        row:SetPoint("RIGHT", 0, 0)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.12, 0.12, 0.12, 1)
        row:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        -- Top line: Name (level) ... Total
        local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLabel:SetPoint("TOPLEFT", 10, -6)
        local displayName = charInfo.name
        if charInfo.level then
            displayName = displayName .. " |cff888888(" .. charInfo.level .. ")|r"
        end
        nameLabel:SetText(displayName)
        nameLabel:SetTextColor(classColor[1], classColor[2], classColor[3], 1)

        local totalLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        totalLabel:SetPoint("TOPRIGHT", -10, -6)
        totalLabel:SetText(IM:FormatMoney(charInfo.netWorth))
        totalLabel:SetTextColor(1, 0.84, 0, 1)

        -- Bottom line: Gold: X | Inventory: X
        local detailLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        detailLabel:SetPoint("BOTTOMLEFT", 10, 6)
        detailLabel:SetTextColor(unpack(UI.colors.textDim))

        local goldText = "|cffffd700" .. IM:FormatMoney(charInfo.gold) .. "|r"
        local invText = "|cff888888" .. IM:FormatMoney(charInfo.inventory) .. "|r"
        detailLabel:SetText("Gold: " .. goldText .. "  |  Inv: " .. invText)

        yOffset = yOffset - (ROW_HEIGHT + ROW_SPACING)
    end

    if #breakdown.characters == 0 then
        local noData = charList:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noData:SetPoint("TOPLEFT", 10, 0)
        noData:SetText("|cff888888No character data yet.|r")
        yOffset = -20
    end

    -- Set scroll child height for proper scrolling
    local totalHeight = math.abs(yOffset) + 10
    charList:SetHeight(totalHeight)

    -- Update charList width to match scroll frame
    if content.scrollFrame then
        local scrollWidth = content.scrollFrame:GetWidth()
        if scrollWidth and scrollWidth > 0 then
            charList:SetWidth(scrollWidth)
        end
    end
end

-- Refresh Ledger content
function Dashboard:RefreshLedger()
    local content = _dashboard.ledgerContent
    if not content then return end

    -- Build filter object from current selections
    local filters = {}

    -- Apply type filter
    if IM.modules.Ledger and _ledgerFilters.typeIndex > 1 then
        local typePresets = IM.modules.Ledger:GetTypePresets()
        local preset = typePresets[_ledgerFilters.typeIndex]
        if preset and preset.types then
            filters.types = preset.types
        end
    end

    -- Apply date filter
    if IM.modules.Ledger then
        local datePresets = IM.modules.Ledger:GetDatePresets()
        local preset = datePresets[_ledgerFilters.dateIndex]
        if preset and preset.minDate then
            filters.minDate = preset.minDate
        end
    end

    -- Apply character filter
    if _ledgerFilters.charIndex > 1 and _ledgerFilters.charKey then
        filters.char = _ledgerFilters.charKey
    end

    -- Apply search filter
    if _ledgerFilters.search and _ledgerFilters.search ~= "" then
        filters.search = _ledgerFilters.search:lower()
    end

    -- Get filtered stats and entries
    local stats = { totalIncome = 0, totalExpense = 0, netGold = 0, totalEntries = 0 }
    local entries = {}

    if IM.modules.Ledger then
        stats = IM:GetLedgerStats(filters)
        entries = IM.modules.Ledger:GetFormattedEntries(filters)
    end

    -- Apply search filter to entries (client-side text filtering)
    -- Searches: item name, character name, source, type (LOOT, MAIL, REPAIRS, etc.)
    if filters.search then
        local filteredEntries = {}
        local searchText = filters.search
        for _, entry in ipairs(entries) do
            -- Build search string from all relevant fields
            local matchParts = {
                entry.itemName or "",
                entry.source or "",
                entry.charName or "",
                entry.typeLabel or "",  -- LOOT, MAIL, REPAIRS, VENDOR, etc.
                entry.itemLink and entry.itemLink:match("%[(.-)%]") or "",  -- Extract item name from link
            }
            local matchText = table.concat(matchParts, " "):lower()
            if matchText:find(searchText, 1, true) then
                table.insert(filteredEntries, entry)
            end
        end
        entries = filteredEntries
    end

    -- Update summary
    content.incomeValue:SetText(IM:FormatMoney(stats.totalIncome))
    content.expenseValue:SetText(IM:FormatMoney(stats.totalExpense))

    -- UX Fix #7: Use consistent colors
    local netColor = stats.netGold >= 0 and "|cff4DCC4D+" or "|cffE64D4D-"
    content.netValue:SetText(netColor .. IM:FormatMoney(math.abs(stats.netGold)) .. "|r")

    if content.countLabel then
        content.countLabel:SetText(#entries .. " transactions")
    end

    -- UX Fix #5: Update pagination status indicator
    if content.paginationStatus then
        if #entries > 0 then
            local showing = math.min(_paginationLimit, #entries)
            content.paginationStatus:SetText("Showing " .. showing .. " of " .. #entries)
        else
            content.paginationStatus:SetText("")
        end
    end

    -- Clear and rebuild transactions list (Performance Fix #4: Use frame pooling)
    local transList = content.transList
    ReleaseAllFrames("ledger")

    -- Show entries up to pagination limit
    local yOffset = 0
    local maxEntries = math.min(_paginationLimit, #entries)

    for i = 1, maxEntries do
        local entry = entries[i]

        -- Performance Fix #4: Get pooled frame instead of creating new
        local row = GetPooledFrame("ledger", transList, "BackdropTemplate")
        row:SetHeight(32)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, yOffset)
        row:SetPoint("RIGHT", 0, 0)
        row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
        row:SetBackdropColor(0.12, 0.12, 0.12, i % 2 == 0 and 0.5 or 0.2)

        -- Create or reuse FontStrings
        if not row.topLine then
            row.topLine = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.topLine:SetPoint("TOPLEFT", 8, -3)
        end
        if not row.timeLabel then
            row.timeLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.timeLabel:SetPoint("TOPRIGHT", -8, -3)
        end
        if not row.nameLabel then
            row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameLabel:SetPoint("BOTTOMLEFT", 8, 4)
            row.nameLabel:SetPoint("RIGHT", row, "CENTER", 40, 0)
            row.nameLabel:SetJustifyH("LEFT")
        end
        if not row.valueLabel then
            row.valueLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.valueLabel:SetPoint("BOTTOMRIGHT", -8, 4)
        end

        -- Update content
        local charName = entry.charName or (entry.charKey and entry.charKey:match("^(.+)-") or nil)
        local charDisplay = ""
        if charName then
            local classColor = CLASS_COLORS[entry.charClass] or {0.7, 0.7, 0.7}
            charDisplay = string.format("|cff%02x%02x%02x[%s]|r ",
                math.floor(classColor[1] * 255),
                math.floor(classColor[2] * 255),
                math.floor(classColor[3] * 255),
                charName)
        end

        row.topLine:Show()
        row.topLine:SetText(charDisplay .. (entry.typeColor or "") .. (entry.typeLabel or "Unknown") .. "|r")

        row.timeLabel:Show()
        row.timeLabel:SetText(entry.timestampFormatted or "")
        row.timeLabel:SetTextColor(unpack(UI.colors.textDim))

        local displayText = ""
        if entry.itemLink then
            displayText = entry.itemLink
            if entry.quantity and entry.quantity > 1 then
                displayText = displayText .. " x" .. entry.quantity
            end
        elseif entry.source then
            displayText = entry.source
        else
            displayText = entry.typeLabel or ""
        end
        row.nameLabel:Show()
        row.nameLabel:SetText(displayText)

        row.valueLabel:Show()
        if entry.valueFormatted and entry.valueFormatted ~= "" then
            -- UX Fix #7: Use consistent colors
            local prefix = entry.isExpense and "|cffE64D4D-" or "|cff4DCC4D+"
            row.valueLabel:SetText(prefix .. entry.valueFormatted .. "|r")
        else
            row.valueLabel:SetText("")
        end

        yOffset = yOffset - 34
    end

    -- Show "no results" or "Show More" button
    if #entries == 0 then
        -- Show the persistent no-data message
        if content.noDataMsg then
            content.noDataMsg:Show()
        end
        yOffset = yOffset - 20
    elseif #entries > _paginationLimit then
        -- Hide the no-data message when we have entries
        if content.noDataMsg then
            content.noDataMsg:Hide()
        end
        -- Show More button (UX Fix #6: More prominent styling)
        local showMoreBtn = CreateFrame("Button", nil, transList, "BackdropTemplate")
        showMoreBtn:SetHeight(28)
        showMoreBtn:SetPoint("TOPLEFT", 0, yOffset - 4)
        showMoreBtn:SetPoint("RIGHT", 0, 0)
        showMoreBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        showMoreBtn:SetBackdropColor(0.2, 0.17, 0.08, 1)
        showMoreBtn:SetBackdropBorderColor(unpack(UI.colors.accent))

        local showMoreText = showMoreBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        showMoreText:SetPoint("CENTER")
        showMoreText:SetText(UI:ColorText("Show More Transactions", "accent") .. " |cff888888(" .. (#entries - _paginationLimit) .. " remaining)|r")

        local module = Dashboard
        showMoreBtn:SetScript("OnClick", function()
            _paginationLimit = _paginationLimit + 10
            module:RefreshLedger()
        end)
        showMoreBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.22, 0.10, 1)
            showMoreText:SetText(UI:ColorText("► Show More Transactions", "accent") .. " |cffaaaaaa(" .. (#entries - _paginationLimit) .. " remaining)|r")
        end)
        showMoreBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.2, 0.17, 0.08, 1)
            showMoreText:SetText(UI:ColorText("Show More Transactions", "accent") .. " |cff888888(" .. (#entries - _paginationLimit) .. " remaining)|r")
        end)
        yOffset = yOffset - 32
    else
        -- Hide the no-data message when we have entries (within pagination limit)
        if content.noDataMsg then
            content.noDataMsg:Hide()
        end
    end

    -- Set scroll child height for proper scrolling
    local totalHeight = math.abs(yOffset) + 10
    transList:SetHeight(totalHeight)

    -- Update transList width to match scroll frame
    if content.scrollFrame then
        local scrollWidth = content.scrollFrame:GetWidth()
        if scrollWidth and scrollWidth > 0 then
            transList:SetWidth(scrollWidth)
        end
    end
end

-- Reset pagination when filters change
function Dashboard:ResetPagination()
    _paginationLimit = 10
end

-- Show the dashboard
function Dashboard:Show()
    local frame = self:Create()

    -- Check if Settings is open and offset position to avoid overlap
    local configFrame = UI:GetConfigFrame()
    if configFrame and configFrame:IsShown() then
        -- Position to the right of settings
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", configFrame, "TOPRIGHT", 20, 0)
    else
        -- Default center position (only set if not already positioned by user drag)
        if not frame._userPositioned then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER")
        end
    end

    self:RefreshContent()
    frame:Show()

    -- Update scroll widths after layout completes
    C_Timer.After(0.1, function()
        if frame and frame:IsShown() then
            -- Trigger OnSizeChanged to update scroll widths
            local w, h = frame:GetSize()
            frame:SetSize(w, h)
        end
    end)
end

-- Hide the dashboard
function Dashboard:Hide()
    if _dashboard then
        _dashboard:Hide()
    end

    -- Bug #12: Cancel all active timers to prevent callbacks after close
    if _searchDebounceTimer then
        _searchDebounceTimer:Cancel()
        _searchDebounceTimer = nil
    end
    if _inventorySearchDebounce then
        _inventorySearchDebounce:Cancel()
        _inventorySearchDebounce = nil
    end
    if _onSizeChangedTimer then
        _onSizeChangedTimer:Cancel()
        _onSizeChangedTimer = nil
    end
end

-- Toggle the dashboard
function Dashboard:Toggle()
    if _dashboard and _dashboard:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Check if dashboard is shown
function Dashboard:IsShown()
    return _dashboard and _dashboard:IsShown()
end
