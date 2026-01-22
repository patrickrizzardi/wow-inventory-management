--[[
    InventoryManager - Modules/Tracking/FlightTracking.lua
    Tracks flight path costs.

    Events:
    - TAXIMAP_OPENED: Flight master opened
    - TAXIMAP_CLOSED: Flight master closed
    - Hook TakeTaxiNode: Capture destination and cost
    - PLAYER_MONEY: Confirm gold spent

    @module Modules.Tracking.FlightTracking
]]

local addonName, IM = ...

local FlightTracking = {}
IM:RegisterModule("FlightTracking", FlightTracking)

-- State tracking
local _atFlightMaster = false
local _pendingFlight = nil
local _lastGold = 0

function FlightTracking:OnEnable()
    local module = self

    -- Skip if flight tracking disabled
    if IM.db and IM.db.global and IM.db.global.ledger and not IM.db.global.ledger.trackFlights then
        IM:Debug("[FlightTracking] Disabled in settings")
        return
    end

    IM:Debug("[FlightTracking] Registering events")

    -- Track when at flight master
    IM:RegisterEvent("TAXIMAP_OPENED", function()
        module:OnTaxiMapOpened()
    end)

    IM:RegisterEvent("TAXIMAP_CLOSED", function()
        module:OnTaxiMapClosed()
    end)

    -- Track gold changes
    IM:RegisterEvent("PLAYER_MONEY", function()
        module:OnPlayerMoney()
    end)

    -- Hook the taxi function to capture destination and cost
    module:HookTaxiFunction()

    IM:Debug("[FlightTracking] Module enabled")
end

function FlightTracking:OnTaxiMapOpened()
    _atFlightMaster = true
    _lastGold = GetMoney()
    IM:Debug("[FlightTracking] Taxi map opened, gold: " .. _lastGold)
end

function FlightTracking:OnTaxiMapClosed()
    _atFlightMaster = false
    _pendingFlight = nil
    IM:Debug("[FlightTracking] Taxi map closed")
end

function FlightTracking:HookTaxiFunction()
    -- Hook TakeTaxiNode to capture what flight the player is taking
    hooksecurefunc("TakeTaxiNode", function(slot)
        if not _atFlightMaster then
            return
        end

        -- Get the cost and destination name
        local cost = TaxiNodeCost(slot) or 0
        local name = TaxiNodeName(slot) or "Unknown"

        if cost > 0 then
            _pendingFlight = {
                cost = cost,
                destination = name,
                timestamp = GetTime(),
            }
            IM:Debug("[FlightTracking] Pending flight to " .. name .. " for " .. IM:FormatMoney(cost))
        end
    end)
end

function FlightTracking:OnPlayerMoney()
    -- Only process if we have a pending flight
    if not _pendingFlight then
        return
    end

    -- Check if this is within a reasonable time window (2 seconds)
    if GetTime() - _pendingFlight.timestamp > 2 then
        IM:Debug("[FlightTracking] Pending flight expired, clearing")
        _pendingFlight = nil
        return
    end

    local currentGold = GetMoney()
    local goldDelta = currentGold - _lastGold

    -- Flight costs should result in gold loss
    if goldDelta < 0 then
        local actualCost = math.abs(goldDelta)

        -- Verify it roughly matches the expected cost (allow some tolerance)
        if math.abs(actualCost - _pendingFlight.cost) <= 1 then
            IM:AddTransaction("flight", {
                value = -actualCost,
                source = _pendingFlight.destination,
            })

            IM:Debug("[FlightTracking] Flight logged: " .. _pendingFlight.destination ..
                     " for " .. IM:FormatMoney(actualCost))
        else
            IM:Debug("[FlightTracking] Cost mismatch - expected " ..
                     _pendingFlight.cost .. ", actual " .. actualCost)
        end
    end

    -- Clear pending flight after processing
    _pendingFlight = nil
    _lastGold = currentGold
end

-- Check if at flight master
function FlightTracking:IsAtFlightMaster()
    return _atFlightMaster
end
