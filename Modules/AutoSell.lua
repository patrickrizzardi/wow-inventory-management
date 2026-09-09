--[[
    InventoryManager - Modules/AutoSell.lua
    Automatic selling of junk items at merchants
]]

local addonName, IM = ...

local AutoSell = {}
IM:RegisterModule("AutoSell", AutoSell)

-- Sell queue for processing items one at a time
local _sellQueue = {}
local _isSelling = false
local _sellTimer = nil

-- Track items merchant rejected (cleared when merchant closes)
local _rejectedItems = {}

-- Statistics for current sell session
local _sessionStats = {
    itemCount = 0,
    totalValue = 0,
}

-- Consent for AUTOMATIC selling, one grant per session, granted ONLY by the confirm dialog below.
-- File scope re-runs on /reload, so a reload re-arms the confirm.
--
-- A manual sale (the popup's "Sell All", /im sell) deliberately grants NOTHING: it sells the list
-- the user is looking at and leaves the automatic path still gated. Consent-to-this-sale and
-- consent-to-unattended-future-sales are different grants and are not interchangeable.
local _sessionConsent = {
    granted = false,
    fingerprint = nil,
}

-- The dialog is on screen and waiting for an answer.
local _consentPending = false

-- The exact item list the confirm dialog quoted its count and value from. The sale is bound to
-- this list, not to a fresh scan, so the figure shown is the figure acted on.
local _approvedItems = nil

--[[
    Proof that an approved list came from the confirm dialog.

    SellJunk exempts an approved sale from the consent gate, because that sale IS the answer to the
    dialog. Exempting it on "approvedItems is non-nil" alone makes the exemption a BEARER TOKEN: any
    caller that hands SellJunk a table shaped like an approved list sells without a dialog, without
    a grant and without binding the visit. Its correctness then rests on an unwritten list of
    callers, which is exactly the shape that cannot be checked.

    So the list is not the proof; the nonce is. `_approvalNonce` is minted in RequestSellConsent
    beside `_approvedItems` and holds that exact table by reference. ConfirmApprovedSale is the only
    thing that presents it, and SellJunk's gate spends it on the first call it reaches - one shot,
    compared by identity, and unreachable from outside this file. A hand-built list has no nonce; a
    replay has a spent one; a substituted list fails the identity comparison.
]]
local _approvalNonce = nil      -- { items = <the list the dialog quoted> }, one per prompt
local _presentedNonce = nil     -- handed to the very next SellJunk call, consumed there

-- True once an approved sale has run at this merchant visit. The dialog told the user which items
-- it would sell, so nothing may start a wider sale for the rest of the visit - not the post-sale
-- sweep, and not a second MERCHANT_SHOW. MayStartAutomaticSale turns it into the gate's
-- "visit-bound" refusal, which SellJunk enforces on every unattended sale it is asked to start.
--
-- MERCHANT_CLOSED clears it, because MERCHANT_CLOSED is the event that ends a visit;
-- MERCHANT_SHOW is not, because some vendors fire it again for a window already on screen and
-- there is no way to tell that re-fire from a reopen at the moment it arrives. Keying the clear on
-- the close needs no such distinction, and the one case it gets "wrong" - a second vendor reached
-- with no MERCHANT_CLOSED in between - fails by declining to sell and saying so, not by selling.
local _visitBoundToApproval = false

-- Did the addon start the sale now running, or did the user? Set from SellJunk's isAutomatic
-- argument as the sale starts, because it cannot be inferred: the automatic path at a later vendor
-- also passes no approved list. FinishSelling reads THIS as well as the shared gate, so "manual
-- sales do not sweep" stays true at a vendor visited after consent was given.
local _currentSaleIsAutomatic = false

--[[
    Retry budgets for "the client has not sent item data yet".

    Two of them, and the split is the point. The automatic path spends its attempts while the
    player is looking at a vendor window and being told nothing; a player who then clicks Sell All
    is making a fresh, explicit request and must not be handed an empty budget and a "gave up
    waiting" message for attempts they never saw. An explicit action gets its own attempts.

    The automatic budget is refilled by both merchant events, so it cannot wedge. The manual budget
    is refilled by each click, which is what "your click, your attempts" means.
]]
local MAX_PENDING_ATTEMPTS = 10
local _pendingAttempts = {
    automatic = 0,
    manual = 0,
}

-- ============================================================================
-- ITEM DATA SIGNAL
-- ============================================================================

--[[
    One debounced "item data has settled" signal for everything on the auto-sell path.

    GET_ITEM_INFO_RECEIVED fires once per item, in bursts. Anything on this path that wants to
    know when a burst is over subscribes here instead of running a clock of its own; before this
    existed, the consent prompt and the Auto-Sell popup each polled the bags separately on the same
    burst of arriving data. One handler, one debounce, one broadcast.

    The deadline exists because "no further item data is coming" produces no event at all, so a
    listener with no clock would wait forever. Waiters are one-shot and are dropped when the
    merchant closes - a wait armed at one vendor must never fire a sale at the next one.
]]
local ITEM_DATA_DEBOUNCE = 0.3
local ITEM_DATA_DEADLINE = 2.0

local _itemDataListeners = {}
local _itemDataWaiters = {}
local _itemDataDeadline = nil
local _itemDataNotifyQueued = false
local _itemDataNotifyToken = 0

local function _NotifyItemData()
    _itemDataNotifyQueued = false
    -- Invalidates any debounce callback already in flight, so a deadline firing first cannot be
    -- followed by a second, redundant broadcast.
    _itemDataNotifyToken = _itemDataNotifyToken + 1

    if _itemDataDeadline then
        _itemDataDeadline:Cancel()
        _itemDataDeadline = nil
    end

    for _, listener in ipairs(_itemDataListeners) do
        listener()
    end

    if #_itemDataWaiters > 0 then
        local waiters = _itemDataWaiters
        _itemDataWaiters = {}
        for _, waiter in ipairs(waiters) do
            waiter()
        end
    end
end

-- Run callback once, as soon as the next burst of item data settles or the deadline expires.
local function _WaitForItemData(callback)
    table.insert(_itemDataWaiters, callback)
    if not _itemDataDeadline then
        _itemDataDeadline = C_Timer.NewTimer(ITEM_DATA_DEADLINE, function()
            _itemDataDeadline = nil
            _NotifyItemData()
        end)
    end
end

local function _CancelItemDataWaiters()
    wipe(_itemDataWaiters)
    if _itemDataDeadline then
        _itemDataDeadline:Cancel()
        _itemDataDeadline = nil
    end
end

-- Subscribe to the signal above for as long as the addon is loaded. The callback is told only that
-- item data arrived; whether it is still relevant (window shown, merchant open) is the caller's
-- own precondition to check.
function AutoSell:RegisterItemDataListener(callback)
    table.insert(_itemDataListeners, callback)
end

-- ============================================================================
-- CONSENT FINGERPRINT
-- ============================================================================

-- Encode one leaf so that no two different values can ever encode alike - two configurations that
-- hash alike are one stale grant, and a stale grant sells items the user protected.
--
-- Length-prefixed, because a value is free to contain the separators this string is built from: a
-- single rule whose filterValue holds "a;mailHelper.rule=nameb" would otherwise spell out exactly
-- what two rules spell out.
-- Type-tagged, because tostring is not injective either: the number 5000 and the string "5000"
-- are different table keys with the same text, as are the boolean true and the string "true".
local function _Field(value)
    local text = tostring(value)
    return type(value):sub(1, 1) .. #text .. ":" .. text
end

-- Hash every leaf of a settings table. Recursive rather than flat because a nested table
-- stringifies to its address, and an address does not move when the table behind it is edited in
-- place - the miss that carries a stale grant forward.
local function _AppendSettings(parts, prefix, value)
    if type(value) ~= "table" then
        table.insert(parts, prefix .. "=" .. _Field(value))
        return
    end
    for key, child in pairs(value) do
        _AppendSettings(parts, prefix .. "." .. _Field(key), child)
    end
end

--[[
    A stable string over the settings Filters:ShouldAutoSell reads to decide WHICH items sell.
    Session consent is bound to it, so changing any of them re-arms the confirm instead of selling
    a wider set under a grant given for a narrower one.

    The rule is: hash what ShouldAutoSell reads, with no exceptions. The exception this function
    shipped last time - "a whitelist entry is a per-item instruction, not sale scope" - was true of
    adding one item and false of the Whitelist panel's Clear All and of `/im reset whitelist`, both
    of which un-protect every locked item at once, under a grant given while they were protected.

    Where this string is coarser than the tables it covers, it is because the code it mirrors
    short-circuits: a gate that makes a whole class of setting unable to move any verdict is hashed
    as that one gate, so an edit behind a closed gate does not re-arm a confirm nobody needed. Each
    collapse reads the gate itself - the module reference, the master toggle, the filter table the
    matcher looks up - never a copy of it.

    .claude/tests/autosell/test_autosell.lua drives mutations against both observables (does
    the grant survive; does a probe item's verdict change) and fails when the two disagree. Add the
    case there before changing what is hashed here.
]]
local function _AutoSellFingerprint()
    local db = IM.db and IM.db.global
    if not db then return "" end

    local parts = {}
    _AppendSettings(parts, "autoSell", db.autoSell)
    _AppendSettings(parts, "categoryExclusions", db.categoryExclusions)
    _AppendSettings(parts, "customCategoryExclusions", db.customCategoryExclusions)

    -- Enumerated, not counted or summed. Both tables are emptied wholesale by Clear All
    -- (ItemLock:ClearAllLocks, JunkList:ClearAllJunk) and by IM:ResetSection, and a digest that is
    -- not injective - a count, a sum - answers "unchanged" for a swap that trades one protected
    -- item for another. Cost: one part per entry, folded into the sort below, on a string rebuilt
    -- a handful of times per merchant visit. The harness measures and prints the per-call cost
    -- over a 1000-entry whitelist rather than restating a number here.
    _AppendSettings(parts, "whitelist", db.whitelist)
    _AppendSettings(parts, "junkList", db.junkList)

    -- MailHelper:ItemMatchesAnyRule refuses everything - whatever the rules say - when the module
    -- is absent or the master toggle is off, and ShouldAutoSell's mail tier is that call. Hashing
    -- rules behind either closed gate re-arms the confirm for an edit that cannot move a verdict,
    -- so the block collapses to the gate: `rulesLive` reads the same module reference and the same
    -- toggle those two gates read, rather than a copy of the condition. If some other path ever
    -- reaches a rule, the harness reports it as a verdict that moved while this string did not.
    local mailHelper = IM.modules and IM.modules.MailHelper
    local mail = db.mailHelper
    local rulesLive = (mailHelper and mailHelper.ItemMatchesAnyRule and mail and mail.enabled)
        and true or false
    table.insert(parts, "mailHelper.rulesLive=" .. _Field(rulesLive))

    if rulesLive then
        -- The matcher's own filter table, asked rather than restated: a rule whose filterType is
        -- not in it reaches FILTER_TYPES[filterType] == nil inside ItemMatchesFilter and refuses
        -- everything, exactly like a rule that is switched off.
        local filterTypes = (mailHelper.GetFilterTypes and mailHelper:GetFilterTypes()) or {}
        local seenRule = {}
        for _, rule in ipairs(mail.rules or {}) do
            -- Not keyed by index: the match is "any rule", so reordering cannot move a verdict and
            -- the sort below makes order invisible. A rule that cannot refuse anything contributes
            -- nothing at all, so deleting or editing it is invisible here too; switching it on
            -- adds its part. `name` and the identity of `alt` reach the refusal message and never
            -- the verdict, so neither is hashed.
            if rule.enabled and rule.alt and filterTypes[rule.filterType] then
                -- filterValue goes through _AppendSettings, not through _Field directly. _Field on
                -- a table hashes its ADDRESS, and an address does not move when the table behind it
                -- is edited in place - the stale-grant miss the recursion exists to kill, which
                -- this was the one line still reintroducing. Sorted, so a table-valued filterValue
                -- hashes the same whichever order pairs() walks it in.
                local ruleParts = {}
                _AppendSettings(ruleParts, "mailHelper.rule=" .. _Field(rule.filterType),
                    rule.filterValue)
                table.sort(ruleParts)
                local part = table.concat(ruleParts, ";")
                -- Deduplicated: two rules that hash alike refuse exactly what one of them refuses,
                -- so deleting the copy cannot move a verdict, and counting it would re-arm the
                -- confirm for a change that widens nothing. Rules only - every other part above is
                -- unique by its own key prefix, so a `seen` set would be a no-op there.
                if not seenRule[part] then
                    seenRule[part] = true
                    table.insert(parts, part)
                end
            end
        end
    end

    table.sort(parts)
    return table.concat(parts, ";")
end

-- The one phrase for "the server has not sent this item's data yet", in chat and in the vendor
-- popup alike. UI/AutoSellPopup.lua calls this rather than wording it again: the popup saying
-- "still loading" while chat said "waiting on item data" is one condition described as two, and a
-- player reasonably reads two descriptions as two problems.
-- @param count number - Items whose data has not arrived
function AutoSell.PendingDataPhrase(count)
    return count .. " item(s) still loading"
end

-- @param verb string - "is waiting for" / "gave up waiting for"
local function _PendingDataMessage(count, verb)
    return "Auto-sell " .. verb .. " " .. AutoSell.PendingDataPhrase(count) ..
        " - nothing was sold. Reopen the merchant once the Auto-Sell list finishes loading."
end

-- Take the confirm down and drop the list it described. Used whenever the dialog's statement stops
-- being true: consent granted, merchant closed, or a manual sale ran while it was still on screen.
local function _DismissConsentPrompt()
    _approvedItems = nil
    _approvalNonce = nil
    if _consentPending then
        _consentPending = false
        StaticPopup_Hide("INVENTORYMANAGER_AUTOSELL_CONFIRM")
    end
end

--[[
    Does this bag slot still hold what the queue entry says it holds?

    Call this rather than comparing itemIDs at the call site. It is run when a list is built AND
    again immediately before the sale, because the bags change in between; a safety check spelled
    out separately at those two moments is a safety check that will eventually disagree with
    itself, and the disagreement is resolved by vendoring the wrong item.

    @param entry table - Queue entry carrying bagID, slotID, itemID and (approved entries)
           stackCount
    @param checkStack boolean - Also require an unchanged stack size. True for approved entries:
           the user was quoted a price for that stack, so a split, a merge or a loot into the slot
           means it is no longer the thing they said yes to. False for a manual sale, where the
           list is whatever is in the bags right now.
    @return boolean matches
    @return table|nil info - The container info, non-nil whenever matches is true
]]
local function _SlotStillHolds(entry, checkStack)
    local info = C_Container.GetContainerItemInfo(entry.bagID, entry.slotID)
    if not info or not info.itemID or info.itemID ~= entry.itemID then
        return false, info
    end
    if checkStack and (info.stackCount or 1) ~= (entry.stackCount or 1) then
        return false, info
    end
    return true, info
end

local function _StillMatchesApproval(entry)
    local matches = _SlotStillHolds(entry, true)
    return matches
end

-- ============================================================================
-- REFUSAL PROSE
-- ============================================================================

--[[
    One reason -> prose mapping, read by every place that explains a refusal.

    It was written out twice - once in SellJunk's gate, once in FinishSelling's suppressed sweep -
    with different wording for the same reason and an independent `else` in each, so a fourth
    reason added to MayStartAutomaticSale was silently relabelled as "not approved" in both. One
    table means a new reason is worded once or not at all, and "not at all" is now visible instead
    of disguised.
]]
local GATE_REASON_PROSE = {
    ["visit-bound"] = "selling here was limited to the list you approved",
    ["settings-changed"] = "your settings changed since you approved automatic selling",
    ["no-consent"] = "automatic selling has not been approved",
}

-- An unmapped reason says so rather than borrowing one of the three above. A reason reported as
-- "not approved" when that is not why sends the player to re-approve something that was never the
-- problem, and leaves the real cause invisible in both the chat line and the bug report.
local function _GateReasonProse(reason)
    return GATE_REASON_PROSE[reason]
        or ("automatic selling was refused (" .. tostring(reason) .. ")")
end

--[[
    How many buyback entries the client shows on one page of the Buyback tab, or nil when that
    cannot be read as a usable count.

    This is Blizzard's BUYBACK_ITEMS_PER_PAGE and nothing more. It is deliberately NOT called the
    tab's capacity: the constant's own name says per PAGE, nobody here has observed whether the tab
    is one page, and asserting that those two numbers are the same would be a claim about the
    client written by hand - the exact thing this helper exists to stop. Two previous attempts to
    state a buyback number by hand were both wrong, in shipped user-facing text.

    Anything that is not a whole count of at least one is treated as unreadable rather than
    rendered. The global is a client value another addon can overwrite, and a sentence offering to
    show "the last -3 items" or "the last 1.5 items" is worse than one that declines to say.
]]
local function _BuybackPageSize()
    local perPage = tonumber(BUYBACK_ITEMS_PER_PAGE)
    if not perPage or perPage < 1 or perPage % 1 ~= 0 then return nil end
    return perPage
end

-- The one wording for that number, so the two sentences quoting it cannot drift into two different
-- claims about the same client constant. nil when there is no number to quote, and both callers
-- then say nothing about it at all - the same way both already decline to say how long the buyback
-- window lasts, which nobody here has observed either.
local function _BuybackPagePhrase()
    local perPage = _BuybackPageSize()
    return perPage and ("which lists " .. perPage .. " items at a time") or nil
end

local function _BuybackSentence()
    local phrase = _BuybackPagePhrase()
    return "Recently sold items can be bought back from this vendor's Buyback tab" ..
        (phrase and (", " .. phrase) or "") ..
        " - but that window does not last indefinitely, so check before you walk away."
end

StaticPopupDialogs["INVENTORYMANAGER_AUTOSELL_CONFIRM"] = {
    -- Both substitutions are built at show time by RequestSellConsent: the first names why the
    -- confirm appeared, the second is _BuybackSentence, whose page size is read from the client
    -- rather than typed here. The sentence deliberately still states no expiry - what ends the
    -- buyback window has never been observed in-game by anyone who wrote this string, so it says
    -- the part that is certain and stops.
    text = "%s\n\n"
        .. "Nothing else is sold at this vendor unless you click Sell All. %s\n\n"
        .. "Accepting also lets auto-sell run without asking again at later vendors this session, "
        .. "until you /reload or change your auto-sell settings.",
    button1 = "Sell",
    button2 = "Not now",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function()
        local module = IM.modules and IM.modules.AutoSell
        if not module then return end
        module:ConfirmApprovedSale()
    end,
    OnCancel = function()
        IM:Print("Auto-sell declined - nothing was sold.")
    end,
    -- Clears on every dismissal path, including Escape, so a declined confirm cannot wedge the
    -- gate and cannot leave an approved list alive behind a dialog nobody answered.
    OnHide = function()
        _consentPending = false
        _approvedItems = nil
        _approvalNonce = nil
    end,
}

function AutoSell:OnInitialize()
    IM:Debug("[AutoSell] Module initialized")
end

function AutoSell:OnEnable()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] OnEnable called, registering events...")

    -- Register for merchant events
    IM:RegisterEvent("MERCHANT_SHOW", function()
        IM:Debug("[AutoSell] MERCHANT_SHOW event received!")
        module:OnMerchantShow()
    end)

    IM:RegisterEvent("MERCHANT_CLOSED", function()
        module:OnMerchantClosed()
    end)

    -- The one item-data handler for the auto-sell path. See the ITEM DATA SIGNAL block above.
    IM:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if _itemDataNotifyQueued then return end
        _itemDataNotifyQueued = true

        local token = _itemDataNotifyToken
        C_Timer.After(ITEM_DATA_DEBOUNCE, function()
            if token ~= _itemDataNotifyToken then return end
            _NotifyItemData()
        end)
    end)

    -- No ITEM_LOCK_CHANGED handler - timer-only progression is more reliable

    IM:Debug("[AutoSell] Events registered successfully")
