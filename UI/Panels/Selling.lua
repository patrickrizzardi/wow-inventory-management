--[[
    InventoryManager - UI/Panels/Selling.lua
    Combined selling settings with internal sub-tabs.
    Uses the reusable UI:CreateTabBar component for consistency.
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Selling = {}

local SellingPanel = UI.Panels.Selling

-- Tab configuration
local subTabs = {
    { id = "autosell", label = "Auto-Sell", module = "AutoSell" },
    { id = "protections", label = "Protections", module = "Categories" },
    { id = "whitelist", label = "Whitelist", module = "Whitelist" },
    { id = "junklist", label = "Junk List", module = "JunkList" },
}

function SellingPanel:Create(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    -- Create content panels for each tab
    local contentArea = CreateFrame("Frame", nil, container)
    local subPanels = {}

    for i, info in ipairs(subTabs) do
        local panel = CreateFrame("Frame", nil, contentArea)
        panel:SetAllPoints()
        panel:Hide()
        panel.module = info.module
        subPanels[info.id] = panel
    end

    -- Create tab bar using reusable component
    local tabBar, selectTab = UI:CreateTabBar(container, {
        tabs = subTabs,
        height = 30,
        onSelect = function(tabId)
            -- Hide all panels
            for id, panel in pairs(subPanels) do
                panel:Hide()
            end
            -- Show selected panel
            local panel = subPanels[tabId]
            if panel then
                -- Lazy-load panel content
                if not panel.loaded then
                    local panelModule = UI.Panels and UI.Panels[panel.module]
                    if panelModule and panelModule.Create then
                        panelModule:Create(panel)
                    end
                    panel.loaded = true
                end
                panel:Show()
            end
        end,
    })

    -- Position tab bar
    tabBar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    -- Position content area below tab bar
    contentArea:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
    contentArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

    -- Store references
    container.tabBar = tabBar
    container.subPanels = subPanels
    container.selectTab = selectTab

    -- Select first tab
    selectTab(subTabs[1].id)

    self._container = container
end

function SellingPanel:SelectSubTabByName(name)
    if not self._container then return false end
    for _, info in ipairs(subTabs) do
        if info.label == name then
            self._container.selectTab(info.id)
            return true
        end
    end
    return false
end
