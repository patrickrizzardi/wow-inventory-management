--[[
    InventoryManager - UI/BagIntegration.lua
    Integration with bag addons (Blizzard default, BetterBags, AdiBags, Bagnon, ArkInventory)

    Adds IM overlays (lock icons, junk skulls, sell highlights) to whatever
    bag addon the user has installed.

    Supported addons:
    - BetterBags: Hooks item button updates via their callback system
    - AdiBags: Scans section containers for item buttons
    - Bagnon: Hooks ItemSlot updates and scans frame children
    - ArkInventory: Scans bar frames for item buttons
    - Blizzard: Hooks ContainerFrame_Update and combined bags

    Public Methods:
    - BagIntegration:GetDetectedAddon() - returns name of detected bag addon
    - BagIntegration:RefreshAllOverlays() - force refresh all overlays
]]

local addonName, IM = ...
local UI = IM.UI

local BagIntegration = {}
UI.BagIntegration = BagIntegration

-- Track which bag addon is detected
local _detectedBagAddon = nil
local _hooksApplied = false
local _retryCount = 0
local MAX_RETRIES = 5

-- Supported bag addons (checked in order of preference)
local BAG_ADDONS = {
    "BetterBags",
    "AdiBags",
    "Bagnon",
    "ArkInventory",
    -- Blizzard default is fallback
}

-- ============================================================================
-- DETECTION & INITIALIZATION
-- ============================================================================

-- Detect which bag addon is active
function BagIntegration:DetectBagAddon()
    for _, addon in ipairs(BAG_ADDONS) do
        if C_AddOns.IsAddOnLoaded(addon) then
            _detectedBagAddon = addon
            IM:Debug("[BagIntegration] Detected bag addon: " .. addon)
            return addon
        end
    end
    _detectedBagAddon = "Blizzard"
    IM:Debug("[BagIntegration] Using Blizzard default bags")
    return "Blizzard"
end

-- Initialize bag integration
function BagIntegration:Initialize()
    if _hooksApplied then return end

    local addon = self:DetectBagAddon()

    if addon == "BetterBags" then
        self:HookBetterBags()
    elseif addon == "AdiBags" then
        self:HookAdiBags()
    elseif addon == "Bagnon" then
        self:HookBagnon()
    elseif addon == "ArkInventory" then
        self:HookArkInventory()
    else
        self:HookBlizzardBags()
    end

    -- Universal events for overlay refresh
    local integration = self
    IM:RegisterEvent("BAG_UPDATE_DELAYED", function()
        integration:RefreshAllOverlays()
    end)

    _hooksApplied = true
    IM:Debug("[BagIntegration] Initialized for " .. addon)
end

-- ============================================================================
-- BLIZZARD DEFAULT BAGS
-- ============================================================================

function BagIntegration:HookBlizzardBags()
    local integration = self

    -- Hook ContainerFrame_Update to add our overlays after items are set
    if ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            integration:OnContainerFrameUpdate(frame)
        end)
    end

    -- Hook for combined bags (Blizzard's combined bag view)
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function()
            C_Timer.After(0.1, function()
                integration:RefreshAllOverlays()
            end)
        end)

        if ContainerFrameCombinedBags.Update then
            hooksecurefunc(ContainerFrameCombinedBags, "Update", function()
                integration:RefreshAllOverlays()
            end)
        end
    end

    -- Hook individual container frames OnShow
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", function()
                C_Timer.After(0.1, function()
                    integration:RefreshAllOverlays()
                end)
            end)
        end
    end

    IM:Debug("[BagIntegration] Hooked Blizzard bags")
end

function BagIntegration:OnContainerFrameUpdate(frame)
    if not frame then return end

    local bagID = frame:GetID()
    if not bagID then return end

    -- Refresh overlays for this bag after a frame
    C_Timer.After(0, function()
        if IM.modules.ItemLock then
            IM.modules.ItemLock:RefreshBagOverlays(bagID)
        end
        if IM.modules.JunkList then
            IM.modules.JunkList:RefreshBagOverlays(bagID)
        end
    end)
end

-- ============================================================================
-- BETTERBAGS INTEGRATION
-- ============================================================================

-- Periodic refresh ticker for BetterBags
local _betterBagsRefreshTicker = nil

