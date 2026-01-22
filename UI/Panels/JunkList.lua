--[[
    InventoryManager - UI/Panels/JunkList.lua
    Junk list management panel
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.JunkList = {}

local JunkListPanel = UI.Panels.JunkList

function JunkListPanel:Create(parent)
    -- Create scroll frame using the standard panel factory
    local scrollFrame, content = UI:CreateScrollPanel(parent)
    local yOffset = -10

    -- Feature Card (amber tint)
    local featureCard = UI:CreateFeatureCard(content, yOffset, 90)
    local featureY = -10

    local title = UI:CreateSectionHeader(featureCard, "Junk List")
    title:SetPoint("TOPLEFT", featureCard, "TOPLEFT", 10, featureY)
    featureY = featureY - 25

    local desc = featureCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", featureCard, "TOPLEFT", 10, featureY)
    desc:SetPoint("RIGHT", featureCard, "RIGHT", -10, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Items on the junk list will always be auto-sold, regardless of quality or value.\n\nCtrl+Alt+Click on any item to add/remove from junk list.")
    desc:SetTextColor(unpack(UI.colors.textDim))

    yOffset = yOffset - 100

    -- Stats Card (dark)
    local statsCard = UI:CreateSettingsCard(content, yOffset, 40)
    local statsY = -10

    local countLabel = statsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countLabel:SetPoint("TOPLEFT", statsCard, "TOPLEFT", 10, statsY)
    countLabel:SetTextColor(unpack(UI.colors.text))

    local function UpdateCount()
        local count = IM:GetJunkListCount()
        countLabel:SetText("Junk items: " .. count)
    end
    UpdateCount()

    yOffset = yOffset - 50

    -- Junk Items List Card (dark, dynamic height)
    local listCard = UI:CreateSettingsCard(content, yOffset, 200)
    local listY = -10

    local listHeader = UI:CreateSectionHeader(listCard, "Junk Items")
    listHeader:SetPoint("TOPLEFT", listCard, "TOPLEFT", 10, listY)
    listY = listY - 30

    -- Create item list using shared builder
    local RefreshList, listContainer = UI:CreateItemListBuilder(
        listCard,
        IM.db.global.junkList,
        "No junk items. Ctrl+Alt+Click items in your bags to add them.",
        function(itemID)
            IM:RemoveFromJunkList(itemID)
            local h = RefreshList()
            local cardHeight = 40 + math.max(h, 50) + 50 -- header + list + clear button
            listCard:SetHeight(cardHeight)
            content:SetHeight(math.abs(yOffset) + cardHeight + 100)
            UpdateCount()
            IM:RefreshAllUI()
        end
    )

    -- Position the list container after the header
    listContainer:SetPoint("TOPLEFT", listCard, "TOPLEFT", 0, listY)

    listY = listY - 10 -- Space after list container (will be dynamic)

    -- Clear button at bottom of list card
    local clearBtn = UI:CreateButton(listCard, "Clear All", 80, 24)
    clearBtn:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 10, -10)
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("INVENTORYMANAGER_CLEAR_JUNKLIST")
    end)

    yOffset = yOffset - 210 -- Initial estimate, will be updated by RefreshList

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
        "- Use Ctrl+Alt+Click on items in your bags to add to junk list\n" ..
        "- Junk items will be auto-sold regardless of quality or value\n" ..
        "- Use this for items you never want to keep\n" ..
        "|r"
    )

    yOffset = yOffset - 60

    -- Auto-refresh when panel is shown
    parent:SetScript("OnShow", function()
        RefreshList()
    end)

    -- Auto-refresh when junk list changes (Ctrl+Alt+Click in bags)
    IM:RegisterJunkListCallback(function(itemID, added)
        if parent:IsVisible() then
            RefreshList()
        end
    end)

    -- Initial refresh
    C_Timer.After(0.1, RefreshList)

    -- Clear confirmation popup
    StaticPopupDialogs["INVENTORYMANAGER_CLEAR_JUNKLIST"] = {
        text = "Are you sure you want to clear the junk list?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if IM.modules.JunkList then
                IM.modules.JunkList:ClearAllJunk()
            end
            RefreshList()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    -- Set final content height
    content:SetHeight(math.abs(yOffset) + 20)
end
