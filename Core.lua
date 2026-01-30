--[[
    InventoryManager - Core.lua
    Main addon initialization and event dispatch system
]]

-- Create addon namespace
local addonName, IM = ...

-- Make namespace globally accessible for debugging
_G.InventoryManager = IM

-- Addon version
IM.version = "1.3.1"

-- Show welcome message on first load
IM.showWelcomeMessage = true

-- Secure interaction tracking (global, accessible to all modules)
IM.secureInteraction = {
    active = false,
    type = nil,
    types = {
        [53] = "ItemUpgrade",
        [10] = "Banker",
        [17] = "GuildBanker",
        [21] = "Auctioneer",
        [26] = "Transmogrifier",
    }
}

-- Module registry
IM.modules = {}

-- Event frame for handling WoW events
IM.eventFrame = CreateFrame("Frame")
IM.eventFrame:Hide()

-- Event handlers table
local eventHandlers = {}

-- Debug log buffer
local _debugLog = {}
local _debugLogMax = 500
local function _FormatArgs(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    return table.concat(parts, " ")
end
local function _AddDebugLogLine(message)
    if not message then return end
    table.insert(_debugLog, message)
    if #_debugLog > _debugLogMax then
        table.remove(_debugLog, 1)
    end
end

-- Register an event handler
function IM:RegisterEvent(event, handler)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        IM.eventFrame:RegisterEvent(event)
    end
    table.insert(eventHandlers[event], handler)
end

-- Unregister a specific handler for an event
function IM:UnregisterEvent(event, handler)
    if not eventHandlers[event] then return end

    for i, h in ipairs(eventHandlers[event]) do
        if h == handler then
            table.remove(eventHandlers[event], i)
            break
        end
    end

    -- Unregister event if no handlers left
    if #eventHandlers[event] == 0 then
        eventHandlers[event] = nil
        IM.eventFrame:UnregisterEvent(event)
    end
end

-- Event dispatcher
IM.eventFrame:SetScript("OnEvent", function(self, event, ...)
    if eventHandlers[event] then
        for _, handler in ipairs(eventHandlers[event]) do
            handler(event, ...)
        end
    end
end)

-- Module registration system
function IM:RegisterModule(name, module)
    if self.modules[name] then
        self:Print("Warning: Module '" .. name .. "' already registered, overwriting")
    end
    self.modules[name] = module

    -- Call module's OnInitialize if it exists
    if module.OnInitialize then
        module:OnInitialize()
    end
end

-- Show welcome message on first login (only once per session)
local welcomeShown = false
IM:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if not welcomeShown and IM.showWelcomeMessage then
        C_Timer.After(2, function()
            IM:Print("|cffffb000Welcome!|r Type |cffffb000/im|r to open settings")
            IM:Print("Version " .. IM.version .. " loaded successfully")
        end)
        welcomeShown = true
    end
end)

-- Track secure interactions globally (helps debug taint issues)
IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(event, interactionType)
    local typeName = IM.secureInteraction.types[interactionType]
    if typeName then
        IM.secureInteraction.active = true
        IM.secureInteraction.type = interactionType
        IM:Debug("[Core] SECURE INTERACTION START: " .. typeName .. " (type " .. interactionType .. ")")
    end
end)

IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(event, interactionType)
    local typeName = IM.secureInteraction.types[interactionType]
    if typeName then
        IM:Debug("[Core] SECURE INTERACTION END: " .. typeName .. " (type " .. interactionType .. ")")
        IM.secureInteraction.active = false
        IM.secureInteraction.type = nil
    end
end)

-- Helper to check if secure interaction is active (for other modules)
function IM:IsSecureInteractionActive()
    return self.secureInteraction.active
end

-- Get a registered module
function IM:GetModule(name)
    return self.modules[name]
end

-- Print to chat with addon prefix (golden/cheddar theme)
function IM:Print(...)
    local prefix = "|cffffb000[InventoryManager]|r "
    print(prefix, ...)
    local timestamp = date("%H:%M:%S")
    _AddDebugLogLine(string.format("[%s] %s", timestamp, _FormatArgs(...)))