end

-- Called when merchant window opens
function AutoSell:OnMerchantShow()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] MERCHANT_SHOW fired, autoSellEnabled=" .. tostring(IM.db.global.autoSellEnabled))

    -- Fresh event, fresh budget: a previous visit that spent all its attempts waiting on item data
    -- must not leave this one unable to retry at all. Unconditional, including on a re-fire for an
    -- already-open window, so this can never wedge.
    _pendingAttempts.automatic = 0

    -- Nothing resets _visitBoundToApproval here. See its declaration: MERCHANT_SHOW is not the end
    -- of a visit, MERCHANT_CLOSED is.

    -- Always show the Auto-Sell popup when merchant opens
    if IM.UI and IM.UI.AutoSellPopup then
        C_Timer.After(0.1, function()
            IM.UI.AutoSellPopup:Show()
        end)
    end

    -- Check if auto-sell is enabled
    if not IM.db.global.autoSellEnabled then
        IM:Debug("[AutoSell] Auto-sell disabled, skipping")
        return
    end

    -- Small delay to let UI settle, then sell - but never without consent this session, and never
    -- past the gate the dialog's own promise set. This is a sale-start path, so it asks
    -- MayStartAutomaticSale the same question FinishSelling's sweep asks; before it did not ask at
    -- all, and a MERCHANT_SHOW re-fire could start a full-bag sale 0.2s after a dialog had told
    -- the player nothing else would be sold at this vendor.
    IM:Debug("[AutoSell] Scheduling sell in 0.2s...")
    C_Timer.After(0.2, function()
        if not MerchantFrame or not MerchantFrame:IsShown() then return end

        local allowed, reason = module:MayStartAutomaticSale()
        if allowed then
            IM:Debug("[AutoSell] Timer fired, automatic selling allowed, calling SellJunk")
            module:SellJunk(nil, true)
        elseif reason == "visit-bound" then
            -- The player already answered a dialog at this vendor. Asking again, or selling wider
            -- than the list they approved, both break the sentence they read.
            --
            -- Debug, not Print, and that is the decision rather than an oversight: what reaches
            -- here is a MERCHANT_SHOW the CLIENT fired, not an action the player took, and some
            -- vendors fire it repeatedly for a window already on screen. A chat line per re-fire
            -- would be noise attributable to nothing they did. The moment items they can see are
            -- being left behind IS worth saying, and FinishSelling's suppressed sweep says it
            -- there, with a count and a next step.
            IM:Debug("[AutoSell] Timer fired but this visit is bound to an approved list, standing down")
        else
            module:RequestSellConsent()
        end
    end)
