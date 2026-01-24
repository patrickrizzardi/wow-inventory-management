--[[
    InventoryManager - UI/Core.lua
    Base frame templates and dark theme utilities
]]

local addonName, IM = ...

local UI = {}
IM.UI = UI

-- Theme colors (dark theme with cheddar/golden accents)
UI.colors = {
    -- Base colors (dark theme)
    background = { 0.08, 0.08, 0.08, 0.95 },
    backgroundLight = { 0.12, 0.12, 0.12, 0.95 },
    backgroundDark = { 0.05, 0.05, 0.05, 0.95 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderLight = { 0.5, 0.5, 0.5, 1 },
    borderDark = { 0.2, 0.2, 0.2, 1 },
    text = { 1, 1, 1, 1 },
    textDim = { 0.7, 0.7, 0.7, 1 },
    textDisabled = { 0.4, 0.4, 0.4, 1 },

    -- Refined gold palette (darker, less saturated to match emblem)
    accent = { 0.85, 0.60, 0.10, 1 },       -- #D9991A darker gold
    accentHover = { 0.95, 0.70, 0.15, 1 },  -- slightly brighter on hover
    accentBright = { 1.0, 0.75, 0.20, 1 },  -- for emphasis only
    accentDim = { 0.6, 0.45, 0.10, 1 },     -- muted for backgrounds
    accentMuted = { 0.35, 0.28, 0.10, 1 },  -- very subtle for selected tabs

    -- Semantic colors
    success = { 0.3, 0.75, 0.3, 1 },        -- green for positive
    warning = { 0.85, 0.60, 0.10, 1 },      -- match accent
    error = { 0.85, 0.30, 0.30, 1 },        -- red for errors

    -- UI element colors (neutral, no brown tint)
    headerBar = { 0.12, 0.12, 0.12, 1 },        -- neutral dark gray
    headerBarHover = { 0.16, 0.15, 0.12, 1 },   -- subtle warm tint on hover
    rowAlt = { 0.10, 0.10, 0.10, 0.5 },         -- alternating row background
    rowHover = { 0.18, 0.16, 0.10, 0.8 },       -- warm hover for rows
    tabSelected = { 0.25, 0.22, 0.12, 1 },      -- selected tab background
    tabSelectedText = { 1.0, 0.85, 0.40, 1 },   -- selected tab text (light gold)
}

-- Hex color codes for inline WoW text formatting
UI.hexColors = {
    accent = "d9991a",        -- darker gold (matches UI.colors.accent)
    accentBright = "f2b833",  -- slightly brighter gold
    success = "4dcc4d",       -- green
    error = "d94d4d",         -- red
    warning = "d9991a",       -- match accent
    info = "88ccff",          -- light blue for informational
    dim = "888888",           -- gray for muted text
}

-- Layout constants for consistent spacing
UI.layout = {
    -- Padding/spacing
    padding = 8,              -- standard padding around elements
    paddingSmall = 4,         -- tight spacing
    paddingLarge = 12,        -- generous spacing
    cardSpacing = 10,         -- space between cards
    elementSpacing = 6,       -- space between elements in a card
    
    -- Row heights
    rowHeight = 28,           -- standard row/header height
    rowHeightSmall = 24,      -- compact rows (headers, list items)
    rowHeightLarge = 32,      -- taller rows (with more content)
    rowHeightTiny = 20,       -- minimal rows (dropdown items)
    
    -- Component heights
    titleBarHeight = 24,      -- window title bar
    bottomBarHeight = 30,     -- window bottom bar
    buttonHeight = 26,        -- standard button
    buttonHeightSmall = 22,   -- compact button
    tabHeight = 28,           -- tab button height
    inputHeight = 24,         -- text input height
    checkboxHeight = 24,      -- checkbox container height
    dropdownMenuItemHeight = 20, -- dropdown menu item
    
    -- Icon sizes
    iconSize = 20,            -- standard icon size
    iconSizeSmall = 16,       -- small icons
    iconSizeLarge = 24,       -- large icons
    iconSizeXLarge = 32,      -- extra large icons
    
    -- Widths
    scrollbarWidth = 16,      -- scrollbar width for calculations
    inputWidth = 150,         -- default input width
    inputWidthSmall = 80,     -- narrow input
    inputWidthLarge = 200,    -- wide input
    buttonWidth = 80,         -- default button width
    buttonWidthSmall = 60,    -- narrow button
    buttonWidthLarge = 120,   -- wide button
    
    -- Borders
    borderSize = 1,           -- standard border thickness
    borderSizeThick = 2,      -- emphasized border
    
    -- List/container initial heights (dynamically updated)
    listInitialHeight = 10,   -- initial height before content loads
    
    -- Divider
    dividerHeight = 1,        -- horizontal divider
}

-- Helper to generate WoW color strings
function UI:ColorText(text, colorName)
    local hex = self.hexColors[colorName] or self.hexColors.dim
    return "|cff" .. hex .. text .. "|r"
end

-- Font sizes
UI.fontSizes = {
    small = 10,
    normal = 12,
    large = 14,
    header = 16,
    title = 18,
}

-- Create a dark-themed panel frame
function UI:CreatePanel(name, parent, width, height)
    local frame = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    frame:SetSize(width or 400, height or 500)

    -- Dark background with thin border
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    frame:SetBackdropColor(unpack(self.colors.background))
    frame:SetBackdropBorderColor(unpack(self.colors.border))

    -- Make it movable
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Close on Escape, but propagate all other keys (so movement works)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return frame
end

-- Create a header/title bar for a panel
function UI:CreateHeader(parent, title)
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetHeight(self.layout.rowHeight)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    header:SetBackdropColor(unpack(self.colors.headerBar))
    header:SetBackdropBorderColor(unpack(self.colors.border))

    -- Title text (uses accent color)
    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.title:SetPoint("LEFT", self.layout.padding, 0)
    header.title:SetText(title or "InventoryManager")
    header.title:SetTextColor(unpack(self.colors.accent))

    -- Close button (red X style)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(self.layout.iconSize - 2, self.layout.iconSize - 2)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -self.layout.paddingSmall, 0)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeBtn.text:SetPoint("CENTER")
    closeBtn.text:SetText("|cffff6666X|r")
    closeBtn:SetScript("OnClick", function()
        parent:Hide()
    end)
    closeBtn:SetScript("OnEnter", function(self)
        self.text:SetText("|cffff0000X|r")
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self.text:SetText("|cffff6666X|r")
    end)
    header.closeButton = closeBtn

    return header