end

-- Print error message
function IM:PrintError(...)
    local prefix = "|cffe64d4d[InventoryManager Error]|r "
    print(prefix, ...)
    local timestamp = date("%H:%M:%S")
    _AddDebugLogLine(string.format("[%s] ERROR: %s", timestamp, _FormatArgs(...)))
end

-- Print warning message (uses accent color)
function IM:PrintWarning(...)
    local prefix = "|cffffb000[InventoryManager]|r "
    print(prefix, ...)
    local timestamp = date("%H:%M:%S")
    _AddDebugLogLine(string.format("[%s] WARN: %s", timestamp, _FormatArgs(...)))
end

-- Print debug message (only if debug mode enabled)
function IM:Debug(...)
    if self.db and self.db.global and self.db.global.debug then
        local prefix = "|cff888888[IM Debug]|r "
        print(prefix, ...)
        local timestamp = date("%H:%M:%S")
        _AddDebugLogLine(string.format("[%s] DEBUG: %s", timestamp, _FormatArgs(...)))
    end
end

function IM:GetDebugLogString()
    if #_debugLog == 0 then
        return "No debug logs captured."
    end
    return table.concat(_debugLog, "\n")
end

-- Create popup dialogs for warnings/errors
StaticPopupDialogs["INVENTORYMANAGER_WARNING"] = {
    text = "%s",
    button1 = "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnShow = function(self)
        -- Yellow warning color for text
        if self.Text then
            self.Text:SetTextColor(1, 0.8, 0)
        end
    end,
    OnHide = function(self)
        if self.Text then
            self.Text:SetTextColor(1, 1, 1)
        end
    end,
}

StaticPopupDialogs["INVENTORYMANAGER_ERROR"] = {
    text = "%s",
    button1 = "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnShow = function(self)
        -- Red error color for text
        if self.Text then
            self.Text:SetTextColor(1, 0.3, 0.3)
        end
    end,
    OnHide = function(self)
        if self.Text then
            self.Text:SetTextColor(1, 1, 1)
        end
    end,
}

StaticPopupDialogs["INVENTORYMANAGER_INFO"] = {
    text = "%s",
    button1 = "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        -- Green info color
        if self.Text then
            self.Text:SetTextColor(0.5, 1, 0.5)
        end
    end,
    OnHide = function(self)
        if self.Text then
            self.Text:SetTextColor(1, 1, 1)
        end
    end,
}

-- Show a warning popup
function IM:ShowWarning(text)
    StaticPopup_Show("INVENTORYMANAGER_WARNING", text)
end

-- Show an error popup
function IM:ShowError(text)
    StaticPopup_Show("INVENTORYMANAGER_ERROR", text)
end

-- Show an info popup
function IM:ShowInfo(text)
    StaticPopup_Show("INVENTORYMANAGER_INFO", text)
end

-- Format gold amount (copper to readable string)
-- Format number with commas (e.g., 1234567 -> "1,234,567")
function IM:FormatNumber(num)
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

function IM:FormatMoney(copper)
    if not copper or copper == 0 then return "0c" end

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRemaining = copper % 100

    local result = ""
    if gold > 0 then
        result = result .. "|cffffd700" .. self:FormatNumber(gold) .. "g|r "
    end
    if silver > 0 or gold > 0 then
        result = result .. "|cffc7c7cf" .. silver .. "s|r "
    end
    result = result .. "|cffeda55f" .. copperRemaining .. "c|r"

    return result
end

-- Item quality colors
IM.qualityColors = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, -- Poor (gray)
    [1] = { r = 1.00, g = 1.00, b = 1.00 }, -- Common (white)
    [2] = { r = 0.12, g = 1.00, b = 0.00 }, -- Uncommon (green)
    [3] = { r = 0.00, g = 0.44, b = 0.87 }, -- Rare (blue)
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, -- Epic (purple)
    [5] = { r = 1.00, g = 0.50, b = 0.00 }, -- Legendary (orange)
    [6] = { r = 0.90, g = 0.80, b = 0.50 }, -- Artifact (gold)
    [7] = { r = 0.00, g = 0.80, b = 1.00 }, -- Heirloom (light blue)
    [8] = { r = 0.00, g = 0.80, b = 1.00 }, -- WoW Token
}

