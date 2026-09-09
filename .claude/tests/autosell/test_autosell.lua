--[[
    Offline behaviour tests for the auto-sell consent gate and the quality floor.

    Run it:
        .claude/tests/autosell/run.sh

    These load the REAL Core.lua, Database.lua, Filters.lua and Modules/AutoSell.lua against
    wow_stub.lua.

    COVERED, as the shipping code rather than a description of it: the quality floor, the stored
    maxQuality clamp (both directions, and its fail-closed fallbacks - asked of GetMaxSellQuality
    directly, because the floor masks it in every sale outcome), the database defaults, the consent
    fingerprint, the approved-list exemption's unforgeability, the sale loop's re-validation,
    Core.lua's quality accessors (IM:GetQualityInfo, IM:GetQualityName, IM:GetQualityColorHex) and
    the settings dropdown deriving its list from them, and the consent dialog - which is answered
    by pressing its buttons, not by calling the handler underneath them, and whose own text is read
    back rather than assumed.

    NOT COVERED, and a change that stops any of them protecting an item will leave this suite
    green:

    - Five of ShouldAutoSell's protective tiers stand on client APIs the stub answers with a
      constant: soulbound (C_Item.IsBound), warbound-until-equip
      (C_Item.IsBoundToAccountUntilEquip), uncollected transmog
      (C_TransmogCollection.PlayerHasTransmog), toys (C_ToyBox.GetToyInfo) and equipment sets
      (C_EquipmentSet).
    - Modules/TooltipInfo.lua is not loaded here. It is a MODULE, not part of the UI layer, so
      "the UI layer is not loaded" does not cover it and nothing below tests it.
    - The UI layer is not loaded either, so UI/AutoSellPopup.lua and the settings panels are
      reached only by reading their source, never by driving them.
    - No claim about the live client can be proven here: buyback lifetime and event ordering at a
      real vendor are in-game checks. The buyback PAGE SIZE is the exception - it is derived from
      Blizzard's constant rather than asserted, so section 9 checks the derivation.
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
    Stub.sold = {}
    Stub.refuseSale = {}
    Stub.shownPopups = {}
    Stub.activePopup = nil
    Stub.refusePopup = false
    Stub.onSell = nil
    MerchantFrame.shown = true

    Stub.LoadAddon()
    AutoSell = IM.modules.AutoSell
    DefineStandardItems()
end

-- Answer a confirm the test expects to be there. A missing one is reported as a named failure and
-- the run continues: a suite that aborts on the first surprise tells you one thing, where the rest
-- of the checks would have told you which guard actually went missing.
local function AnswerConfirm(label, answer, verb)
    if answer() then return true end
    check(label .. ": a confirm was expected to " .. verb .. " but none was shown", false)
    return false
end

local function AcceptConfirm(label) return AnswerConfirm(label, Stub.PopupAccept, "accept") end
local function DeclineConfirm(label) return AnswerConfirm(label, Stub.PopupCancel, "decline") end
local function EscapeConfirm(label) return AnswerConfirm(label, Stub.PopupEscape, "escape") end

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
            -- A protected item produces no eligible list, so usually there is no dialog at all. Accept
            -- one if it appears: "no dialog" must not be the only reason nothing sold.
            if Stub.PopupOnScreen() then Stub.PopupAccept() end
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
            if Stub.PopupOnScreen() then Stub.PopupAccept() end
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
    AcceptConfirm("poor-quality sale")
    Stub.DrainTimers()
    check("a Poor-quality item with a vendor price IS sold once approved", SoldCount() == 1, Prints())

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
    if Stub.PopupOnScreen() then Stub.PopupAccept() end
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
        if Stub.PopupOnScreen() then Stub.PopupAccept() end
        Stub.DrainTimers()
        check("a stored maxQuality of " .. stored .. " does not resurrect a quality-" .. stored ..
            " sale", SoldCount() == 0, Prints())
    end
end)

-- ============================================================================
-- 2. The consent gate, driven through the real dialog
-- ============================================================================

RunSection("Consent gate", function()

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    check("MERCHANT_SHOW with sellable items and no session grant sells nothing",
        SoldCount() == 0, Prints())
    check("...and puts the confirm on screen", Stub.PopupOnScreen())

    AcceptConfirm("first confirm")
    Stub.DrainTimers()
    check("...and pressing Sell on that confirm sells the quoted item", SoldCount() == 1, Prints())

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    DeclineConfirm("declined confirm")
    Stub.DrainTimers()
    check("declining the confirm sells nothing", SoldCount() == 0, Prints())
    check("...and says so", Printed("declined"), Prints())
    check("...and grants nothing", AutoSell:HasSessionConsent() == false)

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    EscapeConfirm("escaped confirm")
    Stub.DrainTimers()
    check("dismissing the confirm with Escape sells nothing and grants nothing",
        SoldCount() == 0 and AutoSell:HasSessionConsent() == false, Prints())

    -- The master toggle. Default is off, and off must mean nothing happens at all.
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    check("autoSellEnabled defaults to false", IM.db.global.autoSellEnabled == false)
    OpenMerchant()
    check("a fresh profile shows no confirm and sells nothing on the first merchant visit",
        SoldCount() == 0 and not Stub.PopupOnScreen(), Prints())

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    AcceptConfirm("second-visit setup")
    Stub.DrainTimers()
    CloseMerchant()
    Stub.PutItem(0, 1, { itemID = SELLABLE_2, stackCount = 1 })
    OpenMerchant()
    check("a second merchant visit in the same session does not re-ask",
        not Stub.PopupOnScreen(), Prints())
    check("...and sells without asking", SoldCount() == 2, table.concat(SoldIDs(), ","))
end)

-- ============================================================================
-- 3. An approved sale is still re-validated against the bags and the filter
-- ============================================================================

RunSection("Approved sales are re-validated", function()

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.PutItem(0, 1, { itemID = SELLABLE_2, stackCount = 1 })  -- different item moved into the slot
    AcceptConfirm("slot holds a different itemID")
    Stub.DrainTimers()
    check("an approved slot now holding a different itemID is not sold", SoldCount() == 0, Prints())
    check("...and no session grant follows a sale that never started",
        AutoSell:HasSessionConsent() == false)

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 5 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 9 })  -- looted into the stack before answering
    AcceptConfirm("stack grew after approval")
    Stub.DrainTimers()
    check("a stack that grew after approval is not sold", SoldCount() == 0, Prints())

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    IM.db.global.whitelist[SELLABLE] = true  -- locked between the dialog and the answer
    AcceptConfirm("item whitelisted after approval")
    Stub.DrainTimers()
    check("an approved item the filter now refuses is not sold", SoldCount() == 0, Prints())

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.PutItem(0, 1, nil)  -- the item leaves the bag before the player answers
    AcceptConfirm("items vanished before answering")
    Stub.DrainTimers()
    check("an approval whose items vanished sells nothing", SoldCount() == 0)
    check("...and records no session grant", AutoSell:HasSessionConsent() == false)
    check("...and says why", Printed("was not approved"), Prints())

    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    MerchantFrame.shown = false
    AcceptConfirm("merchant closed before answering")
    Stub.DrainTimers()
    check("an approval answered after the merchant closed records no grant",
        AutoSell:HasSessionConsent() == false)
    check("...and names the merchant closing rather than an empty list",
        Printed("merchant closed"), Prints())
end)

-- ============================================================================
-- 4. One gate for every sale-start path
-- ============================================================================