function BagIntegration:HookBetterBags()
    local integration = self

    -- Wait for BetterBags to fully initialize
    C_Timer.After(1, function()
        integration:SetupBetterBagsHooks()
    end)

    -- Start a periodic refresh while bags might be visible
    -- This catches updates that hooks might miss
    _betterBagsRefreshTicker = C_Timer.NewTicker(1.0, function()
        -- Only refresh if BetterBags backpack is visible
        local backpackVisible = false
        if integration._betterBagsBackpack and integration._betterBagsBackpack:IsVisible() then
            backpackVisible = true
        elseif _G.BetterBagsBagBackpack and _G.BetterBagsBagBackpack:IsVisible() then
            backpackVisible = true
        elseif _G.BetterBagsBackpack and _G.BetterBagsBackpack:IsVisible() then
            backpackVisible = true
        end

        if backpackVisible then
            integration:RefreshBetterBagsOverlays()
        end
    end)
end

function BagIntegration:SetupBetterBagsHooks()
    local integration = self
    local BetterBags = _G.BetterBags

    if not BetterBags then
        _retryCount = _retryCount + 1
        if _retryCount < MAX_RETRIES then
            IM:Debug("[BagIntegration] BetterBags global not found, retrying... (" .. _retryCount .. "/" .. MAX_RETRIES .. ")")
            C_Timer.After(2, function()
                integration:SetupBetterBagsHooks()
            end)
        else
            IM:Debug("[BagIntegration] BetterBags global not found after " .. MAX_RETRIES .. " retries, falling back to event-based refresh")
        end
        return
    end

    IM:Debug("[BagIntegration] Setting up BetterBags hooks")

    -- Find the main BetterBags backpack frame
    local backpackFrame = nil

    -- Try different ways to find the backpack frame
    if BetterBags.Backpack and BetterBags.Backpack.frame then
        backpackFrame = BetterBags.Backpack.frame
    elseif _G.BetterBagsBagBackpack then
        backpackFrame = _G.BetterBagsBagBackpack
    elseif _G.BetterBagsBackpack then
        backpackFrame = _G.BetterBagsBackpack
    end

    if backpackFrame then
        IM:Debug("[BagIntegration] Found BetterBags backpack frame: " .. (backpackFrame:GetName() or "unnamed"))

        backpackFrame:HookScript("OnShow", function()
            C_Timer.After(0.3, function()
                integration:RefreshBetterBagsOverlays()
            end)
        end)
    end

    -- Hook BetterBags' Draw/Refresh functions if available
    if BetterBags.Backpack then
        if BetterBags.Backpack.Draw then
            hooksecurefunc(BetterBags.Backpack, "Draw", function()
                C_Timer.After(0.15, function()
                    integration:RefreshBetterBagsOverlays()
                end)
            end)
            IM:Debug("[BagIntegration] Hooked BetterBags.Backpack.Draw")
        end

        if BetterBags.Backpack.Refresh then
            hooksecurefunc(BetterBags.Backpack, "Refresh", function()
                C_Timer.After(0.15, function()
                    integration:RefreshBetterBagsOverlays()
                end)
            end)
            IM:Debug("[BagIntegration] Hooked BetterBags.Backpack.Refresh")
        end
    end

    -- Try to hook the ItemFrame module's update function
    local ItemFrame = BetterBags:GetModule("ItemFrame", true)
    if ItemFrame then
        IM:Debug("[BagIntegration] Found BetterBags ItemFrame module")

        -- Hook SetItem if it exists (called when an item is placed in a slot)
        if ItemFrame.SetItem then
            hooksecurefunc(ItemFrame, "SetItem", function(self)
                C_Timer.After(0.05, function()
                    integration:RefreshBetterBagsOverlays()
                end)
            end)
            IM:Debug("[BagIntegration] Hooked ItemFrame.SetItem")
        end
    end

    -- Store backpack frame reference for scanning
    self._betterBagsBackpack = backpackFrame

    IM:Debug("[BagIntegration] BetterBags hooks applied")
end

-- Recursively scan frame for item buttons
function BagIntegration:ScanFrameForItemButtons(frame, results, depth, visited)
    if not frame then return results or {} end
    depth = depth or 0
    results = results or {}
    visited = visited or {}

    -- Prevent infinite loops from circular references
    if visited[frame] then return results end
    visited[frame] = true

    -- Limit recursion depth to prevent issues
    if depth > 20 then return results end

    -- Check if this frame is an item button (try multiple methods)
    local bagID, slotID = self:GetBetterBagsSlotInfo(frame)
    if bagID and slotID and frame:IsVisible() then
        table.insert(results, { button = frame, bagID = bagID, slotID = slotID })
    else
        -- BetterBags wraps buttons in item frame objects
        -- The actual button might be in .frame or .button property
        if frame.frame then
            bagID, slotID = self:GetBetterBagsSlotInfo(frame.frame)
            if bagID and slotID and frame.frame:IsVisible() then
                table.insert(results, { button = frame.frame, bagID = bagID, slotID = slotID })
            end
        end
        if frame.button then
            bagID, slotID = self:GetBetterBagsSlotInfo(frame.button)
            if bagID and slotID and frame.button:IsVisible() then
                table.insert(results, { button = frame.button, bagID = bagID, slotID = slotID })
            end
        end
    end

    -- Scan children
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if child then
                self:ScanFrameForItemButtons(child, results, depth + 1, visited)
            end
        end
    end

    return results
