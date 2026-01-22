--[[
    InventoryManager - Modules/AuctionHouseProtection.lua
    Visual protection and confirmation popup for locked items at the Auction House
]]

local addonName, IM = ...

local AHProtection = {}
IM:RegisterModule("AuctionHouseProtection", AHProtection)

local isAHOpen = false

-- Track if we're allowing a post (user clicked "Post Anyway")
local allowPost = false

-- Track the pending item info for the popup
local pendingItemLink = nil

-- Create confirmation popup at load time (must be before OnInitialize)
StaticPopupDialogs["INVENTORYMANAGER_AH_LOCKED_CONFIRM"] = {
    text = "You are about to post a LOCKED item to the Auction House:\n\n%s\n\nAre you sure you want to continue?",
    button1 = "Post Anyway",
    button2 = "Cancel",
    OnAccept = function()
        allowPost = true
        -- Find and click the appropriate post button
        if AuctionHouseFrame then
            if AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame:IsShown() then
                local postButton = AuctionHouseFrame.CommoditiesSellFrame.PostButton
                if postButton and postButton:IsEnabled() then
                    postButton:Click()
                end
            elseif AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame:IsShown() then
                local postButton = AuctionHouseFrame.ItemSellFrame.PostButton
                if postButton and postButton:IsEnabled() then
                    postButton:Click()
                end
            end
        end
        -- Reset allowPost after a short delay to ensure the click completes
        C_Timer.After(0.1, function()
            allowPost = false
        end)
    end,
    OnCancel = function()
        -- No popup needed - user intentionally cancelled
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

function AHProtection:OnInitialize()
    -- Nothing needed here now
end

function AHProtection:OnEnable()
    -- Register for AH events
    IM:RegisterEvent("AUCTION_HOUSE_SHOW", function()
        self:OnAuctionHouseShow()
    end)

    IM:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
        self:OnAuctionHouseClosed()
    end)
end

-- Called when AH opens
function AHProtection:OnAuctionHouseShow()
    isAHOpen = true
    -- Hook the post buttons when AH opens
    self:HookPostButtons()
end

-- Called when AH closes
function AHProtection:OnAuctionHouseClosed()
    isAHOpen = false
    allowPost = false
    pendingItemLink = nil
end

-- Get the currently selected item for posting
function AHProtection:GetSelectedItemInfo()
    if not AuctionHouseFrame then return nil, nil end

    -- Check Commodities sell frame
    if AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame:IsShown() then
        -- itemLocation is a property, not a method
        local itemLocation = AuctionHouseFrame.CommoditiesSellFrame.itemLocation
        if itemLocation and itemLocation.IsValid and itemLocation:IsValid() then
            local bagID, slotID = itemLocation:GetBagAndSlot()
            if bagID and slotID then
                local info = C_Container.GetContainerItemInfo(bagID, slotID)
                if info then
                    return info.itemID, info.hyperlink
                end
            end
        end
    end

    -- Check Item sell frame
    if AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame:IsShown() then
        -- itemLocation is a property, not a method
        local itemLocation = AuctionHouseFrame.ItemSellFrame.itemLocation
        if itemLocation and itemLocation.IsValid and itemLocation:IsValid() then
            local bagID, slotID = itemLocation:GetBagAndSlot()
            if bagID and slotID then
                local info = C_Container.GetContainerItemInfo(bagID, slotID)
                if info then
                    return info.itemID, info.hyperlink
                end
            end
        end
    end

    return nil, nil
end

-- Hook the post buttons by replacing their OnClick handlers
function AHProtection:HookPostButtons()
    if not AuctionHouseFrame then return end

    -- Hook Commodities Post Button
    if AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.PostButton then
        local postButton = AuctionHouseFrame.CommoditiesSellFrame.PostButton
        if not postButton.IMHooked then
            local originalOnClick = postButton:GetScript("OnClick")
            postButton:SetScript("OnClick", function(self, button, down)
                if not allowPost then
                    local itemID, itemLink = AHProtection:GetSelectedItemInfo()
                    if itemID and IM:IsWhitelisted(itemID) then
                        pendingItemLink = itemLink
                        StaticPopup_Show("INVENTORYMANAGER_AH_LOCKED_CONFIRM", itemLink or ("Item #" .. itemID))
                        return -- Block the click
                    end
                end
                -- Call original handler
                if originalOnClick then
                    originalOnClick(self, button, down)
                end
            end)
            postButton.IMHooked = true
            postButton.IMOriginalOnClick = originalOnClick
            IM:Debug("AHProtection: Replaced CommoditiesSellFrame.PostButton OnClick")
        end
    end

    -- Hook Item Post Button
    if AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame.PostButton then
        local postButton = AuctionHouseFrame.ItemSellFrame.PostButton
        if not postButton.IMHooked then
            local originalOnClick = postButton:GetScript("OnClick")
            postButton:SetScript("OnClick", function(self, button, down)
                if not allowPost then
                    local itemID, itemLink = AHProtection:GetSelectedItemInfo()
                    if itemID and IM:IsWhitelisted(itemID) then
                        pendingItemLink = itemLink
                        StaticPopup_Show("INVENTORYMANAGER_AH_LOCKED_CONFIRM", itemLink or ("Item #" .. itemID))
                        return -- Block the click
                    end
                end
                -- Call original handler
                if originalOnClick then
                    originalOnClick(self, button, down)
                end
            end)
            postButton.IMHooked = true
            postButton.IMOriginalOnClick = originalOnClick
            IM:Debug("AHProtection: Replaced ItemSellFrame.PostButton OnClick")
        end
    end
end

-- Check if AH is currently open
function AHProtection:IsAuctionHouseOpen()
    return isAHOpen
end