end

-- Create a button with dark theme
function UI:CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or self.layout.buttonWidth, height or self.layout.buttonHeightSmall)

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 1)
    button:SetBackdropBorderColor(unpack(self.colors.border))

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("CENTER")
    button.text:SetText(text or "")
    button.text:SetTextColor(unpack(self.colors.text))

    -- Hover effects
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.25, 1)
        self:SetBackdropBorderColor(unpack(UI.colors.borderLight))
    end)

    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 1)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    -- Click effect
    button:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 1)
    end)

    button:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.25, 1)
    end)

    return button
end

-- Create a checkbox with dark theme
function UI:CreateCheckbox(parent, text, default)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, self.layout.checkboxHeight)

    local checkboxSize = self.layout.iconSize - 2  -- 18
    local checkmarkSize = checkboxSize - 4  -- 14
    
    local checkbox = CreateFrame("CheckButton", nil, container, "BackdropTemplate")
    checkbox:SetSize(checkboxSize, checkboxSize)
    checkbox:SetPoint("LEFT", 0, 3)  -- Offset to center in container and prevent clipping

    checkbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    checkbox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    checkbox:SetBackdropBorderColor(unpack(self.colors.border))

    -- Checkmark
    checkbox.check = checkbox:CreateTexture(nil, "OVERLAY")
    checkbox.check:SetSize(checkmarkSize, checkmarkSize)
    checkbox.check:SetPoint("CENTER")
    checkbox.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkbox.check:Hide()

    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            self.check:Show()
        else
            self.check:Hide()
        end
        if self.OnValueChanged then
            self:OnValueChanged(self:GetChecked())
        end
    end)

    -- Helper to set checked state AND update visual (use this instead of :SetChecked for programmatic changes)
    function checkbox:SetCheckedState(checked)
        self:SetChecked(checked)
        if checked then
            self.check:Show()
        else
            self.check:Hide()
        end
    end

    -- Label
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
    container.label:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    container.label:SetJustifyH("LEFT")
    container.label:SetText(text or "")
    container.label:SetTextColor(unpack(self.colors.text))

    -- Set default value
    if default then
        checkbox:SetChecked(true)
        checkbox.check:Show()
    end

    container.checkbox = checkbox
    return container
end

-- Create a slider with dark theme
function UI:CreateSlider(parent, text, min, max, step, default)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(340, 50)  -- Container size set by parent layout

    -- Label (on its own line)
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.label:SetPoint("TOPLEFT", 0, 0)
    container.label:SetText(text or "")
    container.label:SetTextColor(unpack(self.colors.text))
    container.label:SetJustifyH("LEFT")

    -- Slider
    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetHeight(12)
    slider:SetPoint("TOPLEFT", 0, -self.layout.iconSize)
    slider:SetPoint("RIGHT", -60, 0)  -- Leave room for value display
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    slider:SetBackdropColor(0.1, 0.1, 0.1, 1)
    slider:SetBackdropBorderColor(unpack(self.colors.border))

    -- Thumb
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(10, self.layout.iconSize - 2)
    thumb:SetVertexColor(unpack(self.colors.accent))

    -- Value display (next to slider)
    container.value = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.value:SetPoint("LEFT", slider, "RIGHT", self.layout.padding, 0)
    container.value:SetTextColor(unpack(self.colors.accent))
    container.value:SetWidth(50)

    slider:SetScript("OnValueChanged", function(self, value)
        -- Show decimals if step is less than 1, otherwise integers
        local displayVal
        if step and step < 1 then
            displayVal = string.format("%.1f", value)
        else
            displayVal = tostring(math.floor(value))
        end
        container.value:SetText(displayVal)
        if container.OnValueChanged then
            container:OnValueChanged(value)
        end
    end)

    slider:SetValue(default or min or 0)

    container.slider = slider
    return container
end