end

function BagIntegration:RefreshBetterBagsOverlays()
    local updated = 0

    -- Method 1: Scan from known backpack frame
    if self._betterBagsBackpack and self._betterBagsBackpack:IsVisible() then
        local items = self:ScanFrameForItemButtons(self._betterBagsBackpack)
        for _, item in ipairs(items) do
            IM.UI.OverlayFactory:Update(item.button, item.bagID, item.slotID)
            updated = updated + 1
        end
    end

    -- Method 2: Try common BetterBags frame names
    local framesToScan = {
        _G.BetterBagsBagBackpack,
        _G.BetterBagsBackpack,
        _G.BetterBagsBag_Backpack,
    }

    for _, frame in ipairs(framesToScan) do
        if frame and frame:IsVisible() and frame ~= self._betterBagsBackpack then
            local items = self:ScanFrameForItemButtons(frame)
            for _, item in ipairs(items) do
                IM.UI.OverlayFactory:Update(item.button, item.bagID, item.slotID)
                updated = updated + 1
            end
        end
    end

    -- Method 3: Scan all visible frames with BetterBags in name
    for _, frameName in ipairs({"BetterBagsBagBackpack", "BetterBagsBackpack", "BetterBagsBag_Backpack", "BetterBagsBag"}) do
        local frame = _G[frameName]
        if frame and frame:IsVisible() then
            local items = self:ScanFrameForItemButtons(frame)
            for _, item in ipairs(items) do
                IM.UI.OverlayFactory:Update(item.button, item.bagID, item.slotID)
                updated = updated + 1
            end
        end
    end

    if updated > 0 then
        IM:Debug("[BagIntegration] Updated " .. updated .. " BetterBags overlays")
    else
        IM:Debug("[BagIntegration] No BetterBags buttons found to update")
    end
end

function BagIntegration:GetBetterBagsSlotInfo(button)
    if not button then return nil, nil end

    -- BetterBags uses different property names depending on version
    -- Try .slotkey first (newer BetterBags format: "bagID_slotID")
    if button.slotkey then
        local bagID, slotID = button.slotkey:match("^(%d+)_(%d+)$")
        if bagID and slotID then
            return tonumber(bagID), tonumber(slotID)
        end
    end

    -- Try .slotInfo (common BetterBags structure)
    if button.slotInfo then
        local bagID = button.slotInfo.bagid or button.slotInfo.bagID or button.slotInfo.bag
        local slotID = button.slotInfo.slotid or button.slotInfo.slotID or button.slotInfo.slot
        if bagID and slotID then
            return bagID, slotID
        end
    end

    -- Try direct properties with various naming conventions
    if button.bagid ~= nil and button.slotid ~= nil then
        return button.bagid, button.slotid
    end
    if button.bagID ~= nil and button.slotID ~= nil then
        return button.bagID, button.slotID
    end
    if button.bag ~= nil and button.slot ~= nil then
        return button.bag, button.slot
    end

    -- Try .data table
    if button.data then
        local bagID = button.data.bagid or button.data.bagID or button.data.bag
        local slotID = button.data.slotid or button.data.slotID or button.data.slot
        if bagID and slotID then
            return bagID, slotID
        end
    end

    -- Try .kind property (BetterBags uses this to identify item frames)
    -- Only process if it looks like an item button (has item data)
    if button.kind and button.kind == "item" then
        -- This is definitely a BetterBags item frame, try harder to find slot info
        if button.staticData then
            local bagID = button.staticData.bagid or button.staticData.bagID
            local slotID = button.staticData.slotid or button.staticData.slotID
            if bagID and slotID then
                return bagID, slotID
            end
        end
    end

    -- Try methods
    if button.GetBagID and button.GetSlotID then
        local ok1, bagID = pcall(button.GetBagID, button)
        local ok2, slotID = pcall(button.GetSlotID, button)
        if ok1 and ok2 and bagID and slotID then
            return bagID, slotID
        end
    end
    if button.GetBag and button.GetSlot then
        local ok1, bagID = pcall(button.GetBag, button)
        local ok2, slotID = pcall(button.GetSlot, button)
        if ok1 and ok2 and bagID and slotID then
            return bagID, slotID
        end
    end

    return nil, nil
