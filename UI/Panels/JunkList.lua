--[[
    InventoryManager - UI/Panels/JunkList.lua
    Junk list management panel
    Uses DRY components: CreateSettingsContainer, CreateCard
]]

local addonName, IM = ...
local UI = IM.UI

UI.Panels = UI.Panels or {}
UI.Panels.JunkList = {}

local JunkListPanel = UI.Panels.JunkList

function JunkListPanel:Create(parent)
    local scrollFrame, content = UI:CreateSettingsContainer(parent)

    -- ============================================================
    -- JUNK LIST OVERVIEW CARD
    -- ============================================================
    local mainCard = UI:CreateCard(content, {
        title = "Junk List",
        description = "Items on the junk list will always be auto-sold, regardless of quality or value.",
    })

    mainCard:AddText("Ctrl+Alt+Click on any item to add/remove from junk list.")

    -- Stats display
    local statsY = mainCard:AddContent(24)
    local countLabel = mainCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countLabel:SetPoint("TOPLEFT", mainCard, "TOPLEFT", mainCard._leftPadding, statsY)
    countLabel:SetTextColor(unpack(UI.colors.text))

    local function UpdateCount()
        local count = IM:GetJunkListCount()
        countLabel:SetText("Junk items: |cffffd700" .. count .. "|r")
    end
    UpdateCount()

    content:AdvanceY(mainCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- JUNK ITEMS LIST CARD
    -- ============================================================
    local listCard = UI:CreateCard(content, {
        title = "Junk Items",
    })

    -- List container (inside card)
    local listContainer = CreateFrame("Frame", nil, listCard)
    listContainer:SetPoint("TOPLEFT", listCard, "TOPLEFT", listCard._leftPadding, -listCard._contentHeight - 4)
    listContainer:SetPoint("RIGHT", listCard, "RIGHT", -listCard._padding, 0)
    listContainer:SetHeight(UI.layout.listInitialHeight)

    local noItemsLabel = listContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noItemsLabel:SetPoint("TOPLEFT", 0, 0)
    noItemsLabel:SetText("|cff888888No junk items. Ctrl+Alt+Click items in your bags to add them.|r")
    noItemsLabel:Hide()

    local RefreshList

    local function CreateItemRow(parentContainer, itemID, yOffset, onRemove)
        local row = CreateFrame("Frame", nil, parentContainer, "BackdropTemplate")
        row:SetHeight(UI.layout.rowHeight)
        row:SetPoint("TOPLEFT", 0, yOffset)
        row:SetPoint("RIGHT", parentContainer, "RIGHT", 0, 0)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = UI.layout.borderSize,
        })
        row:SetBackdropColor(0.12, 0.12, 0.12, 1)
        row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

        -- Item icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(UI.layout.buttonHeightSmall, UI.layout.buttonHeightSmall)
        icon:SetPoint("LEFT", 4, 0)

        -- Item name
        local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLabel:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        nameLabel:SetPoint("RIGHT", row, "RIGHT", -30, 0)
        nameLabel:SetJustifyH("LEFT")
        nameLabel:SetWordWrap(false)

        -- Load item info
        local item = Item:CreateFromItemID(itemID)
        item:ContinueOnItemLoad(function()
            local name = item:GetItemName()
            local quality = item:GetItemQuality()
            local iconTexture = item:GetItemIcon()
            
            icon:SetTexture(iconTexture)
            if quality and ITEM_QUALITY_COLORS[quality] then
                local color = ITEM_QUALITY_COLORS[quality]
                nameLabel:SetText(color.hex .. name .. "|r")
            else
                nameLabel:SetText(name or "Loading...")
            end
        end)

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        removeBtn:SetSize(UI.layout.buttonHeightSmall, UI.layout.buttonHeightSmall)
        removeBtn:SetPoint("RIGHT", -2, 0)
        removeBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
        removeBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)
        removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        removeBtn.text:SetPoint("CENTER")
        removeBtn.text:SetText("|cffff6666X|r")
        removeBtn:SetScript("OnClick", function()
            onRemove(itemID)
        end)
        removeBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.5, 0.1, 0.1, 1)
            self.text:SetText("|cffff0000X|r")
        end)
        removeBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.3, 0.1, 0.1, 1)
            self.text:SetText("|cffff6666X|r")
        end)

        return row
    end

    RefreshList = function()
        for _, child in pairs({listContainer:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local yOff = 0
        local hasEntries = false

        for itemID, _ in pairs(IM.db.global.junkList or {}) do
            hasEntries = true
            CreateItemRow(listContainer, itemID, yOff, function(id)
                IM:RemoveFromJunkList(id)
                RefreshList()
                UpdateCount()
                IM:RefreshAllUI()
            end)
            yOff = yOff - 30
        end

        if not hasEntries then
            noItemsLabel:Show()
            yOff = -24
        else
            noItemsLabel:Hide()
        end

        local listHeight = math.max(math.abs(yOff), 24)
        listContainer:SetHeight(listHeight)
        return listHeight
    end

    -- Initial list refresh - must happen before button positioning
    local listHeight = RefreshList()
    listCard._contentHeight = listCard._contentHeight + listHeight + 12

    -- Clear button (positioned after list)
    local clearBtn = UI:CreateButton(listCard, "Clear All", 80, 24)
    clearBtn:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -8)
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("INVENTORYMANAGER_CLEAR_JUNKLIST")
    end)

    -- Add space for button
    listCard._contentHeight = listCard._contentHeight + 36
    listCard:SetHeight(listCard:GetContentHeight())

    content:AdvanceY(listCard:GetContentHeight() + UI.layout.spacing)

    -- ============================================================
    -- TIPS CARD
    -- ============================================================
    local tipsCard = UI:CreateCard(content, {
        title = "Tips",
    })

    tipsCard:AddText("- Use Ctrl+Alt+Click on items in your bags to add to junk list")
    tipsCard:AddText("- Junk items will be auto-sold regardless of quality or value")
    tipsCard:AddText("- Use this for items you never want to keep")

    content:AdvanceY(tipsCard:GetContentHeight() + UI.layout.spacing)

    content:FinalizeHeight()

    -- Full refresh function
    local function FullRefresh()
        local listHeight = RefreshList()
        -- Recalculate: title (36) + list + button spacing (8) + button (24) + padding (16)
        listCard._contentHeight = 36 + listHeight + 8 + 24 + 16
        listCard:SetHeight(listCard:GetContentHeight())
        UpdateCount()
    end

    -- Auto-refresh when panel is shown
    parent:SetScript("OnShow", FullRefresh)

    -- Auto-refresh when junk list changes
    IM:RegisterJunkListCallback(function(itemID, added)
        if parent:IsVisible() then
            FullRefresh()
        end
    end)

    -- Initial refresh
    C_Timer.After(0.1, FullRefresh)

    -- Clear confirmation popup
    StaticPopupDialogs["INVENTORYMANAGER_CLEAR_JUNKLIST"] = {
        text = "Are you sure you want to clear the junk list?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if IM.modules.JunkList then
                IM.modules.JunkList:ClearAllJunk()
            end
            FullRefresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end