-- Create a simple number editbox input
function UI:CreateNumberInput(parent, text, default, minVal, maxVal)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(340, 45)  -- Container size set by parent layout

    -- Label
    if text then
        container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        container.label:SetPoint("TOPLEFT", 0, 0)
        container.label:SetText(text)
        container.label:SetTextColor(unpack(self.colors.text))
    end

    -- Editbox
    local editbox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editbox:SetSize(self.layout.inputWidthSmall, self.layout.buttonHeightSmall)
    editbox:SetPoint("TOPLEFT", 0, text and -self.layout.iconSizeSmall or 0)
    editbox:SetFontObject("GameFontNormalSmall")
    editbox:SetAutoFocus(false)
    editbox:SetNumeric(true)
    editbox:SetMaxLetters(6)

    editbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    editbox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    editbox:SetBackdropBorderColor(unpack(self.colors.border))
    editbox:SetTextInsets(self.layout.elementSpacing, self.layout.elementSpacing, 0, 0)
    editbox:SetTextColor(unpack(self.colors.text))

    editbox:SetText(tostring(default or 0))

    editbox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local val = tonumber(self:GetText()) or 0
        if minVal and val < minVal then val = minVal end
        if maxVal and val > maxVal then val = maxVal end
        self:SetText(tostring(val))
        if container.OnValueChanged then
            container:OnValueChanged(val)
        end
    end)

    editbox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Focus styling
    editbox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.accent))
        self:HighlightText()
    end)

    editbox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
        local val = tonumber(self:GetText()) or 0
        if minVal and val < minVal then val = minVal end
        if maxVal and val > maxVal then val = maxVal end
        self:SetText(tostring(val))
        if container.OnValueChanged then
            container:OnValueChanged(val)
        end
    end)

    container.editbox = editbox

    -- Helper to get value
    function container:GetValue()
        return tonumber(editbox:GetText()) or 0
    end

    -- Helper to set value
    function container:SetValue(val)
        editbox:SetText(tostring(val or 0))
    end

    return container
end

-- Create a currency input (gold/silver/copper fields)
function UI:CreateCurrencyInput(parent, text, defaultCopper)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(340, 45)  -- Container size set by parent layout

    -- Label
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.label:SetPoint("TOPLEFT", 0, 0)
    container.label:SetText(text or "")
    container.label:SetTextColor(unpack(self.colors.text))

    -- Convert default copper to g/s/c
    local copper = defaultCopper or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRemainder = copper % 100
    
    local inputHeight = self.layout.buttonHeightSmall
    local iconSize = self.layout.iconSizeSmall - 2  -- 14
    local smallInputWidth = 35
    local goldInputWidth = 50

    -- Gold editbox
    local goldBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    goldBox:SetSize(goldInputWidth, inputHeight)
    goldBox:SetPoint("TOPLEFT", 0, -self.layout.iconSizeSmall)
    goldBox:SetFontObject("GameFontNormalSmall")
    goldBox:SetAutoFocus(false)
    goldBox:SetNumeric(true)
    goldBox:SetMaxLetters(5)
    goldBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    goldBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    goldBox:SetBackdropBorderColor(unpack(self.colors.border))
    goldBox:SetTextInsets(self.layout.paddingSmall, self.layout.paddingSmall, 0, 0)
    goldBox:SetTextColor(1, 0.84, 0, 1) -- Gold color
    goldBox:SetText(tostring(gold))

    -- Gold icon
    local goldIcon = container:CreateTexture(nil, "OVERLAY")
    goldIcon:SetSize(iconSize, iconSize)
    goldIcon:SetPoint("LEFT", goldBox, "RIGHT", 2, 0)
    goldIcon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")

    -- Silver editbox
    local silverBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    silverBox:SetSize(smallInputWidth, inputHeight)
    silverBox:SetPoint("LEFT", goldIcon, "RIGHT", self.layout.elementSpacing, 0)
    silverBox:SetFontObject("GameFontNormalSmall")
    silverBox:SetAutoFocus(false)
    silverBox:SetNumeric(true)
    silverBox:SetMaxLetters(2)
    silverBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    silverBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    silverBox:SetBackdropBorderColor(unpack(self.colors.border))
    silverBox:SetTextInsets(self.layout.paddingSmall, self.layout.paddingSmall, 0, 0)
    silverBox:SetTextColor(0.75, 0.75, 0.75, 1) -- Silver color
    silverBox:SetText(tostring(silver))

    -- Silver icon
    local silverIcon = container:CreateTexture(nil, "OVERLAY")
    silverIcon:SetSize(iconSize, iconSize)
    silverIcon:SetPoint("LEFT", silverBox, "RIGHT", 2, 0)
    silverIcon:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")

    -- Copper editbox
    local copperBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    copperBox:SetSize(smallInputWidth, inputHeight)
    copperBox:SetPoint("LEFT", silverIcon, "RIGHT", self.layout.elementSpacing, 0)
    copperBox:SetFontObject("GameFontNormalSmall")
    copperBox:SetAutoFocus(false)
    copperBox:SetNumeric(true)
    copperBox:SetMaxLetters(2)
    copperBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    copperBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    copperBox:SetBackdropBorderColor(unpack(self.colors.border))
    copperBox:SetTextInsets(self.layout.paddingSmall, self.layout.paddingSmall, 0, 0)
    copperBox:SetTextColor(0.72, 0.45, 0.2, 1) -- Copper color
    copperBox:SetText(tostring(copperRemainder))

    -- Copper icon
    local copperIcon = container:CreateTexture(nil, "OVERLAY")
    copperIcon:SetSize(iconSize, iconSize)
    copperIcon:SetPoint("LEFT", copperBox, "RIGHT", 2, 0)
    copperIcon:SetTexture("Interface\\MoneyFrame\\UI-CopperIcon")

    -- Store references
    container.goldBox = goldBox
    container.silverBox = silverBox
    container.copperBox = copperBox

    -- Helper to get total copper value
    local function GetTotalCopper()
        local g = tonumber(goldBox:GetText()) or 0
        local s = tonumber(silverBox:GetText()) or 0
        local c = tonumber(copperBox:GetText()) or 0
        return (g * 10000) + (s * 100) + c
    end

    -- Helper to update and fire callback
    local function OnUpdate()
        if container.OnValueChanged then
            container:OnValueChanged(GetTotalCopper())
        end
    end

    -- Set up scripts for all editboxes
    for _, box in ipairs({goldBox, silverBox, copperBox}) do
        box:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            OnUpdate()
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(unpack(UI.colors.accent))
            self:HighlightText()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(unpack(UI.colors.border))
            OnUpdate()
        end)
    end

    -- Public methods
    function container:GetValue()
        return GetTotalCopper()
    end

    function container:SetValue(totalCopper)
        local g = math.floor(totalCopper / 10000)
        local s = math.floor((totalCopper % 10000) / 100)
        local c = totalCopper % 100
        goldBox:SetText(tostring(g))
        silverBox:SetText(tostring(s))
        copperBox:SetText(tostring(c))
    end

    return container