end

--[[
    May an unattended, whole-bag sale START right now?

    The one gate. It is enforced from SellJunk, which is the only function that builds a sell
    queue, so it binds every unattended sale-start path there is rather than the ones somebody
    remembered to add a call to. Schedulers (the merchant-open timer, FinishSelling's post-sale
    sweep) ask it too, but only so they can say something useful about the refusal - their answer
    is advisory and can be stale by the time their timer comes due; SellJunk's is the one that
    decides.

    A sale carrying an approved list is not gated here. That sale is the answer to the dialog,
    bounded to the list the dialog quoted; it is the thing being consented to, not a thing needing
    consent.

    @return boolean allowed
    @return string|nil reason - "visit-bound" when a dialog-approved sale already ran at this
            merchant visit, "settings-changed" when a grant exists but under a different
            configuration, "no-consent" when none was ever given. nil when allowed.
]]
function AutoSell:MayStartAutomaticSale()
    if _visitBoundToApproval then
        return false, "visit-bound"
    end

    local allowed, consentReason = self:HasSessionConsent()
    if allowed then
        return true
    end
    return false, consentReason or "no-consent"
end

-- Grant automatic-sell consent for the rest of this session (until /reload or a settings change).
--
-- Do not call this from anywhere that is not the user answering the confirm dialog. It is the
-- whole permission the unattended path runs on, and granting it from a code path the player did
-- not click is indistinguishable, afterwards, from them having agreed.
function AutoSell:GrantSessionConsent()
    _sessionConsent.granted = true
    _sessionConsent.fingerprint = _AutoSellFingerprint()
    _DismissConsentPrompt()
    IM:Debug("[AutoSell] Session consent granted")
