--[[
    InventoryManager - Modules/Tracking/GuildBankTracking.lua
    Tracks gold and item deposits/withdrawals to/from guild bank.

    Unlike warband bank (which is your own money moving between locations),
    guild bank IS income/expense since it's communal money.
    - Gold withdrawn = income (you're taking shared money)
    - Gold deposited = expense (you're giving away money)
    - Items also tracked for audit trail

    Events:
    - PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE with GuildBanker type
    - GUILDBANK_UPDATE_MONEY: Guild bank gold changed
    - BAG_UPDATE_DELAYED: Player bags changed (for item tracking)

    @module Modules.Tracking.GuildBankTracking
]]

local addonName, IM = ...

-- DEBUG: Verify module file is loading
print("|cff888888[IM Debug] GuildBankTracking.lua loading...|r")

local GuildBankTracking = {}
IM:RegisterModule("GuildBankTracking", GuildBankTracking)

-- Bag IDs (0-4 are regular bags, 5 is reagent bag)
local BAG_SLOTS = { 0, 1, 2, 3, 4, 5 }

-- State
local _guildBankOpen = false
local _lastGuildBankGold = nil
local _bagSnapshot = {}
local _pendingUpdate = false
local _bagUpdateHandler = nil

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

-- Create a snapshot of player bags (for item tracking)
local function _SnapshotBags()
    local snapshot = {}

    for _, bagID in ipairs(BAG_SLOTS) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.itemID then
                local key = info.itemID
                snapshot[key] = snapshot[key] or { quantity = 0, link = info.hyperlink }
                snapshot[key].quantity = snapshot[key].quantity + (info.stackCount or 1)
            end
        end
    end

    return snapshot
end

-- Compare two bag snapshots and return changes
local function _CompareBagSnapshots(before, after)
    local changes = {}

    -- Find items that decreased (went to guild bank)
    for itemID, beforeData in pairs(before) do
        local afterQty = after[itemID] and after[itemID].quantity or 0
        local diff = beforeData.quantity - afterQty
        if diff > 0 then
            table.insert(changes, {
                itemID = itemID,
                itemLink = beforeData.link,
                quantity = diff,
                direction = "deposit",
            })
        end
    end

    -- Find items that increased (came from guild bank)
    for itemID, afterData in pairs(after) do
        local beforeQty = before[itemID] and before[itemID].quantity or 0
        local diff = afterData.quantity - beforeQty
        if diff > 0 then
            table.insert(changes, {
                itemID = itemID,
                itemLink = afterData.link,
                quantity = diff,
                direction = "withdraw",
            })
        end
    end

    return changes
end

-- Process detected item changes
local function _ProcessItemChanges(changes)
    if #changes == 0 then
        return
    end

    IM:Debug("[GuildBankTracking] Processing " .. #changes .. " item changes")

    for _, change in ipairs(changes) do
        local transType
        local actionWord

        if change.direction == "deposit" then
            transType = "guildbank_item_out"
            actionWord = "deposited"
        else
            transType = "guildbank_item_in"
            actionWord = "withdrew"
        end

        IM:AddTransaction(transType, {
            itemID = change.itemID,
            itemLink = change.itemLink,
            quantity = change.quantity,
            value = 0,  -- Item transactions don't have gold value
            source = "Guild Bank",
        })

        -- User-visible confirmation
        local itemName = change.itemLink or ("Item #" .. change.itemID)
        IM:Print("Guild Bank: " .. actionWord .. " " .. itemName .. " x" .. change.quantity)
    end
end

-- Handle bag updates while guild bank is open (for item tracking)
local function _OnBagUpdate()
    print("|cff888888[IM Debug] GuildBankTracking: _OnBagUpdate() called, bankOpen=" .. tostring(_guildBankOpen) .. "|r")

    if not _guildBankOpen then
        print("|cffff6666[IM Debug] GuildBankTracking: Bank not open, ignoring bag update|r")
        return
    end

    -- Debounce: Only process once per frame
    if _pendingUpdate then
        print("|cff888888[IM Debug] GuildBankTracking: Update already pending, debouncing|r")
        return
    end
    _pendingUpdate = true

    -- Delay slightly to let bag state settle
    C_Timer.After(0.1, function()
        _pendingUpdate = false

        if not _guildBankOpen then
            print("|cffff6666[IM Debug] GuildBankTracking: Bank closed during debounce, skipping|r")
            return
        end

        -- Take new snapshot
        local newSnapshot = _SnapshotBags()
        print("|cff888888[IM Debug] GuildBankTracking: Took new snapshot|r")

        -- Compare with current snapshot
        local changes = _CompareBagSnapshots(_bagSnapshot, newSnapshot)
        print("|cff888888[IM Debug] GuildBankTracking: Found " .. #changes .. " item changes|r")

        -- Process any changes found
        if #changes > 0 then
            print("|cff00ff00[IM Debug] GuildBankTracking: Processing " .. #changes .. " changes!|r")
            _ProcessItemChanges(changes)
        end

        -- Update snapshot to new state for next comparison
        _bagSnapshot = newSnapshot
    end)
end

-- ============================================================================
-- PUBLIC METHODS
-- ============================================================================

function GuildBankTracking:OnEnable()
    local module = self  -- Capture for closures

    IM:Debug("[GuildBankTracking] Registering events")
    print("|cff888888[IM Debug] GuildBankTracking:OnEnable() called|r")

    -- Create bag update handler
    _bagUpdateHandler = function()
        _OnBagUpdate()
    end

    -- PRIMARY: Use Player Interaction Manager events (same as BankItemTracking)
    -- Guild bank uses Enum.PlayerInteractionType.GuildBanker
    if Enum and Enum.PlayerInteractionType then
        IM:Debug("[GuildBankTracking] PlayerInteractionType enum available")
        print("|cff888888[IM Debug] GuildBankTracking: Enum.PlayerInteractionType available|r")

        -- Check if GuildBanker type exists
        if Enum.PlayerInteractionType.GuildBanker then
            print("|cff888888[IM Debug] GuildBankTracking: GuildBanker type = " .. tostring(Enum.PlayerInteractionType.GuildBanker) .. "|r")
        else
            print("|cffff6666[IM Debug] GuildBankTracking: WARNING - GuildBanker type NOT FOUND in enum!|r")
            -- List available types for debugging
            print("|cff888888[IM Debug] Available PlayerInteractionType values:|r")
            for k, v in pairs(Enum.PlayerInteractionType) do
                print("|cff888888  " .. tostring(k) .. " = " .. tostring(v) .. "|r")
            end
        end

        IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(event, interactionType)
            IM:Debug("[GuildBankTracking] FRAME_SHOW fired, type=" .. tostring(interactionType))
            print("|cff888888[IM Debug] GuildBankTracking: FRAME_SHOW type=" .. tostring(interactionType) .. "|r")

            if Enum.PlayerInteractionType.GuildBanker and interactionType == Enum.PlayerInteractionType.GuildBanker then
                IM:Debug("[GuildBankTracking] Guild bank opened (interaction manager)")
                print("|cff00ff00[IM Debug] GuildBankTracking: GUILD BANK DETECTED!|r")
                module:OnGuildBankOpened()
            end
        end)

        IM:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(event, interactionType)
            IM:Debug("[GuildBankTracking] FRAME_HIDE fired, type=" .. tostring(interactionType))
            print("|cff888888[IM Debug] GuildBankTracking: FRAME_HIDE type=" .. tostring(interactionType) .. "|r")

            if Enum.PlayerInteractionType.GuildBanker and interactionType == Enum.PlayerInteractionType.GuildBanker then
                IM:Debug("[GuildBankTracking] Guild bank closed (interaction manager)")
                print("|cff00ff00[IM Debug] GuildBankTracking: GUILD BANK CLOSED!|r")
                module:OnGuildBankClosed()
            end
        end)
    else
        print("|cffff6666[IM Debug] GuildBankTracking: WARNING - Enum.PlayerInteractionType NOT available!|r")
        IM:Debug("[GuildBankTracking] PlayerInteractionType enum NOT available - using fallback events")

        -- FALLBACK: Try the legacy events (may or may not work)
        IM:RegisterEvent("GUILDBANKFRAME_OPENED", function()
            IM:Debug("[GuildBankTracking] Guild bank opened (legacy event)")
            print("|cff00ff00[IM Debug] GuildBankTracking: GUILDBANKFRAME_OPENED fired!|r")
            module:OnGuildBankOpened()
        end)

        IM:RegisterEvent("GUILDBANKFRAME_CLOSED", function()
            IM:Debug("[GuildBankTracking] Guild bank closed (legacy event)")
            print("|cff00ff00[IM Debug] GuildBankTracking: GUILDBANKFRAME_CLOSED fired!|r")
            module:OnGuildBankClosed()
        end)
    end

    -- Gold tracking - fires when guild bank gold changes
    IM:RegisterEvent("GUILDBANK_UPDATE_MONEY", function()
        IM:Debug("[GuildBankTracking] GUILDBANK_UPDATE_MONEY fired, bankOpen=" .. tostring(_guildBankOpen))
        print("|cff888888[IM Debug] GuildBankTracking: GUILDBANK_UPDATE_MONEY fired|r")
        if _guildBankOpen then
            module:OnGuildBankMoneyChanged()
        end
    end)

    IM:Debug("[GuildBankTracking] Module enabled")
    print("|cff00ff00[IM Debug] GuildBankTracking: Module enabled successfully|r")
end

function GuildBankTracking:OnGuildBankOpened()
    print("|cff00ff00[IM Debug] GuildBankTracking:OnGuildBankOpened() called|r")

    if _guildBankOpen then
        print("|cffff6666[IM Debug] GuildBankTracking: Already open, skipping|r")
        return
    end

    _guildBankOpen = true

    -- Initialize gold tracking
    -- GetGuildBankMoney() returns the guild bank's gold in copper
    if GetGuildBankMoney then
        _lastGuildBankGold = GetGuildBankMoney()
        IM:Debug("[GuildBankTracking] Initial guild gold: " .. IM:FormatMoney(_lastGuildBankGold or 0))
        print("|cff888888[IM Debug] GuildBankTracking: Initial guild gold = " .. IM:FormatMoney(_lastGuildBankGold or 0) .. "|r")
    else
        print("|cffff6666[IM Debug] GuildBankTracking: WARNING - GetGuildBankMoney() not available!|r")
    end

    -- Take initial bag snapshot for item tracking
    _bagSnapshot = _SnapshotBags()
    local itemCount = 0
    local totalQty = 0
    for _, data in pairs(_bagSnapshot) do
        itemCount = itemCount + 1
        totalQty = totalQty + data.quantity
    end
    IM:Debug("[GuildBankTracking] Initial snapshot: " .. itemCount .. " unique items, " .. totalQty .. " total")
    print("|cff888888[IM Debug] GuildBankTracking: Initial snapshot: " .. itemCount .. " unique items, " .. totalQty .. " total|r")

    -- Register for bag updates while guild bank is open
    IM:RegisterEvent("BAG_UPDATE_DELAYED", _bagUpdateHandler)
    print("|cff00ff00[IM Debug] GuildBankTracking: Now listening for BAG_UPDATE_DELAYED events|r")
end

function GuildBankTracking:OnGuildBankClosed()
    print("|cff888888[IM Debug] GuildBankTracking:OnGuildBankClosed() called|r")

    if not _guildBankOpen then
        print("|cffff6666[IM Debug] GuildBankTracking: Bank wasn't open, skipping|r")
        return
    end

    -- Unregister bag update handler
    if _bagUpdateHandler then
        IM:UnregisterEvent("BAG_UPDATE_DELAYED", _bagUpdateHandler)
        print("|cff888888[IM Debug] GuildBankTracking: Unregistered BAG_UPDATE_DELAYED handler|r")
    end

    _guildBankOpen = false
    _bagSnapshot = {}
    _lastGuildBankGold = nil

    IM:Debug("[GuildBankTracking] Guild bank closed, handler unregistered")
    print("|cff00ff00[IM Debug] GuildBankTracking: Bank closed, state reset|r")
end

function GuildBankTracking:OnGuildBankMoneyChanged()
    print("|cff888888[IM Debug] GuildBankTracking:OnGuildBankMoneyChanged() called|r")

    if not GetGuildBankMoney then
        print("|cffff6666[IM Debug] GuildBankTracking: GetGuildBankMoney not available!|r")
        return
    end

    local currentGold = GetGuildBankMoney()
    print("|cff888888[IM Debug] GuildBankTracking: Current guild gold = " .. tostring(currentGold) .. "|r")

    if not currentGold or currentGold < 0 then
        IM:Debug("[GuildBankTracking] Invalid gold value")
        print("|cffff6666[IM Debug] GuildBankTracking: Invalid gold value|r")
        return
    end

    -- Calculate delta
    local previousGold = _lastGuildBankGold or 0
    local delta = currentGold - previousGold

    -- Update reference
    _lastGuildBankGold = currentGold

    -- Skip if no meaningful change
    if math.abs(delta) < 1 then
        print("|cff888888[IM Debug] GuildBankTracking: No meaningful change (delta < 1)|r")
        return
    end

    IM:Debug("[GuildBankTracking] Guild gold changed: " .. previousGold .. " -> " .. currentGold .. " (delta: " .. delta .. ")")
    print("|cff00ff00[IM Debug] GuildBankTracking: Gold changed! " .. IM:FormatMoney(previousGold) .. " -> " .. IM:FormatMoney(currentGold) .. " (delta: " .. IM:FormatMoney(math.abs(delta)) .. ")|r")

    -- Determine if player deposited or withdrew
    -- NOTE: We detect this by checking player's gold change
    -- If guild bank increased AND player gold decreased = deposit
    -- If guild bank decreased AND player gold increased = withdrawal
    --
    -- Since this event fires when guild bank changes, we need to infer direction:
    -- - Guild bank gold increased = someone deposited (we assume it was us)
    -- - Guild bank gold decreased = someone withdrew (we assume it was us)
    --
    -- This is imperfect (could be another guild member), but best we can do without
    -- tracking player gold delta at same time. For single-player usage, it's accurate.

    if delta < 0 then
        -- Guild bank decreased = withdrawal (income for character)
        local amount = math.abs(delta)
        IM:AddTransaction("guildbank_gold_in", {
            value = amount,  -- Positive = income
            source = "Guild Bank",
        })
        IM:Print("Guild Bank: withdrew " .. IM:FormatMoney(amount))
    else
        -- Guild bank increased = deposit (expense for character)
        IM:AddTransaction("guildbank_gold_out", {
            value = -delta,  -- Negative = expense
            source = "Guild Bank",
        })
        IM:Print("Guild Bank: deposited " .. IM:FormatMoney(delta))
    end
end

-- Debug helpers
function GuildBankTracking:IsGuildBankOpen()
    return _guildBankOpen
end

-- Alias for unclaimed gold tracking
function GuildBankTracking:IsAtGuildBank()
    return _guildBankOpen
end

function GuildBankTracking:GetLastGuildBankGold()
    return _lastGuildBankGold or 0
end
