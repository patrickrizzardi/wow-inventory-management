--[[
    InventoryManager - UI/Panels/Whitelist.lua
    Whitelist (locked items) management panel

    Design Standard:
    - Feature card (amber) at top with description
    - Settings cards (dark) for grouped options
    - Tips section at bottom
    - All elements use dynamic width (TOPLEFT + RIGHT anchoring)
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.Whitelist = {}

local WhitelistPanel = UI.Panels.Whitelist

function WhitelistPanel:Create(parent)
    -- Create scroll frame for all content
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = 0

    -- ============================================================
    -- FEATURE CARD: Locked Items Overview
    -- ============================================================
    local featureCard = UI:CreateFeatureCard(content, yOffset, 85)

    local featureTitle = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureTitle:SetPoint("TOPLEFT", 10, -8)
    featureTitle:SetText(UI:ColorText("Locked Items (Whitelist)", "accent"))

    local featureDesc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    featureDesc:SetPoint("TOPLEFT", 10, -28)
    featureDesc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    featureDesc:SetJustifyH("LEFT")
    featureDesc:SetSpacing(2)
    featureDesc:SetText(
        "Locked items will never be auto-sold or posted to the Auction House.\n" ..
        "Alt+Click on any item in your bags to lock/unlock it."
    )
    featureDesc:SetTextColor(0.9, 0.9, 0.9)

    yOffset = yOffset - 95

    -- ============================================================
    -- SETTINGS CARD: Stats
    -- ============================================================
    local statsHeader = UI:CreateSectionHeader(content, "Statistics")
    statsHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    local statsCard = UI:CreateSettingsCard(content, yOffset, 40)

    local countLabel = statsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countLabel:SetPoint("TOPLEFT", statsCard, "TOPLEFT", 10, -10)
    countLabel:SetTextColor(unpack(UI.colors.text))

    local function UpdateCount()
        local count = IM:GetWhitelistCount()
        countLabel:SetText("Locked items: " .. count)
    end
    UpdateCount()

    yOffset = yOffset - 50

    -- ============================================================
    -- SETTINGS CARD: Locked Items List
    -- ============================================================
    local listHeader = UI:CreateSectionHeader(content, "Locked Items")
    listHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 24

    -- This card will be dynamically sized based on item count
    local listCard = UI:CreateSettingsCard(content, yOffset, 200)

    -- Create item list using shared builder
    local RefreshList, listContainer = UI:CreateItemListBuilder(
        listCard,
        IM.db.global.whitelist,
        "No locked items. Alt+Click items in your bags to lock them.",
        function(itemID)
            IM:RemoveFromWhitelist(itemID)
            local h = RefreshList()
            listCard:SetHeight(h + 70)
            UpdateCount()
            IM:RefreshAllUI()
        end
    )

    -- Clear button at bottom of list card
    local clearBtn = UI:CreateButton(listCard, "Clear All", 80, 24)
    clearBtn:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 10, -10)
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("INVENTORYMANAGER_CLEAR_WHITELIST")
    end)

    -- Initial list refresh and card sizing
    local listHeight = RefreshList()
    local initialCardHeight = listHeight + 70
    listCard:SetHeight(initialCardHeight)
    yOffset = yOffset - initialCardHeight - 10

    -- ============================================================
    -- TIPS SECTION
    -- ============================================================
    local tipsHeader = UI:CreateSectionHeader(content, "Tips")
    tipsHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    yOffset = yOffset - 22

    local tipsText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipsText:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yOffset)
    tipsText:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    tipsText:SetJustifyH("LEFT")
    tipsText:SetSpacing(2)
    tipsText:SetText(
        "|cffaaaaaa" ..
        "- Alt+Click on items in your bags to quickly lock/unlock them\n" ..
        "- Locked items show a lock icon overlay in your bags\n" ..
        "- Locking an item also protects it from AH posting\n" ..
        "|r"
    )

    yOffset = yOffset - 60

    -- Set content height
    content:SetHeight(math.abs(yOffset) + 20)

    -- Auto-refresh when panel is shown
    parent:SetScript("OnShow", function()
        local h = RefreshList()
        listCard:SetHeight(h + 70)
    end)

    -- Auto-refresh when whitelist changes (Alt+Click in bags)
    IM:RegisterWhitelistCallback(function(itemID, added)
        if parent:IsVisible() then
            local h = RefreshList()
            listCard:SetHeight(h + 70)
        end
    end)

    -- Initial refresh
    C_Timer.After(0.1, RefreshList)

    -- Clear confirmation popup
    StaticPopupDialogs["INVENTORYMANAGER_CLEAR_WHITELIST"] = {
        text = "Are you sure you want to remove all locked items?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if IM.modules.ItemLock then
                IM.modules.ItemLock:ClearAllLocks()
            end
            RefreshList()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end