end

-- Is there a standing session grant, given under the settings in force right now?
--
-- This is the session-level half of the question. The visit-level half lives in
-- MayStartAutomaticSale, which is what a sale-start path should ask; this is for callers that
-- want the grant itself, such as /im status reporting whether automatic selling is armed.
-- @return boolean allowed
-- @return string|nil reason - "settings-changed" when a grant exists but was given under a
--         different configuration. nil otherwise, including when nothing was ever granted, so the
--         prompt can tell "you changed something" apart from "I never asked you".
function AutoSell:HasSessionConsent()
    if not _sessionConsent.granted then
        return false
    end
    if _sessionConsent.fingerprint ~= _AutoSellFingerprint() then
        return false, "settings-changed"
    end
    return true
end

--[[
    The user pressed Sell on the confirm. Sell the list the dialog quoted, nothing else, and leave
    this merchant visit bound to that list.

    The grant follows the sale rather than preceding it. "There is an approved list" is not the
    same fact as "a queue was built from it": every entry is re-checked against the bags first, and
    all of them can be gone by the time the dialog is answered. SellJunk's `started` is the weaker
    of those two facts - it says a queue was built and the loop began, not that any item was
    actually vendored, because the merchant can refuse every one of them. It is still the right
    thing to key the grant on: a click that could not even begin a sale described nothing, so it
    must not leave a standing permission to sell unattended behind it.
]]
function AutoSell:ConfirmApprovedSale()
    local approved = _approvedItems
    local nonce = _approvalNonce
    _DismissConsentPrompt()  -- clears both of those, hence the captures above

    local started, reason = false, nil
    if not approved or #approved == 0 then
        reason = "approval-consumed"
        IM:Debug("[AutoSell] Consent accepted but the approved list was already consumed")
    elseif not MerchantFrame or not MerchantFrame:IsShown() then
        reason = "no-merchant"
        IM:Debug("[AutoSell] Consent accepted after the merchant closed, nothing sold")
    else
        -- Bound BEFORE the sale, not after: a queue made entirely of items the merchant already
        -- refused reaches FinishSelling synchronously, and the sweep would read the flag before a
        -- later assignment could set it. Undone below if no sale actually started.
        local wasBound = _visitBoundToApproval
        _visitBoundToApproval = true
        -- Present the nonce minted with this list. This is the ONLY place it is presented, and
        -- SellJunk spends it immediately, so it cannot authorise a later call.
        _presentedNonce = nonce
        started, reason = self:SellJunk(approved, true)
        if not started then
            _visitBoundToApproval = wasBound
        end
    end

    if not started then
        -- Say the stop that happened. "Nothing could be sold" was printed for every refusal
        -- including "a sale is already running", which is the one case where the items are about
        -- to be sold and the sentence is the opposite of the truth.
        if reason == "already-selling" then
            IM:Print("A sale is already in progress, so that approval was not used - " ..
                "auto-sell will ask again at the next vendor.")
        elseif reason == "no-merchant" then
            IM:Print("The merchant closed before that sale could start - " ..
                "auto-sell will ask again at the next vendor.")
        else
            IM:Print("Nothing from that list could be sold, so automatic selling was not approved - " ..
                "auto-sell will ask again at the next vendor.")
        end
        return
    end

    self:GrantSessionConsent()