end

-- ============================================================================
-- ADIBAGS INTEGRATION
-- ============================================================================

function BagIntegration:HookAdiBags()
    local integration = self

    C_Timer.After(1, function()
        integration:SetupAdiBagsHooks()
    end)
end

function BagIntegration:SetupAdiBagsHooks()
    local integration = self
    local AdiBags = _G.AdiBags

    if not AdiBags then
        _retryCount = _retryCount + 1
        if _retryCount < MAX_RETRIES then
            IM:Debug("[BagIntegration] AdiBags global not found, retrying...")
            C_Timer.After(2, function()
                integration:SetupAdiBagsHooks()
            end)
        end
        return
    end

    IM:Debug("[BagIntegration] Setting up AdiBags hooks")

    -- AdiBags uses sections with item buttons inside
    -- Hook their container's OnShow
    if AdiBags.frame then
        AdiBags.frame:HookScript("OnShow", function()
            C_Timer.After(0.2, function()
                integration:RefreshAdiBagsOverlays()
            end)
        end)
    end

    -- Hook LayoutSection if available
    if AdiBags.LayoutSection then
        hooksecurefunc(AdiBags, "LayoutSection", function()
            C_Timer.After(0.1, function()
                integration:RefreshAdiBagsOverlays()
            end)
        end)
    end

    -- Hook their content update
    if AdiBags.UpdateContent then
        hooksecurefunc(AdiBags, "UpdateContent", function()
            C_Timer.After(0.1, function()
                integration:RefreshAdiBagsOverlays()
            end)
        end)
    end

    IM:Debug("[BagIntegration] AdiBags hooks applied")
end

function BagIntegration:RefreshAdiBagsOverlays()
    local updated = 0

    -- Scan for AdiBags item buttons by pattern
    -- AdiBags uses names like "AdiBagsItemButton1", "AdiBagsItemButton2"
    for i = 1, 500 do
        local button = _G["AdiBagsItemButton" .. i]
        if button and button:IsVisible() then
            local bagID, slotID = self:GetAdiBagsSlotInfo(button)
            if bagID and slotID then
                IM.UI.OverlayFactory:Update(button, bagID, slotID)
                updated = updated + 1
            end
        end
    end

    if updated > 0 then
        IM:Debug("[BagIntegration] Updated " .. updated .. " AdiBags overlays")
    end
end

function BagIntegration:GetAdiBagsSlotInfo(button)
    if not button then return nil, nil end

    -- AdiBags stores bag/slot in button properties
    if button.bag and button.slot then
        return button.bag, button.slot
    end

    -- Try GetBag/GetSlot methods
    if button.GetBag and button.GetSlot then
        return button:GetBag(), button:GetSlot()
    end

    -- Try bagId/slotId naming
    if button.bagId and button.slotId then
        return button.bagId, button.slotId
    end

    return nil, nil
end

-- ============================================================================
-- BAGNON INTEGRATION
-- ============================================================================

function BagIntegration:HookBagnon()
    local integration = self

    C_Timer.After(1, function()
        integration:SetupBagnonHooks()
    end)
end

function BagIntegration:SetupBagnonHooks()
    local integration = self
    local Bagnon = _G.Bagnon

    if not Bagnon then
        _retryCount = _retryCount + 1
        if _retryCount < MAX_RETRIES then
            IM:Debug("[BagIntegration] Bagnon global not found, retrying...")
            C_Timer.After(2, function()
                integration:SetupBagnonHooks()
            end)
        end
        return
    end

    IM:Debug("[BagIntegration] Setting up Bagnon hooks")

    -- Bagnon uses ItemSlot class for item buttons
    -- Try to hook their ItemSlot:Update method
    if Bagnon.ItemSlot and Bagnon.ItemSlot.Update then
        hooksecurefunc(Bagnon.ItemSlot, "Update", function(slot)
            if slot and slot:IsVisible() then
                local bagID, slotID = integration:GetBagnonSlotInfo(slot)
                if bagID and slotID then
                    IM.UI.OverlayFactory:Update(slot, bagID, slotID)
                end
            end
        end)
    end

    -- Hook frame show events
    if Bagnon.Frame then
        -- Bagnon creates frames like Bagnon.bags, Bagnon.bank
        for _, frameName in ipairs({"bags", "bank", "void", "guild"}) do
            local frame = Bagnon[frameName]
            if frame and frame.HookScript then
                frame:HookScript("OnShow", function()
                    C_Timer.After(0.2, function()
                        integration:RefreshBagnonOverlays()
                    end)
                end)
            end
        end
    end

    IM:Debug("[BagIntegration] Bagnon hooks applied")