RunSection("Sale-start paths share one gate", function()

    --[[
        The re-fire hole, with the timer intact.

        A vendor that fires MERCHANT_SHOW again for a window already on screen used to schedule an
        unbounded SellJunk 0.2s later - at a vendor whose dialog had just said nothing else would be
        sold. The previous suite called ClearTimers() immediately after the re-fire and so discarded
        the exact timer that carried the bug.
    ]]
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    -- A straggler lands after the dialog was drawn, so it is NOT on the approved list and the dialog
    -- has already promised it will not be sold.
    Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    AcceptConfirm("approved sale with a straggler")
    Stub.DrainTimers()
    check("an approved sale sells the approved item and not the straggler beside it",
        SoldCount() == 1 and SoldIDs()[1] == SELLABLE, table.concat(SoldIDs(), ","))
    check("...and the suppressed sweep names the approved list",
        Printed("limited to the list you approved"), Prints())

    local soldAfterApproval = SoldCount()
    IM.prints = {}
    Stub.Fire("MERCHANT_SHOW")   -- re-fire for the window already open
    Stub.DrainTimers()           -- and let its 0.2s timer actually come due
    check("a MERCHANT_SHOW re-fire during an approved visit does not sell the straggler",
        SoldCount() == soldAfterApproval, table.concat(SoldIDs(), ","))
    check("...and does not put a second confirm on screen", not Stub.PopupOnScreen())
    -- The re-fire is the client's, not the player's, and some vendors emit it repeatedly for a
    -- window already on screen. A chat line per re-fire is noise attributable to nothing they did,
    -- so the merchant-open scheduler's visit-bound branch says nothing at all. That silence was
    -- described in a comment and asserted nowhere.
    check("...and says nothing at all, because the player did not do anything",
        #IM.prints == 0, Prints())

    -- The bind belongs to the visit, and the visit ends at MERCHANT_CLOSED. The same straggler is
    -- still in the bag, so the next visit is where the session grant legitimately takes it.
    IM.prints = {}
    CloseMerchant()
    OpenMerchant()
    check("the next merchant visit is no longer bound to the old approval",
        SoldCount() > soldAfterApproval, table.concat(SoldIDs(), ","))
    check("...and does not claim a sale there was limited to a list nobody was shown",
        not Printed("limited to the list you approved"), Prints())

    -- The sweep keys on THIS sale being automatic, not on the session grant.
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    AcceptConfirm("sweep gate setup")
    Stub.DrainTimers()
    CloseMerchant()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    MerchantFrame.shown = true
    IM.prints = {}
    AutoSell:SellJunk(nil, false)   -- hand-clicked Sell All at a vendor visited AFTER consent
    Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    Stub.DrainTimers()
    check("a manual Sell All does not sweep items the user never saw",
        Printed("started by hand"), Prints())

    --[[
        A grant withdrawn while a retry is in flight.

        The item-data retry re-enters SellJunk with no approved list - a full-bag scan, started by
        the addon, up to a whole retry budget's worth of deadlines after the schedulers checked
        anything. If authorization lives at the schedulers, this path carries no check at all: the
        player clicks Clear All on the Whitelist panel during the wait, every locked item stops
        being protected, and the sale that comes due sells them under a grant that no longer holds.

        The check has to live where the queue is built, which is why this case is the chokepoint's.
    ]]
    local LATE = 555  -- data has not arrived yet, so the first scan finds nothing and waits
    Reset()
    IM.db.global.autoSellEnabled = true
    IM.db.global.whitelist[7777] = true   -- something for Clear All to un-protect later
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    AcceptConfirm("grant taken before the retry window")
    Stub.DrainTimers()
    check("the session grant is standing before the retry window opens",
        AutoSell:HasSessionConsent() == true, Prints())
    CloseMerchant()

    -- Next vendor. The only thing in the bags is an item whose data has not arrived, so the
    -- automatic path arms a wait instead of selling. The setup sale above is dropped from the
    -- record so the counts below are about this vendor only.
    Stub.PutItem(0, 1, { itemID = LATE, stackCount = 1 })
    MerchantFrame.shown = true
    IM.prints = {}
    Stub.sold = {}
    Stub.Fire("MERCHANT_SHOW")
    -- Exactly one round: the 0.2s sell timer runs and arms the wait; the wait's own deadline is
    -- queued and deliberately left pending, which is the window this case is about.
    Stub.DrainTimers(1)
    local soldBeforeWait = SoldCount()
    check("nothing has sold yet - the automatic path is waiting on item data",
        soldBeforeWait == 0, table.concat(SoldIDs(), ","))

    -- Mid-wait: the data lands AND the player clears the whitelist, which withdraws the grant.
    Stub.DefineItem(LATE, { quality = 0, sellPrice = 100, classID = 4 })
    IM:ResetSection("whitelist")
    check("...and clearing the whitelist mid-wait withdraws the grant",
        AutoSell:HasSessionConsent() == false)

    Stub.DrainTimers()
    check("a retry that comes due after the grant was withdrawn sells nothing",
        SoldCount() == soldBeforeWait, table.concat(SoldIDs(), ","))
    -- A silent stop here is indistinguishable from the addon being broken: the player is at a
    -- vendor, the items are still in the bags, and nothing scheduled this sale but the addon.
    check("...and names the stop rather than going quiet",
        Printed("your settings changed since you approved automatic selling"), Prints())
    check("...and says outright that nothing was sold, not that a sale was interrupted",
        Printed("Nothing was sold automatically"), Prints())
    check("...and points at the Sell All button that still works right now",
        Printed("Sell All button still works right now"), Prints())

    --[[
        The other side of the same chokepoint: the post-sale sweep.

        FinishSelling asks the gate and then starts the sale 0.2s later, so the answer it acts on
        is 200ms old. Withdrawing the grant inside that window is a sale authorised by a permission
        that had already been taken back by the time the items went to the vendor.

        Driven a round at a time rather than by a wall clock: the sweep is armed in the round after
        the sale loop ends, which is the first round that leaves a timer queued with no sale
        running.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    IM.db.global.whitelist[7777] = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    AcceptConfirm("grant taken before the sweep window")
    Stub.DrainTimers()
    CloseMerchant()

    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    -- Lands during the sale, so it is not in the queue: FinishSelling finds it and arms the sweep.
    Stub.onSell = function() Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 }) end
    MerchantFrame.shown = true
    IM.prints = {}
    Stub.sold = {}   -- the setup sale is not part of what this vendor did
    Stub.Fire("MERCHANT_SHOW")

    local withdrawn = false
    for _ = 1, 60 do
        if Stub.PendingTimerCount() == 0 then break end
        Stub.DrainTimers(1)
        if not withdrawn and not AutoSell:IsSelling() and Stub.PendingTimerCount() > 0 then
            IM:ResetSection("whitelist")
            withdrawn = true
        end
    end
    check("the sweep window was actually reached and the grant withdrawn inside it",
        withdrawn and AutoSell:HasSessionConsent() == false, Prints())
    check("a sweep that comes due after the grant was withdrawn sells nothing more",
        SoldCount() == 1 and SoldIDs()[1] == SELLABLE, table.concat(SoldIDs(), ","))
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
    AutoSell:SellJunk(nil, false)
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
    AutoSell:SellJunk(nil, false)
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
-- 6. Consent fingerprint: the mutation battery
-- ============================================================================

RunSection("Consent fingerprint (mutation battery)", function()

    --[[
        What this locks, and why it is a battery rather than a list.

        Session consent is bound to a fingerprint over settings. The set that fingerprint covers was
        twice written by hand and twice wrong: the first list omitted mail rules, so unticking Mail
        Helper's master enable carried an old grant over every item a rule was protecting; the
        replacement hashed the whole database minus an exclusion list, so opening a mailbox revoked
        consent. Both survived a suite that only ever asked "does the fingerprint change?".

        So each case below runs the mutation against BOTH observables and prints both:
          - fingerprint moved  = the grant no longer holds (AutoSell:HasSessionConsent is false)
          - verdict moved      = Filters:ShouldAutoSell answers differently for some probe item

        The property is that those two agree, and the aggregate check at the end of the section
        asserts it over every case at once rather than trusting the per-case expectations. Disagreeing
        one way (verdict moves, fingerprint does not) is a sale nobody approved; the other way is a
        confirm nobody needed.

        What the aggregate can promise: every case that EXISTS is in it. A case cannot be labelled a
        carve-out to take it out of both its own expectation and the aggregate, which is how a
        failing case used to be made to disappear by relabelling it - an exclusion list inside the
        suite built to kill exclusion lists.

        What it cannot promise: completeness. A mutation nobody wrote is a mutation nobody tests, so
        a case can still be exempted by simply never adding it - and that omission looks exactly
        like green. Read the case list below as a list of things a user can do to their settings and
        ask what is missing from it; the aggregate cannot ask that question for you.

        Rules are edited straight in the database rather than through MailHelper:AddRule, because the
        fingerprint reads the database and that is the state the settings panel leaves behind.
    ]]

    -- Probe items. Each is refused by exactly one setting under the baseline below, so a verdict flip
    -- names the setting that caused it.
    local PROBE_ORDER = { "plain", "rare", "consumable", "tradegood" }
    local PROBE = {
        plain      = 3001,  -- Miscellaneous, Poor, priced: only the baseline mail rule refuses it
        rare       = 3002,  -- Armor, Rare (3): refused by the default maxQuality of 2 and nothing else
        consumable = 3003,  -- classID 0: refused by the default consumables exclusion
        tradegood  = 3004,  -- classID 7: no default category exclusion covers it, so it sells
    }

    -- One enabled rule matching the `plain` probe, and one DISABLED rule matching `tradegood`. The
    -- disabled one is how "a rule that is off cannot refuse anything" gets tested rather than assumed.
    local function Baseline()
        Stub.DefineItem(PROBE.plain, { quality = 0, sellPrice = 100, classID = 15 })
        Stub.DefineItem(PROBE.rare, { quality = 3, sellPrice = 100, classID = 4 })
        Stub.DefineItem(PROBE.consumable, { quality = 0, sellPrice = 100, classID = 0 })
        Stub.DefineItem(PROBE.tradegood, { quality = 0, sellPrice = 100, classID = 7 })

        IM.db.global.mailHelper.rules = {
            { name = "To bank", alt = "Bank-Realm", filterType = "classID", filterValue = "15", enabled = true },
            { name = "Mats",    alt = "Bank-Realm", filterType = "classID", filterValue = "7",  enabled = false },
        }
    end

    local function ProbeVerdicts()
        local out = {}
        for slot, key in ipairs(PROBE_ORDER) do
            local itemID = PROBE[key]
            local shouldSell = IM.Filters:ShouldAutoSell(0, slot, itemID, Stub.ItemLink(itemID))
            table.insert(out, key .. "=" .. tostring(shouldSell and true or false))
        end
        return table.concat(out, ",")
    end

    -- Every case's raw result, so the aggregate below is computed rather than restated.
    local battery = {}

    --[[
        @param name string - what the user did
        @param mutate function(db) - the change
        @param expectFingerprint boolean - consent should be withdrawn
        @param expectVerdict boolean - some probe item's sell/keep answer should flip
        @param setup function(db)|nil - state to establish BEFORE the grant is taken, for cases whose
               mutation is a removal: the grant has to be given while the thing being removed is still
               there, or the case tests an addition wearing a removal's name.
    ]]
    local function Case(name, mutate, expectFingerprint, expectVerdict, setup)
        Reset()
        Baseline()
        if setup then setup(IM.db.global) end
        AutoSell:GrantSessionConsent()

        local before = ProbeVerdicts()
        mutate(IM.db.global)
        local after = ProbeVerdicts()

        local fingerprintMoved = (AutoSell:HasSessionConsent() == false)
        local verdictMoved = (before ~= after)
        local detail = "fingerprint=" .. tostring(fingerprintMoved) ..
            " verdict=" .. tostring(verdictMoved) .. " [" .. before .. " -> " .. after .. "]"

        table.insert(battery, {
            name = name,
            fingerprintMoved = fingerprintMoved,
            verdictMoved = verdictMoved,
        })

        check(name .. ": consent " .. (expectFingerprint and "re-arms" or "holds"),
            fingerprintMoved == expectFingerprint, detail)
        -- Named, not "...and": one wrong thing in the fingerprint fails a whole cluster of these at
        -- once, and identically-named failures cannot be told apart in the output.
        check(name .. ": the filter's verdict " .. (expectVerdict and "moves" or "holds"),
            verdictMoved == expectVerdict, detail)
    end

    -- Sanity: the baseline itself must not already be re-arming consent, or every case below passes
    -- for the wrong reason.
    Case("nothing changed", function() end, false, false)

    -- Scope settings: both observables move.
    Case("Mail Helper master enable is unticked",
        function(db) db.mailHelper.enabled = false end, true, true)

    Case("a single mail rule is disabled",
        function(db) db.mailHelper.rules[1].enabled = false end, true, true)

    Case("a mail rule's filter is edited",
        function(db) db.mailHelper.rules[1].filterValue = "7" end, true, true)

    Case("a mail rule is deleted",
        function(db) table.remove(db.mailHelper.rules, 1) end, true, true)

    Case("a mail rule is added",
        function(db)
            table.insert(db.mailHelper.rules,
                { name = "Mats too", alt = "Bank-Realm", filterType = "classID", filterValue = "7", enabled = true })
        end, true, true)

    Case("a disabled mail rule is switched on",
        function(db) db.mailHelper.rules[2].enabled = true end, true, true)

    -- A duplicate refuses exactly what the rule it duplicates refuses, so deleting it cannot widen
    -- a sale by one item - and a confirm that re-arms for it is a confirm the user is asked to
    -- answer for nothing, which is how a consent prompt gets trained into a reflex.
    Case("a duplicate of an existing mail rule is deleted",
        function(db) table.remove(db.mailHelper.rules, 3) end, false, false,
        function(db)
            table.insert(db.mailHelper.rules,
                { name = "To bank", alt = "Bank-Realm", filterType = "classID", filterValue = "15", enabled = true })
        end)

    -- Per-item protection is sale scope too. Adding one item is the shape that made "these are
    -- per-item instructions, not scope" sound right; the removals below are the shape that made it an
    -- asset-loss defect, because the Whitelist panel's Clear All and /im reset whitelist un-protect
    -- every locked item at once, under a grant given while they were all still locked.
    Case("an item is whitelisted",
        function(db) db.whitelist[PROBE.tradegood] = true end, true, true)

    Case("a whitelisted item is unlocked",
        function(db) db.whitelist[PROBE.tradegood] = nil end, true, true,
        function(db) db.whitelist[PROBE.tradegood] = true end)

    -- The real bulk path: IM:ResetSection is what /im reset whitelist calls, and it leaves the same
    -- empty table the panel's Clear All (wipe) leaves.
    Case("the whole whitelist is cleared",
        function() IM:ResetSection("whitelist") end, true, true,
        function(db)
            db.whitelist[PROBE.tradegood] = true
            db.whitelist[PROBE.plain] = true
            db.whitelist[PROBE.consumable] = true
        end)

    Case("an item is junk-listed",
        function(db) db.junkList[PROBE.rare] = true end, true, true)

    Case("an item is taken off the junk list",
        function(db) db.junkList[PROBE.rare] = nil end, true, true,
        function(db) db.junkList[PROBE.rare] = true end)

    Case("maxQuality is raised",
        function(db) db.autoSell.maxQuality = 4 end, true, true)

    Case("a category exclusion is unticked",
        function(db) db.categoryExclusions.consumables = false end, true, true)

    Case("a custom category exclusion is added",
        function(db) db.customCategoryExclusions["7"] = true end, true, true)

    Case("the minimum sell price is raised above the probes",
        function(db) db.autoSell.minSellPrice = 500 end, true, true)

    -- Runtime state and unrelated subsystems: neither observable moves.
    Case("a mailbox visit rewrites the pending queue",
        function(db) db.mailHelper.pendingQueue = { ["Bank-Realm"] = { items = { 1 }, gold = 0 } } end,
        false, false)

    Case("a mail rule is renamed",
        function(db) db.mailHelper.rules[1].name = "Send to the bank alt" end, false, false)

    Case("a mail rule is pointed at a different alt",
        function(db) db.mailHelper.rules[1].alt = "Other-Realm" end, false, false)

    Case("a DISABLED mail rule's filter is edited",
        function(db) db.mailHelper.rules[2].filterValue = "0" end, false, false)

    Case("mail rules are reordered",
        function(db)
            db.mailHelper.rules[1], db.mailHelper.rules[2] = db.mailHelper.rules[2], db.mailHelper.rules[1]
        end, false, false)

    Case("a ledger tracking toggle is turned off",
        function(db) db.ledger.trackLoot = false end, false, false)

    Case("the minimap button is hidden",
        function(db) db.ui.showMinimapButton = false end, false, false)

    Case("the bag window is reconfigured",
        function(db) db.bagUI = { enabled = false, height = 720 } end, false, false)

    Case("a transaction is recorded",
        function(db) table.insert(db.transactions.entries, { ts = 1, t = "loot" }) end, false, false)

    Case("an inventory snapshot is stored",
        function(db) db.inventorySnapshots["Alt-Realm"] = { timestamp = 1 } end, false, false)

    Case("debug mode is toggled",
        function(db) db.debug = true end, false, false)

    --[[
        Composed mutations. Each pair below is already covered one at a time and passed that way; the
        composition is where the fingerprint's own short-circuits have to match ShouldAutoSell's.

        ItemMatchesAnyRule returns false on the master toggle before it looks at a single rule, so with
        the toggle off NO rule edit can move a verdict. A fingerprint that hashes the rules anyway
        re-arms the confirm on every rule edit made while Mail Helper is switched off.
    ]]
    Case("a mail rule is edited while the master enable is off",
        function(db) db.mailHelper.rules[1].filterValue = "7" end, false, false,
        function(db) db.mailHelper.enabled = false end)

    Case("a mail rule is deleted while the master enable is off",
        function(db) table.remove(db.mailHelper.rules, 1) end, false, false,
        function(db) db.mailHelper.enabled = false end)

    -- ItemMatchesFilter looks its filterType up in FILTER_TYPES and returns false when it is not
    -- there, so a rule naming a type that does not exist refuses nothing however it is edited.
    Case("a rule whose filterType does not exist is edited",
        function(db) db.mailHelper.rules[1].filterValue = "7" end, false, false,
        function(db) db.mailHelper.rules[1].filterType = "notAFilterType" end)

    -- Filters consults mail rules only when the module is loaded, and the fingerprint's collapse is
    -- read off the same reference rather than a copy of the condition.
    Case("the MailHelper module is not loaded",
        function() IM.modules.MailHelper = nil end, true, true)

    -- The property itself, computed over the battery rather than restated case by case. Every case
    -- counts; nothing can opt out.
    local disagreements, moved, held = {}, 0, 0
    for _, case in ipairs(battery) do
        if case.fingerprintMoved ~= case.verdictMoved then
            table.insert(disagreements, case.name ..
                " (fingerprint=" .. tostring(case.fingerprintMoved) ..
                " verdict=" .. tostring(case.verdictMoved) .. ")")
        end
        if case.fingerprintMoved then moved = moved + 1 else held = held + 1 end
    end

    check("the fingerprint moves if and only if a verdict can move (" .. #battery ..
        " mutations, none exempt)",
        #disagreements == 0, table.concat(disagreements, "; "))

    -- A battery where nothing ever moves, or everything always moves, would satisfy the line above
    -- while testing nothing.
    check("...over a battery that actually exercises both outcomes",
        moved > 0 and held > 0, "moved=" .. moved .. " held=" .. held)

    -- The reason string the re-armed confirm quotes.
    Reset()
    AutoSell:GrantSessionConsent()
    IM.db.global.mailHelper.enabled = false
    local allowed, reason = AutoSell:HasSessionConsent()
    check("a changed grant reports reason 'settings-changed'",
        allowed == false and reason == "settings-changed", tostring(reason))

    Reset()
    local neverAllowed, neverReason = AutoSell:HasSessionConsent()
    check("a grant that never existed reports no reason",
        neverAllowed == false and neverReason == nil, tostring(neverReason))

    --[[
        Injectivity of the encoding. Two different configurations that produce the same string are
        one stale grant, and a stale grant sells items the user protected.

        _Field defends this with two things - a length prefix and a type tag - and each is worth
        exactly one case. The adversarial values below are CRAFTED AGAINST a named weakening: each
        one is the string that collides when that specific defence is removed and the other is left
        in place. That is a deliberate dependency on the encoding, so when the encoding changes
        these values stop biting silently. The way to tell they still bite is the same procedure
        the rest of this section is checked with: remove the guard, watch the named check go red.

        Every configuration here stays a real one - both filterTypes are ones
        MailHelper:GetFilterTypes returns, so no rule drops out of the fingerprint and no string
        moves merely because a rule vanished.
    ]]

    -- One rule's value spelling out what two rules spell out. `name` is a filterType whose value is
    -- free text the user types, so these are strings a real rule can hold.
    for _, collision in ipairs({
        -- Spelled against the exact shape _AutoSellFingerprint emits for a rule, which is
        -- `mailHelper.rule=<filterType>=<filterValue>` with both leaves through _Field. Two
        -- details a value written by eye gets wrong: the type tag survives the length-prefix
        -- weakening, so `_Field("name")` is `s:name` there and not `sname`; and the `=` between
        -- the two leaves comes from _AppendSettings. Miss either and the value collides with
        -- nothing and the case passes for no reason at all.
        { weakening = "the length prefix removed", value = "a;mailHelper.rule=s:name=s:b" },
        { weakening = "the encoding unprefixed entirely", value = "a;mailHelper.rule=name=b" },
    }) do
        Reset()
        IM.db.global.mailHelper.rules = {
            { alt = "Bank-Realm", filterType = "name", filterValue = "a", enabled = true },
            { alt = "Bank-Realm", filterType = "name", filterValue = "b", enabled = true },
        }
        AutoSell:GrantSessionConsent()
        IM.db.global.mailHelper.rules = {
            { alt = "Bank-Realm", filterType = "name", filterValue = collision.value, enabled = true },
        }
        check("one mail rule cannot spell out what two spell out, with " .. collision.weakening,
            AutoSell:HasSessionConsent() == false)
    end

    -- The same question on _AppendSettings' key path: a flat key holding the key separator against
    -- the nested shape that flattens to the same place.
    for _, collision in ipairs({
        -- Same correction as above: with the tag still in place a nested key flattens through
        -- `.s:9`, so the flat key that has to collide with it carries the colon too.
        { weakening = "the length prefix removed", key = "7.s:9" },
        { weakening = "the encoding unprefixed entirely", key = "7.9" },
    }) do
        Reset()
        IM.db.global.customCategoryExclusions = { [collision.key] = true }
        AutoSell:GrantSessionConsent()
        IM.db.global.customCategoryExclusions = { ["7"] = { ["9"] = true } }
        check("a settings key is not confusable with a nested table, with " .. collision.weakening,
            AutoSell:HasSessionConsent() == false)
    end

    --[[
        A table-valued filterValue, edited in place.

        The rule part used to hash filterValue through _Field directly - the one leaf in the whole
        fingerprint that skipped the recursion - and _Field on a table hashes its ADDRESS, which
        does not move when the table behind it is edited. That is precisely the stale-grant miss
        _AppendSettings exists to kill, reintroduced on the single line that routed around it.

        No shipping filterType holds a table today, so this locks the contract rather than a live
        shape. It is worth locking anyway: "no filterType does this yet" is exactly the sort of
        claim that stops being true without anyone revisiting the hash.
    ]]
    Reset()
    local sharedValue = { "Herb", "Ore" }
    IM.db.global.mailHelper.rules = {
        { alt = "Bank-Realm", filterType = "name", filterValue = sharedValue, enabled = true },
    }
    AutoSell:GrantSessionConsent()
    sharedValue[2] = "Cloth"   -- same table, different contents, same address
    check("a table-valued filterValue edited in place does not carry its grant forward",
        AutoSell:HasSessionConsent() == false)

    -- tostring collapses types. Whitelist keys are itemIDs, and an itemID that arrives as text -
    -- from a saved variable, from a panel that never called tonumber - is a different table key
    -- protecting a different set of items.
    Reset()
    IM.db.global.whitelist = { [5000] = true }
    AutoSell:GrantSessionConsent()
    IM.db.global.whitelist = { ["5000"] = true }
    check("a numeric whitelist key does not hash like the string of the same digits",
        AutoSell:HasSessionConsent() == false)

    Reset()
    IM.db.global.autoSell.skipSoulbound = true
    AutoSell:GrantSessionConsent()
    IM.db.global.autoSell.skipSoulbound = "true"
    check("a boolean setting does not hash like the string of the same word",
        AutoSell:HasSessionConsent() == false)

    --[[
        Big whitelists, and why they are enumerated rather than digested.

        A player with hundreds of locked items is the case that makes a cheaper summary tempting: a
        count, a sum, an xor. The swap below defeats count-and-sum together - two IDs out, two IDs in,
        same number of entries and the same total - while genuinely un-protecting two items. Only an
        injective encoding answers it, so the fingerprint enumerates.
    ]]
    Reset()
    for id = 5000, 5999 do IM.db.global.whitelist[id] = true end
    AutoSell:GrantSessionConsent()
    -- 5000 and 5001 out, 4001 and 6000 in. Both incomers are outside the block, so the entry count is
    -- unchanged at 1000, and 4001 + 6000 = 5000 + 5001, so the total is unchanged too. Two items that
    -- were protected when the grant was given no longer are.
    IM.db.global.whitelist[5000] = nil
    IM.db.global.whitelist[5001] = nil
    IM.db.global.whitelist[4001] = true
    IM.db.global.whitelist[6000] = true
    local swappedCount, swappedSum = 0, 0
    for id in pairs(IM.db.global.whitelist) do
        swappedCount = swappedCount + 1
        swappedSum = swappedSum + id
    end
    check("the swap really does preserve the entry count and their total",
        swappedCount == 1000 and swappedSum == 5499500,
        "count=" .. swappedCount .. " sum=" .. swappedSum)
    check("a 1000-entry whitelist that swaps two IDs for two others of the same count and sum " ..
        "does not hash alike", AutoSell:HasSessionConsent() == false)

    -- What that costs. Not a pass/fail check - a wall-clock number on whatever ran the suite,
    -- printed so the price of enumerating is a measurement rather than an assurance.
    Reset()
    for id = 5000, 5999 do IM.db.global.whitelist[id] = true end
    AutoSell:GrantSessionConsent()
    local started = os.clock()
    for _ = 1, 100 do AutoSell:HasSessionConsent() end
    Stub.Say(string.format("  info HasSessionConsent over a 1000-entry whitelist: %.3f ms per call",
        (os.clock() - started) * 10))
end)

-- ============================================================================
-- 7. Guards that must survive being deleted
-- ============================================================================

RunSection("Guards nothing else covers", function()

    --[[
        The slot identity check in ProcessNextItem, in the window it actually exists for.

        Every other test changes a bag slot BEFORE the confirm is answered, where SellJunk's own
        re-validation of the approved list catches it first - so the ProcessNextItem check could be
        deleted with the suite still green. The window it owns is mid-queue: the sale is running, item
        one has gone to the merchant, and something lands in item two's slot during the 0.15s timer
        between the two sales. Nothing re-validates after that point.

        The intruder is chosen to pass every filter on its own, so a failure here means the addon sold
        a thing the player never saw quoted - not that it refused something it should have taken.
    ]]
    local INTRUDER = 444

    Reset()
    Stub.DefineItem(INTRUDER, { quality = 0, sellPrice = 100, classID = 4 })
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    OpenMerchant()
    Stub.onSell = function(bagID, slotID)
        if bagID == 0 and slotID == 1 then
            -- Lands while the inter-sale timer is pending, after the accept, mid-queue.
            C_Timer.After(0.05, function()
                Stub.PutItem(0, 2, { itemID = INTRUDER, stackCount = 1 })
            end)
        end
    end
    AcceptConfirm("mid-queue slot swap")
    Stub.DrainTimers()

    local soldIntruder = false
    for _, id in ipairs(SoldIDs()) do
        if id == INTRUDER then soldIntruder = true end
    end
    check("an item that lands in a queued slot mid-sale is not sold in the queued item's place",
        not soldIntruder, table.concat(SoldIDs(), ","))
    check("...and the approved item that was still there was sold",
        SoldCount() == 1 and SoldIDs()[1] == SELLABLE, table.concat(SoldIDs(), ","))
    check("...and the intruder is still in the bag",
        (C_Container.GetContainerItemInfo(0, 2) or {}).itemID == INTRUDER)

    --[[
        "A manual sale grants NOTHING."

        Asserted three times in AutoSell.lua's comments and, until now, locked by nothing: consent
        could be granted from inside SellJunk - which every sale reaches, manual ones included - with
        the whole suite still green. The four existing false-assertions on HasSessionConsent all sit on
        paths where no sale started, so they pass whether or not a sale grants consent.

        Both manual entry points therefore assert it on a path where a sale DID start.
    ]]
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    MerchantFrame.shown = true
    SlashCmdList["INVENTORYMANAGER"]("sell")
    Stub.DrainTimers()
    check("/im sell sells the items in the bags", SoldCount() == 1, Prints())
    check("...and grants no session consent for the unattended path",
        AutoSell:HasSessionConsent() == false)

    -- The vendor popup's Sell All button reaches the same argument-free SellJunk, so the behavioural
    -- half is the same assertion:
    Reset()
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    IM.db.global.autoSellEnabled = true
    MerchantFrame.shown = true
    AutoSell:SellJunk()
    Stub.DrainTimers()
    check("a manual SellJunk() sells the items in the bags", SoldCount() == 1, Prints())
    check("...and grants no session consent either", AutoSell:HasSessionConsent() == false)

    --[[
        ...and the binding half, read out of the shipping file rather than asserted about it.

        UI/AutoSellPopup.lua needs the UI layer, which this harness does not load, so the click cannot
        be driven. What can be checked without loading it is that the button's handler is still the
        call the line above exercises: no approved list, no consent grant. A comment claiming those two
        are the same call would be exactly the kind of hand-maintained claim this suite exists to stop.
    ]]
    local sellAllHandler
    do
        local file = io.open("UI/AutoSellPopup.lua")
        if not file then
            check("the Auto-Sell popup source is readable from the harness", false,
                "run the suite from the repo root")
        else
            local source = file:read("*a")
            file:close()
            sellAllHandler = source:match('local sellBtn = UI:CreateButton.-popup%.sellBtn = sellBtn')
        end
    end
    check("the popup's Sell All button still calls SellJunk with no approved list",
        sellAllHandler ~= nil and sellAllHandler:find("AutoSell:SellJunk()", 1, true) ~= nil,
        tostring(sellAllHandler))
    check("...and grants nothing on the way",
        sellAllHandler ~= nil and sellAllHandler:find("Consent", 1, true) == nil,
        tostring(sellAllHandler))

    --[[
        MERCHANT_CLOSED drops anything waiting on item data.

        A wait armed at one vendor that comes due at the next one starts a sale at a vendor the
        player never approved anything at. The window is opened here WITHOUT firing MERCHANT_SHOW,
        deliberately: with the show path running, its own sale would mask the stale waiter's, and
        the thing under test is whether the waiter survived the close at all.
    ]]
    local LATE = 666
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    AcceptConfirm("grant before the stale-waiter window")
    Stub.DrainTimers()
    CloseMerchant()

    -- First vendor of the pair: the bags hold only an item whose data has not arrived, so the
    -- automatic path arms a wait rather than selling.
    Stub.PutItem(0, 1, { itemID = LATE, stackCount = 1 })
    MerchantFrame.shown = true
    Stub.sold = {}
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
        No free dialog slot.

        StaticPopup_Show hands back nil when other addons hold every Blizzard popup slot. There is
        then no dialog, so no OnHide, so nothing to clear _consentPending - and a gate stuck at
        "already asking" never asks again for the rest of the session, silently. The branch fails
        closed instead: nothing sold, said out loud, and the gate left able to ask again.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.refusePopup = true
    OpenMerchant()
    check("a confirm that cannot be shown sells nothing", SoldCount() == 0, Prints())
    check("...and says so rather than failing silently",
        Printed("no free dialog slot"), Prints())

    -- The slot frees up while the player is still at the same vendor. The gate must not still think
    -- a dialog is on screen: nothing but a merchant close would ever clear that, so a wedge here is
    -- an addon that has gone quiet for the rest of the visit with no way for the player to tell.
    Stub.refusePopup = false
    IM.prints = {}
    Stub.Fire("MERCHANT_SHOW")
    Stub.DrainTimers()
    check("...and asks again once a slot frees, instead of staying quiet for the rest of the visit",
        Stub.PopupOnScreen(), Prints())

    --[[
        A manual sale takes the confirm down.

        The dialog describes a sale of a specific list. If the player answers it by clicking Sell
        All instead, that sale has happened - and a dialog still on screen is now describing it in
        the future tense, with a live approved list behind it that Sell would act on a second time.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    check("the confirm is on screen before the manual sale", Stub.PopupOnScreen(), Prints())
    AutoSell:SellJunk()          -- the popup's Sell All, while the confirm is still up
    Stub.DrainTimers()
    check("a manual sale run while the confirm is up sells the bags",
        SoldCount() == 1, table.concat(SoldIDs(), ","))
    check("...and takes the confirm down rather than leaving it describing a sale that happened",
        not Stub.PopupOnScreen())
    check("...and still grants nothing", AutoSell:HasSessionConsent() == false)

    --[[
        ...but a click that sells NOTHING must destroy nothing either.

        Sell All while a sale is already running is answered with "already-selling". The dismissal
        above used to run BEFORE that guard, so the click took down a dialog the player was
        part-way through answering, and its approved list with it, having vendored not one item.

        Timers here are drained in rounds rather than by a clock, one queued item per round, so
        stopping after a single round leaves the sell loop mid-queue with its next timer pending -
        which is the only state in which a second click can meet a live sale.
    ]]
    local BYSTANDER = 777
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.DefineItem(BYSTANDER, { quality = 0, sellPrice = 100, classID = 4 })
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 3, { itemID = SELLABLE, stackCount = 1 })
    MerchantFrame.shown = true
    AutoSell:SellJunk()          -- the popup's Sell All: slot 1 goes, the queue keeps running
    -- Lands after that queue was built, so the running sale will never reach it. It is what makes
    -- the confirm below answerable afterwards instead of describing items already gone.
    Stub.PutItem(0, 4, { itemID = BYSTANDER, stackCount = 1 })
    Stub.Fire("MERCHANT_SHOW")   -- the vendor window the player is standing at
    Stub.DrainTimers(1)          -- one round: the sale advances, and the confirm goes up
    check("the confirm can be on screen while a sale is still running",
        Stub.PopupOnScreen() and AutoSell:IsSelling(), Prints())

    local soldMidSale = SoldCount()
    local busyStarted, busyReason = AutoSell:SellJunk()
    check("a second Sell All during that sale is refused as already-selling",
        busyStarted == false and busyReason == "already-selling", tostring(busyReason))
    check("...and vendors nothing", SoldCount() == soldMidSale, table.concat(SoldIDs(), ","))
    check("...and leaves the confirm the player was answering on screen", Stub.PopupOnScreen())

    Stub.DrainTimers()           -- the running sale finishes
    local soldBeforeAnswer = SoldCount()
    if AcceptConfirm("the confirm that survived a refused click") then
        Stub.DrainTimers()
        check("...still holding the approved list, so answering it sells what it quoted",
            SoldCount() == soldBeforeAnswer + 1 and SoldIDs()[#SoldIDs()] == BYSTANDER,
            table.concat(SoldIDs(), ","))
    end

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
-- 8. The approved-list exemption is proof, not a bearer token
-- ============================================================================

--[[
    Call the dangerous function directly, from a path nobody sanctioned, and confirm it refuses.

    SellJunk exempts a sale carrying an approved list from the consent gate. While that exemption
    keyed on "approvedItems is non-nil", the exemption was a BEARER TOKEN: a caller that built a
    table shaped like an approved list sold without a dialog, without a grant and without binding
    the visit, and the only thing making that safe was an unwritten list of callers.

    Nothing in this suite exercised it, which is the disease rather than an oversight: the property
    was guarded by throwaway probes that got deleted, so the code could regress in silence. These
    cases are the guard. The corresponding legitimate paths stay green in every section above, so a
    fix that refuses forgeries by refusing everything cannot pass.
]]
RunSection("The approved-list exemption cannot be forged", function()

    -- A direct automatic sale with no grant at all. This is also the only case that reaches
    -- SellJunk's own no-consent refusal message - the merchant-open scheduler asks for consent
    -- instead of getting here, so the branch was deletable with the suite still green.
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    MerchantFrame.shown = true
    IM.prints = {}
    local bareStarted, bareReason = AutoSell:SellJunk(nil, true)
    check("a direct automatic SellJunk with no grant refuses",
        bareStarted == false and bareReason == "no-consent", tostring(bareReason))
    check("...and vendors nothing", SoldCount() == 0, table.concat(SoldIDs(), ","))
    check("...and says so instead of stopping silently",
        Printed("Nothing was sold automatically") and
        Printed("automatic selling has not been approved"), Prints())

    -- A hand-built approved list, exactly as a bearer token would be presented.
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    MerchantFrame.shown = true
    IM.prints = {}
    local forged = { { bagID = 0, slotID = 1, itemID = SELLABLE, stackCount = 1, approved = true } }
    local forgedStarted, forgedReason = AutoSell:SellJunk(forged, true)
    check("a hand-built approved list is refused",
        forgedStarted == false and forgedReason == "unapproved-list", tostring(forgedReason))
    check("...and vendors nothing", SoldCount() == 0, table.concat(SoldIDs(), ","))
    check("...and grants no session consent on the way",
        AutoSell:HasSessionConsent() == false)
    check("...and is loud about it, because only a bug or another addon can produce it",
        Printed("without the confirmation that authorises it"), Prints())

    -- The refusal must not wedge the gate: the player is still owed the real dialog.
    Stub.Fire("MERCHANT_SHOW")
    Stub.DrainTimers()
    check("...and the real confirm still appears afterwards", Stub.PopupOnScreen(), Prints())

    -- A truthy non-table. This used to skip the gate on `approvedItems ~= nil` and then raise
    -- inside ipairs - a bypass that ends in a Lua error rather than a refusal.
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    MerchantFrame.shown = true
    local okScalar, scalarStarted, scalarReason =
        pcall(function() return AutoSell:SellJunk(true, true) end)
    check("a truthy non-table approvedItems is refused rather than raising",
        okScalar and scalarStarted == false and scalarReason == "unapproved-list",
        tostring(okScalar) .. "/" .. tostring(scalarReason))
    check("...and vendors nothing", SoldCount() == 0, table.concat(SoldIDs(), ","))

    --[[
        The sharpest one: mid-visit, with a session grant standing and the visit bound.

        Here the forged list is the only thing between a straggler and the vendor. The dialog told
        the player nothing else would be sold at this vendor; the grant means the session-level
        half of the gate would say yes; and the approved-list exemption is what skips the
        visit-level half. A bearer token sells the straggler the dialog promised to leave alone.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    AcceptConfirm("approved visit before the forged calls")
    Stub.DrainTimers()
    local soldUnderApproval = SoldCount()
    check("the approved sale ran and the grant is standing",
        soldUnderApproval == 1 and AutoSell:HasSessionConsent() == true, Prints())

    Stub.PutItem(0, 2, { itemID = SELLABLE_2, stackCount = 1 })   -- the straggler
    IM.prints = {}
    local midStarted, midReason = AutoSell:SellJunk(nil, true)
    check("a direct automatic call during an approved visit refuses",
        midStarted == false and midReason == "visit-bound", tostring(midReason))
    -- Alone among the gate's refusals, this one is deliberately silent: it is the expected state
    -- for the rest of an approved visit, and the player is told about left-behind items by
    -- FinishSelling's suppressed sweep instead. Every other refusal prints, so the exemption is a
    -- real branch and was locked by nothing.
    check("...silently, because a visit-bound refusal is the state the dialog itself created",
        #IM.prints == 0, Prints())

    local midForged = { { bagID = 0, slotID = 2, itemID = SELLABLE_2, stackCount = 1, approved = true } }
    local midForgedStarted, midForgedReason = AutoSell:SellJunk(midForged, true)
    check("...and a forged approved list during that visit is refused too",
        midForgedStarted == false and midForgedReason == "unapproved-list", tostring(midForgedReason))
    check("...so the straggler the dialog promised to leave alone is still in the bag",
        SoldCount() == soldUnderApproval and
        (C_Container.GetContainerItemInfo(0, 2) or {}).itemID == SELLABLE_2,
        table.concat(SoldIDs(), ","))

    --[[
        The nonce's other two terms, observed while a presentation is LIVE.

        Every case above calls SellJunk at a moment when nothing has been presented, so only the
        presence term can refuse them - and an independent mutation pass proved exactly that:
        reducing the gate to `presented == nil`, and separately deleting the `_presentedNonce = nil`
        spend line, each left the whole suite green. The identity comparison and the spend are
        unobservable from outside a real ConfirmApprovedSale, because it mints the nonce, presents
        it and hands it to SellJunk with no gap a caller can stand in.

        So these two stand in for SellJunk itself, for exactly one call. That is the only seam
        between "presented" and "spent", and it is a seam in the harness rather than a door in the
        addon: the stand-in restores the real function before calling it, so the sale's own
        continuations are the shipping ones.
    ]]

    -- The presented nonce holds THE list, by reference. A twin table carrying the very same
    -- entries is a different list, and the exemption does not transfer to it.
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    IM.prints = {}
    local realSellJunk = AutoSell.SellJunk
    local swapStarted, swapReason
    AutoSell.SellJunk = function(module, list, isAutomatic, isRetry)
        AutoSell.SellJunk = realSellJunk
        local twin = {}
        for i, entry in ipairs(list) do twin[i] = entry end
        swapStarted, swapReason = realSellJunk(module, twin, isAutomatic, isRetry)
        return swapStarted, swapReason
    end
    AcceptConfirm("a twin approved list under a live presentation")
    Stub.DrainTimers()
    check("a twin of the approved list is refused even while its nonce is presented",
        swapStarted == false and swapReason == "unapproved-list", tostring(swapReason))
    check("...and vendors nothing", SoldCount() == 0, table.concat(SoldIDs(), ","))
    check("...and grants no session consent", AutoSell:HasSessionConsent() == false)
    check("...and is loud about it, the same as any other forgery",
        Printed("without the confirmation that authorises it"), Prints())

    --[[
        One presentation authorises ONE call.

        The spend is the first thing SellJunk does, whatever the call turns out to be, so a second
        call carrying the very same table is a replay against a nonce that is already gone. The
        replay here is aimed at a slot that has been refilled since the approved sale emptied it:
        an item matching the approved entry exactly, that no dialog ever quoted and no player ever
        saw. Without the spend, that item goes to the vendor.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    IM.prints = {}
    local realForReplay = AutoSell.SellJunk
    local replayStarted, replayReason
    AutoSell.SellJunk = function(module, list, isAutomatic, isRetry)
        AutoSell.SellJunk = realForReplay
        local started, reason = realForReplay(module, list, isAutomatic, isRetry)
        Stub.DrainTimers()                                          -- the approved sale completes
        Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })   -- a fresh, never-quoted item
        replayStarted, replayReason = realForReplay(module, list, true)
        return started, reason
    end
    AcceptConfirm("a replayed approved list under a spent presentation")
    Stub.DrainTimers()
    check("the approved sale itself went through, so the replay is the only thing being refused",
        SoldCount() == 1 and SoldIDs()[1] == SELLABLE, table.concat(SoldIDs(), ","))
    check("a second call carrying the same approved table is refused",
        replayStarted == false and replayReason == "unapproved-list", tostring(replayReason))
    check("...so the item that landed in the approved slot afterwards is still in the bag",
        SoldCount() == 1 and (C_Container.GetContainerItemInfo(0, 1) or {}).itemID == SELLABLE,
        table.concat(SoldIDs(), ","))
end)

-- ============================================================================
-- 9. The buyback page size is read from the client, not typed into the addon
-- ============================================================================

RunSection("Buyback page size is derived", function()

    local livePageSize = BUYBACK_ITEMS_PER_PAGE

    -- Deliberately NOT the live 12: a number hand-written into AutoSell.lua passes a test that
    -- asserts 12, which is how the previous two wrong numbers survived.
    BUYBACK_ITEMS_PER_PAGE = 7
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    local sentence = Stub.PopupText2() or ""
    check("the confirm's buyback sentence quotes the client's page size",
        sentence:find("lists 7 items at a time", 1, true) ~= nil, sentence)
    AcceptConfirm("derived buyback page size")
    Stub.DrainTimers()
    -- The post-sale line does NOT quote it: itemCount sums item units across stacks, not buyback
    -- slots, so a page-size number stated beside a stack-of-items count would invite a comparison
    -- that does not hold. See section 9b for the overstatement this used to make.
    check("...but the post-sale line states no page-size number at all",
        not Printed("items at a time"), Prints())

    -- No constant to read: the number is dropped, never guessed. The rest of the sentence - which
    -- states no expiry, because nobody here has observed one - stands unchanged.
    BUYBACK_ITEMS_PER_PAGE = nil
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    local bare = Stub.PopupText2() or ""
    check("a client with no buyback constant gets the sentence with no number at all",
        bare:find("Buyback tab -", 1, true) ~= nil and bare:find("lists", 1, true) == nil,
        bare)

    --[[
        The constant is a client global, and any addon in the load order can overwrite it. Anything
        that is not a whole count of at least one is unreadable rather than renderable: "lists 0
        items at a time" and "lists -3 items at a time" are worse than saying nothing, and all
        three of these used to render verbatim into the dialog the player is consenting through.
    ]]
    for _, junk in ipairs({ 0, -3, 1.5 }) do
        BUYBACK_ITEMS_PER_PAGE = junk
        Reset()
        IM.db.global.autoSellEnabled = true
        Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
        OpenMerchant()
        local nonsense = Stub.PopupText2() or ""
        check("a BUYBACK_ITEMS_PER_PAGE of " .. junk .. " is dropped rather than quoted",
            nonsense:find("lists", 1, true) == nil and
            nonsense:find(tostring(junk), 1, true) == nil, nonsense)
    end

    BUYBACK_ITEMS_PER_PAGE = livePageSize
end)

-- ============================================================================
-- 9b. The post-sale line cannot overstate what buyback still holds
-- ============================================================================

--[[
    The buyback tab holds only the client's most recent entries. Sell more stacks in one session
    than BUYBACK_ITEMS_PER_PAGE and the post-sale line must not read as a promise that every item
    just sold is still sitting there - the older ones may already have fallen off the list.

    Also sells at a stack size (4) that makes itemCount (item units, summed across stacks) diverge
    from both the stack count sold and the page size, so nothing here can be read as "N items sold,
    N of them safe" arithmetic - the two numbers were never in the same unit.

    This case was checked red before it was checked green: restoring the old wording ("they are in
    this vendor's Buyback tab ... if you want any of them back") fails the second check below, which
    is what makes the assertion a lock on the defect rather than a tautology that would pass no
    matter what shipped.
]]
RunSection("The post-sale line does not overstate what buyback still holds", function()

    local livePageSize = BUYBACK_ITEMS_PER_PAGE
    BUYBACK_ITEMS_PER_PAGE = 3

    Reset()
    IM.db.global.autoSellEnabled = true
    for slot = 1, 5 do
        Stub.PutItem(0, slot, { itemID = SELLABLE, stackCount = 4 })
    end
    OpenMerchant()
    AcceptConfirm("selling more stacks than the buyback page holds")
    Stub.DrainTimers()

    check("all 5 stacks actually sold, so the scenario exercises the overstatement rather than a no-op",
        SoldCount() == 5, table.concat(SoldIDs(), ","))
    check("the post-sale line does not promise every item just sold is still retrievable",
        not Printed("if you want any of them back"), Prints())
    check("...it scopes the claim instead: only the most recent entries, older ones may be gone",
        Printed("only the most recently sold items are still in this vendor's Buyback tab") and
        Printed("earlier ones may already be gone"), Prints())
    check("...and quotes no page-size number beside the count - itemCount is stack units, not slots",
        not Printed("items at a time"), Prints())

    BUYBACK_ITEMS_PER_PAGE = livePageSize
end)

-- ============================================================================
-- 10. What the confirm's own text says
-- ============================================================================

--[[
    The dialog's first substitution is the sentence the player is consenting to, and not one word
    of it was asserted: replacing the whole `summary` argument with "" left the suite green, taking
    the item count, the money figure, the excluded-stragglers sentence and the re-prompt's lead
    with it. Stub.PopupText existed for exactly this and was called by nothing - the same shape as
    the round that added PopupText2 and only asserted on the accessor it happened to be using.

    Every figure below is computed from the fixture rather than typed, so a change to what the
    dialog counts fails here instead of being copied into the expectation.
]]
RunSection("The confirm says what is about to happen", function()

    local PRICEY = 888

    Reset()
    Stub.DefineItem(PRICEY, { quality = 0, sellPrice = 2500, classID = 4 })
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 3 })   -- 3 x 100
    Stub.PutItem(0, 2, { itemID = PRICEY, stackCount = 1 })     -- 1 x 2500
    OpenMerchant()
    local text = Stub.PopupText() or ""
    check("the confirm quotes how many items it is about to sell, counting the stacks",
        text:find("about to sell 4 items for ", 1, true) ~= nil, text)
    check("...and the money figure, in the addon's own money formatting",
        text:find(IM:FormatMoney(3 * 100 + 2500), 1, true) ~= nil, text)
    check("...and does not claim a setting changed, because none did",
        text:find("settings changed", 1, true) == nil, text)

    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    OpenMerchant()
    local single = Stub.PopupText() or ""
    check("a one-item sale is worded in the singular",
        single:find("about to sell 1 item for ", 1, true) ~= nil, single)

    --[[
        Items whose data never arrived are excluded from the sale. The dialog has to say so: the
        count it quotes is the whole story as far as the player can tell, and a bag with items in
        it that the confirm silently omitted looks like the filter refusing them.
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    Stub.PutItem(0, 2, { itemID = UNCACHED, stackCount = 1 })
    OpenMerchant()
    Stub.DrainTimers(200)   -- spend the wait-for-data budget, so the prompt stops waiting and quotes
    local straggler = Stub.PopupText() or ""
    check("an item that never loaded is named as excluded rather than silently dropped",
        straggler:find("1 further item(s) never finished loading", 1, true) ~= nil, straggler)
    check("...and the count quoted is only the items that did load",
        straggler:find("about to sell 1 item for ", 1, true) ~= nil, straggler)

    --[[
        The re-prompt. A confirm re-armed by a settings change is otherwise word-for-word the
        first-time confirm, and the player cannot tell "you changed something" from "the addon
        forgot you already answered this".
    ]]
    Reset()
    IM.db.global.autoSellEnabled = true
    Stub.PutItem(0, 1, { itemID = SELLABLE, stackCount = 1 })
    AutoSell:GrantSessionConsent()
    IM.db.global.autoSell.maxQuality = 3    -- moves the fingerprint; Poor stays sellable either way
    check("the grant is withdrawn by the settings change, so the confirm is a re-prompt",
        AutoSell:HasSessionConsent() == false)
    OpenMerchant()
    local reprompt = Stub.PopupText() or ""
    check("a re-armed confirm leads with why it is asking again",
        reprompt:find("Your InventoryManager settings changed since you approved automatic selling",
            1, true) ~= nil, reprompt)
    check("...and still quotes the sale underneath that lead",
        reprompt:find("about to sell 1 item for ", 1, true) ~= nil, reprompt)
end)

-- ============================================================================
-- 11. The auto-sell settings dropdown derives its quality list
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
local EXPECTED_CHECKS = 225   -- this assertion included

check("every expected check ran", checks + 1 == EXPECTED_CHECKS,
    "counted=" .. (checks + 1) .. " expected=" .. EXPECTED_CHECKS)

Stub.Say(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
