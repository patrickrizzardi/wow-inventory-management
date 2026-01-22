--[[
    InventoryManager - UI/Panels/Selling.lua
    Combined selling settings with internal sub-tabs.
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Selling = {}

local SellingPanel = UI.Panels.Selling

local subTabs = {
    { name = "Auto-Sell", module = "AutoSell" },
    { name = "Protections", module = "Categories" },
    { name = "Whitelist", module = "Whitelist" },
    { name = "Junk List", module = "JunkList" },
}

local function _CreateTabButton(parent, name, index)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(90, 24)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    button:SetBackdropColor(0.1, 0.1, 0.1, 1)

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("CENTER")
    button.text:SetText(name)
    button.text:SetTextColor(unpack(UI.colors.textDim))

    button.selected = button:CreateTexture(nil, "BACKGROUND")
    button.selected:SetAllPoints()
    button.selected:SetColorTexture(unpack(UI.colors.accent))
    button.selected:SetAlpha(0.2)
    button.selected:Hide()

    button.tabIndex = index

    button:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(UI.colors.text))
    end)

    button:SetScript("OnLeave", function(self)
        if parent.activeTab ~= self.tabIndex then
            self.text:SetTextColor(unpack(UI.colors.textDim))
        end
    end)

    return button
end

function SellingPanel:Create(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    local tabBar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    tabBar:SetHeight(30)
    tabBar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    tabBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    tabBar:SetBackdropColor(0.08, 0.08, 0.08, 1)

    local contentArea = CreateFrame("Frame", nil, container)
    contentArea:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
    contentArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

    container.tabButtons = {}
    container.subPanels = {}
    container.activeTab = nil

    for i, info in ipairs(subTabs) do
        local button = _CreateTabButton(tabBar, info.name, i)

        button:SetScript("OnClick", function(self)
            SellingPanel:SelectSubTab(container, self.tabIndex)
        end)

        container.tabButtons[i] = button

        local panel = CreateFrame("Frame", nil, contentArea)
        panel:SetAllPoints()
        panel:Hide()
        container.subPanels[i] = panel
    end

    local function layoutTabs()
        local width = tabBar:GetWidth() or 0
        if width <= 0 then
            return
        end

        local padding = 8
        local spacing = 6
        local count = #container.tabButtons
        local available = width - (padding * 2) - (spacing * (count - 1))
        local buttonWidth = math.max(70, math.floor(available / count))

        local xOffset = padding
        for _, button in ipairs(container.tabButtons) do
            button:ClearAllPoints()
            button:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
            button:SetWidth(buttonWidth)
            xOffset = xOffset + buttonWidth + spacing
        end
    end

    tabBar:SetScript("OnSizeChanged", function()
        layoutTabs()
    end)

    C_Timer.After(0, layoutTabs)

    SellingPanel:SelectSubTab(container, 1)
    self._container = container
end

function SellingPanel:SelectSubTab(container, index)
    if not container or not container.subPanels then return end

    if container.activeTab and container.tabButtons[container.activeTab] then
        local prevBtn = container.tabButtons[container.activeTab]
        prevBtn.selected:Hide()
        prevBtn.text:SetTextColor(unpack(UI.colors.textDim))
        container.subPanels[container.activeTab]:Hide()
    end

    container.activeTab = index
    local btn = container.tabButtons[index]
    local panel = container.subPanels[index]
    local info = subTabs[index]

    if btn then
        btn.selected:Show()
        btn.text:SetTextColor(unpack(UI.colors.text))
    end

    if panel then
        if not panel.loaded then
            local panelModule = UI.Panels and UI.Panels[info.module]
            if panelModule and panelModule.Create then
                panelModule:Create(panel)
            end
            panel.loaded = true
        end
        panel:Show()
    end
end

function SellingPanel:SelectSubTabByName(name)
    if not self._container then return false end
    for i, info in ipairs(subTabs) do
        if info.name == name then
            self:SelectSubTab(self._container, i)
            return true
        end
    end
    return false
end
