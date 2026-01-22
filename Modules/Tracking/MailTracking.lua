--[[
    InventoryManager - Modules/Tracking/MailTracking.lua
    Tracks mail gold and items sent/received.

    Events:
    - MAIL_SHOW: Enter mail context
    - MAIL_CLOSED: Leave mail context
    - MAIL_SUCCESS: Item/gold taken from mail
    - MAIL_SEND_SUCCESS: Mail sent successfully

    Note: Mail API is fragile, requires throttling between calls.

    @module Modules.Tracking.MailTracking
]]

local addonName, IM = ...

local MailTracking = {}
IM:RegisterModule("MailTracking", MailTracking)

-- State tracking
local _atMailbox = false
local _pendingSend = nil
local _lastMailAction = 0
local MAIL_THROTTLE = 0.5 -- Minimum seconds between mail actions

function MailTracking:OnEnable()
    -- Skip if mail tracking disabled
    if not IM.db.global.ledger.trackMail then
        IM:Debug("[MailTracking] Disabled in settings")
        return
    end

    IM:Debug("[MailTracking] Registering events")

    -- Mail context
    IM:RegisterEvent("MAIL_SHOW", function()
        self:OnMailShow()
    end)

    IM:RegisterEvent("MAIL_CLOSED", function()
        self:OnMailClosed()
    end)

    -- Mail send success
    IM:RegisterEvent("MAIL_SEND_SUCCESS", function()
        self:OnMailSendSuccess()
    end)

    -- Hook mail functions
    self:HookMailFunctions()

    IM:Debug("[MailTracking] Module enabled")
end

function MailTracking:OnMailShow()
    _atMailbox = true
    IM:Debug("[MailTracking] Mailbox opened")
end

function MailTracking:OnMailClosed()
    _atMailbox = false
    _pendingSend = nil
    IM:Debug("[MailTracking] Mailbox closed")
end

-- Hook mail sending
function MailTracking:HookMailFunctions()
    -- Hook SendMail to track outgoing
    local originalSendMail = SendMail

    SendMail = function(recipient, subject, body)
        -- Capture what we're sending
        local money = GetSendMailMoney() or 0
        local cod = GetSendMailCOD() or 0
        local items = {}

        -- Get attached items
        for i = 1, ATTACHMENTS_MAX_SEND or 12 do
            local itemLink = GetSendMailItemLink(i)
            if itemLink then
                local _, _, _, count = GetSendMailItem(i)
                local itemID = GetItemInfoInstant(itemLink)
                if itemID then
                    table.insert(items, {
                        itemID = itemID,
                        itemLink = itemLink,
                        quantity = count or 1,
                    })
                end
            end
        end

        _pendingSend = {
            recipient = recipient,
            money = money,
            cod = cod,
            items = items,
            timestamp = time(),
        }

        -- Call original
        return originalSendMail(recipient, subject, body)
    end

    -- Hook TakeInboxMoney to track incoming gold
    local originalTakeInboxMoney = TakeInboxMoney

    TakeInboxMoney = function(index)
        -- Get money amount before taking
        local _, _, sender, subject, money = GetInboxHeaderInfo(index)

        -- Call original
        originalTakeInboxMoney(index)

        -- Log if there was money
        if money and money > 0 then
            IM:AddTransaction("mail_gold_recv", {
                value = money,
                source = sender or "Unknown",
            })
            IM:Debug("[MailTracking] Received gold: " .. IM:FormatMoney(money) .. " from " .. (sender or "Unknown"))
        end
    end

    -- Hook TakeInboxItem to track incoming items
    local originalTakeInboxItem = TakeInboxItem

    TakeInboxItem = function(index, itemIndex)
        -- Get item info before taking
        local itemLink = GetInboxItemLink(index, itemIndex)
        local _, itemID, _, itemCount = GetInboxItem(index, itemIndex)
        local _, _, sender = GetInboxHeaderInfo(index)

        -- Call original
        originalTakeInboxItem(index, itemIndex)

        -- Log if there was an item
        if itemID then
            IM:AddTransaction("mail_item_recv", {
                itemID = itemID,
                itemLink = itemLink,
                quantity = itemCount or 1,
                value = 0,
                source = sender or "Unknown",
            })
            IM:Debug("[MailTracking] Received item: " .. (itemLink or "item") .. " from " .. (sender or "Unknown"))
        end
    end
end

-- Handle successful mail send
function MailTracking:OnMailSendSuccess()
    if not _pendingSend then return end

    -- Log sent gold
    if _pendingSend.money and _pendingSend.money > 0 then
        IM:AddTransaction("mail_gold_sent", {
            value = -_pendingSend.money, -- Negative = expense
            source = _pendingSend.recipient,
        })
        IM:Debug("[MailTracking] Sent gold: " .. IM:FormatMoney(_pendingSend.money) .. " to " .. _pendingSend.recipient)
    end

    -- Log sent items
    for _, item in ipairs(_pendingSend.items) do
        IM:AddTransaction("mail_item_sent", {
            itemID = item.itemID,
            itemLink = item.itemLink,
            quantity = item.quantity,
            value = 0,
            source = _pendingSend.recipient,
        })
        IM:Debug("[MailTracking] Sent item: " .. (item.itemLink or "item") .. " to " .. _pendingSend.recipient)
    end

    _pendingSend = nil
end

-- Check if at mailbox
function MailTracking:IsAtMailbox()
    return _atMailbox
end