end

--[[
    Ask, once per session, before the addon sells anything on its own.

    The dialog quotes a count and a value; those numbers come from this scan and this scan becomes
    the approved list, so the sale that follows is the sale that was described. A scan taken while
    item data is still arriving would describe a different, smaller sale than the one that would
    run, so the prompt waits for the loads to settle first - on the shared item-data signal rather
    than a poll of its own, spending the automatic path's per-visit retry budget.
]]
function AutoSell:RequestSellConsent()
    local module = self

    local allowed, consentReason = self:HasSessionConsent()
    if allowed or _consentPending then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then return end

    local items, pendingItems = IM.Filters:GetAutoSellItems()
    local pendingCount = pendingItems and #pendingItems or 0

    -- Still loading: wait rather than quote a figure over a half-finished scan.
    if pendingCount > 0 and _pendingAttempts.automatic < MAX_PENDING_ATTEMPTS then
        _pendingAttempts.automatic = _pendingAttempts.automatic + 1
        IM:Debug("[AutoSell] Consent deferred, " .. pendingCount .. " items pending, attempt " .. _pendingAttempts.automatic)
        _WaitForItemData(function()
            module:RequestSellConsent()
        end)
        return
    end

    if #items == 0 then
        if pendingCount > 0 then
            -- Items still pending here means the budget above is spent. "Gave up waiting" and
            -- "nothing to sell" are different answers and the user gets to tell them apart; the
            -- Auto-Sell window says the same thing while it waits.
            IM:Print(_PendingDataMessage(pendingCount, "gave up waiting for"))
        else
            IM:Debug("[AutoSell] Nothing eligible to sell, not asking for consent")
        end
        return
    end

    local count, value = 0, 0
    for _, item in ipairs(items) do
        item.approved = true
        count = count + (item.stackCount or 1)
        value = value + (item.totalValue or 0)
    end

    -- A re-armed confirm is otherwise word-for-word a first-time confirm, and the player cannot
    -- tell "asking because you changed a setting" from "the addon forgot".
    --
    -- It says "settings", not "auto-sell settings", and names nothing: the gate compares two
    -- strings, so it cannot say which setting moved, and the one that moved may not live in the
    -- auto-sell panel at all - a mail rule re-arms this too. Guessing a cause would send the
    -- player to the wrong panel.
    local lead = ""
    if consentReason == "settings-changed" then
        lead = "Your InventoryManager settings changed since you approved automatic selling, so " ..
            "this needs confirming again.\n\n"
    end

    local summary = lead .. "InventoryManager is about to sell " .. count ..
        (count == 1 and " item for " or " items for ") .. IM:FormatMoney(value) .. "."
    if pendingCount > 0 then
        summary = summary .. "\n\n" .. pendingCount ..
            " further item(s) never finished loading and are NOT part of this sale. Reopen the " ..
            "merchant once they have loaded to include them."
    end

    _approvedItems = items
    -- Minted here and nowhere else, bound to this exact table. See the declaration: without it the
    -- gate's approved-list exemption is a bearer token.
    _approvalNonce = { items = items }
    _consentPending = true

    local dialog = StaticPopup_Show("INVENTORYMANAGER_AUTOSELL_CONFIRM", summary, _BuybackSentence())
    if not dialog then
        -- Every Blizzard popup slot is taken by other addons. Fail closed and say so: with no
        -- dialog there is no OnHide, so nothing would ever clear the gate, and a prompt that never
        -- appears is indistinguishable from an addon that decided to stay quiet.
        _consentPending = false
        _approvedItems = nil
        _approvalNonce = nil
        IM:PrintError("Could not show the auto-sell confirmation (no free dialog slot). " ..
            "Nothing was sold - close another popup and reopen the merchant.")
        return
    end

    IM:Debug("[AutoSell] Requesting sell consent for " .. count .. " items")
end

-- Called when merchant window closes
function AutoSell:OnMerchantClosed()
    -- Cancel any pending sales
    self:CancelSelling()

    -- Don't leave a sell confirm on screen for a merchant that is gone
    _DismissConsentPrompt()

    -- Drop anything waiting on item data. A wait armed at this vendor must not come due at the
    -- next one and start a sale nobody asked for there.
    _CancelItemDataWaiters()

    -- Clear rejected items list for next merchant
    wipe(_rejectedItems)

    -- The visit is over, so everything scoped to it goes with it. This is the ONLY place the
    -- approval bind is cleared: it was previously cleared on MERCHANT_SHOW instead, which both
    -- dropped it halfway through a visit whose dialog was still governing (a re-fire with no
    -- merchant unit yet) and left it standing at a vendor after the player walked away, so a later
    -- visit could be told its sale "was limited to the list you approved" when no dialog had been
    -- shown at all.
    _visitBoundToApproval = false
    _pendingAttempts.automatic = 0
    _pendingAttempts.manual = 0

    -- Hide the Auto-Sell popup
    if IM.UI and IM.UI.AutoSellPopup then
        IM.UI.AutoSellPopup:Hide()
    end
end

-- Cancel ongoing sell operation
function AutoSell:CancelSelling()
    _isSelling = false
    wipe(_sellQueue)
    if _sellTimer then
        _sellTimer:Cancel()
        _sellTimer = nil
    end
end

