--[[
    Offline behaviour tests for what stops an item reaching a vendor.

    Run it:
        .claude/tests/autosell/run.sh

    These load the REAL Core.lua, Database.lua, Filters.lua and Modules/AutoSell.lua against
    wow_stub.lua.

    There is no confirm dialog and no session consent. `autoSellEnabled`, off by default, IS the
    permission to sell unattended, so the cases that used to drive a dialog now drive the setting.

    COVERED, as the shipping code rather than a description of it: the quality floor, the stored
    maxQuality clamp (both directions, and its fail-closed fallbacks - asked of GetMaxSellQuality
    directly, because the floor masks it in every sale outcome), the configured maxQuality
    threshold through a sale in both directions, the junk list overriding a filter that would have
    refused, the category-exclusion, mail-rule and no-vendor-value tiers, the database defaults,
    the master toggle governing the merchant-open sale, the addon's own later continuations (the
    item-data retry and the post-sale sweep) and the drain of a queue already running, the sale
    loop's per-item re-validation against the bags and the filter, the retry budgets, the popup's
    Sell All click driven through the shipping handler, and Core.lua's quality accessors
    (IM:GetQualityInfo, IM:GetQualityName, IM:GetQualityColorHex) with the settings dropdown
    deriving its list from them.

    NOT COVERED, and a change that stops any of them protecting an item will leave this suite
    green:

    - Five of ShouldAutoSell's protective tiers stand on client APIs the stub answers with a
      constant: soulbound (C_Item.IsBound), warbound-until-equip
      (C_Item.IsBoundToAccountUntilEquip), uncollected transmog
      (C_TransmogCollection.PlayerHasTransmog), toys (C_ToyBox.GetToyInfo) and equipment sets
      (C_EquipmentSet). Also the minSellPrice threshold, which nothing here sets.
    - Modules/TooltipInfo.lua is not loaded here. It is a MODULE, not part of the UI layer, so
      "the UI layer is not loaded" does not cover it and nothing below tests it.
    - Of the UI layer, only UI/Core.lua and UI/AutoSellPopup.lua are loaded, only in the Sell All
      case, and only far enough to call a click handler under a frame stub that answers every
      method - nothing here shows that anything DRAWS. The settings panels are reached by reading
      their source, never by driving them.
    - No claim about the live client can be proven here: buyback lifetime and event ordering at a
      real vendor are in-game checks.

    This list is hand-written, which is the shape this project's registry keeps catching. Read it
    as "these were known uncovered when it was written", never as "everything else is covered" -
    the only version of that claim worth believing is someone else deleting a guard and watching
    the suite go red.
]]

package.path = ".claude/tests/autosell/?.lua;" .. package.path

local Stub = require("wow_stub")
local IM = Stub.IM

local AutoSell  -- reassigned by Reset()

-- ------------------------------------------------------------- assertions --

local failures, checks = 0, 0

local function check(name, ok, detail)
    checks = checks + 1
    if ok then
        Stub.Say("  ok   " .. name)
    else
        failures = failures + 1
        Stub.Say("  FAIL " .. name .. (detail and ("  <- " .. tostring(detail)) or ""))
    end
end

--[[
    Run one section, and let the run survive it dying.

    An error raised out of a case - a production nil-index, a stub that met an argument nobody
    anticipated - used to end the process on the spot: no summary line, and every later check
    silently never executed. A suite that reports "6 checks, 0 failures" because the seventh
    section never ran is worse than one that reports a failure, because the missing checks are
    invisible in the output. So a section that aborts becomes exactly one named failure, the
    remaining sections still run, and the summary at the bottom is always printed.
]]
local function RunSection(name, body)
    Stub.Say("\n" .. name)
    local ok, err = pcall(body)
    if not ok then
        check(name .. ": the section ran to completion without raising", false, err)
    end
end

-- --------------------------------------------------------------- fixtures --

-- Item IDs used throughout. Quality and class are chosen so the only filter that can refuse them
-- is the one a given test is about.
local SELLABLE = 111        -- Poor quality, has a vendor price
local SELLABLE_2 = 222
local UNCACHED = 999        -- deliberately never defined: GetItemInfo returns nil for it

local function DefineStandardItems()
    Stub.DefineItem(SELLABLE, { quality = 0, sellPrice = 100, classID = 4 })
    Stub.DefineItem(SELLABLE_2, { quality = 0, sellPrice = 100, classID = 4 })
end

local function Reset()
    Stub.ClearTimers()
    Stub.ClearBags()
    Stub.items = {}
    Stub.itemVariants = {}
    Stub.sold = {}
    Stub.onSell = nil
    MerchantFrame.shown = true

    Stub.LoadAddon()
    AutoSell = IM.modules.AutoSell
    DefineStandardItems()
end

local function Printed(needle)
    for _, line in ipairs(IM.prints) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

local function Prints() return table.concat(IM.prints, " | ") end

local function SoldIDs()
    local ids = {}
    for _, sale in ipairs(Stub.sold or {}) do table.insert(ids, sale.itemID) end
    return ids
end

local function SoldCount() return #(Stub.sold or {}) end

--[[
    "Did the retry budget refill?" is a question about how many times the bags were re-scanned, not
    about the final message - a path that waits properly still gives up in the end, so the message
    alone cannot tell a fresh budget from an exhausted one. Count the scans instead.
]]
local function CountScans()
    local realGetAutoSellItems = IM.Filters.GetAutoSellItems
    local scans = 0
    IM.Filters.GetAutoSellItems = function(...)
        scans = scans + 1
        return realGetAutoSellItems(...)
    end
    return function() return scans end
end

-- Open a merchant the way the client does, including the 0.2s sell timer.
local function OpenMerchant()
    MerchantFrame.shown = true
    Stub.Fire("MERCHANT_SHOW")
    Stub.DrainTimers()
end

local function CloseMerchant()
    MerchantFrame.shown = false
    Stub.Fire("MERCHANT_CLOSED")
    Stub.DrainTimers()
end

-- ============================================================================
-- 1. The quality floor, against the real Filters.lua
-- ============================================================================