end

function BagIntegration:RefreshBagnonOverlays()
    local updated = 0

    -- Scan for Bagnon item buttons
    -- Pattern: BagnonInventoryItem{bag}_{slot} or BagnonItem{N}
    for bagID = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            -- Try various Bagnon naming patterns
            local button = _G["BagnonInventoryItem" .. bagID .. "_" .. slotID]
                        or _G["BagnonBagItem" .. bagID .. "_" .. slotID]
                        or _G["BagnonItem" .. bagID .. "_" .. slotID]

            if button and button:IsVisible() then
                IM.UI.OverlayFactory:Update(button, bagID, slotID)
                updated = updated + 1
            end
        end
    end

    -- Also scan numbered buttons
    for i = 1, 500 do
        local button = _G["BagnonItemButton" .. i]
        if button and button:IsVisible() then
            local bagID, slotID = self:GetBagnonSlotInfo(button)
            if bagID and slotID then
                IM.UI.OverlayFactory:Update(button, bagID, slotID)
                updated = updated + 1
            end
        end
    end

    if updated > 0 then
        IM:Debug("[BagIntegration] Updated " .. updated .. " Bagnon overlays")
    end
end

function BagIntegration:GetBagnonSlotInfo(slot)
    if not slot then return nil, nil end

    -- Bagnon ItemSlot has GetBag() and GetID() methods
    if slot.GetBag and slot.GetID then
        local bagID = slot:GetBag()
        local slotID = slot:GetID()
        if bagID and slotID then
            return bagID, slotID
        end
    end

    -- Try info table
    if slot.info then
        return slot.info.bag, slot.info.slot
    end

    -- Try direct properties
    if slot.bag and slot.slot then
        return slot.bag, slot.slot
    end

    return nil, nil
end

-- ============================================================================
-- ARKINVENTORY INTEGRATION
-- ============================================================================

function BagIntegration:HookArkInventory()
    local integration = self

    C_Timer.After(1, function()
        integration:SetupArkInventoryHooks()
    end)
end

function BagIntegration:SetupArkInventoryHooks()
    local integration = self
    local ArkInventory = _G.ArkInventory

    if not ArkInventory then
        _retryCount = _retryCount + 1
        if _retryCount < MAX_RETRIES then
            IM:Debug("[BagIntegration] ArkInventory global not found, retrying...")
            C_Timer.After(2, function()
                integration:SetupArkInventoryHooks()
            end)
        end
        return
    end

    IM:Debug("[BagIntegration] Setting up ArkInventory hooks")

    -- ArkInventory uses Frame_Item_Update for item button updates
    if ArkInventory.Frame_Item_Update then
        hooksecurefunc(ArkInventory, "Frame_Item_Update", function(frame)
            if frame and frame:IsVisible() then
                local bagID, slotID = integration:GetArkInventorySlotInfo(frame)
                if bagID and slotID then
                    IM.UI.OverlayFactory:Update(frame, bagID, slotID)
                end
            end
        end)
    end

    -- Hook main frame show
    if ArkInventory.Frame_Main_Show then
        hooksecurefunc(ArkInventory, "Frame_Main_Show", function()
            C_Timer.After(0.2, function()
                integration:RefreshArkInventoryOverlays()
            end)
        end)
    end

    IM:Debug("[BagIntegration] ArkInventory hooks applied")
end

function BagIntegration:RefreshArkInventoryOverlays()
    local ArkInventory = _G.ArkInventory
    if not ArkInventory then return end

    local updated = 0

    -- Scan for ArkInventory item frames
    -- Pattern: ARKINV_Frame{loc}ScrollContainerItem{n}
    for loc = 1, 9 do  -- Various location types (bag, bank, etc.)
        for i = 1, 200 do
            local button = _G["ARKINV_Frame" .. loc .. "ScrollContainerItem" .. i]
            if button and button:IsVisible() then
                local bagID, slotID = self:GetArkInventorySlotInfo(button)
                if bagID and slotID then
                    IM.UI.OverlayFactory:Update(button, bagID, slotID)
                    updated = updated + 1
                end
            end
        end
    end

    if updated > 0 then
        IM:Debug("[BagIntegration] Updated " .. updated .. " ArkInventory overlays")
    end