-- Get quality color as hex string
function IM:GetQualityColorHex(quality)
    local color = self.qualityColors[quality] or self.qualityColors[1]
    return string.format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
end

-- Item bind types (from LE_ITEM_BIND)
IM.BIND_NONE = 0
IM.BIND_ON_ACQUIRE = 1  -- BoP
IM.BIND_ON_EQUIP = 2    -- BoE
IM.BIND_ON_USE = 3      -- BoU
IM.BIND_QUEST = 4       -- Quest item

-- Quality thresholds
IM.QUALITY_POOR = 0      -- Gray
IM.QUALITY_COMMON = 1    -- White
IM.QUALITY_UNCOMMON = 2  -- Green
IM.QUALITY_RARE = 3      -- Blue
IM.QUALITY_EPIC = 4      -- Purple
IM.QUALITY_LEGENDARY = 5 -- Orange
IM.QUALITY_ARTIFACT = 6  -- Gold
IM.QUALITY_HEIRLOOM = 7  -- Light blue

-- Initialize addon on ADDON_LOADED
IM:RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
    if loadedAddon ~= addonName then return end

    -- Initialize database
    if IM.InitializeDatabase then
        IM:InitializeDatabase()
    end

    -- Initialize all registered modules that have OnEnable
    for name, module in pairs(IM.modules) do
        if module.OnEnable then
            module:OnEnable()
        end
    end

    -- Register with Blizzard Settings (AddOns menu)
    if IM.RegisterBlizzardSettings then
        IM:RegisterBlizzardSettings()
    end

    -- Show first-time welcome message with keybind hints
    if not IM.db.global.hasSeenWelcome then
        IM.db.global.hasSeenWelcome = true
        C_Timer.After(3, function()
            IM:Print("|cff00ff00Welcome to InventoryManager!|r")
            IM:Print("Quick tips:")
            IM:Print("  |cffffb000Alt+Click|r any item to lock/protect it")
            IM:Print("  |cffffb000Ctrl+Alt+Click|r to mark as junk (force sell)")
            IM:Print("  |cffffb000/im|r for settings | |cffffb000/im dashboard|r for gold tracking")
        end)
    end

    -- Unregister ADDON_LOADED after initialization
    local handlers = eventHandlers["ADDON_LOADED"]
    if handlers and handlers[1] then
        IM:UnregisterEvent("ADDON_LOADED", handlers[1])
    end
end)

-- Slash command handler
SLASH_INVENTORYMANAGER1 = "/im"
SLASH_INVENTORYMANAGER2 = "/inventorymanager"