RunSection("Quality floor (real Filters.lua)", function()

    local PROTECTED_QUALITIES = { 5, 6, 7, 8 }
    local QUALITY_NAMES = { [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom", [8] = "WoW Token" }

    for _, quality in ipairs(PROTECTED_QUALITIES) do
        local soldAtSomeSetting, junkSoldAtSomeSetting = false, false

        for maxQuality = 0, 4 do
            -- Plain: protected purely by the floor.
            Reset()
            Stub.DefineItem(SELLABLE, { quality = quality, sellPrice = 5000, classID = 4 })
            Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
            IM.db.global.autoSellEnabled = true
            IM.db.global.autoSell.maxQuality = maxQuality
            OpenMerchant()
            Stub.DrainTimers()
            if SoldCount() > 0 then soldAtSomeSetting = true end

            -- On the junk list, which overrides every protection BELOW the floor.
            Reset()
            Stub.DefineItem(SELLABLE, { quality = quality, sellPrice = 5000, classID = 4 })
            Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
            IM.db.global.autoSellEnabled = true
            IM.db.global.autoSell.maxQuality = maxQuality
            IM.db.global.junkList[SELLABLE] = true
            OpenMerchant()
            Stub.DrainTimers()
            if SoldCount() > 0 then junkSoldAtSomeSetting = true end
        end

        check("quality " .. quality .. " (" .. QUALITY_NAMES[quality] .. ") is never sold at any maxQuality",
            not soldAtSomeSetting)
        check("quality " .. quality .. " is never sold even on the junk list",
            not junkSoldAtSomeSetting)
    end

    -- The floor must not protect everything: a suite where nothing ever sells passes every check
    -- above for the wrong reason.
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    IM.db.global.autoSell.maxQuality = 2
    OpenMerchant()
    Stub.DrainTimers()
    check("a Poor-quality item with a vendor price IS sold", SoldCount() == 1, Prints())

    -- An item whose data has not arrived has nil quality and must fail closed.
    Reset()
    Stub.PutItem(0, 1, { itemID = UNCACHED, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.DrainTimers(200)
    check("an uncached item is never sold", SoldCount() == 0, Prints())
    check("...and the stop is reported as waiting on data, not as nothing to sell",
        Printed("still loading"), Prints())

    -- The other half of that guard: an item that reports a name but no quality. GetItemInfo is not
    -- believed to do this, and the floor refuses it anyway, because the cost of being wrong about a
    -- 14-return-value API is a destroyed asset.
    Reset()
    Stub.DefineItem(SELLABLE, { quality = Stub.NO_QUALITY, sellPrice = 5000, classID = 4 })
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.DrainTimers(200)
    check("an item whose quality is missing but whose name is not is never sold",
        SoldCount() == 0, Prints())

    -- Two guards refuse that item - the explicit nil branch and IsProtectedByQuality's own non-number
    -- check - so the sale outcome alone cannot tell whether both are still there. What only the
    -- explicit branch produces is the PENDING signal, which is what makes the refusal retryable once
    -- the data lands instead of permanent.
    local floored, flooredReason, flooredPending =
        IM.Filters:ShouldAutoSell(0, 1, SELLABLE, Stub.ItemLink(SELLABLE))
    check("...and the refusal is reported as pending, so it is retried when data arrives",
        floored == false and flooredPending == true, tostring(flooredReason) .. "/" .. tostring(flooredPending))

    --[[
        The clamp's own branches, observed on the functions rather than through a sale.

        Four defensive branches here survived the whole suite being deleted one at a time, and the
        producer is that ShouldAutoSell's floor tier masks them: with the floor refusing everything
        above MAX_SELLABLE_QUALITY, GetMaxSellQuality can return 0, 4 or 7 and the sale outcome is
        identical in every scenario the sections below construct. A guard whose only observable is
        masked by a second guard is a guard no sale-level case can lock, so these ask the two
        functions directly.
    ]]
    Reset()
    local okNil, protectedNil = pcall(function() return IM.Filters:IsProtectedByQuality(nil) end)
    check("IsProtectedByQuality fails closed on a nil quality",
        okNil and protectedNil == true, okNil and tostring(protectedNil) or tostring(protectedNil))

    local okText, protectedText = pcall(function() return IM.Filters:IsProtectedByQuality("4") end)
    check("IsProtectedByQuality fails closed on a quality that arrived as text",
        okText and protectedText == true, okText and tostring(protectedText) or tostring(protectedText))

    check("a real sellable quality is not protected by the floor",
        IM.Filters:IsProtectedByQuality(IM.MAX_SELLABLE_QUALITY) == false)
    check("...and one above it is",
        IM.Filters:IsProtectedByQuality(IM.MAX_SELLABLE_QUALITY + 1) == true)

    -- No database at all. The narrowest setting the UI can express, never the widest: a fallback
    -- that resolves to MAX_SELLABLE_QUALITY would sell everything up to Epic on a profile that has
    -- not loaded yet.
    Reset()
    local savedDB = IM.db
    IM.db = nil
    local okNoDB, noDBQuality = pcall(function() return IM.Filters:GetMaxSellQuality() end)
    IM.db = savedDB
    check("GetMaxSellQuality falls back to QUALITY_POOR when there is no database",
        okNoDB and noDBQuality == IM.QUALITY_POOR, tostring(noDBQuality))

    Reset()
    IM.db.global.autoSell = nil
    check("...and when the autoSell table is missing",
        IM.Filters:GetMaxSellQuality() == IM.QUALITY_POOR, tostring(IM.Filters:GetMaxSellQuality()))

    -- The upper clamp. A profile written by an older build can already hold 5, 6 or 7, and the
    -- stored value is deliberately never rewritten, so the clamp on the read is the only thing
    -- standing between that value and anything that renders or reasons about it.
    for _, stored in ipairs({ 5, 6, 7, 99 }) do
        Reset()
        IM.db.global.autoSell.maxQuality = stored
        check("a stored maxQuality of " .. stored .. " reads back clamped to MAX_SELLABLE_QUALITY",
            IM.Filters:GetMaxSellQuality() == IM.MAX_SELLABLE_QUALITY,
            tostring(IM.Filters:GetMaxSellQuality()))
    end

    -- The lower clamp, the same way.
    for _, stored in ipairs({ -1, -100 }) do
        Reset()
        IM.db.global.autoSell.maxQuality = stored
        check("a stored maxQuality of " .. stored .. " reads back clamped to QUALITY_POOR",
            IM.Filters:GetMaxSellQuality() == IM.QUALITY_POOR,
            tostring(IM.Filters:GetMaxSellQuality()))
    end

    -- A stored value already inside the range is returned untouched, so the two clamps above
    -- cannot be passed by a function that simply always answers the same number.
    Reset()
    IM.db.global.autoSell.maxQuality = 3
    check("a stored maxQuality inside the range is returned unchanged",
        IM.Filters:GetMaxSellQuality() == 3, tostring(IM.Filters:GetMaxSellQuality()))

    --[[
        The plan's smoke line, offline: "a previously-stored 5/6/7 does not resurrect a sale".

        It is the FLOOR that refuses these, not the clamp - which is the whole reason the clamp's
        branches are checked directly above instead of through a vendor. The line is still worth
        locking as a pair, because the claim a user cares about is about the pair.
    ]]
    for _, stored in ipairs({ 5, 6, 7 }) do
        Reset()
        Stub.DefineItem(SELLABLE, { quality = stored, sellPrice = 5000, classID = 4 })
        Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
        IM.db.global.autoSellEnabled = true
        IM.db.global.autoSell.maxQuality = stored   -- a value only an older build could have written
        OpenMerchant()
        Stub.DrainTimers()
        check("a stored maxQuality of " .. stored .. " does not resurrect a quality-" .. stored ..
            " sale", SoldCount() == 0, Prints())
    end
end)

-- ============================================================================
-- 2. The master toggle is the whole permission
-- ============================================================================

--[[
    autoSellEnabled, off by default, is what a fresh install has instead of a prompt: nothing can
    be vendored until the user opens the settings and switches it on. Once they have, the addon
    sells at a vendor without asking, because "may I sell at vendors" is the question the setting
    already answered - asking it again every session would turn an automatic feature into a
    two-click manual one.
]]
RunSection("The master toggle is the whole permission", function()

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    check("autoSellEnabled defaults to false", IM.db.global.autoSellEnabled == false)
    OpenMerchant()
    Stub.DrainTimers()
    check("a fresh profile sells nothing on the first merchant visit", SoldCount() == 0, Prints())

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    check("with the setting on, MERCHANT_SHOW sells what the filter approves and asks nothing",
        SoldCount() == 1, Prints())
    check("...and says what it sold", Printed("Sold 1 items for"), Prints())

    -- Every later vendor too. There is no per-session state left to go stale, so the second visit
    -- behaves exactly like the first.
    CloseMerchant()
    Stub.PutItem(0, 1, { itemID = SELLABLE_2, stackCount = 1 })
    OpenMerchant()
    check("a second merchant visit sells the same way, with no session state in between",
        SoldCount() == 2, table.concat(SoldIDs(), ","))

    -- Switching it back off stops the automatic path dead...
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = false
    OpenMerchant()
    Stub.DrainTimers()
    check("switching the setting off stops the merchant-open sale", SoldCount() == 0, Prints())

    -- ...but never the button the player is looking at: Sell All is a sale they asked for by hand,
    -- on the list the popup is showing them, and the setting governs the unattended path only.
    IM.prints = {}
    AutoSell:SellJunk()
    Stub.DrainTimers()
    check("...and leaves Sell All working, because that is a sale asked for by hand",
        SoldCount() == 1, Prints())
end)

-- ============================================================================
-- 3. The sale loop re-validates immediately before the vendor call
-- ============================================================================

RunSection("The sale loop re-validates before every vendor call", function()

    --[[
        ProcessNextItem re-asks Filters:ShouldAutoSell for each queued item immediately before
        handing its slot to C_Container.UseContainerItem. The queue is built from one scan and
        drained over many frames, and a whitelist edit or a bag move can land in between - so with
        no dialog left to pause at, this re-validation is the last thing between the filter and the
        vendor.

        Driven through Stub.onSell, which fires inside the first sale: that is the only moment a
        change can land in a queue that has already been built.
    ]]

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    Stub.onSell = function(bagID, slotID)
        -- The player alt-clicks the second item while the first one is going to the vendor.
        if bagID == 0 and slotID == 1 then IM.db.global.whitelist[SELLABLE_2] = true end
    end
    OpenMerchant()
    Stub.DrainTimers()
    check("an item locked after the queue was built is not sold",
        SoldCount() == 1 and SoldIDs()[1] == SELLABLE, table.concat(SoldIDs(), ","))
    check("...and is still in the bag",
        (C_Container.GetContainerItemInfo(0, 2) or {}).itemID == SELLABLE_2)

    -- The control: the identical queue with nothing changed mid-sale vendors both items, so the
    -- case above cannot pass because the second item was never going to be sold anyway.
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.DrainTimers()
    check("...while the same queue with nothing changed sells both",
        SoldCount() == 2, table.concat(SoldIDs(), ","))
end)

-- ============================================================================
-- 4. The setting is re-read where the queue is built and on every item of the drain
-- ============================================================================

RunSection("The setting is re-read where the queue is built and while it drains", function()

    --[[
        Three windows separate "auto-sell is on" from an item reaching the vendor: the item-data
        retry (up to a whole retry budget of deadlines later), FinishSelling's post-sale sweep
        (0.2s), and the drain of the queue itself (0.15s per item, longer on a locked slot). A
        player who unticks auto-sell inside any of them has withdrawn the only permission that sale
        had, and a check living at the schedulers cannot see that - the round that added the retry
        added a sale-start path and no check with it. So the setting is read in SellJunk, where the
        queue is built and which every sale-start path must traverse, and again in ProcessNextItem,
        which every item must traverse.
    ]]

    local LATE = 555  -- data has not arrived yet, so the first scan finds nothing and waits

    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = LATE, stackCount = 1 })
    Stub.Fire("MERCHANT_SHOW")
    -- Exactly one round: the 0.2s sell timer runs and arms the wait; the wait's own deadline is
    -- queued and deliberately left pending, which is the window this case is about.
    Stub.DrainTimers(1)
    check("nothing has sold yet - the automatic path is waiting on item data",
        SoldCount() == 0, table.concat(SoldIDs(), ","))

    -- Mid-wait: the data lands AND the player unticks auto-sell.
    Stub.DefineItem(LATE, { quality = 0, sellPrice = 100, classID = 4 })
    IM.db.global.autoSellEnabled = false
    Stub.DrainTimers()
    check("a retry that comes due after the setting was switched off sells nothing",
        SoldCount() == 0, table.concat(SoldIDs(), ","))

    -- The same wait with the setting left alone DOES sell once the data lands, so the case above
    -- cannot pass because the retry never came due at all.
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = LATE, stackCount = 1 })
    Stub.Fire("MERCHANT_SHOW")
    Stub.DrainTimers(1)
    Stub.DefineItem(LATE, { quality = 0, sellPrice = 100, classID = 4 })
    Stub.DrainTimers()
    check("...while the same retry with the setting left on does sell",
        SoldCount() == 1 and SoldIDs()[1] == LATE, table.concat(SoldIDs(), ","))

    --[[
        The other side of the same chokepoint: the post-sale sweep.

        FinishSelling arms the sweep and the sale starts 0.2s later, so the state it acted on is
        200ms old. Driven a round at a time rather than by a wall clock: the sweep is armed in the
        round after the sale loop ends, which is the first round that leaves a timer queued with no
        sale running.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    -- Lands during the sale, so it is not in the queue: FinishSelling finds it and arms the sweep.
    Stub.onSell = function()
        Stub.onSell = nil
        Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    end
    Stub.Fire("MERCHANT_SHOW")

    local switchedOff = false
    for _ = 1, 60 do
        if Stub.PendingTimerCount() == 0 then break end
        Stub.DrainTimers(1)
        if not switchedOff and not AutoSell:IsSelling() and Stub.PendingTimerCount() > 0 then
            IM.db.global.autoSellEnabled = false
            switchedOff = true
        end
    end
    check("the sweep window was actually reached and the setting switched off inside it",
        switchedOff, Prints())
    check("a sweep that comes due after the setting was switched off sells nothing more",
        SoldCount() == 1 and SoldIDs()[1] == SELLABLE, table.concat(SoldIDs(), ","))

    -- The control again: the same straggler with the setting left on IS swept.
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.onSell = function()
        Stub.onSell = nil
        Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    end
    OpenMerchant()
    Stub.DrainTimers()
    check("...while the same sweep with the setting left on takes the straggler",
        SoldCount() == 2, table.concat(SoldIDs(), ","))

    -- A hand-clicked sale never sweeps, whatever the setting says: the user was shown a list and
    -- clicked it, and an item that became eligible afterwards was not on that list.
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.onSell = function()
        Stub.onSell = nil
        Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    end
    MerchantFrame.shown = true
    IM.prints = {}
    AutoSell:SellJunk()
    Stub.DrainTimers()
    check("a manual Sell All does not sweep items the user never saw",
        SoldCount() == 1 and SoldIDs()[1] == SELLABLE, table.concat(SoldIDs(), ","))
    check("...and says so, with a count and the button that would take them",
        Printed("started by hand") and Printed("click Sell All"), Prints())

    --[[
        The third window, and the longest: the drain.

        The two above are gaps between scheduling a sale and starting it. This one is a sale
        already running - 0.15s per item and longer whenever a slot is locked, so a bag of junk is
        several seconds of vendoring with the merchant frame open and the settings panel reachable
        throughout. A check that only ran where the queue was BUILT would let the whole rest of the
        queue go after the permission was withdrawn, which is the largest of the three exposures.
    ]]
    local function RemainingInBags(fromSlot, toSlot)
        local remaining = 0
        for slot = fromSlot, toSlot do
            if C_Container.GetContainerItemInfo(0, slot) then remaining = remaining + 1 end
        end
        return remaining
    end

    Reset()
    IM.db.global.autoSellEnabled = true
    for slot = 1, 6 do Stub.PutItem(0, slot, { itemID = SELLABLE, stackCount = 1 }) end
    Stub.onSell = function()
        Stub.onSell = nil       -- the player unticks the setting during the first vendor call
        IM.db.global.autoSellEnabled = false
    end
    OpenMerchant()
    Stub.DrainTimers()
    check("unticking auto-sell mid-drain stops the queue where it stands",
        SoldCount() == 1, table.concat(SoldIDs(), ","))
    check("...leaving every item it had not reached yet in the bags",
        RemainingInBags(2, 6) == 5, "remaining=" .. RemainingInBags(2, 6))
    check("...and says so, because a sale that stops halfway without a word reads as a bug",
        Printed("switched off during the sale") and Printed("5 item(s) left in your bags"), Prints())
    check("...while still reporting the part that did sell",
        Printed("Sold 1 items for"), Prints())

    -- The control: the identical queue with the setting left alone drains all six, so the case
    -- above cannot pass because the queue was never going to get past its first item.
    Reset()
    IM.db.global.autoSellEnabled = true
    for slot = 1, 6 do Stub.PutItem(0, slot, { itemID = SELLABLE, stackCount = 1 }) end
    OpenMerchant()
    Stub.DrainTimers()
    check("...while the same queue with the setting left on drains all six",
        SoldCount() == 6, table.concat(SoldIDs(), ","))
end)
-- ============================================================================
-- 5. Retry budgets are not shared between the addon and the user
-- ============================================================================

RunSection("Retry budgets", function()

    -- SCAN_CEILING is a loose upper bound, not the retry budget restated: the property under test
    -- is "it stops", and a bound that tracked the budget exactly would be a second, hand-maintained
    -- copy of a number that already lives in AutoSell.lua. Anything at or below this is bounded;
    -- an unterminated loop blows straight past it.
    local SCAN_CEILING = 20

    Reset()
    Stub.PutItem(0, 1, { itemID = UNCACHED, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    local automaticScans = CountScans()
    OpenMerchant()
    Stub.DrainTimers(200)
    check("the automatic path gives up out loud when item data never arrives",
        Printed("gave up waiting"), Prints())
    check("...after spending its budget rather than looping forever",
        automaticScans() > 1 and automaticScans() <= SCAN_CEILING, "scans=" .. automaticScans())

    IM.prints = {}
    local manualScans = CountScans()
    AutoSell:SellJunk(false)
    Stub.DrainTimers(200)
    check("the user's first manual click gets its own attempts, not the automatic path's empty budget",
        manualScans() > 1, "scans=" .. manualScans())
    check("...and those attempts are bounded too",
        manualScans() <= SCAN_CEILING, "scans=" .. manualScans())
    check("...and it says so when they run out", Printed("gave up waiting"), Prints())

    -- A second click is a second explicit request, so it gets attempts again rather than being
    -- refused instantly on the back of the first one.
    IM.prints = {}
    local secondClickScans = CountScans()
    AutoSell:SellJunk(false)
    Stub.DrainTimers(200)
    check("a second manual click is not refused on the first click's spent budget",
        secondClickScans() > 1, "scans=" .. secondClickScans())

    -- A new merchant visit refills the automatic budget; the flag must never wedge.
    Reset()
    Stub.PutItem(0, 1, { itemID = UNCACHED, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.DrainTimers(200)
    CloseMerchant()
    IM.prints = {}
    OpenMerchant()
    Stub.DrainTimers(200)
    check("a new merchant visit refills the automatic retry budget",
        Printed("gave up waiting"), Prints())
end)

-- ============================================================================
-- 6. Guards that must survive being deleted
-- ============================================================================

RunSection("Guards nothing else covers", function()

    --[[
        The slot identity check in ProcessNextItem, in the window it actually exists for.

        The window it owns is mid-queue: the sale is running, item one has gone to the merchant,
        and something lands in item two's slot during the 0.15s timer between the two sales.
        Nothing re-scans after that point, so the per-item check is all there is.

        The intruder is Legendary, which the floor refuses at every setting, and that is what makes
        the case bite: the filter re-check underneath is asked about the QUEUED itemID, not about
        whatever is in the slot now, so with the identity check gone it approves the sale of an item
        that is no longer there and UseContainerItem vendors a protected one. An intruder the filter
        would have taken anyway proves nothing here - the post-sale sweep would sell it a moment
        later, legitimately, and the two outcomes are indistinguishable in the sale record.
    ]]
    local INTRUDER = 444

    Reset()
    Stub.DefineItem(INTRUDER, { quality = 5, sellPrice = 100, classID = 4 })
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    Stub.onSell = function(bagID, slotID)
        if bagID == 0 and slotID == 1 then
            -- Lands while the inter-sale timer is pending, mid-queue.
            C_Timer.After(0.05, function()
                Stub.PutItem(0, 2, { itemID = INTRUDER, stackCount = 1 })
            end)
        end
    end
    OpenMerchant()
    Stub.DrainTimers()

    local soldIntruder = false
    for _, id in ipairs(SoldIDs()) do
        if id == INTRUDER then soldIntruder = true end
    end
    check("an item that lands in a queued slot mid-sale is not sold in the queued item's place",
        not soldIntruder, table.concat(SoldIDs(), ","))
    check("...and the queued item that was still there was sold",
        SoldCount() == 1 and SoldIDs()[1] == SELLABLE, table.concat(SoldIDs(), ","))
    check("...and the intruder is still in the bag",
        (C_Container.GetContainerItemInfo(0, 2) or {}).itemID == INTRUDER)

    --[[
        The same window, one step subtler: the intruder is the SAME itemID.

        Bonus IDs make one itemID several items. The identity check compares itemIDs, so a
        higher-ilvl variant swapped into a queued slot passes it - and everything after that has to
        be asked about the LIVE link, not the link the queue was built from, or the maxItemLevel
        ceiling gets applied to the variant that is no longer there.

        The ceiling is the owner's stated guard ("never sell items over 290"), so the scenario is
        his: a 100-ilvl piece is queued, a 500-ilvl piece of the same itemID lands in the slot
        mid-drain, and the ceiling has to refuse the thing actually in the slot.
    ]]
    local UPGRADE = 333
    local HIGH_ILVL_LINK = "|Hitem:333::::::::::::1:9999|h[Item 333 (upgraded)]|h"

    Reset()
    Stub.DefineItem(UPGRADE, { quality = 2, sellPrice = 5000, classID = 4, itemLevel = 100 })
    Stub.DefineVariant(HIGH_ILVL_LINK, { quality = 2, sellPrice = 5000, classID = 4, itemLevel = 500 })
    IM.db.global.autoSellEnabled = true
    IM.db.global.autoSell.maxItemLevel = 290
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = UPGRADE, stackCount = 1 })   -- queued at ilvl 100, below the ceiling
    Stub.onSell = function(bagID, slotID)
        if bagID == 0 and slotID == 1 then
            Stub.onSell = nil
            C_Timer.After(0.05, function()
                Stub.PutItem(0, 2, { itemID = UPGRADE, stackCount = 1, hyperlink = HIGH_ILVL_LINK })
            end)
        end
    end
    OpenMerchant()
    Stub.DrainTimers()

    local soldUpgrade = false
    for _, id in ipairs(SoldIDs()) do
        if id == UPGRADE then soldUpgrade = true end
    end
    check("a higher-ilvl variant of the queued itemID is judged on the link in the slot, not the queued one",
        not soldUpgrade, table.concat(SoldIDs(), ","))
    check("...so the item-level ceiling still refuses it and it stays in the bag",
        (C_Container.GetContainerItemInfo(0, 2) or {}).itemID == UPGRADE)

    -- The control: the same queue with no swap sells the 100-ilvl piece, so the case above cannot
    -- pass because the ceiling was refusing that slot all along.
    Reset()
    Stub.DefineItem(UPGRADE, { quality = 2, sellPrice = 5000, classID = 4, itemLevel = 100 })
    IM.db.global.autoSellEnabled = true
    IM.db.global.autoSell.maxItemLevel = 290
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = UPGRADE, stackCount = 1 })
    OpenMerchant()
    Stub.DrainTimers()
    check("...while the same queue left alone sells it, because 100 is under the ceiling",
        SoldCount() == 2, table.concat(SoldIDs(), ","))

    -- Both hand-driven entry points sell the list in the bags right now.
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    MerchantFrame.shown = true
    SlashCmdList["INVENTORYMANAGER"]("sell")
    Stub.DrainTimers()
    check("/im sell sells the items in the bags", SoldCount() == 1, Prints())

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    MerchantFrame.shown = true
    AutoSell:SellJunk()
    Stub.DrainTimers()
    check("a manual SellJunk() sells the items in the bags", SoldCount() == 1, Prints())

    --[[
        ...and the binding half, by clicking the shipping button rather than reading its source.

        This is the wired-up consumer of the rule the section above states: the setting gates the
        unattended path, and Sell All keeps working while it is off. Checking that by grepping
        AutoSellPopup.lua for the literal `AutoSell:SellJunk()` proves only that the text is still
        in the file - wrap the handler in `if IM.db.global.autoSellEnabled then` and the literal
        survives, the grep passes, and the escape hatch is silently gated.

        So the UI layer is loaded here (only here) and the button's real OnClick closure is called
        with the setting OFF. Residual, stated rather than implied: the frame stub answers every
        method, so this proves what the click DOES, never that the button draws, is enabled, or is
        reachable on screen.
    ]]
    Reset()
    Stub.LoadUI()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = false
    MerchantFrame.shown = true

    local popup = IM.UI.AutoSellPopup:Create()
    local onClick = popup.sellBtn and popup.sellBtn:GetScript("OnClick")
    check("the popup's Sell All button has a click handler to drive", type(onClick) == "function",
        type(onClick))
    if type(onClick) == "function" then
        onClick(popup.sellBtn)
        Stub.DrainTimers()
    end
    check("clicking Sell All sells while auto-sell is switched off, because it is a sale asked for by hand",
        SoldCount() == 1, Prints())

    --[[
        MERCHANT_CLOSED drops anything waiting on item data.

        A wait armed at one vendor that comes due at the next one starts a sale the player never
        stood in front of. The window is opened here WITHOUT firing MERCHANT_SHOW, deliberately:
        with the show path running, its own sale would mask the stale waiter's, and the thing under
        test is whether the waiter survived the close at all.
    ]]
    local LATE = 666
    Reset()
    IM.db.global.autoSellEnabled = true

    -- First vendor of the pair: the bags hold only an item whose data has not arrived, so the
    -- automatic path arms a wait rather than selling.
    Stub.PutItem(0, 1, { itemID = LATE, stackCount = 1 })
    MerchantFrame.shown = true
    Stub.Fire("MERCHANT_SHOW")
    Stub.DrainTimers(1)
    check("the first vendor armed a wait and sold nothing", SoldCount() == 0, table.concat(SoldIDs(), ","))

    -- Walk away and stand at another vendor, inside the wait's own deadline - the timers are NOT
    -- drained across the close, because a waiter that has already come due and found no merchant
    -- is a waiter that can no longer reach the next vendor, and that is not the case under test.
    MerchantFrame.shown = false
    Stub.Fire("MERCHANT_CLOSED")
    Stub.DefineItem(LATE, { quality = 0, sellPrice = 100, classID = 4 })
    MerchantFrame.shown = true
    IM.prints = {}
    Stub.DrainTimers()
    check("a wait armed at one vendor does not come due as a sale at the next",
        SoldCount() == 0, table.concat(SoldIDs(), ","))

    --[[
        A second Sell All while the first is still draining.

        Two queues over the same bag slots is a second sale trying to vendor slots the first one
        has already emptied. It is refused rather than allowed to start, and the refusal is
        reported so the caller can say something other than "nothing happened".

        Timers here are drained in rounds rather than by a clock, one queued item per round, so
        stopping after a single round leaves the sell loop mid-queue with its next timer pending -
        which is the only state in which a second click can meet a live sale.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 3, { itemID = SELLABLE, stackCount = 1 })
    MerchantFrame.shown = true
    AutoSell:SellJunk()          -- the popup's Sell All: slot 1 goes, the queue keeps running
    Stub.DrainTimers(1)          -- one round: the sale advances and stays mid-queue
    check("the sale is still running after one round", AutoSell:IsSelling(), Prints())

    local soldMidSale = SoldCount()
    local busyStarted, busyReason = AutoSell:SellJunk()
    check("a second Sell All during that sale is refused as already-selling",
        busyStarted == false and busyReason == "already-selling", tostring(busyReason))
    check("...and vendors nothing on top of the running queue",
        SoldCount() == soldMidSale, table.concat(SoldIDs(), ","))

    Stub.DrainTimers()           -- the running sale finishes
    check("...and the running sale still gets through its own queue",
        SoldCount() == 3, table.concat(SoldIDs(), ","))

    --[[
        MERCHANT_SHOW refills the automatic retry budget even with no intervening close.

        The reset is unconditional for exactly this case: some vendors fire MERCHANT_SHOW again for
        a window already on screen, and a visit that spent its attempts waiting on item data must
        not leave the re-fire unable to retry at all. A close would refill it too, which is why the
        Open-Close-Open shape cannot tell whether this line is doing anything.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = UNCACHED, stackCount = 1 })
    OpenMerchant()
    Stub.DrainTimers(200)        -- budget spent at this vendor
    IM.prints = {}
    local refireScans = CountScans()
    Stub.Fire("MERCHANT_SHOW")   -- same window, no MERCHANT_CLOSED in between
    Stub.DrainTimers(200)
    check("a MERCHANT_SHOW re-fire with no intervening close can still retry",
        refireScans() > 1, "scans=" .. refireScans())
end)

-- ============================================================================
-- 7. The post-sale line cannot overstate what buyback still holds
-- ============================================================================

--[[
    The buyback tab holds only the client's most recent entries. Sell more stacks in one session
    than it holds and the post-sale line must not read as a promise that every item just sold is
    still sitting there - the older ones may already have fallen off the list.

    It states no number at all, which is why no client constant is set up here: itemCount sums item
    units across stacks while a buyback entry is one stack, so any count quoted beside it would
    invite a comparison that does not hold. The sale below uses a stack size of 4 to keep those two
    units visibly different.

    This case was checked red before it was checked green: restoring the old wording ("they are in
    this vendor's Buyback tab ... if you want any of them back") fails the second check below, which
    is what makes the assertion a lock on the defect rather than a tautology that would pass no
    matter what shipped.
]]
RunSection("The post-sale line does not overstate what buyback still holds", function()

    Reset()
    IM.db.global.autoSellEnabled = true
    for slot = 1, 5 do
        Stub.PutItem(0, slot, { itemID = SELLABLE, stackCount = 4 })
    end
    OpenMerchant()
    Stub.DrainTimers()

    check("all 5 stacks actually sold, so the scenario exercises the overstatement rather than a no-op",
        SoldCount() == 5, table.concat(SoldIDs(), ","))
    check("the post-sale line does not promise every item just sold is still retrievable",
        not Printed("if you want any of them back"), Prints())
    check("...it scopes the claim instead: only the most recent entries, older ones may be gone",
        Printed("only the most recently sold items are still in this vendor's Buyback tab") and
        Printed("earlier ones may already be gone"), Prints())
    check("...and quotes no buyback capacity beside the count - itemCount is stack units, not slots",
        not Printed("items at a time"), Prints())
end)

-- ============================================================================
-- 8. The auto-sell settings dropdown derives its quality list
-- ============================================================================

--[[
    UI/Panels/AutoSell.lua builds its dropdown by looping IM.QUALITY_INFO up to
    IM.MAX_SELLABLE_QUALITY. It is derived because a hand-written copy of that list went on
    offering Legendary, Artifact and Heirloom long after Filters:IsProtectedByQuality had stopped
    honouring them - the settings panel promising a sale the filter always refuses.

    Core.lua IS loaded here, so the accessors it derives FROM are executed rather than described.
    The panel itself needs the UI layer, which is not loaded, so its list is read out of the
    shipping file the same way the Sell All button's handler is: what is checked is that it still
    derives, and that it names no quality the floor refuses.
]]
RunSection("The quality dropdown derives its list", function()

    local gap, mismatch
    for quality = IM.QUALITY_POOR, IM.MAX_SELLABLE_QUALITY do
        local info = IM:GetQualityInfo(quality)
        if type(info) ~= "table" or type(info.name) ~= "string" or type(info.colorName) ~= "string"
            or type(info.hex) ~= "string" then
            gap = gap or quality
        elseif IM:GetQualityName(quality) ~= info.name or IM:GetQualityColorHex(quality) ~= info.hex then
            mismatch = mismatch or quality
        end
    end
    check("every quality from Poor up to MAX_SELLABLE_QUALITY has a complete QUALITY_INFO entry",
        gap == nil, "first gap at " .. tostring(gap))
    check("...and the accessors answer each of them out of that entry",
        mismatch == nil, "first mismatch at " .. tostring(mismatch))

    -- The floor is what ends the list, not a missing entry: the qualities above it are described
    -- here too, and are absent from the dropdown because the loop stops.
    check("QUALITY_INFO describes the qualities above the floor as well",
        IM:GetQualityInfo(IM.MAX_SELLABLE_QUALITY + 1) ~= nil)

    check("GetQualityName answers 'Unknown' for an index the addon does not know",
        IM:GetQualityName(99) == "Unknown", IM:GetQualityName(99))

    -- Colour is asked for while drawing a row, so a raise here is a settings panel that will not
    -- open. It falls back rather than indexing nil.
    local okHex, hex = pcall(function() return IM:GetQualityColorHex(99) end)
    check("GetQualityColorHex falls back to Common rather than raising on an unknown index",
        okHex and hex == IM:GetQualityInfo(IM.QUALITY_COMMON).hex, tostring(hex))
    check("...and returns a bare six-digit hex, so callers add their own |cff exactly once",
        (IM:GetQualityColorHex(IM.QUALITY_EPIC)):match("^%x%x%x%x%x%x$") ~= nil,
        IM:GetQualityColorHex(IM.QUALITY_EPIC))

    local source
    do
        local file = io.open("UI/Panels/AutoSell.lua")
        if not file then
            check("the auto-sell settings panel source is readable from the harness", false,
                "run the suite from the repo root")
        else
            source = file:read("*a")
            file:close()
        end
    end

    -- Comments are stripped first. The block above the list explains WHY Legendary and friends are
    -- absent, and a scan that could not tell that explanation from a table entry would either fail
    -- on it or force it to be deleted - which is how a derivation loses the note saying why it is
    -- a derivation.
    local code = (source or "")
        :gsub("%-%-%[%[.-%]%]", " ")
        :gsub("%-%-[^\n]*", " ")

    check("the dropdown's list is built by a loop that stops at MAX_SELLABLE_QUALITY",
        code:find("for quality = IM.QUALITY_POOR, IM.MAX_SELLABLE_QUALITY do", 1, true) ~= nil,
        "no derived loop in the panel")
    check("...filling each entry from Core.lua's accessors rather than a table written there",
        code:find("IM:GetQualityInfo(quality)", 1, true) ~= nil and
        code:find("IM:GetQualityColorHex(quality)", 1, true) ~= nil,
        "no accessor call in the panel")

    -- The mutation this exists for: a hand-written list restored beside the loop, or in place of
    -- it, naming qualities the floor refuses at every setting.
    local named
    for quality = IM.MAX_SELLABLE_QUALITY + 1, IM.QUALITY_TOKEN do
        local name = IM:GetQualityName(quality)
        if code:find(name, 1, true) then named = named or name end
    end
    check("...and the panel's code names no quality the floor refuses",
        named == nil, "found " .. tostring(named))
end)

-- ============================================================================
-- 9. The configured quality threshold, and the junk list overriding it
-- ============================================================================

--[[
    Nothing above this point crosses the CONFIGURED threshold. Every fixture is quality 0 and every
    other sale case runs at a quality the floor refuses, so the setting the auto-sell panel is
    mostly about had no sale-level coverage at all: raising Database.lua's default maxQuality from
    2 to 4 (every fresh profile silently vendoring up to Epic) and deleting ShouldAutoSell's
    threshold tier outright both left the suite green.

    Quality 3 is the item that can tell them apart: under the floor, over the default. The first
    case deliberately does NOT set maxQuality - it is the shipped default that has to refuse this
    item, which is what makes the default itself load-bearing here.
]]
RunSection("The configured quality threshold, and junk overriding it", function()

    local RARE = 777

    Reset()
    Stub.DefineItem(RARE, { quality = 3, sellPrice = 5000, classID = 4 })
    Stub.PutItem(0, 1, { itemID = RARE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.DrainTimers()
    check("a Rare item is not sold at the default maxQuality", SoldCount() == 0, Prints())

    Reset()
    Stub.DefineItem(RARE, { quality = 3, sellPrice = 5000, classID = 4 })
    Stub.PutItem(0, 1, { itemID = RARE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    IM.db.global.autoSell.maxQuality = 4
    OpenMerchant()
    Stub.DrainTimers()
    check("...and the same item IS sold once maxQuality is raised to Epic",
        SoldCount() == 1, Prints())

    --[[
        Junk, in the direction that can break.

        The junk checks in section 1 all sit ABOVE the floor, where the item is refused either way,
        so they pass with the junk tier deleted outright. What the user actually bought with a
        manual junk designation is this: an item the normal filters WOULD refuse sells anyway.
    ]]
    Reset()
    Stub.DefineItem(RARE, { quality = 3, sellPrice = 5000, classID = 4 })
    Stub.PutItem(0, 1, { itemID = RARE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    IM.db.global.junkList[RARE] = true
    OpenMerchant()
    Stub.DrainTimers()
    check("an item the threshold refuses is sold anyway once the user junk-lists it",
        SoldCount() == 1, Prints())
end)

-- ============================================================================
-- 10. Protective tiers that no sale ever reached
-- ============================================================================

--[[
    Three more tiers of ShouldAutoSell were listed as uncovered rather than covered. All three are
    drivable here - they read the database and GetItemInfo, not a client API the stub answers with
    a constant - so they are driven instead of named.
]]
RunSection("Category exclusions, mail rules and no vendor value", function()

    -- CATEGORY EXCLUSIONS. classID 0 is Consumable, excluded by default.
    local POTION = 888

    Reset()
    Stub.DefineItem(POTION, { quality = 0, sellPrice = 100, classID = 0 })
    Stub.PutItem(0, 1, { itemID = POTION, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.DrainTimers()
    check("an item in an excluded category is not sold", SoldCount() == 0, Prints())

    Reset()
    Stub.DefineItem(POTION, { quality = 0, sellPrice = 100, classID = 0 })
    Stub.PutItem(0, 1, { itemID = POTION, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    IM.db.global.categoryExclusions.consumables = false
    OpenMerchant()
    Stub.DrainTimers()
    check("...and is sold once the user unexcludes that category", SoldCount() == 1, Prints())

    --[[
        MAIL RULES. Not a mail feature from auto-sell's point of view: a rule holding an item for an
        alt is the reason it is not vendored, so the mail settings are auto-sell SCOPE settings.
        The second case is the historical asset-loss shape - widening the sale from the mail panel,
        with no visit to the auto-sell panel to suggest anything changed.
    ]]
    local MATS = 121

    local function _MailRuleFixture()
        Reset()
        Stub.DefineItem(MATS, { name = "Bank Mats", quality = 0, sellPrice = 100, classID = 4 })
        Stub.PutItem(0, 1, { itemID = MATS, stackCount = 1 })
        IM.db.global.autoSellEnabled = true
        IM.db.global.mailHelper.rules = {
            { name = "Mats to the bank alt", alt = "Banker-Realm", filterType = "name",
              filterValue = "Bank Mats", enabled = true },
        }
    end

    _MailRuleFixture()
    OpenMerchant()
    Stub.DrainTimers()
    check("an item a mail rule is holding for an alt is not sold", SoldCount() == 0, Prints())

    _MailRuleFixture()
    IM.db.global.mailHelper.enabled = false
    OpenMerchant()
    Stub.DrainTimers()
    check("...and unticking Mail Helper's master enable widens the sale to take it",
        SoldCount() == 1, Prints())

    -- NO VENDOR VALUE. The control is the standard fixture: same quality, same class, sellPrice
    -- 100, sold in the quality-floor section - so only the price differs here.
    Reset()
    Stub.DefineItem(SELLABLE, { quality = 0, sellPrice = 0, classID = 4 })
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.DrainTimers()
    check("an item the vendor pays nothing for is not sold", SoldCount() == 0, Prints())
end)

-- ---------------------------------------------------------------- summary --

--[[
    The total, pinned.

    RunSection turns a section that RAISES into one named failure. A section that stops early
    WITHOUT raising - a loop over a table somebody emptied, an `if` that quietly stopped matching,
    an early `return` added mid-edit - drops its remaining checks with no trace, and "N checks, 0
    failures" reads exactly like a full run. Two rounds have now shipped cases that passed for the
    wrong reason; a case that never executed at all is the same failure with even less evidence.

    Bump this deliberately when adding or removing cases. A number that had to be changed without
    anyone intending to change it is the signal.
]]
local EXPECTED_CHECKS = 98    -- this assertion included

check("every expected check ran", checks + 1 == EXPECTED_CHECKS,
    "counted=" .. (checks + 1) .. " expected=" .. EXPECTED_CHECKS)

Stub.Say(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