end

-- Create a dropdown with dark theme
function UI:CreateDropdown(parent, text, options, default)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(self.layout.inputWidthLarge, 40)  -- Container height set by parent layout

    -- Label
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.label:SetPoint("TOPLEFT", 0, 0)
    container.label:SetText(text or "")
    container.label:SetTextColor(unpack(self.colors.text))

    -- Dropdown button
    local dropdown = CreateFrame("Button", nil, container, "BackdropTemplate")
    dropdown:SetSize(self.layout.inputWidthLarge - self.layout.iconSize, self.layout.buttonHeightSmall)
    dropdown:SetPoint("TOPLEFT", 0, -self.layout.iconSizeSmall + 2)

    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    dropdown:SetBackdropColor(0.12, 0.12, 0.12, 1)
    dropdown:SetBackdropBorderColor(unpack(self.colors.border))

    dropdown.text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropdown.text:SetPoint("LEFT", self.layout.elementSpacing, 0)
    dropdown.text:SetTextColor(unpack(self.colors.text))

    dropdown.arrow = dropdown:CreateTexture(nil, "OVERLAY")
    dropdown.arrow:SetSize(12, 12)
    dropdown.arrow:SetPoint("RIGHT", -self.layout.paddingSmall, 0)
    dropdown.arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")

    dropdown.options = options or {}
    dropdown.selected = default or 1

    dropdown.text:SetText(dropdown.options[dropdown.selected] or "Select...")

    -- Dropdown menu (created on demand)
    dropdown:SetScript("OnClick", function(self)
        UI:ShowDropdownMenu(self, self.options, function(index, value)
            self.selected = index
            self.text:SetText(value)
            if container.OnValueChanged then
                container:OnValueChanged(index, value)
            end
        end)
    end)

    container.dropdown = dropdown
    return container
end

-- Show dropdown menu
function UI:ShowDropdownMenu(anchor, options, callback)
    -- Create or reuse menu frame
    if not UI.dropdownMenu then
        UI.dropdownMenu = CreateFrame("Frame", "InventoryManagerDropdownMenu", UIParent, "BackdropTemplate")
        UI.dropdownMenu:SetFrameStrata("TOOLTIP")
        UI.dropdownMenu:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = self.layout.borderSize,
        })
        UI.dropdownMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        UI.dropdownMenu:SetBackdropBorderColor(unpack(self.colors.border))

        UI.dropdownMenu.buttons = {}
    end

    local menu = UI.dropdownMenu

    -- Clear old buttons
    for _, button in ipairs(menu.buttons) do
        button:Hide()
    end

    -- Create buttons for options
    local itemHeight = self.layout.dropdownMenuItemHeight
    local yOffset = self.layout.paddingSmall
    for i, option in ipairs(options) do
        local button = menu.buttons[i]
        if not button then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(itemHeight)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("LEFT", self.layout.elementSpacing, 0)
            button.text:SetTextColor(unpack(self.colors.text))

            button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
            button.highlight:SetAllPoints()
            button.highlight:SetColorTexture(0.3, 0.3, 0.3, 0.5)

            menu.buttons[i] = button
        end

        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -yOffset)
        button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -yOffset)
        button.text:SetText(option)
        button:SetScript("OnClick", function()
            callback(i, option)
            menu:Hide()
        end)
        button:Show()

        yOffset = yOffset + itemHeight
    end

    menu:SetSize(anchor:GetWidth(), yOffset + self.layout.paddingSmall)
    menu:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    menu:Show()

    -- Hide on click elsewhere
    menu:SetScript("OnUpdate", function(self)
        if not MouseIsOver(self) and not MouseIsOver(anchor) then
            if IsMouseButtonDown("LeftButton") then
                self:Hide()
            end
        end
    end)
end

