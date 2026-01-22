--[[
    InventoryManager - BagHooks.lua
    One-time bag function wrapping and dispatch system

    Wraps Blizzard bag functions ONCE on addon load to prevent
    "last writer wins" conflicts with other addons.

    Public Methods:
    - BagHooks:Initialize() - Called early in load order
    - BagHooks:IsIMBagsEnabled() - Check if IM bags are active
]]

local addonName, IM = ...

local BagHooks = {}
IM:RegisterModule("BagHooks", BagHooks)

-- Private state
local _initialized = false
local _originals = {}

-- Store reference to BagUI (set after BagUI loads)
local _bagUI = nil

local _dispatchers = {}

local function _IsDispatcher(func)
    for _, dispatcher in pairs(_dispatchers) do
        if func == dispatcher then
            return true
        end
    end
    return false
end

local function _CaptureOriginals()
    if OpenAllBags and not _IsDispatcher(OpenAllBags) then _originals.OpenAllBags = OpenAllBags end
    if CloseAllBags and not _IsDispatcher(CloseAllBags) then _originals.CloseAllBags = CloseAllBags end
    if ToggleAllBags and not _IsDispatcher(ToggleAllBags) then _originals.ToggleAllBags = ToggleAllBags end
    if OpenBag and not _IsDispatcher(OpenBag) then _originals.OpenBag = OpenBag end
    if CloseBag and not _IsDispatcher(CloseBag) then _originals.CloseBag = CloseBag end
    if ToggleBag and not _IsDispatcher(ToggleBag) then _originals.ToggleBag = ToggleBag end
    if OpenBackpack and not _IsDispatcher(OpenBackpack) then _originals.OpenBackpack = OpenBackpack end
    if CloseBackpack and not _IsDispatcher(CloseBackpack) then _originals.CloseBackpack = CloseBackpack end
    if ToggleBackpack and not _IsDispatcher(ToggleBackpack) then _originals.ToggleBackpack = ToggleBackpack end
end

local function _EnsureBagUI()
    if _bagUI then
        return _bagUI
    end

    if IM and IM.UI and IM.UI.BagUI then
        if IM.UI.BagUI.Initialize then
            IM.UI.BagUI:Initialize()
        end
        _bagUI = IM.UI.BagUI
    end

    return _bagUI
end

function BagHooks:SetBagUI(bagUI)
    _bagUI = bagUI
    IM:Debug("[BagHooks] BagUI reference set: " .. tostring(bagUI ~= nil))

    if _bagUI and _bagUI.ApplyKeybindOverrides then
        _bagUI:ApplyKeybindOverrides()
    end
end

function BagHooks:IsIMBagsEnabled()
    return IM.db and IM.db.global.useIMBags
end

-- Dispatch helpers
local function _CanDispatch()
    -- Don't dispatch during combat lockdown
    if InCombatLockdown() then
        return false
    end
    return true
end

-- Helper to call IM BagUI or fall back to original
local function _TryIMBagsOrFallback(imAction, originalFunc, ...)
    local bagUI = _EnsureBagUI()
    
    IM:Debug("[BagHooks] _TryIMBagsOrFallback: enabled=" .. tostring(BagHooks:IsIMBagsEnabled()) .. ", bagUI=" .. tostring(bagUI ~= nil))

    if BagHooks:IsIMBagsEnabled() and bagUI then
        IM:Debug("[BagHooks] Calling IM BagUI action")
        local ok, err = pcall(imAction, bagUI)
        if not ok then
            IM:Debug("[BagHooks] Error in IM BagUI: " .. tostring(err))
            -- Fall back to original on error
            if originalFunc then
                IM:Debug("[BagHooks] Falling back to original function")
                originalFunc(...)
            end
        else
            IM:Debug("[BagHooks] IM BagUI action succeeded")
        end
    else
        -- Not enabled or BagUI not ready - use original
        IM:Debug("[BagHooks] Using original function (not enabled or BagUI not ready)")
        if originalFunc then
            originalFunc(...)
        end
    end
end

local function _DispatchOpenAll(...)
    _CaptureOriginals()
    IM:Debug("[BagHooks] OpenAllBags DISPATCHER called")
    if not _CanDispatch() then 
        IM:Debug("[BagHooks] Cannot dispatch (combat lockdown?)")
        return 
    end
    _TryIMBagsOrFallback(function(ui) ui:Show() end, _originals.OpenAllBags, ...)
end

local function _DispatchCloseAll()
    _CaptureOriginals()
    if not _CanDispatch() then return end
    _TryIMBagsOrFallback(function(ui) ui:Hide() end, _originals.CloseAllBags)