end

function BagIntegration:GetArkInventorySlotInfo(frame)
    if not frame then return nil, nil end

    -- ArkInventory stores location info in the frame
    if frame.ARK_Data then
        local data = frame.ARK_Data
        if data.loc_id and data.bag_id and data.slot_id then
            -- Convert ArkInventory's internal IDs to WoW bag IDs
            -- loc_id 1 = bags, bag_id maps to actual bag
            if data.loc_id == 1 then
                return data.bag_id - 1, data.slot_id  -- ArkInventory uses 1-indexed bags
            end
        end
    end

    -- Try direct properties
    if frame.bag and frame.slot then
        return frame.bag, frame.slot
    end

    return nil, nil
end

-- ============================================================================
-- SHARED UTILITIES
-- ============================================================================

-- Get the detected bag addon name
function BagIntegration:GetDetectedAddon()
    return _detectedBagAddon or "Unknown"
end

-- Get item button from a container frame (for Blizzard or unknown addons)
function BagIntegration:GetItemButton(bagID, slotID)
    if _detectedBagAddon == "BetterBags" then
        return self:FindBetterBagsButton(bagID, slotID)
    elseif _detectedBagAddon == "AdiBags" then
        return self:FindAdiBagsButton(bagID, slotID)
    elseif _detectedBagAddon == "Bagnon" then
        return self:FindBagnonButton(bagID, slotID)
    elseif _detectedBagAddon == "ArkInventory" then
        return self:FindArkInventoryButton(bagID, slotID)
    end

    -- Blizzard default
    local containerFrame
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag and bagID == Enum.BagIndex.ReagentBag then
        containerFrame = _G["ContainerFrame" .. (NUM_BAG_SLOTS + 2)]
    else
        containerFrame = _G["ContainerFrame" .. (bagID + 1)]
    end
    if not containerFrame then return nil end

    local buttonName = containerFrame:GetName() .. "Item" .. slotID
    return _G[buttonName]
end

-- Find button by bag/slot for each addon (used by GetItemButton)
function BagIntegration:FindBetterBagsButton(bagID, slotID)
    for i = 1, 500 do
        local button = _G["BetterBagsBagButton" .. i] or _G["BetterBagsItemButton" .. i]
        if button then
            local b, s = self:GetBetterBagsSlotInfo(button)
            if b == bagID and s == slotID then
                return button
            end
        end
    end
    return nil
end

function BagIntegration:FindAdiBagsButton(bagID, slotID)
    for i = 1, 500 do
        local button = _G["AdiBagsItemButton" .. i]
        if button then
            local b, s = self:GetAdiBagsSlotInfo(button)
            if b == bagID and s == slotID then
                return button
            end
        end
    end
    return nil
end

function BagIntegration:FindBagnonButton(bagID, slotID)
    local button = _G["BagnonInventoryItem" .. bagID .. "_" .. slotID]
                or _G["BagnonBagItem" .. bagID .. "_" .. slotID]
                or _G["BagnonItem" .. bagID .. "_" .. slotID]
    return button
end

function BagIntegration:FindArkInventoryButton(bagID, slotID)
    for loc = 1, 9 do
        for i = 1, 200 do
            local button = _G["ARKINV_Frame" .. loc .. "ScrollContainerItem" .. i]
            if button then
                local b, s = self:GetArkInventorySlotInfo(button)
                if b == bagID and s == slotID then
                    return button
                end
            end
        end
    end
    return nil
end

-- Force refresh all bag overlays
function BagIntegration:RefreshAllOverlays()
    -- Call addon-specific refresh
    if _detectedBagAddon == "BetterBags" then
        self:RefreshBetterBagsOverlays()
    elseif _detectedBagAddon == "AdiBags" then
        self:RefreshAdiBagsOverlays()
    elseif _detectedBagAddon == "Bagnon" then
        self:RefreshBagnonOverlays()
    elseif _detectedBagAddon == "ArkInventory" then
        self:RefreshArkInventoryOverlays()
    end

    -- Also refresh via module methods (for Blizzard and as fallback)
    if IM.modules.ItemLock then
        IM.modules.ItemLock:RefreshAllOverlays()
    end
    if IM.modules.JunkList then
        IM.modules.JunkList:RefreshAllOverlays()
    end
end

-- ============================================================================
-- DIAGNOSTICS
-- ============================================================================