-- Create a scroll frame with dark theme (custom implementation)
-- If width/height are nil and fill is true, uses anchors to fill parent
function UI:CreateScrollFrame(parent, width, height, fill)
    local w = width or 380
    local h = height or 400

    -- Container frame
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if fill then
        -- Fill mode: use anchors instead of fixed size
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
        container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)
    else
        container:SetSize(w, h)
    end
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    container:SetBackdropColor(0.05, 0.05, 0.05, 0.3)
    container:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    -- The actual scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -18, 4)

    -- Content frame that gets scrolled
    local content = CreateFrame("Frame", nil, scrollFrame)
    if fill then
        -- Dynamic width based on container
        content:SetWidth(container:GetWidth() - 22)
    else
        content:SetWidth(w - 22)
    end
    content:SetHeight(1) -- Will be set dynamically
    scrollFrame:SetScrollChild(content)

    -- Update content width when container resizes (for fill mode)
    if fill then
        container:SetScript("OnSizeChanged", function(self, newWidth, newHeight)
            content:SetWidth(newWidth - 22)
            -- Update scrollbar range
            local scrollHeight = content:GetHeight() - scrollFrame:GetHeight()
            if scrollHeight > 0 then
                container.scrollBar:SetMinMaxValues(0, scrollHeight)
                container.scrollBar:Show()
            else
                container.scrollBar:SetMinMaxValues(0, 0)
                container.scrollBar:SetValue(0)
                container.scrollBar:Hide()
            end
        end)
    end

    -- Scrollbar dimensions
    local scrollbarWidth = 10
    local scrollbarMargin = 2
    local scrollbarPadding = self.layout.paddingSmall
    local scrollStep = self.layout.rowHeightLarge + self.layout.padding  -- ~40

    -- Scrollbar track
    local scrollBarTrack = container:CreateTexture(nil, "BACKGROUND")
    scrollBarTrack:SetPoint("TOPRIGHT", -scrollbarMargin, -scrollbarPadding)
    scrollBarTrack:SetPoint("BOTTOMRIGHT", -scrollbarMargin, scrollbarPadding)
    scrollBarTrack:SetWidth(scrollbarWidth)
    scrollBarTrack:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Scrollbar slider
    local scrollBar = CreateFrame("Slider", nil, container, "BackdropTemplate")
    scrollBar:SetPoint("TOPRIGHT", -scrollbarMargin, -scrollbarPadding)
    scrollBar:SetPoint("BOTTOMRIGHT", -scrollbarMargin, scrollbarPadding)
    scrollBar:SetWidth(scrollbarWidth)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(1)

    -- Thumb texture
    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.5, 0.5, 0.5, 0.8)
    thumb:SetSize(scrollbarWidth, self.layout.rowHeightLarge + self.layout.padding)
    scrollBar:SetThumbTexture(thumb)

    -- Sync scrollbar with scroll frame
    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    -- Mouse wheel on scrollbar
    scrollBar:EnableMouseWheel(true)
    scrollBar:SetScript("OnMouseWheel", function(self, delta)
        local minVal, maxVal = self:GetMinMaxValues()
        local current = self:GetValue()
        if delta > 0 then
            self:SetValue(math.max(minVal, current - scrollStep))
        else
            self:SetValue(math.min(maxVal, current + scrollStep))
        end
    end)

    -- Mouse wheel on content
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local current = scrollBar:GetValue()
        if delta > 0 then
            scrollBar:SetValue(math.max(minVal, current - scrollStep))
        else
            scrollBar:SetValue(math.min(maxVal, current + scrollStep))
        end
    end)

    -- Also enable mouse wheel on container
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(self, delta)
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local current = scrollBar:GetValue()
        if delta > 0 then
            scrollBar:SetValue(math.max(minVal, current - scrollStep))
        else
            scrollBar:SetValue(math.min(maxVal, current + scrollStep))
        end
    end)

    -- Update scrollbar range when content size changes
    content:SetScript("OnSizeChanged", function(self, contentWidth, contentHeight)
        local scrollHeight = contentHeight - scrollFrame:GetHeight()
        if scrollHeight > 0 then
            scrollBar:SetMinMaxValues(0, scrollHeight)
            scrollBar:Show()
        else
            scrollBar:SetMinMaxValues(0, 0)
            scrollBar:SetValue(0)
            scrollBar:Hide()
        end
    end)

    -- Store references for compatibility
    container.content = content
    container.scrollFrame = scrollFrame
    container.scrollBar = scrollBar

    -- Also make scrollFrame.content work for code that expects it
    scrollFrame.content = content

    return container
end

-- Create a section header
function UI:CreateSectionHeader(parent, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetText(text)
    header:SetTextColor(unpack(self.colors.accent))
    return header
end

-- Create a horizontal divider
function UI:CreateDivider(parent, width)
    local divider = parent:CreateTexture(nil, "OVERLAY")
    divider:SetSize(width or 380, 1)
    divider:SetColorTexture(unpack(self.colors.border))
    return divider
end

-- ============================================================
-- DESIGN STANDARD: Card Components
-- All cards use dynamic width (TOPLEFT + RIGHT anchoring)
-- ============================================================

-- Create a feature card (subtle warm tint, accent border)
-- Used at top of panels to describe the feature
function UI:CreateFeatureCard(parent, yOffset, height)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height or 100)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", self.layout.cardSpacing, yOffset or 0)
    card:SetPoint("RIGHT", parent, "RIGHT", -self.layout.cardSpacing, 0)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    card:SetBackdropColor(0.10, 0.09, 0.07, 0.9)  -- Subtle warm tint
    card:SetBackdropBorderColor(unpack(self.colors.accentDim))
    return card
end

-- Create a settings card (dark, subtle border)
-- Used for grouping related settings
function UI:CreateSettingsCard(parent, yOffset, height)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height or 100)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", self.layout.cardSpacing, yOffset or 0)
    card:SetPoint("RIGHT", parent, "RIGHT", -self.layout.cardSpacing, 0)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    card:SetBackdropColor(unpack(self.colors.background))
    card:SetBackdropBorderColor(unpack(self.colors.borderDark))
    return card
end

-- ============================================================================
-- SETTINGS CONTAINER (DRY COMPONENT)
-- ============================================================================
-- Creates a standardized container for settings panels with consistent padding
-- @param parent: Parent frame
-- @param config: Optional config table { topPadding, bottomPadding }
-- @return container: The container frame
-- @return content: The scroll content frame (add elements to this)
function UI:CreateSettingsContainer(parent, config)
    config = config or {}
    local topPadding = config.topPadding or self.layout.padding
    local bottomPadding = config.bottomPadding or self.layout.padding
    
    local scrollFrame, content = self:CreateScrollPanel(parent)
    
    -- Store reference to track content height with initial top padding
    content._yOffset = -topPadding
    content._topPadding = topPadding
    content._bottomPadding = bottomPadding
    
    -- Helper to get current Y offset
    function content:GetYOffset()
        return self._yOffset
    end
    
    -- Helper to advance Y offset
    function content:AdvanceY(amount)
        self._yOffset = self._yOffset - amount
        return self._yOffset
    end
    
    -- Helper to finalize content height (includes top and bottom padding)
    function content:FinalizeHeight(extraPadding)
        local extra = extraPadding or self._bottomPadding
        self:SetHeight(math.abs(self._yOffset) + extra)
    end
    
    return scrollFrame, content