end

local function _DispatchToggleAll()
    _CaptureOriginals()
    IM:Debug("[BagHooks] ToggleAllBags DISPATCHER called")
    if not _CanDispatch() then 
        IM:Debug("[BagHooks] Cannot dispatch (combat lockdown?)")
        return 
    end
    IM:Debug("[BagHooks] ToggleAllBags called, useIMBags=" .. tostring(BagHooks:IsIMBagsEnabled()) .. ", _bagUI=" .. tostring(_bagUI ~= nil))
    _TryIMBagsOrFallback(function(ui) ui:Toggle() end, _originals.ToggleAllBags)
end

local function _DispatchOpenBag(bagID)
    _CaptureOriginals()
    IM:Debug("[BagHooks] OpenBag DISPATCHER called for bagID=" .. tostring(bagID))
    if not _CanDispatch() then return end
    _TryIMBagsOrFallback(function(ui) ui:Show() end, _originals.OpenBag, bagID)
end

local function _DispatchCloseBag(bagID)
    _CaptureOriginals()
    IM:Debug("[BagHooks] CloseBag DISPATCHER called for bagID=" .. tostring(bagID))
    if not _CanDispatch() then return end
    _TryIMBagsOrFallback(function(ui) ui:Hide() end, _originals.CloseBag, bagID)
end

local function _DispatchToggleBag(bagID)
    _CaptureOriginals()
    IM:Debug("[BagHooks] ToggleBag DISPATCHER called for bagID=" .. tostring(bagID))
    if not _CanDispatch() then return end
    _TryIMBagsOrFallback(function(ui) ui:Toggle() end, _originals.ToggleBag, bagID)
end

local function _DispatchOpenBackpack()
    _CaptureOriginals()
    IM:Debug("[BagHooks] OpenBackpack DISPATCHER called")
    if not _CanDispatch() then return end
    _TryIMBagsOrFallback(function(ui) ui:Show() end, _originals.OpenBackpack)
end

local function _DispatchCloseBackpack()
    _CaptureOriginals()
    IM:Debug("[BagHooks] CloseBackpack DISPATCHER called")
    if not _CanDispatch() then return end
    _TryIMBagsOrFallback(function(ui) ui:Hide() end, _originals.CloseBackpack)
end

local function _DispatchToggleBackpack()
    _CaptureOriginals()
    IM:Debug("[BagHooks] ToggleBackpack DISPATCHER called")
    if not _CanDispatch() then 
        IM:Debug("[BagHooks] Cannot dispatch (combat lockdown?)")
        return 
    end
    IM:Debug("[BagHooks] ToggleBackpack called, useIMBags=" .. tostring(BagHooks:IsIMBagsEnabled()) .. ", _bagUI=" .. tostring(_bagUI ~= nil))
    _TryIMBagsOrFallback(function(ui) ui:Toggle() end, _originals.ToggleBackpack)
end

local function _HandleForceIMBags()
    _CaptureOriginals()
    if not _CanDispatch() then return end

    local bagUI = _EnsureBagUI()
    if BagHooks:IsIMBagsEnabled() and bagUI then
        -- Close Blizzard bags first, then show IM bags
        if _originals.CloseAllBags then
            pcall(_originals.CloseAllBags)
        end
        pcall(function() bagUI:Show() end)
    end
end

-- Initialize hooks - called ONCE on addon load
function BagHooks:Initialize()
    -- Prevent double-wrapping on /reload
    if _initialized then
        IM:Debug("[BagHooks] Already initialized, skipping")
        return
    end
    _initialized = true

    -- Store dispatchers for comparison
    _dispatchers = {
        OpenAllBags = _DispatchOpenAll,
        CloseAllBags = _DispatchCloseAll,
        ToggleAllBags = _DispatchToggleAll,
        OpenBag = _DispatchOpenBag,
        CloseBag = _DispatchCloseBag,
        ToggleBag = _DispatchToggleBag,
        OpenBackpack = _DispatchOpenBackpack,
        CloseBackpack = _DispatchCloseBackpack,
        ToggleBackpack = _DispatchToggleBackpack,
    }

    local function _ApplyHooks()
        _CaptureOriginals()

        if OpenAllBags ~= _dispatchers.OpenAllBags then OpenAllBags = _dispatchers.OpenAllBags end
        if CloseAllBags ~= _dispatchers.CloseAllBags then CloseAllBags = _dispatchers.CloseAllBags end
        if ToggleAllBags ~= _dispatchers.ToggleAllBags then ToggleAllBags = _dispatchers.ToggleAllBags end
        if OpenBag ~= _dispatchers.OpenBag then OpenBag = _dispatchers.OpenBag end
        if CloseBag ~= _dispatchers.CloseBag then CloseBag = _dispatchers.CloseBag end
        if ToggleBag ~= _dispatchers.ToggleBag then ToggleBag = _dispatchers.ToggleBag end
        if OpenBackpack ~= _dispatchers.OpenBackpack then OpenBackpack = _dispatchers.OpenBackpack end
        if CloseBackpack ~= _dispatchers.CloseBackpack then CloseBackpack = _dispatchers.CloseBackpack end
        if ToggleBackpack ~= _dispatchers.ToggleBackpack then ToggleBackpack = _dispatchers.ToggleBackpack end
    end

    -- Apply immediately
    _ApplyHooks()

    IM:Debug("[BagHooks] Bag functions wrapped successfully")