-- Diagnostic function to help debug bag addon detection
function BagIntegration:RunDiagnostics()
    IM:Print("=== BagIntegration Diagnostics ===")
    IM:Print("Detected addon: " .. (self:GetDetectedAddon() or "None"))
    IM:Print("Hooks applied: " .. (_hooksApplied and "Yes" or "No"))

    -- Check for BetterBags
    IM:Print("")
    IM:Print("BetterBags check:")
    IM:Print("  _G.BetterBags: " .. ((_G.BetterBags and "Found") or "Not found"))
    IM:Print("  _G.BetterBagsBagBackpack: " .. ((_G.BetterBagsBagBackpack and "Found") or "Not found"))
    IM:Print("  _G.BetterBagsBackpack: " .. ((_G.BetterBagsBackpack and "Found") or "Not found"))

    if self._betterBagsBackpack then
        IM:Print("  Stored backpack frame: " .. (self._betterBagsBackpack:GetName() or "unnamed"))
        IM:Print("  Backpack visible: " .. (self._betterBagsBackpack:IsVisible() and "Yes" or "No"))
    end

    -- Scan for item buttons
    if _detectedBagAddon == "BetterBags" then
        IM:Print("")
        IM:Print("Scanning for BetterBags item buttons...")
        local totalFound = 0

        -- Try each frame
        local framesToCheck = {
            { name = "_betterBagsBackpack", frame = self._betterBagsBackpack },
            { name = "BetterBagsBagBackpack", frame = _G.BetterBagsBagBackpack },
            { name = "BetterBagsBackpack", frame = _G.BetterBagsBackpack },
        }

        for _, info in ipairs(framesToCheck) do
            if info.frame and info.frame:IsVisible() then
                local items = self:ScanFrameForItemButtons(info.frame)
                IM:Print("  " .. info.name .. ": " .. #items .. " item buttons")
                totalFound = totalFound + #items

                -- Show first few buttons for debugging
                if #items > 0 and #items <= 3 then
                    for _, item in ipairs(items) do
                        IM:Print("    - Bag " .. item.bagID .. " Slot " .. item.slotID)
                    end
                end
            else
                IM:Print("  " .. info.name .. ": " .. (info.frame and "Not visible" or "Not found"))
            end
        end

        IM:Print("Total item buttons found: " .. totalFound)
    end

    IM:Print("=== End Diagnostics ===")
end

-- ============================================================================
-- IM BAG BUTTON (Cheddar Icon)
-- ============================================================================

local _imBagButton = nil

-- Create the IM button that appears on bag frames
function BagIntegration:CreateIMButton()
    if _imBagButton then return _imBagButton end

    local button = CreateFrame("Button", "InventoryManagerBagButton", UIParent)
    button:SetSize(60, 60)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(100)
    button:Hide()

    -- Icon texture (custom cheddar icon)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture("Interface\\AddOns\\InventoryManager\\Textures\\cheddar-icon")

    -- Click handler
    button:SetScript("OnClick", function(self, mouseButton)
        if IsShiftKeyDown() then
            -- Shift+Click: Open Settings
            if IM.UI and IM.UI.ToggleConfig then
                IM.UI:ToggleConfig()
            else
                IM:Print("Settings not available")
            end
        else
            -- Regular Click: Open Dashboard/Net Worth
            if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Toggle then
                IM.UI.Dashboard:Toggle()
            else
                IM:Print("Dashboard not available")
            end
        end
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cffffb000InventoryManager|r", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffffffClick|r to open Net Worth Dashboard", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffShift+Click|r to open Settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Detected bag addon: |cff00ff00" .. (_detectedBagAddon or "Unknown") .. "|r", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    _imBagButton = button
    return button
end

-- Position the IM button relative to a bag frame
function BagIntegration:PositionIMButton(bagFrame)
    if not _imBagButton then
        self:CreateIMButton()
    end

    if not bagFrame or not bagFrame:IsVisible() then
        _imBagButton:Hide()
        return
    end

    -- Position in top-right corner of bag frame
    _imBagButton:ClearAllPoints()
    _imBagButton:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -35, 10)
    _imBagButton:SetParent(bagFrame)
    _imBagButton:SetFrameStrata("HIGH")
    _imBagButton:Show()
end

-- Show/hide IM button based on bag visibility
function BagIntegration:UpdateIMButtonVisibility()
    if not _imBagButton then
        self:CreateIMButton()
    end

    local bagFrame = nil

    -- Find the visible bag frame based on detected addon
    if _detectedBagAddon == "BetterBags" then
        bagFrame = self._betterBagsBackpack
            or _G.BetterBagsBagBackpack
            or _G.BetterBagsBackpack
    elseif _detectedBagAddon == "AdiBags" then
        bagFrame = _G.AdiBagsContainer1
    elseif _detectedBagAddon == "Bagnon" then
        bagFrame = _G.BagnonInventory1 or _G.BagnonBagFrame1
    elseif _detectedBagAddon == "ArkInventory" then
        bagFrame = _G.ARKINV_Frame1
    else
        -- Blizzard bags
        bagFrame = ContainerFrameCombinedBags or _G.ContainerFrame1
    end

    if bagFrame and bagFrame:IsVisible() then
        self:PositionIMButton(bagFrame)
    else
        _imBagButton:Hide()
    end
end

-- Hook bag frames to show/hide IM button
function BagIntegration:HookIMButton()
    local integration = self

    -- Create the button
    self:CreateIMButton()

    -- Hook bag open/close events
    IM:RegisterEvent("BAG_OPEN", function()
        C_Timer.After(0.1, function()
            integration:UpdateIMButtonVisibility()
        end)
    end)

    IM:RegisterEvent("BAG_CLOSED", function()
        C_Timer.After(0.1, function()
            integration:UpdateIMButtonVisibility()
        end)
    end)

    -- Also check periodically while bags might be open
    C_Timer.NewTicker(0.5, function()
        if _imBagButton and _imBagButton:IsShown() then
            -- Button is showing, verify parent is still visible
            local parent = _imBagButton:GetParent()
            if parent and not parent:IsVisible() then
                _imBagButton:Hide()
            end
        end
    end)

    -- Hook specific bag frames based on addon
    if _detectedBagAddon == "BetterBags" then
        -- BetterBags - hook their backpack frame
        C_Timer.After(2, function()
            local bbFrame = integration._betterBagsBackpack
                or _G.BetterBagsBagBackpack
                or _G.BetterBagsBackpack

            if bbFrame then
                bbFrame:HookScript("OnShow", function()
                    C_Timer.After(0.1, function()
                        integration:PositionIMButton(bbFrame)
                    end)
                end)
                bbFrame:HookScript("OnHide", function()
                    if _imBagButton then _imBagButton:Hide() end
                end)
            end
        end)
    else
        -- Blizzard/other bags
        if ContainerFrameCombinedBags then
            ContainerFrameCombinedBags:HookScript("OnShow", function()
                C_Timer.After(0.1, function()
                    integration:PositionIMButton(ContainerFrameCombinedBags)
                end)
            end)
            ContainerFrameCombinedBags:HookScript("OnHide", function()
                if _imBagButton then _imBagButton:Hide() end
            end)
        end

        for i = 1, 13 do
            local frame = _G["ContainerFrame" .. i]
            if frame then
                frame:HookScript("OnShow", function()
                    C_Timer.After(0.1, function()
                        integration:UpdateIMButtonVisibility()
                    end)
                end)
            end
        end
    end

    IM:Debug("[BagIntegration] IM button hooks applied")
end

-- ============================================================================
-- GOLD CLICK HOOK (Shift+Click for Net Worth)
-- ============================================================================

function BagIntegration:HookGoldFrame()
    -- Hook the backpack gold display for Shift+Click
    -- This works with Blizzard bags - other addons may have their own gold frames

    local function HookGoldButton(frame)
        if not frame then return end

        frame:HookScript("OnClick", function(self, button)
            if IsShiftKeyDown() then
                -- Open Net Worth Dashboard
                if IM.UI and IM.UI.Dashboard and IM.UI.Dashboard.Toggle then
                    IM.UI.Dashboard:Toggle()
                end
            end
        end)
    end

    -- Try to hook Blizzard's gold frame
    if BackpackTokenFrame then
        HookGoldButton(BackpackTokenFrame)
    end

    -- Hook money frames in container frames
    for i = 1, 13 do
        local moneyFrame = _G["ContainerFrame" .. i .. "MoneyFrame"]
        if moneyFrame then
            HookGoldButton(moneyFrame)
        end
    end

    IM:Debug("[BagIntegration] Gold frame hooks applied")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Initialize when addon loads
IM:RegisterEvent("PLAYER_LOGIN", function()
    IM:Debug("[BagIntegration] PLAYER_LOGIN - Initializing")
    BagIntegration:Initialize()

    -- Initialize IM button after a short delay
    C_Timer.After(1, function()
        BagIntegration:HookIMButton()
        BagIntegration:HookGoldFrame()
    end)
end)