end

-- ============================================================================
-- DYNAMIC SETTINGS CARD (DRY COMPONENT)
-- ============================================================================
-- Creates a settings card that auto-sizes based on content
-- Supports optional title inside the card (not outside)
-- @param parent: Parent frame
-- @param config: Table with options:
--   - yOffset: Y position offset (default: parent:GetYOffset() if available)
--   - title: Optional title text (displayed inside card at top)
--   - description: Optional description text below title
--   - padding: Internal padding (default: layout.padding)
-- @return card: The card frame with helper methods
function UI:CreateCard(parent, config)
    config = config or {}
    local padding = config.padding or self.layout.padding
    local yOffset = config.yOffset or (parent.GetYOffset and parent:GetYOffset()) or 0
    
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", self.layout.cardSpacing, yOffset)
    card:SetPoint("RIGHT", parent, "RIGHT", -self.layout.cardSpacing, 0)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    card:SetBackdropColor(unpack(self.colors.background))
    card:SetBackdropBorderColor(unpack(self.colors.borderDark))
    
    -- Track content height
    card._contentHeight = padding
    card._padding = padding
    card._leftPadding = padding + 2
    
    -- Add title inside card if provided
    if config.title then
        local titleY = -card._contentHeight
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", card._leftPadding, titleY)
        title:SetText(self:ColorText(config.title, "accent"))
        card.title = title
        card._contentHeight = card._contentHeight + 20
        
        -- Add description if provided
        if config.description then
            local desc = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            desc:SetPoint("TOPLEFT", card, "TOPLEFT", card._leftPadding, -card._contentHeight)
            desc:SetPoint("RIGHT", card, "RIGHT", -padding, 0)
            desc:SetJustifyH("LEFT")
            desc:SetText(config.description)
            desc:SetTextColor(0.7, 0.7, 0.7)
            card.description = desc
            
            -- Dynamically calculate height based on actual rendered text
            -- Use parent width minus card margins to estimate available width
            local parentWidth = parent:GetWidth()
            if parentWidth and parentWidth > 0 then
                local availableWidth = parentWidth - (self.layout.cardSpacing * 2) - card._leftPadding - padding
                desc:SetWidth(availableWidth)
            end
            local descHeight = desc:GetStringHeight() or 14
            card._contentHeight = card._contentHeight + descHeight + 6
        end
        
        -- Add spacing after header
        card._contentHeight = card._contentHeight + 6
    end
    
    -- Add content and track height
    -- @param height: Height of the content being added
    -- @return yPos: The Y position where this content should be placed
    function card:AddContent(height)
        local yPos = -self._contentHeight
        self._contentHeight = self._contentHeight + height
        self:SetHeight(self._contentHeight + self._padding)
        return yPos
    end
    
    -- Add a checkbox with optional hint
    -- @param text: Checkbox label
    -- @param default: Default value
    -- @param hint: Optional hint text (appears below checkbox, defaults to gray)
    -- @param hintColor: Optional table of {r, g, b, a} to override default gray
    -- @return checkbox: The checkbox widget
    function card:AddCheckbox(text, default, hint, hintColor)
        -- Calculate hint height dynamically if hint exists
        local hintHeight = 0
        local hintText = nil
        
        if hint then
            -- Create hint FontString first to measure height
            hintText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hintText:SetJustifyH("LEFT")
            -- Strip any existing color codes from hint (DRY handles color)
            local cleanHint = hint:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            hintText:SetText(cleanHint)
            
            -- Calculate width for proper wrapping
            local parentWidth = self:GetParent():GetWidth()
            if parentWidth and parentWidth > 0 then
                local availableWidth = parentWidth - (UI.layout.cardSpacing * 2) - self._leftPadding - self._padding - 24
                hintText:SetWidth(availableWidth)
            end
            
            hintHeight = (hintText:GetStringHeight() or 14) + 4
            
            -- Default to gray, allow override
            if type(hintColor) == "table" then
                hintText:SetTextColor(unpack(hintColor))
            else
                hintText:SetTextColor(0.4, 0.4, 0.4, 1)  -- Default gray
            end
        end
        
        -- Reserve space: checkbox (24) + hint height
        local totalHeight = 24 + hintHeight + 4
        local checkY = self:AddContent(totalHeight)
        
        local check = UI:CreateCheckbox(self, text, default)
        check:SetPoint("TOPLEFT", self, "TOPLEFT", self._leftPadding, checkY)
        check:SetPoint("RIGHT", self, "RIGHT", -self._padding, 0)
        
        if hintText then
            hintText:SetPoint("TOPLEFT", self, "TOPLEFT", self._leftPadding + 24, checkY - 22)
            hintText:SetPoint("RIGHT", self, "RIGHT", -self._padding, 0)
            check.hint = hintText
        end
        
        return check
    end
    
    -- Add text/description
    -- @param text: The text to display
    -- @param minHeight: Optional minimum height (default: auto-calculated)
    -- @return fontString: The created font string
    function card:AddText(text, minHeight)
        -- Create FontString first to measure actual height
        local fs = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(0.6, 0.6, 0.6)
        
        -- Calculate width for proper wrapping
        local parentWidth = self:GetParent():GetWidth()
        if parentWidth and parentWidth > 0 then
            local availableWidth = parentWidth - (UI.layout.cardSpacing * 2) - self._leftPadding - self._padding
            fs:SetWidth(availableWidth)
        end
        
        -- Get actual rendered height, with minimum
        local textHeight = fs:GetStringHeight() or 14
        local height = math.max(textHeight + 4, minHeight or 0)
        
        local textY = self:AddContent(height)
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", self._leftPadding, textY)
        fs:SetPoint("RIGHT", self, "RIGHT", -self._padding, 0)
        
        return fs
    end
    
    -- Get current content height (for external tracking)
    function card:GetContentHeight()
        return self._contentHeight + self._padding
    end
    
    -- Initialize with padding
    card:SetHeight(padding * 2)
    
    return card