end

-- Get original function (for testing/debugging)
function BagHooks:GetOriginal(funcName)
    return _originals[funcName]
end

-- Debug: check if BagUI is set
function BagHooks:HasBagUI()
    return _bagUI ~= nil
end

-- Debug: manually trigger show and dump state
function BagHooks:DebugShow()
    IM:Print("BagHooks Debug:")
    IM:Print("  _initialized: " .. tostring(_initialized))
    IM:Print("  _bagUI: " .. tostring(_bagUI ~= nil))
    IM:Print("  useIMBags: " .. tostring(self:IsIMBagsEnabled()))
    IM:Print("  IM.UI.BagUI exists: " .. tostring(IM.UI and IM.UI.BagUI ~= nil))
    IM:Print("Originals captured:")
    IM:Print("  OpenAllBags: " .. tostring(_originals.OpenAllBags ~= nil))
    IM:Print("  CloseAllBags: " .. tostring(_originals.CloseAllBags ~= nil))
    IM:Print("  ToggleAllBags: " .. tostring(_originals.ToggleAllBags ~= nil))
    IM:Print("  ToggleBackpack: " .. tostring(_originals.ToggleBackpack ~= nil))
    IM:Print("Globals are dispatchers:")
    IM:Print("  OpenAllBags: " .. tostring(_IsDispatcher(OpenAllBags)))
    IM:Print("  ToggleBackpack: " .. tostring(_IsDispatcher(ToggleBackpack)))

    if _bagUI and self:IsIMBagsEnabled() then
        IM:Print("Attempting to show BagUI...")
        local ok, err = pcall(function() _bagUI:Show() end)
        if not ok then
            IM:PrintError("Show failed: " .. tostring(err))
        end
    elseif _originals.ToggleBackpack then
        IM:Print("Falling back to original ToggleBackpack...")
        _originals.ToggleBackpack()
    else
        IM:PrintError("No BagUI and no original ToggleBackpack!")
    end
end

function BagHooks:OnInitialize()
    -- Initialize hooks immediately on module registration
    -- This ensures we capture originals before other addons
    self:Initialize()
end

function BagHooks:OnEnable()
    local module = self  -- Closure scoping pattern per CLAUDE.md

    local function _ReapplyDispatchers()
        _CaptureOriginals()
        if _dispatchers.ToggleBackpack then
            OpenAllBags = _dispatchers.OpenAllBags
            CloseAllBags = _dispatchers.CloseAllBags
            ToggleAllBags = _dispatchers.ToggleAllBags
            OpenBag = _dispatchers.OpenBag
            CloseBag = _dispatchers.CloseBag
            ToggleBag = _dispatchers.ToggleBag
            OpenBackpack = _dispatchers.OpenBackpack
            CloseBackpack = _dispatchers.CloseBackpack
            ToggleBackpack = _dispatchers.ToggleBackpack
        end
    end

    IM:RegisterEvent("PLAYER_LOGIN", function()
        -- Re-apply after Blizzard loads keybind handlers
        _ReapplyDispatchers()

        -- Catch late overrides from other addons
        C_Timer.After(1, function()
            _ReapplyDispatchers()
        end)
    end)

    -- Force IM bags when NPCs open bags automatically
    IM:RegisterEvent("MERCHANT_SHOW", _HandleForceIMBags)
    IM:RegisterEvent("MAIL_SHOW", _HandleForceIMBags)
    IM:RegisterEvent("AUCTION_HOUSE_SHOW", _HandleForceIMBags)
    IM:RegisterEvent("BANKFRAME_OPENED", _HandleForceIMBags)
end
