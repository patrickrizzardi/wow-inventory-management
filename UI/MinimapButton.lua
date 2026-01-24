--[[
    InventoryManager - UI/MinimapButton.lua
    Minimap button for quick access to settings and dashboard.
]]

local addonName, IM = ...
local UI = IM.UI

UI.MinimapButton = {}

local MinimapButton = UI.MinimapButton
local _button = nil
local _isDragging = false

-- Default position
local DEFAULT_ANGLE = 220

-- Create the minimap button
function MinimapButton:Create()
    if _button then return _button end

    -- Use LibDBIcon naming convention so SexyMap detects this button
    local button = CreateFrame("Button", "LibDBIcon10_InventoryManager", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Button background
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(26, 26)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Icon
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(237381)  -- Gold coins icon

    -- Border
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Position the button on the minimap edge
    local function UpdatePosition(angle)
        -- Calculate radius based on minimap size to sit ON the border ring
        -- Minimap is typically 140px, so radius ~70 to edge, plus offset for button
        local mapRadius = (Minimap:GetWidth() or 140) / 2
        local radius = mapRadius + 10  -- Offset to place button ON the edge ring
        local radian = math.rad(angle)
        local x = math.cos(radian) * radius
        local y = math.sin(radian) * radius
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- Calculate angle from cursor position
    local function GetCursorAngle()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        return math.deg(math.atan2(cy - my, cx - mx))
    end

    -- Click handler
    button:SetScript("OnClick", function(self, btn)
        if _isDragging then return end

        if btn == "LeftButton" then
            -- Toggle Settings
            if IM.UI and IM.UI.ToggleConfig then
                IM.UI:ToggleConfig()
            end
        elseif btn == "RightButton" then
            -- Open Dashboard
            if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Show then
                IM.UI.Dashboard:Show()
            end
        end
    end)

    -- Drag handlers for repositioning
    button:SetScript("OnDragStart", function(self)
        _isDragging = true
        self:SetScript("OnUpdate", function(self)
            local angle = GetCursorAngle()
            UpdatePosition(angle)
            -- Save position
            if IM.db and IM.db.global then
                IM.db.global.minimapButtonAngle = angle
            end
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        C_Timer.After(0.1, function()
            _isDragging = false
        end)
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("InventoryManager", 1, 0.84, 0)
        GameTooltip:AddLine(" ")
        
        -- Show current net worth if available
        if IM.modules and IM.modules.NetWorth then
            local breakdown = IM.modules.NetWorth:GetAccountBreakdown()
            if breakdown and breakdown.total and breakdown.total.netWorth > 0 then
                local gold = math.floor(breakdown.total.netWorth / 10000)
                local silver = math.floor((breakdown.total.netWorth % 10000) / 100)
                GameTooltip:AddLine(string.format("Net Worth: |cffffd700%s|cffddddddg |cffc0c0c0%02ds|r", 
                    IM:FormatNumber(gold), silver), 1, 1, 1)
                GameTooltip:AddLine(" ")
            end
        end
        
        GameTooltip:AddLine("|cffffffffLeft-click:|r Open Settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffRight-click:|r Open Tracker", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffDrag:|r Move Button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Load saved position
    local angle = DEFAULT_ANGLE
    if IM.db and IM.db.global and IM.db.global.minimapButtonAngle then
        angle = IM.db.global.minimapButtonAngle
    end
    UpdatePosition(angle)

    -- Show/hide based on setting
    if IM.db and IM.db.global and IM.db.global.ui and IM.db.global.ui.showMinimapButton == false then
        button:Hide()
    else
        button:Show()
    end

    _button = button
    return button
end

-- Update the button text with live stats (for LibDataBroker displays)
function MinimapButton:UpdateText()
    if not self.dataObj then return end
    
    if IM.modules and IM.modules.NetWorth then
        local breakdown = IM.modules.NetWorth:GetAccountBreakdown()
        if breakdown and breakdown.total and breakdown.total.netWorth > 0 then
            local gold = math.floor(breakdown.total.netWorth / 10000)
            self.dataObj.text = string.format("IM: %s|cffddddddg|r", IM:FormatNumber(gold))
        else
            self.dataObj.text = "IM: --"
        end
    else
        self.dataObj.text = "IM"
    end
end

-- Show the button
function MinimapButton:Show()
    if IM.db and IM.db.global and IM.db.global.ui then
        IM.db.global.ui.showMinimapButton = true
    end

    if self.ldbiRegistered and self.ldbi then
        self.ldbi:Show("InventoryManager")
    else
        local button = self:Create()
        button:Show()
    end
end

-- Hide the button
function MinimapButton:Hide()
    if self.ldbiRegistered and self.ldbi then
        self.ldbi:Hide("InventoryManager")
    elseif _button then
        _button:Hide()
    end
end

-- Toggle the button
function MinimapButton:Toggle()
    if self:IsShown() then
        self:Hide()
        if IM.db and IM.db.global and IM.db.global.ui then
            IM.db.global.ui.showMinimapButton = false
        end
    else
        self:Show()
    end
end

-- Check if button is shown
function MinimapButton:IsShown()
    if self.ldbiRegistered and self.ldbi then
        local button = self.ldbi:GetMinimapButton("InventoryManager")
        return button and button:IsShown()
    end
    return _button and _button:IsShown()
end

-- Try to register with LibDBIcon if available (for SexyMap compatibility)
function MinimapButton:RegisterWithLibDBIcon()
    -- Check if LibDBIcon is available (from another addon)
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)

    if LDB and LDBI then
        -- Create a data broker object
        local dataObj = LDB:NewDataObject("InventoryManager", {
            type = "data source",  -- Supports both launcher and data display
            icon = 237381,  -- Gold coins icon
            text = "IM: --",  -- Initial text
            OnClick = function(self, button)
                if button == "LeftButton" then
                    if IM.UI and IM.UI.ToggleConfig then
                        IM.UI:ToggleConfig()
                    end
                elseif button == "RightButton" then
                    if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Show then
                        IM.UI.Dashboard:Show()
                    end
                end
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine("InventoryManager", 1, 0.84, 0)
                tooltip:AddLine(" ")
                
                -- Show current net worth if available
                if IM.modules and IM.modules.NetWorth then
                    local breakdown = IM.modules.NetWorth:GetAccountBreakdown()
                    if breakdown and breakdown.total and breakdown.total.netWorth > 0 then
                        local gold = math.floor(breakdown.total.netWorth / 10000)
                        local silver = math.floor((breakdown.total.netWorth % 10000) / 100)
                        tooltip:AddLine(string.format("Net Worth: |cffffd700%s|cffddddddg |cffc0c0c0%02ds|r", 
                            IM:FormatNumber(gold), silver), 1, 1, 1)
                        tooltip:AddLine(" ")
                    end
                end
                
                tooltip:AddLine("|cffffffffLeft-click:|r Open Settings", 0.8, 0.8, 0.8)
                tooltip:AddLine("|cffffffffRight-click:|r Open Tracker", 0.8, 0.8, 0.8)
            end,
        })
        
        -- Store reference for text updates
        MinimapButton.dataObj = dataObj

        -- Register with LibDBIcon
        -- showInCompartment adds button to the Addon Compartment (consolidated button popup)
        LDBI:Register("InventoryManager", dataObj, {
            hide = not (IM.db and IM.db.global and IM.db.global.ui and IM.db.global.ui.showMinimapButton ~= false),
            showInCompartment = true,
        })

        -- Store reference so we can hide/show via LDBI
        MinimapButton.ldbiRegistered = true
        MinimapButton.ldbi = LDBI

        -- Hide our custom button since LDBI creates its own
        if _button then
            _button:Hide()
        end

        -- Hook the LDBI button for right-click with multiple fallback approaches
        -- SexyMap and other minimap addons can interfere with normal click handling
        local function SetupButtonHooks()
            local ldbiButton = LDBI:GetMinimapButton("InventoryManager")
            if not ldbiButton then
                IM:Debug("LibDBIcon button not found for hooking")
                return false
            end

            -- Enable all click types
            ldbiButton:RegisterForClicks("AnyUp", "AnyDown")

            -- Method 1: Hook OnMouseUp (more reliable than OnClick with some addons)
            if not ldbiButton._imHooked then
                ldbiButton._imHooked = true

                -- Store original scripts
                local origOnClick = ldbiButton:GetScript("OnClick")
                local origOnMouseUp = ldbiButton:GetScript("OnMouseUp")

                -- Set our own OnMouseUp handler (fires before OnClick)
                ldbiButton:SetScript("OnMouseUp", function(self, btn)
                    if btn == "LeftButton" then
                        if IM.UI and IM.UI.ToggleConfig then
                            IM.UI:ToggleConfig()
                        end
                    elseif btn == "RightButton" then
                        if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Show then
                            IM.UI.Dashboard:Show()
                        end
                        return -- Don't propagate
                    end
                    if origOnMouseUp then
                        origOnMouseUp(self, btn)
                    end
                end)

                -- Also hook OnClick as fallback for both buttons
                ldbiButton:HookScript("OnClick", function(self, btn)
                    if btn == "LeftButton" then
                        if IM.UI and IM.UI.ToggleConfig then
                            IM.UI:ToggleConfig()
                        end
                    elseif btn == "RightButton" then
                        if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Show then
                            IM.UI.Dashboard:Show()
                        end
                    end
                end)

                IM:Debug("LibDBIcon button hooked for left and right-click")
            end
            return true
        end

        -- Try immediately, then again after delays (SexyMap loads late)
        C_Timer.After(0.5, SetupButtonHooks)
        C_Timer.After(2, SetupButtonHooks)
        C_Timer.After(5, SetupButtonHooks)

        IM:Debug("Registered with LibDBIcon for SexyMap compatibility")
        return true
    end

    return false
end

-- Initialize the minimap button on addon load
IM:RegisterEvent("PLAYER_LOGIN", function()
    -- Try LibDBIcon first (for SexyMap and other minimap addon compatibility)
    if not MinimapButton:RegisterWithLibDBIcon() then
        -- Fall back to our custom button
        MinimapButton:Create()
    end
    
    -- Update text every 5 seconds for LDB displays
    C_Timer.NewTicker(5, function()
        MinimapButton:UpdateText()
    end)
    
    -- Initial update after a delay (let NetWorth module initialize)
    C_Timer.After(2, function()
        MinimapButton:UpdateText()
    end)
end)
