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
    border = { 0.3, 0.3, 0.3, 1 },
    borderLight = { 0.5, 0.5, 0.5, 1 },
    text = { 1, 1, 1, 1 },
    textDim = { 0.7, 0.7, 0.7, 1 },
    textDisabled = { 0.4, 0.4, 0.4, 1 },

    -- Cheddar/golden accent colors (based on logo)
    accent = { 1.0, 0.69, 0, 1 },           -- #FFB000 golden amber
    accentHover = { 1.0, 0.78, 0.2, 1 },    -- brighter gold on hover
    accentBright = { 1.0, 0.84, 0, 1 },     -- #FFD700 bright gold
    accentDim = { 0.8, 0.55, 0, 1 },        -- muted amber for subtle elements

    -- Semantic colors (keep for meaning)
    success = { 0.3, 0.8, 0.3, 1 },         -- green for positive
    warning = { 1.0, 0.69, 0, 1 },          -- same as accent
    error = { 0.9, 0.3, 0.3, 1 },           -- red for errors

    -- UI element colors
    headerBar = { 0.15, 0.12, 0.05, 1 },    -- warm amber tint for title bars
}

-- Hex color codes for inline WoW text formatting
UI.hexColors = {
    accent = "ffb000",        -- golden amber
    accentBright = "ffd700",  -- bright gold
    success = "4dcc4d",       -- green
    error = "e64d4d",         -- red
    warning = "ffb000",       -- golden (same as accent)
    info = "88ccff",          -- light blue for informational
    dim = "888888",           -- gray for muted text
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
        edgeSize = 1,
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
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    header:SetBackdropColor(unpack(self.colors.headerBar))
    header:SetBackdropBorderColor(unpack(self.colors.border))

    -- Title text (uses accent color like Dashboard/MailPopup)
    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.title:SetPoint("LEFT", 10, 0)
    header.title:SetText(title or "InventoryManager")
    header.title:SetTextColor(unpack(self.colors.accent))

    -- Close button (red X style)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
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
    button:SetSize(width or 100, height or 24)

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
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
    container:SetSize(200, 20)

    local checkbox = CreateFrame("CheckButton", nil, container, "BackdropTemplate")
    checkbox:SetSize(18, 18)
    checkbox:SetPoint("LEFT", 0, 0)

    checkbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    checkbox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    checkbox:SetBackdropBorderColor(unpack(self.colors.border))

    -- Checkmark
    checkbox.check = checkbox:CreateTexture(nil, "OVERLAY")
    checkbox.check:SetSize(14, 14)
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
    container:SetSize(340, 50)

    -- Label (on its own line)
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.label:SetPoint("TOPLEFT", 0, 0)
    container.label:SetText(text or "")
    container.label:SetTextColor(unpack(self.colors.text))
    container.label:SetWidth(320)
    container.label:SetJustifyH("LEFT")

    -- Slider
    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetSize(280, 12)
    slider:SetPoint("TOPLEFT", 0, -20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    slider:SetBackdropColor(0.1, 0.1, 0.1, 1)
    slider:SetBackdropBorderColor(unpack(self.colors.border))

    -- Thumb
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(10, 18)
    thumb:SetVertexColor(unpack(self.colors.accent))

    -- Value display (next to slider)
    container.value = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.value:SetPoint("LEFT", slider, "RIGHT", 8, 0)
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
    container:SetSize(340, 45)

    -- Label
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.label:SetPoint("TOPLEFT", 0, 0)
    container.label:SetText(text or "")
    container.label:SetTextColor(unpack(self.colors.text))

    -- Editbox
    local editbox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editbox:SetSize(80, 22)
    editbox:SetPoint("TOPLEFT", 0, -16)
    editbox:SetFontObject("GameFontNormalSmall")
    editbox:SetAutoFocus(false)
    editbox:SetNumeric(true)
    editbox:SetMaxLetters(6)

    editbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    editbox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    editbox:SetBackdropBorderColor(unpack(self.colors.border))
    editbox:SetTextInsets(6, 6, 0, 0)
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
    container:SetSize(340, 45)

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

    -- Gold editbox
    local goldBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    goldBox:SetSize(50, 22)
    goldBox:SetPoint("TOPLEFT", 0, -16)
    goldBox:SetFontObject("GameFontNormalSmall")
    goldBox:SetAutoFocus(false)
    goldBox:SetNumeric(true)
    goldBox:SetMaxLetters(5)
    goldBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    goldBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    goldBox:SetBackdropBorderColor(unpack(self.colors.border))
    goldBox:SetTextInsets(4, 4, 0, 0)
    goldBox:SetTextColor(1, 0.84, 0, 1) -- Gold color
    goldBox:SetText(tostring(gold))

    -- Gold icon
    local goldIcon = container:CreateTexture(nil, "OVERLAY")
    goldIcon:SetSize(14, 14)
    goldIcon:SetPoint("LEFT", goldBox, "RIGHT", 2, 0)
    goldIcon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")

    -- Silver editbox
    local silverBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    silverBox:SetSize(35, 22)
    silverBox:SetPoint("LEFT", goldIcon, "RIGHT", 6, 0)
    silverBox:SetFontObject("GameFontNormalSmall")
    silverBox:SetAutoFocus(false)
    silverBox:SetNumeric(true)
    silverBox:SetMaxLetters(2)
    silverBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    silverBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    silverBox:SetBackdropBorderColor(unpack(self.colors.border))
    silverBox:SetTextInsets(4, 4, 0, 0)
    silverBox:SetTextColor(0.75, 0.75, 0.75, 1) -- Silver color
    silverBox:SetText(tostring(silver))

    -- Silver icon
    local silverIcon = container:CreateTexture(nil, "OVERLAY")
    silverIcon:SetSize(14, 14)
    silverIcon:SetPoint("LEFT", silverBox, "RIGHT", 2, 0)
    silverIcon:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")

    -- Copper editbox
    local copperBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    copperBox:SetSize(35, 22)
    copperBox:SetPoint("LEFT", silverIcon, "RIGHT", 6, 0)
    copperBox:SetFontObject("GameFontNormalSmall")
    copperBox:SetAutoFocus(false)
    copperBox:SetNumeric(true)
    copperBox:SetMaxLetters(2)
    copperBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    copperBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    copperBox:SetBackdropBorderColor(unpack(self.colors.border))
    copperBox:SetTextInsets(4, 4, 0, 0)
    copperBox:SetTextColor(0.72, 0.45, 0.2, 1) -- Copper color
    copperBox:SetText(tostring(copperRemainder))

    -- Copper icon
    local copperIcon = container:CreateTexture(nil, "OVERLAY")
    copperIcon:SetSize(14, 14)
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
    container:SetSize(200, 40)

    -- Label
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    container.label:SetPoint("TOPLEFT", 0, 0)
    container.label:SetText(text or "")
    container.label:SetTextColor(unpack(self.colors.text))

    -- Dropdown button
    local dropdown = CreateFrame("Button", nil, container, "BackdropTemplate")
    dropdown:SetSize(180, 22)
    dropdown:SetPoint("TOPLEFT", 0, -14)

    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dropdown:SetBackdropColor(0.12, 0.12, 0.12, 1)
    dropdown:SetBackdropBorderColor(unpack(self.colors.border))

    dropdown.text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropdown.text:SetPoint("LEFT", 6, 0)
    dropdown.text:SetTextColor(unpack(self.colors.text))

    dropdown.arrow = dropdown:CreateTexture(nil, "OVERLAY")
    dropdown.arrow:SetSize(12, 12)
    dropdown.arrow:SetPoint("RIGHT", -4, 0)
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
            edgeSize = 1,
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
    local height = 4
    for i, option in ipairs(options) do
        local button = menu.buttons[i]
        if not button then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(20)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("LEFT", 6, 0)
            button.text:SetTextColor(unpack(self.colors.text))

            button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
            button.highlight:SetAllPoints()
            button.highlight:SetColorTexture(0.3, 0.3, 0.3, 0.5)

            menu.buttons[i] = button
        end

        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -height)
        button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -height)
        button.text:SetText(option)
        button:SetScript("OnClick", function()
            callback(i, option)
            menu:Hide()
        end)
        button:Show()

        height = height + 20
    end

    menu:SetSize(anchor:GetWidth(), height + 4)
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
        edgeSize = 1,
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

    -- Scrollbar track
    local scrollBarTrack = container:CreateTexture(nil, "BACKGROUND")
    scrollBarTrack:SetPoint("TOPRIGHT", -2, -4)
    scrollBarTrack:SetPoint("BOTTOMRIGHT", -2, 4)
    scrollBarTrack:SetWidth(10)
    scrollBarTrack:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Scrollbar slider
    local scrollBar = CreateFrame("Slider", nil, container, "BackdropTemplate")
    scrollBar:SetPoint("TOPRIGHT", -2, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", -2, 4)
    scrollBar:SetWidth(10)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(1)

    -- Thumb texture
    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.5, 0.5, 0.5, 0.8)
    thumb:SetSize(10, 40)
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
        local step = 40
        if delta > 0 then
            self:SetValue(math.max(minVal, current - step))
        else
            self:SetValue(math.min(maxVal, current + step))
        end
    end)

    -- Mouse wheel on content
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local current = scrollBar:GetValue()
        local step = 40
        if delta > 0 then
            scrollBar:SetValue(math.max(minVal, current - step))
        else
            scrollBar:SetValue(math.min(maxVal, current + step))
        end
    end)

    -- Also enable mouse wheel on container
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(self, delta)
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local current = scrollBar:GetValue()
        local step = 40
        if delta > 0 then
            scrollBar:SetValue(math.max(minVal, current - step))
        else
            scrollBar:SetValue(math.min(maxVal, current + step))
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

-- Create a feature card (amber tint, accent border)
-- Used at top of panels to describe the feature
function UI:CreateFeatureCard(parent, yOffset, height)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height or 100)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset or 0)
    card:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.12, 0.10, 0.06, 0.9)  -- Warm amber tint
    card:SetBackdropBorderColor(unpack(self.colors.accent))
    return card
end

-- Create a settings card (dark, subtle border)
-- Used for grouping related settings
function UI:CreateSettingsCard(parent, yOffset, height)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height or 100)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset or 0)
    card:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.08, 0.08, 0.08, 0.8)  -- Dark background
    card:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)  -- Subtle border
    return card
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
    row:SetHeight(26)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0.12, 0.12, 0.12, 1)
    row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    -- Icon
    local icon = row:CreateTexture(nil, "OVERLAY")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Remove button (red X style)
    local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    removeBtn:SetSize(22, 22)
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
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
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
    listContainer:SetHeight(10)

    -- "No items" label
    local noItemsLabel = listContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noItemsLabel:SetPoint("TOPLEFT", 10, 0)
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