end

-- Legacy wrapper for CreateDynamicSettingsCard
function UI:CreateDynamicSettingsCard(parent, yOffset, padding)
    return self:CreateCard(parent, { yOffset = yOffset, padding = padding })
end

-- ============================================================================
-- CHECKBOX WITH HINT (DRY COMPONENT) - Legacy support
-- ============================================================================
-- Creates a checkbox with an optional hint line below it
-- @param parent: Parent frame (usually a card)
-- @param text: Checkbox label text
-- @param default: Default checked state
-- @param hint: Optional hint text to show below the checkbox
-- @param hintColor: Optional hint color (default: dim gray)
-- @return container: Container frame with .checkbox and .hint references
-- @return totalHeight: Total height of the component (for layout calculations)
function UI:CreateCheckboxWithHint(parent, text, default, hint, hintColor)
    local rowHeight = self.layout.rowHeight
    local hintHeight = hint and self.layout.iconSizeSmall or 0
    local totalHeight = rowHeight + hintHeight
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(totalHeight)
    
    -- Create checkbox
    local checkbox = self:CreateCheckbox(container, text, default)
    checkbox:SetPoint("TOPLEFT", 0, 0)
    
    -- Create hint if provided
    if hint then
        local hintText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintText:SetPoint("TOPLEFT", self.layout.iconSize, -rowHeight + self.layout.elementSpacing)
        hintText:SetText(hint)
        hintText:SetTextColor(unpack(hintColor or self.colors.textDisabled))
        container.hint = hintText
    end
    
    container.checkbox = checkbox.checkbox
    container.label = checkbox.label
    
    return container, totalHeight
end

-- Create a scroll panel that fills parent and resizes dynamically
-- Returns: scrollFrame, content (use content as parent for children)
function UI:CreateScrollPanel(parent)
    local scrollFrame = self:CreateScrollFrame(parent, nil, nil, true)  -- fill mode
    local content = scrollFrame.content
    return scrollFrame, content
end

-- ============================================================
-- SHARED UI UTILITIES
-- ============================================================

-- Unpack color table to r, g, b, a values
-- Used for SetVertexColor/SetTextColor calls
function UI:UnpackColor(colorTable, includeAlpha)
    if includeAlpha == false then
        return colorTable[1], colorTable[2], colorTable[3]
    end
    return colorTable[1], colorTable[2], colorTable[3], colorTable[4]
end

-- Create a standard item list row with icon, name, and remove button
-- Used by Whitelist and JunkList panels
-- @param parent: Parent frame for the row
-- @param itemID: Item ID
-- @param itemName: Item name (optional, will be fetched if nil)
-- @param itemLink: Item link (optional, will be fetched if nil)
-- @param itemTexture: Item texture path (optional, will be fetched if nil)
-- @param yOffset: Y offset for positioning
-- @param removeCallback: Function to call when remove button is clicked (receives itemID)
-- @return row: The created row frame
function UI:CreateItemListRow(parent, itemID, itemName, itemLink, itemTexture, yOffset, removeCallback)
    -- Fetch item info if not provided
    if not itemName or not itemLink or not itemTexture then
        local name, link, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
        itemName = itemName or name
        itemLink = itemLink or link
        itemTexture = itemTexture or texture
    end

    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(self.layout.rowHeightSmall + 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", self.layout.cardSpacing, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", -self.layout.cardSpacing, 0)

    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.layout.borderSize,
    })
    row:SetBackdropColor(0.12, 0.12, 0.12, 1)
    row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    -- Icon
    local icon = row:CreateTexture(nil, "OVERLAY")
    icon:SetSize(self.layout.iconSize, self.layout.iconSize)
    icon:SetPoint("LEFT", self.layout.paddingSmall, 0)
    icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Remove button (red X style)
    local removeBtnSize = self.layout.buttonHeightSmall
    local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    removeBtn:SetSize(removeBtnSize, removeBtnSize)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    removeBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
    removeBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)
    removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    removeBtn.text:SetPoint("CENTER")
    removeBtn.text:SetText("|cffff6666X|r")
    removeBtn.itemID = itemID
    removeBtn:SetScript("OnClick", function(self)
        if removeCallback then
            removeCallback(self.itemID)
        end
    end)
    removeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.1, 0.1, 1)
        self.text:SetText("|cffff0000X|r")
    end)
    removeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.1, 0.1, 1)
        self.text:SetText("|cffff6666X|r")
    end)

    -- Name (anchored between icon and remove button)
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", icon, "RIGHT", self.layout.elementSpacing, 0)
    name:SetPoint("RIGHT", removeBtn, "LEFT", -self.layout.elementSpacing, 0)
    name:SetText(itemLink or itemName or ("Item #" .. itemID))
    name:SetJustifyH("LEFT")

    return row
