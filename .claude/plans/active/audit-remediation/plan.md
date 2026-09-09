---
name: audit-remediation
plan-id: 2026-09-07-audit-remediation
status: active
tier: opord
tier-reason: Mechanically triggered — unbounded blast radius (W2/W3), an EX-HIGH reversibility hazard (irreplaceable item destruction, unrecoverable SavedVariables loss), and two Floor-B classes touched (money movement, irreversible operations). No override available.
execution-branch: main
execution-worktree: none (/home/patrick/development/wow/InventoryManager)
session-id:
  - 7d6ca3d0-55ef-47b1-8349-7f5fbbc6fb4b
  - exec-p1-a1f7c2
  - exec-p1-fix1-6b3e91
  - exec-p1-fix2-d47a05
  - exec-p1-fix3-9c02be
  - exec-p1-fix4-e51d77
  - exec-p1-fix5-3ab8e0
  - exec-p1-fix6-7d41c9
  - exec-p1-fix7-b82f10
  - exec-p1-fix8-4e77a3
  - exec-p1-fix9-c60f21
  - exec-p1-fix10-a04b2e
created_at: 2026-09-07
updated_at: 2026-09-08
---

# PLAN: audit-remediation

Remediation of every finding from five completed audits of the InventoryManager WoW addon,
shipped as a single 1.4.0 release. Every numbered finding in the brief has exactly one home below —
or, for eight of them, two labelled work items **both** of which must close; the coverage index in
Appendix A proves it and is the authority on completeness. **The count is now 127, not 125**: two
findings came from neither an audit nor a review pass. **OQ-1** (Phase 11) came from a question the
owner asked while reading revision five and that was answered in revision six, and it is a
data-loss defect. **OQ-2** (Phase 3) came from reading the owner's own in-game debug log during
Phase 0 execution — four startup paths re-entering their own work on every login with no completion
latch — and its addition to this table is itself a bookkeeping correction: an earlier revision folded
that same remediation work into Phase 3's scope with no coverage-index row, which is exactly the
silent-discharge shape this plan's own risk R11 exists to catch. See Appendix A.

> **Two findings in this plan were found by the owner or by reading a live trace, not by the audits
> or the review passes, and both are signals about where the remaining blind spots are.**
>
> **OQ-1** — the two stores expire on different axes, so dropping `sellHistory` destroys entries
> that exist nowhere else — survived five planner rounds and four review rounds. Every one of those
> passes read `sellHistory` as *duplicate* data because the v1→v2 migration had copied it, and
> nobody checked whether the copies were still there. The blind spot was not the code; it was that
> the plan reasoned about the *shape* of the two stores and never about their **lifetimes**. Any
> future review of a store-retirement in this plan should ask the lifetime question first: what
> deletes rows from each side, on what axis, and can one side outlive the other?
>
> **OQ-1 is closed by an owner decision to ACCEPT the loss, not by a fix.** Revision six proposed a
> consolidation merge into `transactions`; revision seven withdraws it on the owner's decision and
> on the merits — his retention setting already declares data past the window unwanted, those rows
> survived only by an accident of the 100-entry count cap, and rescuing them into the store his own
> policy purges is circular. The finding stays on the coverage index as a **finding closed by
> decision** (Appendix B, **L1**), and the lesson above survives the decision unchanged. **Owner
> silence would not have closed it** — an explicit accept did.
>
> **OQ-2** — four startup paths (BagUI's override bindings, `BagData`'s full refresh,
> `InventorySnapshot`'s startup scan, `NetWorth`'s gold-update logging) each re-run their real work
> multiple times on a single login, with no completion latch — was found by reading the owner's
> in-game debug log during Phase 0 execution, by no audit and no review pass. Every audit reasoned
> about steady-state event handling — what a handler does when it fires during play — and none of
> them read a login trace to see how many times a startup handler actually fires before the client
> settles. That is the same class of blind spot as OQ-1's: the process reasoned about a *shape*
> (what the code does) and never observed a *trace* (how many times, over what window, it actually
> runs). Any future audit of a startup path in this plan should read a real `/reload` debug trace
> before trusting the handler list.
>
> **OQ-2 is closed by a fix, not a decision.** Phase 3's login-settle latch (step 3), keyed on
> successful completion rather than on first firing, collapses all four paths to once per login —
> and, unlike a fire-once latch, leaves `InventorySnapshot`'s scan re-runnable when Phase 9's
> `ScanBags` honest-return fix reports a real failure. The close condition is the in-game cross-check
> both phases carry in their exit criteria, not a `git show` on either phase alone. **This finding
> was also, until this revision, the exact defect its own sibling risk R11 exists to catch**: it was
> real remediation work folded into Phase 3's scope with no coverage-index row, discovered by
> re-reading this plan rather than by a new observation in-game. It is corrected here, not deferred.

> **How this plan treats completeness, stated once at the top because it changed the shape of
> Phase 11.** Where a set's exhaustiveness cannot be proved by listing it — every write site into a
> character-keyed table, every reader and writer of a field a migration rewrites — this plan
> carries a **non-exhaustive seed list plus a step that derives the real set by grep at execution
> time**, and the grep is authoritative. A hand-written list in a plan is a guess; a grep run in
> the tree is a fact. Three review rounds each found a different missing member of exactly those
> sets, which is what earned the rule.

> Anchor: rationale, evidence and alternatives weighed for each decision go in the commit that
> implements it (`git log --grep=audit-remediation`). This document carries current state only.

---

## 1. Situation

### Terrain (code and systems touched)

- **`Core.lua`** — module registry (`RegisterModule:96-106`, 33 modules) and the event dispatcher
  (`RegisterEvent:60-66`, dispatch `:87-93`, `UnregisterEvent:74`). `OnEnable` runs under
  `pairs(IM.modules)` (`:342-346`), so `.toc`/registration order is discarded and **handler order
  equals OnEnable order** — 119 registrations, 26 events with more than one handler
  (`PLAYER_MONEY` 11, `BAG_UPDATE_DELAYED` 9, `PLAYER_ENTERING_WORLD` 7, `MERCHANT_SHOW` 5).
  `Core.lua:366-369` unregisters `handlers[1]` from inside an `ADDON_LOADED` dispatch; the
  `table.remove` shifts index 2 into 1 and `ipairs` terminates, silently skipping
  `CurrencySearch.lua:25`. `_G.InventoryManager = IM` (`:10`, `:754`) exposes the whole namespace
  including `IM.db` to any other addon — this is why W2 and W3 are unbounded.
- **`Database.lua`** — `DB_VERSION = 2` (`:9`), 24 top-level global keys, empty unread
  `defaults.char` (`:164-167`). `_mergeDefaults:181-192` forces any table-shaped default onto the
  stored value and can never remove a stale key. `_runMigrations:195-248` v1→v2 is **not
  idempotent by construction** — it appends `sellHistory.entries` into `transactions.entries` with
  no dedupe key, guarded only by the version stamp at `:245`. `IM.OnDatabaseReady` is invoked
  (`:269-271`) and defined nowhere.
  **The two stores expire on different axes, and that is the producer of OQ-1.** `sellHistory` is
  capped **by count** — `maxEntries = 100` (`:72`), trimmed in `IM:AddHistoryEntry` at `:399-401` —
  while `transactions` is purged **by age**: `ledger.maxAgeDays = 30` (`:78`) and
  `IM:PurgeOldEntries` (`:799-822`) removes `transactions.entries` where `entry.ts < time() -
  maxAgeDays*86400` (`:805,811`), fired 5s after login and every 600s (`Modules/Ledger.lua:100-106`).
  So for any user who sells infrequently the 100 rows in `sellHistory` span **more than 30 days**:
  v1→v2 copied them into `transactions` (`:206-247`), the age purge then deleted the copies, and the
  originals survived because 100 rows had not rolled over. **Those rows now exist ONLY in the legacy
  store, so the v3 drop destroys them — and the owner has decided to accept that loss** rather than
  merge them into the store his own retention policy purges. By design, not by defect; recorded with
  all four fields as Appendix B **L1**. `GetCharacterKey:542-552` does no realm normalization;
  `GetNormalizedRealmName` appears zero times in the tree; **18 sites** greedy-parse the key with
  `:match("^(.+)-")`, alongside **7** already-correct realm parses `:match("-(.+)$")` — **25
  enumerated line entries** in all (Phase 11 step 1 lists them and makes the grep, not the count,
  the gate). Earlier revisions of this plan and of the brief said "24 sites", which matched neither
  the enumeration nor the defect count.
- **Tracking subsystem** (`Modules/Tracking/*`) — 13 modules, each with a private `_lastGold`
  baseline. `IM:ClaimGoldChange` has exactly one caller; `IsInTrackedContext`
  (`UnclaimedGoldTracking.lua:107-166`) is a frame-context whitelist with no loot/quest/flight
  branch. The result is systematic double-booking.
- **`NetWorth.lua` / `InventorySnapshot.lua`** — hold account-shared data (warband bank gold and
  items) in per-character slots, and overwrite good snapshots with empty scans.
- **`UI/Core.lua`** — the component factory. 36 public methods, 9 public data tables.
  **FENCED, ADD ONLY** (see below).
- **`UI/Dashboard.lua`** — 1700+ lines; frame pooling implemented in 1 of 3 refresh paths; 5 raw
  `UIDropDownMenuTemplate`, 2 raw `EditBox`, **22 hardcoded hex `|cff…` literals** (plus three
  dynamic class-colour constructions and three token-sourced strings that are correct and stay);
  six dead `SetTextColor` calls on money-formatter output, of which only four carry the `money`
  token.
- **`UI/MailPopup.lua` / `UI/AutoSellPopup.lua`** — converged on paint, diverged on interaction.
- **`UI/BagUI/*`** — the custom bag subsystem, not a registered module; registers four handlers at
  file scope. Owner-tuned; see the fence and the approval gates.
- **`.claude/CLAUDE.md` + registry** — assert several things that are false, including a
  CRITICAL-tagged rule that is a no-op in Lua and a prescribed 25-file sweep.

### The `UI/Core.lua` fence — hard constraint, restated in every phase that touches it

**ADD ONLY.** These twelve signatures AND their observable behavior are frozen because
`UI/BagUI/*`, `UI/Panels/BagUI.lua` or `UI/Panels/UI.lua` consume them: `CreatePanel`,
`CreateHeader`, `MakeRounded`, `CreateGlyphButton`, `CreateRailRow`, `CreateScrollFrame`,
`CreateCard`, `CreateButton`, `AttachRing`, `CreateSettingsContainer`, `CreateSlider`,
`CreateCheckbox`.

**"Twelve methods" is shorthand — the frozen surface includes the methods those factories hang on
the objects they return.** Name them so nobody reads the list too narrowly:
- `CreateCard`'s returned object: `AddContent` (`UI/Core.lua:1308`), `AddCheckbox` (`:1321`),
  `AddText` (`:1372`), `GetContentHeight` (`:1398`), plus the private field `card._leftPadding`.
  Consumed by `UI/Panels/BagUI.lua:53,159,177` (and `:141,164,182,196,212` for the padding) and
  rendered inside the bag window through `ResizeForSettings`. All frozen with `CreateCard` itself.
- `CreateSettingsContainer`'s returned object: `AdvanceY`, `FinalizeHeight`, `GetYOffset`.
- `CreateRailRow`'s returned row: `SetSelected(bool)`, `Refresh(hovered)`, and its being a `Button`.
- `CreateScrollFrame`'s returned fields: `container.content`, `scrollFrame.content`,
  `container.scrollBar`.
- `AttachRing`'s returned ring: `Show`/`Hide`/`SetColor`.
- Note the inverse case: `UI:CreateCheckbox` is on the twelve yet has **zero direct** BagUI
  consumers — the bag path reaches it only through `card:AddCheckbox`. It stays frozen anyway,
  because that indirect path is the one that renders.

`CreateScrollFrame`'s **internal geometry is frozen too**: `UI/BagUI/Core.lua:126-134`
numerically mirrors the factory's private fill-mode margins into its own `SIZING` table
(`SCROLL_CONTAINER_MARGIN=10` mirrors `UI/Core.lua:1016-1017`, `SCROLL_CONTENT_INSET=22` mirrors
`:1037/:1047`, `SCROLLBAR_WIDTH=10`/`SCROLLBAR_MARGIN=8` mirror `:1062-1063`), and
`CalculateRequiredWidth:186-187` derives the entire bag window width from those copies.
`ResizeForSettings:885` holds a second un-named copy as a raw `- 20 - 22`. Changing the factory's
`10`/`-18`/`-4`/`-22` silently costs or gains a bag column.

`UI.layout` (`UI/Core.lua:82-140`, 45 keys): **add new keys freely, never retune an existing
value.** Four are load-bearing in geometry BagUI recomputes independently: `bottomBarHeight`,
`rowHeightSmall`+`elementSpacing`, `rowHeight`, `iconSize`.

Provably safe to change (zero BagUI consumption): `CreateDropdown`, `ShowDropdownMenu`,
`CreateItemListRow`, `CreateItemListBuilder`, `CreateTabBar`, `CreateFeatureCard`,
`CreateSettingsCard`, `CreateDynamicSettingsCard`, `CreateCheckboxWithHint`, `CreateSectionHeader`,
`CreateDivider`, `CreateNumberInput`, `CreateCurrencyInput`, `UnpackColor`, `ColorText`,
`UI.hexColors`. The `Button:SetText` and `Disable`/`Enable` fixes are provably invisible to BagUI
(BagUI calls `UI:CreateButton` at exactly two sites and never calls either).

**The fence follows the output, not the file.** Requirement 9 is about the bag the owner tuned, so
any symbol whose observable output is rendered inside the bag window is fenced wherever it lives —
`Core.lua` and `Modules/*` buy no exemption. Four such indirections are touched by this plan and
are enumerated with their consumer sites in Phase 13's **indirection audit**: `IM:FormatMoney`
(bag footer, `UI/BagUI/Core.lua:717`), **`IM:FormatNumber` (`Core.lua:267`, `FormatMoney`'s own
dependency at `:286` — so it renders transitively in that same footer)**, the `UI.colors` table
(20+ BagUI read sites), and `IM.ITEM_CLASS_NAMES` (bag category labels *and* ordering). All four
are frozen; changes to them are gates, not edits.

**The rest of the bag's indirect surface, for the next phase author.** These also render inside
the bag window and **no phase in this plan touches any of them** — their absence from Phase 13's
audit is in scope, not a hole: `IM.CATEGORY_EXCLUSION_NAMES`, `IM.ITEM_CLASS` / `MISC_SUBCLASS`,
`UI.fonts` / `UI.fontSizes`, `Filters:GetEquipmentSets`, `IM:IsSecureInteractionActive`. If a
future phase touches one, it inherits the same freeze and the same gate.

### External constraints

- Lua 5.1 (WoW's embedded runtime). No harness can run *inside* the WoW client. An offline one
  outside it exists as of Phase 1: `.claude/tests/autosell/` (`run.sh`, `wow_stub.lua`,
  `test_autosell.lua`) loads the real `Core.lua`, `Database.lua`, `Filters.lua`, `AutoSell.lua`
  and `MailHelper.lua` under Lua 5.1 in a digest-pinned container. It stubs the WoW API, so it
  proves branch logic and never client behaviour; anything resting on a real API answer still
  needs an in-game check. *(Corrected 2026-09-08 — this line previously read "No in-process test
  harness and none possible," which was true of the client and false of everything else.)*
- Published commitments: `.toc` `Interface: 120100`, `Version: 1.3.3`,
  `SavedVariables: InventoryManagerDB`, `X-Curse-Project-ID: 1422035`. `publish.sh` rewrites
  `## Version:` and `IM.version` only — **it never touches `## Interface:`**, so any interface bump
  is a manual edit. `publish.sh` hard-gates on: clean working tree, no untracked files except
  `VERSION_GUIDE.md`/`*.zip`, branch `main`, monotonic version increment.
- `.toc` load-order constraints that must survive every edit: `Core.lua` first;
  `UI\Core.lua` before the 23 files binding `local UI = IM.UI` at file scope;
  `UI\BagUI\Core.lua` before `MasonryLayout.lua`. `Database.lua` readiness is enforced by
  `ADDON_LOADED` (`Core.lua:337-339`), not by `.toc` position. The `.toc` comment
  "Core.lua first - defines SIZING constants" is stale.
- 30 `hooksecurefunc` sites across 14 files reach into Blizzard APIs. Five API behaviors are
  unverified and are settled by Phase 0 before any design depends on them.

### Friendly forces (team, tooling, services)

- Single developer, direct commits to `main`, working copy symlinked into WoW — every fix is live
  immediately; "release" means the CurseForge publish only.
- **Docker Lua 5.1 is available and verified working**:
  `docker run --rm -v /tmp:/w -w /w akorn/lua:5.1-alpine lua script.lua` returns `Lua 5.1`. User is
  in the `docker` group. This is the only real verification leverage in the whole plan. Do NOT use
  npm `fengari`/`lua-in-js` — Lua 5.3 semantics differ on `#` and integer division.
- `Database.lua` is almost perfectly CLI-exercisable: zero load-time global references, so
  `loadfile("Database.lua")(addonName, IMStub)` works with an `IMStub` providing `Debug`, `Print`,
  `PrintError`, plus globals `time = os.time`, `date = os.date`. The real SavedVariables file is
  valid Lua and `loadfile`s directly. `IM:InitializeDatabase()` chains merge→migrate, so
  **idempotency is testable by calling it twice and deep-comparing.**
  **The corollary is a hard design constraint, not a convenience** (Phase 11 steps 4, 6, 10): this
  leverage exists **only** for code that calls no WoW API. Anything the migration needs from the
  game — the clock, a normalized realm name — is injected through `opts`, because a WoW call inside
  the pass is either stubbed away or an error, and either way the artefact certifies a pass that
  never ran the step.
- In-game: `/reload`, `/im debug` (`Core.lua:498-501`), 500-line debug ring buffer via
  `IM:GetDebugLogString()` (`Core.lua:183`).
- Reuse rather than rebuild: `GetPooledFrame`/`ReleaseAllFrames` (`Dashboard.lua:59-86`, two of
  three pools have no callers), `IM:GetBagIDsToScan()` (`Filters.lua:646-658`, canonical bag list
  including the reagent bag), `UI:CreateTabBar` (`:1609`, lazy-load-by-name),
  `IM:ParseMoneyFromMessage`/`ExtractItemLinkFromMessage` (`Core.lua:715,734`, already pcall-wrapped),
  `StaticPopupDialogs` (`Core.lua:191-243,601-611`),
  `ItemLock._CheckAndBuybackLockedItems` (`ItemLock.lua:134-168`, the undo pattern already exists),
  `UI:CreateDropdown`/`ShowDropdownMenu` (`UI/Core.lua:893,942`), `UI.hexColors`.

### Civil considerations (real people, real property)

The only affected person is the owner, but the property is real: irreplaceable in-game items
(legendaries, artifacts, heirlooms, unique-equipped gear), a multi-million-gold account balance,
and a gold ledger he treats as authoritative. WoW keeps **no version history of SavedVariables**;
a bad write is gone. Two consequences bind the whole plan: asset-safety phases ship before
anything else, and a confidently-wrong number is treated as worse than a missing one.

### Assumptions

| # | Assumption | Status |
|---|---|---|
| A1 | Docker Lua 5.1 reproduces WoW's Lua 5.1 semantics closely enough to prove migration idempotency | `verified` — image runs, `Database.lua` has no load-time globals |
| A2 | `.toc` order is a sane authoritative `OnEnable` order and no module depends on the accidental `pairs()` order | `verified` — recon refuted every candidate dependency (`RecentItems.lua:93`, `JunkList.lua:23-24`) |
| A3 | Only the `_claimedThisCycle` item is gated on the module-order fix | `verified` — five other asserted prerequisites explicitly refuted by recon |
| A4 | BagUI consumes the twelve fenced factory methods **plus the methods those factories hang on their returned objects** (enumerated under the fence above — `card:AddContent/AddCheckbox/AddText/GetContentHeight`, `container:AdvanceY/FinalizeHeight/GetYOffset`, `row:SetSelected/Refresh`, `ring:Show/Hide/SetColor`, `container.content`/`scrollFrame.content`/`container.scrollBar`) and nothing else | `verified` — exhaustive grep across the subsystem; the returned-object half is consumed at `UI/Panels/BagUI.lua:53,159,177` and renders through `ResizeForSettings` |
| A5 | `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` returns `0` (not `nil`) before the account bank is opened | `verified` — **REFUTED.** Observed identically on three separate cold logins, before any bank was opened: `[Database] Warband bank gold set to 11294783865` / `[WarbandBankTracking] Initialized warband gold: 1,129,478g 38s 65c`. The API returns the REAL value cold — not `0`, not `nil`. Consequence: W3-1's login wipe is a **latent hazard, not observed damage**, on this client — the `>= 0` guard in `Database.lua` still accepts a `0` or `nil` the day the API returns one and would still stamp `warbandBankGoldUpdated` as fresh, so Phase 8's guard is still required, but the failure story softens from "damage already happening" to "unfired hazard" (Phase 8's evidence note). This also settles that warband gold is readable anywhere with no bank visit — the foundation for requirement 4's cross-character sharing |
| A6 | `C_Bank.FetchPurchasedBankTabIDs` is readable cold | `partially verified` — the call returns a live table cold (`table: 0000019953E87C70`, no bank frame open), not `nil` and not an error. **The element count (`#` of that table) is still unobserved and stays OPEN.** Phase 9 step 9's cold warband-item-refresh capability therefore stays conditional, not confirmed: a non-empty count would unlock it, but nobody has checked |
| A7 | `Enum.PlayerInteractionType.AccountBanker` fires on the live build | `verified` — **REFUTED as a usable signal.** The owner opened the personal bank frame and switched to its warband tab, repeatedly: **no event fired at all**. In TWW the warband bank is a second tab inside the personal bank frame, not a distinct interaction, so `AccountBanker` cannot be relied on to fire on a tab switch. This is the definitive confirmation of W2-18 (Phase 7): resolving bank type at **process time** via `C_Bank.IsAccountBankPanelShown()` is the only available mechanism, not merely the preferred one — there is no event to hook, so `_detectedBankType` latched at frame-open cannot be corrected by any listener, and bank-side counterpart diffing is mandatory rather than optional, because a bag-side-only diff can never learn which bank received an item. Any future design keyed on an interaction event here is dead on arrival |
| A8 | `pairs()` order over `IM.modules` is stable within a build | `verified` — three `/reload`s produced a byte-identical `OnEnable` order: CurrencySearch, AutoSell, MailHelper, WarbandBankTracking, InventorySnapshot, NetWorth, BankItemTracking, BarberTracking, BMAHTracking, GuildBankTracking, UnclaimedGoldTracking, TooltipInfo, QuestTracking, TransmogTracking, SellHistory, Ledger, VendorTracking, MailTracking, AuctionTracking, RepairTracking, TradeTracking, FlightTracking, ItemLock, LootTracking. **Caveat**: these were `/reload`s, not full client restarts, so string interning persisted — stability across a cold restart is unobserved; this does not change the fix (Phase 3 makes order deterministic regardless), only the reproduction confidence for Phase 4. Derived consequence, recorded in Phases 3 and 4: the resulting `PLAYER_MONEY` handler chain is NetWorth → Barber → BMAH → UnclaimedGold → Transmog → Ledger → Vendor → Auction → Flight, so UnclaimedGold's `_claimedThisCycle = false` reset runs BEFORE the vendor/auction/flight/transmog claims, which is why those stick; WarbandBank's claim comes from the separate `ACCOUNT_MONEY` event, whose ordering relative to `PLAYER_MONEY` remains unobserved — the amount-keyed queue (Phase 4) makes that unknown moot |
| A9 | The scroll-child width snapshot clips the Dashboard/popup search boxes | `unverified` — Phase 0 item 5; the fix (set width at refresh time) is free either way |
| A10 | `SetOverrideBindingClick`/`ClearOverrideBindings` are combat-restricted | `unverified` in-game, documented by Blizzard — the guard is correct regardless |
| A11 | `UI/Panels/History.lua`, `Ledger.lua`, `NetWorth.lua` are unreachable | `verified` for `History.lua` — **proven dead in both directions.** `UI/Config.lua:17-25` lists General, BagUI, UI, Selling, Dashboard, MailHelper, Currency — no History. The only dynamic resolver in the tree is `UI/Panels/Selling.lua:53` (`UI.Panels[panel.module]`), whose `subTabs` (`:16-21`) resolve only AutoSell, Categories, Whitelist, JunkList. Nothing can construct `UI.Panels.History` — cleared for deletion in Phase 18. `Ledger.lua`/`NetWorth.lua` verdicts unchanged (still to be confirmed the same way before their own deletion) |
| A12 | The user accepts an unbacked-up migration | `verified` — asked twice, answered "just write it and ship it" both times |
| A14 | `GetNormalizedRealmName()`'s output for each of the owner's realms is knowable only by observation | `verified` — **normalization PRESERVES apostrophes.** Recorded pairs: `(Warsong, Warsong)` and `(Zul'jin, Zul'jin)` — normalization strips spaces and hyphens, not punctuation, so both of the owner's real realms are **identity** under the transform; `realmMap = {Warsong→Warsong, Zul'jin→Zul'jin}`. **Design consequence, re-scoping Phase 11's fixtures (see that phase's steps 9A/11 and the Docker-proof note)**: because the map is identity for both real realms, the v3 key rewrite is a provable no-op against the owner's real SavedVariables — the real-data Docker run cannot exercise the key-rewrite path at all. The synthetic fixtures are therefore promoted from pathological-case coverage to the **sole** coverage of that path, and a clean real-data run showing zero key changes is the *expected* result, not evidence the rewrite works |
| A13 | The owner's `sellHistory` contains rows older than `ledger.maxAgeDays` that have **no** counterpart left in `transactions` | `unverified`, and **deliberately left unmeasured** — the instrument that would have counted it was the consolidation merge, withdrawn by owner decision in revision seven. Its truth changes how many rows the v3 drop destroys, not what the plan does: the loss is accepted either way (Appendix B **L1**). Nothing in the plan depends on the number |

### Risk table

Probability `A Frequent · B Likely · C Occasional · D Seldom · E Unlikely`.
Severity = MAX over {money, data, prod-state, security, irreversibility}:
`I Catastrophic · II Critical · III Marginal · IV Negligible`.
Mitigation buckets: `elim` = eliminated/automated (−2, one axis), `guard` = engineered guard
(−1, one axis), `human` = vigilance (0, record-only).

| Risk | Prob | Sev | Initial | Mitigation (bucket) | Residual | Gate |
|---|---|---|---|---|---|---|
| R1 Auto-sell destroys an irreplaceable item (dead quality floor `Filters.lua:200` + junk-list override `:553` + `autoSellEnabled=true` default) | B | I | **EH** | Quality floor wired above BOTH the threshold and the junk-list branch, nil-quality guard, default false, first-sale-per-session confirm (`elim`, B→D) | **HIGH** | Floor B (irreversible) — cannot go below HIGH. **Override required** |
| R2 The v3 migration corrupts or destroys live SavedVariables (no backup by user decision; v1→v2 non-idempotent precedent; `_mergeDefaults:183-187` scalar→table coercion) | B | I | **EH** | Migration written as pure functions over explicit inputs — **including the realm transform, which is a pure `opts.normalizeRealm` lookup rather than a WoW API call, so the proof actually executes the key rewrite instead of stubbing it away** (Phase 11 steps 4, 6, 10) — + Docker Lua 5.1 double-run deep-compare against a copy of the real DB, second run must be a no-op; the transform's values proven output-equal to `GetNormalizedRealmName()` for the owner's real realms before the commit exists (step 9A); `sellHistory` removed from `defaults` in the same commit as the data drop so `_mergeDefaults` cannot resurrect it (`guard`, B→C). **Bucket note: `guard` is earned only because every line of the pass is executable in the harness.** An earlier revision put a WoW API call inside the key rewrite, which would have made the artefact prove a migration with its most destructive step disabled — an unearned bucket. Any future edit that reaches for a WoW global inside the pass forfeits the −1 and puts this row back at **EX-HIGH**. **One loss inside this risk is by design, not by defect, and is not mitigated**: the v3 drop destroys `sellHistory` rows older than `ledger.maxAgeDays` that have no counterpart left in `transactions` — accepted by owner decision, Appendix B **L1**. **Mitigation-cell honesty, added after Phase 0's realm observation (A14) — this does NOT re-score the row.** The realm-rewrite member is a **provable no-op** against the owner's real data: both his realms (`Warsong`, `Zul'jin`) map to themselves, so the real-data Docker run shows zero key rewrites and that is the *expected*, not reassuring, result — only the synthetic fixtures (Phase 11 step 11) exercise that member at all. The other four atomic-commit members — the `sellHistory` drop, the `ledgerCharFilter`→`ledgerCharKey` rename, the `pendingQueue` delete, and the `.char`/`.src` normalization pass itself — are **not** inert; they touch the owner's real, live data on every run and carry the row's full risk. Nobody should read "the migration did nothing visible" on the real-data run as "the migration is safe" | **HIGH** | Floor B (irreversible + data). **Override required** |
| R3 Account-shared warband gold/items destroyed by a cold read or an empty scan | A | III | **HIGH** | Single writer that rejects a write lowering a nonzero stored value, treats `nil`/`0` as UNKNOWN, never stamps a timestamp on a rejected write; never replace a non-empty snapshot with an empty one (`elim`, A→C) | **MEDIUM** | Passes, recorded in Future Requirements with trigger |
| R4 Gold movements booked twice, with the wrong sign, or never (the ledger is money accounting) | A | II | **EH** | Amount-keyed FIFO claim queue hooked inside `IM:AddTransaction`, order-independent, arm-and-confirm against the matching `PLAYER_MONEY` delta (`guard`, A→B) | **HIGH** | Floor B (money movement) — cannot go below HIGH. **Override required** |
| R5 The module-order change regresses one of 119 registrations across 26 multi-handler events | C | III | MEDIUM | `.toc` order made authoritative via an ordered array AND the dispatcher's mutation-during-`ipairs` hole closed in the same change, eliminating the truncation class (`elim`, C→E) | LOW | Passes |
| R6 A fence breach silently changes the bag window's column count or geometry | C | III | MEDIUM | Fence restated inline in every affected phase; add-only discipline; frozen list enumerated (`human`, 0) | MEDIUM | Passes, recorded with trigger |
| R7 Deleting code that is only reachable by dynamic string lookup (`UI.Panels[panel.module]`) — fails at runtime, not load | C | III | MEDIUM | Prove-death-in-both-directions grep plus an in-game visit to every settings tab and dashboard tab before any deletion (`human`, 0) | MEDIUM | Passes, recorded with trigger |
| R8 The mail cursor / async `SendMail` path loses or misplaces an item | C | II | HIGH | Verify attachment after the click, `ClearCursor()` on every path including before `SendMail`, unmailable collection list, serial state machine advancing on `MAIL_SEND_SUCCESS` with retry-then-abort on `MAIL_FAILED` (`elim`, C→E) | LOW | Passes |
| R9 A Blizzard API assumption is wrong (30 `hooksecurefunc` edges, interface bump to 120100, 5 unverified behaviors) | C | III | MEDIUM | Phase 0 settles all five in-game before any dependent design; tainted-string parsing stays inside `pcall` (`guard`, C→D) | LOW | Passes |
| R10 Client stutter and unbounded frame/memory growth (hidden-window rebuilds, 2 of 3 leaking refresh paths, per-refresh debug formatting) | A | IV | MEDIUM | Frame pooling on all three Dashboard paths + shared row pool for both popups + one debounced `BagUI:QueueRefresh` + `IM:IsDebug()` guards (`elim`, A→C) | LOW | Passes. **Caveat**: the largest single win (B1's `OnHide`) is approval-gated; until approved this stays MEDIUM |
| R11 A finding is silently dropped, or a set the plan asserts is incomplete, **or a whole defect class goes unfound by every pass** — the audits' counts were unreliable (5 vs 18 defective charKey sites, 40 vs 30 `hooksecurefunc` sites, an earlier 96-vs-125 finding total the conductor has since corrected), three review rounds each found a different missing member of a plan-asserted set, **OQ-1 — a data-loss defect — was found by the owner asking a question after five planner rounds and four review rounds had all read past it, and OQ-2 — four startup-path re-entry defects, found by reading a login debug trace that no audit or review pass read — was itself briefly an instance of this exact risk: real remediation work folded into a phase's scope with no coverage-index row, until this revision caught it against the plan's own draft** | B | III | MEDIUM | Coverage index mapping every numbered item to exactly one phase or to two labelled work items both of which must close — **plus** the completeness-critical sets converted from plan-time assertions into execution-time grep derivations whose exit criterion is "zero unhandled hits" (Phase 11 steps 2-3). **Both are `human`, 0, record-only, and the derivation does NOT earn a guard bucket**: a grep an executor must remember to run is a written procedure, not an automated one — nothing in the tree fails if it is skipped. It moves the *probability of a wrong list* honestly, but it is not mechanically enforced, so it scores nothing (`human`, 0) | MEDIUM | Passes, recorded with trigger |
| R12 Colour-only encoding of income/expense and staleness is unreadable to a colour-blind user | A | IV | MEDIUM | Every colour-carried meaning also carries a glyph or a word (`↑ +142,000g`, `stale 12d`, `12.4%`, `6 by quality · 2 on junk list`) (`elim`, A→C) | LOW | Passes |
| Security | — | — | N/A | Sandboxed WoW client addon: no network, no credentials, no untrusted input beyond Blizzard's own API. Injection surface is tainted chat strings, already `pcall`-wrapped | N/A | — |
| Auth | — | — | N/A | Single-user client addon, no auth model | N/A | — |
| Prod-state | — | — | N/A as infrastructure | The user's live account data is the real "prod"; folded into R2/R3 | N/A | — |

#### Failure paths for the HIGH and EX-HIGH rows

**R1 — most likely failure path**: the quality floor is inserted *below* the junk-list branch
instead of above it, so an Alt+Ctrl-clicked heirloom still sells; nobody notices because the
default `maxQuality` never reaches quality 5 anyway and the smoke test only exercises defaults.
**R1 — most dangerous failure path**: the floor as written (`>= 5 or == 7`) also blocks quality 8
(WoW Token, `Core.lua:306`); an executor "fixes" that by loosening the comparison, reopening the
legendary hole, and `ShouldAutoSell` never nil-checks `itemQuality` (it early-returns on nil
`itemName` at `:517-522` but not on nil quality), so an uncached item with `nil` quality slips
straight through the loosened test and is sold.

**R2 — most likely failure path**: the character-key merge picks a winner by `lastSeen`, one side
has no `lastSeen`, the comparison errors or silently prefers `nil`, and one character's gold and
snapshot history vanish. Docker double-run catches the non-idempotency but not the wrong winner —
the second run is a faithful no-op over already-corrupted data.
**R2 — the merge's worst variant, named because it was live in this plan until revision eight**: the
key rewrite calls `GetNormalizedRealmName()`, which takes no argument and returns the **running**
character's realm, so every stored alt's realm half becomes the current realm, the merge rule then
fuses characters that were never the same character, and on a multi-realm account the loss is total
and silent. Phase 11 step 6 removes the mechanism (pure injected lookup, no API, merges only between
map-verified keys) and step 9A ties the lookup's values back to the API; step 11 asserts all three.
**Do not reintroduce an API call, or a derived space-stripping rule, into the pass.**
**R2 — most dangerous failure path**: `sellHistory` is deleted from the data but not from
`defaults`, so `_mergeDefaults:181-192` re-adds the key on the next login; the version stamp says
v3, the resurrection is invisible, and the next release's migration appends the resurrected
entries into `transactions` exactly as v1→v2 did — silently doubling the ledger with no backup to
compare against.
**R2 — what is NOT a failure path, stated so nobody re-scores it as one.** The v3 drop destroys
`sellHistory` rows that have no counterpart left in `transactions`. That is a **deliberate accepted
loss** (Appendix B **L1**), not a defect and not a probability the mitigations move: the owner's
retention setting already declares data past his window unwanted. Revision six proposed a
consolidation merge and it was withdrawn on the merits in revision seven; the band stays `C` and
the residual stays HIGH either way. Do not re-add the merge as a mitigation.

**R4 — most likely failure path**: the amount-keyed queue matches on exact copper, two unrelated
simultaneous movements share an amount (a 30c postage and a 30c vendor sale), and the wrong
claimant consumes the entry — one movement booked twice, one not at all.
**R4 — most dangerous failure path**: the claim queue is hooked inside `IM:AddTransaction` and a
bug there fails closed, so *every* tracker's entry is swallowed; the Dashboard shows a clean,
plausible, empty week and the user trusts it. Silent under-reporting is unfalsifiable without the
per-source debug trace, which is why Phase 4's smoke checklist counts entries per action rather
than eyeballing a total.

**One hazard class was deleted rather than scored — read this before going looking for it.**
Earlier revisions of this plan carried a scored risk (`R13`) covering a live window between a
normalized character-key *producer* and the migration that rewrites the *stored* keys, mitigated by
an `IM:GetStorageKey` read-compat resolver and an identity-vs-storage split. **The window no longer
exists.** The producer change and the migration are one atomic phase landing in one commit
(Phase 11), so there is no reachable state in which a normalized producer meets un-normalized
storage. A hazard whose mechanism has been removed earns no row, no residual and no trigger — it is
deleted, not mitigated to LOW. `IM:GetStorageKey` is not part of this plan and must not be written;
`IM:GetCharacterKey` is the single key producer, for identity and for storage alike. An executor
who finds a reference to a storage resolver anywhere is reading a stale copy of this document.

---

## 2. Mission

The executor, working through this plan's phases in order on `main` with the working copy
symlinked into WoW, remediates every audit finding — asset-safety first, then ledger correctness,
then account-shared data and the migration, then dashboard and UI debt, then documentation — each
phase verified by an in-game smoke checklist and the migration additionally by a Docker Lua 5.1
double-run idempotency proof, in order to reach a 1.4.0 release in which no auto-sell can destroy
an irreplaceable item, no gold movement is booked twice or lost, account-shared data survives a
cold login, and every number the addon displays is computed over the same set as the rows beneath
it.

---

## Requirements (verbatim)

The user's confirmed list, copied exactly, in order.

1. **"we fix it ALL" — every audit finding gets a home, nothing parked**
   → Satisfied by the coverage index (Appendix A): all 125 numbered findings mapped to exactly one
   phase, **plus OQ-1 (the finding the owner found himself, asked while reading revision five,
   answered in revision six) and OQ-2 (the login-storm findings, discovered by reading the owner's
   debug log during Phase 0 and now correctly indexed rather than folded into a phase's scope) —
   127 rows in total.** OQ-1 stays on the index and is closed by the owner's recorded decision to
   accept its consequence (Appendix B **L1**); OQ-2 stays on the index and is closed by Phase 3's
   fix, cross-checked against Phase 9's exit criteria — "nothing parked" means every row reaches a
   recorded resolution, a fix is one and an accept is one, silence and a scope-fold with no row are
   not. Exit criterion: Phase 19's release checklist refuses to publish while any coverage-index row
   is unclosed.
2. **"batch the duct tape" — no-duct-tape rule applies; fix at discovery, don't defer**
   → Satisfied by the root-cause clustering in §3.2: six named ancestors replace 30-odd symptom
   patches. Two deferrals (D1, D2) and one deliberate accepted loss (L1) exist, and each names all
   four fields (Appendix B). Exit criterion: no phase closes with a symptom fixed downstream of an
   unfixed producer.
3. **Bugs, stale data fixes, ledger fixes**
   → Phases 1-2 (bugs with asset consequences), 3-7 (ledger correctness), 8-12 (stale and
   account-shared data, one accounting system, character identity + the migration as one atomic
   phase, ledger storage).
4. **"If shit is shared then it should be able to pass from one char to the other because the
   warbound bank is the same amount for all chars"**
   → Phase 8 (warband gold: one global writer, one reader) and Phase 9 (warband item value stored
   once globally next to the already-global `warbandBankInventory`, counted once in
   `GetAccountBreakdown`). Exit criterion: five alts opening a bank yield 1× the warband contents,
   not 5×.
5. **"for some things like banks and shit it requires visiting the bank but ffs lets get creative"**
   → Phase 9 (currency capture needs no bank or vendor visit — `C_CurrencyInfo` is always
   readable), Phase 15 (staleness rendering: an alt's six-month-old data stops carrying the same
   visual authority as live data), and Phase 0 item 2 (if `FetchPurchasedBankTabIDs` reads cold,
   warband items become refreshable anywhere and Phase 9 grows that capability).
6. **UX improvements on the net worth / ledger / inventory stuff**
   → Phase 14 (dashboard correctness) and Phase 15 (the fourteen W5 render items).
7. **UI/UX improvements on the mail and auto sell stuff**
   → Phase 16 (all twenty W6 items), with the shared factory surface they need added in Phase 13.
8. **Reviews, not prescriptions — the user deliberately did not say what he thought was wrong**
   → Honoured: every finding in this plan traces to a file:line in the audits, not to a user
   assertion. Where a finding is a *judgment* the plan states the decision it makes and why (e.g.
   W1-2's dropdown clamp, W2-20's localization call, W5-9's wire-or-delete).
9. **On the Bag UI: "the bag UI itself is set in stone at least mostly. If you try to change
   anything with the bag itself it needs run by me first because i already did alot of
   improvements to the bag itself"**
   → Phase 17 ships invisible-only fixes; Phase 17A is **nine** explicit STOP-AND-ASK gates —
   six bag-UI visible changes (B1, B2, B6, B10, B11, B14-visible), two questions that are new
   plans if wanted (G7 edge resizing, G8 `CustomCategories`), and **G9**, which is Phase 1 step 4:
   a direct edit to the bag's own sell-ring rendering predicate at `UI/OverlayFactory.lua:462`.
   The `UI/Core.lua` fence in §1 is restated inline in every phase that touches that file.
   **This requirement is read on what the bag window renders, not on which file the code lives
   in**: a symbol in `Core.lua` or `Modules/*` whose output reaches the bag window is fenced
   exactly as hard as `UI/Core.lua` is — hence Phase 13's indirection audit, which freezes
   `IM:FormatMoney` (rendered at `UI/BagUI/Core.lua:717`), the `UI.colors` table and
   `IM.ITEM_CLASS_NAMES`. Exit criterion: the diff for Phase 17 changes no on-screen pixel the owner
   has not approved, and no phase in Movement IV changes the observable output of an audited
   indirect symbol.
   **The one thing this requirement does NOT gate, stated so nobody gates it by mistake**: a
   correctness fix upstream of the bag whose ring consequence is unavoidable. Phase 1's quality
   floor lives in `Filters.lua`; `OverlayFactory:Update` calls `ShouldAutoSell` per bag item, so
   fixing the filter necessarily moves which items wear a ring. Gating that would gate the
   asset-safety fix itself. G9 is different in kind: it edits the rendering predicate directly, in
   the bag's own rendering file, and nothing upstream forces it — so it is gated and the floor
   is not.
10. **Old plans in `.claude/plans/active/` are OUT OF SCOPE: "if they arnt apart of what you just
    audited i dont want it included. This was about the audit findings not finishing other plans"**
    → Honoured in §3.4 (Out of scope). `auto-loot-mail-plan` and `bagui-dynamic-sizing-plan` stay
    `pending_approval`, files untouched. Noted only: this plan's mail findings edit code that
    `auto-loot-mail-plan` created.

---

## 3. Execution

### 3.1 Intent & End State

**Purpose.** The addon currently destroys property and lies about money. Both are failures of
trust, and trust is the only thing a personal gold ledger sells. This plan removes the two
producers of destruction (an unwired quality floor, an unguarded mail cursor), removes the
producer of double-counted gold (context-guessing instead of amount-claiming), stops per-character
slots from holding account-shared data, and then — only then — makes the numbers legible.

**Key tasks.**
1. Wire the quality floor and gate the first automatic sale; guard the mail cursor and serialize
   Send All. Nothing else ships before these.
2. Make module and handler order deterministic, then replace every context-guessing gold tracker
   with one amount-keyed claim queue hooked inside `IM:AddTransaction`.
3. Store account-shared data once, globally, and make every writer refuse to lower a good value or
   overwrite a non-empty snapshot with an empty one.
4. Normalize character identity at the producer **and** migrate existing keys in **one commit** —
   one provably idempotent v3 pass, verified in Docker Lua 5.1 before it is wired. Producer and
   storage never disagree, not even for one `/reload`. Retire the legacy store's accessors in the
   commit *before* it, then drop the store and its `defaults` entry together in the atomic commit.
5. Retire the second accounting system, then render the data already being computed and thrown
   away — timestamps, category totals, item totals, exports — without moving a bag-UI pixel the
   owner has not approved.

**End state.**
- Auto-sell cannot destroy a legendary, artifact or heirloom at any `maxQuality` setting, and does
  not run without consent on a fresh install.
- Mail cannot silently lose an item, every mail failure names a cause, and every mail action the
  addon takes appears in the ledger.
- Every gold movement is booked exactly once with the correct sign and type; a guildmate's deposit
  produces nothing on the player's ledger.
- Warband bank gold and items are stored once, globally, and survive a login with no bank visit —
  no zeroing, no phantom transfer.
- One accounting system. `sellHistory` is gone from the data *and* from `defaults`. Its rows are
  discarded with it — a **deliberate accepted loss** by owner decision (Appendix B **L1**), because
  his retention setting already declares data past the window unwanted. `UI/Panels/History.lua` is
  confirmed unreachable (Phase 0, both directions) and is deleted outright in Phase 18, so there is
  no surviving view whose span could shorten.
- Every Dashboard total is computed over the same post-filter array as the rows beneath it.
- Timestamps, per-category totals, per-item totals and exports are rendered.
- The Bag UI's correctness and performance defects are fixed; every visible change was approved
  individually.
- `.claude/CLAUDE.md` and the registry stop asserting things that are false, including the
  CRITICAL-tagged rule that is a Lua no-op.
- Released once as 1.4.0, interface `120100` confirmed by a manual `.toc` edit.

**Judgment guidance for divergence.** Two rules outrank the steps. First: if a step would make a
number *look* authoritative while being computed over a different set than the rows it heads, stop
and fix the set, not the number. Second: if a step would touch anything on the fenced list in §1,
stop — the fix is additive or it is a question for the owner, never a retune. Where a phase's
premise turns out to be false in-game (Phase 0 exists to catch most of these), record the
observation and re-derive that phase's steps rather than forcing the written ones.

### 3.2 Concept

Twenty phases in four movements. **Movement I (P0-P2)** buys back the irreversible risk:
recon settles five API unknowns, then asset safety ships. **Movement II (P3-P7)** fixes money.
P3 is the only ordering prerequisite in the whole plan; P4-P7 then run against a deterministic
event order, and — per recon's five refutations — P5, P6 and P7 have no dependency on each other
and may run in parallel or in any order. P5 and P6 need nothing from P4; P7 alone waits for P4,
because it consumes P4's claim machinery (see §3.4 item 4). **Movement III (P8-P12)** fixes data:
the account-shared writers, the value split, the retirement of the second accounting system (P10),
then **P11 — the one atomic phase** where the character-key producer change and the v3 migration
land together in a single commit, and finally ledger storage (P12). **Movement IV (P13-P19)** is
presentation: the factory grows (add-only), then the Dashboard, then the popups, then the Bag UI
behind approval gates, then documentation, then the release.

**Why P11 is atomic, recorded because it reverses an earlier decision in this plan.** Three
consecutive review rounds each found a *different* live defect produced by the old P10→P12 split —
a duplicated display row, then the wrong producer named as its source, then an unscored comparison
class, then a mail-to-self mismatch. Each patch closed one exposure and opened the next, which is
the tell that the window itself was the producer: a live schema split on a working copy symlinked
into WoW. The owner chose to delete the window rather than patch it again, which kills all four
classes at once and retires the `IM:GetStorageKey` resolver, the identity-vs-storage split, and the
risk row that scored the window. The conductor's round-1 approval of keeping the window is recorded
here as the mistake it was; evidence and the rounds themselves live in
`git log --grep=audit-remediation`.

**What "atomic" does and does not cover — the commit-class rule, refined by owner decision in
revision six.** The earlier rule was *a commit must carry every reader and every writer of every
field it touches*, and under it the atomic commit grew to seven members across ~9 files. Those seven
were **not one class**. The refined rule, which is the one an executor applies:

> **A commit must carry every reader and every writer of a field whose SHAPE it changes. A field
> being DELETED only requires its accessors retired no later than the deletion.**

A reshape has a disagreement window — reader and writer must land together or the window reopens.
A deletion has none: retire the accessors first and the store simply stops being touched while its
data sits untouched, so the accessor retirement can be its own earlier commit and *should* be, because
a smaller atomic commit is a reviewable one. Applied to Phase 11: `ledgerCharKey`'s
rename-and-retype is a **reshape** and stays in the atomic commit; the `sellHistory` reader/writer
retirement is a **deletion** and moves to its own commit before the migration. Phase 11 therefore
lands **three** commits — the split helper, the accessor retirement, then the atomic commit of
**five** members. The one thing the split makes newly possible, and the reason its step says so in
capitals: an executor "finishing the job" by deleting the *data* in the retirement commit would
separate the data drop from the `defaults` removal that makes it hold — R2's most dangerous failure
path, and the one thing the atomic commit exists to keep in a single `git show`.

**Root-cause clustering — the six ancestors.** One fix each; the listed symptoms die with it.

| Ancestor fix | Phase | Symptoms that die with it |
|---|---|---|
| **Amount-keyed FIFO claim queue inside `IM:AddTransaction`** (`Database.lua:614-652`), so an entry with `val ~= 0` claims its own amount. Order-independent, covers every present and future call site, and lets `IsInTrackedContext` be deleted outright. | P4 | W2-2 (loot/quest/flight double-count), W2-3 (`_claimedThisCycle` session boolean), W2-4 (flag never reset on tracked context), W2-5 (single-slot `_pendingChange`), W2-6 (`IsAtWarbandBank` returns false unconditionally → dead context check), W2-7 (hook logs transactions that never happened), W2-17 (`_inTrade` cleared before `TRADE_CLOSED`). Reused as machinery by W2-14 in P7. |
| **`CalculateInventoryValue` returns `(bagsValue, bankValue, warbandValue)`** instead of one scalar; bags refresh freely, bank persists with its own `bankValueTimestamp`, warband value is stored ONCE GLOBALLY beside `warbandBankInventory`. | P9 | W3-2 (warband value × alt count), W3-3 (bank value evaporates when you walk away), W3-5 (reagent bag counted twice). Also kills the same two bugs independently reimplemented in the dead `IM:GetAccountNetWorth`. |
| **Delete SellHistory's writers**, keep the read/format helpers P11 will then retire. **W3-8's other half — the `IM:AddHistoryEntry` writer family and its nine surviving Tracking/`Core.lua` call sites — lands in P11's own "retire legacy accessors" commit**, immediately before the atomic commit, because a writer left behind nil-derefs on every sale and every loot once the key is gone. That retirement touches **accessors only**: the data and its `defaults` entry are dropped together in the atomic commit, because the two halves coming apart is R2's most dangerous failure path. | P10 (+ P11) | W3-8 (two accounting systems written in parallel: loot twice, `BuyMerchantItem` hooked twice, auction sales twice, buyback three times, plus the 100-entry cap truncating stats), W3-9 (four dead functions reading a `sellPrice` field nothing writes, plus a UTC-midnight bug already fixed elsewhere). |
| **Normalize at `IM:GetCharacterKey`** (`Database.lua:542-552`) with `GetNormalizedRealmName()` — **the producer only, where the subject IS the current character** — add `IM:SplitCharacterKey`, **and migrate every stored key in the same commit** using the pure `IM:NormalizeRealmString(realm, realmMap)` transform injected through the migration's `opts`, **never the API** (P11 step 6: the API takes no argument and returns the *running* character's realm, so applied to stored keys it merges alts into one another). One producer, one key format, no window: the `DB_VERSION` bump, the `_runMigrations` wiring, the producer conversion and the key rewrite are one commit, proven in Docker before it is written. No resolver, no fallback, no identity-vs-storage split. | P11 (atomic) | W3-11 (realm drift producer), W3-13 (18 greedy `:match("^(.+)-")` sites among 25 enumerated realm-parse entries; closed by grep, not by count), W3-10 (the migration itself, whose pass is **derived by grep over write sites**, not listed), W3-12 (per-row delete), W3-14 (the permanent zero-guard). Carries W3-8's remainder — the legacy history writer family and its nine surviving Tracking/`Core.lua` call sites — in the **preceding** retirement commit, per the reshape-vs-deletion rule above. A realm rename or connected-realm partner stops permanently double-counting gold, and the four argument-less `IM:GetCharacterData` callers plus MailHelper's four key comparisons stop being hazards because producer and storage change together. |
| **Filter once, client-side, over the full field set**; strip `filters.search` before both data calls and compute income/expense from that same post-filter array. Fix the producer to search `entry.link or entry.src or ""`. | P14 | W4-1 (summary describes a different set than the rows — every gold-only entry passes search unconditionally), W4-2 (searching a character name deletes every item transaction, same for `typeLabel`). Feeds P15's category block, which reuses the same array. |
| **One shared bag iterator** — `IM:ForEachTrackedBagSlot(fn)` / `IM:GetTrackedBagIDs()` with the `or 0` guard, routing all six call sites through it. | P17 | B3 (3 of 6 sites forgot the nil guard, two of them outside any `pcall`, so a bag swap renders nothing after the pools were released) and BagData's hardcoded `5` vs `Enum.BagIndex.ReagentBag` divergence. Pairs with W2-19's `SnapshotBags` fix in P6, which has the same producer: no canonical bag list.

**Transition criteria between movements.**
- I → II: all five Phase 0 questions answered and recorded in the plan's assumption table; the
  Phase 1 and Phase 2 smoke checklists pass.
- II → III: no ledger phase leaves a known double-book; the P4 smoke run counts exactly one entry
  per action for loot, vendor, repair, mail and warband deposit.
- III → IV: P11's Docker double-run proof is green (second run a byte-identical no-op) with every
  step-11 assertion passing; the retirement commit and the atomic commit are both in history with `git show` proving
  their separate contents; the migration commit has actually run in-game and a second `/reload`
  changes nothing further; and a cold login with no bank visit leaves warband gold unchanged with no
  phantom transfer.
- IV → release: every coverage-index row closed, every approval gate (G1-G9) either
  approved-and-shipped or explicitly declined-and-recorded, `.toc` interface edited manually,
  `publish.sh`'s four hard gates green.

### 3.3 Phases

Reviewer fan-out lines are **advisory predictions only**. The conductor re-derives the real seats
from each round's actual diff; a docs-only or rename-only round earns zero seats regardless of
what is predicted here.

---

#### Phase 0 — In-game recon and death proofs

**Task and purpose.** Answer five API questions in-game, record the owner's realm-normalization
pairs, and prove the reachability of four suspect files, in order that no later phase designs
against an unverified premise, rewrites a stored key by a guessed rule, or deletes code that is only
reachable by dynamic string lookup.

The user runs the in-game steps; the executor records the answers into the assumption table in §1
and adjusts the named phases before they start.

**Execution status — the owner ran most of this phase; results are in §1 (A5, A6, A7, A8, A11,
A14) and in the evidence notes of Phases 3, 4, 7, 8, 9, 11 and 18.** Five of seven items are
settled: W0-1 (A5, REFUTED — the API returns the real value cold), W0-3 (A7, REFUTED as a usable
signal — no event fires), W0-4 (A8, verified stable), the death proofs (A11, `History.lua`
confirmed unreachable in both directions), and the realm pairs (A14, both realms are identity
under normalization). **Two items stay OPEN and gate exactly what they always gated**: W0-2 (A6,
partially verified — the table reads cold but its element count is still unmeasured, so Phase 9
step 9's cold-refresh capability stays conditional) and W0-5 (A9, still unverified — the bag UI's
`CreateScrollFrame` chain resolves fine, but the Dashboard's two search boxes and both popups are a
different code path and remain unchecked). No design in this plan depends on either open item
resolving one way or the other before it can ship.

**Steps.**
1. **W0-1.** `/reload`, `/im debug`, and read the `[WarbandBankTracking] Initialized warband gold:`
   line at login *before opening any bank*. Records whether
   `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` returns `0` or `nil` cold. This is what
   makes W3-1 a live wipe rather than a no-op. (Settles A5. Phase 8's fix treats both as UNKNOWN
   either way, so this changes the severity story, not the code.)
2. **W0-2.** Call `C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)` with no bank frame open.
   **If it reads cold, warband bank items become refreshable anywhere and Phase 9 grows that
   capability** — it is the honest creative answer to requirement 5. (Settles A6.)
3. **W0-3.** Confirm `Enum.PlayerInteractionType.AccountBanker` actually fires on the live build.
   (Settles A7; Phase 8 and Phase 9 both want it as the "bank is reachable" precondition.)
4. **W0-4.** Add a temporary `IM:Print` of the `OnEnable` order and compare across three
   `/reload`s to establish whether `pairs()` over `IM.modules` is stable within a build. **If
   stable, the `_claimedThisCycle` double-log is deterministic rather than intermittent, which
   changes how Phase 4 reproduces it.** Remove the temporary print before Phase 3 commits.
   (Settles A8.)
5. **W0-5.** Type a long string into both Dashboard search boxes and both popups' equivalents
   (`UI/MailPopup.lua:58-61`, `UI/AutoSellPopup.lua:95-98` share the shape) and observe whether
   the scroll-child width snapshot at `UI/Core.lua:1037` clips content. Also check the third filter
   dropdown at the 350px minimum frame width (`Dashboard.lua:101`). (Settles A9 and W6-19; the fix
   is free either way.)
6. **Death proofs (gates every deletion in Phase 18).** Read `UI/Panels/Dashboard.lua` past line 40
   and all of `UI/Panels/Currency.lua`; enumerate every value ever assigned to `panel.module` and
   resolved through `UI.Panels[panel.module]` (`UI/Panels/Selling.lua:53`); then visit every
   settings tab and every dashboard tab in-game. Produce an explicit reachable/unreachable verdict
   for `UI/Panels/History.lua`, `UI/Panels/Ledger.lua`, `UI/Panels/NetWorth.lua`,
   `IM:GetAccountGold`, `IM:GetAccountNetWorth`, `IM.OnDatabaseReady`, `defaults.char`, and the two
   overlapping welcome messages. **Absence from the view you are looking at is a theory, not
   proof.** (Settles A11.)
7. **Realm-normalization pairs — the input Phase 11's migration cannot be written without, and
   there is no offline substitute.** First, offline: parse a **copy** of
   `InventoryManagerDB.lua` and list the **distinct realm strings** it holds — the realm half of
   every key in `characters`, `inventorySnapshots`, `mailHelper.alts` and `mailHelper.rules[i].alt`,
   plus every `transactions.entries[i].char` and `.src` that parses as a character key. Then, for
   **each** distinct realm, log in one character on that realm and print both values side by side:
   `/run print(GetRealmName(), GetNormalizedRealmName())`.
   Record every `(raw, normalized)` pair in §1's assumption table (**A14**). Phase 11 writes exactly
   these pairs into `Database.lua` as the migration's `realmMap` and its harness asserts the map
   against them (Phase 11 step 9A).
   **Why per realm and why in-game**: normalized realm names strip punctuation and accents, not only
   spaces, so no offline string rule is provably equivalent — a naive space-strip is **not**. The
   migration therefore looks values up rather than deriving them, and this step is where the values
   come from. Any realm you cannot log into (a transferred or deleted character) goes on a written
   **"unvisitable"** list; Phase 11 step 6 leaves those keys byte-identical rather than guessing.
   (Settles A14.)

**Exit criteria.**
- Five recorded answers in §1's assumption table, each flipped from `unverified` to `verified` with
  the observed value written next to it — consumed by Phases 4, 8 and 9 before they start.
- **One `(raw, normalized)` realm pair recorded per distinct stored realm, or that realm on the
  written unvisitable list. No third state** — Phase 11's atomic commit is blocked by an
  unclassified realm, so an incomplete list here surfaces there rather than being papered over.
- A written reachable/unreachable verdict per candidate file and function, with the grep that
  proved it, consumed by Phase 18's deletion steps. No deletion may cite this phase without a
  verdict line.
- No code change ships in this phase except the temporary print, which is removed.

**Reviewer fan-out prediction.** Zero seats — no gradeable decision, no production diff.

---

#### Phase 1 — Auto-sell asset safety

**Task and purpose.** Wire the quality floor that does not exist and stop the addon selling
without consent, in order that a legendary, artifact or heirloom cannot be destroyed at any
`maxQuality` setting and a fresh install sells nothing until the user says so.

This phase carries risk R1 (residual HIGH, override required). Nothing else ships before it.

**Steps.**
1. **W1-1.** `Filters:IsProtectedByQuality` (`Filters.lua:200-202`) has **zero callers** — the only
   quality gate in `ShouldAutoSell` is `itemQuality > db.autoSell.maxQuality` (`:619`), so the
   documented "Legendary/Heirloom never sell" step does not exist in code. Insert the floor **above
   both the threshold check and the junk-list branch** (`:553-561`) and **below** the whitelist
   check at `:549`, so nothing but an explicit whitelist can override it.
2. **W1-1 (continued).** Add the missing nil guard: `ShouldAutoSell` early-returns on a nil
   `itemName` (`:517-522`) but never nil-checks `itemQuality`. A nil quality must fail closed
   (protected), not fall through. Also handle quality 8 (WoW Token, `Core.lua:306`) deliberately —
   the floor as written (`>= 5 or == 7`) blocks it; decide protect-or-allow explicitly rather than
   loosening the comparison, because loosening it is precisely R1's most dangerous failure path.
3. **W1-2.** `UI/Panels/AutoSell.lua:16-25,82` offers `maxQuality` indices 5/6/7
   (Legendary/Artifact/Heirloom) and writes the raw index. **Decision: clamp the dropdown to 4 and
   let the floor be belt-and-braces.** Reason: offering a setting the filter will refuse to honour
   is a lie in the UI, and a clamp is the cheaper thing to keep true. The floor stays as the
   authority; the clamp stops the UI promising otherwise.

**CHECKPOINT** — a legendary with a vendor price survives a merchant visit at `maxQuality` 1, 2, 3
and 4, and survives being on the junk list; an uncached item (nil quality) is not sold.

4. **W1-1, second half — MOVED OUT OF THIS PHASE. It is approval gate G9 in Phase 17A.**
   `OverlayFactory:Update` keeps its **own** junk check (`isJunk = IM:IsJunk(itemID)`,
   `UI/OverlayFactory.lua:420`) and the will-be-sold ring fires on `(isSellable or isJunk)`
   (`:462`), independently of the filter. Deleting that `isJunk` term is a **direct edit to the
   bag's rendering predicate, inside the bag's own rendering file, whose entire effect is which
   ring paints** — and nothing upstream forces it. Requirement 9's instruction was broad and
   prospective, so the owner decides it. **Do not implement it in this phase; do not invent a
   reason it is exempt.**
   **The rest of Phase 1 ships without waiting for G9** — G9 blocks only this step. Steps 1-3, 5
   and 6 are the asset-safety fix and they are not gated.
   **Consequence of leaving it un-gated-and-unfixed for now, stated so nobody is surprised**: until
   G9 is decided, a whitelisted item that is *also* on the junk list can still wear a will-be-sold
   ring when `showLockOverlay` is off, because the `isJunk` term reaches `:462` while
   `ShouldAutoSell` refuses the item. That is a wrong ring on a protected item; it does not sell
   the item (the filter is the authority and the filter says no), so it is a display defect, not an
   asset-safety one. Phase 1's merchant tests below are what prove the asset is safe either way.

**Why the quality floor's ring consequence is NOT gated, while step 4 is.** These look alike and
are not. The floor lives in `Filters.lua`; `OverlayFactory:Update` calls `ShouldAutoSell` per bag
item (`:437`), so **you cannot fix the filter without moving the ring** — the ring change is an
unavoidable downstream consequence of a correctness fix, and gating it would gate the asset-safety
fix itself. Step 4 has no such compulsion: it is a hand edit to the predicate. Consequence gets no
gate; deliberate rendering edit gets one.

5. **W1-3.** `autoSellEnabled = true` by default (`Database.lua:21`) plus `AutoSell.lua:64-75`
   selling 0.2s after `MERCHANT_SHOW` means a fresh install sells without consent; the popup at
   +0.1s is a receipt, not a preview. Set the default to **false**.
6. **W1-3 (continued).** Gate the first automatic sale *per session* behind a real confirm using
   the existing `StaticPopupDialogs` infrastructure (`Core.lua:191-243,601-611`). Keep every reader
   consistent — `Database.lua:21`, `AutoSell.lua:64`, `Core.lua:465`, `Panels/AutoSell.lua:43,47`.

**Exit criteria (in-game smoke checklist).**
- A legendary with a vendor price in the bags survives a merchant visit at **every** `maxQuality`
  setting the UI can produce, including with the item also on the junk list.
- An item whose info is uncached (log in and open a merchant immediately) is not sold.
- A fresh profile (`/im reset`, then `/reload`) sells **nothing** on the first merchant visit
  without an explicit confirm click; declining the confirm sells nothing.
- After accepting the confirm once, a second merchant visit in the same session does not re-ask,
  and a `/reload` re-arms the confirm.
  **FRAGO, applied by the conductor 2026-09-08, no human gate (risk direction down).** Add
  "**with auto-sell settings unchanged**". Execution bound session consent to a fingerprint over
  the settings that decide auto-sell scope, so changing any of them re-arms the confirm rather
  than selling under a grant the user gave for a narrower set. `plan-adherence` graded the
  divergence as lowering risk relative to R1 and did not tag it `frago-needed`; logged here
  rather than left in a code comment, because this line is what the owner's smoke run reads.
- The AutoSell settings panel offers no quality above index 4, and the previously-stored value 5/6/7
  in an existing profile does not resurrect a sale.
- **OBSERVATION REQUESTED, not a pass/fail gate — buyback lifetime.** *(Written by an executor,
  which is outside its charter; re-adopted by the conductor 2026-09-08 on plan-adherence's finding
  that the content is correct and only the signature was wrong. A conductor FRAGO is not precedent
  for an executor editing plan prose.)* Two rounds asserted a
  specific expiry for the vendor Buyback tab ("until you close the merchant window", and before
  that "selling cannot be undone"), both written offline and both wrong. The shipped copy now says
  only what is certain: recently sold items are in the vendor's Buyback tab, it holds the last N —
  where N is read from the client's own `BUYBACK_ITEMS_PER_PAGE` and omitted entirely if that
  constant is missing — and the window does not last indefinitely. To let a future round say more, sell a junk item at a
  vendor and record which of these actually clears it — closing the merchant window · reopening
  the same vendor · opening a different vendor · a thirteenth sale · `/reload` · zoning · logout.
  Write the answer here; the copy in `Modules/AutoSell.lua` stays vague until it exists.
- **MANDATORY, because this phase touches `ItemLock`/`Filters`: `Alt+Click` and `Ctrl+Alt+Click`
  still lock and junk an item inside the CUSTOM bag.** BagUI does not handle lock/junk clicks at
  all (`ItemButton.lua:218-221`); it works only because those buttons inherit
  `ContainerFrameItemButtonTemplate` and `ItemLock.lua:414`/`JunkList.lua:48` hook
  `ContainerFrameItemButtonMixin.OnClick`. If a fix here ever moves those hooks to Blizzard's
  **named** bag buttons, Alt+Click dies in the custom bag **with no error**. No step in this phase
  changes those hooks — check it anyway, because the failure is silent.
- **Named visible consequence in the bag window** (indirection, not a fence breach):
  `OverlayFactory:Update` calls `Filters:ShouldAutoSell` per bag item, so the new quality floor
  changes **which items wear a will-be-sold ring** inside the custom bag. Expected and correct —
  the ring now tells the truth. Open the bag with a legendary in it and confirm the ring is gone
  from it, and that no other visual property of the bag changed.
- **The junk-listed legendary, at the merchant — this is the asset test and it does not depend on
  G9.** Put a legendary **on the junk list**, visit a merchant at every `maxQuality` setting, and
  confirm it is **not sold**. Then read `/im debug`'s `ShouldAutoSell` verbose line and confirm the
  refusal reason is the quality floor, not "No vendor value" — the two are different findings and
  the wrong one passing is how R1's likely failure path hides.
- **The bag ring on that same item is EXPECTED to be wrong until G9 is decided** — it may still
  paint, because `UI/OverlayFactory.lua:462`'s `isJunk` term is untouched by this phase. Record
  what you observe and take it to G9's presentation; **do not fix it here.** `git diff` must show
  **zero** change to `UI/OverlayFactory.lua` in this phase's commits.

**Reviewer fan-out prediction.** Filter-logic correctness seat — the floor's position relative to
the junk-list branch is the whole finding — and a UX seat for the consent popup wording. No bag
seat: this phase's diff does not touch a bag file.

---

**PHASE 1 EXECUTION LOG — sealed `cbfb3c3`, 2026-09-08. Code complete; phase NOT closed until the
in-game checklist above is run and its results are written here.**

Nine execution rounds, one seal commit. Seats were derived per round from that round's diff, never
from a fixed roster; a round with only a rename or comment edits earned zero. Verdicts:

| Seat | Rounds fired | Blockers found | What it caught that nothing else did |
|---|---|---|---|
| `green-check` | every round | 2 red | Both C3 instances — staged content diverging from tested content |
| `critical-path-integrity` | 8 | 3 | The mail-rule fingerprint omission; the ungated retry path (reproduced, not argued); the bearer-token exemption |
| `test-quality` | 5 | 5 | That the suite was green while the consent gate, the pre-sale re-check and the slot-identity check were each deletable |
| `code-reviewer` | 8 | 3 | C1 instances 9 and 10; the 400k-config brute force proving `_Field` injective |
| `plan-adherence` | 9 | 2 | That Phase 17 step 9 already owned the dead code Phase 1 was deleting; the two false plan-text claims |
| `performance` | 3 | 0 | Deflated two inflated concerns, including one the conductor framed as a likely blocker |
| `ux` | 3 | 1 | The dialog stating a falsehood about the player's property — this phase's first blocker |
| `migration-safety` | 1 | 0 | Graded the live-SavedVariables deletion that a later round removed entirely |

Three seats never fired, correctly: `a11y` (glob matched `UI/` twice, no interactive surface added),
`seo`, `doc-auditor`.

**Findings that changed the design rather than patching it:** the consent fingerprint was rebuilt
three times — hand list, inverted exclusion list plus a runtime audit, then derived from what
`ShouldAutoSell` actually reads. The middle version required declaring UI tables in `defaults`,
which made a BagUI initialiser unreachable, which orphaned a key, which produced a destructive
SavedVariables write in Phase 17's territory. All of that scaffolding was deleted in round 8 rather
than maintained. `.claude/corpses.md` C1 and C2 are the durable record of why.

**Owed before this phase closes:** the CHECKPOINT at §3.3 Phase 1 step 3, the in-game smoke
checklist, and the buyback-lifetime observation. Write the results into this section.

---

#### Phase 2 — Mail asset safety

**Task and purpose.** Guard the mail cursor and serialize Send All, in order that no mail action
can place an item into the wrong bag slot, leave it stranded on the cursor, or report success for
a send that never happened.

This phase carries risk R8 (residual LOW after mitigation). Note: these findings edit code that
the out-of-scope `auto-loot-mail-plan` created; that plan stays untouched.

**Steps.**
1. **W1-4.** `MailHelper.lua:601-610` does `PickupContainerItem` then
   `if CursorHasItem() then ClickSendMailItemButton(...)` with **no verification that the click
   attached and no `ClearCursor()` on any path** — `ClearCursor` exists in the entire repo only at
   `ItemLock.lua:229`. A refused attachment (soulbound, 12-slot cap, unique-equipped) leaves the
   item on the cursor, and the next iteration's `PickupContainerItem` on a full cursor performs a
   **place/swap into that bag slot**. Fix: verify attachment after the click; on failure
   `ClearCursor()` and collect the item into an `unmailable` list; `ClearCursor()` once more before
   `SendMail` regardless of path.
2. **W1-5.** Mail rules are `classID`-only and never inspect bind state
   (`Panels/MailHelper.lua:405`), so a Trade Goods rule queues soulbound materials. The
   `soulbound` FILTER_TYPE already exists (`MailHelper.lua:113-145`) and is unreachable from the
   UI. Pre-filter in `AutoFillQueue` (`:451-468`) via
   `C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(...))`. (Exposing `soulbound` in the rule UI
   is W6-12, in Phase 16, and depends on this.)

**CHECKPOINT** — a queue containing a soulbound item and a full-mailbox recipient produces an
`unmailable` report, an empty cursor, and zero moved bag slots.

3. **W1-6.** "Send All" is a broken transaction: `UI/MailPopup.lua:229-241` loops `SendToAlt`
   synchronously, `SendToAlt` calls `ClearSendMail()` on entry (`MailHelper.lua:599`), and
   `SendMail` is async — so iteration 2 wipes the frame while iteration 1 is in flight and
   `_currentRecipient` (`:613`) ends up as the last alt. `OnMailSendSuccess` (`:245-251`) then
   empties **that** alt's queue regardless of who actually received mail. Fix: a serial state
   machine in `MailHelper` advancing on `MAIL_SEND_SUCCESS`, retry-then-abort on `MAIL_FAILED`
   (both already registered at `:180-186`).
4. **W1-6 (continued).** Success clears **only the items actually attached to the mail that
   succeeded**, never the whole queue. Model the progress contract on
   `MailPopup:OnLootingStarted/Progress/Stopped` (`:312-342`) — that shape is already correct and
   is what W6-6 and W6-9 also build on.

**Exit criteria (in-game smoke checklist).**
- Mail to a **full mailbox** and mail to a **typo'd recipient** each report a cause and leave the
  cursor empty and the bags unchanged (no swapped slots).
- A soulbound item matching an active Trade Goods rule is never queued.
- A multi-alt **Send All** either sends every mail or names exactly which recipient failed and
  why; every alt that received mail has only its own sent items removed from its queue, and every
  alt that did not receive mail keeps its full queue.
- A 30-item queue to one alt reports how many were actually sent; the remaining items are still
  queued after the popup refreshes.
- `CursorHasItem()` is false after every one of the above (check by clicking a bag slot: nothing
  swaps).

**Reviewer fan-out prediction.** Concurrency/state-machine seat (async send serialization,
retry-then-abort) and an asset-safety seat for the cursor paths.

---

#### Phase 3 — The lifecycle spine

**Task and purpose.** Make `.toc` order authoritative for `OnEnable` and close the dispatcher's
mutation-during-iteration hole **in one change**, in order that handler order stops being
accidental and Phase 4 can distinguish a design bug from an ordering artefact.

**This is the only prerequisite in the whole plan.** Recon confirmed exactly one dependency (the
`_claimedThisCycle` fix needs this first) and **refuted five others** — the repair race, the AH fee
arithmetic, MailHelper's tracking bypass, guild bank attribution, and single-slot pendings are all
independently fixable. Do not serialize the rest of the ledger work behind this.

**Evidence (A8, observed, Phase 0 W0-4).** Three `/reload`s produced a byte-identical `OnEnable`
order — see §1's A8 for the full sequence. **The `_claimedThisCycle` bug (Phase 4) is therefore
deterministic and reproducible on demand under this ordering, not intermittent**; this changes how
Phase 4 is reproduced, not what either phase fixes. Caveat carried forward: these were `/reload`s,
not full client restarts, so stability across a cold restart is unobserved — it does not weaken this
phase's fix, which makes order deterministic regardless of `pairs()` behavior.

**Login storm — OQ-2, a numbered finding clustered here as one ancestor (see Appendix A), not
folded-in scope with no coverage row.** All four instances share one producer — a startup path
re-entering its own work on every login with no completion latch — and this phase already owns the
lifecycle spine, so the fix lands here rather than in a new phase.
**This is a different producer class from B8 (Phase 17), not the same one — state the boundary
explicitly.** B8 debounces an *interval*-triggered rebuild that recurs during play
(`BAG_UPDATE_DELAYED`/`PLAYER_EQUIPMENT_CHANGED` firing repeatedly while the user loots and swaps
gear), which needs a time-window debounce. OQ-2 is a *one-shot* re-entry at a single event — login —
across four unrelated modules, which needs a per-login completion latch, not a debounce interval.
Same symptom shape (redundant re-entry, no dedup), different trigger and different mechanism.
**Provenance.** Found by reading the owner's in-game debug log during Phase 0 execution, by no
audit and no review pass — the same class of blind spot as OQ-1: every audit reasoned about
steady-state event handling and none of them read a login trace. See the plan's opening diagnosis
note.
Observed on every login, before any user action:
- BagUI's override bindings are **cleared and re-set five times in ~2 seconds**. This compounds B12
  (Phase 17): those calls carry no `InCombatLockdown` guard, and `BagUI/Core.lua:1381-1382`'s
  clear-then-set means a failure between the two — now observed to happen five times per login
  instead of once — leaves the user with no working bag key until the next `UPDATE_BINDINGS`.
- `[BagData] Full refresh complete` fires **twice** back to back.
- `InventorySnapshot` scans the same 6 bags **three times in ~1 second** (`PLAYER_ENTERING_WORLD` →
  a delayed startup scan → a third pass).
- `[NetWorth] Gold updated: <same value>` fires **three times** in the same second.
**Decision: close OQ-2 with a fix inside this phase (the login-settle guard below) rather than
opening a new phase for it** — same ancestor as the ordering fix, since this phase already owns the
lifecycle spine.

**Steps.**
1. **W2-1 (ordering).** `Core.lua:342` drives `OnEnable` from `pairs(IM.modules)`, discarding
   registration order. Add an ordered array — `table.insert(self.moduleOrder, name)` at
   `Core.lua:100`, `ipairs(self.moduleOrder)` at `:342` — making `.toc` order authoritative.
   Handler order equals `OnEnable` order, so this determinizes all 119 registrations across the 26
   multi-handler events.
2. **W2-1 (iterator hole).** In the same change, fix `Core.lua:366-369` / `:89`: unregistering
   `handlers[1]` from inside the `ADDON_LOADED` dispatch does a `table.remove` (`:74`) that shifts
   index 2 into 1, terminating `ipairs` and silently skipping `CurrencySearch.lua:25`'s handler.
   **The implementation is DEFERRED REMOVAL, not iterate-over-a-snapshot. This is not a free
   choice.** `IM:UnregisterEvent` marks the handler and the dispatcher applies pending removals
   after the loop finishes; the live list is what `ipairs` walks.
   **Why the snapshot variant is wrong here, and why it would defeat this phase's own proof.**
   `CurrencySearch`'s second `ADDON_LOADED` handler is registered at `Modules/CurrencySearch.lua:25`
   **inside `OnEnable`**, and `OnEnable` runs *during* the bootstrap `ADDON_LOADED` dispatch
   (`Core.lua:342-346`). A snapshot taken at dispatch entry therefore holds **only Core's own
   handler** — CurrencySearch's does not exist yet — so its handler still does not run in that
   dispatch, the handlers-that-ran counter still reads **1**, and both instruments below read
   **identically before and after the change**. The snapshot does not fix the bug; it makes the bug
   unfalsifiable. Deferred removal walks the live table, reaches index 2 once `OnEnable` has
   appended it, and runs 2 handlers.
   **This must land in the same commit as the ordering fix** — otherwise the ordering fix leaves a
   live iterator bug in the exact thirty lines it just touched.
3. **Login-settle guard (OQ-2 — see this phase's evidence note above and Appendix A).** Add one
   latch, cleared only by the next `/reload`, and route BagUI's binding setup, `BagData`'s full
   refresh, `InventorySnapshot`'s startup scan and `NetWorth`'s gold-update logging through it, so
   each does its real startup work once per login instead of once per firing handler.
   **The latch must key on successful completion, not on "has this path fired yet."** Each wrapped
   call reports back whether it actually did its work; only a call that reports completion sets that
   path's latch. A call that reports it did **not** complete — most concretely,
   `InventorySnapshot:ScanBags` returning `false` — must **not** set the latch and must remain
   callable on the next firing of the same handler. **Do not implement "set on the first
   `PLAYER_ENTERING_WORLD` pass" as an earlier sketch of this step described** — that version latches
   on firing, not completion, and would silently suppress the retry Phase 9 depends on.
   Concretely: one latch per wrapped path (not one shared boolean for all four) —
   `IM:IsLoginSettled(pathName)` / `IM:MarkLoginSettled(pathName, success)` — set only when `success`
   is truthy.
   **Forward reference — this is the collision Phase 9 exists to close, and it is real, not
   theoretical.** `InventorySnapshot.lua`'s `ScanBags` returns `true` unconditionally today (the
   W3-6 bug Phase 9 fixes), so until Phase 9 lands, this latch behaves exactly like a fire-once latch
   for that one path — that is expected and correct here, not a defect in this phase. Once Phase 9's
   step 5 makes `ScanBags` return `false` on an empty scan, this same latch, unchanged, starts
   respecting `TryScanWithRetry`'s exponential backoff automatically, because the latch was built to
   consume a completion signal from day one rather than a firing signal. **Phase 9 must re-verify
   this interaction as its own exit criterion** (see Phase 9's exit criteria) — do not assume it once
   Phase 9's return-value change lands; prove it in-game with the latch live. See §3.4: Phase 3
   precedes Phase 9.
   **This is a separate commit from steps 1-2** — it touches four different files for a different
   reason (redundant startup re-entry, not handler ordering) and mixing it into the ordering/iterator
   commit would make `git show` prove two unrelated things at once.

**Exit criteria (in-game smoke checklist). This phase has three parts; each needs its own
falsifiable proof.**

- **Half 1 — ordering.** `/reload` three times with the temporary order print from Phase 0
  re-enabled: the `OnEnable` order is **identical** all three times and matches `.toc` order.
  Remove the print before commit.
- **Half 2 — the iterator hole. Do NOT assert on CurrencySearch's initialization appearing in
  `/im debug`: that output already appears today, with the bug present.** `CurrencySearch.lua:15`
  and `:33` log from `OnEnable`, which always runs, and `TrySetup` — the only thing the truncated
  `ADDON_LOADED` handler calls — is *also* reached from the `PLAYER_ENTERING_WORLD` +
  `C_Timer.After(2)` path at `:18-23`, logging at `:52/:56/:104`. An assertion on those lines
  passes before and after the fix and proves nothing. Assert instead on what the truncation
  actually changes, with **two temporary instruments removed before commit**.
  **Both instruments' expected values below assume step 2's required deferred-removal
  implementation.** They are not implementation-neutral: under the rejected iterate-over-a-snapshot
  variant both read the same before and after, because CurrencySearch's handler is registered
  mid-dispatch and is absent from any snapshot taken at dispatch entry. If an executor reaches this
  checklist and the numbers do not move, the first thing to check is which variant was written.
  1. A temporary `IM:Print` placed **inside the body of the second `ADDON_LOADED` handler**
     (`CurrencySearch.lua:25`, above the `addon == "Blizzard_TokenUI"` test so it fires for every
     `ADDON_LOADED`), **printing `loadedAddon`**. Do **not** assert that the line never prints
     before the fix — it does. `IM:UnregisterEvent` (`Core.lua:68-84`) only unregisters the event
     from the frame when the handler count reaches **0**, and after the bootstrap dispatch the count
     is 1 (CurrencySearch's own), so `ADDON_LOADED` stays live and this handler runs on **every
     subsequent** `ADDON_LOADED` — `Blizzard_TokenUI`, every load-on-demand addon — with the bug
     present. The truncation skips exactly **one** dispatch: the addon's own. So the assertion is
     **on the value**: the occurrence printing `InventoryManager` is **absent before the fix and
     present after it**, while the `Blizzard_*` occurrences appear both ways. Run it both ways —
     stash the fix, log in, confirm no `InventoryManager` line; unstash, log in, confirm one —
     because a proof you only ran after the change is not a proof.
  2. A temporary `IM:Print` of `#eventHandlers["ADDON_LOADED"]` at **both** ends of the dispatch
     loop in `Core.lua:87-93`. Note the identifier: `eventHandlers` is a **file-local**
     (`Core.lua:39`), not `IM.eventHandlers` — printing the latter prints `nil`. Measured at the
     loop's two ends, the count goes **1 → 1** across the addon's own bootstrap dispatch: it is 1
     on entry, transiently 2 mid-handler once `OnEnable` registers CurrencySearch, and back to 1
     after `Core.lua:366-369` removes index 1 (which is correct and stays). **The list length is
     therefore not a discriminator at all** — same numbers before and after the fix. The
     falsifiable quantity is **how many handlers actually ran inside that dispatch**: instrument
     the loop with a counter and assert **2 ran** after the fix versus **1** before. Instrument 2
     is what carries the proof; instrument 1 corroborates it by naming which addon was skipped.
- A merchant visit, a loot, a mailbox open and a bank open all still work — spot check that no
  module silently stopped receiving its event (`MERCHANT_SHOW` 5 handlers, `BAG_UPDATE_DELAYED` 9,
  `PLAYER_MONEY` 11, `PLAYER_ENTERING_WORLD` 7 all fire their observable effects).
- The custom bag still opens on its keybind (BagUI registers four handlers at file scope; ordering
  must not have disturbed them).
- **Half 3 — the login-settle guard.** `/reload` and watch `/im debug`: BagUI's override-binding
  setup, `BagData`'s full refresh, `InventorySnapshot`'s startup scan and `NetWorth`'s gold-update
  log each fire their real work **exactly once** per login, not the observed five/two/three/three.
  The bag key still works immediately after login and after a second `/reload`. **This half proves
  the once-per-login collapse only** — it does not and cannot prove the retry stays reachable, since
  today's `ScanBags` always reports success; that half of the proof is Phase 9's exit criterion,
  run after Phase 9 lands.

**Reviewer fan-out prediction.** One concurrency/lifecycle seat for the ordering and iterator fix.
The blast radius is unbounded on paper but the diff is thirty lines with a single decision in it.
The login-settle guard earns its own small correctness seat — four call sites, one latch mechanism
keyed per path on completion, not on firing.

---

#### Phase 4 — The claim-queue ancestor

**Task and purpose.** Replace context-guessing with amount-claiming, in order that every gold
movement is booked exactly once regardless of which handler runs first.

**Ancestor fix**: an amount-keyed FIFO claim queue hooked **inside `IM:AddTransaction`**
(`Database.lua:614-652`) so that an entry with `val ~= 0` claims its own amount. Order-independent
by construction, covers every present and future call site, and lets `IsInTrackedContext` be
deleted entirely. **Symptoms that die with it: W2-2, W2-3, W2-4, W2-5, W2-6, W2-7, W2-17.**

**Evidence (A8, observed, Phase 0 W0-4).** `OnEnable` order is stable across three `/reload`s (§1
A8), so the `_claimedThisCycle` double-log this phase deletes is **deterministic and reproducible
on demand** under that ordering, not intermittent — reproduce it by loading gold through two
sources inside the same half-second and expect it every time, not occasionally. Derived from the
same observation: the `PLAYER_MONEY` handler chain is NetWorth → Barber → BMAH → UnclaimedGold →
Transmog → Ledger → Vendor → Auction → Flight, which is *why* UnclaimedGold's stale-flag bug (W2-3,
W2-4) reliably lets the later trackers' claims stick — it resets before them. WarbandBank's claim
runs off the separate `ACCOUNT_MONEY` event, whose ordering relative to `PLAYER_MONEY` was not
observed and does not need to be: the amount-keyed queue this phase builds is order-independent by
construction, so that remaining unknown is moot.

**Design constraint (verification leverage).** Write the queue as **pure functions over explicit
inputs** — `claim(queue, amount, now) -> (claimed, newQueue)` and
`expire(queue, now) -> newQueue`, with no reads of `IM.db`, no `time()` calls inside, and no
WoW API. This is the only reason it can be tested at all: pure tables run under
`docker run --rm -v /tmp:/w -w /w akorn/lua:5.1-alpine lua script.lua`. The event handlers stay
thin wrappers that pass `time()` in.

Gated on Phase 3 for the `_claimedThisCycle` items (W2-3) only — but since the ancestor deletes
that flag outright, run the whole phase after Phase 3.

**Steps.**
1. Build the pure claim queue: entries keyed by exact copper amount with a short expiry window,
   FIFO within an amount, an explicit "unclaimed" drain that the catcher consumes. Cover the
   collision case named in R4's likely failure path (two unrelated movements sharing an amount)
   with FIFO-plus-expiry semantics and a Docker case that asserts it.
2. Hook it inside `IM:AddTransaction` so any booked entry with `val ~= 0` claims its own amount
   before the unclaimed catcher can see it.
3. **W2-2.** Loot/quest/flight gold is double-counted: `IM:ClaimGoldChange` has exactly one caller
   (`WarbandBankTracking.lua:130`) and `IsInTrackedContext`
   (`UnclaimedGoldTracking.lua:107-166`) is a frame-context whitelist with no loot/quest/flight
   branch — `FlightTracking.lua:162-163` even comments that flight costs "are claimed immediately"
   while the file never calls `ClaimGoldChange`. Result: `CHAT_MSG_MONEY` → `loot +N`, then
   `PLAYER_MONEY` → `other_income +N`. Delete `IsInTrackedContext` and route everything through
   the queue.

**CHECKPOINT** — loot 12g and confirm exactly ONE ledger entry, typed `loot`; take a flight and
confirm exactly one negative entry; hand in a quest and confirm one `quest` entry.

4. **W2-3.** `_claimedThisCycle` is a session-wide boolean reset on every money event
   (`UnclaimedGoldTracking.lua:33,96`): an order flip double-logs, a reset-then-claim loses the
   entry. Deleted with the flag. (This is the item gated on Phase 3.)
5. **W2-4.** `_claimedThisCycle` is never reset when `IsInTrackedContext()` returns true
   (`:84-88`), so a stale `true` suppresses the next legitimate log. Deleted with the flag.
6. **W2-5.** `_pendingChange` is a single slot (`:32,91`) — two changes inside 0.5s yield one entry
   carrying the wrong amount (`:170`). Replaced by the queue, which holds many.
7. **W2-6.** `WarbandBankTracking:IsAtWarbandBank()` returns `false` unconditionally (`:159-165`),
   making the context check at `UnclaimedGoldTracking.lua:152` dead code. Deleted with
   `IsInTrackedContext`; the warband path claims by amount like everything else.

**CHECKPOINT** — a warband deposit produces exactly one transfer entry and no `other_expense`;
two money movements inside the same half-second produce two entries with the correct amounts.

8. **W2-7.** `hooksecurefunc` logs transactions that never happened: a `BuyMerchantItem` rejected
   for full bags or insufficient gold still books `purchase -totalCost`
   (`VendorTracking.lua:256-262`); same for `BuybackItem` (`:284`), `TakeInboxMoney`
   (`MailTracking.lua:285`) and `TakeInboxItem` (`:302`). Also
   `totalCost = price * ceil(qty/(stackCount or 1))` (`:254`) books `-0` for currency-cost
   purchases. Fix: **arm a pending record and confirm it against the matching `PLAYER_MONEY`
   delta** — the same queue — and for mail confirm on `MAIL_SUCCESS`. An unconfirmed pending
   expires and books nothing.
9. **W2-17.** `TradeTracking` clears `_inTrade` at `OnTradeComplete` (`:417`), before
   `TRADE_CLOSED`, so late trade money escapes the guard and is double-booked. Dies with the
   ancestor; verify rather than patch the flag.

**Exit criteria (in-game smoke checklist).**
- **Count entries per action, do not eyeball totals** (R4's dangerous path is silent
  under-reporting): loot 12g → exactly one `loot` entry. Sell to a vendor → one entry. Buy with a
  **full bag** so the purchase is rejected → **zero** entries. Buy an item priced in a currency
  rather than gold → zero gold entries, no `-0` row. Buy back an item → one entry. Take gold from
  a mail → one entry. Take an item from a mail → one entry, and cancelling the take → none.
- A warband bank deposit → exactly one transfer entry, no `other_expense`, no `other_income`.
- A player trade where gold arrives after the trade window closes → exactly one entry.
- Two rapid movements (sell two items fast) → two entries with the right amounts, not one merged.
- `/im debug` shows no unclaimed-catcher entry for any action that produced a typed entry.
- Docker: the pure claim-queue test file passes, including the shared-amount collision case.

**Reviewer fan-out prediction.** Money-correctness seat, a concurrency seat (claim/expire windows
against async `PLAYER_MONEY`), and a data-model seat for the `AddTransaction` hook point.

---

#### Phase 5 — Auction house accounting

**Task and purpose.** Fix four independent arithmetic and emission defects in
`AuctionTracking.lua`, in order that AH income and expense stop being systematically wrong.

**Recon refuted any dependency here** — these are pure arithmetic/emission defects with no
cross-handler state. Runs independently of Phases 4, 6 and 7.

**Steps.**
1. **W2-8.** The 5% cut is subtracted twice: `ah_sold` is booked at `totalCopper`, which is
   **already net** (`:220-228`), then `ah_fee` at `-ahFee` (`:236`). **Decision: book gross plus a
   separate fee row.** Reason: the fee is a real expense the user should be able to see and filter,
   and a gross-plus-fee pair reconciles against the mail he receives; net-with-no-fee-row hides it.
2. **W2-9.** `ah_refund` is never emitted anywhere: declared `Ledger.lua:41`, documented
   `AuctionTracking.lua:17`, and `OnPlayerMoney` (`:102-157`) has **no positive-delta branch at
   all**; the expired branch (`:174-180`) only logs. Expired-auction deposits are lost, and
   `IsAtAuctionHouse()` suppresses the unclaimed catcher too. Add the positive-delta branch and
   emit `ah_refund`.
3. **W2-10.** Outbid refunds are lost and a phantom purchase is kept: `OnPlaceBid` (`:348-360`)
   sets `_pendingPurchase` for any bid, booked as `ah_bought` (`:132`), while the refund is a
   positive delta with no handler — so the expense stays forever. Bid-sourced pendings also carry
   no `itemID`. Fix both: handle the refund and stamp the `itemID`.
4. **W2-11.** Single-slot AH pendings: `_pendingDeposit`/`_pendingPurchase` (`:31-32`) are
   overwritten at `:312,337`, so five quick commodity posts yield one merged entry. Use the
   Phase 4 queue's multi-slot shape rather than a second bespoke structure.

**Exit criteria (in-game smoke checklist).**
- Sell one item on the AH and reconcile against the mail actually received: gross entry plus one
  fee entry, and gross − fee equals the copper in the mail. No double-subtraction.
- Let an auction expire and confirm exactly one `ah_refund` entry for the deposit.
- Get outbid and confirm the phantom `ah_bought` expense is reversed and the resulting rows net to
  zero; the entry carries an `itemID`.
- Post five commodity stacks in quick succession and confirm **five** deposit entries, not one.
- Filter the ledger to the AH type preset and confirm every row corresponds to a real AH event.

**Reviewer fan-out prediction.** One money-arithmetic seat.

---

#### Phase 6 — Repair, mail-site logging, postage, transfers, vendor scan, locale

**Task and purpose.** Close six independent tracking gaps, in order that repairs, mail, postage
and alt-to-alt transfers appear in the ledger with the correct type and sign.

**Recon refuted the ordering dependency here**: `RepairTracking.lua:37-40` snapshots synchronously
inside its own `MERCHANT_SHOW` handler while `AutoSell.lua:71-75` defers `SellJunk` by
`C_Timer.After(0.2)`, so the snapshot **always** precedes the sale regardless of handler order.
MailHelper's bypass is a missing code path, fully deterministic. Runs independently.

**Steps.**
1. **W2-12.** Repair cost is lost and mislabelled guild-paid: `_goldBeforeRepair` snapshots at
   `MERCHANT_SHOW` (`RepairTracking.lua:238-242`), auto-sell income makes `actualCost` negative,
   the `< repairCost*0.5` heuristic (`:262`) fires "guild", and `:264-270` logs `repair_guild` with
   `value = 0`. Fix: snapshot **inside** the `hooksecurefunc("RepairAllItems")` body and use the
   hook's own `useGuildFunds` argument, already passed at `:245` and ignored. **Log guild-paid
   repairs with the real cost** so guild spend is visible rather than zeroed.
2. **W2-13.** MailHelper's automation bypasses MailTracking entirely: `_pendingSend` is captured
   only from `SendMailMailButton:HookScript("PreClick")` (`MailTracking.lua:75`), but
   `MailHelper.lua:617` calls `SendMail` directly so it never fires and `OnMailSendSuccess` bails
   at `:151`; `MailHelper.lua:796` calls `AutoLootMailItem`, which is not among MailTracking's
   hooks (`TakeInboxMoney:114`, `TakeInboxItem:129`), so auto-loot is invisible too; and
   `IsAtMailbox()` suppresses the unclaimed catcher, so the gold is not even booked as
   `other_income`. **AH proceeds arrive by mail, so for anyone using the automation, AH income is
   entirely absent.** Fix at the action site: extract `MailTracking:LogInboxMail(index)` and
   `MailTracking:CapturePendingSend(recipient, money, items)` and call them from **both** paths.
3. **W2-15.** Postage is never logged — `SendMail` costs 30c per mail and nothing records it, in an
   addon whose headline feature is a gold ledger. Log it at the send site alongside W2-13's
   capture. (The pre-commit *display* of postage is W6-10, in Phase 16.)

**CHECKPOINT** — a repair paid personally, a repair paid by the guild, one auto-looted mail and one
manual send each produce exactly one correctly-typed entry, and the send also produces a 30c
postage entry.

4. **W2-16.** Alt-to-alt mail is counted as real income **and** real expense: `TRANSFER_TYPES`
   (`Database.lua:750-753`) lists only the warband pair.
   **The brief's original instruction — "classify as a transfer when `entry.src` matches a key in
   `db.global.characters` or `mailHelper.alts`" — cannot work, and the conductor has corrected it.**
   `MailTracking.lua:122,142` set `source = sender or "Unknown"`: a raw mail sender name, **bare**
   (`"Bob"`) for same-realm mail and never `"Bob-Realm"`, so the *receiving* half of the pair can
   never match a charKey no matter how the comparison is written. The sending half
   (`:157,169`) stores `_pendingSend.recipient`, which is whatever the user typed — equally not a
   charKey.
   **Fix: stamp a real charKey at the mail log site, then compare charKeys.** Do it inside the
   `MailTracking:LogInboxMail(index)` / `CapturePendingSend(recipient, money, items)` extraction
   that **step 2 (W2-13) already requires** — same producer, one edit: resolve the bare sender or
   typed recipient to `name .. "-" .. <realm>`, **defaulting a bare name to the current realm**
   (which is correct: WoW renders cross-realm senders as `Name-Realm` and same-realm senders bare),
   and write that into `source`. Then `TRANSFER_TYPES` classification is a charKey-to-charKey
   comparison against `db.global.characters` / `mailHelper.alts`.
   **Ordering inside this phase: step 4 runs after step 2** — the extraction is where the stamp
   lands; doing W2-16 first would mean writing the classifier against a field that is still a bare
   name. **Key format: just call `IM:GetCharacterKey()` and do not branch on whether Phase 11 has
   landed.** Phase 11 is atomic — before it, `GetCharacterKey` returns the raw form and every
   stored key is raw; after it, it returns the normalized form and every stored key is normalized.
   Either way the producer and the storage agree, so this step's comparison is correct at both
   times and needs no resolver and no conditional. Rows written **before** Phase 11 carry raw keys
   in `src`; **Phase 11's migration normalizes `transactions.entries[i].src` along with `.char`**,
   which it must do regardless, for exactly those rows.
5. **W2-19.** `VendorTracking:SnapshotBags` iterates `bagID = 0, 4` (`:78`), missing the reagent
   bag that `IM:GetBagIDsToScan()` (`Filters.lua:646-658`) includes, so reagent-bag sells are
   unattributable. Route it through `GetBagIDsToScan`. **Same producer as B3** (no canonical bag
   list); Phase 17 finishes the job for the BagUI call sites.
6. **W2-20.** `IM:ParseMoneyFromMessage` (`Core.lua:715-727`) matches only English unit names and
   `LootTracking.lua:142` gates on `find(msgLower, "loot")` — on a non-enUS client the loot entry
   is **missing entirely** and only the duplicate lands. **Decision: document the enUS assumption
   with a real trigger rather than localize now** — see Appendix B deferral D1, which names all
   four fields. **The in-scope guard taken now: a one-time `IM:PrintError` at login when
   `GetLocale() ~= "enUS"`**, naming the consequence ("loot gold will be recorded as untyped income
   on this client locale") and pointing at the setting or report path. **Not `IM:Debug`** — this
   plan files `IM:Debug` printing nothing without `/im debug` as a defect in its own right (W6-8,
   Phase 16) and Appendix C states the plan's standard is `IM:PrintError`; a guard on a channel the
   user cannot see does not discharge the no-duct-tape requirement for a live exposure. Once per
   session, at login, on non-enUS clients only — an enUS user never sees it. Plus Phase 4's claim
   queue means the duplicate `other_income` no longer lands either way, so a non-enUS user gets one
   honest unclaimed entry instead of one wrong typed entry.

**Exit criteria (in-game smoke checklist).**
- Repair at a vendor while auto-sell also runs: exactly one `repair` entry with the **real** cost,
  correctly attributed personal-vs-guild per the hook's own argument.
- A guild-funded repair shows the real cost, not `0`.
- Auto-loot a mailbox with 5 mails containing gold: 5 entries, correctly typed, none as
  `other_income`.
- **W2-16, the falsifiable form**: send gold to a **same-realm** alt (the case the brief's original
  rule could never catch, because the sender arrives bare) and log in as that alt. Inspect both
  rows: each carries a `src` that is a **full charKey**, not a bare name; the pair classifies as a
  **transfer**; and the account income/expense totals do not move. Repeat with a **cross-realm**
  alt, whose sender already arrives as `Name-Realm`, and confirm the same result with no double
  realm suffix. Then send gold to a **non-character** recipient (a real other player) and confirm
  it is still booked as a genuine expense, not swallowed as a transfer.
- Sell an item **from the reagent bag** and confirm the entry is attributed.
- Sell an item and confirm exactly one 30c postage entry per mail sent (not per item).
- On an enUS client nothing changes and **no locale line appears at all**; on a non-enUS client the
  `IM:PrintError` warning appears exactly once per session, in chat, **with `/im debug` off**.

**Reviewer fan-out prediction.** Money-correctness seat; an i18n note but no seat (the decision is
a documented deferral, not code).

---

#### Phase 7 — Bank and guild bank attribution

**Task and purpose.** Stop attributing other people's gold moves and other banks' item moves to
the player, in order that the ledger contains only the player's own transactions.

Recon refuted any ordering dependency — `GuildBankTracking` uses only `GUILDBANK_UPDATE_MONEY` and
its own `_lastGuildBankGold`. This phase **consumes** Phase 4's claim machinery, so run it after
Phase 4.

**Evidence (W2-18, observed, Phase 0).** `/im debug` logged `[BankItemTracking] Bank opened
(fallback) - type=personal` followed by `Initial snapshot: 1 unique items, 1 total` while the
character bank actually held 7 items — the snapshot is of the BAGS (1 item), not the bank, and it
reached its type through the **fallback** path. Confirms the bag-only-diff half of W2-18 directly.

**Evidence (A7, observed, Phase 0 W0-3).** The owner opened the personal bank frame and switched to
its warband tab, repeatedly: no event fired. `Enum.PlayerInteractionType.AccountBanker` is not a
usable per-tab signal because the warband bank is a second tab inside the same frame, not a
distinct interaction. **This makes the process-time check below the only available mechanism, not
merely the preferred one** — there is no event to hook, so `_detectedBankType` latched at frame-open
can never be corrected by a listener, at any point in the future, on this client. Counterpart
(bank-side) diffing is mandatory for the same reason: a bag-side-only diff can never learn which
bank received an item with no event to disambiguate it. **Any future "improvement" that tries to key
this off an interaction event is dead on arrival — do not reopen it.**

**Steps.**
1. **W2-14.** Guild bank attributes other members' gold moves to the player:
   `GuildBankTracking.lua:269-323` infers direction from the guild bank's own delta and assumes "it
   was us" (the comment at `:296-305` says so outright), then `IM:Print`s it to chat — so
   guild-funded repairs land as **income**. Fix: only log when the player's own gold moved by the
   matching amount in the opposite direction within the window — **reuse Phase 4's amount-keyed
   claim machinery**, do not build a second mechanism.
2. **W2-14 (continued).** Guild bank state is per-guild shared data persisted nowhere. If it ever
   enters net worth, key it `guildBanks[guildName]` with a `lastSeen`. **Decision: do not add it to
   net worth in this release** — it is shared property the user does not own outright, and putting
   it in a personal net-worth total would be exactly the confidently-wrong number this plan
   exists to remove. Recorded in Future Requirements with a trigger.
3. **W2-18.** Bank item transfers are attributed to the wrong bank: `_detectedBankType`
   (`BankItemTracking.lua:25,514-547`) is set at frame-show and never revisited, and in TWW both
   banks live in one frame with tab switches firing no new event — so **every** transfer for the
   session is typed by whichever tab opened first. Detection is also a bag-only diff
   (`_SnapshotBags:30-46`) driven by `BAG_UPDATE_DELAYED`, so looting or crafting while the frame
   is open **fabricates deposits**, complete with a chat line (`:117`).
4. **W2-18 (continued).** Fix: resolve the bank type **at process time** via
   `C_Bank.IsAccountBankPanelShown()` (already used at `:539`), and diff the **bank side as well as
   the bag side** so a transfer requires a matching counterpart — which identifies direction *and*
   which bank, and rejects loot and consumption. `GuildBankTracking:127-160` has the **identical
   producer**: extract the duplicated snapshot/diff helper once so both files get the fix.
   Note for the executor: the project docs blame a nil `_lastBankType`; **that variable no longer
   exists — the module was rewritten** (the doc fix is W7-6, Phase 18).
5. **New, in-scope as an instance of W2-14's class (wrong-context handling in
   `GuildBankTracking`), not a new finding.** `/im debug` observed (Phase 0)
   `[GuildBankTracking] FRAME_SHOW fired, type=8` on a **personal** bank open — the module wakes for
   the wrong banker — and on close it fires **twice**, `type=8` then `type=0`. A guild-bank module
   reacting to a personal banker and to a null interaction type, in the exact module whose gold
   attribution step 1 above is already rewriting. Fix: scope `GuildBankTracking`'s frame handling to
   the actual guild-bank interaction type (`Enum.PlayerInteractionType.GuildBanker`, or whatever
   process-time check the extracted helper in step 4 exposes) and ignore `FRAME_SHOW`/`FRAME_HIDE`
   for any other type, including the null `type=0` close.

**Exit criteria (in-game smoke checklist).**
- **A guildmate's deposit while you watch the guild bank produces no entry on your ledger** and no
  chat line.
- A guild-funded repair does not appear as income.
- Deposit an item into the character bank, switch to the account bank tab **without closing the
  frame**, deposit another item: the two entries carry **different** bank types, matching reality.
- Loot an item and consume a food item while the bank frame is open: **zero** fabricated deposit
  entries, zero chat lines.
- Withdraw an item and confirm the direction is correct.
- The extracted snapshot/diff helper is called from both `BankItemTracking` and
  `GuildBankTracking` (grep confirms no second copy remains).
- **Open the personal bank (not the guild bank) and confirm `/im debug` shows no
  `[GuildBankTracking] FRAME_SHOW` line at all** — the observed `type=8`/`type=0` wake-on-wrong-banker
  is gone.

**Reviewer fan-out prediction.** Money-correctness seat and a DRY/extraction seat for the shared
snapshot helper.

---

#### Phase 8 — Warband gold: one writer, one reader

**Task and purpose.** Collapse two warband-gold writers into one that refuses to destroy a good
value, in order that logging in without visiting a bank leaves the balance intact and produces no
phantom transfer.

Carries risk R3 (initial HIGH → residual MEDIUM). Consumes Phase 0 items 1 and 3.

**Evidence (A5, observed, Phase 0 W0-1).** `C_Bank.FetchDepositedMoney(Enum.BankType.Account)`
returns the REAL value cold, on three separate logins, before any bank was opened:
`[Database] Warband bank gold set to 11294783865` / `[WarbandBankTracking] Initialized warband
gold: 1,129,478g 38s 65c`. **This means W3-1's login wipe is a latent hazard on this client, not
observed damage** — the `>= 0` guard would still accept a `0` or `nil` value the day the API
returns one, and would still stamp `warbandBankGoldUpdated` as fresh, so this phase's guard is
still required exactly as designed; only the severity story changes, from "this is actively
happening" to "this has not fired yet." The same observation is the foundation of requirement 4:
warband gold is readable **anywhere, with no bank visit at all**, which is what makes the
cross-character sharing the owner asked for possible without a bank-presence precondition.

**Evidence (W3-1, observed, Phase 0).** `[Database] Warband bank gold set to 11294783865` fired
**twice** per bank open in the recorded log, on both bank opens — once from
`WarbandBankTracking`, once from `NetWorth:UpdateWarbandBankGold`. This is the two-writer defect
this phase exists to collapse, observed directly rather than inferred from source.

**Steps.**
1. **W3-1.** Login zeroes the account-shared warband bank and fabricates a transfer:
   `WarbandBankTracking.lua:64` calls `InitializeWarbandGold()` unconditionally in `OnEnable`
   (i.e. at `ADDON_LOADED`, nowhere near a bank); the guard at `:74` is `currentGold >= 0` so **0
   is accepted**, and `IM:SetWarbandBankGold(0)` also stamps `warbandBankGoldUpdated = time()`
   (`Database.lua:881-885`) — destroyed data relabelled as fresh. Then `_lastWarbandGold = 0` makes
   the next real `ACCOUNT_MONEY` compute `delta = +fullBalance` → a phantom `warbank_deposit` for
   the entire balance (`:132-139`).
2. **W3-1 (the single-writer fix).** `IM:UpdateCharacterGold` **already implements exactly this
   guard** for character gold (`Database.lua:598`); the warband writers just do not. At the one
   writer: reject a write that lowers a nonzero stored value unless the account bank is actually
   reachable (Phase 0 item 3's interaction type); treat `nil` **and** `0` as **UNKNOWN, not zero**
   (`IM:SetWarbandBankGold` currently coerces `nil`→0 via `copper or 0`, so the sink has no
   rejection path either); **do not stamp the timestamp on a rejected write**; never reset
   `_lastWarbandGold` to `0` — leave it `nil` and skip the first delta; and delete the `OnEnable`
   init.
3. **W3-1 (collapse the second writer).** `NetWorth.lua:401-415` has the identical `>= 0` hole and
   is wired to `ACCOUNT_MONEY`, `BANKFRAME_OPENED` and
   `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`. **`NetWorth` must READ `IM:GetWarbandBankGold()`, not
   write it.** After this, exactly one function in the tree writes warband gold.

**CHECKPOINT** — log in on a fresh session without opening any bank: warband gold unchanged,
timestamp unchanged, zero new ledger entries.

4. **W3-4.** `UpdateInventoryValue` dereferences a nil `charData` (`NetWorth.lua:257-262`).
   `IM:GetCharacterData` is documented to return nil on early load (`Database.lua:556-562`) with
   "CALLERS MUST handle nil" at `:536-537`; `UpdateCharacterGold` guards it (`:586-590`), this does
   not. Reachable from the `PLAYER_MONEY` 0.1s handler (`:48-53`) and the 2s login timer
   (`:128-130`). **The error aborts the enclosing `C_Timer` callback, so paired work in that
   closure never runs** — which is why this presents as random missing updates rather than as an
   error. Add the guard and make the early-return explicit.

**Exit criteria (in-game smoke checklist).**
- **Log in without visiting a bank: warband gold is unchanged, its "as of" timestamp is unchanged,
  and no phantom transfer appears in the ledger.** Repeat across three characters.
- Open the account bank, deposit gold, and confirm exactly one transfer entry with the right
  amount and sign.
- Open the account bank, withdraw gold, confirm one entry the other way.
- With `/im debug` on, confirm a rejected write logs a rejection line rather than silently
  succeeding.
- Log in as a brand-new character (never seen by the addon) and confirm no Lua error in the first
  three seconds and that the net-worth panel populates once data is ready.
- `grep` proves exactly one writer of `warbandBankGold` remains.

**Reviewer fan-out prediction.** Data-integrity seat and one seat for the nil-contract guard.

---

#### Phase 9 — Inventory value split, snapshot write rule, currency capture

**Task and purpose.** Make inventory value three separate numbers with separate lifetimes, and
make every snapshot writer refuse to replace good data with nothing, in order that the account
total counts warband contents once and bank value stops evaporating when you walk away.

Carries risk R3. Consumes Phase 0 items 2 and 3.

**Ancestor fix**: `CalculateInventoryValue` returns `(bagsValue, bankValue, warbandValue)`.
**Symptoms that die with it: W3-2, W3-3, W3-5** — plus the same two bugs in the dead
`IM:GetAccountNetWorth`, which reimplements `GetAccountBreakdown` and inherits both independently.

**Evidence (W3-2/W3-3, observed, Phase 0).** Before opening a bank the character held 1 bag item
worth `0c`. On bank open, `/im debug` logged `[InventorySnapshot] Scanned bank: 7 items` then
`[NetWorth] Inventory scan: 27 items, 143g 2s 36c` → `Updated inventory value: 143g 2s 36c`. 1 bag
item + 7 bank items = 8; the scan counted **27**, so roughly 19 warband-tab items were folded into
the count, and `143g` is now stored on `Chzuljinn-Zul'jin`'s `inventoryValue` — the ×alt-count
inflation (W3-2) is not theoretical, it is already sitting in the owner's live database. The same
event is direct proof of W3-3: that `143g 2s 36c` figure came from `0c` purely by opening a bank,
on the per-character scalar the very next bags-only pass overwrites back toward `0c`.

**Evidence (A6, partially verified, Phase 0 W0-2 — affects step 9 below).**
`C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)` returns a live table cold (no bank frame
open), not `nil`. **Its element count is unmeasured and stays open** — step 9's cold-refresh
capability is written as conditional on that count, not confirmed by it.

**Steps.**
1. **W3-2.** Warband bank item value is multiplied by the alt count:
   `CalculateInventoryValue(true)` folds `Enum.BagIndex.AccountBankTab_1..5` into one scalar
   (`NetWorth.lua:227-252`) persisted to the **current character's** `inventoryValue` (`:257-262`),
   and `GetAccountBreakdown` (`:317-319,379`) then sums every character and adds warband gold on
   top. Five alts who opened a bank = 5× the warband contents. `IM:GetAccountNetWorth`
   (`Database.lua:865-873`) repeats the bug independently.
2. **W3-3.** Bank value evaporates when you walk away: the same scalar holds bags-only **or**
   bags+bank depending on which handler fired last; bank contents are included only while
   `BankFrame:IsShown()` (`:184`), and the next `BAG_UPDATE_DELAYED` (`:69-79`) or `PLAYER_MONEY`
   (`:47-54`) recomputes bags-only and overwrites. `GetInventoryValue` (`:277-281`) falls through
   to `UpdateInventoryValue(false)` and does the same.
3. **W3-5.** Reagent bag counted twice: `IM:GetBagIDsToScan()` already appends
   `Enum.BagIndex.ReagentBag` (`NetWorth.lua:156`, `Filters.lua:647-657`), and then
   `NetWorth.lua:170-181` scans bag 5 **again** behind `if C_Container.GetContainerNumSlots(5) then`
   — **always true, because Lua treats `0` as truthy.** Delete `:170-181`; `GetBagIDsToScan` is the
   single source of truth.
4. **The one change for 2+3+5.** Return the triple; bags refresh freely; **bank persists with its
   own `bankValueTimestamp` and is never overwritten by a bags-only pass**; warband value is stored
   **once globally**, next to the already-correctly-global `warbandBankInventory`
   (`Database.lua:157-161`). `GetAccountBreakdown` adds the global warband value **exactly once**.
   Give `IM:GetAccountNetWorth` the same treatment or delete it (Phase 18 decides deletion on
   Phase 0's death verdict; if it survives, it gets the fix).

**CHECKPOINT** — open a bank on one alt, walk away, loot something: bank value is still counted and
still carries its own timestamp. Log in on a second alt that also opened a bank: the account total
counts the warband contents once, not twice.

5. **W3-6.** Empty scans clobber good snapshots and the retry is dead code: `ScanBags`
   (`InventorySnapshot.lua:228-276`) returns `true` whenever `IM.db.global` and `charKey` exist —
   it never reports whether an item was read (`:275`) — so `TryScanWithRetry`'s exponential backoff
   (`:63-82`) never fires because attempt 1 always "succeeds". `snapshot.bags = items` assigns
   unconditionally at `:270`, same shape at `:306` (bank) and `:328` (reagentBank).
   **Backward reference — this is the other half of the Phase 3 collision, not an independent fix.**
   Phase 3's login-settle latch (step 3 there, OQ-2) wraps this same `ScanBags` call in a per-login
   completion latch, and that latch was built to consume this exact return value: before this step,
   `ScanBags` always reports success, so the latch behaves as a fire-once latch; after this step,
   an honest `false` leaves the latch unset and the path re-runnable. **Do not treat this as done
   once the return-value change lands** — re-run Phase 3's Half 3 smoke check and this phase's own
   cross-check exit criterion below, with the latch live, before calling either phase complete.
6. **W3-7.** `ScanWarbandBank` destroys account-shared data unconditionally: `:337-374` writes
   `IM.db.global.warbandBankInventory = { timestamp = time(), items = items }` at `:368-371` **even
   when `tabIDs` is nil or empty** — the `if tabIDs` guard at `:346-348` skips the **loop, not the
   write** — and stamps a fresh timestamp on the emptiness.
7. **The one rule for 6+7, applied at the write sites.** Never replace a non-empty stored snapshot
   with an empty one. Make `ScanBags` return `false` when `totalSlots == 0` so the retry actually
   retries. `ScanWarbandBank` additionally needs an **"is the account bank readable" precondition
   before it may write at all** (Phase 0 items 2 and 3 supply the test). **Item 3's answer (A7,
   Phase 0 W0-3) came back "no usable event" — the warband bank fires no distinct interaction, ever,
   on this client** — so this precondition cannot be an event listener either; it is the same
   process-time `C_Bank.IsAccountBankPanelShown()` check Phase 7 uses for W2-18, not an event-driven
   one. Do not design this precondition around `AccountBanker` firing.

**CHECKPOINT** — `/reload` and immediately query cross-character inventory: no snapshot is emptied;
with `/im debug` on, a failed first scan visibly retries.

8. **W3-15.** Currencies are never captured, though `C_CurrencyInfo` needs **no bank or vendor
   visit** — this is the direct answer to requirement 5. `currencyFavorites`
   (`Database.lua:144-146`) is the only currency state, and `Modules/CurrencySearch.lua` is purely
   a search box over Blizzard's `TokenFrame`. Fix: walk
   `GetCurrencyListSize`/`GetCurrencyListInfo`/`GetCurrencyInfo` and store account-wide currencies
   **once globally** (same rule as the warband bank) and genuinely per-character ones under
   `characters[charKey].currencies`.
   **Two triggers, two different mechanisms — do not give both their own debounce.** The
   `PLAYER_ENTERING_WORLD` half is startup work, so it routes through Phase 3's login-settle latch
   (this capture becomes a fifth wrapped path, alongside BagUI's bindings, `BagData`'s refresh,
   `InventorySnapshot`'s scan and `NetWorth`'s logging) rather than inventing a second, independent
   startup debounce — that would be the exact duplication this plan spends Phase 3 (OQ-2) and Phase
   17's B8 killing everywhere else. The `CURRENCY_DISPLAY_UPDATE` half fires during play, not at
   startup, so it keeps its own debounce, at the project's 0.5s shape. **Dependency: this step needs
   Phase 3's latch to exist first** — see §3.4, Phase 3 precedes Phase 9.
9. **Phase 0 item 2 (A6) came back partially verified: the tab-ID table reads cold and is not
   `nil`, but its element count is unmeasured.** That count, not the table's mere existence, is
   what decides this step: a non-empty count unlocks the cold warband-item refresh capability —
   `ScanWarbandBank` becomes callable anywhere rather than only at the bank, the "let's get
   creative" win — while an empty or unusable count means no substitute mechanism and no guessing.
   **This step therefore stays conditional on a check that has not been run yet**: before writing
   the capability, read `#C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)` cold and record
   the number. Do not guess it from the table's existence alone.

**Exit criteria (in-game smoke checklist).**
- With two alts that have each opened the account bank, the account total counts warband item value
  **once**; disable one alt's data and the total drops by that alt's bags only.
- Open a bank, walk away, loot ten items: bank value persists, bags value updates, and the Net
  Worth panel shows separate bank and bags figures with the bank's own timestamp.
- A character with a reagent bag shows a reagent bag value counted exactly once (compare against
  hand-summed vendor prices for a small, known set).
- `/reload` and immediately search cross-character inventory: previous snapshots are intact.
- Log in with no account bank access and confirm `warbandBankInventory` is untouched and its
  timestamp unchanged.
- Currencies appear for the current character after one login; a second character adds its own
  per-character currencies without disturbing the account-wide set.
- **The latch/retry cross-check (Phase 3 collision, OQ-2 — this is the proof the two phases
  actually compose, not an assumption).** With Phase 3's login-settle latch live, force a failed
  first scan — either a login where bags are genuinely not yet populated, or a temporary forced
  `return false` at the top of `ScanBags` — and confirm: (1) `TryScanWithRetry`'s exponential
  backoff still fires and eventually stores a non-empty snapshot, and (2) the per-login latch for
  `InventorySnapshot`'s path did **not** set on the failed attempt (a subsequent legitimate scan in
  the same login still runs). Remove any temporary forced-failure code before commit.

**Reviewer fan-out prediction.** Data-model seat (the triple return and where each value lives),
a data-integrity seat for the never-write-empty rule, and a performance note on the currency walk.
The latch/retry cross-check earns its own small correctness seat shared with Phase 3's reviewer.

---

#### Phase 10 — One accounting system

**Task and purpose.** Delete SellHistory's writers, in order that every transaction is written by
exactly one system and the Dashboard and the History panel stop describing different data.

**Ancestor fix**: retire the writers. The read/format helpers survive **this** phase only — they
read `sellHistory.entries`, and Phase 11 deletes that key from the data *and* from `defaults`, so
Phase 11 retires or guards each surviving reader as part of the same commit. This phase does not
leave them standing permanently; it leaves them standing for one phase.
**Symptoms that die with it: W3-8, W3-9.**

**Steps.**
1. **W3-8.** Two accounting systems have been written in parallel ever since the v1→v2 migration
   copied `sellHistory` into `transactions` without stopping the legacy writers: loot is handled by
   **both** `SellHistory.lua:98` and `LootTracking.lua:115` (both call `IM:AddLootHistoryEntry`);
   `BuyMerchantItem` is hooked **twice** (`SellHistory.lua:106`, `VendorTracking.lua:235`, calling
   `IM:AddPurchaseHistoryEntry` at `:126`/`:265`); auction sales twice (`SellHistory.lua:193`,
   `AuctionTracking.lua:241`); protected-item buyback **three times** (`VendorTracking.lua:284`
   ledger, plus legacy at `:293` and `ItemLock.lua:157`). SellHistory's copies also skip the
   vendor/AH/mailbox context guards `LootTracking.lua:43-70` has, so they fire in contexts the
   design excludes. `UI/Panels/History.lua:38` renders the doubled legacy store while the Dashboard
   reads the other, and `sellHistory` is capped at 100 (`Database.lua:399-402`) so
   `GetTotalGoldEarned`/`GetTransactionStats` are truncated.
2. **W3-8 (the fix).** Delete `RegisterLootTracking`/`RegisterPurchaseTracking`/
   `RegisterAuctionTracking` and their handlers — `SellHistory.lua:26-40,52-99,101-131,133-206` —
   keep the read/format helpers, point `Panels/History.lua:38` at `IM:GetLedgerStats`, and remove
   the duplicate `IM:AddBuybackHistoryEntry` at `ItemLock.lua:157`.
   **This list is `SellHistory.lua`'s half of W3-8, and it is not all of W3-8.** Nine more live
   legacy-store writes survive it, in the **Tracking** modules and `Core.lua` —
   `LootTracking.lua:115`, `VendorTracking.lua:226,265,293`, `AuctionTracking.lua:142,241,388`,
   `Core.lua:509,516` — and they are retired in **Phase 11 step 12, its own "retire legacy
   accessors" commit immediately before the atomic commit** (owner decision, revision six: a
   deletion has no shape-disagreement window, so it does not belong inside the reshape's atomic
   commit). **They are in scope for W3-8, not new work**: the brief's W3-8 named SellHistory's own
   writers and dropped the Tracking-module calls the original audit had flagged. W3-8 is not closed
   until both halves are.
   **Neither half deletes the legacy DATA.** The data and its `defaults` entry are dropped together
   in Phase 11's atomic commit, because the two halves coming apart is R2's most dangerous failure
   path. Retire accessors, not rows.
3. **W3-9.** Dead SellHistory stats read a field nothing writes: `IM:AddHistoryEntry` writes
   `value`, never `sellPrice` (`Database.lua:384-394`), so `GetStatistics` (`SellHistory.lua:289-291`)
   always returns zeros, `ExportToString` (`:324`) prints `0c` per row, and `GetSessionTotal`
   (`:359`) **would raise a nil arithmetic error** if anything called it. All three are unreferenced
   outside the file — latent, not live. `GetTodaysSales` (`:348`) also still uses UTC midnight, a
   bug already fixed in `Ledger:GetDatePresets` (`Ledger.lua:241-246`). **Delete all four with
   item 2**, rather than repairing functions whose data source is being retired.
4. **Do not delete the `sellHistory` data or its `defaults` entry here** — that is Phase 11's
   migration, and doing it without removing it from `defaults` would not hold (`_mergeDefaults`
   re-adds any nil default key). Removing the writers first is what makes the migration's deletion
   final. Record the entry count of `sellHistory.entries` at the end of this phase; Phase 11's
   retirement-commit guard ("same entry count before and after") is measured against it.
5. **Hand Phase 11 the surviving-reader list, written down, as this phase's output — as a SEED,
   not as a proof of completeness.** Phase 11 step 3 re-derives both directions by grep and that
   grep is authoritative; this list exists so Phase 11 starts from something rather than nothing.
   **It is readers only, and a reader-only handoff is exactly how `IM:AddHistoryEntry` and its nine
   Tracking call sites survived four revisions** — Phase 11 step 3 is what catches the writers.
   Deleting the
   writers leaves readers that still dereference `self.db.global.sellHistory.entries` with no
   guard, and Phase 11 removes the key they read. Enumerate them here so Phase 11 has no discovery
   work to do: `IM:GetSellHistory` (`Database.lua:435-437`), `IM:ClearSellHistory` (`:439-442`),
   `IM:GetTotalGoldEarned` (`:445-447`), `IM:GetTransactionStats` (`:488-498`),
   `SellHistory:GetFormattedHistory` (`Modules/SellHistory.lua:207-208`) and
   `SellHistory:GetEntriesSince` (`:333-334`). Note their live callers:
   `UI/Panels/History.lua:124` calls `GetFormattedHistory`, `:268` calls `IM:ClearSellHistory`,
   and `Core.lua:486,493` still list `sellHistory` as a valid `/im reset` section. Note also that
   `GetEntriesSince`'s only callers are `GetTodaysSales` (`:349`) and `GetSessionTotal` (`:355`),
   both of which step 3 deletes — so after this phase it has **zero** callers and Phase 11 deletes
   it rather than guarding it.

**Exit criteria (in-game smoke checklist).**
- Loot gold, buy an item, sell on the AH and buy back a protected item: each produces **exactly
  one *ledger* entry**.
- **`sellHistory.entries` still grows in this phase, and that is expected — do not treat it as a
  failure and do not chase it here.** The earlier form of this criterion said the store must gain
  **nothing**, which **cannot pass as written**: the nine surviving Tracking/`Core.lua` call sites
  named in step 2 keep writing it on every loot and every vendor sale until Phase 11 step 12
  deletes the writer family. The honest criterion for **this** phase is narrower and checkable:
  after the four actions above, `sellHistory.entries` gains **at most one entry per action** —
  never two — which is what proves `SellHistory.lua`'s duplicate writers are dead. Count
  before/after in the saved variables after a `/reload`. The "gains nothing" check belongs to
  Phase 11 and is written into its exit criteria as "no `sellHistory` key at all."
- The History settings panel and the Dashboard ledger now show the **same** totals for the same
  period.
- Totals are no longer truncated at 100 entries: a period containing more than 100 transactions
  reports the full figure.
- No Lua error from any surviving SellHistory read/format helper when the History panel opens.
  **This criterion cannot catch the post-migration break and does not pretend to** — it runs while
  `sellHistory` is still in the data, so it proves only that this phase's deletions did not break a
  reader. The reader-vs-missing-key case is Phase 11's criterion, run **after** the migration.
- `grep` proves the four dead functions and the three registration functions are gone and nothing
  references them.
- The written surviving-reader list from step 5 exists and is handed to Phase 11. Phase 11 may not
  start its reader work by rediscovering it.

**Reviewer fan-out prediction.** One dead-code/DRY seat and one money-correctness seat (the
switch of `Panels/History.lua` onto `GetLedgerStats`).

---

#### Phase 11 — Character identity and the v3 migration (ONE ATOMIC PHASE)

**Task and purpose.** Normalize the character key at its producer **and** rewrite every stored key
in the same commit, in order that a realm with a space, a realm rename or a connected-realm partner
stops permanently double-counting gold — without the addon ever running for even one `/reload` with
a normalized producer against un-normalized storage.

**Carries risk R2 (residual HIGH, override required).** Runs after Phase 10, which kills
`SellHistory.lua`'s own duplicate writers; this phase kills the rest of them, then drops the key.
**The rows that exist only in the legacy store go with it — a deliberate accepted loss on the
owner's decision, recorded with all four fields as Appendix B L1.** Revision six planned a
consolidation merge here; revision seven withdrew it on the merits. Do not re-add it.

**Evidence (A13/A14, observed, Phase 0 step 7).** The owner's realms are `Warsong` and `Zul'jin`,
and `GetNormalizedRealmName()` **preserves the apostrophe** in `Zul'jin` — normalization strips
spaces and hyphens, not punctuation. `realmMap = {Warsong→Warsong, Zul'jin→Zul'jin}` — **identity**
for both. This is exactly the equality-proof input step 9A needs, and it is also why the seven
synthetic fixtures (Sustainment, above) are re-scoped to be the sole coverage of the key-rewrite
path rather than merely pathological cases alongside a real-data check — see step 9A and step 11 for
the mechanism, and the reviewer fan-out prediction below for the consequence to reviewer scope.

**This phase lands THREE commits, and which member goes in which one is the thing revision six
changed.** In order: (1) step 1's `IM:SplitCharacterKey` helper — safe alone, format-independent;
(2) step 12's **retirement commit** — the legacy store's readers and writers, deletions only, data
untouched; (3) step 13's **atomic commit** — FIVE members, the reshape and the migration. The rule
that assigns members, refined by owner decision and stated in full in step 3: *a commit must carry
every reader and every writer of a field whose SHAPE it changes; a field being deleted only requires
its accessors retired no later than the deletion.*

**Atomicity is the whole design of this phase. Read this before touching anything.** The working
copy is symlinked into WoW, so **every commit is live at the next `/reload`** — there is no staging
period. An earlier revision of this plan split the producer change and the migration across two
phases and tried to bridge the gap with a read-compat resolver (`IM:GetStorageKey`). Three review
rounds each found a *different* live defect in that gap and each patch opened the next one. The
gap was the producer. It is deleted.

**What that retires — if you find any of it in a stale copy, it is not the plan:**
`IM:GetStorageKey` and any read-compat resolver · any un-normalized fallback branch and any
step that deletes one later · the identity-vs-storage split (`IM:GetCharacterKey` is the **single**
producer again, for display strings, for the mail recipient and for indexing storage alike) ·
any per-table existence probe · the "no character-keyed table is indexed with an **unresolved**
key" gate · the risk row that scored the gap. None of these has a mechanism to guard any more.

**But one thing that gate was doing was NOT about the window, and deleting it cost the plan
three findings. Read this before you read the steps.** That gate was the only thing in the phase
that forced a walk of **write** sites. Everything else here derives its completeness from
`defaults` (step 6's key list) or from **read** sites (step 12's reader list) — and a persisted
character-keyed table can exist in neither. `mailHelper.pendingQueue` is exactly that: written at
`MailHelper.lua:385`, keyed by `rule.alt`, and **absent from `defaults`** (`Database.lua:108-115`
declares only `enabled`, `autoFillOnOpen`, `autoLootOnOpen`, `skipCOD`, `alts`, `rules`), so no
list built from `defaults` can ever contain it. Three consecutive review rounds each found a
*different* missing member of these same two sets — `pendingQueue`, then `sellHistory`'s own
writer and its Tracking-module callers, then `ledgerCharFilter`'s reader.

**So this phase stops asserting its sets and starts deriving them, and that is the structural
fix.** A hand-written list in a plan is a guess made by someone who was not looking at the tree; a
grep run by an executor is a fact about the tree as it is. Every enumeration below that
completeness depends on is therefore **two things**: a seed list of *known members, not
exhaustive*, and a step that runs the grep which is **authoritative**. Where the two disagree, the
grep wins and the seed list was wrong. **A plan cannot prove the exhaustiveness of a set by
listing it** — that is why steps 2 and 3 exist, why their exit criteria are phrased as "the grep
returns zero unhandled hits" rather than "the list above is complete", and why an executor who
finds a member the seed list omits has found the expected thing, not an emergency.

**This treatment applies to every set in this plan whose exhaustiveness matters and cannot be
proved by listing** — the charKey write sites (step 2), the readers-and-writers of every field this
phase's commits touch (step 3), and the greedy realm-parse sites (step 1, gated by its own grep,
not by its count).

**And one question in this phase is answerable by neither a grep nor a list, which is the OQ-1
lesson.** "Does this store hold rows that exist nowhere else?" is a fact about the owner's *data*,
not about the code: four review passes read the code correctly and still got it wrong, because the
code says the two stores hold the same *kind* of row and says nothing about which rows are still
there. **A store's shape does not tell you its lifetime.** Before retiring or consolidating any
store, ask what deletes rows from each side, on what axis, and whether one side can outlive the
other. Here the answer is known and the owner has **accepted the loss** (Appendix B **L1**), so this
phase carries no instrument to measure it — the lesson is a standing rule for the next store, not a
step in this one.

**Why atomicity actually works — the load-bearing claim, verified in source.** Every runtime site
that indexes a character-keyed table reads the producer *at call time*; none caches a key across a
`/reload`. So the moment the producer's output changes and the stored keys change in the same
commit, producer and storage agree again with no bridge. Confirmed sites:
- The four **argument-less** `IM:GetCharacterData()` callers, which are the row-creation path
  (`Database.lua:557` falls through to `self:GetCharacterKey()`, then creates at `:564-577`):
  `IM:UpdateCharacterGold` (`Database.lua:584`), `Ledger:OnPlayerLogin` (`Modules/Ledger.lua:114`),
  `NetWorth:OnPlayerLogin` (`Modules/NetWorth.lua:117`), `NetWorth:UpdateInventoryValue`
  (`Modules/NetWorth.lua:260`). **None needs an edit** — each resolves through the producer on every
  call, so all four flip with it.
- `IM:AddTransaction`'s `entry.char` stamp (`Database.lua:618`) — same: reads
  `self:GetCharacterKey()` per entry, needs no edit, and the migration rewrites the historical
  `.char` values in the same commit.
- `InventorySnapshot`'s three keyed writes (`:273, 309, 331`), keyed from `IM:GetCharacterKey()` at
  `:238, 285, 321` — no edit needed.
- MailHelper's four key comparisons, all of which compare producer output against stored keys and
  are therefore correct **only** because both change together: `GetAlts`'s self-exclusion
  (`MailHelper.lua:264`, compared at `:268` and `:282`), `AutoFillQueue`'s mail-to-self skip
  (`:440`, compared at `:455` against `rule.alt`), and `SendToAlt`'s realm-suffix decision
  (`:587`, compared at `:590` against the realm parsed out of the stored key).
- `mailHelper.alts` has **no live writer at all**: both `MailHelper:AddAlt` (`:297`, writing at
  `:299`) and `MailHelper:RemoveAlt` (`:304`, writing at `:305`) have zero callers tree-wide
  (verified in review), so only the migration's rewrite of already-stored rows matters for that
  table. **This is a claim about callers, not about the table's presence in the migration's pass** —
  `mailHelper.alts` is in the pass, and step 2's grep lists its write sites regardless of whether
  anything currently reaches them, because a dead writer that comes back to life later would write
  the wrong key format.

The two sites that **do** need editing, and must be edited **inside the atomic commit** for exactly
this reason, are the two live raw `GetRealmName()` calls that build keys outside the producer:
`UI/Panels/MailHelper.lua:400` (builds a rule's `alt`) and `MailHelper.lua:587` (builds the mail
recipient). Convert either one early and it disagrees with storage until the migration lands; that
is the defect this phase exists to make impossible.

**The third raw `GetRealmName()` is dead work — do NOT convert it.** `Database.lua:382` sits inside
`IM:AddHistoryEntry`, whose **function step 12 deletes** and whose store step 5 then drops. It goes
away with the writer family, not via a conversion. Converting it would be effort spent on a function
that stops existing one commit later.

**User decision on record — do not re-litigate:** no backup table, no `/im restore`, no release
gate. The user was asked twice and answered "just write it and ship it" both times. **The planner
and executor must NOT add a backup mechanism.** Two things survive as work rather than gates: the
offline verification below, which is part of building the migration, and one **advisory** line in
Phase 19's release checklist telling the user to copy `InventoryManagerDB.lua` out of WTF before
first login.

**Design constraint (verification leverage).** Write the migration as **pure functions taking
explicit inputs** — `migrateV2toV3(dbTable, opts) -> dbTable` with no `IM.db` reads, **no WoW API
call of any kind**, and every environment-dependent value injected through `opts`:
`opts.time`, `opts.date`, **`opts.normalizeRealm(realm) -> normalizedRealm, viaMap`** and
**`opts.realmMap`** (step 6). This is the only reason it is testable at all — and the realm
transform is **inside** that contract, not an exception to it. **A WoW API call anywhere in the pass
is a defect by construction**: the harness cannot execute it, so anything it does is invisible to
the proof R2 leans on. If a step seems to need one, the step is wrong, not the constraint.

**Steps.**

1. **W3-13 (safe to land first, on its own commit).** Add `IM:SplitCharacterKey` next to
   `GetCharacterKey` using `^([^-]+)-(.+)$`, and route every realm-parse site through it.
   **The authoritative gate is the grep, not the count** — run
   `rg 'match\("\^\(\.\+\)-"\)'` and `rg 'match\("-\(\.\+\)\$"\)'` and convert every hit.
   **Seed list — known members, 25 line entries, verified against the tree; the grep is
   authoritative**: `Database.lua:836,837`; `Ledger.lua:159,160`;
   `InventorySnapshot.lua:475,476,516`; `NetWorth.lua:308,309`;
   `MailHelper.lua:270,271,284,285,521,585,586`; `TooltipInfo.lua:161`; `UI/MailPopup.lua:154`;
   `UI/Dashboard.lua:597,624,1059,1240,1622`; `UI/Panels/MailHelper.lua:194,346`.
   **The composition of those 25 entries, because the single number was wrong in three documents
   and the mix is what matters**: **18** are the defective greedy name parse
   `:match("^(.+)-")` — the ones that actually produce W3-13's bug — and **7** are already-correct
   realm parses `:match("-(.+)$")` at `Database.lua:837`, `Ledger.lua:160`,
   `InventorySnapshot.lua:476`, `NetWorth.lua:309`, `MailHelper.lua:271,285,586`, which are
   converted for consistency and single-sourcing, not to fix a bug. The audits said 5; earlier
   revisions of this plan and of the brief said 24, which matched neither the enumeration (25) nor
   the defect count (18). **Do not re-derive a headline number: the closing condition is that
   `rg 'match\("\^\(\.\+\)-"\)'` returns zero hits.**
   **This one step may precede the atomic commit, and here is why it is safe**: the new pattern is
   **format-independent**. On a raw key it returns exactly what the greedy parse returned
   (`"Bob-Area 52"` → `"Bob"`, `"Area 52"`), and on a hyphenated realm it returns what the greedy
   parse got *wrong* (`"Bob-Kirin-Tor"` → `"Bob"`, `"Kirin-Tor"`, where greedy gave
   `"Bob-Kirin"`). It is a strict improvement at both key formats, so it neither depends on nor
   anticipates the producer change.

**CHECKPOINT** — the split helper is live and every consumer renders the right name and realm
(walk the Dashboard's three tabs, the mail popup, the tooltip and the mail-helper panel), while the
producer and every stored key are still **untouched and raw**. `grep` proves zero remaining
`:match("^(.+)-")` occurrences.

2. **DERIVE the migration's pass from write sites, by grep. This step comes before the migration
   is written, and its output — not the seed list below — defines what the migration touches.**
   Enumerate **every write site into every character-keyed table**: every assignment of the form
   `<table>[<key>] = …`, every `table.insert` into a character-keyed sub-table, and **every
   persisted snapshot of an in-memory keyed table** (the class the plan kept missing — an
   in-memory table keyed by a charKey, assigned wholesale into `IM.db.global.*`). Suggested greps,
   run all three and union the results:
   - `rg 'db\.global\.[A-Za-z.]*\[' --type lua` — direct keyed writes and reads.
   - `rg 'IM\.db\.global\.[A-Za-z.]+ = ' --type lua` — wholesale assignments, which is how
     `pendingQueue` hides.
   - `rg 'GetCharacterKey|charKey|altKey|rule\.alt' --type lua` — everything that produces or
     carries a key, then read each hit for where the value lands.
   **Every hit must end in one of two states, written down: in the migration's pass, or
   explicitly exempted with a stated reason.** No third state; an unclassified hit blocks the
   phase.
   **Seed list — known members, NOT exhaustive:** `characters` (`Database.lua:101`, written
   `:568`), `inventorySnapshots` (`:155`, written `InventorySnapshot.lua:273,309,331`),
   `mailHelper.alts` (`:113`, written `MailHelper.lua:299,305`), `mailHelper.rules[i].alt`
   (`:114`, written `UI/Panels/MailHelper.lua:400`), `transactions.entries[i].char` (`:95`,
   stamped `:618`), `transactions.entries[i].src` (`MailTracking.lua:157,169`,
   `TradeTracking.lua:113`), **`mailHelper.pendingQueue`** (no `defaults` entry at all; written
   `MailHelper.lua:385`), and `dashboard.ledgerCharFilter` (`:140`, written
   `UI/Dashboard.lua:584,607`).
   **Known exemptions, with reasons, so an executor does not re-litigate them:**
   `warbandBankInventory` (`:158-161`) is account-global and carries no character key;
   `customCategoryExclusions` (`UI/Panels/Categories.lua:244,279`) is keyed by category, not
   character; `bagUI.position`/`bagUI.height` are per-account UI state.
3. **DERIVE the membership of this phase's commits from readers AND writers, by grep. State the
   rule plainly, because it is the rule three review rounds found violated — and it was refined in
   revision six, so read the refined form and not the old one:**
   > **A commit must carry every reader and every writer of a field whose SHAPE it changes. A field
   > being DELETED only requires its accessors retired no later than the deletion.**

   **Why the refinement is not a loophole.** A reshape (`ledgerCharFilter` → `ledgerCharKey`: a
   rename *and* a retype) has a live disagreement window — a reader on the old shape meets a writer
   on the new one and errors, which is the whole reason this phase is atomic. A deletion has no such
   window: retire the accessors and the store simply stops being touched, its data sitting untouched
   until the migration removes it. So the accessor retirement is its own commit (step 12) landing
   **before** the atomic commit (step 13), and the atomic commit shrinks from seven members to
   **five**. Smaller is the point: a seven-member commit across ~9 files is not reviewable, and
   `git show` on it cannot be read as a proof of anything.
   **The one hazard the split creates, and the reason step 12 shouts about it**: a deletion commit
   that "finishes the job" by deleting the *data* separates the drop from the `defaults` removal
   that makes it hold, which is R2's most dangerous failure path. Accessors, not rows.
   For each field this phase rewrites or deletes, grep both directions and classify every hit:
   - `sellHistory` → `rg 'sellHistory' --type lua` (readers **and** writers; **step 12's retirement
     commit handles both**, after which nothing touches the store until step 5 drops it).
   - `ledgerCharFilter` → `rg 'ledgerCharFilter|charIndex' --type lua`.
   - `pendingQueue` → `rg 'pendingQueue|_mailQueue' --type lua`.
   - `HistoryEntry` → `rg 'HistoryEntry' --type lua` (the legacy writer family).
   - each character-keyed table from step 2 → `rg '<tableName>' --type lua`.
   **A reader left behind errors on a missing key; a writer left behind resurrects the data or
   nil-derefs the store.** Both are live defects, and a reader-only list catches only half —
   which is precisely how `IM:AddHistoryEntry` and its Tracking-module callers survived four
   revisions of this phase. Neither this step nor step 2 changes a line of code; they produce two
   written classifications that steps 4-13 consume.

**CHECKPOINT** — both derivation classifications from steps 2-3 are written down, every hit either
in-pass or exempted-with-reason, and **not one line of code has changed** (`git diff` is empty
beyond step 1's helper commit). This is the cheapest possible green state to be wrong in.

4. **Write the migration as pure functions. Wire nothing.** `migrateV2toV3(dbTable, opts) ->
   dbTable`: no `IM.db` reads, **no WoW API**, and `opts` carrying `time`, `date`,
   **`normalizeRealm(realm) -> normalizedRealm, viaMap`** and **`realmMap`** (step 6's transform —
   part of this contract, not an exception to it, and the reason the key rewrite is executable in the
   Docker proof at all). Also add `IM:NormalizeRealmString` itself in this step: it is a pure
   function on `IM`, so the harness can reach it and pass it in as `opts.normalizeRealm`.
   `DB_VERSION` stays at 2,
   `_runMigrations` is not touched, `IM:GetCharacterKey` is not touched, and nothing in the loaded
   addon can reach the new code. Steps 5-9A describe what these functions do, **over the set step 2
   derived** — not over step 2's seed list.
   **Do NOT extract a shared legacy-entry mapping function.** Revision six added
   `_legacyEntryToTransaction` — a hoist of the v1→v2 field mapping at `Database.lua:213-232` —
   solely so the withdrawn consolidation merge could dedupe against rows the v1→v2 code had
   produced. With the merge gone the v1→v2 block is the mapping's only caller, so the extraction has
   no second consumer and no independent justification; checked, and there is none. **Leave the
   v1→v2 block exactly as it is** — a refactor of a migration path that has already run for real
   users, bought for nothing, is a worse trade than the duplication it removes. Scaffolding for a
   deleted feature does not ship.
5. **W3-10 (drop `sellHistory`).** Delete
   `db.global.sellHistory` **and remove it from `defaults`** — `_mergeDefaults:181-192` re-adds any
   nil default key, so deleting the data alone will not hold. This is R2's most dangerous failure
   path; the `defaults` edit is not optional.
   **Both halves of the drop stay in the atomic commit (step 13), and here is why the `defaults`
   half is not moved into step 12's retirement commit with the accessors.** The `defaults` removal
   is what makes the data deletion *hold*, so it is part of the deletion, not part of the accessor
   retirement — and R2's most dangerous failure path is precisely the two halves coming apart.
   Keeping them in one commit means one `git show` proves the pairing. (Between step 12 and step 13
   the reverse state exists harmlessly: accessors gone, `defaults` and data both still present.
   `_mergeDefaults` never removes a key, so nothing resurrects and nothing errors.)
   **This step destroys the rows that exist only in this store, and that is the accepted outcome, not
   an oversight.** Appendix B **L1** records it with all four fields. Do not add a merge, a backup, or
   a retention override to soften it; the owner weighed it and chose the loss.
6. **W3-10 (normalize STORED keys) — READ THE WHOLE STEP BEFORE WRITING A LINE. The function you
   will reach for first is the wrong one, and calling it here is the single most destructive act
   available anywhere in this plan.**

   **DO NOT CALL `GetNormalizedRealmName()` IN THIS STEP OR ANYWHERE INSIDE THE MIGRATION.** It
   **takes no argument and returns the CURRENT player's normalized realm**; it is *not* a normalizer
   of an arbitrary realm string. Applied to a *stored* key it rewrites every alt's realm half to the
   running character's realm, and the merge rule below then merges characters that were never the
   same character — silent, unrecoverable destruction of alts' gold and snapshot rows, inside the one
   commit that touches the live database, with no backup by owner decision. The call is valid in
   **exactly one place in this plan**: step 13 member 1, the *producer* (`IM:GetCharacterKey`), where
   the subject genuinely **is** the current character. Nowhere else. One phrase covered two different
   operations in earlier revisions and only the producer half was ever valid.
   **It is also unexecutable here, which is why the Docker proof could not have caught it**: the
   migration is a pure function (step 4) and the harness (step 10) supplies only
   `Debug`/`Print`/`PrintError`, `time`/`date` and `opts`, so a WoW API call inside the pass either
   errors or is stubbed away — and the artefact R2 credits as its probability-mover would be proving
   a migration with the key rewrite switched off.

   **What to write instead — the pure transform, named, with its signature.** Add to `Database.lua`,
   beside `GetCharacterKey`/`SplitCharacterKey`:

   `IM:NormalizeRealmString(realm, realmMap) -> normalizedRealm, viaMap`

   - **Takes the realm string as an argument.** Reads **no** WoW global — not
     `GetNormalizedRealmName`, not `GetRealmName`, not `UnitName`. Pure: same input, same output,
     forever, in-game or in Docker.
   - `realmMap` is an explicit `raw realm string -> normalized realm string` table for the owner's
     **actual** realms, recorded in-game by **Phase 0 step 7** and written into `Database.lua` as a
     constant inside the atomic commit. A hit returns the mapped value and `viaMap = true`.
   - **A miss returns the input unchanged and `viaMap = false`. The transform never guesses.** There
     is deliberately no space-stripping or punctuation-stripping fallback rule: **normalized realm
     names strip punctuation and accents, not only spaces**, so no offline rule is provably
     equivalent to the API, and Lua 5.1's `%w` is locale-dependent and would mangle the UTF-8 bytes
     of an accented realm. A lookup that is proven equal (step 9A) or an identity that changes
     nothing are the only two behaviours this function has.
   - **The migration reaches it only through `opts.normalizeRealm`** (step 4's contract), never by
     name, so the harness supplies it and the pass stays pure.

   **Apply it to the realm half only.** Split each stored key with step 1's `IM:SplitCharacterKey`
   (`^([^-]+)-(.+)$`), leave the **name half byte-identical**, transform the **realm half**, rejoin.
   The realm half is the greedy tail, so a hyphenated realm (`"Bob-Kirin-Tor"`) splits correctly; and
   because every mapped value is punctuation-free, a rewritten key contains exactly one hyphen —
   after this migration the split is unambiguous for every key in the database.

   **Re-entry safety, which the `dbVersion` stamp does NOT give you** — this is the v1→v2 lesson
   (Appendix C's Idempotency row: v1→v2 was guarded *only* by a stamp, and a failed stamp write
   duplicated the ledger). The map's **keys** are raw realm strings and its **values** are normalized
   ones, so an already-migrated key **misses** the map, comes back unchanged, and cannot be
   transformed twice: the pass is idempotent by construction even if the stamp is never written.
   Keep it that way. The single thing that would break it is a map whose key set and value set
   overlap across *different* realms, so **assert that `realmMap`'s keys and values are disjoint
   except where a realm's raw form already equals its normalized form** (step 11).

   **Tables: every table step 2's grep placed in the pass** — known members being `characters`
   (`Database.lua:101`), `inventorySnapshots` (`:155`), `mailHelper.alts` and
   `mailHelper.rules[i].alt` (`:113-114`), `transactions.entries[i].char` (`:95`, stamped at
   `:618`) **and `transactions.entries[i].src`** — **in one pass**.

   **Merging is permitted ONLY between two keys whose realm halves both resolved `viaMap = true`.**
   Those merge by newest `lastSeen`. Handle the missing-`lastSeen` case explicitly: a nil `lastSeen`
   loses to any present one, and two nils merge by preferring the entry with more data. This is R2's
   most likely failure path; make the tie-break explicit in code, not incidental.
   **If either side resolved `viaMap = false`, do NOT merge and do NOT rewrite**: leave both keys
   byte-identical and log the pair. Reason: a merge is the only irreversible act in this pass, and it
   must never rest on an unproven transform. **Decision, recorded so nobody "improves" it into a
   guess:** a realm the owner could not log into during Phase 0 (a transferred or deleted character)
   keeps its raw key. Consequence, stated plainly: that character keeps today's realm-drift behaviour
   — if the owner ever logs in there again he gets a second row under the normalized key. That is
   **visible** in Net Worth and removable with step 14's per-row delete, whereas a wrongly-guessed
   rewrite is invisible and permanent. Cheap, reversible, and honest beats clever here.
   **`src` is not optional.** It holds character identifiers for mail and trade rows
   (`MailTracking.lua:157,169`, `TradeTracking.lua:113`, built name-plus-realm at
   `Panels/MailHelper.lua:400`) and **Phase 6's W2-16 reads exactly that field** to classify
   alt-to-alt mail as a transfer. Omit it and every historical transfer row silently reverts to
   income *and* expense, shifting the account totals. `src` may also legitimately hold a
   **non**-character string (a vendor name, `"Unknown"`) — normalize only values that resolve to a
   known character key **and whose realm half resolves `viaMap = true`**, leave everything else
   byte-identical, and assert both cases in step 11.
   **The `"Unknown"` exemption is a CLASS OF THREE SHAPES, not one literal — this is the trap an
   earlier revision walked into.** `Database.lua:216` builds the legacy char field as
   `(oldEntry.character or "Unknown") .. "-" .. (oldEntry.realm or "Unknown")` — **two independent
   fallbacks**, so `transactions.entries` can already contain `"Unknown-Unknown"`, `"Bob-Unknown"`
   **and** `"Unknown-Area 52"`.
   **Decision: exempt any `char`/`src` whose name half OR realm half is the literal `"Unknown"`, and
   leave the whole value byte-identical.** Do not normalize it and do not attribute it to the current
   character: attributing a row of unknown provenance to a real character fabricates that character's
   history and shifts its per-character ledger and net-worth figures. **Order matters: test the
   exemption BEFORE calling the transform**, so `"Unknown-Area 52"` is left alone even though its
   realm half is perfectly mappable.
   **Why the both-halves rule matters more than its probability suggests.** Exempting only the
   both-nil literal leaves `"Bob-Unknown"` inside the pass, where the transform would produce
   `"Bob-Unknown"`… or, if anyone ever reintroduces a current-realm default, `"Bob-<currentRealm>"` —
   **and step 11's assertion would PASS**, because that value *does* match a normalized key. The
   harness is structurally blind to exactly the harm this step's own reasoning is about: a real
   character's history fabricated onto a row that never belonged to it. Consequence for step 11: the
   exemption is asserted as a **class**, byte-identical, not as one literal string.
7. **W3-10 (`mailHelper.pendingQueue`) — DELETE it; the decision and its reason, so nobody
   "improves" it into a rewrite.** This is the table step 2 exists to catch: persisted at
   `MailHelper.lua:385`, keyed by `rule.alt` (`:458`) and by `altKey` (`:535`), re-persisted live
   from `:250,479,543,551,561,568`, restored into `_mailQueue` at `:159-160` in `OnEnable`, and
   **absent from `defaults`** (`Database.lua:108-115`), which is why every earlier revision's
   defaults-derived key list missed it.
   **What breaks if it is left alone**: after the atomic commit `rule.alt` is normalized while the
   restored queue keys are raw, so `SendToAlt` looks up `_mailQueue[altKey]`, finds `nil`, and
   reports "No items in queue" (`:578-581`) — while `pairs(_mailQueue)` at `:474,515,642` keeps
   rendering the orphaned rows and counting their items. Nothing clears it on its own:
   `autoFillOnOpen` defaults `false` (`Database.lua:110`), so `AutoFillQueue`'s `wipe` at `:425`
   never runs unattended.
   **Decision: the migration deletes `db.global.mailHelper.pendingQueue` outright rather than
   rewriting its keys.** Reason: the queue holds only `bagID`/`slotID` references to items that are
   still sitting in the user's bags — discarding it destroys no property and loses no gold, it
   costs one re-click of Auto-Fill. Rewriting the keys would be more code, would need its own
   idempotency case, and would carry stale bag coordinates forward anyway (bag positions move
   between sessions). **Do not add it to `defaults`** — the restore at `:159-160` is already
   nil-guarded (`if IM.db.global.mailHelper.pendingQueue then`), so a missing key is a clean empty
   queue, and adding a default would make `_mergeDefaults:183-187` recreate the table on every
   login for no reason.
8. **W3-10 (repoint the filter) — replace the field, do not retype it. This one is a RESHAPE, so it
   stays in the atomic commit; contrast step 12's deletions, which do not.**
   `dashboard.ledgerCharFilter` (`:140`) persists an **index** into a runtime-sorted char list
   (`Dashboard.lua:618-630`), so any key rename silently repoints the filter.
   **Decision: the migration DELETES `ledgerCharFilter` and writes a new field
   `dashboard.ledgerCharKey`** holding a normalized character key or `nil` for "All Characters".
   Reason: reusing the old name with a changed *type* is the exact shape of the I-3 defect below —
   a numeric value left in the DB and read as a key, or a key read as a number. A new name makes
   the mismatch unrepresentable: nothing reads `ledgerCharFilter` after this commit, so a stale
   numeric value is inert, and `ledgerCharKey` can only ever have been written by the new code.
   **The reader conversion is NOT deferred to Phase 14.** `UI/Dashboard.lua:411` loads the stored
   value straight into `_ledgerFilters.charIndex`, and `:622` does
   `chars[_ledgerFilters.charIndex - 1]` — arithmetic on the stored value. A stored key like
   `"Bob-Area52"` raises a Lua 5.1 error there and **aborts construction of the whole Ledger tab**;
   the self-healing branch at `:626-628` is never reached, because the arithmetic errors before it.
   The guard at `:619` tests `charIndex == 1`, which a string never satisfies, so this fires for
   any stored selection other than "All Characters" — a state step 11's own assertion guarantees
   exists in the owner's database. So **`Dashboard.lua:411,584,607,618-630` convert inside the
   atomic commit** (step 13 member 5), by the refined rule in step 3: a field whose **shape**
   changes carries every reader and every writer in the same commit. Phase 14's W4-11 keeps the
   `typeIndex`/`dateIndex` half and reads `ledgerCharKey` as already-converted.
9. **W3-10 (`warbandBankInventory`).** Leave the value alone (it is already correctly global) but
   ensure the migration does not strip or re-shape it, and that a nil or empty stored value is not
   replaced by an empty table with a fresh timestamp.

9A. **THE REALM-MAP EQUALITY PROOF — mandatory, and it is not belt-and-braces.** The migration's
   `realmMap` must be proven to produce **the same output as `GetNormalizedRealmName()` for the
   owner's actual realms** before the atomic commit exists. Mechanism, three parts:
   1. **Offline**: parse the copy of the real SavedVariables and list the **distinct realm strings**
      it contains — the realm half of every key in `characters`, `inventorySnapshots`,
      `mailHelper.alts` and `mailHelper.rules[i].alt`, plus every `transactions.entries[i].char` and
      `.src` that parses as a character key.
   2. **In-game**: **Phase 0 step 7** already recorded, per realm, the pair
      `(GetRealmName(), GetNormalizedRealmName())` into §1's assumption table (A14). Those pairs —
      not a rule, not an inference — are the map's contents.
   3. **Offline, asserted in the harness**: for every recorded pair, `realmMap[raw] == normalized`;
      and every distinct stored realm from part 1 is **either** in the map with a Phase-0-verified
      value **or** on the written "unvisitable — left byte-identical" list from step 6. A realm in
      neither state **blocks the atomic commit**.
   **Why this is mandatory rather than tidy.** Normalized realm names strip punctuation and accents,
   not only spaces, so a naive space-strip is **not** equivalent and no offline rule can be trusted
   sight-unseen. Without the equality proof the "atomic" commit can still land a **producer**
   (`GetNormalizedRealmName()`, member 1) and a **storage format** (the map's values) that disagree —
   which is the exact failure atomicity was bought to prevent, and it is **invisible to the Docker
   proof**, because the harness has no `GetNormalizedRealmName()` to compare against. The proof is
   what ties the pure transform back to the API it must imitate. Nothing else in this phase does.
   **Observed (Phase 0 step 7, A14): the proof is now trivial to state but stays mandatory to run.**
   Two realms, both identity — `(Warsong, Warsong)` and `(Zul'jin, Zul'jin)` — so `realmMap`'s two
   entries both map a string to itself, and normalization here strips spaces and hyphens, not
   punctuation. **"Trivial" describes the map's content, not the obligation to assert it**: this
   step's harness assertion (step 11 below) still runs, still blocks the atomic commit if either
   pair is missing, and still exists to catch the day one of these facts stops being true. A future
   realm transfer, a realm rename, or the owner rolling a character on a third, non-identity realm
   re-opens this proof for real; an unmapped realm is left byte-identical by design (step 6), not
   guessed at.

**CHECKPOINT — hard stop, not a convenience.** Green state before anything can touch the owner's
database: steps 1-9A are in the tree, the realm map is written from Phase 0's recorded pairs and
every distinct stored realm is either mapped-and-verified or on the unvisitable list, both derivation classifications from steps 2-3 are written
down with every hit either in-pass or exempted-with-reason, the migration exists **only** as pure
functions, the v1→v2 block is **unrefactored**, and
`DB_VERSION`, `_runMigrations`, `IM:GetCharacterKey`, `Panels/MailHelper.lua:400` and
`MailHelper.lua:587` are all **unchanged**. `git diff` proves the addon still runs the old v2 path
against raw keys with a raw producer. This is the last state from which nothing has been rewritten.

10. **The Docker proof (mandatory).** Build the harness the brief specifies:
   `loadfile("Database.lua")(addonName, IMStub)` with `IMStub` providing `Debug`, `Print`,
   `PrintError` (the only IM methods the migration path touches — `:237,246,255,259`), globals
   `time = os.time` and `date = os.date`, and `InventoryManagerDB` loaded from a **copy of the real
   SavedVariables file** (it is valid Lua and `loadfile`s directly). `_deepCopy`/`_mergeDefaults`/
   `_runMigrations` are file-locals, so the harness calls the public `IM:InitializeDatabase()`
   (`:251`), which chains all three and is the real entry point.
   **The stub list has one member the brief's version did not, and it is the whole reason the key
   rewrite is provable: `opts.normalizeRealm` and `opts.realmMap`** (steps 4 and 6). The harness
   supplies them as `opts.normalizeRealm = function(r) return IMStub:NormalizeRealmString(r, map) end`
   with `map` built from Phase 0's recorded pairs — `IM:NormalizeRealmString` is a pure method defined
   on the stub by `Database.lua` itself, so the harness exercises **the shipped transform**, not a
   test double of it. **The stub list is now closed: `Debug`, `Print`, `PrintError`, `time`, `date`,
   and the two `opts` members. Nothing else may be stubbed, because anything else the pass reaches
   for is a WoW API call and therefore a defect (step 4).** Run:
   `docker run --rm -v /tmp:/w -w /w akorn/lua:5.1-alpine lua migrate_test.lua`
11. **Assert.** Call `IM:InitializeDatabase()` **twice** and deep-compare: **the second run must be
   a byte-identical no-op.** Additionally assert: no character disappeared (count before vs after,
   accounting for deliberate merges, with each merge logged); `sellHistory` is absent from both the
   data and the merged defaults; **`ledgerCharFilter` is absent and `ledgerCharKey` is either nil
   or a key present in `characters`**; **`mailHelper.pendingQueue` is absent**; **every table step
   2's grep placed in the pass has been visited — assert per table, so a table silently skipped
   fails the harness rather than passing by omission**; every
   `transactions.entries[i].char` matches a normalized key **except the step 6 exemption class,
   asserted as a class and byte-identical: any value whose name half OR realm half is the literal
   `"Unknown"` — all three shapes `"Unknown-Unknown"`, `"Bob-Unknown"` and `"Unknown-Area 52"` —
   comes out byte-identical to its input. Assert the class, not the literal: a per-literal assertion
   passes on a fabricated `"Bob-<realm>"` because that value does match a normalized key**; **every
   `transactions.entries[i].src` that matched a known character key before the run matches a
   normalized key after it, and every `src` that did not (a vendor name, `"Unknown"`, nil) is
   byte-identical to its input.**
   **Four assertions about the realm transform itself, which are what make step 6 checkable rather
   than merely written down**: (a) **every rewritten realm half is a value present in `realmMap`'s
   range** — a rewrite to anything else means someone reintroduced a guessing rule or a WoW API call;
   (b) **every key whose realm half is absent from `realmMap` is byte-identical** before and after,
   and appears on the logged unvisitable list; (c) **no merge occurred between two keys unless both
   realm halves resolved `viaMap = true`** — the merge log names the pair and the resolution for
   each side; (d) **`realmMap`'s key set and value set are disjoint**, except where a realm's raw
   form already equals its normalized form — the property that makes the pass re-entry-safe without
   leaning on the `dbVersion` stamp (step 6), which is exactly the guarantee v1→v2 lacked.
   Add a case with a spaced realm name, a case with two colliding
   keys where one lacks `lastSeen`, a case whose `src` is a non-character string, **a case for each
   of the three `"Unknown"` shapes, and a case whose realm is absent from `realmMap` (which must come
   out untouched and unmerged)**.
   **These synthetic cases are not optional colour on top of the real-data run — per A14 (Phase 0
   step 7) they are the ONLY thing in this harness that exercises the rewrite, merge and exemption
   logic at all**, because both of the owner's real realms are identity under `realmMap` and the
   real-data run therefore rewrites, merges and exempts nothing. **A real-data run showing zero key
   changes is the expected result of that fact, not a passing test of this logic** — do not read it
   as one, and do not let a future pass trim these fixtures because the real-data run "already looks
   clean."
   **One assertion about what the migration must NOT do, because the drop is destructive by
   design.** `#transactions.entries` before vs after must be **unchanged** — the v3 pass rewrites
   `transactions` keys and drops `sellHistory`; it must never insert, append or re-import a
   transaction row. An entries count that *grows* means someone re-added the withdrawn consolidation
   merge, or that the v1→v2 block is being re-entered; both are the doubling v1→v2 caused. This is
   the standing guard that replaces revision six's merge assertions.

**CHECKPOINT** — the Docker artefact is green (second `IM:InitializeDatabase()` a deep-compare
no-op against a copy of the real SavedVariables, every step-11 assertion passing) while the addon in
the tree is **still running the old v2 path with the raw producer**.

12. **THE RETIREMENT COMMIT — "retire legacy accessors". Its own commit, landing immediately
    BEFORE the atomic commit. Owner decision, revision six.**
    **Why it is not inside the atomic commit** (step 3's refined rule): every member of this commit
    is a **deletion**, and a deletion has no shape-disagreement window. Retire the accessors and the
    legacy store simply stops being touched, while its data sits untouched until the atomic commit
    drops it. Nothing here can disagree with anything, so bundling it into the reshape's commit
    bought nothing but a seven-member diff across ~9 files that `git show` could not usefully prove.
    **THIS COMMIT MUST NOT DELETE THE DATA.** Not `db.global.sellHistory`, not
    `sellHistory.entries`, not the `defaults` entry. All three belong to step 5, inside the atomic
    commit, **because the data drop and the `defaults` removal must land in one `git show` — the two
    coming apart is R2's most dangerous failure path** (`_mergeDefaults` re-adds any nil default key,
    so a data-only deletion silently resurrects on the next login and the version stamp says it
    worked). The check is mechanical: `sellHistory.entries` has the same entry count after this
    commit as before it.
    **What this commit does contain** — retire every reader AND every writer of the legacy store,
    using step 3's derived classification and Phase 10 step 5's written list:
    **`sellHistory` readers.** Deleting the data and the `defaults` entry leaves five unguarded
    readers and two reachable UI callers dereferencing `self.db.global.sellHistory.entries`, so the
    History panel errors the moment it is opened after the migration:
    - `IM:GetSellHistory` (`Database.lua:435-437`), `IM:ClearSellHistory` (`:439-442`),
      `IM:GetTotalGoldEarned` (`:445-447`), `IM:GetTransactionStats` (`:488-498`).
    - `SellHistory:GetFormattedHistory` (`Modules/SellHistory.lua:207-208`) — **live-called from
      `UI/Panels/History.lua:124`**.
    - `SellHistory:GetEntriesSince` (`:333-334`) — **zero callers** after Phase 10 deleted
      `GetTodaysSales`/`GetSessionTotal`, so **delete it** rather than guarding it.
    - `UI/Panels/History.lua:268` calls `IM:ClearSellHistory()`.
    - **`Core.lua:486` still lists `sellHistory` as a valid `/im reset` section** (and `:493`
      advertises it), so `/im reset sellHistory` reaches `IM:ResetSection` with no default behind
      it. Remove it from `validSections` and from the advertised list.
    **Decision: retire, do not nil-guard, wherever the function has no purpose without the store.**
    `GetSellHistory`, `GetTotalGoldEarned`, `GetTransactionStats` and `GetFormattedHistory` exist
    only to read a store that no longer exists; a nil guard would leave four functions that
    permanently return nothing, which is the "dead code with a title" the no-duct-tape rule says to
    delete. Delete them and repoint their two live callers: `UI/Panels/History.lua:38` and `:124`
    onto `IM:GetLedgerStats` / `Ledger:GetFormattedEntries` (Phase 10 already repoints `:38`), and
    `:268`'s Clear button onto the ledger's own clear path — or remove the button if the ledger has
    no equivalent, which is a decision to record in the commit, not to leave half-done.
    **The ordering constraint that governs this, restated in the refined rule's terms.** The
    `defaults` edit is **not** benign pre-wiring: with `sellHistory` out of `defaults` but the
    readers still standing, `/im reset` recreates the defaults **without** the key and every reader
    breaks immediately. Two revisions ago that argument put the `defaults` edit and the reader
    retirement in the same commit. The refined rule gets the same protection more cheaply: the
    accessors are retired **no later than** the deletion, and one commit earlier is earlier than
    "no later" — so the `defaults` edit stays with the data drop in step 13 and this commit
    precedes it. The forbidden order is the reverse one; **never land the `defaults` edit or the
    data drop before this commit.**

    **`sellHistory`'s own WRITER and its live callers — the half no reader list contains.** The
    store has a writer that Phase 10 never touched and this phase never listed:
    `IM:AddHistoryEntry` (`Database.lua:380-403`, inserting at `:396` and trimming at `:399-401`)
    plus its **six** convenience wrappers — `AddSellHistoryEntry` (`:406`),
    `AddBuybackHistoryEntry` (`:411`), `AddLootHistoryEntry` (`:416`), `AddPurchaseHistoryEntry`
    (`:421`), `AddAuctionSoldHistoryEntry` (`:426`), `AddAuctionBoughtHistoryEntry` (`:431`).
    **Delete all seven functions in this commit**, and convert their surviving call sites.
    **Surviving live call sites — seed list from `rg 'HistoryEntry' --type lua`, which is the
    authoritative gate:** Phase 10's deletion covers only `SellHistory.lua:26-40,52-99,101-131,
    133-206` (i.e. `:98`, `:126`, `:193`) plus `ItemLock.lua:157`. These nine survive it, in four
    files:
    - `Modules/Tracking/LootTracking.lua:115` → `AddLootHistoryEntry` — **every item loot**.
    - `Modules/Tracking/VendorTracking.lua:226` → `AddSellHistoryEntry` — **every vendor sale**.
    - `Modules/Tracking/VendorTracking.lua:265` → `AddPurchaseHistoryEntry`.
    - `Modules/Tracking/VendorTracking.lua:293` → `AddBuybackHistoryEntry`.
    - `Modules/Tracking/AuctionTracking.lua:142` and `:388` → `AddAuctionBoughtHistoryEntry`.
    - `Modules/Tracking/AuctionTracking.lua:241` → `AddAuctionSoldHistoryEntry`.
    - `Core.lua:509` (`/im test loot`) and `:516` (`/im test sell`).
    **Two consequences, both already in scope for W3-8 — treat them as W3-8's remainder, not as new
    work.** The brief's W3-8 named SellHistory's own writers and dropped the Tracking-module calls
    the original audit had flagged; that is a brief defect, corrected here.
    - **W3-8 is only half-fixed even before the migration.** With these nine standing, the legacy
      store is still written in parallel by the Tracking modules on every loot and every sale — so
      **Phase 10's exit criterion "`sellHistory.entries` gains nothing" cannot pass as written**.
      Phase 10's criterion is amended accordingly (see that phase); the parallel writes stop here.
    - **After the key leaves the data *and* `defaults`, `AddHistoryEntry` nil-derefs at `:396`** —
      inside a `hooksecurefunc` body (`VendorTracking`) and inside the loot chat handler
      (`LootTracking`), i.e. erroring on **every sale and every loot**, in code paths whose errors
      are easy to miss because they are not user-initiated UI. **That is the "no later than the
      deletion" half of step 3's rule, and it is why this commit lands before step 13 rather than
      after it.** Retiring the writers one commit early costs nothing: the store stops being
      written while its rows sit intact until the atomic commit drops them alongside the `defaults`
      entry.
    **Decision: delete the writer family and its call sites outright, rather than pointing them at
    the ledger.** Reason: each of the nine sites already writes the ledger immediately alongside its
    legacy call — that duplication *is* W3-8 — so redirecting them would create the double-count the
    finding exists to remove. `Core.lua:509,516`'s two `/im test` commands lose their legacy half
    and keep whatever ledger write they already make; if a test command has no ledger equivalent,
    point it at `IM:AddTransaction` rather than leaving a command that writes nothing, and record
    that in the commit.

**CHECKPOINT — the retirement commit is green and the data is still there.** Nothing reads or writes
the legacy store any more, and the store itself is untouched. Prove all four, in this order:
`rg 'sellHistory|HistoryEntry' --type lua` returns hits **only** inside `Database.lua`'s `defaults`
block, the v1→v2 block and the migration's own drop (step 5) — nowhere else; loot an item, sell one
at a vendor and buy one back, then `/reload` and confirm **no Lua error** in `/im debug` from the
`hooksecurefunc` and loot-chat paths; `sellHistory.entries` has the **same entry count** as it did
before this commit (this is the pairing guard — the data drop belongs with the `defaults` removal in
the atomic commit, and a smaller count here means the two came apart);
`git show` proves this commit touched no `defaults` entry, no `DB_VERSION`, no `_runMigrations`, and
no character key. The addon is still running the old v2 path with the raw producer.

13. **THE ATOMIC COMMIT — one commit, the last live change in this phase, and the only one that
    touches the owner's stored data.**
    **FIVE members, numbered so the count is checkable against the list rather than asserted next
    to it.** It was seven before revision six; the two deletion-class members moved to step 12 by
    owner decision, per step 3's refined rule. **Revision seven removed work from inside member 3
    (the withdrawn consolidation merge) and the member count did not change** — the merge was a step
    inside the migration pass, never a member of this commit. Everything here lands together or
    nothing does:
    1. **W3-11, the producer.** Normalize inside `IM:GetCharacterKey` (`Database.lua:542-552`) with
       `GetNormalizedRealmName()`. `GetNormalizedRealmName` appears **zero times** in the tree today,
       and after this commit it must appear **exactly once** — here. **This call is correct in this
       member and only in this member**, because the subject genuinely is the current character; the
       migration rewrites *stored* keys through step 6's pure `opts.normalizeRealm` and must never
       name this function (step 6 says why, at length). This is the class-killer: without it the only
       remedy for realm drift is the "delete ALL" at `Panels/Dashboard.lua:262-277`.
    2. **The two live raw `GetRealmName()` conversions**: `UI/Panels/MailHelper.lua:400` and
       `MailHelper.lua:587`, onto the producer / `IM:SplitCharacterKey`. Not earlier, not later.
    3. **`DB_VERSION` bumped to 3** and `migrateV2toV3` wired into `_runMigrations` — carrying step
       5's drop, step 6's key normalization, step 7's `pendingQueue` delete and step 8's field
       replacement, in that order inside the pass. **The wiring is also where `realmMap` (the Phase 0
       pairs, step 9A-verified) becomes a `Database.lua` constant and is passed in as
       `opts.realmMap`/`opts.normalizeRealm`.** `IM:NormalizeRealmString` itself already landed in
       step 4 unwired; this member is what lets the pass reach it.
    4. **`sellHistory` removed from `defaults`** (step 5's other half — the two halves of the
       deletion stay together so one `git show` proves the pairing R2's most dangerous failure path
       is about).
    5. **The `ledgerCharFilter` → `ledgerCharKey` reader conversion** at
       `UI/Dashboard.lua:411,584,607,618-630` (step 8). This is the **reshape**, and the only member
       that has a disagreement window: without it the Ledger tab raises a Lua error on the first
       `/reload` after migration for any stored character selection.
    `git show` on this commit must show **all five** together, and must show **none** of step 12's
    deletions (they are already in history). A commit carrying the producer change without the
    wiring, or the wiring without the producer change, or the data change without the reader of the
    field it reshapes, is the failure this phase was restructured to make impossible; stop and
    squash rather than shipping it.

**CHECKPOINT** — the atomic commit is live on the owner's database and a second `/reload` changes
nothing: `characters`, `inventorySnapshots` and `mailHelper` each hold one row per character under
the normalized key, the Dashboard's Ledger tab constructs with a stored character selection, and no
`sellHistory` key exists in the saved variables. Steps 14-15 are additive work on the final key
format and can only be written safely from here.

14. **W3-12 (after the atomic commit).** Add **per-row character delete** so a stale or transferred
    character can be removed without the full wipe. `inventorySnapshots` are also never pruned for
    deleted characters — the delete must remove the character's row from `characters`, its
    `inventorySnapshots` entry, its `mailHelper.alts` membership, and leave its `transactions`
    entries intact (they are history, and deleting them would rewrite the ledger). Confirm via
    `StaticPopupDialogs`. Sequenced after the migration deliberately, so it is written and tested
    against the final key format only.
15. **W3-14 (after the atomic commit).** `UpdateCharacterGold`'s zero-guard is permanent
    (`Database.lua:598`) — a character who genuinely spends to zero keeps a stale snapshot forever,
    overstating net worth. **Decision: require two consecutive zero readings** rather than gating on
    time-since-login. Reason: the two-reading rule is testable and does not depend on a login clock
    that is wrong after a `/reload`.

**Exit criteria.**
- **The derivation greps return zero unhandled hits. This is the phase's completeness criterion,
  and it deliberately does not say "the lists above are complete."**
  - `rg 'IM\.db\.global\.[A-Za-z.]+ = ' --type lua` and `rg 'db\.global\.[A-Za-z.]*\[' --type lua`
    → every hit is either in the migration's pass or on the written exemption list with a reason.
    **Zero unclassified hits.**
  - `rg 'HistoryEntry' --type lua`, `rg 'ledgerCharFilter' --type lua`,
    `rg 'pendingQueue' --type lua` → **zero hits each**, in both directions, readers and writers
    alike.
  - `rg 'sellHistory' --type lua` → **hits only inside the migration functions** —
    `_runMigrations`'s v1→v2 block and `migrateV2toV3`, which must name the key in order to delete
    it (step 5). **This bullet is deliberately not "zero hits"**: the earlier
    revision said zero and was wrong on its own terms, because a migration that deletes a key has
    to mention it. Zero hits *outside* those two function bodies is the real condition, and any hit
    outside them is a surviving reader or writer.
  - `rg 'match\("\^\(\.\+\)-"\)' --type lua` → **zero hits** (step 1's real closing condition; the
    count in the seed list is not the gate).
  An executor who finds a hit no list in this plan named has found the expected thing. Classify it,
  handle it, and note it in the commit — that is the mechanism working, not a surprise.
- **Docker double-run proof green**: second `IM:InitializeDatabase()` is a no-op under deep
  compare, against a copy of the **real** SavedVariables file, on `akorn/lua:5.1-alpine`. Every
  assertion in step 11 passes, including **`#transactions.entries` unchanged across the run** — the
  v3 pass rewrites and deletes, it never inserts a transaction row. This artefact is the phase's
  proof; a passing single run is not.
- **The migration contains no WoW API call, and `grep` proves it**:
  `rg 'GetNormalizedRealmName|GetRealmName|UnitName|C_[A-Za-z]+\.' --type lua` inside
  `migrateV2toV3` and `IM:NormalizeRealmString` returns **zero hits**. The producer
  (`IM:GetCharacterKey`) is the **only** site in the tree that calls `GetNormalizedRealmName`, and
  `rg 'GetNormalizedRealmName' --type lua` returns **exactly one hit**. Two hits means the phrase
  leaked back into the migration, which is the one defect this phase is shaped to make impossible.
- **The realm-map equality proof is green (step 9A)**: every `(raw, normalized)` pair Phase 0
  recorded is present in `realmMap` with the recorded value, and every distinct realm string in the
  owner's stored keys is either mapped-and-verified or on the written unvisitable list. **No third
  state** — an unclassified realm blocks the atomic commit.
- **`git show` on the retirement commit (step 12) proves it is deletions only**: the `sellHistory`
  reader retirement and the legacy history writer retirement (`IM:AddHistoryEntry` + its six
  wrappers + the nine `LootTracking`/`VendorTracking`/`AuctionTracking`/`Core.lua` call sites +
  `Core.lua:486,493`'s `validSections`/advertised list), and **no** `defaults` edit, **no**
  `DB_VERSION` change, **no** `_runMigrations` change, **no** character-key change and **no** change
  to `sellHistory`'s stored rows. `sellHistory.entries` has the same entry count before and after.
- **`git show` on the atomic commit proves all FIVE members landed together** — matching step 13's
  numbered list exactly, one for one: (1) the `IM:GetCharacterKey` normalization, (2) the two raw
  `GetRealmName()` conversions, (3) the `DB_VERSION` bump plus the `_runMigrations` wiring (carrying
  the drop, the key normalization, the `pendingQueue` delete and the field replacement),
  (4) the `defaults` removal, (5) the `ledgerCharFilter` → `ledgerCharKey` reader conversion in
  `UI/Dashboard.lua`. **It was seven before revision six**; the two deletion-class members are in
  step 12's commit and `git show` on the atomic commit must **not** contain them. **And
  `git log -p` proves no earlier commit in this phase touched `IM:GetCharacterKey`,
  `Panels/MailHelper.lua:400` or `MailHelper.lua:587`** — that is the check that the window was
  never reopened by accident.
- **OQ-1's one visible consequence is observed and accepted, not treated as a regression.**
  Phase 0's verdict is now settled: `UI/Panels/History.lua` is **confirmed unreachable** (both
  directions, see this phase's A11/W0-6 evidence), so there is **no visible consequence at all** —
  no view exists to observe a span change in — and this criterion is discharged by that verdict
  line alone, with no in-game step. The row loss itself is still the accepted outcome of Appendix B
  **L1**; do not open a defect for it.
- **The mail queue is gone, not orphaned**: after the migration, `/reload` and open the mailbox —
  the mail popup shows an empty queue with no phantom rows and no stale item counts, and
  `pendingQueue` is absent from the saved variables. Then run Auto-Fill once and confirm a fresh
  queue builds under the normalized key and `SendToAlt` finds it (no "No items in queue" on a
  visibly non-empty queue).
- **The Ledger tab survives a stored character selection**: before the migration, select a specific
  character in the ledger filter (not "All Characters") so the old numeric value is on disk; after
  the atomic commit, `/reload` and open the Dashboard's Ledger tab. **It must construct with no Lua
  error and the filter must name a character whose rows are that character's.** This is the check
  that member 5 landed; without it the tab aborts mid-construction.
- **Nothing writes the legacy store any more — run this twice, once per commit, because the halves
  land separately now.** Loot an item, sell one at a vendor, buy one back and sell one on the AH,
  then `/reload`. **After the retirement commit**: `sellHistory.entries` gains **nothing** from those
  four actions (this is the criterion Phase 10 could not pass and handed forward) and its existing
  rows are all still there. **After the atomic commit**: the saved variables contain **no**
  `sellHistory` key at all. Neither run may produce a Lua error; the two error-prone paths are
  inside a `hooksecurefunc` body and the loot chat handler, so watch `/im debug` rather than
  trusting a silent screen.
- `grep` proves **no** storage-key resolver exists anywhere: no `GetStorageKey`, no un-normalized
  fallback branch, no per-table existence probe. `IM:GetCharacterKey` is the only key producer, and
  `grep` proves zero raw `GetRealmName()` calls survive outside it. `Database.lua:382`'s live call
  counts as satisfied by `IM:AddHistoryEntry` having been **deleted in step 12**, not converted —
  confirm the function is gone, not that the line was edited.
- `grep` proves **no `_legacyEntryToTransaction` exists**: the v1→v2 block at
  `Database.lua:206-247` is byte-identical to what it was before this phase. The extraction was
  scaffolding for the withdrawn merge (step 4).
- **After the migration, on the spaced/connected-realm character**: `/reload`, then count its rows
  in `characters`, `inventorySnapshots` and `mailHelper.alts` — **exactly one row each, now under
  the normalized key**. It appears **once** in Net Worth, not twice, and its gold is not
  double-counted in the total.
- **Mail still resolves to that character**: its mail-helper rule still matches its queue
  (`rule.alt` vs `_mailQueue`), `GetAlts` still excludes the *current* character rather than
  listing it as its own alt, and `SendToAlt` builds a recipient with **no** doubled or spurious
  realm suffix. Send one item to it and confirm arrival.
- **`UI/Panels/History.lua` is CONFIRMED UNREACHABLE (Phase 0, both directions — see this phase's
  A11/W0-6 evidence and Phase 18's evidence note). The grep proof is the stated method for this
  criterion, not a fallback, and there is no in-game half to run.** `UI/Config.lua:17-25` names no
  History tab, and the tree's one dynamic resolver over sub-tabs, `UI/Panels/Selling.lua:53`,
  resolves only its own four `subTabs` — nothing can construct `UI.Panels.History`, so there is no
  click path to test and no Lua-error-on-open case to reproduce. Discharge this criterion with
  `rg 'sellHistory|GetFormattedHistory|ClearSellHistory' UI/Panels/History.lua` returning zero hits,
  or with the file already deleted under Phase 18 step 10 (order-independent: Phase 18 runs after
  this phase, so at this point in the sequence the grep is what runs). Record the discharge in the
  commit; do not attempt to open the panel in-game looking for a path that Phase 0 already proved
  does not exist.
  **`/im reset sellHistory` either reports an invalid section or is gone from the advertised
  list — this half runs in-game regardless, and after the atomic commit, not before.** Phase 10's
  equivalent criterion runs while the key still exists and structurally cannot catch this.
  **Neither half is a licence to skip anything**: the unreachable panel's dead readers were already
  deleted in the retirement commit, because they live in `Database.lua` and `SellHistory.lua`,
  which are very much reachable regardless of whether `History.lua` itself is.
- Alt-to-alt mail rows recorded **before** this migration still classify as transfers afterwards
  (pick one known historical pair, confirm it is a transfer both before and after the run) — the
  `src` normalization check for W2-16.
- **In-game after the migration**: confirm the character count in Net Worth is unchanged (or reduced
  exactly by the logged merges); the ledger's total for "All Time" is unchanged; the ledger
  character filter still selects the character it names; cross-character inventory search still
  finds items on every character.
- **Second `/reload`** changes nothing further (in-game confirmation of the offline idempotency
  proof).
- `grep` proves `sellHistory` appears nowhere in `defaults`.
- Deleting one character from Net Worth removes exactly that character's row, its inventory
  snapshot and its alt membership; the ledger still shows its historical transactions; no other
  character is affected; a `/reload` confirms the deletion persisted.
- Spend a character to exactly 0 gold: after two readings the stored value is 0, and the account
  total drops accordingly rather than holding the stale figure.

**Reviewer fan-out prediction.** Data-migration seat (idempotency and the character-merge
tie-break), a data-model seat for the key format, one adversarial seat asked specifically to break
the character-key merge with the synthetic fixtures (spaced realms, hyphenated realms, colliding
keys with a missing `lastSeen`, all three `"Unknown"` shapes, a realm absent from `realmMap`) —
**these are no longer "pathological cases" run alongside a real-data check; per A14 they are the
sole coverage of the key-rewrite path**, since both of the owner's real realms are identity under
`GetNormalizedRealmName()` and the real-data run cannot exercise a rewrite, a merge or an exemption
at all — **and to check one thing first: that nothing in the migration pass calls a WoW API and
that `GetNormalizedRealmName` appears exactly once in the tree** — and one seat on the retirement
commit's blast radius across
`Database.lua`, `SellHistory.lua`, `Panels/History.lua`, `Core.lua` and the four Tracking modules
(`LootTracking`, `VendorTracking`, `AuctionTracking`). The retirement commit and the atomic commit
are separate rounds now and earn their seats separately from their own diffs.

---

#### Phase 12 — Ledger storage and the filter cache

**Task and purpose.** Fix the ledger's insert cost and growth, and the double-keyed item cache, in
order that the store stays usable at scale and the sell decision and the displayed value come from
the same lookup.

**Steps.**
1. **W3-16.** Ledger insert is O(n) and growth is unbounded: `table.insert(t, 1, entry)`
   (`Database.lua:644`) shifts the whole array per transaction, and `PurgeOldEntries` (`:799`)
   prunes by age only — with `maxAgeDays = 0` disabling it entirely (`:801`, default 30 at `:78`).
   Fix: **append at the tail, reverse in the read path, add a hard `maxEntries` cap.** The read-path
   reversal must land in the same change as the append, or every consumer silently flips order.
   **The cap is destructive and must not quietly out-rank the retention setting the owner chose.**
   It drops **oldest-first**, so a default set below the store's real size silently enforces a
   tighter policy than `ledger.maxAgeDays` does — a second retention policy nobody asked for. Two
   constraints follow: the cap's **default must exceed the number of rows the owner's own retention
   window actually holds** (read the count from his saved variables and pick a default above it — do
   not pick a round number and hope), so the cap acts as a ceiling against runaway growth rather
   than as a competing purge; and the cap must be **documented in the settings UI as destructive**,
   naming that it drops the oldest rows, not presented as a tidiness knob.
   **The default is pinned to one measurement, so it has a revisit trigger — write it into the
   commit.** Today's row count is today's play rate; heavier play later puts more rows inside the
   same 30-day window and the cap silently becomes the competing purge this constraint exists to
   prevent. **Trigger to revisit: the ledger reaching the cap while `maxAgeDays` is still purging
   nothing** — i.e. the cap, not the retention window, becoming the binding constraint. That state is
   observable, so make it visible: when the cap drops a row whose age is inside the retention window,
   log it once per session via `IM:PrintError` so the owner learns the cap has started deciding
   policy. Recorded in Appendix B.
2. **W3-17.** `_GetCachedItemInfo` is keyed two ways — `itemLink or itemID` (`Filters.lua:515`) vs
   `info.itemID` (`:679,711`) — producing two entries per item, and **the queue's displayed
   `totalValue` comes from a different lookup than the sell decision used**. Pick one key
   (`itemID`, since it is the stable identity and the link varies by suffix) and route both sites
   through it. Keep the existing 1000-entry prune.
   **This step reaches the bag window — it is on Phase 13's indirection audit.** `ShouldAutoSell`
   reads its quality, `sellPrice` and `bindType` from that lookup at `Filters.lua:514-515`, and
   `OverlayFactory:Update` (`:437`) calls `ShouldAutoSell` per bag item. For a suffix-varying item
   the `itemID` key can return different info than the `itemLink` key did, so **which items wear a
   will-be-sold ring can change**. That is a truth fix, not a presentation change, and needs no
   approval gate — but it is checked below, because Movement III is outside §3.4's Movement IV
   audit walk.
3. **W3-18.** `blockLockedPost` (`Database.lua:119`) has no reader —
   `AuctionHouseProtection.lua:132,157` always shows the confirm popup regardless of the setting.
   **Decision: wire the setting** rather than delete it, because the popup is a real interruption
   and the user already has a switch for it in the database; a setting that does nothing is the
   same lie as W5-11's dropdown.

**Exit criteria (in-game smoke checklist).**
- Ledger rows still display newest-first in the Dashboard after the append/reverse change (check
  the first and last page, and the date-preset boundaries).
- With a large history, opening the ledger tab is not perceptibly slower than before, and adding a
  transaction does not stutter (sell 20 items and watch for hitching).
- `maxEntries` enforced: with the cap set low, the store stops growing and the **oldest** entries
  are the ones dropped.
- With `maxAgeDays = 0` the age purge stays disabled but the cap still applies.
- The auto-sell popup's `totalValue` equals the sum of the per-item values shown in its rows
  (same-lookup check for W3-17).
- **Bag-window check for the cache re-key** (step 2's indirect consequence): with a suffix-varying
  item in the bags — an ilvl-scaling or upgradeable piece — open the custom bag before and after
  the change and confirm the will-be-sold rings are **the same set**, and that the ring's verdict
  still agrees with the merchant (open a vendor and confirm the popup queues exactly the ringed
  items). A ring that changes state here is either a real fix or a real regression: settle it
  against `/im debug`'s `ShouldAutoSell` verbose line, not by eyeballing.
- Toggle `blockLockedPost` off and confirm posting a locked item no longer prompts; toggle it on
  and confirm it does.

**Reviewer fan-out prediction.** Performance seat for the insert/read inversion, plus one
correctness seat on the cache key.

---

#### Phase 13 — Factory additions (ADD ONLY)

**Task and purpose.** Add the shared surface Phases 14, 15 and 16 consume, in order that the
Dashboard and both popups stop hand-rolling widgets — without moving a bag-UI pixel.

> **FENCE — hard constraint in this phase.** `UI/Core.lua` is **ADD ONLY**. Do not change any of
> the twelve frozen signatures or their observable behavior (`CreatePanel`, `CreateHeader`,
> `MakeRounded`, `CreateGlyphButton`, `CreateRailRow`, `CreateScrollFrame`, `CreateCard`,
> `CreateButton`, `AttachRing`, `CreateSettingsContainer`, `CreateSlider`, `CreateCheckbox`) —
> **and that freeze covers the methods those factories hang on their returned objects**, listed
> under the fence in §1: `card:AddContent/AddCheckbox/AddText/GetContentHeight` (`UI/Core.lua:
> 1308-1398`, consumed at `UI/Panels/BagUI.lua:53,159,177` and rendered through
> `ResizeForSettings`), `container:AdvanceY/FinalizeHeight/GetYOffset`, `row:SetSelected/Refresh`,
> `ring:Show/Hide/SetColor`, and the `container.content`/`scrollFrame.content`/`container.scrollBar`
> fields. Do not touch `CreateScrollFrame`'s geometry — `UI/BagUI/Core.lua:126-134` numerically mirrors its
> private margins and `CalculateRequiredWidth:186-187` derives the bag window width from those
> copies, so changing `10`/`-18`/`-4`/`-22` costs or gains a bag column. **Add new `UI.layout` keys
> freely; never retune an existing value** — `bottomBarHeight`, `rowHeightSmall`,
> `elementSpacing`, `rowHeight` and `iconSize` are recomputed independently inside BagUI.

**Steps.**
1. **W6-14.** `sendAllBtn:SetText("Send All")` (`MailPopup.lua:228`) is a silent no-op —
   `UI:CreateButton` never calls `SetFontString` (`UI/Core.lua:526-530`), so `Button:SetText`
   writes to a fontstring that does not exist. Harmless at that one site (the label is already
   right from construction) but it is exactly the anti-pattern the project's own CLAUDE.md
   documents, sitting in shipped code. **Durable fix at the producer**: add
   `button.SetText = function(self, t) self.text:SetText(t) end` in the factory
   (`UI/Core.lua:530`). **Provably invisible to BagUI** — BagUI calls `UI:CreateButton` at exactly
   two sites and never calls `SetText`.
2. **W6-15.** `Disable()`/`Enable()` on a factory button has no visual effect — the factory defines
   no disabled appearance, yet both popups call them (`AutoSellPopup.lua:154,158`;
   `MailPopup.lua:320,338,352`), so a dead **Sell All** looks identical to a live one. Fix in the
   factory: on disable also set
   `button.text:SetTextColor(unpack(UI.colors.textDisabled))` (the token exists at
   `UI/Core.lua:37`) and drop the backdrop; restore both on enable. **Provably invisible to BagUI**
   (never calls either).
**CHECKPOINT** — the only two non-additive `UI/Core.lua` edits in the whole plan are now in the
diff and nothing else is. Green state: `git diff UI/Core.lua` is **two behaviour changes inside
`CreateButton` and nothing more** — no touched signature, no touched `CreateScrollFrame` number, no
retuned `UI.layout` or `UI.colors` value; the custom bag opens with the same column count and
window width, and its two factory buttons (`BagUI/Core.lua:1319,1325`) look and behave exactly as
before. Catch a breach here, while the diff is two lines, rather than at the phase's exit.

3. **W4-6 (additions only).** Add `UI:CreateSearchBox` — a plain text-input factory, the one
   genuine gap (`CreateNumberInput`/`CreateCurrencyInput` exist, a plain text input does not). The
   Dashboard's two search boxes (`:418-485`, `:799-858`) are a 60-line copy-paste **including the
   debounce**; the factory owns the debounce. Add `UI:CreateHairline` (also B6's producer, so B6
   becomes a two-line call once approved). **No dropdown factory is needed** —
   `UI:CreateDropdown`/`UI:ShowDropdownMenu` already exist at `UI/Core.lua:893,942`.
4. **W4-7.** Add `UI:CreateItemRow` as a **`Button`** with `SetHyperlinksEnabled(true)`,
   `OnHyperlinkEnter` → `GameTooltip:SetHyperlink`, `OnHyperlinkClick` → `SetItemRef` (which gives
   shift-linking and the dressing room for free), and an icon `OnEnter` → `SetItemByID`. Today
   `SetHyperlinksEnabled`, `OnHyperlinkEnter` and `OnHyperlinkClick` appear **zero times in the
   entire addon**, while rows render quality-coloured `[Item Name]` links — the universal hover
   affordance — and deliver nothing; the 24×24 icon at `Dashboard.lua:1281-1289` sits on a plain
   Frame and is not hoverable either.
5. **W6-16.** Add a shared `UI:AcquireItemRow`/`UI:ReleaseItemRows` **keyed by parent**, next to
   `CreateItemListRow` (`UI/Core.lua:1482`), that **hides rather than reparents**. Both popups
   currently destroy and rebuild every row per refresh (`MailPopup.lua:124-127,152-217`;
   `AutoSellPopup.lua:178-181,192-229`) via `child:Hide(); child:SetParent(nil)` then
   `CreateFrame` — against the project's own pooling mandate. In the mail popup this runs on a
   0.3s-debounced `BAG_UPDATE` (`:263-272`), and **`BAG_UPDATE` fires per mail looted**, so
   auto-looting 40 mails churns hundreds of frames WoW never reclaims.
   `UI/Panels/History.lua:116-119` repeats the pattern. Conversion of all three call sites happens
   in Phases 16 and 18; the pool lands here.
6. **W6-18.** Add a `contentTopOffset` `UI.layout` key. `AutoSellPopup.lua:77,83` currently use
   `UI.layout.buttonWidth` (80) as a **Y offset**, and `MailPopup.lua:223` computes
   `totalHeight = UI.layout.buttonWidth + ...` with the height clamp at `:224` inheriting the
   coupling — it works today by coincidence and silently shifts both item lists the day button
   widths are tuned. **The fence permits new keys**; the popups switch to it in Phase 16.
7. **W4-8.** Money formatting: `IM:FormatMoney` (`Core.lua:277-294`) hardcodes `|cffffd700`, not
   the palette's `money` token `#F0B23A` (`UI/Core.lua:52`) — and because the returned string
   carries its own colour codes, **every surrounding `SetTextColor` on a FontString holding its
   output is a no-op**: six of them, `:292,303,348,1456` on `UI.colors.money`, `:320` on
   `UI.colors.success` and `:331` on `UI.colors.textDim` (`Dashboard.lua`). It also always appends
   silver and copper (the headline reads `4,312,908g 44s 12c`) and returns `"0c"` for zero.
   **`IM:FormatMoney`'s observable output is FROZEN — it is rendered inside the bag window.**
   `UI/BagUI/Core.lua:717` does `_bagFrame.footer.goldText:SetText(IM:FormatMoney(money))`, so
   recolouring the gold segment, suppressing silver/copper, or changing the `"0c"` case **repaints
   the owner-tuned bag footer**. Requirement 9 reads on what the bag window renders, not on which
   file the code lives in, so `Core.lua` buys no exemption.
   **Decision: keep `IM:FormatMoney` byte-identical (signature AND output) and put all of W4-8's
   new formatting in the two ADDED helpers.** Reason for this branch rather than a tenth Phase 17A
   approval gate: the gate would spend the owner's attention asking permission for a footer colour
   change nobody requested, while the finding's real consumer is the Dashboard — which needs new
   helpers anyway. Freezing the old formatter costs nothing.
   So: **add** `IM:FormatMoneyIcon` using `GetCoinTextureString` for the five headline rows
   (`Dashboard.lua:1409-1413`); **add** `IM:FormatMoneyShort` (`4.31M` / `312.4k`) for the
   per-character column (`:1455,1463-1465`). Both emit **no `|cff` codes of their own** so the
   caller's `SetTextColor`/`UI:ColorText` is the colour authority — that is what makes all six dead
   `SetTextColor` calls fixable instead of merely deletable, and it is why `:320`'s `success` and
   `:331`'s `textDim` can keep the colours they mean. The gold-only / no-`"0c"` behaviour and the
   `money` token live in `FormatMoneyShort`. Dashboard consumption (routing the rows through the new
   helpers and repairing the six dead `SetTextColor` calls) is Phase 14 step 13.

**Indirection audit — every symbol this movement touches whose output reaches the bag window.**
Run this list before any edit in Phases 13, 14, 15 or 16; a symbol on it is fenced by requirement 9
wherever it lives.
   - `IM:FormatMoney` → bag footer, `UI/BagUI/Core.lua:717`. **Frozen**, per step 7 above.
   - **`IM:FormatNumber` (`Core.lua:267`) → the same bag footer, transitively**: `FormatMoney`
     builds its gold segment from it at `Core.lua:286`. No phase touches it, and it is listed
     precisely because `IM:FormatMoneyShort`'s implementer is the one person tempted to put the
     `k`/`M` abbreviation logic *inside* `FormatNumber` — which would repaint the footer. **Frozen.
     `FormatMoneyShort` gets its own arithmetic and calls `FormatNumber` only for the unabbreviated
     case, or not at all.**
   - `UI.colors` (the table, not the factory) → read at 20+ BagUI sites, including the footer's
     `goldText:SetTextColor(unpack(UI.colors.money))` (`BagUI/Core.lua:489`), `:263,277,299-309,
     389,395,403,410,481,516-535,755,767`, `ItemButton.lua:201,390`,
     `CategoryView.lua:68,811,819,827`. **No phase retunes a `UI.colors` value.** Phase 13 step 2
     only *reads* `textDisabled`; any palette change is gate G4.
   - `OverlayFactory`'s `COLORS` and `UI:AttachRing` → painted onto bag item buttons
     (`BagUI/ItemButton.lua:181,196`). Untouched here; owned by gate G4.
   - Existing `UI.layout` values → recomputed independently inside BagUI. Add-only, already stated.
   - `Filters:ShouldAutoSell` (changed in **Phase 1** *and* **Phase 12**) → `OverlayFactory:Update`
     calls it per bag item (`UI/OverlayFactory.lua:437`), so it decides **which items wear a
     will-be-sold ring inside the bag window**. Two phases move it, and both are **consequence,
     not a rendering edit** — which is why neither is gated:
     - **Phase 1** wires the quality floor in `Filters.lua`. You cannot fix the filter without
       moving the ring, so the ring change is unavoidable downstream fallout of an asset-safety
       fix. (The *deliberate* edit to the ring predicate — deleting `OverlayFactory`'s duplicated
       `isJunk` term at `UI/OverlayFactory.lua:462` — is **not** in Phase 1. It is gate **G9** in
       Phase 17A, because nothing upstream forces it.)
     - **Phase 12 step 2** re-keys `_GetCachedItemInfo` from `itemLink or itemID`
       (`Filters.lua:515`) to `itemID`. For suffix-varying items that changes the info
       `ShouldAutoSell` reads — quality, `sellPrice`, `bindType` — and therefore which items wear
       the ring. Phase 12 is in Movement III, so §3.4's "walk this list before any Movement IV
       phase completes" would not have caught it; the check is written into Phase 12's own exit
       criteria.
     Both are changes in the *truth* the bag renders, not in how it renders it, so both are bug
     fixes rather than approval gates — but both are visible consequences, and each phase's smoke
     check names its own rather than letting the owner discover it.
   - `IM.ITEM_CLASS_NAMES` → read-only invariant; see Phase 16's W6-12 and Phase 17 step 13b.
   - `UI:CreateSearchBox`, `CreateHairline`, `CreateItemRow`, `AcquireItemRow`/`ReleaseItemRows`,
     `contentTopOffset`, `CreateQueuePopup`, `FormatMoneyIcon`, `FormatMoneyShort` → **new symbols,
     zero BagUI consumers.** Safe by construction.

**Exit criteria (in-game smoke checklist).**
- **Fence check first**: open the custom bag before and after this phase and confirm the **same
  number of columns** and the same window width; `git diff UI/Core.lua` shows **only additions**
  plus the two provably-invisible `CreateButton` behaviour changes (`SetText`, disabled
  appearance), and no edit to `CreateScrollFrame`'s numbers or to any existing `UI.layout` value.
- **Fence check, indirect half**: `git diff Core.lua` shows **zero change to `IM:FormatMoney`'s
  body**, and the bag footer's gold line at **`UI/BagUI/Core.lua:717`** renders the same string as
  before this phase (same colour, same `g/s/c` segments, same zero case — screenshot the footer
  before and after). Then walk the indirection audit list above and confirm no other listed symbol
  changed observable output. `git diff UI/Core.lua Core.lua` must show no retuned `UI.colors` value.
- A button created by the factory responds to `:SetText("x")` by changing its visible label.
- A disabled factory button is visibly disabled (dim text, no backdrop) and a re-enabled one is
  visibly restored — checked on the mail popup's Send All and the vendor popup's Sell All.
- A `UI:CreateItemRow` instance hovers to a real item tooltip, shift-click inserts the link into
  chat, and ctrl-click opens the dressing room for a wearable.
- `UI:CreateSearchBox` debounces (type quickly and confirm one refresh, not one per keystroke).
- `IM:FormatMoneyIcon` on a multi-million value renders coin textures; `IM:FormatMoneyShort`
  renders `4.31M` in the `money` token (colour applied by the caller, not embedded) and renders
  nothing resembling `"0c"` for zero. **`IM:FormatMoney` itself still prints
  `4,312,908g 44s 12c` and `"0c"`, unchanged** — that is the pass condition, not a defect.
- Every existing panel that uses the factory still renders (visit all nine settings tabs).

**Reviewer fan-out prediction.** UI-factory seat (fence compliance is the whole risk here) and one
accessibility seat on the disabled-state contrast.

---

#### Phase 14 — Dashboard correctness

**Task and purpose.** Make every Dashboard total describe the same set as the rows beneath it, and
stop leaking frames in two of three refresh paths, in order that the headline numbers become
trustworthy and searching stops silently deleting whole classes of row.

> **FENCE**: this phase consumes `UI/Core.lua` but must not modify it. Anything missing is an
> addition made in Phase 13, not an edit here.

**Ancestor fix**: strip `filters.search` before both data calls, **filter once client-side over
the full field set**, and compute income and expense from that same post-filter array.
**Symptoms that die with it: W4-1, W4-2.**

**Steps.**
1. **W4-1.** The ledger summary describes a different set than the rows: `filters.search` goes into
   **both** `IM:GetLedgerStats(filters)` (`Dashboard.lua:1530`) and
   `Ledger:GetFormattedEntries(filters)` (`:1532`), both routing through `IM:GetTransactions` where
   the test is `if filters.search and include and entry.link` (`Database.lua:725`) — **so every
   gold-only entry with no `entry.link` passes search unconditionally** and lands in the totals.
   Then `Dashboard.lua:1534-1555` **re-filters** the formatted array over a wider field set. Search
   "repair" → 4 rows shown, totals spanning the whole retention window.
2. **W4-1 (the fix).** Strip `filters.search` before both data calls; filter **once**, client-side,
   over the full field set; compute income and expense from that same post-filter array, skipping
   `TRANSFER_TYPES` to match `Database.lua:750-753`. **Also fix the producer** to search
   `entry.link or entry.src or ""` so it is not wrong for any future caller. Three callers of
   `GetTransactions` are affected and enumerated: `Database.lua:757` (`GetLedgerStats`),
   `Ledger.lua:168`, `Ledger.lua:180` — check each still behaves.
3. **W4-2.** Searching a character name deletes every item transaction — item-bearing rows are
   dropped by the DB gate before the client filter at `:1544` can test `entry.charName`; same for
   `entry.typeLabel` at `:1546`. Dies with item 2; verify rather than patch.
4. **W4-3.** `entry.itemName` (`Dashboard.lua:1543`) is **never set** by `Ledger:FormatEntry`
   (`Ledger.lua:130-164`) — always `""`. **Decision: populate it** (the name is already derivable
   from the link) rather than drop the search term, because searching by item name is what a user
   will try first.
5. **W4-4.** Ledger rows are never class-coloured: `:1625` reads `entry.charClass`, which
   `FormatEntry` never sets, so every row falls to the grey fallback — while Net Worth (`:1451`)
   and Inventory (`:1311-1315`) **do** colour the same characters. Fix in `Ledger.lua:158-161`:
   `formatted.charClass = (IM.db.global.characters[entry.char] or {}).class`, exactly the lookup
   `InventorySnapshot:CreateSearchResult` already does at `:479-482`.

**CHECKPOINT** — search "repair" and confirm the summary totals match the visible rows; search a
character name and confirm item rows survive; ledger rows are class-coloured.

6. **W4-5.** Frame leak in 2 of 3 refresh paths: `_framePool.networth` (`Dashboard.lua:30`) and
   `.inventory` (`:32`) are declared and **never read**; `GetPooledFrame` is called at exactly one
   site (`:1591`, ledger). `RefreshNetWorth` creates raw frames at `:1435`, `RefreshInventory` at
   `:1097,1113,1208,1272,1326`, and **both orphan the previous set with `child:SetParent(nil)`
   (`:1422-1425,1032-1036`) — which is what makes the leak permanent.** The trigger is hot:
   `NetWorth.lua:47` (`PLAYER_MONEY`) and `:69` (`BAG_UPDATE_DELAYED`) → `QueueUIRefresh` →
   `Core.lua:698` → `RefreshContent`. Fix: `GetPooledFrame` + `ReleaseAllFrames` mirroring
   `RefreshLedger:1581-1619` (create FontStrings only when `not row.topLine`), and **delete the
   `SetParent(nil)` loops**. Note: the project's own CLAUDE.md claims pooling is implemented — it
   is, in one of three paths (the doc fix is W7-5, Phase 18).
7. **W4-11 — the character half already landed in Phase 11; this step owns the REST.** The ledger
   character filter was persisted as an **index** (`:607`) into an alphabetically-sorted list
   re-derived at `:618-630`; a newly-transacting character shifts every index by one, so after a
   reload the filter **shows a name and the rows belong to someone else**.
   **`ledgerCharFilter` → `ledgerCharKey`, including its reader at `Dashboard.lua:411,584,607,
   618-630`, is Phase 11 step 13 member 5 and is already done when this phase starts.** It was
   pulled into the atomic commit because leaving the reader four phases behind its writer made
   `:622` do arithmetic on a string key and abort the whole Ledger tab. **Do not re-do it, and do
   not "improve" the field back to an index.** Verify it instead: `/reload` with a character filter
   set and confirm the filter names the right character and the rows are that character's.
   **What this step still owns**: `typeIndex` (`:521`) and `dateIndex` (`:554`), which share the
   same flaw latently — persist **identities** (`preset.label` for the date preset, a stable type
   token for the type filter) and keep the index as runtime state only. These two are safe to land
   here because neither is a character key: nothing in the migration rewrites their values, so
   reader and writer can move together in this phase with no window.
8. **W4-12.** Inventory filter state is discarded on reload while the ledger persists four keys,
   and neither `_inventoryPaginationLimit` (`:764`) nor `_paginationLimit` (`:24`) is reset on
   `Dashboard:Show` (`:1741`) or on tab switch (`:201-215`) — so reopening after "Show More"
   re-renders up to 300 rows as the first paint. Fix: persist the inventory filters the same way
   the ledger's are, and reset both pagination limits on show and on tab switch.
   **This step CREATES a new persisted character key, so it inherits Phase 11's standing rule.**
   `_inventoryFilters.charKey` holds a character key, and persisting it adds a character-keyed
   field to the schema that did not exist when Phase 11's migration ran. Two obligations follow:
   name it `dashboard.inventoryCharKey` and store the **producer's** output
   (`IM:GetCharacterKey`-normalized), never a raw `GetRealmName()` build; and treat a stored key
   that no longer exists in `characters` as "All Characters" rather than erroring or showing an
   empty list — the character may have been deleted by Phase 11 step 14's per-row delete. **Any
   future migration that renames character keys must carry this field**, which is exactly what
   Phase 18 step 9's standing instruction exists to make survive this plan.

**CHECKPOINT** — `/reload` with a character filter and an inventory filter set: both restore
correctly, and the first paint after "Show More" is one page, not 300 rows.

9. **W4-6 (consumption).** Migrate the Dashboard's 5 raw `UIDropDownMenuTemplate` frames
   (`:503,536,569,877,936`) onto the existing `UI:CreateDropdown`/`ShowDropdownMenu`; replace the 2
   raw `EditBox` (`:430,811`) with Phase 13's `UI:CreateSearchBox`; replace **all 22 hardcoded hex
   `|cff…` literals** — 17 of them `|cff8c8c9b` at
   `:753,790,1018,1106,1173,1181,1233,1245,1342,1352,1356,1448,1464,1473,1697,1708,1712`, plus
   `:183,185,186,693,1298` — with `UI:ColorText`/`UI.hexColors`. **This is why the palette rework
   could not reach the Dashboard — it does not read tokens.**
   **Scope, because "all `|cff`" is not the same set**: the file also holds three dynamic
   class-colour constructions (`string.format("|cff%02x%02x%02x…")` at `:1156,1311,1626`) and three
   already-token-sourced strings (`:1463,1562,1657`). **Those six lines stay.** A blanket
   `|cff`-elimination would delete working class colouring; the target is literal hex values only.
10. **W4-7 (consumption).** Route `RefreshInventory` (`:1292-1300`) and `RefreshLedger`
    (`:1610-1652`) through Phase 13's `UI:CreateItemRow` so every item link becomes hoverable and
    shift-linkable.
11. **W4-9.** Long names wrap into rows too short for two lines — `:1292-1294` (a 48px row that
    also holds a location line) and `:1610-1614` (32px). FontStrings word-wrap by default, so text
    collides or clips mid-glyph with no ellipsis. `SetWordWrap(false)` + `SetMaxLines(1)`; the
    tooltip from W4-7 carries the full name.
12. **W4-10.** Search boxes are `SetSize(320, 20)` (`:431,812`) in a 420px-default frame (`:91`)
    with 8px insets (`:225-226`) ≈ 404 usable — **clipped out of the box** — and `OnSizeChanged`
    (`:132-159`) resizes only the three scroll children, never the inputs. Anchor `RIGHT` with an
    inset instead of `SetSize` and it tracks every resize for free. Phase 0 item 5 settles whether
    the third filter dropdown also overflows at the 350px minimum (`:101`); if it does, anchor it
    the same way.
13. **W4-8 (consumption).** Phase 13 step 7 only *added* `IM:FormatMoneyIcon` and
    `IM:FormatMoneyShort` (and deliberately froze `IM:FormatMoney`, which the bag footer renders).
    Route the consumers here, or the finding is half-closed: the five headline rows
    (`Dashboard.lua:1409-1413`) through `IM:FormatMoneyIcon`; the per-character column
    (`:1455,1463-1465`) through `IM:FormatMoneyShort`.
    **And repair the dead `SetTextColor` calls — six of them, not five, and only four carry the
    `money` token.** The defect is not the token; it is that `IM:FormatMoney`'s return string
    carries its own `|cff` codes, so **any** `SetTextColor` on a FontString whose text is
    money-formatter output is a no-op. The real list, verified against the file:
    - `:292` (`charGoldValue`), `:303` (`warbandValue`), `:348` (`totalValue`), `:1456`
      (`totalLabel`) — `unpack(UI.colors.money)`. Four, not five.
    - **`:320` (`liquidValue`) is `unpack(UI.colors.success)`**, not `money` — dead for the same
      reason (its text is `IM:FormatMoney(liquidGold)` at `:1411`). Keep it green; make it
      *actually* green.
    - **`:331` (`invValue`) is `unpack(UI.colors.textDim)`** — the sixth dead one, missed by a
      `money`-shaped grep. Its text is `"+ " .. IM:FormatMoney(...)` at `:1412`, a row this step
      routes through `FormatMoneyIcon`.
    Each becomes a real colour application on the new helpers' uncoloured output (`UI:ColorText`,
    or a `SetTextColor` that now takes effect), preserving the colour each row means today —
    `money` for the four, `success` for `:320`, `textDim` for `:331`. A dead `SetTextColor` left in
    place is the no-op that made this finding hard to see in the first place. **Anything the Net
    Worth summary rows still render as raw `IM:FormatMoney` stays as-is** — it is correct, just
    verbose, and Phase 15's W5-5 decides what the dominant figure is.

**Exit criteria (in-game smoke checklist).**
- **Ledger search "repair": the summary totals match the sum of the visible rows exactly.** Repeat
  with a character name (item rows must survive) and with an item name.
- Ledger rows are class-coloured, matching the colours the Net Worth and Inventory tabs already use
  for the same characters.
- Switch tabs and trigger `PLAYER_MONEY` and `BAG_UPDATE_DELAYED` twenty times (sell and loot):
  memory does not climb monotonically and the tabs stay responsive; no orphaned frames (spot check
  by confirming `ReleaseAllFrames` is reached on all three paths with `/im debug`).
- `/reload` with a character filter set: the filter still names the same character **and** the rows
  belong to that character. Add a new transacting character whose name sorts first, `/reload`, and
  confirm the filter did not shift.
- `/reload` with inventory filters set: they persist; the first paint is one page.
- Resize the Dashboard from 350px to wide: both search boxes and all filter dropdowns stay inside
  the frame at every width.
- Long item and character names show one clipped line, not a collision.
- Every item link hovers to a tooltip and shift-links into chat.
- **No *hardcoded hex* `|cff` literal remains in `Dashboard.lua`.** Stated that way deliberately:
  the blanket "no `|cff`" version of this criterion is unachievable and would have failed a correct
  implementation. Three occurrences are **legitimate dynamic class-colour constructions and must
  survive** — `string.format("|cff%02x%02x%02x…")` at `:1156`, `:1311` and `:1626` — and three are
  already token-sourced and also survive: `:1463`, `:1562`, `:1657` (all `"|cff" ..
  UI.hexColors.<token>`). What must be gone is every literal hex value, the seventeen `|cff8c8c9b`
  greys and the `|cffff6666`/`|cffff0000`/`|cffcc66ff`/`|cffffffff` one-offs included, replaced by
  `UI:ColorText`/`UI.hexColors`.
- **No `SetTextColor` remains on a FontString whose text is money-formatter output.** Not a grep
  for `SetTextColor(unpack(UI.colors.money))` — that pattern misses `:320` (`success`) and `:331`
  (`textDim`), both equally dead, so a money-shaped grep passes with two no-ops still in the file.
  The check is: for each of `charGoldValue`, `warbandValue`, `liquidValue`, `invValue`,
  `totalValue` and the per-row `totalLabel`, the colour visible on screen is the colour the code
  asks for. Verify by eye at the Dashboard, one row at a time — `liquidValue` green, `invValue`
  dim, the other four in `money`.
- The five headline rows render coin textures and the per-character column reads `4.31M`-style
  short money, both in the `money` token — while the bag footer's gold line is untouched.

**Reviewer fan-out prediction.** Correctness seat on the filter-once change (three affected
`GetTransactions` callers), performance seat on the pooling conversion, and a UI seat on the
dropdown/token migration.

---

#### Phase 15 — Dashboard rendering: the data already computed and thrown away

**Task and purpose.** Render the timestamps, category totals, item totals and exports the addon
already computes and discards, in order that the user can tell fresh data from six-month-old data
and answer "where did my gold go this week" without thirteen dropdown selections.

Runs after Phase 14 (it reuses the same post-filter array) and after Phase 13 (it consumes
`CreateItemRow` and `CreateHairline`).

> **FENCE**: consumes `UI/Core.lua`, does not modify it.

**Steps.**
1. **W5-1 — the highest trust-per-line-of-code item in the plan, and the honest answer to
   requirement 5.** Nothing renders any timestamp: `charData.lastSeen` (`Database.lua:570,604`) is
   carried into `charInfo` (`NetWorth.lua:358`) and consumed by nothing; `lastInventoryUpdate`
   (`NetWorth.lua:262`), `snapshot.timestamp` (`InventorySnapshot.lua:271`), `bankTimestamp`
   (`:307`) and `reagentBankTimestamp` (`:329`) have **zero display consumers**; the Inventory
   summary even stores `timestamp` per entry (`Dashboard.lua:1068,1082`) and only sorts by count.
   Only warband **gold** gets an "as of" line, and only in the settings panel
   (`UI/Panels/Dashboard.lua:42-46`) — the one place a user will not look. **An alt not logged in
   for six months contributes its gold to the headline total with the same visual authority as live
   data.** Fix: an age column on Net Worth character rows (`:1459-1465`), per-source age on
   Inventory summary rows (before the `>` arrow at `:1171-1173`), in browse-mode header
   (`:1243-1245`) and in the character dropdown (`:917`), and a stale suffix on the Warband Bank row
   (`:301-304`). Escalate `textDim` → `warning` past 7 days → `error` past 30. **Per R12, the age
   is always a word or number ("12d"), never colour alone.**
2. **W5-5.** "Total Net Worth" mixes gold with a partial proxy: `inventoryValue` is vendor sell
   price only (`NetWorth.lua:161`), is `0` for any character never logged in with the addon, and
   includes bank contents only if a bank happened to be open — and the character sort **ranks on
   this hybrid** (`:365`), so a freshly-scanned alt outranks a richer un-scanned one. Fix: rank by
   `gold` (comparable across all characters), keep net worth as a secondary column, rename the row
   at `:324-332` to `Inventory (vendor value)`, make **Liquid Gold** (`:313-321`) the visually
   dominant figure, and replace the vague "Inventory requires vendor price data (login to each
   character)" hint (`:352-354`) with a live `Inventory value missing for 4 of 9 characters`.
3. **W5-3.** No share-of-total (`:1432-1468`) — nine rows of large numbers, and working out that
   the banker holds 78% is manual division per row. Fix: a `money`-token texture at ~0.18 alpha
   behind each pooled row, width-scaled to `charInfo.netWorth / breakdown.total.netWorth`, plus a
   right-aligned `12.4%` in `textDim`. Turns the list into a distribution chart at zero interaction
   cost.
4. **W5-4.** Character rows are dead ends — plain `Frame`s (`:1435`), no `OnEnter`/`OnClick`, and
   the sort order is hardcoded `netWorth` descending **inside the module**
   (`NetWorth.lua:365-367`) so the UI cannot offer one; contrast the Inventory summary rows
   (`:1113-1149`), which are proper Buttons. Fix: make them Buttons (free, given Phase 14's
   pooling), `OnClick` → set `_ledgerFilters.charKey` + `frame.SelectTab("ledger")`, right-click →
   Inventory tab; add a clickable column-header row above `:357-366` toggling a view-level
   `_networthSort`.
5. **W5-14.** Carry the `(Click character to browse)` hint pattern (`:1106`) to every row made
   clickable by item 4. **Discoverability is otherwise genuinely fine** — `/im dashboard` + `/im d`
   (`Core.lua:394-404`), four minimap paths (`MinimapButton.lua:84,235,307,324`), three settings
   deep-links (`UI/Panels/Dashboard.lua:73-110`, correctly targeting the `"Tracking"` tab present
   at `UI/Config.lua:22`), a login advertisement (`Core.lua:361`), word-labelled tabs (`:189-193`),
   ESC closes (`:162`). **Do not "fix" it.**

**CHECKPOINT** — Net Worth: every row shows an age, a percentage and a share bar; the list ranks by
gold; clicking a character jumps to its ledger; the missing-inventory hint names a real count.

6. **W5-2.** No trend — "am I richer than last week" is unanswerable, because no gold history is
   stored (`goldHistory` appears nowhere; `characters[charKey]` holds only current `gold`). Fix
   **without a new table**: a delta line under Total Net Worth (`:346-349`) from
   `IM:GetLedgerStats({minDate = time()-7*86400}).netGold`, rendered `↑ +142,000g` in `success` and
   `↓` in `error`, **labelled "gold flow, 7 days" and not "net worth change"**, because that is what
   it honestly is. For a true curve later, append `{ts, netWorth}` to a capped ring buffer in
   `NetWorth:OnPlayerLogout` (`:136`) — one entry per logout — and draw a sparkline; that half is
   deferral **D2** in Appendix B, with all four fields.
7. **W5-6 — this is what turns the tab from a log into a ledger.** The Ledger is a flat tape with
   no grouping or category totals (`:1587-1664`, 10 rows at a time, `:24`), despite
   `IM:GetLedgerStats` **already** returning `stats.counts[type]` (`Database.lua:772`) and
   `Ledger:GetTypePresets` (`:258-274`) **already** grouping all 40 types into 13 semantic buckets.
   "Where did my gold go this week" currently takes 13 dropdown selections plus hand arithmetic.
   Fix: a collapsible "By category" block between the summary box (`:635`) and the Transactions
   header (`:712`), computed from **the same post-filter array as W4-1**;
   `UI:CreateRailRow`-style lines with the label left and net right in `success`/`error`, plus a 2px
   `money`-token bar scaled to `|net| / maxAbsNet`; each row click-through to that type filter.
8. **W5-7.** The default date filter is "All Time" (`:18,410` → `dateIndex = 5`,
   `Ledger.lua:253`) — the least useful option and the most expensive first paint. Make it `3`
   (Last 7 Days), which also makes the summary box a de-facto weekly report and pairs with item 6.
9. **W5-8.** `Ledger:ExportToString` (`:179-222`) is filter-aware, strips colour codes, has a
   header row — and **zero callers** — while the sell-history equivalent **is** wired to a button
   (`UI/Panels/History.lua:230`). Fix: an Export button in the bottom bar (`:239-257`) passing the
   **current** filter object built at `:1496-1524`, with the result in a `UI:CreatePanel` holding a
   read-only multiline EditBox plus `HighlightText()`, following the History pattern.
10. **W5-9.** `Ledger:GetSummaryString` (`:225`) and `NetWorth:GetSummaryString`
    (`NetWorth.lua:385`) have zero callers. **Decision: delete both.** Reason: the summary box
    (item 6's neighbour) and the export (item 9) cover every consumer either could have had, and a
    string-formatting function with no caller is the dead code the no-duct-tape rule says to delete
    — git is the archive. Do not leave them.

**CHECKPOINT** — Ledger: default view is Last 7 Days, the category block totals reconcile against
the row list, Export produces a copyable filtered dump.

11. **W5-10 — this is what makes the Inventory tab worth opening.** It answers "which alt" but not
    "how much total": one row per **stack**, sorted alphabetically
    (`InventorySnapshot.lua:435-439`), 15 at a time — so "Ore" returns 30 near-identical rows and
    the total needs hand-addition across pages. **`GetTotalItemCount`
    (`InventorySnapshot.lua:575-593`) already sums an item across every character AND the warband
    bank, and has zero callers.** Fix: group by `itemID` after `:1199` — one parent row per item
    with icon, link and a right-aligned `N total` in `money`; per-character and per-location stacks
    as indented 20px sub-lines using the class colours already applied at `:1311-1315`; groups
    sorted by total descending; plus an `N items across M characters` count.
12. **W5-12.** "items" counts stacks, not items: `:1054-1056` sums `#snapshot.bags` (occupied
    slots) and labels it `N items` (`:1168`); `:1089` does the same into `(N total items)`, and the
    summary **sorts by this figure** (`:1087`). 200 slots of single arrows reads "200 items"; 40
    stacks of 200 ore (8,000 items) reads "40". Fix: sum `item.quantity` and show
    `N stacks · M items` — both are useful, keep both, and sort by the item count.
13. **W5-11.** The Location filter is **silently ignored in the default view**: `showSummary` is
    true whenever search is empty and `charIndex == 1` (`:1042`), and the summary branch returns at
    `:1186` without ever consulting `_inventoryFilters.location`. The dropdown accepts input,
    relabels itself, and changes nothing — **worse than being disabled, because the user concludes
    the DATA is wrong.** Fix: use it to choose which counts to sum (`:1054-1056` already breaks out
    `bags`/`bank`/`reagentBank` separately, so it is nearly a one-line change) and reflect it in the
    header. (The `Disable()`-while-summary alternative is rejected: the filter is genuinely
    meaningful over the summary.)
14. **W5-13.** The Tips card claims "Ledger tracks gold only, not item transfers (yet)"
    (`UI/Panels/Dashboard.lua:340`) — **false**: `Ledger.lua:34-35,54-57,64-65` define eight
    item-transfer types and the "Bank" preset filters them (`:271`). Correct the text.

**Exit criteria (in-game smoke checklist).**
- Every Net Worth character row shows an age in days and a share percentage; an alt not seen for
  40 days renders its age in the `error` token **and** as text ("40d"); the Warband Bank row carries
  a stale suffix when appropriate.
- The Net Worth list ranks by gold; the missing-inventory hint reads a real
  `Inventory value missing for N of M characters`.
- Clicking a character row lands on the Ledger tab filtered to that character; right-click lands on
  Inventory; the column header toggles the sort.
- The 7-day delta line under Total Net Worth matches `IM:GetLedgerStats` for the same window and is
  labelled "gold flow, 7 days".
- Ledger opens on Last 7 Days; the "By category" block's per-bucket nets **sum to the summary
  box's net**; clicking a bucket filters the rows to that type.
- Export writes a filtered, colour-code-free dump that can be selected and copied.
- Inventory search "Ore": one parent row per item with a correct `N total`, sub-lines per
  character/location in class colour, groups sorted by total descending, plus
  `N items across M characters`.
- Inventory summary shows `N stacks · M items` with the item count matching a hand count for one
  known character.
- Changing the Location filter in the **default** view visibly changes the numbers and the header.
- The Tips card no longer claims item transfers are untracked.
- `grep` proves `GetSummaryString` is gone from both modules with no dangling callers.

**Reviewer fan-out prediction.** UX seat (this is the phase with the most judgment per line),
accessibility seat (colour-plus-glyph for staleness and income/expense), and a correctness seat on
the category block reconciling against the summary.

---

#### Phase 16 — Mail and vendor popup convergence

**Task and purpose.** Make both popups say why an item is in the list, let the user opt an item
out, report progress and failures, and share one implementation, in order that the moment before
gold and items move is the moment the user actually has information.

Runs after Phase 13 (consumes `SetText`, the disabled state, the row pool, `contentTopOffset`,
`CreateItemRow`) and after Phase 2 (the mail state machine). Phase 1's consent popup is a
prerequisite for W6-6's progress work being meaningful.

> **FENCE**: consumes `UI/Core.lua`, does not modify it. The shared `UI:CreateQueuePopup` in the
> final step is an **addition**.

**Steps.**
1. **W6-1 — the cheapest high-value fix in the plan.** The vendor popup never says **why** an item
   qualified, though `Filters:GetAutoSellItems` returns `reason` per item (`Filters.lua:719`) from
   12 labelled exit points (`:498-642`) and `AutoSellPopup:RefreshItems` (`:192-229`) drops it. The
   only "why" is one bottom line, `"Selling: Uncommon and below"` (`:165`), which is **wrong for
   junk-list items** — they override the quality gate entirely (`Filters.lua:553-562`). Fix: shift
   `itemLabel`'s right anchor from `-60` to `-140` (`:212`) and insert a reason column,
   `UI:ColorText(item.reason, ...)`, with junk-list rows in the amber `warning` token **precisely
   because they bypassed protections**; replace the single filter line with
   `"6 by quality · 2 on junk list"`.
2. **W6-2.** The sell list is capped at 8 inside a scroll frame that therefore never scrolls —
   `maxItems = 8` then `"... and X more"` (`:187,232-237`), with content height set from the
   **capped** list (`:252`), so items 9..n are unviewable and the scrollbar is inert. There is no
   per-item opt-out and no right-click-to-protect. Contrast the mail popup, which renders every
   queued item with no cap (`MailPopup.lua:186`). Fix: remove the cap; make each row a Button with
   the tooltip/hyperlink treatment from W4-7; `OnClick` → `IM:ToggleWhitelist(item.itemID)`; plus a
   red `UI:CreateGlyphButton(row, "X", UI.colors.error)` that whitelists and refreshes — **one
   click turns "about to be sold" into "protected forever"**, which is the action a user actually
   wants at that moment. Footer hint in the existing `bottomBar`.
3. **W6-3.** Buyback is the only undo and the UI never mentions it.
   `ItemLock._CheckAndBuybackLockedItems` (`:134-168`) already scans `GetBuybackItemLink(1..12)`
   and repurchases — but **only for whitelisted items**, i.e. the case where selling should not
   have happened at all. For a normal mis-sale there is no undo and no text telling the player WoW
   will sell it back at cost before they leave. Fix: an "Undo last sale" `UI:CreateButton` in
   `bottomBar`, shown only when `GetNumBuybackItems() > 0` **and** the last run sold something
   (track itemIDs in `_sessionStats`), walking the buyback list. **Even without the button, change
   the `FinishSelling` (`:310-318`) chat line to name buyback — the wording alone is worth
   shipping.**
4. **W6-17.** Protections are invisible at the moment they matter: the overlay system is good
   (`OverlayFactory.lua:407-475`, priority-ordered) but it paints **item buttons**, and `ItemLock`
   refreshes them 0.2s after `MERCHANT_SHOW` (`:99-101`) — the exact tick `SellJunk` starts
   (`AutoSell.lua:71-74`). A player with closed bags (the normal case at a vendor) sees no
   protection state at all, and the popup carries no whitelist or junk marker. Fix: fold it into the
   popup — the reason column from item 1 plus a `UI:ColorText(n .. " protected", "success")` count
   in the summary, from the same bag scan.

**CHECKPOINT** — vendor popup: every qualifying item is listed and scrollable, each with a reason,
junk-list rows in amber, a protected count in the summary, an X that protects, and a
buyback-aware finish line.

5. **W6-6.** Zero progress feedback during a sale and no way to stop one:
   `AutoSellPopup:UpdateStatus(message)` (`:291-295`) has a body of
   `-- Could update a status label if needed` and is called from nowhere, while selling walks the
   queue at 0.15s per item (`AutoSell.lua:282`) — so 40 items is a six-second sale showing the
   unchanged pre-sale list. `AutoSell:CancelSelling()` (`:92-99`) is **fully implemented with no UI
   affordance** — a sale cannot be stopped except by closing the merchant. Fix: implement the stub
   against the shape the mail popup already proved (`MailPopup.lua:312-342`), and swap
   `sellBtn.text` to `"Stop"` while `_isSelling`, routed to `CancelSelling`.
6. **W6-7.** Merchant rejections are debug-only: `AutoSell.lua:289-302` marks `_rejectedItems`,
   backs the stats out and moves on (`:294`); same for "item moved" (`:218`) and "no longer passes
   filters" (`:245`). **An item no vendor will buy is indistinguishable from one that sold.** Fix:
   accumulate `_sessionStats.rejected`, append it to the `FinishSelling` line, and keep rejected
   rows visible and greyed in the reason column from item 1.
7. **W6-4.** Repair has a silent dead branch: with `useGuildFunds = true` and
   `fallbackToPersonal = false` (`Database.lua:37-40`), if the guild cannot pay, the guard at
   `AutoRepair.lua:84` is false, the function falls through to `return false` at `:102`, and
   **nothing prints** — gear stays broken with no explanation. Fix: an `else` at `:93` naming the
   cause, the guild balance, the repair cost and which setting to change.
8. **W6-5.** Repair is invisible in the popup: `AutoRepair:GetRepairCost()` (`:117-122`) exists
   with zero callers. Fix: when `CanMerchantRepair()`, show the cost under `totalValueLabel` with
   the funding source, and after a repair show the source actually used.

**CHECKPOINT** — a 40-item sale shows progress, can be stopped mid-run, reports rejections in the
finish line, and a guild-funds-exhausted repair prints a cause.

9. **W6-8.** Every mail failure is invisible: `OnMailFailed` (`MailHelper.lua:256-259`) is
   `_currentRecipient = nil` plus an `IM:Debug` line, which prints nothing unless `/im debug` is
   on — so a recipient typo, a full mailbox, a mail throttle and "you can't mail that" all land in
   the same hole. **Rule creation accepts any string as a recipient**
   (`Panels/MailHelper.lua:399-400`) and appends the current realm with no validation, though
   `MailHelper:GetAlts()` (`:262-294`) holds every known character. Fix: `IM:PrintError` naming
   cause + next step + the rule name; surface it on the popup's status line; and warn at Add-Rule
   time when the recipient is not a known character.
10. **W6-9.** The 12-attachment cap is silent (`MailHelper.lua:594-621`): Send on a 30-item queue
    looks complete, `OnMailSendSuccess` wipes the whole queue (`:248`), and the popup refreshes off
    a fixed `C_Timer.After(1, ...)` (`MailPopup.lua:174-177`) that **races the async send** — if the
    send confirms slower than 1s the queue shows items already in the mail. Fix: report
    `"Sent 12 of 30"`, label the button `"Send 12/30"` via `sendBtn.text:SetText` (which now works,
    per W6-14), and chain on `MAIL_SEND_SUCCESS` rather than a timer. **Folds into Phase 2's state
    machine** — do not build a second one.
11. **W6-10.** Postage is never shown before committing — Send All across 4 alts silently spends
    1s 20c. Fix: a second summary line, `ceil(items/12)` mails × 30c. (The *logging* is W2-15,
    Phase 6.)
12. **W6-11.** No preview, no confirm, no per-item opt-out, and rows are not inspectable:
    `MailHelper:RemoveFromQueue` (`:548`), `ClearAltQueue` (`:558`), `ClearQueue` (`:566`) and
    `AddToQueue` (`:531`) are **called from nowhere in the tree**; item names are FontStrings on
    plain `Frame`s (`MailPopup.lua:187-210`) with no `EnableMouse` and no `SetHyperlinksEnabled`,
    so you cannot hover to see what an item is or shift-click it. **You are asked to approve a list
    you cannot inspect.** Fix: rows as Buttons with tooltip + `CHATLINK` handling, plus an X glyph
    wired to `RemoveFromQueue` — which also wires up the dead API.
13. **W6-12.** Rules cannot be tested and 4 of 5 filter types are unreachable: `AddRule` hardcodes
    `filterType = "classID"` (`Panels/MailHelper.lua:405`) and the validator rejects anything but
    `%d+`/`%d+_%d+` (`:395`), while `FILTER_TYPES` implements `quality`, `name`, `vendorPrice` and
    `soulbound` (`MailHelper.lua:35-146`). The user is told to type raw class integers and go hover
    items to find them (`:433-434`), with no "matches N items" preview, so a rule's blast radius is
    unknown until the mailbox opens. Fix: **(a)** a live match count in `RefreshRulesList`
    (`:290,352`) — free, because `AddRule` already triggers `AutoFillQueue` — plus a Preview button
    running the typed filter without saving; **(b)** replace the numeric EditBox with
    `UI:CreateDropdown` over `IM.ITEM_CLASS_NAMES` (`Filters.lua:86-103`) and a subclass dropdown
    via `GetItemSubClassInfo` (the row renderer already decodes these for display at `:329-344`),
    and **expose `soulbound`** (W1-5 depends on it existing in the UI).
    > **INVARIANT — `IM.ITEM_CLASS_NAMES` is READ-ONLY in this step.** It is a hand-synced ordering
    > key for the custom bag: `CategoryView.lua:601,625` reads it un-nil-guarded and
    > `GetCategoryOrder:647-659` keys on the **display string**, so renaming any value silently
    > re-labels **and** re-orders bag categories — a visible bag change, which requirement 9 puts
    > behind owner approval. Build the dropdown **over** the table: read it, add nothing to it,
    > rename nothing in it. If a label reads badly in the dropdown, map it in the dropdown.
    > (Also recorded in Phase 17 step 13b — restated here because this is the step that can break
    > it, and an executor reads only its own phase.)
14. **W6-13.** Mail Helper needs a `/reload` to turn on, with no hint: `OnEnable` returns early
    before any `RegisterEvent` when `mailHelper.enabled` is false (`MailHelper.lua:148-154`), and
    the checkbox flips the flag and calls `AutoFillQueue` but never registers `MAIL_SHOW` — so
    enabling it mid-session appears permanently broken. `OnMailShow` already re-checks `enabled` at
    `:196`, so **the guard at `:151` is redundant AND harmful**: delete the early return and move
    the queue restore below it.
15. **W6-19.** Scroll content width is snapshotted before layout (`MailPopup.lua:58-61`,
    `AutoSellPopup.lua:95-98`): `scrollContent:SetSize(scrollFrame:GetWidth(), 1)` runs at Create
    time while the popup is hidden and two-sided anchors have not resolved. Marked probable, settled
    by Phase 0 item 5. **The fix is free either way**: set the width at refresh time, when shown.
16. **W6-18 (consumption).** Switch `AutoSellPopup.lua:77,83` and `MailPopup.lua:223-224` from
    `UI.layout.buttonWidth` to the `contentTopOffset` key added in Phase 13.
17. **W6-16 (consumption).** Convert both popups' row rendering to Phase 13's
    `UI:AcquireItemRow`/`ReleaseItemRows` (hide, never reparent). `UI/Panels/History.lua:116-119`
    is converted in Phase 18 with the rest of that file's work — **if the file survives at all**;
    Phase 11 step 12 may have retired its History-store readers and repointed it onto the ledger,
    and Phase 18's death verdict decides whether the file remains.
18. **W6-20 — last, once both call sites have stopped moving.** The popups converged on paint, not
    interaction: both are 280px, `MakeRounded`, `DIALOG` strata, `CreateHeader`, draggable,
    `UISpecialFrames` — but they diverge on item cap, per-row value, progress contract, cancel
    affordance, auto-refresh, close-with-parent (`MailFrame:HookScript("OnHide")` vs
    `MERCHANT_CLOSED` only) and height strategy. Fix: **add** a shared
    `UI:CreateQueuePopup(name, title, opts)` owning the frame, header, scroll body, bottom bar,
    progress line and Stop wiring, leaving each file only a row renderer and an action handler.
    **This step must run after steps 1-17**, which is what makes W6-2/6/16/19 one fix each instead
    of two.

**Exit criteria (in-game smoke checklist).**
- Vendor popup with 20 qualifying items: **all 20 are listed and the scrollbar works**; each row
  shows a reason; junk-list rows are amber; the summary reads
  `"N by quality · M on junk list"` plus a protected count.
- Clicking a row's X protects that item and it disappears from the list; a `/reload` confirms the
  whitelist persisted.
- A 40-item sale shows progress ticking, the Sell button reads "Stop" and stopping it mid-run
  leaves the remaining items unsold; the finish line names buyback and reports rejected items.
- Sell an item no vendor will buy and confirm it is reported, not silently dropped.
- With `useGuildFunds` on, `fallbackToPersonal` off and an empty guild bank, a repair attempt
  **prints a cause** naming the balance, the cost and the setting.
- Repair cost and funding source are shown in the popup before repairing, and the source actually
  used is shown after.
- Mail to a typo'd recipient prints a cause on the status line **and** in chat; adding a rule for
  an unknown recipient warns at Add-Rule time.
- A 30-item queue: the button reads "Send 12/30", the result reads "Sent 12 of 30", the remaining
  18 are still queued after the popup refreshes (no timer race).
- Postage is shown before committing and matches `ceil(items/12) × 30c`.
- Mail popup rows hover to tooltips, shift-link, and the X removes exactly that item.
- A rule built from the class/subclass dropdowns shows a live match count; Preview does not save;
  the `soulbound` type is selectable and excludes soulbound items.
- Toggling the Mail Helper checkbox **works without a `/reload`** — open a mailbox immediately and
  the queue populates.
- Both popups: type/resize with a long item name and confirm no clipping; both use pooled rows
  (auto-loot 40 mails and confirm no unbounded frame growth).
- After the `UI:CreateQueuePopup` hoist, both popups behave identically on close-with-parent,
  progress and cancel; the custom bag is unaffected (fence check).
- **MANDATORY, because step 2 calls `IM:ToggleWhitelist` and this phase touches `ItemLock`:
  `Alt+Click` and `Ctrl+Alt+Click` still lock and junk an item inside the CUSTOM bag.** The
  coupling is silent — BagUI handles no lock/junk clicks itself (`ItemButton.lua:218-221`) and
  relies entirely on `ItemLock.lua:414`/`JunkList.lua:48` hooking
  `ContainerFrameItemButtonMixin.OnClick`; if that ever moves to Blizzard's named bag buttons,
  Alt+Click dies in the custom bag with no error.
- `git diff` proves **no value in `IM.ITEM_CLASS_NAMES` was renamed or added** by W6-12's dropdown
  work, and the custom bag's category labels and category order are unchanged.

**Reviewer fan-out prediction.** UX seat, a concurrency seat on the send chaining (shared with
Phase 2), and a DRY seat on the final hoist.

---

#### Phase 17 — Bag UI: invisible-only fixes

**Task and purpose.** Fix the Bag UI's correctness, performance and cleanliness defects **without
moving a single pixel the owner has not approved**, in order to honour requirement 9 while still
closing real bugs.

> **FENCE — hard constraint in this phase.** `UI/Core.lua` is **ADD ONLY** and in practice this
> phase should not touch it at all. **B1 must NOT be fixed by changing `CreatePanel` or
> `CreateHeader`** — both are frozen. `CreateScrollFrame`'s geometry stays untouched; B4's seeding
> step uses **the same expression `ResizeForSettings:874-889` already uses**, on BagUI's side of the
> boundary, and adds no new mirrored constant. No existing `UI.layout` value is retuned.

**Steps.**
1. **B3 — the ancestor: one shared bag iterator.** No canonical bag iterator exists, so 3 of 6 call
   sites forgot the nil guard: `CategoryView.lua:347-348` iterates `1, numSlots` with no `or 0` and
   is called from `CategoryView:Refresh` **outside** the `pcall`s at `:158,195`;
   `BagUI/Core.lua:727-728` compares nil with a number and aborts `Refresh`; `BagData.lua:287,297`
   likewise. Guarded sites for contrast: `BagUI/Core.lua:910,915`, `ItemButton.lua:53`,
   `RecentItems.lua:174,193,227`, `CategoryView.lua:372`. **With script errors off, a bag swap
   renders nothing after the pools were already released.** Fix: one shared
   `IM:ForEachTrackedBagSlot(fn)` (or at minimum `IM:GetTrackedBagIDs()` plus `or 0`), routing all
   six sites through it — **which also kills BagData's hardcoded `5` vs
   `Enum.BagIndex.ReagentBag` divergence**, the same producer as W2-19 in Phase 6.
2. **B5.** `ItemButton:Clear` zeroes the **shared** virtual bag frame's ID:
   `ItemButton.lua:257-280` (especially `:264-267`) does `button:GetParent():SetID(0)`, but that
   parent is the per-bag virtual frame cached in `scrollContent._imBagFrames` (`:317-329`) and
   **shared by every button in that bag**; `ReleaseAll` (`:244-255`) calls `Clear` on each active
   button, stomping it repeatedly. Any virtual bag frame not re-populated next pass (e.g. all its
   items filtered out by search) keeps `ID == 0` and **claims to be the backpack**. Latent today
   because `SetItem` re-asserts `bagFrame:SetID(bagID)` at `:341` and stale buttons are hidden —
   but `ContainerFrameItemButtonTemplate` resolves which item you are clicking from exactly that
   field, so this is the "using an item acts on the wrong bag" class. Fix: **delete the line**;
   virtual bag frames are permanent identity holders, so set the ID once at creation (`:323`). Keep
   `button:SetID(0)`.
3. **B4.** MasonryLayout's non-positive-width "safety check" is a no-op and a negative width
   reaches `header:SetSize`: `MasonryLayout.lua:155-162` recomputes the identical expression it just
   rejected, yielding `-12` for `containerWidth = 0` and `-52` for the `CategoryView:191` fallback;
   the negative width goes to `header:SetSize` (`CategoryView.lua:794`), errors, and the error is
   swallowed by the per-section `pcall` at `:708` — producing "Bag section 'X' failed to render"
   for **every** section. Reachable because `Create()` (`BagUI/Core.lua:465-467`) never seeds
   `scrollFrame.content:SetWidth(...)` the way `ResizeForSettings:874-889` explicitly does, so the
   first render depends entirely on the factory's `OnSizeChanged` having fired. Fix: make the guard
   real with a `math.max` floor; have `GetItemsPerRow` reject non-positive input explicitly rather
   than relying on `math.max(1, ...)` masking it; and seed the scroll-child width in `Create()`
   **using the same expression `ResizeForSettings` uses**. Invisible — it only changes a path that
   currently prints errors and draws nothing.

**CHECKPOINT** — swap a bag, open the custom bag on a fresh login, and search until a category
empties: no "failed to render" lines, no missing sections, no items acting on the wrong bag.

4. **B7.** Per-refresh `string.format` and a `pairs(button)` scan run whether debug is on or off:
   `IM:Debug` (`Core.lua:174-181`) no-ops when disabled but **its arguments are evaluated first** —
   `ItemButton.lua:343` runs a format with four `GetID()` calls **per item per refresh**;
   `CategoryView.lua:182` five `GetWidth()` calls plus a format per refresh; more at
   `ItemButton.lua:334-335`, `CategoryView.lua:202-203,216-217,221,732-733,763`,
   `MasonryLayout.lua:164-165,179,239-240`, `BagUI/Core.lua:197-198,820,852,869,887`. Separately
   `SetItem` calls `SetItemCraftingQualityOverlay` then walks **every key of the button table**
   (`:464-477`) calling `GetAtlas()` on each table-valued child, per item per refresh, and
   permanently re-anchors Blizzard's overlay each time. Fix: add an `IM:IsDebug()` predicate and
   guard the hot-path calls (or delete the per-item ones outright); cache the resolved overlay
   child as `button._imCraftingPip` on first discovery.
5. **B8.** `BAG_UPDATE_DELAYED` and `PLAYER_EQUIPMENT_CHANGED` trigger an **undebounced** full
   rebuild (`BagUI/Core.lua:581-602` calls `Refresh()` synchronously), while the search path **is**
   debounced (0.15s, `:42-58`) and the settings sliders are (0.12s, `Panels/BagUI.lua:109-135`).
   **Observed, Phase 0**: opening a bank produced **two complete `CategoryView` render cycles**
   (`Width chain` → `MasonryLayout` → `Rendering` → `Content bounds`, twice) on both bank opens in
   the recorded log — a live instance of the undebounced-rebuild class this step fixes, not a
   separate finding.
   `PLAYER_EQUIPMENT_CHANGED` fires **twice per swap** and once per slot on an equipment-set change
   — up to ~16 full rebuilds for one click — and `BagData.lua:486-488` queues its own refresh on the
   same event, doubling the work. Each rebuild is `ReleaseAll` + `GatherItems` (up to 3×
   `GetItemInfo` per item) + full `SetItem` of every button + `OverlayFactory:Update` per item
   (which calls `Filters:ShouldAutoSell`) + `FitHeightToContent`. Fix: one `BagUI:QueueRefresh()`
   using the existing debounce shape at `:49-57`, routing both handlers through it; **keep `Show()`
   calling `Refresh()` directly so opening stays instant.** **Set it to 0.2s, not the 0.5s the
   project standard names** — 0.2s is invisible, 0.5s of stale icons after a loot is perceptible
   and would need approval.
6. **B9.** `button._imOverlay` is a dead frame created once per pooled button: created at
   `ItemButton.lua:212-216`, and the only other reference is the always-empty child loop at
   `:270-274`. `UpdateOverlay:494-501` passes **`button`**, not `button._imOverlay`, to
   `OverlayFactory:Update`, which parents its own overlay to the button
   (`OverlayFactory.lua:180-184`). The overlay system moved and the old per-button frame was never
   removed. Cost: one orphan Frame per pooled button — **200+ pre-created at `PLAYER_LOGIN`**
   (`CalculatePoolSize:65`), none ever drawn — plus a wasted `{...:GetChildren()}` table allocation
   per button per `ReleaseAll`. Delete `:212-216` and `:269-274` (grep confirms nothing else
   touches `_imOverlay`).
7. **B14 (invisible half).** The button pool can never grow, so items silently vanish:
   `ItemButton.lua:48-66` sizes the pool `max(totalSlots × 2, 200)` once at `PLAYER_LOGIN` and
   `:72-73` refuses to re-run, so later bag upgrades are not accounted for; on exhaustion `Acquire`
   (`:230-242`) returns nil and `RenderCategory:756-757` **silently skips the item** with only a
   debug line. Fix: grow on demand — `_buttonPool[#_buttonPool+1] = self:CreateButton(...)` —
   which removes the failure mode entirely rather than raising a constant.

**CHECKPOINT** — loot heavily with the bag open and swap equipment repeatedly: one rebuild per
debounce window, no per-item formatting cost, and every item renders even after a bag upgrade.

8. **B12.** Override-binding calls have no `InCombatLockdown` guard: `BagUI/Core.lua:961-1002`,
   called from `:1365,1381-1382,1390,1424` and `Panels/BagUI.lua:71,94`.
   `SetOverrideBindingClick`/`ClearOverrideBindings` are combat-restricted and two call sites are
   event handlers that can fire in combat (`UPDATE_BINDINGS` `:1379`,
   `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/_HIDE` `:1387,1408`); `_toggleButton` is a
   `SecureActionButtonTemplate` whose OnClick is swapped at runtime (`:1393,1418-1422`), also
   protected. **Worse than an error**: `:1381-1382` clears then re-sets, so a failure between the
   two leaves the user with **no working bag key** until the next `UPDATE_BINDINGS`. Fix: one
   `BagUI:ApplyBindingOverrides()` that both Setup and Clear route through, deferring to
   `PLAYER_REGEN_ENABLED` when locked down. (A10: the API restriction is documented but unverified
   in-game; the guard is correct regardless.)
   **Observed, Phase 0, compounding this finding**: the override bindings are cleared and re-set
   **five times in ~2 seconds on every login**, not once — see Phase 3's login-storm evidence and
   its login-settle guard (step 3 there). That guard collapses this to one clear-then-set per
   login, which shrinks the window this step's fix has to close from five chances per login down
   to one; it does not replace this step's `InCombatLockdown`/`PLAYER_REGEN_ENABLED` fix, which
   still stands on its own for the in-combat case.
9. **B13 — dead code, delete it (git is the archive).** Resize scaffolding:
   `SetResizable`/`SetResizeBounds` (`:246-247`), `resizeGrip` (`:550-561`) **which is `Hide()`n at
   `:553`**, and `BagUI:OnResize` (`:780-797`) — the grip is the only caller of `StartSizing`, so
   `OnResize` and its `settings.height` persistence are unreachable. `ItemButton:ResizeButton`
   (`:553-558`) has no callers and a **different scale contract** from `ResizeAll` (`:560-571`) —
   it divides by 37 without the `+17` border compensation, so it would be wrong if called.
   `BagUI/Core.lua:906-920` computes `totalSlots`/`defaultItemsPerRow` then discards them (`:924`
   hardcodes 10). `settings.scale` (`:936`) is never read. `settings.columns` is read at
   `MasonryLayout.lua:350`, never written, and `Calculate:131` forces `columns = 1` anyway.
   `SIZING.SCROLL_CONTENT_INSET` (`:131`) is declared and never read (the literal `22` is used at
   `:885` instead) — **use the constant at `:885` rather than deleting it**, since that removes one
   of the un-named mirrored copies the fence warns about. `ItemButton.lua:290` gates a dump on
   `IM.db.global.debugMode`; **the real flag is `debug`** (`Core.lua:175,500`), so `:289-303` is
   unreachable — fix the flag name and keep it, since B7 makes the debug path worth having.
   **If the user wants edge resizing back, that is a feature request, not a cleanup — it is
   gate G7 in Phase 17A, not a step here.**
10. **B15 (convention drift).** Add the missing `_` prefix to four file-local helpers:
    `ItemButton.lua:48` (`CalculatePoolSize`), `CategoryView.lua:583` (`IsCurrencyToken`),
    `BagUI/Core.lua:509` (`CreateMeter`), `:1112` (`CloseAllBagFrames`). ~11 others are already
    correct, so the convention is followed ~80%.
11. **B15 (lifecycle).** The subsystem has no module lifecycle at all: `BagUI` is not a registered
    module, hangs off `IM.UI`, and registers four `IM:RegisterEvent` handlers **at file scope**
    (`BagUI/Core.lua:1343,1379,1387,1408`), as does `BagIntegration` (`:293`), while
    `BagUI:RegisterEvents` (`:581`) is called from inside `Create()`. Consequence: those four
    handlers cannot be unregistered or reordered, which is why `Create()` has to be called from
    inside a `PLAYER_LOGIN` handler that also does hooking and conflict detection (`:1343-1376`).
    `CustomCategories.lua:266-268` has an `OnInitialize` that is a comment only.
    **Do NOT force BagUI into `RegisterModule` — that buys nothing and reshuffles load order.**
    **Decision: give it a `BagUI:OnLogin()` that the single `PLAYER_LOGIN` handler calls**, so the
    sequencing is readable, **and** add one sentence to CLAUDE.md (Phase 18) stating that `UI.*`
    namespaces use file-scope registration by design. Delete the comment-only `OnInitialize`.
12. **RecentItems diagnostic.** `RecentItems:OnEnable` returns early and silently if `BagData` is
    absent (`RecentItems.lua:90-94`), permanently disabling own-flag tracking with no diagnostic —
    which would make the Recent section cover only Blizzard's flags, a partial **invisible**
    degradation that `Diagnose:215-220` would reveal. Add the diagnostic.
13. **Two do-not-break invariants — record them, change nothing.**
    **(a) Lock/junk clicks are not handled by BagUI at all**: `ItemButton.lua:218-221` relies on
    `ItemLock`/`JunkList` hooking `ContainerFrameItemButtonMixin.OnClick` (`ItemLock.lua:414`,
    `JunkList.lua:48`), which works **only** because these buttons inherit
    `ContainerFrameItemButtonTemplate`. If `ItemLock`/`JunkList` ever switch to hooking Blizzard's
    **named** bag buttons, Alt+Click dies in the custom bag with no error. No phase changes those
    hooks — **but Phases 1 and 16 touch `ItemLock`, so the smoke check below is mandatory.**
    **(b) `IM.ITEM_CLASS_NAMES` is a hand-synced ordering key**: `CategoryView.lua:601,625` reads
    it un-nil-guarded and `GetCategoryOrder:647-659` keys on the **display string**, so renaming a
    value silently re-labels **and** re-orders bag categories. Phase 16's W6-12 builds a dropdown
    over this same table — it may **read** it, never rename a value.

**Exit criteria (in-game smoke checklist).**
- **The window is pixel-identical to before this phase**: same width, same column count, same row
  heights, same colours. Screenshot before and after.
- **`Alt+Click` and `Ctrl+Alt+Click` still lock and junk inside the CUSTOM bag** (invariant 13a —
  mandatory because Phases 1 and 16 touched `ItemLock`).
- Swap bags, upgrade a bag, and empty a category by searching: every section renders, no "failed to
  render" lines in `/im debug`, no item silently missing.
- Use an item from a non-backpack bag after a search has emptied another bag's section: the correct
  item is used (B5).
- Loot 40 items with the bag open: one rebuild per 0.2s window, not one per event; equipment swap
  produces one rebuild, not sixteen.
- Enter combat and press the bag key, and change a binding in combat: the bag key still works
  afterwards and no error fires (B12).
- **B7, as a code-level assertion rather than a profiler run** (no profiler exists in this plan's
  tooling and none is being added): `grep` proves **every** `IM:Debug` call on a bag hot path sits
  behind an `IM:IsDebug()` test or has been deleted — specifically `ItemButton.lua:334-335,343`,
  `CategoryView.lua:182,202-203,216-217,221,732-733,763`,
  `MasonryLayout.lua:164-165,179,239-240`, `BagUI/Core.lua:197-198,820,852,869,887` — so no
  `string.format` and no `GetID()`/`GetWidth()` call is evaluated per item per refresh with debug
  off. Also `grep` proves the `pairs(button)` walk at `ItemButton.lua:464-477` is gone, replaced by
  the cached `button._imCraftingPip`. With `/im debug` **on**, the item dump at
  `ItemButton.lua:289-303` now actually appears (the flag-name fix in step 9).
- Log in with `BagData` unavailable (simulate by disabling it in `.toc` locally, then restore):
  `Diagnose` reports the degradation.
- `grep` proves the deleted dead code is gone and that `SCROLL_CONTENT_INSET` is used at `:885`
  rather than the raw literal.

**Reviewer fan-out prediction.** Performance seat (debounce, debug-argument evaluation, pool
growth), a correctness seat on B5's shared-ID deletion, and a concurrency seat on the combat-lockdown
deferral. **No visual seat — a visual finding in this diff means the fence was breached.**

---

#### Phase 17A — Bag UI approval gates (STOP AND ASK)

**Task and purpose.** Present each visible Bag UI change to the owner individually, in order that
requirement 9 is honoured literally: nothing about the bag itself changes without his say-so.

**These are decision gates, not work.** An executor **must not implement any of them** before the
owner has approved that specific item. Present them **one at a time**. A declined gate is recorded
as declined in Future Requirements with its trigger — it is not silently dropped and not
re-proposed.

**Nine gates: G1-G6 are visible bag-UI changes, G7-G8 are questions that become new plans if the
answer is yes, and G9 belongs to Phase 1 and blocks only that phase's step 4.** G9 is presented
here with the others because this is where the owner's bag-UI attention is already pointed — but
**it does not block Phase 1**, which ships steps 1-3, 5 and 6 without waiting. Present G9 **first**
if Phase 1 has already shipped, because it is the one gate holding a known-wrong ring on screen.

**Gates.**
- **G1 — B1: the hidden window rebuilds itself forever.** Closing the bag with the header X or
  ESCAPE leaves `_isVisible` stuck `true` (`UI/BagUI/Core.lua:20,631-646,657-659,669-670,583-601`):
  BagUI keeps a parallel visibility flag maintained only inside its own `Show`/`Hide`, while two
  **factory-installed** controls hide the raw frame directly and never route through them —
  `CreatePanel`'s `OnKeyDown` ESCAPE (`UI/Core.lua:400-406`) and `CreateHeader`'s close button
  (`UI/Core.lua:509-511`) — and there is no `OnHide` script to reconcile. Consequences:
  `BAG_UPDATE_DELAYED` and `PLAYER_EQUIPMENT_CHANGED` still see `_isVisible == true` and run a full
  teardown/rebuild of every item button + `GatherItems` + all overlay recomputation +
  `FitHeightToContent` **on an invisible window, indefinitely**; `RecentItems:MarkAllSeen()`
  (`:632-635`) never runs so Recent markers never clear; and `Toggle()` (`:649-655`) needs two `B`
  presses to reopen. Proposed fix: add `frame:SetScript("OnHide", ...)` in `Create()` doing the
  `MarkAllSeen` + `ClearSearchFilter` + flag bookkeeping, and make `BagUI:Hide()` just call
  `_bagFrame:Hide()` — or make `_isVisible` a derived read of `IsShown()`. **Do NOT fix this by
  changing `CreatePanel`/`CreateHeader` — those are fenced.**
  **Why it is a gate**: the close sound moves to the X/ESC paths and Recent markers start clearing
  on those paths (which matches the documented intent at `:626-630`).
  **Recommendation: APPROVE — strongly.** The performance win is the largest in the subsystem and
  the behaviour change is small and arguably already intended. Until it is approved, R10 stays
  MEDIUM.
- **G2 — B2: the viewport is ~20px too short.** `FitHeightToContent`
  (`BagUI/Core.lua:693-711`) ignores 28px of `CreateScrollFrame` chrome (container insets 10+10 at
  `UI/Core.lua:1016-1017`, ScrollFrame insets 4+4 at `:1029-1030`), so the last row is clipped and a
  scrollbar appears even though the window was just sized to fit. Proposed fix: **measure**
  (`_bagFrame.scrollFrame.scrollFrame:GetHeight()`, exposed at `UI/Core.lua:1146`) rather than add a
  fourth mirrored constant. **Visible: the window grows ~20px and the scrollbar disappears when
  content fits — a hand-tuned dimension.** Unverified in-game. **Ask before touching.**
- **G3 — B6: the rail's two hairlines never render.** `railRule` (`:391-395`) and
  `railHeadingRule` (`:406-410`) are created, sized, anchored and `SetVertexColor`'d but **never
  call `SetTexture`**, so they draw nothing — compare the working `footerRule:476-481`. The design
  intent is spelled out in the comments at `:384-385` and `:397-399`. **Visible: adds two lines to
  the window the owner has never seen.** The producer (absence of a `UI:CreateHairline` factory) is
  already fixed in Phase 13, so approval makes this a two-line call.
- **G4 — B10: palette violations.** The **retired** amber `|cffffb000` is still used at
  `Panels/BagUI.lua:240,241(×2),242,243,244` and `UI/BagIntegration.lua:181`, so the bag settings
  Tips card renders in the old accent and clashes with the cyan used elsewhere in the same window.
  Plus hardcoded colours at `BagUI/Core.lua:330,1254,1276,1309,1336`, `CategoryView.lua:140,142`
  (a grey that is neither `textDim` nor `textDisabled`), `Panels/BagUI.lua:30,50,66,69,89`,
  `Panels/UI.lua:49,69,80,91,102`. **Ancestor**: `OverlayFactory`'s `COLORS` table
  (`OverlayFactory.lua:44-65`) is a **second palette** with no relationship to `UI.colors`;
  `SetColors` (`:511-527`) exists, nothing calls it, and its own comment admits existing overlays
  will not update. The `Panels/UI.lua:69,80,91,102` swatches restate overlay colours and should be
  sourced from `OverlayFactory:GetColors()`. **Visible: every one changes an on-screen colour.**
  Present as one gate with the ancestor named, so an approval fixes the producer rather than
  repainting six literals.
- **G5 — B11: uncached items stick in "Other".** In `subcategory` mode,
  `GetItemSubcategory` (`CategoryView.lua:606-643,664-692`) deliberately uses `GetItemInfo` (comment
  `:607-608`) because `GetItemInfoInstant` does not return `equipLoc` reliably; `GetItemInfo`
  returns nil for uncached items so everything falls to `return "Other"` (`:642`). The `ItemStats`
  refresh callback that exists **precisely** to re-render on `GET_ITEM_INFO_RECEIVED` is filtered to
  the two stat modes (`BagUI/Core.lua:1348-1356`). `category` mode is unaffected (synchronous
  `GetItemInfoInstant`). Proposed fix: drop the mode filter at `:1352` — re-rendering on late item
  data is correct for every mode. **Visible: items visibly jump out of "Other" a fraction of a
  second after opening the bag.**
- **G6 — B14 (visible half): an item in two equipment sets renders twice.**
  `CategoryView.lua:489-498` sets `claimed[item] = true` once but then inserts the item into
  **every** matching set's list, so one bag slot yields N buttons with the same `bagID`/`slotID` —
  and `ItemButton:GetButton(bagID, slotID)` (`:532-540`) returns only the first, so a targeted
  single-slot update refreshes one copy and leaves the other stale. **Decision required from the
  owner: render a shared item only in its first set (matching how `claimed` is used for Recent), or
  keep the duplication and document it.** Present both, with the staleness consequence stated.
- **G7 — edge resizing: feature request, not cleanup.** Phase 17 deletes the unreachable resize
  scaffolding per B13. **Ask, do not assume**: does the owner want edge resizing as a real feature?
  If yes, it is a new plan, out of scope here. If no, the deletion stands.
- **G8 — `CustomCategories` has no effect on the custom bag view.** It is consumed only by
  `BagData._GetItemCategory` (`BagData.lua:167-172`), and the bag UI **does not use `BagData` at
  all** (it scans containers directly, `CategoryView.lua:341-397`) — despite
  `CustomCategories.lua:4` saying "Custom category management for the Bag UI". **This is a missing
  feature, not a regression. Surface it as a question; do not build it.** If the owner wants it, it
  is a new plan.
- **G9 — the sell-ring predicate: which ring the bag paints, edited by hand.** This is Phase 1
  step 4, gated. It blocks **only** that step; the rest of Phase 1 ships without it.
  **What is wrong.** `OverlayFactory:Update` keeps its **own** junk check —
  `isJunk = IM:IsJunk(itemID)` (`UI/OverlayFactory.lua:420`) — and the will-be-sold ring fires on
  `(isSellable or isJunk)` (`:462`), independently of the filter. Verified: that local is read at
  `:462` and **nowhere else** tree-wide, and `Filters:ShouldAutoSell` already returns `true` for a
  junk-listed item **with** vendor value (`Filters.lua:555-557`) and `false, "No vendor value"`
  for one without (`:559-560`). So the OR paints a will-be-sold ring on junk the filter refuses.
  **Proposed fix**: delete the `isJunk` term from `:462` and delete the now-unused local at `:420`,
  so the ring reads `isSellable` alone.
  **What the owner is actually being asked**, because the simple version of the claim overshoots
  and he should not be handed an overstated one. "All three read from one decision now" is **not**
  true as written: `isSellable` is computed only under
  `if showSellOverlay and not isLocked and not isMailRuleMatch` (`:434-437`), so after the deletion
  the ring still reads *no* decision in three situations. Two of them are improvements (a
  whitelisted item and a no-vendor-value junk item stop wearing a false ring — the OR was wrong
  there). The third is the one that needs a decision:
  - **The junk + mail-rule conflict.** `ShouldAutoSell` checks the junk list at `Filters.lua:553`
    **before** the mail-rule check at `:566`, so **a junk-listed item that also matches a mail rule
    will be sold**. But `OverlayFactory` gives `isMailRuleMatch` higher priority than the sell ring
    (`:456` before `:462`), and short-circuits `isSellable` to `false` for that item — so with
    `showMailOverlay` on, the bag paints the **mail** ring on an item the vendor is about to sell.
    That lie exists today and survives the deletion untouched; the `isJunk` term never reached it,
    because `:456` wins first. (With `showMailOverlay` **off**, `isMailRuleMatch` is false,
    `isSellable` is computed, and it comes back `true` — the sell ring paints correctly both before
    and after the deletion. So there is **no** case where the deletion loses a correct ring.)
  **Two options, present both:**
  1. **Narrow scope (recommended).** Delete the `isJunk` term only. Cheap, provably loses no correct
     ring, and the mail-vs-junk lie is recorded as a separate finding for a later plan. Claim
     narrows to: *the sell ring now reflects `ShouldAutoSell` wherever `ShouldAutoSell` is
     consulted at all.*
  2. **Full correctness.** Additionally compute `isSellable` **unconditionally** and reorder the
     priority chain so a will-be-sold verdict outranks the mail ring. This makes the ring honest in
     the junk + mail-rule case, but it is a **bigger visible change** (a blue mail ring becomes a
     yellow sell ring on those items) and it costs one `ShouldAutoSell` call per bag item even when
     the result is discarded — a hot-path cost in the same file B7/B8 are trying to make cheaper.
  Whichever the owner picks, **the smoke check adds the `showMailOverlay = false` + junk-listed +
  mail-rule-matching item** as an explicit case, alongside: a junk-listed legendary, a junk-listed
  item with a vendor price, and a junk-listed item with no vendor price.
  **Recommendation: approve option 1.** It is the fix with no downside; option 2 trades a real
  perf cost and a larger repaint for a case the owner may prefer to see as "mail wins".
  **G9's line numbers are verified against `UI/OverlayFactory.lua` and are correct as written — do
  not "correct" them.** A fifth-round review proposed shifting each back by one (419/429/455/461);
  the file says otherwise: `isJunk` is `:420`, `local isMailRuleMatch = false` is `:429` with its
  `showMailOverlay` gate on the following line `:430`, `isSellable` is computed at `:437`, the mail
  branch is `elseif isMailRuleMatch and showMailOverlay then` at `:456`, and the sell branch is
  `elseif (isSellable or isJunk) and showSellOverlay then` at `:462`. Read the file before changing
  a citation here; the priority claim (`:456` outranks `:462`) depends on these being right.

**Exit criteria.**
- Each of G1-G9 has a recorded owner decision: **approved** (then implemented and smoke-checked as
  its own commit, with the pixel diff described to the owner beforehand), **declined** (recorded in
  Future Requirements with a revisit trigger), or **deferred to a new plan** (G7, G8).
- No unapproved gate appears in any diff. `git diff` for Phase 17 shows zero changes to the files
  and lines named in G1-G6 unless that gate's approval is recorded, and **`git diff` across all of
  Phase 1 shows zero changes to `UI/OverlayFactory.lua`** unless G9's approval is recorded.
- For each approved gate, the smoke check is: open the bag, confirm the described visual change and
  **only** that change, then confirm column count and window width are otherwise unchanged.
- **If G9 is declined**, record it with its trigger and state plainly in the record that the bag
  ring will keep contradicting `ShouldAutoSell` for junk-listed protected items. A declined G9 is
  not a discharge of W1-1's second half; it is an owner-accepted display defect.

**Reviewer fan-out prediction.** Zero seats for the gate presentation itself. Each approved gate
earns seats from its own diff when it lands — G4 a visual/token seat, G1 a lifecycle seat, G6 and
G9 correctness seats.

---

#### Phase 18 — Documentation truth-up and dead code

**Task and purpose.** Stop the project's own documentation asserting things that are false, and
delete the code Phase 0 proved dead, in order that the next contributor (or the next session) is
not sent to do a 25-file sweep that Lua makes pointless or to read eight report files that do not
exist.

Runs last among the work phases: several items describe code that earlier phases changed, so
writing the docs first would be documenting a moving target.

**Evidence (A11/W0-6, observed, Phase 0), and a new in-scope item of the same class.**
`UI/Panels/History.lua` is now **confirmed unreachable, proven in both directions**: `UI/Config.lua:17-25`
lists General, BagUI, UI, Selling, Dashboard, MailHelper, Currency — no History — and the only
dynamic resolver in the tree, `UI/Panels/Selling.lua:53` (`UI.Panels[panel.module]`), resolves only
its own four `subTabs` (`:16-21`, AutoSell/Categories/Whitelist/JunkList). Nothing can construct
`UI.Panels.History`. This is no longer "candidate only" — step 10 below deletes it outright.
**New in-scope item, of W7's own class (a doc/UX claim contradicted by the code), not a new
finding**: `Core.lua:511` prints *"Check /im -> History tab to verify"* after `/im test sell`,
directing the user to a tab that cannot be opened. Fixed in step 10, in the same commit that
deletes the panel, since both are the same lie about the same dead tab.

**Steps.**
1. **W7-1 — the expensive one.** The `local module = self` rule is **wrong**. CLAUDE.md calls it
   CRITICAL and claims "24 of 25 modules violate" it, prescribing a 25-file sweep. In Lua, `self`
   is an ordinary parameter and a closure over it captures a stable upvalue — `local module = self`
   produces a **byte-identical binding**. It would matter only if the module table were reassigned
   after `OnEnable`, and `IM.modules[name]` never is (`Core.lua:96-107`, called once per file at
   load). Recon also found the pattern **is** used in `AutoSell.lua:31`, `MailHelper.lua:149`,
   `FlightTracking.lua:25`, `VendorTracking.lua:26`, `WarbandBankTracking.lua:22`,
   `UnclaimedGoldTracking.lua:53`, `BagData.lua:474`, `RecentItems.lua:91`,
   `BagIntegration.lua:36` and others — so the "1 of 25" claim is false in **both** directions.
   **Downgrade it to a style preference and cancel the sweep.** State plainly that the genuine
   lifecycle hazard was `pairs(IM.modules)`, fixed in Phase 3.
2. **W7-2.** The palette is wrong: CLAUDE.md documents amber `#FFB000` as the primary accent, but
   `UI/Core.lua:41` has been cyan `#3FA9F5` since the restyle, `:52` reserves amber `#F0B23A` for
   money only, and `:56`'s `warning` is commented "deliberately NOT the accent". Rewrite the colour
   section from the code.
3. **W7-3.** The interface version is wrong — CLAUDE.md says `110002`, the `.toc` says `120100`.
   Fix the doc, and note in it that **`publish.sh` never rewrites `## Interface:`**, so an
   interface bump is always a manual edit (Phase 19 depends on this being written down).
4. **W7-4.** `.analysis/` **does not exist.** CLAUDE.md cites eight report files (`bugs.md`,
   `performance.md`, `consistency.md`, `redundancy.md`, `cleanup.md`, `documentation.md`, `ux.md`,
   `report.md`) plus "Issue #1"/"Bug #1" references throughout — **every one is a dangling
   pointer.** **Decision: strip the references** and replace them with current state plus a
   `git log --grep=audit-remediation` anchor, per the decision-records rule. Restoring eight report
   files would recreate the same drift.
5. **W7-5.** The pooling claim is true in one of three paths — now true in all three after
   Phase 14. Update the claim to describe reality and drop the "Fix Plan" note.
6. **W7-6.** BankItemTracking's documented root cause is stale: CLAUDE.md blames a nil
   `_lastBankType`; **that variable no longer exists**, the module was rewritten, and the real
   defect was frame-open-time type detection — fixed in Phase 7. Rewrite the entry, or delete it
   now that it is fixed, and remove the "KNOWN BUG" marker from the module list.
7. **W7-7.** `Database.lua:103` still comments that warband gold is "manual entry - no API
   available" — disproved by the code itself (`C_Bank.FetchDepositedMoney`). Fix the comment.
8. **W7-8.** The documented module list is badly out of date — absent from CLAUDE.md entirely:
   `CustomCategories`, `ItemStats`, `RecentItems`, `BagData`, the whole `UI/BagUI/*` subsystem,
   `GuildBankTracking`, `FlightTracking`, `TransmogTracking`, `BarberTracking`, `BMAHTracking`,
   `UnclaimedGoldTracking`. The documented filter-priority list also asserts a quality-protection
   step **that did not exist in code** — Phase 1 made it real, so now the doc becomes true by
   describing the new order. Also add the one sentence Phase 17 step 11 owes: `UI.*` namespaces use
   file-scope event registration by design.
   **W7-8 names the Filter Pipeline section (`:170-180`) and that is not the only place the rule is
   asserted — fix BOTH or the doc still contradicts the code.** `.claude/CLAUDE.md:593-602` carries
   a *Key Architectural Decisions* entry titled "Junk List Overrides Protections" whose Decision
   line (`:595`) reads *"Junk list overrides ALL protections (quality, category, special items)
   EXCEPT whitelist"* and whose Priority Order (`:597-600`) puts the junk list above every
   protection. **Phase 1 step 1 deliberately reverses that**: the quality floor is inserted above
   the junk-list branch, so a junk-listed legendary is no longer sold. Rewrite that section to the
   new rule — **whitelist, then the quality floor, then the junk list, then everything else** — and
   keep the "Why" honest: the junk list remains the user's manual override over *category and
   special-item* filtering, but it can no longer override the quality floor, because the floor
   exists to make item destruction impossible rather than merely unlikely. This is a **reversal of
   a recorded Decision, not a drift correction**, so the reasoning goes in the commit
   (decision-records rule) and the doc carries only the new current state.
9. **Three CLAUDE.md claims THIS PLAN invalidates, plus one standing instruction this plan's own
   diagnosis adds.** W7's list was drawn from the audit, i.e. from claims that were already false.
   The three claims below are ones this plan *makes* false, so they are not in W7 and would
   otherwise be left standing. The fourth item, at the end, is not a false claim being corrected —
   it is a methodology gap OQ-2 exposed that CLAUDE.md never named at all:
   - **The "0.5 second throttle" debouncing standard.** Phase 17's B8 deliberately uses **0.2s**
     for `BagUI:QueueRefresh`, with a stated reason (0.5s of stale icons after a loot is
     perceptible and would need owner approval). Rewrite the standard as "0.5s for settings-panel
     and dashboard refreshes; 0.2s where staleness is visible in the bag window", so the next
     session does not "correct" 0.2s back to 0.5s.
   - **The character-key format**: CLAUDE.md says *always use
     `UnitName("player") .. "-" .. GetRealmName()`*. Phase 11 makes that the **wrong** thing to
     write — the producer is `IM:GetCharacterKey()`, it normalizes the realm, and the raw form is
     what W3-11 exists to eliminate. Rewrite it to name the producer and the split helper
     (`IM:SplitCharacterKey`), and state that raw `GetRealmName()` outside `GetCharacterKey` is a
     defect. **Add five standing instructions, which are the durable output of Phase 11's
     restructuring** (an earlier revision said "three" while listing four — the list below is the
     authority). Put them in the doc so they survive this plan rather than living in an
     appendix nobody reads next year:
     1. *Any future change to `IM:GetCharacterKey`'s output must land in the same commit as the
        migration that rewrites the stored keys — never a phase apart, never bridged by a
        read-compat resolver.* (This replaces the retired risk row.)
     2. *A commit carries every **reader** and every **writer** of a field whose **shape** it
        changes. A field being **deleted** needs only its accessors retired **no later than** the
        deletion.* A reader left behind errors on a missing key; a writer left behind resurrects
        the data or nil-derefs the store. Both are live defects, and a reader-only sweep catches
        half. But a deletion has no disagreement window, so the accessor retirement belongs in its
        own earlier commit — bundling it into a reshape's atomic commit only makes the diff
        unreviewable. Worked example: Phase 11's atomic commit went from seven members to five
        when the `sellHistory` retirement moved out.
     3. *Enumerate character-keyed persistence by grepping **write** sites, not by reading
        `defaults`.* A persisted table can exist with no `defaults` entry —
        `mailHelper.pendingQueue` did, which is why three review rounds of this plan each missed a
        different member of that set. Name `pendingQueue` in the doc as the worked example.
     4. *Before retiring or consolidating any store, ask the **lifetime** question: what deletes
        rows from each side, on what axis, and can one side outlive the other?* Worked example, and
        it is the reason this instruction exists: `sellHistory` was capped **by count** and
        `transactions` purged **by age**, so rows migrated from one to the other were deleted from
        the destination by age while the originals survived in the source — making a store everyone
        had labelled "duplicate" the **only** copy of those rows. Five planner rounds and four
        review rounds read past it; the owner found it by asking. **A store's shape does not tell
        you its lifetime.**
     5. *`GetNormalizedRealmName()` normalizes the **current character's** realm and nothing else —
        it takes no argument. There is no WoW API that normalizes an arbitrary realm string.* So:
        call it in `IM:GetCharacterKey` and **nowhere else**; anything that must transform a
        **stored** realm (a migration, a repair tool, an import) looks the value up in a table proven
        equal to the API for the realms in play, or leaves the string alone — it never derives one by
        stripping characters, because normalized names drop punctuation and accents, not just spaces.
        Worked example, and the reason this instruction exists: one sentence in an early revision of
        Phase 11 said "normalize stored keys via `GetNormalizedRealmName()`", which would have
        rewritten every alt's realm to the running character's and then **merged** the collisions —
        total silent loss of every alt's gold and snapshot history on a multi-realm account.
   - **"NOT `button:SetText()` — that method doesn't exist."** Phase 13 step 1 makes it exist, at
     the producer. Rewrite to say `button:SetText(t)` is supported and is the preferred call, with
     `button.text` remaining the underlying FontString.
   - **A methodology gap, not a false claim: audits and reviews of a startup/login path must read a
     real trace, not just the handler list.** Every one of the five audits reasoned about
     steady-state event handling — what a handler does when it fires during play — and none of
     them read an actual `/im debug` trace across a `/reload` to see how many times a startup
     handler actually fires before the client settles. **OQ-2 is the worked example**: BagUI's
     override bindings, `BagData`'s full refresh, `InventorySnapshot`'s startup scan and
     `NetWorth`'s gold-update logging each fired multiple times per login, invisible to any review
     of the handler registrations alone, and found only by reading `/im debug` output across a
     `/reload` during Phase 0. Add this as a standing instruction, next to the character-key five
     above: *before auditing or reviewing any startup/login-time code path, capture and read a real
     `/im debug` trace across a `/reload` — reasoning about the handler list alone is exactly what
     let four redundant startup paths through five audits and four review rounds.*
   Same rule as the rest of this phase: describe the code as it now is, no history in the doc.

**CHECKPOINT** — steps 1-9 are docs-only and carry zero runtime risk; step 10 deletes code whose
failure mode is runtime-only (R7). Green state before crossing this line: CLAUDE.md contradicts
nothing in the tree, `grep -c '\.analysis/' .claude/CLAUDE.md` returns 0, and **Phase 0's written
reachable/unreachable verdict lines are in hand for every candidate in step 10**. Commit the docs
work here, separately, so a deletion rollback never drags the documentation back with it.

10. **W7-9 — deletions, each gated on Phase 0's written verdict.** Delete only what Phase 0 proved
   dead **in both directions**: `UI/Panels/Ledger.lua` (146 lines) and `UI/Panels/NetWorth.lua`
   (169 lines) — absent from the `.toc`, unreachable, still carrying amber-era styling, and both
   absorbed refactor commits (`927cdee`, `b7fc08c`) that changed nothing a user can see. Also
   `IM:GetAccountGold`/`IM:GetAccountNetWorth` (`Database.lua:856-873`, zero callers, with
   `GetAccountNetWorth` reimplementing `GetAccountBreakdown` and independently inheriting W3-2 and
   W3-5 — if Phase 9 fixed it instead, delete it now); `IM.OnDatabaseReady` (invoked
   `Database.lua:269-271`, defined nowhere — remove the invocation or define it, do not leave a
   call to nothing); `defaults.char` (`:164-167`, empty, never read); and the two overlapping
   welcome messages (`Core.lua:16,110-118,353-363` — keep one).
   **`UI/Panels/History.lua` is CONFIRMED DEAD, not a candidate — Phase 0 proved it in both
   directions (see this phase's evidence note above): `UI/Config.lua:17-25` names no History tab,
   and the tree's one dynamic resolver, `UI/Panels/Selling.lua:53`, resolves only its own four
   `subTabs`. Delete the file.** In the same commit, fix `Core.lua:511`'s
   *"Check /im -> History tab to verify"* message (after `/im test sell`) — it currently points the
   user at a tab that has never been openable; either remove the line or repoint it at the ledger's
   equivalent view, and record which in the commit. This is R7; the deletion still cites Phase 0's
   written verdict line, which now reads "unreachable" rather than "pending."

**Exit criteria.**
- CLAUDE.md contains **no claim that contradicts the code**: spot-verify the accent colour, the
  interface number, the pooling claim, the module list, the filter-priority order **in both places
  it is asserted — the Filter Pipeline section AND the "Junk List Overrides Protections" Decision
  at `:593-602`, which must now read whitelist → quality floor → junk list** — and the
  BankItemTracking entry against their files — **plus the three claims this plan itself
  invalidated**: the debounce standard reads 0.5s/0.2s-in-bag, the character-key section names
  `IM:GetCharacterKey`/`IM:SplitCharacterKey` rather than raw `GetRealmName()`, and the button
  section says `button:SetText` works — **and the standing instruction OQ-2 added**: CLAUDE.md
  names reading a real `/im debug` startup trace as a prerequisite for auditing or reviewing any
  login-time code path.
- No dangling pointer remains: `grep -c '\.analysis/' .claude/CLAUDE.md` returns 0.
- The `local module = self` rule is a style preference and the 25-file sweep is explicitly
  cancelled in writing, so no future session re-opens it.
- Every deletion cites Phase 0's verdict line. **In-game after deletions**: visit all nine settings
  tabs and all three dashboard tabs, plus the minimap menu — no Lua error, no missing panel (this
  is the only test that can catch a dynamic-lookup break, since it fails at runtime, not load).
- `/reload` produces exactly one welcome message.
- **`UI/Panels/History.lua` is deleted** (confirmed dead, not a survivor — see this phase's evidence
  note), the `.toc` entry loading it is removed, and `Core.lua:511`'s dangling "History tab"
  message is fixed in the same commit. `grep` confirms no remaining reference to the file outside
  `git log`.

**Reviewer fan-out prediction.** Docs-only for steps 1-9 → **zero seats**. Step 10's deletions earn
one dead-code seat. Do not run a code reviewer over a documentation diff.

---

#### Phase 19 — Release 1.4.0

**Task and purpose.** Publish once, in order that the whole remediation reaches CurseForge as a
single coherent version.

Note the user runs the working copy symlinked into WoW (`symlink-to-wow.md`), so every fix has
already been live for him throughout; **"release" means the CurseForge publish only**, and there
are no per-wave releases.

**Steps.**
1. **Coverage gate.** Walk Appendix A and confirm every row is closed: implemented, deliberately
   deferred with all four fields (Appendix B), or recorded as an owner-declined gate. **Do not
   publish with an open row.** For the **eight** two-work-item findings (W4-6, W4-7, W4-8,
   **W4-11**, W6-16, W6-18, **W3-8** and **W1-1**), **both** items must be closed — a factory
   addition with no call site switched onto it is an open row, not half a closed one. W1-1's second
   half is gate **G9**; an owner **decision** on G9 (approve-and-ship or decline-and-record) closes
   it, an undecided G9 does not. **W4-11's second half lives inside Phase 11's atomic commit and
   W3-8's inside Phase 11's preceding retirement commit, so it takes `git show` on BOTH commits to
   close them** — one commit is not the proof of the other. **The table is 127 rows now**: OQ-1 is
   its own row and is **closed by an owner decision to accept the loss** (Appendix B **L1**), not by
   W3-8 and not by any fix. Read it the way the gate reads a declined approval gate: a recorded
   **decision** closes the row; **silence would not have closed it**, and neither would shipping the
   drop without the decision on record. Confirm the L1 entry exists with all four fields before
   marking the row closed. **OQ-2 is also its own row, closed by a fix rather than a decision** —
   Phase 3's login-settle latch (step 3) plus Phase 9's `ScanBags` honest-return fix (step 5) — and
   its close condition is the in-game cross-check both phases carry in their exit criteria: the
   latch fires exactly once per login for all four paths **and** a forced failed scan still
   retries and does not set the latch. A green `git show` on Phase 3 alone does not close this row.
2. **Manual `.toc` edit.** Confirm `## Interface: 120100` is correct for the live build and edit it
   by hand if not — **`publish.sh` rewrites `## Version:` and `IM.version` only and never touches
   `## Interface:`**.
3. **Advisory line (not a gate).** Tell the user, in the release notes and in chat: *copy
   `InventoryManagerDB.lua` out of `WTF/Account/<ACCOUNT>/SavedVariables/` before first login on
   1.4.0.* Advisory by explicit user decision — **do not turn this into a gate and do not add a
   backup mechanism.**
   **Release-note line about the sell-history span change is NOT written.** Phase 0 confirmed
   `UI/Panels/History.lua` unreachable in both directions, and Phase 18 deletes it, so there is no
   surviving view whose span changes and nothing to advise the user about on this point. Do not
   write a retention advisory in its place — the owner's decision was to accept the loss of rows
   past his window, and telling him to widen the setting to dodge his own policy would reverse that
   decision by footnote.
4. **Clear `publish.sh`'s four hard gates**: clean working tree; no untracked files except
   `VERSION_GUIDE.md`/`*.zip`; branch `main`; monotonic version increment (1.3.3 → 1.4.0).
5. **Publish once.** `X-Curse-Project-ID: 1422035`, `SavedVariables: InventoryManagerDB` unchanged.
6. **Post-publish smoke.** `/reload` on the published copy, confirm `IM.version` reads `1.4.0` and
   the addon loads with no error on a character that has never seen 1.4.0.

**Exit criteria.**
- Appendix A fully closed; Appendix B's deferrals each carry all four fields.
- `.toc` interface verified by hand; `## Version: 1.4.0` and `IM.version = "1.4.0"` agree.
- One CurseForge release exists for 1.4.0; no intermediate releases were cut.
- The advisory `cp` line appears in the release notes. **No sell-history span line appears** —
  Phase 0's verdict (`History.lua` confirmed unreachable) discharges it.
- A fresh login on 1.4.0 runs the v3 migration once, produces no error, and a second login changes
  nothing (final in-game confirmation of Phase 11's idempotency proof) — **including
  `#transactions.entries`, which must not change on either login.**

**Reviewer fan-out prediction.** Zero seats — no gradeable code decision. The release is a
checklist, and `publish.sh` is the mechanical gate.

### 3.4 Coordinating instructions

**FRAGO — line anchors are ADVISORY; the symbol name governs. Applied by the conductor 2026-09-08,
owner-approved, on `plan-adherence`'s `frago-needed` risk call after Phase 1.**

Every `file:line` citation in this plan is a convenience, not an address. **The function, symbol or
string named beside it is the authority; when they disagree, the anchor is wrong and the name is
right.** Re-derive by grep at execution time.

This is not a style preference — Phase 1 alone moved 142 citations across seven files:
`Modules/AutoSell.lua` ≈+660, `Filters.lua` +70 rising to +99, `Core.lua` +33 to +49,
`UI/AutoSellPopup.lua` +45, `Modules/TooltipInfo.lua` ≈+20, `UI/Panels/AutoSell.lua` +18,
`Database.lua` +1. Phases 3, 11, 13, 15, 16, 17 and 17A all read anchors into those files, and
Phase 11's atomic realm-key migration is driven off a `Database.lua` seed list every entry of
which is now one line early. An executor that trusts a stale anchor and reports "not found" is the
silent-discharge shape risk R11 exists to catch.

The alternative considered and rejected: a mechanical re-anchor pass after every phase commit.
Rejected because it is per-phase work that rots on its own and would itself need policing — the
same hand-maintained-claim disease logged as C1 in `.claude/corpses.md`. This rule extends the
posture §1 already takes on sets ("a hand-written list in a plan is a guess; a grep run in the
tree is a fact") from set membership to line position.

**Sequencing constraints — the complete list. Everything not named here is parallelizable.**
1. Phase 0 precedes Phases 4, 8, 9 (API answers), Phase 18 (death verdicts), **and Phase 11 — a
   hard one, not an advisory: Phase 0 step 7's `(GetRealmName(), GetNormalizedRealmName())` pairs
   ARE the migration's `realmMap`, and step 9A cannot be proven without them. No pairs, no atomic
   commit.**
2. Phases 1 and 2 precede everything else. Asset safety first, by commander's intent.
3. **Phase 3 precedes Phase 4** — the single confirmed prerequisite in the plan.
   `UnclaimedGoldTracking.lua:96` writes `false` and `WarbandBankTracking.lua:130` writes `true`;
   they are the only pair in the tree where two `PLAYER_MONEY` handlers write shared mutable state,
   so until `Core.lua:342` yields a fixed order you cannot tell whether a duplicate entry came from
   the ordering or from the flag's design.
4. **Phases 5, 6 and 7 are independent of each other. Unambiguously:**
   - **Phase 5 — no prerequisite.** Run it any time after Phase 2. Pure arithmetic/emission fixes.
   - **Phase 6 — no prerequisite.** Run it any time after Phase 2. Its only internal ordering
     constraint is *inside* the phase: step 4 (W2-16) runs after step 2 (W2-13), because the charKey
     stamp lands in step 2's extraction.
   - **Phase 7 — after Phase 4**, and that is the whole of its dependency: it *consumes* Phase 4's
     claim machinery rather than building a second mechanism. Not an ordering dependency in the
     nondeterminism sense; a code-reuse one.
   So: 5 and 6 need nothing from 4; 7 needs 4 landed. Nothing here requires 5, 6 and 7 to be
   serialized against each other in any order.
   **Recon REFUTED five asserted prerequisites — the refutations are load-bearing, do not
   re-serialize:** the repair race is deterministic today (`RepairTracking.lua:37-40` snapshots
   synchronously inside `MERCHANT_SHOW`; `AutoSell.lua:71-75` defers by 0.2s, so the snapshot
   always precedes the sale); the AH fee double-subtraction and missing `ah_refund` are pure
   arithmetic with no cross-handler state; MailHelper's tracking bypass is a missing code path;
   guild bank attribution uses only its own event and baseline; single-slot pendings collide in
   time, not across handlers. Every other tracker is order-independent by construction — each keeps
   a private `_lastGold`.
5. **Phase 10 precedes Phase 11** — deleting the `sellHistory` data is only final once its writers
   are dead, and Phase 10 also hands Phase 11 the written surviving-reader **seed** list its
   step 12 consumes (Phase 11 step 3's grep is what makes that list complete). **Phase 10 must not
   delete the legacy data or its `defaults` entry** — `_mergeDefaults` would undo a data-only
   deletion, and the two halves must land in one `git show` (R2's most dangerous failure path).
   **Phase 11's ATOMIC COMMIT is not splittable — but the phase is three commits, and the
   distinction matters.** The atomic commit carries **FIVE** members: the character-key producer
   change, the two remaining raw `GetRealmName()` conversions, the `DB_VERSION` bump plus the
   `_runMigrations` wiring, the `defaults` removal, and the `ledgerCharKey` **reader** conversion.
   It was seven until revision six; the owner split the two deletion-class members —
   the `sellHistory` reader retirement and the legacy history writer retirement — into their own
   **preceding** commit, on the rule now stated in Phase 11 step 3: *a commit must carry every
   reader and every writer of a field whose SHAPE it changes; a field being deleted only requires
   its accessors retired no later than the deletion.* A deletion has no disagreement window, so
   bundling it in bought nothing but an unreviewable diff.
   The working copy is symlinked into WoW, so a split of the **reshape** is live: an earlier revision
   split the producer change from the migration with an `IM:GetStorageKey` resolver bridging the gap,
   and three review rounds each found a different live defect in that gap. The owner deleted the
   window. **There is no resolver, no fallback, no identity-vs-storage split, and no scored risk row
   for a mechanism that no longer exists.** An executor who commits the producer change without the
   migration wiring, or vice versa, has recreated the window and must stop and squash.
   **The retirement commit must not touch data.** Its whole content is accessor deletions; if it
   also deletes `sellHistory`'s rows or its `defaults` entry, it separates the drop from the
   `defaults` removal that makes it hold — R2's most dangerous failure path.
6. **Phase 11 owns `ledgerCharFilter` entirely — field, migration AND reader. Phase 14's W4-11
   owns only `typeIndex`/`dateIndex`.** The earlier form of this item said "whichever lands first
   defines it; the other reads it", and **that was the defect**: it left a field whose *type*
   changes in Phase 11 being read by `UI/Dashboard.lua:411` and arithmetic-ed at `:622`
   (`chars[charIndex - 1]`) until Phase 14. `"Bob-Area52" - 1` raises a Lua 5.1 error there and
   aborts construction of the Ledger tab, and the self-healing branch at `:626-628` never runs
   because the arithmetic errors first. The general rule this is an instance of — **a field whose
   SHAPE changes moves with every one of its readers and writers in one commit; a field being
   deleted needs only its accessors retired no later than the deletion** — is now stated in Phase 11
   step 3 and enforced by its derivation grep. `ledgerCharKey` is a reshape and is therefore in the
   atomic commit; `sellHistory` is a deletion and is therefore not. Phase 11 deletes
   `ledgerCharFilter`, writes
   `dashboard.ledgerCharKey`, and converts the reader, all in the atomic commit; Phase 14 verifies
   and moves on.
7. **Phase 13 precedes Phases 14, 15 and 16** — they consume its additions.
8. **Phase 14 precedes Phase 15** — the category block reuses the post-filter array.
9. **Phase 2 precedes Phase 16's W6-9** — one send state machine, not two.
10. **Phase 16 step 18 (`UI:CreateQueuePopup`) runs last within its phase**, once both call sites
    have stopped moving.
11. **Phase 17A gates precede any implementation of G1-G6 and G9.** G9 is Phase 1 step 4 and
    **blocks only that step** — Phase 1's other steps ship without waiting, and Phase 1's own commits
    must show zero changes to `UI/OverlayFactory.lua`.
12. Phase 18 runs after the work phases it documents. Phase 19 runs last.
13. **Phase 4 depends on Phase 3 only; Phase 14 depends on nothing in Phases 4-12 except ledger
    search semantics** — the change alters what `IM:GetTransactions` means for exactly three
    callers: `Database.lua:757`, `Ledger.lua:168`, `Ledger.lua:180`. Check those three, not the
    world.
14. **Phase 3 precedes Phase 9 — two independent reasons, both real.** First, Phase 9's currency
    capture (step 8) routes its `PLAYER_ENTERING_WORLD` half through Phase 3's login-settle latch
    rather than inventing a second startup debounce — the latch has to exist to be consumed.
    Second, Phase 9's `ScanBags` honest-return fix (step 5, W3-6) and Phase 3's login-settle latch
    (step 3, OQ-2) are the two halves of one collision: the latch, if built wrong, would silently
    suppress the retry this fix depends on. Phase 9 must land, and be smoke-tested, with Phase 3's
    latch already in place, and Phase 3's Half 3 check must be re-run afterward — see the forward
    and backward references in each phase's steps.

**Verify-before-complete gates.**
- **No phase completes on "the file loads."** Every phase's exit criteria is an in-game smoke
  checklist, and the checklist must be *run*, not read. `green-check` buys nothing here; do not
  plan a step around it.
- **Phase 11 cannot complete without the Docker artefact** — a passing single run is not the proof;
  the second run must be a deep-compare no-op against a copy of the real SavedVariables. And the
  artefact must be green **before** the atomic commit exists, not after. One assertion in it is a
  standing guard rather than a check of this release's code: **`#transactions.entries` must be
  unchanged across the run.** The v3 pass rewrites keys and drops a store; it never inserts a
  transaction row. A growing count means someone re-added the withdrawn consolidation merge or the
  v1→v2 block is being re-entered.
- **Phase 11 also cannot complete on an artefact that ran a hollowed-out pass.** Two mechanical
  checks, both cheap, both mandatory before the atomic commit: `rg 'GetNormalizedRealmName' --type
  lua` returns **exactly one hit** (the producer, `IM:GetCharacterKey`) and **zero** inside
  `migrateV2toV3`/`IM:NormalizeRealmString`; and the realm-map equality proof (Phase 11 step 9A) is
  green, every distinct stored realm either mapped-and-Phase-0-verified or on the written
  unvisitable list. **Reason: the migration is only provable because it is pure. A WoW API call
  inside the pass is invisible to the harness — it would be stubbed away or would error — so the
  artefact would certify a migration whose most destructive step never ran.** That forfeits R2's
  `guard` bucket and returns the row to EX-HIGH.
- **Any phase touching `UI/Core.lua` completes only after the fence check**: `git diff UI/Core.lua`
  shows additions only (plus the two provably-invisible `CreateButton` behaviour changes), and the
  custom bag's column count and window width are unchanged.
- **Any phase touching `ItemLock` or `JunkList` completes only after the Alt+Click / Ctrl+Alt+Click
  check inside the CUSTOM bag** (Phases 1, 16, and any that follow). The check is also written into
  those phases' own exit criteria, because an executor reads its own phase, not this section.
- **Requirement 9 reads on the bag window's OUTPUT, not on file paths.** Any change to the
  observable output of a symbol the bag window renders is a visible bag change and needs owner
  approval, whichever file it lives in — `Core.lua` and `Modules/*` included. The audited list is
  in Phase 13 ("Indirection audit"); `IM:FormatMoney` (bag footer, `UI/BagUI/Core.lua:717`) and the
  `UI.colors` table are the two live traps, `IM.ITEM_CLASS_NAMES` is the third and
  `IM:FormatNumber` (`Core.lua:267`, `FormatMoney`'s own dependency) is the fourth. Before any
  phase in Movement IV completes, walk that list. **Two phases outside Movement IV are on it too
  and must walk it as well: Phase 1** (the quality floor) **and Phase 12** (the
  `_GetCachedItemInfo` re-key, which changes the info `ShouldAutoSell` reads for suffix-varying
  items). Both change what the bag ring says is true, so both carry a bag-window check in their own
  exit criteria; **neither needs an approval gate, because in both cases the ring change is an
  unavoidable downstream consequence of a correctness fix in a non-bag file.** The distinction that
  decides this, and the one an executor must not get wrong: a **consequence** of fixing something
  upstream is ungated; a **deliberate edit to the bag's rendering predicate** is gated. The only
  example of the latter in this plan is Phase 1 step 4 (`UI/OverlayFactory.lua:462`) — gate G9.
- **Phase 11 completes only after `git show` proves its atomic commit carried all FIVE members at
  once** — matching Phase 11 step 13's numbered list one for one: the `IM:GetCharacterKey`
  normalization; `Panels/MailHelper.lua:400` + `MailHelper.lua:587`; the `DB_VERSION` bump + the
  `_runMigrations` wiring; the `defaults` removal; and the `ledgerCharFilter` → `ledgerCharKey`
  reader conversion in `UI/Dashboard.lua`. **And `git log -p` proves no earlier commit in the phase
  touched any of those.** **FIVE, not seven**: the `sellHistory` **reader** retirement and the
  legacy history **writer** retirement (`IM:AddHistoryEntry` + six wrappers + nine call sites) are
  deletions and land in the **preceding** retirement commit (Phase 11 step 12) — which has its own
  gate: `git show` proves it is deletions only, with no `defaults` edit, no `DB_VERSION` change and
  **no change to `sellHistory`'s stored rows** (same entry count before and after). A retirement
  commit that deleted the data would separate the drop from the `defaults` removal.
- **OQ-1 carries no completion gate, and that is deliberate.** It is closed by the owner's recorded
  decision to accept the loss (Appendix B **L1**), not by a proof. Phase 0 confirmed
  `UI/Panels/History.lua` unreachable, so there is no view left to observe a span change in and
  nothing more owed here. An executor who finds himself building a merge, a backup or a retention
  override to satisfy this line has reversed an owner decision.
- **Phase 11 also completes only after its derivation greps return zero unhandled hits** (Phase 11
  steps 2-3 and the matching exit criterion). **This is what replaces the retired "no
  character-keyed table is indexed with an unresolved key" gate, and it is deliberately a
  different instrument.** Retiring that gate was right about the window — producer and storage can
  no longer disagree — but it also removed the plan's only forced walk of **write** sites, and
  three review rounds then found three different missing members of sets this plan had merely
  listed (`mailHelper.pendingQueue`, `sellHistory`'s writer family, `ledgerCharFilter`'s reader).
  **The standing rule, which applies to every phase and not only to Phase 11: a set whose
  exhaustiveness the plan cannot mechanically prove is derived at execution time by grep, with any
  written list demoted to a non-exhaustive seed.** A phase that closes a completeness criterion by
  pointing at a list in this document has not closed it.
- **Phase 11 also completes only after the post-migration check that structurally cannot run
  earlier**: `/im reset sellHistory` no longer reaches a section with no default. Must be run
  **after** the atomic commit; Phase 10's equivalent criterion runs while `sellHistory` still
  exists and cannot catch it. **The History-panel half of this gate is retired, not deferred**:
  Phase 0 confirmed `UI/Panels/History.lua` unreachable in both directions, so there is no panel to
  open and no Lua error to watch for — the grep proof in Phase 11's own exit criteria is what
  discharges that half, not an in-game check.
- **No deletion lands without Phase 0's written verdict line** for that file or function.
- **No approval-gated BagUI item lands without a recorded owner approval.** That now includes G9,
  whose subject file is `UI/OverlayFactory.lua`.

**Things no single phase owns.**
- **Commit discipline.** One logical fix per commit, conventional-commit format with the project's
  emoji prefixes. The decision, the alternatives weighed and the evidence go **in the commit
  message** — not into this plan and not into an ADR section (decision-records rule). Trailer
  convention in §5.
- **The `_G.InventoryManager` exposure** (`Core.lua:10`, `:754`) is why W2 and W3 are scored
  unbounded: another addon can read or write `IM.db` and call `IM:RegisterEvent`. No phase changes
  it (removing it would break the user's own console workflow), but every executor should know that
  a "impossible" state may have come from outside the addon.
- **`pcall` swallowing.** Several fixes (B4, B3) live behind per-section `pcall`s that hide errors.
  When a smoke check shows nothing rendering, check the debug ring buffer
  (`IM:GetDebugLogString()`) before concluding the code did not run.
- **The underlying audits' counts are unreliable, and so were two of this plan's own.** The audits
  said 5 charKey parse sites, 40 `hooksecurefunc` sites (30) and 1-of-25 closure-pattern modules
  (false in both directions); the brief's own finding total was 96 over 125 numbered entries until
  the conductor corrected it to **125**, and this plan now covers **127** — OQ-1 and OQ-2, neither
  of which any audit or review pass produced. Then recon said "24
  charKey sites" and the brief and this plan both transcribed it — over an enumeration holding
  **25** line entries, of which **18** are the defective greedy parse. Corrected throughout; the
  gate is now `rg 'match\("\^\(\.\+\)-"\)'` returning zero, which is what actually closes W3-13.
  **Trust the file:line evidence, count it yourself, treat Appendix A as the authority on which
  findings exist — and where a count and an enumeration disagree, re-derive both from the tree
  rather than picking one.**
- **Out of scope — state it and hold it.**
  - The two `pending_approval` plans already in `.claude/plans/active/` —
    **`auto-loot-mail-plan`** and **`bagui-dynamic-sizing-plan`**. Files untouched, status
    unchanged. User's words: "if they arnt apart of what you just audited i dont want it included.
    This was about the audit findings not finishing other plans." Noted only: this plan's mail
    findings edit code that `auto-loot-mail-plan` created.
  - **Any redesign of the bag UI.** Invisible fixes and approved individual changes only.
  - **Any migration backup mechanism** — no backup table, no `/im restore`, no release gate. User
    decision on record, asked twice, answered "just write it and ship it" both times. The residual
    risk this leaves is scored honestly as R2, signed HIGH per the RISK OVERRIDE block above (O2);
    the answer to it is not a backup, it is the Docker proof.
  - Edge resizing (G7) and `CustomCategories` in the bag view (G8) — new plans if wanted.
  - Localization of `ParseMoneyFromMessage` — deferral D1.
  - A true net-worth curve / sparkline — deferral D2.

---

## 4. Sustainment

- **Runtime**: WoW retail, The War Within, interface `120100`, Lua 5.1. No package manager, no
  dependencies, no external services.
- **Verification tooling**: Docker (daemon 29.7.2, user in the `docker` group) running
  `akorn/lua:5.1-alpine` — the only automated check available. In-game: `/reload`, `/im debug`,
  `IM:GetDebugLogString()`.
- **Fixtures**: a **copy** of the real `InventoryManagerDB.lua` from
  `WTF/Account/<ACCOUNT>/SavedVariables/` is the migration test input. Copy it; never point the
  harness at the live file. **Seven synthetic fixtures on top of it**, because the real file cannot
  be relied on to contain every case: a spaced-realm key, two colliding keys where one lacks
  `lastSeen`, a `transactions` row whose `src` is a non-character string (a vendor name or
  `"Unknown"`), which must come out byte-identical, **one row for each of the three `"Unknown"`
  shapes `Database.lua:216`'s two independent fallbacks can produce (`"Unknown-Unknown"`,
  `"Bob-Unknown"`, `"Unknown-Area 52"`), all byte-identical out, and a key whose realm is absent from
  `realmMap`, which must come out untouched and unmerged**. **Plus one non-synthetic input: the
  `(GetRealmName(), GetNormalizedRealmName())` pairs Phase 0 step 7 recorded** — the migration's
  `realmMap` and the only thing that ties its values to the API (Phase 11 step 9A). **Two fixtures from revision six are withdrawn
  with the consolidation merge**: the older-than-retention `sellHistory` row plus its already-copied
  mirror, and the `dbVersion = 1` database that existed only to prove the mapping extraction was
  behaviour-neutral. There is no extraction and no merge, so neither has anything to prove.
  **Re-scoped by Phase 0's realm observation (A14): these fixtures are now the SOLE coverage of the
  key-rewrite path, not "pathological cases" alongside a real-data check.** Both of the owner's real
  realms (`Warsong`, `Zul'jin`) are identity under `GetNormalizedRealmName()`, so `realmMap` maps
  each to itself and the real-data Docker run is a provable no-op on every key it touches — it
  cannot exercise the rewrite, the merge rule, the `"Unknown"`-class exemption or the unmapped-realm
  path at all. **A clean real-data run showing zero key changes is the *expected* result, not
  evidence the rewrite works.** No future executor may trim these seven fixtures as "redundant with
  the real-data pass" — they are not redundant with it, they are the only thing that runs the code
  the real data cannot reach. A future realm transfer, rename, or a second account with a
  non-identity realm reopens the question of whether the map still needs proving against a live
  case; until then, the synthetic fixtures carry that proof alone.
- **Credentials**: CurseForge publish credentials, already configured in `publish.sh`. Nothing new.
- **Test characters needed for the smoke checklists**: at least three characters, one of which has
  never been logged in with the addon (for W3-4 and W5-5), one on a spaced or connected realm (for
  W3-11), plus a guild with a bank the player can watch someone else use (for W2-14), a legendary
  or heirloom with a vendor price (W1-1), and a full mailbox (W1-4).

---

## 5. Command & Signal

- **Ownership**: single developer (patrick@vpmsolutions.com), direct commits to `main`. The
  conductor dispatches phases; the owner is the sole approver for every Phase 17A gate (G1-G9) and
  for the override block below.
- **Succession / cold-resume pointer.** To pick this plan up cold, read in this order:
  1. this `plan.md` — §3.2's ancestor table and §3.4's sequencing list are the load-bearing parts;
  2. `Appendix A` to find which findings are still open;
  3. `.claude/plans/active/audit-remediation/brief.md` for the full file:line evidence behind any
     finding (this plan compresses it; the brief does not). **Two exceptions: OQ-1 and OQ-2 are not
     in the brief and never were.** OQ-1 came from the owner, asked while reading revision five and
     answered in revision six, so its only evidence is Appendix B **L1** and §1's `Database.lua`
     terrain note. OQ-2 came from reading the owner's in-game debug log during Phase 0 execution,
     so its only evidence is Phase 3's evidence note and its Appendix A row. Do not conclude either
     is out of scope because the brief is silent on it, and do not conclude either is unresolved:
     OQ-1 is closed by an owner decision to accept the loss, OQ-2 by Phase 3's fix cross-checked
     against Phase 9;
  4. `git log --grep=audit-remediation` for every decision already made and why — **do this before
     relitigating anything**;
  5. `.claude/sessions/inventorymanager-state.md` for the last session's working context;
  6. `.claude/CLAUDE.md`, but only after Phase 18 — before then, several of its claims are the
     findings.
- **Audit trail**: commits carry the trailer `Plan: 2026-09-07-audit-remediation` and
  `Phase: <n>`. Decisions, alternatives weighed and evidence live in the commit body
  (decision-records rule). Where a decision has no file change (an owner declining a Phase 17A
  gate, an accepted override), record it with `git commit --allow-empty`.
- **`audit.md` sections in use**: none currently. If one is opened, the sections this plan would
  feed are *Risk overrides* (signatures and dates for the block below) and *Approval gates* (the
  nine Phase 17A decisions, G1-G9).

---

## RISK OVERRIDE — SIGNED 2026-09-07

Three residuals stand at HIGH and cannot be mitigated lower. All three are Floor-B classes, where
the rule fixes the floor at HIGH regardless of how good the mitigation is. **Signed by the owner on
2026-09-07 — see the acceptance block below the table, which records his words verbatim, the
redirect he was offered on O2 and declined, and the forfeit condition that voids this signature.**
The rows and their reasoning are unchanged since signing; any edit to a mitigation cell that lowers
a bucket requires re-signature. Surfacing this block was the planner's job; signing it is the
owner's, never the planner's or
the conductor's.**

**Three rows. There is no fourth, and no retired one hiding as a footnote.** Earlier revisions
argued at length about whether a fourth row (`R13`, the live key-format window) belonged here. That
argument is void: the window's mechanism was deleted when Phase 11 became atomic, so there is
nothing left to classify or to sign for. See §1's note. Do not reintroduce the row, the resolver it
mitigated, or the exemption argument that surrounded it.

| # | Risk | Why not mitigable below HIGH | Mitigations already applied | Revisit trigger |
|---|---|---|---|---|
| O1 | **R1 — auto-sell destroys an irreplaceable item.** Residual HIGH (prob D × sev I, floored). | Floor B: irreversible operations never score below HIGH. Item destruction has no undo beyond WoW's own buyback window, whose slot count the addon reads from `BUYBACK_ITEMS_PER_PAGE` rather than asserting, and severity cannot be reduced — a destroyed heirloom is destroyed. An offline harness (`.claude/tests/autosell/`) asserts the filter's branch logic against the real files; it cannot assert client behaviour, so the live-merchant smoke run remains the only proof of the shipped behaviour. | Quality floor wired above both the threshold and the junk-list branch and below the whitelist; nil-quality fails closed; `maxQuality` dropdown clamped to 4; default `autoSellEnabled = false`; first automatic sale per session gated behind a `StaticPopupDialogs` confirm; Phase 1's smoke checklist tests every `maxQuality` setting plus the junk-list and uncached-item cases. **Every mitigation in this list is ungated and ships in Phase 1.** The one gated item (G9, the bag sell-ring predicate) is display-only: the filter is the sole authority over whether an item is sold, so a declined or undecided G9 leaves a wrong ring, never a wrong sale. | Any future change to `Filters:ShouldAutoSell`'s branch order, or any addition of a new "always sell" override alongside the junk list. |
| O2 | **R2 — the v3 migration corrupts or destroys live SavedVariables.** Residual HIGH (prob C × sev I, floored). | Floor B: irreversible operation on irreplaceable data. WoW keeps no version history of SavedVariables. **The one mitigation that would drop severity — a backup table plus a restore command — was explicitly refused by the owner, twice, on the record ("just write it and ship it").** The conductor pushed back twice and dropped it. Offline verification reduces probability but cannot touch severity. | Migration written as pure functions over explicit inputs, **with the realm transform inside that contract rather than exempt from it**: stored keys are rewritten by a pure `opts.normalizeRealm` lookup over a Phase-0-derived `realmMap` — never by `GetNormalizedRealmName()`, which returns the *running* character's realm and would fuse every alt into one row — and the map's values are proven output-equal to the API for the owner's real realms before the commit exists (Phase 11 step 9A), with merges permitted only between map-verified keys and unmapped realms left byte-identical. **This is also what makes the Docker artefact honest**: every line of the pass, including the key rewrite, executes in the harness. Docker Lua 5.1 double-run deep-compare against a **copy** of the real SavedVariables, second run must be a byte-identical no-op; explicit assertions on character count, `sellHistory` absence from data **and** defaults, `ledgerCharFilter` absence plus `ledgerCharKey` validity, `mailHelper.pendingQueue` absence, per-table proof that every table the write-site grep placed in the pass was actually visited, and normalized `transactions.entries[i].char`; pathological cases for spaced realms and colliding keys with a missing `lastSeen`; `sellHistory` removed from `defaults` so `_mergeDefaults` cannot resurrect it; assertions that every `transactions.entries[i].src` matching a known character key is normalized and every other `src` is byte-identical; the never-replace-non-empty-with-empty rule from Phase 9; and one standing assertion that `#transactions.entries` is **unchanged** across the run, so no future edit can turn the pass into an inserting one. **Plus atomicity as a structural mitigation, not a procedural one**: the five reshape members — the producer change, the two raw `GetRealmName()` conversions, the `DB_VERSION` bump plus `_runMigrations` wiring, the `defaults` removal, and the `ledgerCharKey` reader conversion — are one commit, and the Docker proof is green before that commit exists, so there is no reachable intermediate state and no resolver whose later deletion could be forgotten. The two deletion-class members (the `sellHistory` reader and writer retirements) land in the preceding commit, which is gated on touching **no data** — a smaller atomic commit is a reviewable one, and a deletion has no disagreement window to protect. **And the migration's pass is derived from a write-site grep rather than from `defaults`**, which is what closes the `pendingQueue`-class hole a defaults-derived list cannot see. One **advisory** `cp` line in the release notes. **ONE LOSS INSIDE THIS RISK IS NOT MITIGATED AND IS NOT A DEFECT — it is destroyed by design, on the owner's decision, and the override signature covers it**: the v3 drop permanently destroys `sellHistory` rows older than `ledger.maxAgeDays` that have no counterpart left in `transactions` (survivors of the 100-entry count cap whose copies the age purge already removed). Revision six proposed a consolidation merge; revision seven withdrew it because the owner's retention setting already declares data past his window unwanted and rescuing those rows into the store that policy purges is circular. Recorded with all four fields as Appendix B **L1**. No merge, no backup, no retention override. | The owner changing his mind about a backup mechanism; OR the first report of a lost character or a doubled ledger after a 1.4.0 login; OR any future migration that merges or renames keys; **OR the discovery of a second store in this addon whose retention axis differs from the store it was migrated into — OQ-1's class, which no audit or review pass found**; OR any future edit that puts a WoW API call, or a derived string rule, inside the migration pass — that forfeits R2's `guard` bucket and returns the row to **EX-HIGH**, at which point this signature no longer covers it. |
| O3 | **R4 — gold movements booked twice, with the wrong sign, or not at all.** Residual HIGH (prob B × sev II, floored). | Floor B: money movement and financial records never score below HIGH. The ledger *is* the financial record, and its inputs are 30 `hooksecurefunc` edges plus 11 `PLAYER_MONEY` handlers whose set is runtime-dependent (four modules return early on settings or API absence), so the handler population cannot be enumerated statically. Silent under-reporting is unfalsifiable without per-source tracing. | One amount-keyed FIFO claim queue inside `IM:AddTransaction`, order-independent by construction, replacing every context-guessing guard (`IsInTrackedContext` deleted); arm-and-confirm against the matching `PLAYER_MONEY` delta so rejected actions book nothing; pure-function design tested in Docker including the shared-amount collision case; deterministic handler order from Phase 3; Phase 4/5/6/7 smoke checklists **count entries per action** rather than eyeballing totals. | The first observed ledger entry that does not correspond to a real action, or any real action that produces no entry, after 1.4.0; OR the addition of any new gold-moving tracker that does not route through `IM:AddTransaction`. |

**The Phase 1 harness does not move a bucket and does not require re-signature.** R1 is floored at
HIGH by Floor B (irreversible operations); the floor keys on severity, and a destroyed heirloom is
still destroyed. The harness lowers probability only. O1's rule that an edit to a mitigation cell
which LOWERS a bucket requires re-signature is therefore not triggered — recorded explicitly so the
next reader does not have to re-derive it. Two clauses in the row above were corrected on
2026-09-08 (the hand-written buyback slot count, and a claim that no such harness could exist);
the bucket, the reasoning and the signature are unchanged.

**Accepted by**: Patrick Rizzardi  **Date**: 2026-09-07

**Owner's decision, verbatim**: *"Approved — sign all three, go active"* — given after being shown
each row's residual tier, its why-not-mitigable reasoning, and the mitigations applied, and after
being offered the chance to redirect O2's mitigation (restore the backup table, add a dry-run
confirm, or add a release gate). He declined the redirect and signed as-is. **O2's severity is
accepted knowingly**: he was told in these terms that the one mitigation which would lower it is
the backup he refused twice, and that the Docker proof reduces probability only.

**Scope of this signature.** It covers O1, O2 and O3 as written above, including the by-design
`sellHistory` loss recorded in Appendix B **L1**. It does NOT survive the forfeit condition in O2's
revisit trigger: if any future edit puts a WoW API call or a derived string rule inside the
migration pass, R2 returns to **EX-HIGH** and this plan must be re-signed before that edit ships.

**G9's disposition, decided at the same time**: *"Gate it — show me before touching it."* Phase 1
ships its ungated steps; the `UI/OverlayFactory.lua` sell-ring predicate waits for the owner in
Phase 17A. Per O1's mitigation cell this is display-only and leaves no path to a wrong sale.

---

## Appendix A — Coverage index

Every numbered finding in the brief — **125**, per the brief's corrected count — **plus OQ-1 and
OQ-2**, neither of which came from the audits or a review pass, for a total of **127** — mapped to
exactly one phase, or to two labelled work items in two phases, both of which must close (see the
note below the table). **This table is the authority on completeness.**

| Wave | Items | Phase |
|---|---|---|
| W0 | 1, 2, 3, 4, 5, + the `History.lua` reachability proof, + the realm-normalization pairs (P0 step 7 — not a brief finding; it is the input P11's `realmMap` and step 9A cannot be built without, so it is catalogued here rather than left uncounted) | **P0** |
| W1 | 1 (work item 1 of 2: the filter-side quality floor + nil guard), 2, 3 | **P1** |
| W1 | 4, 5, 6 | **P2** |
| W2 | 1 | **P3** |
| **OQ-2** | **Four startup paths re-enter their own work on every login with no completion latch: BagUI's override bindings clear/re-set five times in ~2s (compounding B12), `BagData`'s full refresh fires twice, `InventorySnapshot`'s startup scan runs three times in ~1s, `NetWorth`'s gold-update logging fires three times in the same second. Resolution: a single login-settle latch (Phase 3 step 3), keyed on completion rather than on firing, so `InventorySnapshot`'s scan stays re-runnable when Phase 9's `ScanBags` fix (step 5) reports a real failure — closed by the cross-check exit criterion both phases carry, not by either phase's `git show` alone.** **Provenance: found by reading the owner's in-game debug log during Phase 0 execution — by no audit and no review pass.** **Boundary with B8** (Phase 17): B8 debounces an interval-triggered rebuild recurring during play (`BAG_UPDATE_DELAYED`/`PLAYER_EQUIPMENT_CHANGED` firing repeatedly while the user plays); OQ-2 is a one-shot re-entry at a single event (login) across four unrelated modules, fixed by a completion latch, not a debounce interval — same producer class, different trigger, different mechanism, so none of the four instances is closed by B8's fix. | **P3** |
| W2 | 2, 3, 4, 5, 6, 7, 17 | **P4** (one ancestor: the claim queue) |
| W2 | 8, 9, 10, 11 | **P5** |
| W2 | 12, 13, 15, 16, 19, 20 | **P6** (20 = deferral D1 + in-scope guard) |
| W2 | 14, 18 | **P7** |
| W3 | 1, 4 | **P8** |
| W3 | 2, 3, 5 (one ancestor), 6, 7 (one rule), 15 | **P9** |
| W3 | 8 (work item 1 of 2: `SellHistory.lua`'s own writers + `ItemLock.lua:157`), 9 (one ancestor) | **P10** |
| W3 | 10, 11, 13 (one ancestor), 12, 14, 8 (work item 2 of 2: the legacy history writer family + its nine Tracking/`Core.lua` call sites) | **P11** — the atomic phase: producer + migration in one commit |
| W4 | 11 (work item 1 of 2: the `ledgerCharFilter` → `ledgerCharKey` field, migration and reader) | **P11** — pulled into the atomic commit (it is the reshape) |
| **OQ-1** | **The two stores expire on different axes (`sellHistory` by count, `transactions` by age), so dropping `sellHistory` destroys rows that exist nowhere else.** **Resolution: CLOSED BY OWNER DECISION TO ACCEPT THE LOSS** — no merge, no backup, no retention override; the drop proceeds and the rows go. Recorded with all four fields as Appendix B **L1**. **Phase 0 confirmed `UI/Panels/History.lua` unreachable in both directions, so there is no visible consequence at all** — no view's span shortens, because no view exists — noted in Phase 11's criteria and Phase 19's release notes. **Closed by a recorded decision, NOT by silence and NOT by a fix** — Phase 19's gate must read the L1 entry, not just the absence of open work. **Provenance: found by the owner's question — asked while reading revision five, answered in revision six — not by any of the five audits and not by any of the four review passes.** Descends from W3-8 (same store, same retirement) but is a distinct defect with a distinct resolution | **P11** — the accepted consequence of step 5's drop |
| W3 | 16, 17, 18 | **P12** |
| W4 | 6 (work item 1 of 2: additions), 7 (1 of 2: addition), 8 (1 of 2: the two added helpers) | **P13** |
| W4 | 1, 2 (one ancestor), 3, 4, 5, 6 (2 of 2: consumption), 7 (2 of 2: consumption), 8 (2 of 2: consumption + dead `SetTextColor` removal), 9, 10, 11 (2 of 2: `typeIndex`/`dateIndex`), 12 | **P14** |
| W5 | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 | **P15** (2 = partial + deferral D2; 9 = delete both) |
| W6 | 14, 15, 16 (work item 1 of 2: the pool), 18 (1 of 2: the key) | **P13** |
| W6 | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16 (2 of 2: consumption), 17, 18 (2 of 2: consumption), 19, 20 | **P16** |
| W-BagUI | B3, B5, B4, B7, B8, B9, B14-invisible, B12, B13, B15-naming, B15-lifecycle, RecentItems diagnostic, and the two recorded invariants (ItemLock hook coupling, `ITEM_CLASS_NAMES`) | **P17** |
| W-BagUI | B1 (G1), B2 (G2), B6 (G3), B10 (G4), B11 (G5), B14-visible (G6), edge resizing (G7), `CustomCategories` (G8) | **P17A** — gates, not work |
| W1 | 1 (work item 2 of 2: the bag sell-ring predicate at `UI/OverlayFactory.lua:462`) | **P17A** — gate **G9** |
| W7 | 1, 2, 3, 4, 5, 6, 7, 8, 9 | **P18** |
| Release | interface edit, publish gates, one 1.4.0 publish, advisory `cp` | **P19** |

**EIGHT findings are one finding with two work items each — W4-6, W4-7, W4-8, W4-11, W6-16,
W6-18, W3-8 and W1-1.** For the five W4/W6 factory ones the producer (a factory addition or a new
`UI.layout` key) lands in P13 and the consumption (the call sites actually switching onto it) lands
in P14 or P16. Three splits are different in kind and are named individually, because each exists
to keep a field's readers and writers in one commit:
- **W1-1**: item 1 is the filter-side quality floor and nil guard (P1, ungated, and the half that
  actually protects the asset); item 2 is the bag's own rendering predicate (gate **G9** in P17A,
  owner's call).
- **W3-8**: item 1 is `SellHistory.lua`'s own duplicate writers plus `ItemLock.lua:157` (P10);
  item 2 is the legacy history writer family — `IM:AddHistoryEntry`, its six wrappers and the nine
  surviving `LootTracking`/`VendorTracking`/`AuctionTracking`/`Core.lua` call sites (**P11's
  retirement commit**, step 12, immediately before the atomic commit: a deletion needs its
  accessors retired no later than the deletion, not inside the same commit as the reshape).
  **OQ-1 is NOT a third work item of W3-8** — it descends from it (same store, discovered while
  reasoning about the same retirement) but it is a separate row with a separate resolution, and
  closing W3-8 does not close it: W3-8 closes on two `git show`s, OQ-1 closes on the owner's
  recorded accept.
- **W4-11**: item 1 is the `ledgerCharFilter` → `ledgerCharKey` field, its migration **and** its
  reader at `UI/Dashboard.lua:411,584,607,618-630` (P11's atomic commit); item 2 is the latent
  `typeIndex`/`dateIndex` half (P14), which carries no character key and needs no migration.
In every case this is a legitimate work split, not two findings, and it is **not** two chances to
close half of one: **a row is closed only when both work items are closed.** Phase 19's coverage
gate reads it that way — an addition with no consumer is an open row, because nothing renders
differently and the finding's symptom is still live. For W1-1 specifically, a recorded owner
**decision** on G9 closes item 2; silence does not.

**Count check, re-verified in revision six. The total is now 126: 125 brief findings + OQ-1.**
The 125 is unchanged and re-derived the same way as before — the collapse of the old P10 and P12
into P11 moved two rows onto one line and merged no finding (W3-10, W3-11, W3-12, W3-13 and W3-14
are all still present and individually named); G9 added no finding, it re-homed the second half of
W1-1, which was already counted inside W1-1; **splitting W3-8 and W4-11 across two phases added no
finding either** — each was already counted once, and re-homing half of it changes where the work
lands, not how many findings exist. Two-work-item findings stand at eight.
**What revision six changed about the count, and what it did not.** OQ-1 is **+1**, because it is a
distinct defect: the brief's W3-8 says to retire the legacy store's writers and its W3-10 says to
drop the key, and *neither* says anything about the rows that exist only in that store — so it is
not a re-scope of an existing row and it cannot be discharged by closing one.
**Splitting the atomic commit into a retirement commit plus a five-member commit added ZERO
findings** — it re-homes work that was already counted (W3-8 item 2 moves from the atomic commit to
the commit before it) and changes no row's existence.
**What revision SEVEN changed about the count: nothing. The total stays 126.** Withdrawing the
consolidation merge removed *work*, not a finding. OQ-1 was a real defect and is still a real
defect; it is now closed by an owner decision to accept its consequence rather than by a fix, and a
finding closed by decision is closed, not deleted. **A row removed from the table because the answer
turned out to be "accept it" would be exactly the silent discharge R11 exists to catch.**
**What revision EIGHT changed about the count: nothing. The total stayed 126.** It corrected *how*
W3-10 normalizes stored keys (a pure injected transform instead of a WoW API call that would have
merged every alt into the running character — see Phase 11 step 6), widened the `"Unknown"`
exemption from one literal to the class of three shapes `Database.lua:216` can produce, and added
two mechanism steps (Phase 0 step 7's realm pairs, Phase 11 step 9A's equality proof). **A
correction to a finding's fix is not a new finding, and a mechanism step is not a finding at all** —
both live inside W3-10/W3-11, which were already counted.
**What revision NINE changed about the count: +1, to 127.** Revision eight's login-storm evidence
(the observed BagUI-binding/`BagData`/`InventorySnapshot`/`NetWorth` re-entry) was wrongly folded
into Phase 3's scope as work with no coverage-index row — a **coverage-index correction, not a
newly-discovered defect**: the four startup-path observations were real remediation work from the
moment they were first written down in Phase 3, they simply had not been given a row. **OQ-2** is
that row now: same defect, same fix (Phase 3 step 3, cross-checked against Phase 9's exit
criteria), now indexed so Phase 19's coverage gate can verify it closed and a future reader can see
it was ever decided rather than quietly absorbed into a phase's prose. This is the exact shape R11
exists to catch — real remediation work with no coverage-index row — caught here against this
plan's own earlier revision, not against the brief.
**127 is the number Phase 19's coverage gate reads.**

**Nothing is dropped.** Two items resolve to documented deferrals (Appendix B, D1-D2), both with all
four fields, and one resolves to a documented **accepted loss** (Appendix B, L1), also with all four
fields. Seven items resolve to owner-decision gates (P17A G1-G6 and G9) plus two questions
(G7, G8) — gates are work-not-done-yet, not discharges; a declined gate is recorded with a revisit
trigger.

## Appendix B — Future Requirements / Revisit

### Deliberate accepted losses (all four fields, per the no-duct-tape rule)

**L1 — Sell-history rows older than the retention window are destroyed by the v3 drop (OQ-1).**
- **WHAT IS LOST**: every entry in `db.global.sellHistory.entries` whose `timestamp` is older than
  `ledger.maxAgeDays` (default 30, `Database.lua:78`) **and which has no counterpart left in
  `transactions.entries`**. Concretely: survivors of the 100-entry count cap (`maxEntries = 100`,
  `:72`, trimmed at `:399-401`) whose v1→v2 copies `IM:PurgeOldEntries` (`:799-822`) already deleted
  by age. Phase 11 step 5 drops the store and they go with it. The count is unknown and deliberately
  unmeasured (assumption A13).
- **WHY (the owner's reasoning, recorded because it is sound and not merely a preference)**: his
  retention setting is a **declaration that data older than 30 days is unwanted**. Those legacy rows
  survived by an accident of the count cap, not by his choice. Rescuing them into `transactions` —
  the store his own retention policy purges 5 seconds after login — is circular: the plan would
  write rows specifically so a policy he set could delete them, or else quietly widen the policy on
  his behalf. The conductor proposed the consolidation merge in revision six and **withdrew it on
  the merits**, not under pressure.
- **COST IF IT TURNS OUT TO MATTER**: **unrecoverable.** There is no backup (owner decision, twice
  on the record) and WoW keeps no version history of SavedVariables. The rows are gone the moment the
  atomic commit runs its migration on his database. No later fix exists at any price; the only
  mitigation would have had to be taken before the drop.
- **TRIGGER TO REVISIT**: the owner asking for sell history older than his retention window after
  1.4.0 — at which point the answer is that it is gone and the discussion is about going forward;
  **OR** any future change that makes `transactions` retention *longer* than the legacy cap's reach
  (a "Forever" default, an age purge removal, a per-type retention scheme), because that is the state
  in which the two stores' lifetimes would no longer have diverged and a consolidation would have
  been non-circular.

### Deferrals (all four fields, per the no-duct-tape rule)

**D1 — Localization of `IM:ParseMoneyFromMessage` (W2-20).**
- **WHAT**: `IM:ParseMoneyFromMessage` (`Core.lua:715-727`) matches only English "gold"/"silver"/
  "copper", and `LootTracking.lua:142` gates on `find(msgLower, "loot")`. Non-enUS clients get no
  loot entry from the chat path.
- **WHY (concrete tradeoff)**: correct localization needs `GOLD_AMOUNT`/`SILVER_AMOUNT`/
  `COPPER_AMOUNT` global-string pattern inversion plus a locale-specific loot-message pattern for
  each of ~11 client locales, and **it cannot be verified from this machine** — the owner runs an
  enUS client and there is no way to produce a deDE or zhCN chat string to test against. Shipping
  unverifiable pattern-matching over money strings would be a worse defect than the honest gap,
  because a partially-matching pattern books a *wrong amount* rather than none.
- **COST TO FIX LATER**: ~2-4 hours plus access to one non-enUS client for verification; contained
  entirely in `Core.lua:715-727` and `LootTracking.lua:142`, with no data migration and no
  dependents.
- **TRIGGER**: the first non-enUS user report, OR the owner switching client locale, OR any
  CurseForge localization request on project 1422035.
- **In-scope guard taken now** (live exposure before the trigger): a one-time **`IM:PrintError`**
  at login when `GetLocale() ~= "enUS"`, naming the consequence — **not `IM:Debug`**, which prints
  nothing without `/im debug` and is filed as a defect elsewhere in this same plan (W6-8); a guard
  the user cannot see is not a guard. Plus Phase 4's claim queue means a non-enUS user now gets
  **one** honest unclaimed entry instead of one wrongly-typed duplicate.

**D2 — True net-worth history and sparkline (W5-2, second half).**
- **WHAT**: no gold history is stored anywhere (`goldHistory` appears nowhere;
  `characters[charKey]` holds only current `gold`), so a real net-worth *curve* is impossible.
  Phase 15 ships the honest substitute — a 7-day gold-flow delta from `IM:GetLedgerStats` — and
  defers the ring buffer plus sparkline.
- **WHY (concrete tradeoff)**: a real curve needs a new persisted table written at logout
  (`NetWorth:OnPlayerLogout`, `:136`), which means **a new schema key and therefore a v4 migration**
  — and Phase 11's v3 migration is already the plan's highest-residual risk (O2, unbacked-up by
  owner decision). Adding a second schema change in the same release multiplies that exposure for a
  feature that produces no data until several logouts have accumulated anyway.
- **COST TO FIX LATER**: ~3-5 hours — a capped ring buffer append at logout, a v4 migration that
  only *adds* a key (strictly lower risk than v3's rewrite), and a sparkline renderer. No rework of
  anything Phase 15 ships; the delta line stays as the at-a-glance figure.
- **TRIGGER**: the next schema-changing release (fold the key in there), OR the owner asking for
  a trend chart, OR the ledger's retention window being shortened such that the 7-day delta stops
  being derivable.

### Recorded MEDIUM residuals (gate: pass, but record with a trigger)

**Phase 1 residuals, recorded at seal 2026-09-08.** Everything below is a gap in *verification*,
not a known defect: the code each item describes was graded correct by independent reviewers, and
what is missing is the mechanism that would catch it regressing. Written here rather than left in
code comments because a residual whose only record is a comment is one refactor from gone.

- **P1 — the fingerprint's table list is hand-maintained one level up (residual MEDIUM).**
  **WHAT**: `_AutoSellFingerprint` recurses wholesale into the settings tables it is given, so a new
  *key* inside one is covered the moment it exists; the list of *tables* is written by hand. A new
  top-level `db.global` table that `Filters:ShouldAutoSell` learns to read is hashed by nobody.
  **WHY accepted**: the mutation battery enforces "the fingerprint moves iff some verdict can move"
  over every table currently read, which is the strongest check available without a lint or CI path
  in this repo. **COST**: a stale grant sells items the user protected, unattended — R1's own
  failure mode. **TRIGGER**: any change giving `ShouldAutoSell` a new top-level `db.global` read;
  the battery case lands in the same commit, or the list is rebuilt by a write-site grep.

- **P2 — five filter tiers are stubbed inert, so the battery's iff is vacuous over them
  (residual MEDIUM).** **WHAT**: soulbound, warbound, uncollected-transmog, toy and equipment-set
  evaluation answer constants in `wow_stub.lua`. Independently measured: making any of those five
  *stop protecting* leaves the suite green. **WHY accepted**: each needs a live client API with no
  offline equivalent; modelling them would assert the stub's behaviour, not WoW's. **COST**: a
  protection tier could be deleted and no offline check would notice. **TRIGGER**: Phase 0 API
  answers making any of the five stubbable faithfully, or the first observed sale of an item one of
  those tiers should have protected.

- **P3 — the approved-sale exemption is authenticated, not attributed to a human
  (residual MEDIUM).** **WHAT**: the one-shot nonce proves an approved list came from
  `RequestSellConsent` and is spent once — it does not prove a *person* clicked Sell.
  `AutoSell:ConfirmApprovedSale` and `GrantSessionConsent` are reachable on the public module table
  via `_G.InventoryManager`. **WHY accepted**: Lua addons share one address space with no memory
  protection, that same table already exposes `SellJunk()` as an unconditional manual vendor, and
  the window is narrow (auto-sell on, merchant open, prompt live and unanswered). **COST**: one
  unattended sale of exactly the list the dialog quoted, plus a session grant never given.
  **TRIGGER**: any new caller of `ConfirmApprovedSale` outside the dialog's `OnAccept` — at which
  point both become file-local, reachable only through the dialog definition.

- **P4 — the offline suite does not exercise the item-data event path (residual MEDIUM).**
  **WHAT**: the `GET_ITEM_INFO_RECEIVED` registration, its stale-token debounce, the listener
  broadcast and the waiter registry are each individually deletable with the suite green; only the
  2.0s deadline fallback is driven. **WHY accepted**: the tiers above it are covered and the
  timeout path is the one that fails closed. **COST**: a regression in the data-arrived path shows
  up in-game as a popup that never fills in, not as a wrong sale. **TRIGGER**: any edit to the item
  data signal, or a report that the Auto-Sell popup stays on "Loading item data…".

- **P5 — `UI/Panels/AutoSell.lua` and `Modules/TooltipInfo.lua` are graded by reading source, not
  by running it (residual MEDIUM).** **WHAT**: the dropdown's derivation is checked with substring
  searches over an unloaded file — appending index entries past the floor to `QUALITY_ORDER` leaves
  the suite green, so the dropdown can again promise a threshold the filter refuses. `TooltipInfo`
  is not loaded at all. **WHY accepted**: both need the UI layer stubbed, which is materially more
  surface than the filter path required. **COST**: UI promising what the filter refuses — a lie in
  the interface, never a wrong sale, since the floor is independent. **TRIGGER**: the next phase
  that edits either file, or the UI layer becoming loadable offline.

- **P6 — the expected-check-count pin is blind to a one-for-one swap (residual MEDIUM).**
  **WHAT**: 35 conditional emission points exist; exactly one can cancel to zero, and it guards a
  load-bearing assertion. Observed live during the final round. **WHY accepted**: not silent — the
  helper always prints a named failure, so nothing has ever hidden behind it. **COST**: the pin
  promises "every expected check ran" and delivers "the total is unchanged". **TRIGGER**: any new
  conditionally-emitted check, or the pin being relied on as the sole evidence a case executed.

- **R3 — account-shared data loss (residual MEDIUM).** The guards make a bad write improbable, not
  impossible, and the values remain a cache of server-authoritative data. **Trigger to revisit**:
  any observed warband gold or item value that drops without a corresponding withdrawal, or a
  `warbandBankGoldUpdated` timestamp that advances while the value is 0.
- **R6 — `UI/Core.lua` fence breach (residual MEDIUM).** The mitigation is discipline, which scores
  zero. **Trigger**: the first time the bag window's column count changes unexpectedly, or any
  change request that cannot be satisfied additively — at which point the mirrored constants in
  `BagUI/Core.lua:126-134` should be replaced by a single exported accessor from the factory (a
  real engineered fix, out of scope here because it edits fenced geometry).
- **R7 — deleting code reachable only by dynamic string lookup (residual MEDIUM).** **Trigger**:
  any runtime "attempt to index a nil value" from `UI/Panels/Selling.lua:53`, or the next time a
  panel is added — at which point `UI.Panels[panel.module]` should be replaced by an explicit
  registration table with a load-time assertion.
- **R10 — client stutter and frame growth (MEDIUM until G1 is approved, LOW after).** **Trigger**:
  owner declines G1, in which case the hidden-window rebuild stands and the debounce from B8 is the
  only mitigation.
- **R11 — a finding silently dropped, a plan-asserted set found incomplete, or a defect class no
  pass found (residual MEDIUM).**
  **Triggers**: any Appendix A row that cannot be closed at Phase 19; the discovery of a numbered
  brief finding absent from Appendix A; a fourth missing member of a completeness-critical set;
  **or a second OQ-class finding — a defect the owner finds by asking a question about work this
  plan already described as settled.** OQ-1 is the first, and its diagnosis is specific enough to
  act on: every pass reasoned about the two stores' *shapes* and none about their *lifetimes*. **The
  standing question this adds to any store retirement or data consolidation in this plan: what
  deletes rows from each side, on what axis, and can one side outlive the other?** The mitigation is
  a derivation rather than a list (Phase 11 steps 2-3), but it scores
  `human` — a grep nobody runs protects nothing. **If a fourth member is found anyway, the
  diagnosis is not "add it to the list": it is that the derivation step was skipped or its output
  was never written down, and the fix is a mechanical one** — a `.luacheckrc`-style pre-commit grep
  or a harness assertion enumerating `IM.db.global.*` write sites, which is out of scope here only
  because no lint or CI path exists in this repo today.

### Defaults measured once, and therefore carrying a trigger

- **The ledger's `maxEntries` cap default (W3-16, Phase 12 step 1).** **WHAT**: the cap's default is
  chosen by reading the row count the owner's own `ledger.maxAgeDays` window currently holds, so the
  cap is a ceiling against runaway growth and never a second, tighter retention policy. **WHY it is
  a measurement and not a rule**: there is no formula — the right number depends on his play rate,
  and a round guess either under-cuts his retention setting (silent oldest-first data loss he did not
  ask for) or is so large it protects nothing. **COST IF IT DRIFTS**: oldest-first row loss inside a
  window the owner declared he wanted kept; recoverable only going forward, never backward.
  **TRIGGER TO REVISIT**: the cap becoming the binding constraint rather than the age purge — i.e.
  the cap dropping a row whose age is still inside `maxAgeDays`, which Phase 12 step 1 makes
  observable with a once-per-session `IM:PrintError`. Raise the cap, or make it derived rather than
  fixed, at that point.

**No R13 entry, deliberately.** The live key-format window it scored does not exist any more:
Phase 11 lands the producer change and the migration in one commit. A residual with no mechanism is
not "recorded with a trigger" — it is deleted. **Retiring it did cost something, though, and that
cost is now paid in a different currency**: the retired gate was the plan's only forced walk of
character-keyed **write** sites, and its removal is why three review rounds each found a different
missing member of a set this plan had merely listed. Phase 11 steps 2-3 replace that function with
grep derivation. The two things worth carrying forward are *rules*, not risks: **any future change
to `IM:GetCharacterKey`'s output must land in the same commit as the migration that rewrites the
stored keys**, and **a migration commit carries every reader and every writer of every field it
touches**. Both belong in CLAUDE.md's character-key section (Phase 18 step 9), where they are
standing instructions rather than open risks.

### Recorded decisions that were deliberately NOT taken

- **Guild bank contents in net worth (W2-14)** — not added in this release. It is shared property
  the user does not own outright, and a personal net-worth total containing it is exactly the
  confidently-wrong number this plan exists to remove. **Trigger**: the owner asking for guild bank
  tracking, at which point key it `guildBanks[guildName]` with a `lastSeen` as the finding
  specifies.
- **A migration backup mechanism** — refused by the owner, twice, on the record. Not re-added. The
  residual is O2 above.
- **Consolidating `sellHistory` into `transactions` before the drop (revision six's merge) —
  PROPOSED AND WITHDRAWN, on the merits, by owner decision.** Revision six correctly diagnosed that
  the two stores expire on different axes — `sellHistory` capped **by count** (`maxEntries = 100`,
  `Database.lua:72`) and `transactions` purged **by age** (`ledger.maxAgeDays = 30`, `:78`;
  `IM:PurgeOldEntries` at `:799-822`) — so some legacy rows exist only in the legacy store. It then
  proposed merging them forward. **The merge does not save them**: `PurgeOldEntries` runs 5s after
  the next login and deletes exactly the rows whose distinguishing property is being older than the
  window, so the merge only "works" paired with widening a retention setting the owner chose. The
  owner's answer: his setting already declares that data unwanted, the rows survived by a count-cap
  accident rather than by his choice, and rescuing them into the store his policy purges is
  circular. **Do not re-add the merge, its `_legacyEntryToTransaction` extraction, its six
  assertions, its two fixtures, or the "set Data Retention to Forever" pre-flight.** The loss is
  recorded as L1 above with all four fields. **Trigger**: L1's trigger, and no other. **Provenance,
  recorded because it says where this plan's blind spots live**: found by the owner's question
  ("the sell history itself isnt being removed right just revamped?") — asked while reading revision
  five, answered in revision six — not by any of the five audits
  and not by any of the four review passes — every pass reasoned about the two stores' *shape* and
  none about their *lifetime*.
- **The 25-file `local module = self` sweep** — cancelled, because the rule is a Lua no-op
  (W7-1, Phase 18). This is a saving, not a deferral: there is nothing to revisit.
- **Restoring the eight `.analysis/` report files** — not done; references stripped instead
  (W7-4), per the decision-records rule. **Trigger**: none. Recreating them recreates the drift.
- **Splitting the character-key producer change from the v3 migration, with an `IM:GetStorageKey`
  read-compat resolver bridging the gap** — tried across three review rounds, abandoned by owner
  decision. Each round found a *different* live defect in the gap and each patch opened the next
  one, which is the signature of guarding a window instead of deleting it. **Trigger**: none.
  Reinstating the split reinstates all four defect classes at once; the correct answer is the
  standing instruction now in CLAUDE.md. Rounds and evidence:
  `git log --grep=audit-remediation`.
- **Iterating over a snapshot to fix the dispatcher's mutation-during-iteration hole (Phase 3
  step 2)** — rejected on the mechanism, not on taste. `CurrencySearch`'s second `ADDON_LOADED`
  handler registers inside `OnEnable`, which runs *during* the bootstrap dispatch, so a snapshot
  taken at dispatch entry cannot contain it: the handler still never runs and both of the phase's
  instruments read identically before and after. Deferred removal is required. **Trigger**: none.

## Appendix C — Factor sweep

Every factor considered; an applicable one earns a risk row and a phase mitigation, an
inapplicable one collapses to a one-line why. Nothing dropped silently.

| Factor | Disposition |
|---|---|
| **Security** | N/A — sandboxed WoW client addon: no network, no credentials, no untrusted input beyond Blizzard's own API. The one adjacent surface is tainted chat strings, already `pcall`-wrapped (`Core.lua:715,734`) and left that way. `_G.InventoryManager` exposure is noted in §3.4 as a known, deliberate hole in the owner's own workflow. |
| **Performance (CPU)** | Addressed — R10. P12 (O(n) insert → tail append), P14 (pooling on all three Dashboard paths), P16 (shared row pool), P17 (B7 debug-argument evaluation, B8 debounce, B9 dead frames, B14 pool growth). One CPU cost is *declined* rather than accepted silently: G9's option 2 would compute `isSellable` unconditionally per bag item, adding a `ShouldAutoSell` call per item per refresh in the same file B7/B8 are cheapening — named in G9 so the owner trades it knowingly. |
| **Performance (memory)** | Addressed — R10. The permanent leaks are the `SetParent(nil)` orphan loops (P14) and destroy-and-rebuild rows (P16); 200+ never-drawn `_imOverlay` frames die in P17. |
| **Accessibility** | Addressed — R12. Every colour-carried meaning also carries a glyph or word: `↑ +142,000g`, `12.4%`, `12d` staleness, `6 by quality · 2 on junk list`, `N stacks · M items`. P13 adds a real disabled-button appearance (contrast, not just colour). **One residual accessibility gap is named rather than fixed**: the bag's overlay rings are colour-only by construction (lock / mail / sell / unsellable), and changing that is a visible bag change behind G4/G9 — recorded, not silently dropped. |
| **PII / privacy** | N/A — no personal data. Character and realm names are game handles, stored locally in the owner's own WTF folder and never transmitted. |
| **Compliance** | N/A — no regulatory regime applies to a personal WoW addon. The one adjacent constraint is Blizzard's addon policy (no automation of gameplay for advantage, no protected-function abuse); P17's B12 combat-lockdown guard moves *toward* compliance, and nothing in the plan adds automation beyond what already ships. |
| **SEO** | N/A — no web surface. The CurseForge listing is unchanged by this plan. |
| **Docs** | Addressed — all of P18, plus the CLAUDE.md sentence P17 step 11 owes about `UI.*` file-scope registration, and the **five** standing character-key instructions P18 step 9 owes — producer change and migration ship in one commit; readers-and-writers on a reshape; enumerate keyed persistence by write sites; ask the store-lifetime question; and **`GetNormalizedRealmName()` normalizes the current character's realm only, so a stored realm is looked up in a verified table or left alone, never derived**. |
| **Reuse / DRY** | Addressed — the six ancestors in §3.2 exist for this reason, plus P7's extracted snapshot/diff helper, P13's factory additions replacing a 60-line copy-paste, and P16's `UI:CreateQueuePopup` hoist. **One DRY extraction was proposed and is NOT taken**: revision six hoisted the v1→v2 legacy-entry field mapping into `_legacyEntryToTransaction` so the consolidation merge could share it. With the merge withdrawn the mapping has exactly one caller, so the extraction is a refactor of an already-shipped migration path bought for nothing — P11 step 4 says leave the v1→v2 block untouched. DRY earns its keep at two consumers, not one. |
| **Type safety** | Addressed as far as Lua permits — nil-contract guards are the substitute: W1-1's nil-quality fail-closed, W3-4's nil `charData`, B3's `or 0` slot counts, B4's non-positive-width rejection, and W3-1's `nil`-is-UNKNOWN rule. The recurring producer is Lua's truthy `0` (W3-5 scanned bag 5 forever because `GetContainerNumSlots(5)` returning `0` is true) — called out in P9. **One type-confusion hazard is eliminated structurally rather than guarded**: a persisted field whose *type* changes (number-index → string-key) cannot be made safe by a nil check, because the wrong type is present and truthy — `chars[charIndex - 1]` on a string key raises rather than falls through. P11 step 8 therefore **renames the field** (`ledgerCharFilter` → `ledgerCharKey`) instead of retyping it, so a stale value of the old type is unreachable by name. The same rule applies to any future field whose type changes. |
| **Idempotency** | Addressed — P11 is built around it, with the Docker double-run as the proof and the v1→v2 non-idempotent migration as the named precedent not to repeat. Also P9's never-replace-non-empty-with-empty rule and P4's arm-and-confirm (an unconfirmed pending expires and books nothing). **The lesson revision six paid for, kept as a standing rule now that the code that provoked it is withdrawn**: a double-run proves idempotency only for code whose *input still exists* on the second run. Anything guarded solely by a version stamp — as v1→v2 was when it duplicated — is unproven by a double-run and needs its own same-input assertion. P11's v3 pass is safe here only because it never inserts, which is why "`#transactions.entries` unchanged" is asserted directly (P11 step 11). **The realm rewrite earns the same treatment rather than trusting the stamp**: `realmMap`'s keys are raw realm strings and its values normalized ones, so an already-migrated key misses the map and cannot be transformed twice — asserted as key/value-set disjointness (P11 step 11(d)), not assumed. |
| **Error handling** | Addressed — W6-4 (silent dead repair branch), W6-8 (invisible mail failures), W2-7 (rejected actions booked as real), B4 (`pcall`-swallowed render errors), RecentItems diagnostic. The pattern throughout: name the cause and the next step, via `IM:PrintError`, not `IM:Debug`. |
| **Observability / logging** | Addressed — P17's `IM:IsDebug()` predicate makes the debug path cheap enough to keep and use; `ItemButton.lua:289-303`'s dump is repaired rather than deleted; the 500-line ring buffer (`IM:GetDebugLogString()`) is the primary instrument in every smoke checklist. P4's smoke checks read per-source traces rather than totals, precisely because silent under-reporting is otherwise unfalsifiable. |
| **Races / TOCTOU** | Addressed — R5 and R8. P3 (nondeterministic handler order, mutation-during-iteration), P2 and W6-9 (async `SendMail` vs synchronous loop vs a 1s timer), P4 (claim windows against async `PLAYER_MONEY`), W2-12 (snapshot-vs-sale ordering — refuted as a live race but fixed at the right site anyway), W2-18 (frame-open-time detection vs process-time), B12 (combat lockdown between clear and re-set). |
| **Resource cleanup** | Addressed — the `SetParent(nil)` orphan loops (P14), destroy-and-rebuild rows (P16), dead `_imOverlay` frames and the `{...:GetChildren()}` allocation per `ReleaseAll` (P17), and `inventorySnapshots` never pruned for deleted characters (P11's per-row delete). |
