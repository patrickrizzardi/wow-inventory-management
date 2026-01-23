--[[
    InventoryManager - UI/Config.lua
    Main configuration panel with tab navigation
]]

local addonName, IM = ...
local UI = IM.UI

-- Main config frame
local configFrame = nil

-- Tab panels
local tabPanels = {}
local activeTab = nil

-- Tab definitions
local tabs = {
    { name = "General", module = "General" },
    { name = "UI", module = "UI" },
    { name = "Selling", module = "Selling" },
    { name = "Tracking", module = "Dashboard" },      -- Consolidated: Ledger, Net Worth, Inventory settings
    { name = "Mail Helper", module = "MailHelper" },  -- Alt mail automation
    { name = "Currencies", module = "Currency" },
}

-- Create the main config frame
function UI:CreateConfigFrame()
    if configFrame then return configFrame end

    -- Main panel - fixed size for consistent, readable layout
    configFrame = self:CreatePanel("InventoryManagerConfig", UIParent, 550, 600)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("HIGH")
    configFrame:Hide()

    -- Header
    local header = self:CreateHeader(configFrame, "InventoryManager Settings")

    -- Tab container (left side) - anchored to stretch with frame
    local tabContainer = CreateFrame("Frame", nil, configFrame, "BackdropTemplate")
    tabContainer:SetWidth(100)
    tabContainer:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 0, -28)
    tabContainer:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 0, 0)
    tabContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    tabContainer:SetBackdropColor(0.06, 0.06, 0.06, 1)
    tabContainer:SetBackdropBorderColor(unpack(self.colors.border))

    -- Create tab buttons
    local yOffset = -10
    for i, tabInfo in ipairs(tabs) do
        local tabButton = CreateFrame("Button", nil, tabContainer, "BackdropTemplate")
        tabButton:SetSize(96, 28)
        tabButton:SetPoint("TOP", tabContainer, "TOP", 0, yOffset)

        tabButton:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
        })
        tabButton:SetBackdropColor(0, 0, 0, 0)

        tabButton.text = tabButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabButton.text:SetPoint("LEFT", 10, 0)
        tabButton.text:SetText(tabInfo.name)
        tabButton.text:SetTextColor(unpack(self.colors.textDim))

        tabButton.highlight = tabButton:CreateTexture(nil, "HIGHLIGHT")
        tabButton.highlight:SetAllPoints()
        tabButton.highlight:SetColorTexture(0.2, 0.2, 0.2, 0.5)

        tabButton.selected = tabButton:CreateTexture(nil, "BACKGROUND")
        tabButton.selected:SetAllPoints()
        tabButton.selected:SetColorTexture(unpack(self.colors.accent))
        tabButton.selected:SetAlpha(0.2)
        tabButton.selected:Hide()

        tabButton.tabIndex = i
        tabButton.tabModule = tabInfo.module

        tabButton:SetScript("OnClick", function(self)
            UI:SelectTab(self.tabIndex)
        end)

        tabButton:SetScript("OnEnter", function(self)
            self.text:SetTextColor(unpack(UI.colors.text))
        end)

        tabButton:SetScript("OnLeave", function(self)
            if activeTab ~= self.tabIndex then
                self.text:SetTextColor(unpack(UI.colors.textDim))
            end
        end)

        tabs[i].button = tabButton
        yOffset = yOffset - 30
    end

    -- Content area (right side)
    local contentArea = CreateFrame("Frame", nil, configFrame)
    contentArea:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", 0, 0)
    contentArea:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMRIGHT", 0, 0)
    configFrame.contentArea = contentArea

    -- Create tab panels (lazy loaded)
    for i, tabInfo in ipairs(tabs) do
        local panel = CreateFrame("Frame", nil, contentArea)
        panel:SetAllPoints()
        panel:Hide()
        tabPanels[i] = panel
    end

    -- Select first tab by default
    self:SelectTab(1)

    return configFrame
end

-- Select a tab
function UI:SelectTab(index)
    -- Deselect previous tab
    if activeTab and tabs[activeTab] then
        tabs[activeTab].button.selected:Hide()
        tabs[activeTab].button.text:SetTextColor(unpack(self.colors.textDim))
        if tabPanels[activeTab] then
            tabPanels[activeTab]:Hide()
        end
    end

    -- Select new tab
    activeTab = index
    if tabs[index] then
        tabs[index].button.selected:Show()
        tabs[index].button.text:SetTextColor(unpack(self.colors.text))

        -- Load panel content if not already loaded
        local panel = tabPanels[index]
        if panel and not panel.loaded then
            self:LoadTabContent(index, panel)
            panel.loaded = true
        end

        if panel then
            panel:Show()
        end
    end
end

-- Load tab content (lazy loading)
function UI:LoadTabContent(index, panel)
    local tabInfo = tabs[index]
    if not tabInfo then return end

    -- Try to load from separate panel files
    local panelModule = self.Panels and self.Panels[tabInfo.module]
    if panelModule and panelModule.Create then
        panelModule:Create(panel)
    else
        -- Fallback: create placeholder
        local placeholder = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        placeholder:SetPoint("CENTER")
        placeholder:SetText(tabInfo.name .. " panel\n(Not yet implemented)")
        placeholder:SetTextColor(unpack(self.colors.textDim))
    end
end

-- Toggle config visibility
function UI:ToggleConfig()
    if not configFrame then
        self:CreateConfigFrame()
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
end

-- Show config
function UI:ShowConfig()
    if not configFrame then
        self:CreateConfigFrame()
    end
    configFrame:Show()
end

-- Hide config
function UI:HideConfig()
    if configFrame then
        configFrame:Hide()
    end
end

-- Check if config is open
function UI:IsConfigOpen()
    return configFrame and configFrame:IsShown()
end

-- Get config frame
function UI:GetConfigFrame()
    return configFrame
end

-- Select tab by name
function UI:SelectTabByName(name)
    for i, tabInfo in ipairs(tabs) do
        if tabInfo.name == name then
            self:SelectTab(i)
            return true
        end
    end
    return false
end

-- Config namespace for external access
UI.Config = {
    Show = function(self)
        UI:ShowConfig()
    end,
    Hide = function(self)
        UI:HideConfig()
    end,
    SelectTab = function(self, name)
        UI:SelectTabByName(name)
    end,
}

-- Initialize panels table
UI.Panels = UI.Panels or {}