--[[
    Start selling.

    @param approvedItems table|nil - The exact list the confirm dialog quoted. When given, ONLY
           those bag slots may be sold, and only while they still hold what was approved: the bags
           are NOT re-scanned, so an item that became eligible after the dialog was drawn is not
           swept into a sale the user never saw. When nil (the popup's "Sell All", /im sell) the
           current filter result is used - that is the list the user is looking at.

           The approved list only ever narrows. Every entry still passes ShouldAutoSell immediately
           before it is sold, so approval can never authorise something the filter now refuses.

    @param isAutomatic boolean|nil - True when the addon started this sale itself (the confirm's
           OnAccept, the merchant-open path once consent is granted, and their continuations).
           False/nil for a sale the user started by hand. It has to be passed rather than inferred:
           the automatic path at a later vendor also carries no approved list, so "approvedItems is
           nil" does not mean "the user clicked something". FinishSelling's sweep keys on this.

    @param isRetry boolean|nil - True only for the module's own continuation after waiting on item
           data. It exists so a fresh manual click can be told apart from the tail of an earlier
           one, and refill the manual retry budget; a retry must not refill it or the budget would
           never run out.

    @return boolean started - True only when a queue was built and the sell loop began on this
            call. It does NOT mean anything was vendored: the merchant can refuse every entry.
            False for every early exit, including "waiting on item data" - a sale that may yet
            start from the retry has not started now.
    @return string|nil reason - Why not, when started is false: "no-merchant", "already-selling",
            "waiting-on-data", "gave-up-waiting", "nothing-to-sell", or one of
            MayStartAutomaticSale's refusals ("visit-bound", "settings-changed", "no-consent")
            when an unattended sale was not authorised. Callers report the stop from this rather
            than guessing a cause from the fact that a sale did not begin.
]]
function AutoSell:SellJunk(approvedItems, isAutomatic, isRetry)
    local module = self  -- Capture for closures

    isAutomatic = isAutomatic and true or false

    --[[
        Spend the presented nonce, before anything else and whatever this call turns out to be. A
        presentation left armed by an early return would authorise the NEXT call instead, which is
        the same bearer-token hole one step along.

        Then: an approved list is only an approved list if the nonce minted with it is the one
        being presented. Without this, `approvedItems ~= nil` was the entire proof, so
        SellJunk({{bagID=0, slotID=1, itemID=111, stackCount=1, approved=true}}, true) vendored
        without a dialog, without a grant and without binding the visit. The type test is part of
        the same check rather than a separate nicety: a truthy non-table used to skip the gate here
        and then raise inside ipairs further down, which is a bypass that ends in an error instead
        of a refusal.
    ]]
    local presented = _presentedNonce
    _presentedNonce = nil

    if approvedItems ~= nil and
        (type(approvedItems) ~= "table" or presented == nil or presented.items ~= approvedItems) then
        IM:Debug("[AutoSell] SellJunk: approved list refused - it carries no matching consent proof")
        IM:PrintError("An approved-sale request arrived without the confirmation that authorises " ..
            "it. Nothing was sold.")
        return false, "unapproved-list"
    end

    IM:Debug("[AutoSell] SellJunk called" .. (approvedItems and (" with an approved list of " .. #approvedItems) or "") ..
        (isAutomatic and " (automatic)" or " (manual)"))

    -- A hand-clicked sale is an explicit request, so it brings its own attempts. See
    -- _pendingAttempts: the automatic path can empty its budget without the player ever seeing a
    -- message, and their first click must not be answered with "gave up waiting".
    if not isAutomatic and not isRetry then
        _pendingAttempts.manual = 0
    end

    local budget = isAutomatic and "automatic" or "manual"

    -- Check if at merchant
    if not MerchantFrame then
        IM:Debug("[AutoSell] SellJunk: MerchantFrame is nil")
        IM:Print("You must be at a merchant to sell items")
        return false, "no-merchant"
    end

    if not MerchantFrame:IsShown() then
        IM:Debug("[AutoSell] SellJunk: MerchantFrame not shown")
        IM:Print("You must be at a merchant to sell items")
        return false, "no-merchant"
    end

    --[[
        THE authorization chokepoint for unattended selling.

        Every whole-bag automatic sale is authorised here, and nowhere else is sufficient. This
        function is the only place a sell queue is built and _isSelling is set, so a path that
        starts a sale must traverse it - which is what makes the check unroutable-around. Asking
        the gate at the call sites instead makes "every sale-start path asks" a hand-maintained
        list, and a list is only as good as the next round's memory: the round that added the
        item-data retry added a sale-start path (the waiter re-enters SellJunk with no approved
        list) without adding a check, so a grant withdrawn during the wait still sold.

        Exempt: a sale carrying an approved list. That sale IS the answer to the dialog - it is
        deliberately bound to the visit the gate refuses on, so asking here would refuse the one
        sale the user explicitly authorised.

        The schedulers keep their own checks. They are not the authority; they are there to say
        something useful (ask for consent, name why the sweep stood down) instead of stopping
        silently.
    ]]
    if isAutomatic and not approvedItems then
        local mayStart, gateReason = self:MayStartAutomaticSale()
        if not mayStart then
            IM:Debug("[AutoSell] SellJunk: automatic sale refused by the gate: " .. tostring(gateReason))
            -- Say it, because nothing else will: this is the sale a scheduler already decided to
            -- run, so no scheduler is going to explain why it did not.
            --
            -- "visit-bound" is the one exception, and it is silent DELIBERATELY: it is the
            -- expected state for the rest of an approved visit rather than a change of mind, and
            -- nothing the player just did produces it. The one moment they ARE owed it is when
            -- items they can see are being left behind, and FinishSelling's suppressed sweep says
            -- so there, with a count.
            --
            -- The wording states outright that nothing was sold: "automatic selling stopped" read
            -- as a sale being interrupted part-way, which is the opposite of what happened. It
            -- also names Sell All, because the button is on screen and still works right now - its
            -- sibling in FinishSelling always said so and this one never did.
            if gateReason ~= "visit-bound" then
                IM:Print("Nothing was sold automatically because " .. _GateReasonProse(gateReason) ..
                    ". The Sell All button still works right now, and auto-sell will ask again at " ..
                    "the next vendor.")
            end
            return false, gateReason or "no-consent"
        end
    end

    -- Don't start if already selling. This is ABOVE the dismissal below, not underneath it: a
    -- click that sells nothing must not destroy anything either. Clicking Sell All while a sale is
    -- already running is answered with "already-selling", and taking the confirm down first meant
    -- a player part-way through answering a dialog watched it vanish, with its approved list, for
    -- a click that vendored not one item.
    if _isSelling then
        IM:Debug("[AutoSell] SellJunk: Already selling, skipping")
        return false, "already-selling"
    end

    if not isAutomatic then
        -- A manual sale is not an answer to the confirm. Take the dialog down rather than leave it
        -- describing a sale that already happened - and grant nothing: the automatic path stays
        -- gated and will ask again on the next merchant visit.
        _DismissConsentPrompt()
    end

    IM:Debug("[AutoSell] SellJunk: Getting items to sell...")

    -- Get items to sell
    local items, pendingItems
    if approvedItems then
        -- Bound to what was approved; whatever no longer matches is simply not sold.
        items = {}
        for _, entry in ipairs(approvedItems) do
            if _StillMatchesApproval(entry) then
                table.insert(items, entry)
            else
                IM:Debug("[AutoSell] Approved slot no longer matches, dropping: bag=" ..
                    tostring(entry.bagID) .. " slot=" .. tostring(entry.slotID) .. " itemID=" .. tostring(entry.itemID))
            end
        end
        IM:Debug("[AutoSell] SellJunk: " .. #items .. " of " .. #approvedItems .. " approved items still match")
    else
        items, pendingItems = IM.Filters:GetAutoSellItems(true)  -- verbose=true for actual selling
        IM:Debug("[AutoSell] SellJunk: GetAutoSellItems returned " .. #items .. " items")
    end

    if #items == 0 then
        if pendingItems and #pendingItems > 0 then
            if _pendingAttempts[budget] < MAX_PENDING_ATTEMPTS then
                _pendingAttempts[budget] = _pendingAttempts[budget] + 1
                IM:Debug("[AutoSell] Waiting on item info (" .. #pendingItems .. " pending), " ..
                    budget .. " attempt " .. _pendingAttempts[budget])
                -- Same signal the consent prompt waits on, so the two do not walk the bags
                -- independently on the same burst of arriving data.
                _WaitForItemData(function()
                    if MerchantFrame and MerchantFrame:IsShown() then
                        module:SellJunk(nil, isAutomatic, true)
                    end
                end)
                return false, "waiting-on-data"
            end
            -- Budget spent with data still missing. Say so: a silent stop here looks exactly
            -- like "there was nothing to sell".
            IM:Print(_PendingDataMessage(#pendingItems, "gave up waiting for"))
            return false, "gave-up-waiting"
        end
        -- No message for the approved case: ConfirmApprovedSale owns that one, because it also
        -- knows the consequence for the session grant and would otherwise say it twice.
        IM:Debug("[AutoSell] No items to sell")
        _pendingAttempts[budget] = 0
        return false, "nothing-to-sell"
    end
    _pendingAttempts[budget] = 0

    -- Reset session stats
    _sessionStats.itemCount = 0
    _sessionStats.totalValue = 0

    -- Build sell queue
    wipe(_sellQueue)
    for _, item in ipairs(items) do
        table.insert(_sellQueue, item)
    end

    IM:Debug("[AutoSell] Starting to sell " .. #_sellQueue .. " items")
    for i, item in ipairs(_sellQueue) do
        IM:Debug("[AutoSell]   Queue[" .. i .. "]: " .. (item.itemLink or item.itemID))
    end

    -- Start selling
    _isSelling = true
    _currentSaleIsAutomatic = isAutomatic
    self:ProcessNextItem()

    return true
end

-- Process the next item in the queue
function AutoSell:ProcessNextItem()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] ProcessNextItem called, _isSelling=" .. tostring(_isSelling) .. ", queueSize=" .. #_sellQueue)

    -- Safety check
    if not _isSelling then
        IM:Debug("[AutoSell] ProcessNextItem: Not selling, returning")
        return
    end

    -- Check if queue is empty
    if #_sellQueue == 0 then
        IM:Debug("[AutoSell] ProcessNextItem: Queue empty, finishing")
        module:FinishSelling()
        return
    end

    -- Check if merchant is still open
    if not MerchantFrame or not MerchantFrame:IsShown() then
        IM:Debug("[AutoSell] ProcessNextItem: Merchant closed, cancelling")
        module:CancelSelling()
        return
    end

    -- Get next item
    local item = table.remove(_sellQueue, 1)
    IM:Debug("[AutoSell] Processing: bag=" .. item.bagID .. " slot=" .. item.slotID .. " itemID=" .. item.itemID)

    -- Skip items the merchant already rejected this session
    if _rejectedItems[item.itemID] then
        IM:Debug("[AutoSell] SKIPPING rejected item (merchant won't buy): " .. (item.itemLink or item.itemID))
        module:ProcessNextItem()
        return
    end

    -- Verify the slot still holds what the queue entry says. Same check the approved list was
    -- filtered with, run again here because the bags can change between the two - and it is the
    -- SAME function, so the two can never drift apart. Approved entries additionally carry the
    -- stack size the user was shown a price for: a split, a merge or a loot into the slot means it
    -- is no longer what they approved, so it is left for the next scan to offer again.
    local matches, info = _SlotStillHolds(item, item.approved == true)
    if not matches then
        IM:Debug("[AutoSell] Slot no longer holds the queued item, skipping: expected itemID=" ..
            tostring(item.itemID) .. " stack=" .. tostring(item.stackCount) ..
            ", found itemID=" .. tostring(info and info.itemID) ..
            " stack=" .. tostring(info and info.stackCount))
        module:ProcessNextItem()
        return
    end

    -- Check if item is locked (being moved/processed)
    if info.isLocked then
        IM:Debug("[AutoSell] Item is locked, waiting...")
        -- Wait a bit and try again, but check merchant is still open
        C_Timer.After(0.1, function()
            -- Double-check both _isSelling flag AND merchant is still open
            if _isSelling and MerchantFrame and MerchantFrame:IsShown() then
                -- Put item back at front of queue
                table.insert(_sellQueue, 1, item)
                module:ProcessNextItem()
            else
                -- Merchant closed or selling cancelled - ensure clean state
                IM:Debug("[AutoSell] Sell cancelled during locked item retry, cleaning up")
                module:CancelSelling()
            end
        end)
        return
    end

    -- Verify item still passes filters (in case whitelist changed)
    local shouldSell = IM.Filters:ShouldAutoSell(item.bagID, item.slotID, item.itemID, item.itemLink, true)
    if not shouldSell then
        IM:Debug("[AutoSell] Item no longer passes filters: " .. (item.itemLink or item.itemID))
        module:ProcessNextItem()
        return
    end

    -- Get sell price for stats (display only - VendorTracking handles ledger logging)
    local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(item.itemID)
    if sellPrice then
        _sessionStats.itemCount = _sessionStats.itemCount + (info.stackCount or 1)
        _sessionStats.totalValue = _sessionStats.totalValue + (sellPrice * (info.stackCount or 1))
        -- Note: VendorTracking now handles logging via PLAYER_MONEY event
    end

    -- Sell the item by using it on merchant
    IM:Debug("[AutoSell] >>> SELLING: " .. (item.itemLink or item.itemID) .. " via C_Container.UseContainerItem(" .. item.bagID .. ", " .. item.slotID .. ")")

    local success, err = pcall(function()
        C_Container.UseContainerItem(item.bagID, item.slotID)
    end)

    if not success then
        IM:Debug("[AutoSell] <<< UseContainerItem error: " .. tostring(err))
        -- Retry after longer delay if busy
        _sellTimer = C_Timer.NewTimer(0.3, function()
            if _isSelling and MerchantFrame and MerchantFrame:IsShown() then
                -- Put item back for retry
                table.insert(_sellQueue, 1, item)
                module:ProcessNextItem()
            end
        end)
        return
    end

    IM:Debug("[AutoSell] <<< UseContainerItem returned")

    -- Timer-based progression: wait for sell to complete, then check result
    local checkBagID, checkSlotID, checkItemID = item.bagID, item.slotID, item.itemID
    _sellTimer = C_Timer.NewTimer(0.15, function()
        if not _isSelling or not MerchantFrame or not MerchantFrame:IsShown() then
            return
        end

        local checkInfo = C_Container.GetContainerItemInfo(checkBagID, checkSlotID)

        if not checkInfo or checkInfo.itemID ~= checkItemID then
            -- Item gone or different item = sold successfully
            IM:Debug("[AutoSell] Timer: Item sold successfully")
        else
            -- Same item still there = merchant rejected it
            IM:Debug("[AutoSell] Timer: Item rejected by merchant")
            _rejectedItems[checkItemID] = true
            -- Undo stats we added
            local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(checkItemID)
            if sellPrice then
                _sessionStats.itemCount = _sessionStats.itemCount - (checkInfo.stackCount or 1)
                _sessionStats.totalValue = _sessionStats.totalValue - (sellPrice * (checkInfo.stackCount or 1))
            end
        end

        -- Process next item
        module:ProcessNextItem()
    end)
end

-- Finish selling session
function AutoSell:FinishSelling()
    local module = self  -- Capture for closures

    IM:Debug("[AutoSell] FinishSelling called, itemCount=" .. _sessionStats.itemCount .. ", totalValue=" .. _sessionStats.totalValue)
    _isSelling = false

    if _sessionStats.itemCount > 0 then
        -- Also shown here, not only in the confirm dialog, so a player who declines the confirm and
        -- only ever clicks Sell All still gets a buyback warning. No page-size number here: itemCount
        -- sums item units across stacks, while a buyback slot is one stack, so quoting the page size
        -- beside this count would invite a comparison that does not hold. And it stops short of
        -- claiming every item just sold is still there - only the most recent entries are.
        IM:Print("Sold " .. _sessionStats.itemCount .. " items for " .. IM:FormatMoney(_sessionStats.totalValue) ..
            " - only the most recently sold items are still in this vendor's Buyback tab; earlier ones may already be gone.")
    else
        IM:Debug("[AutoSell] No items were sold")
    end

    -- Reset stats
    _sessionStats.itemCount = 0
    _sessionStats.totalValue = 0

    -- Refresh the Auto-Sell popup
    if IM.UI and IM.UI.AutoSellPopup and IM.UI.AutoSellPopup:IsShown() then
        IM.UI.AutoSellPopup:Refresh()
    end

    -- If additional items become eligible after item data loads, keep selling - but only ones the
    -- filter accepts NOW. Items still waiting on data are not swept in here; they are left to the
    -- wait-and-retry inside SellJunk, which is where the remaining attempts are counted.
    if MerchantFrame and MerchantFrame:IsShown() then
        local items, pendingItems = IM.Filters:GetAutoSellItems()

        -- Filter out rejected items
        local validItems = {}
        local filteredCount = 0
        for _, item in ipairs(items or {}) do
            if not _rejectedItems[item.itemID] then
                table.insert(validItems, item)
            else
                filteredCount = filteredCount + 1
            end
        end

        IM:Debug("[AutoSell] FinishSelling check: " .. #(items or {}) .. " found, " .. filteredCount .. " rejected, " .. #validItems .. " valid, " .. #(pendingItems or {}) .. " pending")

        -- The sweep is a sale-start path, so the shared gate decides it. The one extra term is
        -- _currentSaleIsAutomatic, which is about THIS sale rather than the visit: a hand-clicked
        -- Sell All at a vendor visited after consent was given is still manual, and sweeping there
        -- would vendor items that were never on screen. The branch underneath reports whichever
        -- term refused, so the condition and the explanation cannot drift into different accounts
        -- of the same stop.
        -- Asked only when there is something to sweep: the gate rebuilds the settings fingerprint,
        -- and there is no reason to pay for that at the end of every sale that swept nothing.
        local maySweep, sweepBlock
        if #validItems > 0 then
            maySweep, sweepBlock = self:MayStartAutomaticSale()
        end

        if #validItems > 0 and _currentSaleIsAutomatic and maySweep then
            C_Timer.After(0.2, function()
                if not _isSelling and MerchantFrame and MerchantFrame:IsShown() then
                    module:SellJunk(nil, true)
                end
            end)
        elseif #validItems > 0 then
            -- Suppressing the sweep silently looks exactly like the addon breaking: the items are
            -- still in the bags, nothing was said, and the Auto-Sell popup only redraws itself
            -- when it happens to be open. Name the reason and give the next step.
            local why
            if not _currentSaleIsAutomatic then
                -- Not a gate reason: the gate may well have allowed this, and the term that
                -- refused is about THIS sale rather than the visit.
                why = "this sale was started by hand"
            else
                why = _GateReasonProse(sweepBlock)
            end
            IM:Print(#validItems .. " more item(s) now match your auto-sell filters, but " .. why ..
                " - click Sell All to sell them too.")
            IM:Debug("[AutoSell] Sweep suppressed: block=" .. tostring(sweepBlock) ..
                " automatic=" .. tostring(_currentSaleIsAutomatic))
        elseif pendingItems and #pendingItems > 0 then
            IM:Debug("[AutoSell] Only pending items remain (" .. #pendingItems .. "), letting retry logic handle it")
        end
    end
end

-- Get count of sellable items (for UI display)
function AutoSell:GetSellableCount()
    return IM.Filters:GetAutoSellCount()
end

-- Check if currently selling
function AutoSell:IsSelling()
    return _isSelling
end

-- Get remaining items in queue
function AutoSell:GetQueueSize()
    return #_sellQueue
end
