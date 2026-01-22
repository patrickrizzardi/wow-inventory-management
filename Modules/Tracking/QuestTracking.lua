--[[
    InventoryManager - Modules/Tracking/QuestTracking.lua
    Tracks quest gold rewards.

    Events:
    - QUEST_TURNED_IN: Quest completed with gold reward

    @module Modules.Tracking.QuestTracking
]]

local addonName, IM = ...

local QuestTracking = {}
IM:RegisterModule("QuestTracking", QuestTracking)

function QuestTracking:OnEnable()
    -- Skip if quest tracking disabled
    if not IM.db.global.ledger.trackQuests then
        IM:Debug("[QuestTracking] Disabled in settings")
        return
    end

    IM:Debug("[QuestTracking] Registering events")

    -- Track quest turn-ins
    IM:RegisterEvent("QUEST_TURNED_IN", function(event, questID, xpReward, moneyReward)
        self:OnQuestTurnedIn(questID, xpReward, moneyReward)
    end)

    IM:Debug("[QuestTracking] Events registered")
end

-- Handle quest turn-in
function QuestTracking:OnQuestTurnedIn(questID, xpReward, moneyReward)
    IM:Debug("[QuestTracking] Quest turned in: " .. tostring(questID) .. ", money: " .. tostring(moneyReward))

    -- Only log if there's a gold reward
    if not moneyReward or moneyReward <= 0 then
        return
    end

    -- Try to get quest name
    local questName = C_QuestLog.GetTitleForQuestID(questID) or ("Quest #" .. questID)

    IM:AddTransaction("quest_gold", {
        value = moneyReward,
        source = questName,
    })

    IM:Debug("[QuestTracking] Logged quest gold: " .. IM:FormatMoney(moneyReward) .. " from " .. questName)
end
