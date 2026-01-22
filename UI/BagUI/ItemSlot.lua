--[[
    InventoryManager - UI/BagUI/ItemSlot.lua
    Item slot button with overlay handling and IM actions.
]]

local addonName, IM = ...

IM.UI.BagUI = IM.UI.BagUI or {}
local ItemSlot = {}
IM.UI.BagUI.ItemSlot = ItemSlot

local ITEM_SIZE = 36
local COUNT_OFFSET_X = -1
local COUNT_OFFSET_Y = 2
local DIM_ALPHA = 0.2
local SHADE_ALPHA = 0
local ILVL_OFFSET_X = 3
local ILVL_OFFSET_Y = -3

local _slotPool = {}

local function _UpdateQualityBorder(slot, quality)
    if not quality or quality <= 1 then
        slot.border:Hide()
        return
    end
    local r, g, b = GetItemQualityColor(quality)
    slot.border:SetBackdropBorderColor(r, g, b, 1)
    slot.border:Show()
end

local function _ClearSlot(slot)
    slot.itemData = nil
    slot.bagID = nil
    slot.slotID = nil

    -- Clear icon (template's or our custom)
    local iconTexture = slot.icon or slot.imIcon
    if iconTexture then
        iconTexture:SetTexture(nil)
    end

    if slot.count then
        slot.count:SetText("")
    end
    if slot.ilvl then
        slot.ilvl:SetText("")
    end
    if slot.border then
        slot.border:Hide()
    end
    slot:SetAlpha(1)

    if IM.UI and IM.UI.OverlayFactory then
        local overlay = IM.UI.OverlayFactory:GetOverlay(slot)
        if overlay then
            IM.UI.OverlayFactory:HideAll(overlay)
        end
    end
end

local function _SetTooltip(slot)
    if not slot.bagID or not slot.slotID then return end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(slot.bagID, slot.slotID)
    GameTooltip:Show()
end

local _slotCount = 0

local function _CreateSlot(parent)
    -- BetterBags pattern: parent frame holds bagID, button holds slotID
    -- See: https://github.com/Cidan/BetterBags/blob/main/frames/item.lua#L769-L772
    _slotCount = _slotCount + 1

    -- Create wrapper as BUTTON (not Frame) - matches BetterBags line 769
    local wrapper = CreateFrame("Button", "IMItemSlotWrapper" .. _slotCount, parent)
    wrapper:SetSize(ITEM_SIZE, ITEM_SIZE)

    -- Create the actual item button as child of wrapper
    local slot = CreateFrame("ItemButton", "IMItemSlot" .. _slotCount, wrapper, "ContainerFrameItemButtonTemplate")
    slot:SetSize(ITEM_SIZE, ITEM_SIZE)
    slot:SetAllPoints(wrapper)

    -- Explicitly register for right-click - BetterBags line 823
    slot:RegisterForDrag("LeftButton")
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Provide GetBagID method if template doesn't have it
    -- Template's click handler calls self:GetBagID() which may rely on parent:GetID()
    if not slot.GetBagID then
        slot.GetBagID = function(self)
            local parent = self:GetParent()
            return parent and parent:GetID() or self.bagID or 0
        end
    end

    -- DEBUG: Log clicks to verify template handler runs
    slot:HookScript("OnClick", function(self, button)
        if IM and IM.Debug then
            local bagID = self.GetBagID and self:GetBagID() or "nil"
            local slotID = self:GetID()
            IM:Debug(string.format("[ItemSlot] OnClick button=%s bagID=%s slotID=%s",
                tostring(button), tostring(bagID), tostring(slotID)))
        end
    end)

    -- Store reference to wrapper
    slot.wrapper = wrapper

    -- Custom visuals (don't interfere with click handling)
    slot.imIcon = slot:CreateTexture(nil, "ARTWORK")
    slot.imIcon:SetAllPoints()

    slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    slot.count:SetPoint("BOTTOMRIGHT", COUNT_OFFSET_X, COUNT_OFFSET_Y)

    slot.ilvl = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    slot.ilvl:SetPoint("TOPLEFT", ILVL_OFFSET_X, ILVL_OFFSET_Y)
    slot.ilvl:SetTextColor(1, 0.95, 0.7, 1)

    slot.border = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    slot.border:SetPoint("TOPLEFT", -1, 1)
    slot.border:SetPoint("BOTTOMRIGHT", 1, -1)
    slot.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    slot.border:Hide()

    return slot
end

function ItemSlot:Acquire(parent)
    local slot = table.remove(_slotPool)
    if not slot then
        slot = _CreateSlot(parent)
    end
    -- Parent the wrapper, not the slot directly
    if slot.wrapper then
        slot.wrapper:SetParent(parent)
        slot.wrapper:Show()
    else
        slot:SetParent(parent)
    end
    slot:Show()
    return slot
end

function ItemSlot:Release(slot)
    if not slot then return end
    _ClearSlot(slot)
    slot:Hide()
    if slot.wrapper then
        slot.wrapper:Hide()
    end
    table.insert(_slotPool, slot)
end

function ItemSlot:SetItem(slot, itemData)
    if not slot or not itemData then return end
    slot.itemData = itemData

    -- BetterBags pattern: parent frame holds bagID, button holds slotID
    -- This is how ContainerFrameItemButtonTemplate expects to find the bag/slot
    if slot.wrapper then
        slot.wrapper:SetID(itemData.bagID)  -- Parent gets bag ID
    end
    slot:SetID(itemData.slotID)             -- Button gets slot ID
    slot.bagID = itemData.bagID             -- Direct property for template

    -- Also store for our own reference
    slot.slotID = itemData.slotID

    -- Set icon (use template's icon if available, otherwise our custom one)
    local iconTexture = slot.icon or slot.imIcon
    if iconTexture then
        iconTexture:SetTexture(itemData.icon)
    end
    _UpdateQualityBorder(slot, itemData.quality)

    if IM and IM.Debug then
        IM:Debug(string.format("[ItemSlot] SetItem bagID=%d slotID=%d (%s)",
            itemData.bagID, itemData.slotID, tostring(itemData.itemLink or itemData.itemID)))
        -- Debug: Check if template methods exist
        IM:Debug(string.format("[ItemSlot] HasGetBagID=%s GetID=%s ParentID=%s",
            tostring(slot.GetBagID ~= nil),
            tostring(slot:GetID()),
            tostring(slot.wrapper and slot.wrapper:GetID() or "no wrapper")))
    end

    if itemData.count and itemData.count > 1 then
        slot.count:SetText(itemData.count)
    else
        slot.count:SetText("")
    end

    if IM.UI and IM.UI.OverlayFactory then
        IM.UI.OverlayFactory:Update(slot, itemData.bagID, itemData.slotID)
        local overlay = IM.UI.OverlayFactory:GetOverlay(slot)
        if overlay then
            if overlay.lockShade then overlay.lockShade:SetAlpha(SHADE_ALPHA) end
            if overlay.sellShade then overlay.sellShade:SetAlpha(SHADE_ALPHA) end
            if overlay.unsellableShade then overlay.unsellableShade:SetAlpha(SHADE_ALPHA) end
            if overlay.mailShade then overlay.mailShade:SetAlpha(SHADE_ALPHA) end
            if overlay:IsShown() then
                slot.border:Hide()
            end
        end
    end

    if slot.ilvl then
        local showIlvl = IM.db and IM.db.global and IM.db.global.bagUI and IM.db.global.bagUI.showItemLevel
        local equipLoc = itemData.itemEquipLoc or ""
        if showIlvl and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
            local ilvl = nil
            if C_Item then
                if C_Item.GetCurrentItemLevel and ItemLocation and ItemLocation.CreateFromBagAndSlot and slot.bagID and slot.slotID then
                    local location = ItemLocation:CreateFromBagAndSlot(slot.bagID, slot.slotID)
                    if location and location:IsValid() then
                        ilvl = C_Item.GetCurrentItemLevel(location)
                    end
                end
                if not ilvl and C_Item.GetDetailedItemLevelInfo and itemData.itemLink then
                    ilvl = C_Item.GetDetailedItemLevelInfo(itemData.itemLink)
                end
            end
            if not ilvl and itemData.itemLink and GetDetailedItemLevelInfo then
                ilvl = GetDetailedItemLevelInfo(itemData.itemLink)
            end
            if ilvl and ilvl > 0 then
                local r, g, b = GetItemQualityColor(itemData.quality or 1)
                slot.ilvl:SetTextColor(r, g, b, 1)
                slot.ilvl:SetText(ilvl)
            else
                slot.ilvl:SetText("")
            end
        else
            slot.ilvl:SetText("")
        end
    end
end

function ItemSlot:SetDimmed(slot, dimmed)
    if not slot then return end
    slot:SetAlpha(dimmed and DIM_ALPHA or 1)
    if IM.UI and IM.UI.OverlayFactory then
        local overlay = IM.UI.OverlayFactory:GetOverlay(slot)
        if overlay then
            IM.UI.OverlayFactory:SetDimmed(overlay, dimmed)
        end
    end
end
