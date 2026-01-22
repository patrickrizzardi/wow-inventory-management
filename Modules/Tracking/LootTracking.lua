--[[
    InventoryManager - Modules/Tracking/LootTracking.lua
    Tracks item and gold looting from corpses, chests, etc.

    Events:
    - CHAT_MSG_LOOT: Item looted
    - CHAT_MSG_MONEY: Gold looted

    @module Modules.Tracking.LootTracking
]]

local addonName, IM = ...

local LootTracking = {}
IM:RegisterModule("LootTracking", LootTracking)

function LootTracking:OnEnable()
    -- Skip if loot tracking disabled
    if not IM.db.global.ledger.trackLoot then
        IM:Debug("[LootTracking] Disabled in settings")
        return
    end

    IM:Debug("[LootTracking] Registering events")

    -- Track item looting
    IM:RegisterEvent("CHAT_MSG_LOOT", function(event, message, ...)
        self:OnLootMessage(message)
    end)

    -- Track gold looting (separate from other money events)
    IM:RegisterEvent("CHAT_MSG_MONEY", function(event, message, ...)
        self:OnMoneyLoot(message)
    end)

    IM:Debug("[LootTracking] Events registered")
end

-- Parse loot message for items
function LootTracking:OnLootMessage(message)
    IM:Debug("[LootTracking] CHAT_MSG_LOOT: " .. tostring(message))

    -- Skip if we're at a vendor - VendorTracking handles purchases separately
    -- This prevents duplicate entries (one from purchase hook, one from loot message)
    local vendorTracking = IM:GetModule("VendorTracking")
    if vendorTracking and vendorTracking:IsAtVendor() then
        IM:Debug("[LootTracking] At vendor, skipping loot message (VendorTracking handles this)")
        return
    end

    -- Skip if we're at the auction house - AuctionTracking handles this
    local auctionTracking = IM:GetModule("AuctionTracking")
    if auctionTracking and auctionTracking:IsAtAuctionHouse() then
        IM:Debug("[LootTracking] At auction house, skipping loot message (AuctionTracking handles this)")
        return
    end

    -- Skip if we're at a mailbox - MailTracking handles this
    local mailTracking = IM:GetModule("MailTracking")
    if mailTracking and mailTracking:IsAtMailbox() then
        IM:Debug("[LootTracking] At mailbox, skipping loot message (MailTracking handles this)")
        return
    end

    -- Skip if we're in a trade - TradeTracking handles this
    local tradeTracking = IM:GetModule("TradeTracking")
    if tradeTracking and tradeTracking:IsInTrade() then
        IM:Debug("[LootTracking] In trade, skipping loot message (TradeTracking handles this)")
        return
    end

    -- Extract item link using shared utility
    local itemLink = IM:ExtractItemLinkFromMessage(message)
    if not itemLink then
        IM:Debug("[LootTracking] No item link found")
        return
    end

    -- Get item ID
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then
        local idFromLink = itemLink:match("|Hitem:(%d+)")
        if idFromLink then
            itemID = tonumber(idFromLink)
        end
    end

    if not itemID then
        IM:Debug("[LootTracking] Could not get itemID")
        return
    end

    -- Extract quantity
    local quantity = 1
    local qtyMatch = message:match("x(%d+)%.?$") or message:match("|rx(%d+)") or message:match(" x(%d+)")
    if qtyMatch then
        quantity = tonumber(qtyMatch) or 1
    end

    -- Log to new ledger system
    IM:AddTransaction("loot", {
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity,
        value = 0, -- Loot has no direct gold value
    })

    -- Also maintain backwards compatibility with old system
    IM:AddLootHistoryEntry(itemID, itemLink, quantity, nil)

    IM:Debug("[LootTracking] Logged: " .. itemLink .. " x" .. quantity)
end

-- Parse money loot messages (gold from corpses)
function LootTracking:OnMoneyLoot(message)
    -- Only track if this looks like a loot message (not auction, trade, etc.)
    -- Loot messages typically contain "loot" or come without specific context
    -- We'll be conservative here to avoid double-counting

    -- Skip if message contains auction-related words
    if message:lower():find("auction") then
        return
    end

    -- Extract gold amount using shared utility
    local totalCopper = IM:ParseMoneyFromMessage(message)

    if totalCopper <= 0 then
        return
    end

    -- Check if this looks like a loot message vs other money sources
    -- This is heuristic - gold loot usually has "You loot" prefix
    if message:lower():find("loot") then
        IM:AddTransaction("loot", {
            value = totalCopper,
            source = "Gold Loot",
        })

        IM:Debug("[LootTracking] Gold looted: " .. IM:FormatMoney(totalCopper))
    end
end