SlashCmdList["INVENTORYMANAGER"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word:lower())
    end

    local cmd = args[1]

    if not cmd or cmd == "" then
        -- Show help + open config panel for discoverability
        IM:Print("|cff00ff00InventoryManager|r - Quick Commands:")
        IM:Print("  |cff888888Alt+Click|r item = Lock/unlock | |cff888888Ctrl+Alt+Click|r = Mark junk")
        IM:Print("  |cff888888/im sell|r | |cff888888/im repair|r | |cff888888/im help|r for all commands")
        if IM.UI and IM.UI.ToggleConfig then
            IM.UI:ToggleConfig()
        else
            IM:Print("Config panel not yet loaded")
        end
    elseif cmd == "dashboard" or cmd == "d" then
        -- Open standalone dashboard
        if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Toggle then
            IM.UI.Dashboard:Toggle()
        else
            IM:Print("Dashboard not yet loaded")
        end
    elseif cmd == "inventory" or cmd == "inv" then
        -- Open dashboard to Inventory tab
        if IM.UI and IM.UI.Dashboard then
            IM.UI.Dashboard:Show()
            C_Timer.After(0.1, function()
                if _G["InventoryManagerDashboard"] and _G["InventoryManagerDashboard"].SelectTab then
                    _G["InventoryManagerDashboard"].SelectTab("inventory")
                end
            end)
        else
            IM:Print("Dashboard not yet loaded")
        end
    elseif cmd == "config" or cmd == "options" then
        -- Open config panel (silent, for power users)
        if IM.UI and IM.UI.ToggleConfig then
            IM.UI:ToggleConfig()
        else
            IM:Print("Config panel not yet loaded")
        end
    elseif cmd == "sell" then
        -- Manual trigger auto-sell (if at vendor)
        if IM.modules.AutoSell and IM.modules.AutoSell.SellJunk then
            IM.modules.AutoSell:SellJunk()
        else
            IM:Print("AutoSell module not loaded")
        end
    elseif cmd == "repair" then
        -- Manual trigger repair
        if IM.modules.AutoRepair and IM.modules.AutoRepair.Repair then
            IM.modules.AutoRepair:Repair()
        else
            IM:Print("AutoRepair module not loaded")
        end
    elseif cmd == "lock" then
        -- Toggle lock on currently hovered item
        local itemID = select(2, GameTooltip:GetItem())
        if itemID then
            local isLocked = IM:ToggleWhitelist(itemID)
            local itemName = GetItemInfo(itemID)
            if isLocked then
                IM:Print("Locked: " .. (itemName or itemID))
            else
                IM:Print("Unlocked: " .. (itemName or itemID))
            end
        else
            IM:Print("Hover over an item to lock/unlock it")
        end
    elseif cmd == "junk" then
        -- Toggle junk on currently hovered item
        local itemID = select(2, GameTooltip:GetItem())
        if itemID then
            local isJunk = IM:ToggleJunkList(itemID)
            local itemName = GetItemInfo(itemID)
            if isJunk then
                IM:Print("Marked as junk: " .. (itemName or itemID))
            else
                IM:Print("Removed from junk: " .. (itemName or itemID))
            end
        else
            IM:Print("Hover over an item to mark/unmark as junk")
        end
    elseif cmd == "status" then
        -- Show addon status
        IM:Print("Status:")
        IM:Print("  Auto-Sell: " .. (IM.db.global.autoSellEnabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        IM:Print("  Auto-Repair: " .. (IM.db.global.autoRepairEnabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

        if IM.Filters then
            local sellCount, sellValue = IM.Filters:GetAutoSellCount()
            IM:Print("  Sellable items: " .. sellCount .. " (" .. IM:FormatMoney(sellValue) .. ")")
        end

        IM:Print("  Whitelisted items: " .. (IM.db and IM:GetWhitelistCount() or 0))
        IM:Print("  Junk list items: " .. (IM.db and IM:GetJunkListCount() or 0))
    elseif cmd == "reset" then
        -- Reset database
        local section = args[2]
        if section then
            -- Valid sections for reset
            local validSections = {
                autoSell = true,
                repair = true,
                categoryExclusions = true,
                whitelist = true,
                junkList = true,
                sellHistory = true,
                ui = true,
            }
            if validSections[section] then
                IM:ResetSection(section)
            else
                IM:Print("Invalid section: " .. section)
                IM:Print("Valid sections: autoSell, repair, categoryExclusions, whitelist, junkList, sellHistory, ui")
            end
        else
            StaticPopup_Show("INVENTORYMANAGER_RESET_CONFIRM")
        end
    elseif cmd == "debug" then
        -- Toggle debug mode
        IM.db.global.debug = not IM.db.global.debug
        IM:Print("Debug mode: " .. (IM.db.global.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    elseif cmd == "test" then
        -- Test commands for debugging
        local testType = args[2]
        if testType == "loot" then
            -- Simulate a loot entry (uses Hearthstone as test item)
            local testItemID = 6948 -- Hearthstone
            local testItemLink = "|cffffffff|Hitem:6948::::::::1:::::|h[Hearthstone]|h|r"
            IM:AddLootHistoryEntry(testItemID, testItemLink, 1, "Test")
            IM:Print("Test loot entry added: " .. testItemLink)
            IM:Print("Check /im -> History tab to verify")
        elseif testType == "sell" then
            -- Simulate a sell entry
            local testItemID = 6948
            local testItemLink = "|cffffffff|Hitem:6948::::::::1:::::|h[Hearthstone]|h|r"
            IM:AddSellHistoryEntry(testItemID, testItemLink, 1, 100)
            IM:Print("Test sell entry added: " .. testItemLink .. " for 1c")
        else
            IM:Print("Test commands:")
            IM:Print("  /im test loot - Add test loot entry")
            IM:Print("  /im test sell - Add test sell entry")
        end
    elseif cmd == "minimap" then
        -- Toggle minimap button
        if IM.UI and IM.UI.MinimapButton then
            IM.UI.MinimapButton:Toggle()
            local isShown = IM.UI.MinimapButton:IsShown()
            IM:Print("Minimap button: " .. (isShown and "|cff00ff00shown|r" or "|cffff0000hidden|r"))
        else
            IM:Print("MinimapButton module not loaded")
        end
    elseif cmd == "bags" or cmd == "bag" then
        -- Toggle custom bag UI
        if IM.UI and IM.UI.BagUI then
            local otherAddon = IM.UI.BagUI:GetDetectedBagAddon()
            if otherAddon then
                IM:Print("|cffffaa00Note: " .. otherAddon .. " is active - may conflict|r")
            end
            IM.UI.BagUI:Toggle()
        else
            IM:Print("BagUI module not loaded")
        end
    elseif cmd == "bagdiag" then
        -- Run bag integration diagnostics
        if IM.UI and IM.UI.BagIntegration then
            IM.UI.BagIntegration:RunDiagnostics()
        else
            IM:Print("BagIntegration module not loaded")
        end
    elseif cmd == "refresh" then
        -- Force refresh all bag overlays
        IM:RefreshBagOverlays()
        IM:Print("Bag overlays refreshed")
    elseif cmd == "help" then
        IM:Print("Commands:")
        IM:Print("  /im - Open settings panel")
        IM:Print("  /im d or /im dashboard - Open dashboard")
        IM:Print("  /im inv or /im inventory - Search inventory")
        IM:Print("  /im bags - Toggle custom bag UI")
        IM:Print("  /im sell - Trigger auto-sell (at vendor)")
        IM:Print("  /im repair - Trigger repair (at vendor)")
        IM:Print("  /im lock - Lock/unlock hovered item")
        IM:Print("  /im junk - Mark/unmark hovered item as junk")
        IM:Print("  /im status - Show addon status")
        IM:Print("  /im reset [section] - Reset settings")
        IM:Print("  /im minimap - Toggle minimap button")
        IM:Print("  /im bagdiag - Run bag addon diagnostics")
        IM:Print("  /im refresh - Force refresh bag overlays")
        IM:Print("  /im debug - Toggle debug mode")
        IM:Print("  /im test [type] - Test logging system")
    else
        IM:Print("Unknown command: " .. cmd .. ". Type /im help for commands.")
    end
end

-- Helper functions for status command
function IM:GetWhitelistCount()
    local count = 0
    for _ in pairs(self.db.global.whitelist) do
        count = count + 1
    end
    return count
end

function IM:GetJunkListCount()
    local count = 0
    for _ in pairs(self.db.global.junkList) do
        count = count + 1
    end
    return count
end

-- Confirmation popup for reset
StaticPopupDialogs["INVENTORYMANAGER_RESET_CONFIRM"] = {
    text = "Are you sure you want to reset all InventoryManager settings?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        IM:ResetDatabase()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Register with Blizzard's Settings API (AddOns menu in Options)
function IM:RegisterBlizzardSettings()
    -- Create a settings panel with actual content
    local panel = CreateFrame("Frame")
    panel:SetSize(600, 400)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cffE6B800InventoryManager|r")

    -- Version
    local version = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    version:SetText("Version " .. (self.version or "1.0"))
    version:SetTextColor(0.7, 0.7, 0.7)

    -- Description
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -16)
    desc:SetWidth(550)
    desc:SetJustifyH("LEFT")
    desc:SetText("InventoryManager helps you organize your bags, auto-sell junk items, track your net worth, and manage mail rules.")
    desc:SetTextColor(1, 1, 1)

    -- Open settings button
    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(180, 30)
    openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    openBtn:SetText("Open Full Settings")
    openBtn:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        C_Timer.After(0.01, function()
            if IM.UI and IM.UI.Config and IM.UI.Config.Show then
                IM.UI.Config:Show()
            end
        end)
    end)

    -- Slash command info
    local slashInfo = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slashInfo:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -20)
    slashInfo:SetText("You can also use |cffE6B800/im|r to open settings at any time.")
    slashInfo:SetTextColor(0.7, 0.7, 0.7)

    -- Register the category
    local category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
    category.ID = addonName
    Settings.RegisterAddOnCategory(category)

    -- Store reference
    self.settingsCategory = category
end

-- Open addon settings via Blizzard menu
function IM:OpenSettings()
    if self.UI and self.UI.Config and self.UI.Config.Show then
        self.UI.Config:Show()
    end
end

-- Centralized UI refresh function
-- Call this when settings change to update all visible UI elements
function IM:RefreshAllUI()
    -- Bag overlays
    if self.RefreshBagOverlays then
        self:RefreshBagOverlays()
    end

    -- IM Bag UI (if visible)
    if self.UI and self.UI.BagUI and self.UI.BagUI.IsShown and self.UI.BagUI:IsShown() then
        self.UI.BagUI:Refresh()
    end

    -- AutoSell popup (if visible)
    if self.UI and self.UI.AutoSellPopup and self.UI.AutoSellPopup.IsShown and self.UI.AutoSellPopup:IsShown() then
        self.UI.AutoSellPopup:Refresh()
    end

    -- Mail popup (if visible)
    if self.UI and self.UI.MailPopup and self.UI.MailPopup.IsShown and self.UI.MailPopup:IsShown() then
        self.UI.MailPopup:Refresh()
    end

    -- Dashboard (if visible)
    if self.UI and self.UI.Dashboard and self.UI.Dashboard.IsShown and self.UI.Dashboard:IsShown() then
        self.UI.Dashboard:RefreshContent()
    end

    -- AutoSell panel stats
    if self.UI and self.UI.Panels and self.UI.Panels.AutoSell and self.UI.Panels.AutoSell.UpdateStats then
        self.UI.Panels.AutoSell.UpdateStats()
    end
end

-- ============================================================
-- SHARED PARSING UTILITIES
-- ============================================================

-- Extract copper value from chat messages (e.g., "You loot 5 gold 23 silver 10 copper")
-- @param message: Chat message string
-- @return totalCopper: Total value in copper, or 0 if not found
function IM:ParseMoneyFromMessage(message)
    if not message then return 0 end

    local gold = tonumber(message:match("(%d+) gold")) or 0
    local silver = tonumber(message:match("(%d+) silver")) or 0
    local copper = tonumber(message:match("(%d+) copper")) or 0

    return gold * 10000 + silver * 100 + copper
end

-- Extract item link from chat message
-- Handles both full colored links and bare links
-- @param message: Chat message string
-- @return itemLink: Item link string, or nil if not found
function IM:ExtractItemLinkFromMessage(message)
    if not message then return nil end

    -- Try full colored link first (|c color code + item link)
    local itemLink = message:match("|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r")
    if itemLink then
        return itemLink
    end

    -- Try bare item link (no color code)
    itemLink = message:match("|Hitem:[^|]+|h%[[^%]]+%]|h")
    if itemLink then
        return itemLink
    end

    return nil
end

-- Expose namespace to other files
InventoryManager = IM 