end

-- Factory function to build item list UI from data table
-- Handles creation, empty state, and dynamic sizing
-- @param scrollContent: The parent content frame (from CreateScrollPanel)
-- @param dataTable: Table of items (keys are itemIDs)
-- @param emptyText: Text to show when list is empty
-- @param removeCallback: Function to call when remove button is clicked (receives itemID)
-- @return refreshFunction: Function to call to rebuild the list
-- @return listContainer: The container frame (for positioning other elements)
function UI:CreateItemListBuilder(scrollContent, dataTable, emptyText, removeCallback)
    local listContainer = CreateFrame("Frame", nil, scrollContent)
    listContainer:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
    listContainer:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    listContainer:SetHeight(self.layout.listInitialHeight)

    -- "No items" label
    local noItemsLabel = listContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noItemsLabel:SetPoint("TOPLEFT", self.layout.cardSpacing, 0)
    noItemsLabel:SetText("|cff888888" .. (emptyText or "No items.") .. "|r")
    noItemsLabel:Hide()

    -- Refresh function
    local function RefreshList()
        -- Clear existing children
        for _, child in pairs({listContainer:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local yOffset = 0
        local count = 0

        for itemID in pairs(dataTable) do
            count = count + 1
            UI:CreateItemListRow(listContainer, itemID, nil, nil, nil, yOffset, removeCallback)
            yOffset = yOffset - 28
        end

        if count == 0 then
            noItemsLabel:Show()
            yOffset = -24
        else
            noItemsLabel:Hide()
        end

        local listHeight = math.max(math.abs(yOffset), 24)
        listContainer:SetHeight(listHeight)

        return listHeight
    end

    return RefreshList, listContainer
end

-- ============================================================================
-- REUSABLE TAB BAR COMPONENT
-- ============================================================================
-- Creates a consistent tab bar that can be used anywhere
-- @param parent: Parent frame for the tab bar
-- @param config: Table with:
--   - tabs: Array of {id, label} objects
--   - height: Optional tab bar height (default: layout.tabHeight)
--   - tabWidth: Optional fixed tab width (nil = auto-calculate)
--   - onSelect: Callback function(tabId) called when tab is selected
--   - padding: Optional horizontal padding (default: layout.padding)
--   - spacing: Optional spacing between tabs (default: layout.paddingSmall)
-- @return tabBar: The tab bar frame
-- @return selectTab: Function to programmatically select a tab
-- @return getActiveTab: Function to get currently active tab id
function UI:CreateTabBar(parent, config)
    config = config or {}
    local tabs = config.tabs or {}
    local height = config.height or self.layout.tabHeight
    local padding = config.padding or self.layout.padding
    local spacing = config.spacing or self.layout.paddingSmall

    -- Create tab bar frame
    local tabBar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    tabBar:SetHeight(height)
    tabBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    tabBar:SetBackdropColor(0.08, 0.08, 0.08, 1)

    -- Store tab buttons and state
    local tabButtons = {}
    local activeTab = nil

    -- Selection function
    local function SelectTab(tabId)
        activeTab = tabId
        for _, btn in pairs(tabButtons) do
            if btn.id == tabId then
                btn:SetBackdropColor(unpack(self.colors.tabSelected))
                btn.text:SetTextColor(unpack(self.colors.tabSelectedText))
            else
                btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
                btn.text:SetTextColor(unpack(self.colors.text))
            end
        end
        -- Call user callback if provided
        if config.onSelect then
            config.onSelect(tabId)
        end
    end

    -- Create individual tab buttons
    local function CreateTabButton(data, index)
        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:SetHeight(height - 6)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = self.layout.borderSize,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(unpack(self.colors.border))

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(data.label)
        btn.text:SetTextColor(unpack(self.colors.text))

        btn.id = data.id
        btn.tabIndex = index

        btn:SetScript("OnClick", function()
            SelectTab(data.id)
        end)

        btn:SetScript("OnEnter", function(self)
            if activeTab ~= self.id then
                self:SetBackdropColor(unpack(UI.colors.headerBarHover))
            end
        end)

        btn:SetScript("OnLeave", function(self)
            if activeTab ~= self.id then
                self:SetBackdropColor(0.15, 0.15, 0.15, 1)
            end
        end)

        return btn
    end

    -- Create all tabs
    for i, data in ipairs(tabs) do
        local btn = CreateTabButton(data, i)
        tabButtons[data.id] = btn
        table.insert(tabButtons, btn) -- Also store by index for layout
    end

    -- Layout function (handles dynamic sizing)
    local function LayoutTabs()
        local barWidth = tabBar:GetWidth() or 0
        if barWidth <= 0 then return end

        local count = #tabs
        if count == 0 then return end

        local availableWidth = barWidth - (padding * 2) - (spacing * (count - 1))
        local tabWidth = config.tabWidth or math.max(70, math.floor(availableWidth / count))

        local xOffset = padding
        for i, data in ipairs(tabs) do
            local btn = tabButtons[data.id]
            if btn then
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
                btn:SetWidth(tabWidth)
                xOffset = xOffset + tabWidth + spacing
            end
        end
    end

    -- Re-layout when size changes
    tabBar:SetScript("OnSizeChanged", LayoutTabs)
    C_Timer.After(0, LayoutTabs)

    -- Store references
    tabBar.buttons = tabButtons
    tabBar.SelectTab = SelectTab
    tabBar.LayoutTabs = LayoutTabs
    tabBar.GetActiveTab = function() return activeTab end

    return tabBar, SelectTab, function() return activeTab end
end
