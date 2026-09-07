# BRIEF: InventoryManager audit remediation

Assembled by the /plan conductor from five completed audits plus one OPORD recon pass.
This is the planner's input. Tier is **OPORD** (locked, see Tier).

---

## Mission

Remediate every finding from five completed audits of the InventoryManager WoW addon — asset-loss
bugs, ledger accounting defects, account-shared data corruption, dashboard correctness, UI factory
debt, mail/vendor flow defects, custom-bag-UI defects, and documentation drift — in dependency
order, with nothing deferred to a backlog, shipping as a single 1.4.0 release.

## Commander's Intent

The user's words: "we fix it ALL" and "batch the duct tape." He invoked the no-duct-tape rule
explicitly and rejected a triage list. Every finding below gets a home in a phase. A finding may
be *sequenced* late; no finding may be *dropped*, and no finding may be closed with a documented
deferral unless the planner names all four deferral fields and the trigger is a real event.

Two classes of defect drive the ordering:
1. Defects that destroy property the user cannot recover (irreplaceable items, account gold
   history). These come first regardless of effort.
2. Defects that make numbers wrong while looking authoritative. The user's headline feature is a
   gold ledger; a confidently-wrong total is worse than a missing one.

## End State

- Auto-sell cannot destroy a legendary/artifact/heirloom, and does not run without consent on a
  fresh install.
- Mail cannot silently lose items, and every mail action the addon takes appears in the ledger.
- Every gold movement is booked exactly once, with the correct sign and type.
- Account-shared data (warband bank gold and items) is stored once, globally, and is never
  destroyed by a bad read or an empty scan.
- One accounting system, not two.
- Every number shown in the Dashboard is computed over the same set as the rows beneath it.
- Data already computed and thrown away (timestamps, category totals, item totals, exports) is
  rendered.
- The custom Bag UI's correctness and performance defects are fixed without moving a pixel the
  owner has not approved.
- The project's own documentation stops asserting things that are false.
- Verified by an in-game smoke checklist per phase; released once as 1.4.0.

---

## Requirements (user's own words, numbered, confirmed)

1. "we fix it ALL" — every audit finding gets a home, nothing parked
2. "batch the duct tape" — no-duct-tape rule applies; fix at discovery, don't defer
3. Bugs, stale data fixes, ledger fixes
4. "If shit is shared then it should be able to pass from one char to the other because the
   warbound bank is the same amount for all chars"
5. "for some things like banks and shit it requires visiting the bank but ffs lets get creative"
6. UX improvements on the net worth / ledger / inventory stuff
7. UI/UX improvements on the mail and auto sell stuff
8. Reviews, not prescriptions — the user deliberately did not say what he thought was wrong
9. On the Bag UI: "the bag UI itself is set in stone at least mostly. If you try to change
   anything with the bag itself it needs run by me first because i already did alot of
   improvements to the bag itself"
10. Old plans in `.claude/plans/active/` are OUT OF SCOPE: "if they arnt apart of what you just
    audited i dont want it included. This was about the audit findings not finishing other plans"

### User decisions on record

- **Migration safety**: no backup table, no `/im restore`, no release gate. User was asked twice
  and chose "just write it and ship it" both times. The conductor pushed back twice and dropped
  it. **The planner must NOT re-add a backup mechanism.** Two things survive as work-not-gates:
  the migration is verified offline (see Tooling) as part of building it, and the release
  checklist carries one advisory line telling the user to copy `InventoryManagerDB.lua` out of
  WTF before first login. Advisory, not a gate.
- **Ship cadence**: one 1.4.0 release at the end. No per-wave releases. Note the user runs the
  working copy symlinked into WoW (`symlink-to-wow.md`), so he gets every fix immediately
  regardless; "release" means the CurseForge publish only.
- **BagUI**: invisible-only fixes ship as a phase. Each of the five visible changes (B2, B6, B10,
  B11, and the duplicate-render half of B14) must be presented to the user individually for
  approval before any executor touches it. Plan these as approval-gated steps, not as work.
- **Old plans** (`auto-loot-mail-plan`, `bagui-dynamic-sizing-plan`, both `pending_approval`):
  out of scope, files untouched. Note only: this plan's mail findings edit code that
  `auto-loot-mail-plan` created.

---

## Tier

**OPORD.** Mechanically triggered, no override available:
- Blast radius `unbounded` (see Landscape)
- EX-HIGH reversibility hazard (irreplaceable item loss; unrecoverable SavedVariables loss)
- Two Floor-B classes touched: money movement, irreversible operations

---

## Landscape (from recon; every claim carries a file:line)

### Module registration and event dispatch — `Core.lua`

- `IM:RegisterModule` (`Core.lua:96-106`) stores into the string-keyed hash `IM.modules` and calls
  `OnInitialize` immediately. 33 modules register.
- `OnEnable` is driven by `pairs(IM.modules)` (`Core.lua:342-346`) — registration/.toc order is
  discarded. There is no ordered array; adding one is the fix surface.
- `IM:RegisterEvent` appends to `eventHandlers[event]` (`Core.lua:60-66`); the dispatcher iterates
  `ipairs` (`Core.lua:87-93`). **Handler order == OnEnable order**, so the nondeterminism
  propagates into every multi-handler event.
- 119 `IM:RegisterEvent` calls. 26 events have >1 handler. `PLAYER_MONEY` has 11:
  `Ledger.lua:94`, `NetWorth.lua:47`, `BagData.lua:513`, `UI/BagUI/Core.lua:590`,
  `VendorTracking.lua:40`, `AuctionTracking.lua:74`, `FlightTracking.lua:45`, `BMAHTracking.lua:52`,
  `TransmogTracking.lua:47`, `BarberTracking.lua:47`, `UnclaimedGoldTracking.lua:57`.
  `BAG_UPDATE_DELAYED` has 9, `PLAYER_ENTERING_WORLD` 7, `MERCHANT_SHOW` 5, `ACCOUNT_MONEY` 2,
  `ADDON_LOADED` 2.
- **Dispatcher mutation-during-iteration bug**: `Core.lua:366-369` unregisters `handlers[1]` from
  inside the `ADDON_LOADED` dispatch; `UnregisterEvent` does `table.remove` (`Core.lua:74`),
  shifting index 2→1, so `ipairs` (`Core.lua:89`) terminates and `CurrencySearch.lua:25`'s
  `ADDON_LOADED` handler is silently skipped. Lives in the same 30 lines as the ordering fix and
  must land in the same change.
- `_G.InventoryManager = IM` (`Core.lua:10`, again `:754`) — the whole namespace including
  `IM.db` is globally readable/writable by any other addon. This is why W2/W3 are unbounded.

### The `UI/Core.lua` factory fence (requirement 9)

36 public methods + 9 public data tables. **Frozen — signature AND observable behavior — because
`UI/BagUI/*` or `UI/Panels/BagUI.lua`/`UI/Panels/UI.lua` consume them:**

| function | consumer sites | fragile detail |
|---|---|---|
| `CreatePanel` | `BagUI/Core.lua:222,1249` | its `OnKeyDown` ESCAPE→`self:Hide()` is load-bearing and is a producer of finding B1 |
| `CreateHeader` | `BagUI/Core.lua:250,1257` | BagUI reads `header.closeButton` (`:255`) to anchor the gear button; the close button's `parent:Hide()` is B1's other trigger |
| `MakeRounded` | `BagUI/Core.lua:298` | depends on the `SetBackdropColor`/`SetBackdropBorderColor` shims it installs |
| `CreateGlyphButton` | `BagUI/Core.lua:357` | BagUI `SetScript`s OnClick and `HookScript`s OnEnter/OnLeave |
| `CreateRailRow` | `BagUI/Core.lua:414` | depends on returned row exposing `row:SetSelected(bool)` and `row:Refresh(hovered)`, and on it being a `Button`; stashes `row._imViewMode` |
| `CreateScrollFrame` | `BagUI/Core.lua:465` | **heaviest coupling, see below** |
| `CreateCard` | `BagUI/Core.lua:1269`; `Panels/BagUI.lua:25,42,103,233`; `Panels/UI.lua:21,60,114` | consumes `AddText`/`AddCheckbox`/`AddContent`/`GetContentHeight` AND the private field `card._leftPadding` (`Panels/BagUI.lua:141,164,182,196,212`) |
| `CreateButton` | `BagUI/Core.lua:1319,1325` | only OnClick used |
| `AttachRing` | `BagUI/ItemButton.lua:181,196`; `UI/OverlayFactory.lua:87` | consumes `:Show()`/`:Hide()`/`:SetColor()`; ~68 textures per item button flow through it |
| `CreateSettingsContainer` | `Panels/BagUI.lua:16`; `Panels/UI.lua:16` | consumes `AdvanceY`/`FinalizeHeight`/`GetYOffset` |
| `CreateSlider` | `Panels/BagUI.lua:140,195,211` | reads inner `slider.slider` to `HookScript("OnMouseUp")` for apply-on-release |
| `CreateCheckbox` (via `card:AddCheckbox`) | `Panels/BagUI.lua:53,159,177`; `Panels/UI.lua:27,40,46,66,77,88,99` | reads `check.checkbox`, assigns `OnValueChanged` |

**`CreateScrollFrame` internals are frozen too.** `UI/BagUI/Core.lua:126-134` numerically MIRRORS
the factory's private fill-mode margins into its own `SIZING` table —
`SCROLL_CONTAINER_MARGIN=10` mirrors `UI/Core.lua:1016-1017`, `SCROLL_CONTENT_INSET=22` mirrors
`UI/Core.lua:1037/1047`, `SCROLLBAR_WIDTH=10`/`SCROLLBAR_MARGIN=8` mirror `UI/Core.lua:1062-1063`
— and `CalculateRequiredWidth` (`:186-187`) derives the whole bag window width from those copies.
`ResizeForSettings:885` holds a SECOND un-named copy as a raw `- 20 - 22`. Changing the factory's
`10`/`-18`/`-4`/`-22` silently makes the bag window lose or gain a column. BagUI also reads
`frame.scrollFrame.content` (`:876,886`) and relies on `container.content` and
`scrollFrame.content` (`UI/Core.lua:1145,1150`) both continuing to exist, plus `container.scrollBar`
being written by the factory's own `OnSizeChanged` (`UI/Core.lua:1051`).

**`UI.layout` (`UI/Core.lua:82-140`, 45 keys): ADD new keys freely — every read is an explicit
named field and nothing iterates it. NEVER retune an existing value.** Four are load-bearing in
geometry BagUI recomputes independently: `bottomBarHeight` (`BagUI/Core.lua:381,445,471` — three
uses of the same number that must agree), `rowHeightSmall`+`elementSpacing` (category header
height computed in two places that must agree: `MasonryLayout.lua:272` and
`CategoryView.lua:729,794,797`), `rowHeight` (`BagUI/Core.lua:414,419` — rail row height AND per-row
Y stride, and the rail's total height is not derived from it), `iconSize` (item icon fallback
`ItemButton.lua:168,562` AND gear button size `Core.lua:254`). `UI.layout` is read 48× in
`BagUI/Core.lua` alone.

**Provably safe to change (zero BagUI consumption)**: `CreateDropdown`, `ShowDropdownMenu`,
`CreateItemListRow`, `CreateItemListBuilder`, `CreateTabBar`, `CreateFeatureCard`,
`CreateSettingsCard`, `CreateDynamicSettingsCard`, `CreateCheckboxWithHint`, `CreateSectionHeader`,
`CreateDivider`, `CreateNumberInput`, `CreateCurrencyInput`, `UnpackColor`, `ColorText`,
`UI.hexColors` (zero reads in BagUI).

**`SetText` and `Disable` fixes are provably invisible to BagUI**: BagUI calls `UI:CreateButton` at
exactly two sites and never calls `Button:SetText` or `Disable()`/`Enable()` anywhere. Verified by
grep across the subsystem.

**Wave 4 needs less new factory surface than first assumed**: `UI:CreateDropdown` (`UI/Core.lua:893`)
and `UI:ShowDropdownMenu` (`:942`) already exist, so the Dashboard's 5 raw `UIDropDownMenuTemplate`
frames migrate onto existing API. `UI:CreateNumberInput`/`CreateCurrencyInput` exist but there is
no plain text-input factory — that is the one genuine addition needed. `UI.hexColors` already
exists and is already used at `Dashboard.lua:1560-1561`.

### `Database.lua` — schema, versioning, migration machinery

- `DB_VERSION = 2` (`Database.lua:9`). `defaults.global` (`:12-162`) has 24 top-level keys.
  `defaults.char` (`:164-167`) is empty and `db.char` is read nowhere.
- `_mergeDefaults` (`:181-192`) recurses into every table in defaults unconditionally (`:183-187`):
  if `type(v)=="table"` it FORCES `target[k]` to a table even when the user's stored value is a
  scalar, then recurses. Scalars are only filled when nil (`:188`). Consequences: (a) it can never
  remove a stale key — so deleting `sellHistory` data without removing it from `defaults` will not
  hold; (b) it silently destroys data if a default's shape ever changes from scalar to table;
  (c) it is idempotent for the current defaults.
- `_runMigrations` (`:195-248`): v0→v1 is a version stamp no-op. **v1→v2 (`:206-247`) is NOT
  idempotent by construction** — it APPENDS `sellHistory.entries` into `transactions.entries` with
  no dedupe key, guarded only by the `dbVersion` stamp written at `:245`. Reset or fail that write
  and every entry duplicates. This is the precedent the v3 migration must not repeat.
- `InitializeDatabase` (`:251-272`) = create-or-merge → migrate → assign `self.db` → optional
  `self:OnDatabaseReady()`. **`OnDatabaseReady` is invoked at `:269-271` and defined nowhere.**
- `IM:GetCharacterKey()` (`:542-552`) = `UnitName("player").."-"..GetRealmName()`. **No realm
  normalization anywhere** — `GetNormalizedRealmName` appears zero times in the tree; only
  `GetRealmName()` at `Database.lua:382,544`, `MailHelper.lua:587`, `Panels/MailHelper.lua:400`.
  Realms with spaces ("Area 52") produce keys with spaces.
- **charKey greedy-parse sites: 24** (the audits said 5). `:match("^(.+)-")` at
  `Database.lua:836,837`; `Ledger.lua:159,160`; `InventorySnapshot.lua:475,476,516`;
  `NetWorth.lua:308,309`; `MailHelper.lua:270,271,284,285,521,585,586`; `TooltipInfo.lua:161`;
  `UI/MailPopup.lua:154`; `UI/Dashboard.lua:597,624,1059,1240,1622`;
  `UI/Panels/MailHelper.lua:194,346`.
- Keys a v3 migration must touch in ONE pass: `characters` (`:101`), `inventorySnapshots` (`:155`),
  `transactions.entries[i].char` (`:95`, stamped at `:618-627`), `mailHelper.alts` +
  `mailHelper.rules[i].alt` (`:113-114`), `sellHistory.entries` (`:71-74`), `warbandBankInventory`
  (`:158-161`), and `dashboard.ledgerCharFilter` (`:140`) — which persists an **index** into a
  runtime-sorted char list (`Dashboard.lua:619-628`), so any key rename silently repoints the
  filter. A self-healing branch exists at `:626-628` but only resets to "All Characters".

### `hooksecurefunc` — 30 sites (audits said 40). Targets hooked from more than one file:

- `ContainerFrame_Update` — `ItemLock.lua:440`, `JunkList.lua:60`, `UI/BagIntegration.lua:40`
- `ContainerFrameItemButtonMixin.OnClick` — `ItemLock.lua:414`, `JunkList.lua:48`
- `ContainerFrameCombinedBags.Update` — `ItemLock.lua:466`, `UI/BagIntegration.lua:57`
- `BuyMerchantItem` — `SellHistory.lua:106`, `VendorTracking.lua:235` — **both then write a legacy
  history entry** (`SellHistory.lua:126`, `VendorTracking.lua:265`)
- `ToggleAllBags` / `OpenAllBags` — `BagUI/Core.lua:1046,1176` / `:1077,1191` (mutually exclusive
  paths)

### `.toc` load-order constraints

1. `UI\Core.lua` must precede the 23 files binding `local UI = IM.UI` at file scope.
2. `Core.lua` must be first — `RegisterModule`/`RegisterEvent` are called at file scope everywhere.
3. `UI\BagUI\Core.lua` must precede `MasonryLayout.lua` (`:15` reads `BagUI.MasonryLayout`
   read-only; the table is created at `BagUI/Core.lua:15`). `ItemButton.lua:24` and
   `CategoryView.lua:14` assign unconditionally and are order-flexible.
4. The `.toc` comment "Core.lua first - defines SIZING constants" is **stale** — `SIZING` is a
   file-local (`BagUI/Core.lua:126`) exposed via `UI:GetSizingConstants()` (`:204`) and read at
   runtime, not load time.
5. `Database.lua` readiness is enforced by the `ADDON_LOADED` event (`Core.lua:337-339`), not by
   `.toc` position.

### Published commitments

`.toc`: `Interface: 120100`, `Version: 1.3.3`, `SavedVariables: InventoryManagerDB`,
`X-Curse-Project-ID: 1422035`. `VERSION` = 1.3.3, `Core.lua:13` `IM.version = "1.3.3"`.
`publish.sh` rewrites `## Version:` and `IM.version` only — **it never touches `## Interface:`**,
so a 1.4.0 interface bump is a manual edit. `publish.sh` hard-gates on: clean working tree, no
untracked files except `VERSION_GUIDE.md`/`*.zip`, branch `main`, monotonic version increment.

### Tooling — what verification actually exists

- **No test harness and none possible in-process.** No `lua`, `lua5.1`, `luajit`, `luacheck` or
  `busted` installed; `sudo -n` fails.
- **Docker IS available and verified working**: `docker run --rm -v /tmp:/w -w /w
  akorn/lua:5.1-alpine lua script.lua` returns `Lua 5.1`. User is in the `docker` group, daemon
  29.7.2. This is the migration verification path — real 5.1 semantics, no install, no password.
  (npm's `fengari`/`lua-in-js` are Lua 5.3 and must NOT be used for migration verification: `#`
  and integer-division semantics differ.)
- **`Database.lua` is almost perfectly CLI-exercisable.** Zero load-time global references —
  `local addonName, IM = ...` at line 6, everything else inside functions. A harness needs:
  `loadfile("Database.lua")(addonName, IMStub)` where `IMStub` provides `Debug`, `Print`,
  `PrintError` (the only IM methods the migration path touches: `:237,246,255,259`); globals
  `time = os.time`, `date = os.date`; and `InventoryManagerDB` loaded from the real SavedVariables
  file, which is already valid Lua and `loadfile`s directly. `_deepCopy`/`_mergeDefaults`/
  `_runMigrations` are file-locals, so the harness calls the public `IM:InitializeDatabase()`
  (`:251`) which chains all three — sufficient, and the real entry point. **Idempotency is testable
  by calling it twice and deep-comparing.**
- In-game: `/reload`, `/im debug` (`Core.lua:498-501`), and a 500-line in-memory debug ring buffer
  (`Core.lua:42-57`) dumpable via `IM:GetDebugLogString()` (`Core.lua:183`).

### Existing things to reuse rather than rebuild

- `GetPooledFrame`/`ReleaseAllFrames` (`Dashboard.lua:59-86`) already work; the `networth` and
  `inventory` pools simply have no callers.
- `IM:GetBagIDsToScan()` (`Filters.lua:646-658`) is the canonical bag-ID list including the
  reagent bag. `VendorTracking:SnapshotBags` (`:78`) hardcodes `0,4`; `BagData.BAG_IDS` hardcodes
  `5` instead of `Enum.BagIndex.ReagentBag`.
- `UI:CreateTabBar` (`:1609`) with lazy-load-by-name is the established sub-panel pattern
  (`UI/Panels/Selling.lua:40-62`).
- `IM:ParseMoneyFromMessage`/`IM:ExtractItemLinkFromMessage` (`Core.lua:715,734`) already wrap
  tainted-string handling in `pcall`. **Note `ParseMoneyFromMessage` only matches English
  "gold"/"silver"/"copper"**, and `LootTracking.lua:142` gates on `find(msgLower,"loot")` — so on
  a non-enUS client the loot entry is missing entirely and only the duplicate `other_income` lands.
- `StaticPopupDialogs` infrastructure for confirms already exists (`Core.lua:191-243,601-611`).
- `ItemLock._CheckAndBuybackLockedItems` (`ItemLock.lua:134-168`) already scans
  `GetBuybackItemLink(1..12)` and repurchases — the pattern for an undo exists.

---

## Risk inputs

Union of user-named and agent-found. The user named none; he does not get to remove one the
audits found.

| class | tier signal | evidence |
|---|---|---|
| reversibility | **EX-HIGH** | irreplaceable item destruction (`Filters.lua:200` dead quality floor + `:553` junk-list override); unrecoverable SavedVariables loss (no WoW version history; `_mergeDefaults:183-187` scalar→table coercion; v1→v2 non-idempotent precedent) |
| money | HIGH | the ledger IS money accounting; auto-sell/repair/mail move real gold |
| data | HIGH | v3 migration spans 7 db keys; `_mergeDefaults` resurrects any nil default; empty scans clobber account-shared snapshots |
| concurrency | HIGH | `pairs()` module order feeding 119 registrations across 26 multi-handler events; async `SendMail` looped synchronously; `C_Timer` races |
| external-deps | HIGH | 30 `hooksecurefunc` edges into Blizzard APIs across 14 files; `.toc` targets `120100`; 5 unverified API behaviors (see W0) |
| security | N/A | sandboxed client addon; no network, credentials, or untrusted input beyond WoW's own API |
| auth | N/A | single-user client addon, no auth model |
| prod-state | N/A as infrastructure | the user's live account data is the real "prod" and folds into `data` |

### Blast radius, per wave (drawn so phase boundaries land where they are cheap)

| wave | signal | reason |
|---|---|---|
| W0 | bounded | recon only, zero code edges |
| W1 | bounded | all inbound edges enumerated: `ShouldAutoSell` callers, `autoSellEnabled` readers (`Database.lua:21`, `AutoSell.lua:64`, `Core.lua:465`, `Panels/AutoSell.lua:43,47`), `MailHelper:SendToAlt` callers (exactly 2: `UI/MailPopup.lua:173,233`) |
| W2 | **unbounded** | the `Core.lua:60-93` dispatcher is shared by all 119 registrations; handler identity is an anonymous closure, and the handler SET is runtime-dependent because `FlightTracking.lua:28`, `MailTracking.lua:29`, `UnclaimedGoldTracking.lua:48`, `WarbandBankTracking.lua:30-44` all return early on settings/API absence. Plus 30 `hooksecurefunc` sites and `_G.InventoryManager` exposing `RegisterEvent` to third parties. |
| W3 | **unbounded** | the migration's input is a real user SavedVariables file whose key shapes cannot be enumerated from this repo; `warbandBankGold`/`warbandBankInventory` are account-shared across sessions the migration will never observe |
| W4 | bounded, one unbounded edge | additive-only factory changes have the enumerated fence above; Dashboard internals are file-local (`Core.lua:396-410,698-700`, `MinimapButton.lua`). **Unbounded edge**: `UI/Panels/Selling.lua:53` resolves panels by string (`UI.Panels[panel.module]`) — a rename fails at runtime, not load time |
| W5 | bounded | purely additive render paths; the four data sources have ZERO inbound edges today |
| W6 | bounded | popup inbound edges enumerated (`Core.lua:688-695`, `AutoSell.lua:57-61,85`, `MailHelper.lua:760,790,820,837`) |
| W-BagUI | bounded | fence mapped exhaustively above |
| W7 | bounded | docs only, zero code edges |

### Sequencing evidence (recon CONFIRMED one dependency and REFUTED five)

- **CONFIRMED**: the `_claimedThisCycle` fix requires the module-order fix first.
  `UnclaimedGoldTracking.lua:96` writes `false` and `WarbandBankTracking.lua:130` writes `true` —
  the ONLY pair in the tree where two `PLAYER_MONEY` handlers write shared mutable state. Until
  `Core.lua:342` yields a fixed order you cannot tell whether a duplicate entry came from the
  ordering or from the flag's design.
- **REFUTED — the repair race is deterministic today.** `RepairTracking.lua:37-40` snapshots
  synchronously inside its `MERCHANT_SHOW` handler; `AutoSell.lua:71-75` defers `SellJunk` by
  `C_Timer.After(0.2)`. The snapshot ALWAYS precedes the sale regardless of handler order. Fixable
  independently.
- **REFUTED — AH fee double-subtraction and missing `ah_refund`** are pure arithmetic/emission
  defects in `AuctionTracking.lua:224-237` and `:174-180`. No cross-handler state.
- **REFUTED — MailHelper's tracking bypass** is a missing code path (`MailHelper.lua:617` vs
  `MailTracking.lua:75`), fully deterministic.
- **REFUTED — guild bank attribution** uses only `GUILDBANK_UPDATE_MONEY` and its own
  `_lastGuildBankGold`.
- **REFUTED — single-slot pendings** collide between two user actions in time, not two handlers.
- **Every other tracker is order-independent by construction** — each keeps a private `_lastGold`
  baseline (`VendorTracking.lua:22`, `FlightTracking.lua:22`, `UnclaimedGoldTracking.lua:31`, same
  in BMAH/Transmog/Barber/Auction).
- **No module depends on the accidental order.** Specifically refuted: `RecentItems.lua:93` calls
  `IM:GetModule("BagData")` + `RegisterCallback` in its own `OnEnable`, but `BagData._callbacks` is
  a file-scope literal (`BagData.lua:34-38`) untouched by either lifecycle hook, and BagData's
  first scan is deferred to `C_Timer.After(0.5)` (`:530-536`). `JunkList.lua:23-24,34,40` reaches
  `IM.modules.ItemLock` nil-guarded.
- **Unnamed prerequisite**: the dispatcher's mutation-during-`ipairs` hole must land in the same
  change as the ordering fix — otherwise the ordering fix leaves a live iterator bug in the exact
  code path it just touched.
- **W3 depends on W2's charKey DECISION, not W2's ordering fix.** `IM:AddTransaction` stamps
  `entry.char` (`Database.lua:618-627`), so realm normalization must land after the key format is
  decided, and the migration must rewrite `transactions.entries[i].char` in the same pass as the
  other six keys.
- **W4 depends on nothing in W2/W3 except ledger search semantics** — the fix changes what
  `IM:GetTransactions` means for exactly three callers: `Database.lua:757` (`GetLedgerStats`),
  `Ledger.lua:168`, `Ledger.lua:180`.

**Net effect: W2 is far more parallelizable than the conductor originally asserted.** Only the
`_claimedThisCycle` item is gated on the ordering fix.

---

## THE FINDINGS — every one gets a phase. Grouped by wave.

Counts (CORRECTED — the conductor's original header said 96 and was wrong; the numbered lists
below are the authority): W0 6 · W1 6 · W2 20 · W3 18 · W4 12 · W5 14 · W6 20 · W-BagUI 15 + 5
approval-gated · W7 9 = **125**.

**CONDUCTOR CORRECTION to W2-16 and W3-10 (a design error in this brief, not a planning defect).**
W2-16 below says to classify alt-to-alt mail as a transfer "when `entry.src` matches a key in
`db.global.characters` or `mailHelper.alts`". **That cannot work as written**:
`MailTracking.lua:122,142` set `source = sender or "Unknown"` — a raw mail sender name, bare
(`"Bob"`) for same-realm mail, never `"Bob-Realm"` — so the receiving half of the pair can never
match a charKey. The correct fix is to stamp a real charKey at the mail log site (inside the
`MailTracking:LogInboxMail` / `CapturePendingSend` extraction that W2-13 already requires),
defaulting a bare sender to the current realm, and compare charKeys. Same producer:
**`transactions.entries[i].src` must be added to W3-10's migration normalization pass** — it holds
character identifiers for mail and trade rows (`MailTracking.lua:157,169`, `TradeTracking.lua:113`,
built as name-plus-realm at `Panels/MailHelper.lua:400`), and W2-16 reads exactly that field, so
omitting it makes historical transfer rows revert to income/expense after migrating.

### W0 — in-game recon (gates design choices in W2/W3; the user runs these)

1. Does `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` return `0` or `nil` before the account
   bank has been opened in a session? This is what makes finding W3-1 a live wipe vs a no-op.
   Settles by: `/reload`, `/im debug`, read the `[WarbandBankTracking] Initialized warband gold:`
   line at login before opening any bank.
2. Is `C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)` readable COLD (no bank frame open)?
   **If yes, warband bank items become refreshable anywhere and W3 grows a capability.**
3. Does `Enum.PlayerInteractionType.AccountBanker` actually fire on the live build?
4. Is `pairs()` iteration order over `IM.modules` stable within a WoW build? Add a temporary
   `IM:Print` of the OnEnable order and compare across three `/reload`s. **If stable, the
   `_claimedThisCycle` bug is deterministic rather than intermittent, which changes how it is
   reproduced.**
5. Does the scroll-child width snapshot (`UI/Core.lua:1037`) actually clip content in the
   Dashboard's two search boxes? (`UI/MailPopup.lua:58-61`, `UI/AutoSellPopup.lua:95-98` have the
   same shape.)

Also: prove `UI/Panels/History.lua`'s reachability before ANY deletion claim in W7 — recon did not
read `UI/Panels/Dashboard.lua` past line 40 or `UI/Panels/Currency.lua`, so its death is a theory.

### W1 — asset safety (nothing else ships first)

1. **`Filters:IsProtectedByQuality` (`Filters.lua:200-202`) has ZERO callers.** The only quality
   gate in `ShouldAutoSell` is `itemQuality > db.autoSell.maxQuality` (`:619`). The documented
   "Legendary/Heirloom never sell" step does not exist. Fix: insert the floor above BOTH the
   threshold check and the junk-list branch (`:553-561`), after the whitelist check at `:549`, so
   nothing overrides it. Note the floor as written (`>= 5 or == 7`) cannot block poor/common/
   uncommon, so re-wiring it does NOT break default auto-sell — but it also blocks quality 8 (WoW
   Token, `Core.lua:306`), and `ShouldAutoSell` never nil-checks `itemQuality` itself even though
   it early-returns on nil `itemName` (`:517-522`). Guard that.
2. `UI/Panels/AutoSell.lua:16-25,82` offers `maxQuality` indices 5/6/7 (Legendary/Artifact/
   Heirloom) and writes the raw index. Clamp the dropdown, or let the new floor win — decide and
   state which.
3. **`autoSellEnabled = true` by default** (`Database.lua:21`) + `AutoSell.lua:64-75` sells 0.2s
   after `MERCHANT_SHOW` with no consent. Popup shows at +0.1s — a receipt, not a preview. Fix:
   default false, and gate the first automatic sale per session behind a real confirm using the
   existing `StaticPopupDialogs` infrastructure. Keep readers consistent: `Core.lua:465`,
   `Panels/AutoSell.lua:43,47`.
4. **Mail cursor is unguarded.** `MailHelper.lua:601-610` does `PickupContainerItem` then
   `if CursorHasItem() then ClickSendMailItemButton(...)` with no verification that the click
   attached and **no `ClearCursor()` on any path** (`ClearCursor` exists in the whole repo only at
   `ItemLock.lua:229`). A refused attachment (soulbound, 12-slot cap, unique-equipped) leaves the
   item on the cursor, and the NEXT iteration's `PickupContainerItem` on a full cursor performs a
   place/swap INTO that bag slot. Fix: verify after the click, `ClearCursor()` and collect into an
   `unmailable` list; `ClearCursor()` once more before `SendMail`.
5. **Rules are `classID`-only and never inspect bind state** (`Panels/MailHelper.lua:405`), so a
   Trade Goods rule queues soulbound mats. The `soulbound` FILTER_TYPE already exists
   (`MailHelper.lua:113-145`) and is unreachable from the UI. Pre-filter in `AutoFillQueue`
   (`:451-468`) via `C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(...))`.
6. **"Send All" is a broken transaction.** `UI/MailPopup.lua:229-241` loops `SendToAlt` synchronously;
   `SendToAlt` calls `ClearSendMail()` on entry (`MailHelper.lua:599`) and `SendMail` is async, so
   iteration 2 wipes the frame while iteration 1 is in flight, and `_currentRecipient` (`:613`)
   ends up as the last alt. `OnMailSendSuccess` (`:245-251`) then empties THAT alt's queue
   regardless of who received mail. Fix: serial state machine in `MailHelper` advancing on
   `MAIL_SEND_SUCCESS`, retry-then-abort on `MAIL_FAILED` (both already registered at `:180-186`);
   have success clear only the items actually attached. Model the progress contract on
   `MailPopup:OnLootingStarted/Progress/Stopped` (`:312-342`), which is the right shape already.

### W2 — ledger correctness

1. **Module `OnEnable` order + the dispatcher iterator hole, in one change.** `Core.lua:342` →
   ordered array (`table.insert(self.moduleOrder, name)` at `:100`, `ipairs` at `:342`), making
   `.toc` order authoritative; and fix `Core.lua:366-369`/`:89` so unregistering during dispatch
   cannot truncate the handler list. **This is the only W2 prerequisite.**
2. **Loot/quest/flight gold double-counted.** `IM:ClaimGoldChange` has exactly ONE caller
   (`WarbandBankTracking.lua:130`); `IsInTrackedContext` (`UnclaimedGoldTracking.lua:107-166`) is a
   frame-context whitelist with no loot/quest/flight branch. `FlightTracking.lua:162-163` comments
   that flight costs "are claimed immediately" — the file never calls `ClaimGoldChange`. Result:
   `CHAT_MSG_MONEY`→`loot +N` then `PLAYER_MONEY`→`other_income +N`.
3. **`_claimedThisCycle` is a session-wide boolean reset on every money event**
   (`UnclaimedGoldTracking.lua:33,96`). Order flip → double-log; reset-then-claim → lost entry.
   **Gated on item 1.**
4. **`_claimedThisCycle` is never reset when `IsInTrackedContext()` returns true**
   (`UnclaimedGoldTracking.lua:84-88`) — a stale `true` suppresses the next legitimate log.
5. **`_pendingChange` is a single slot** (`:32,91`) — two changes inside 0.5s yield one entry
   carrying the wrong amount (`:170`).
6. **`WarbandBankTracking:IsAtWarbandBank()` returns `false` unconditionally** (`:159-165`), making
   the context check at `UnclaimedGoldTracking.lua:152` dead code.
   **Fixes 2-6 are ONE fix at the ancestor**: amount-keyed FIFO claim queue, hooked inside
   `IM:AddTransaction` (`Database.lua:614-652`) so `entry.val ~= 0` claims its own amount. Order-
   independent, covers every present and future call site, and lets `IsInTrackedContext` be
   deleted entirely.
7. **`hooksecurefunc` logs transactions that never happened.** `BuyMerchantItem` rejected for full
   bags/insufficient gold still books `purchase -totalCost` (`VendorTracking.lua:256-262`); same
   for `BuybackItem` (`:284`), `TakeInboxMoney` (`MailTracking.lua:285`), `TakeInboxItem` (`:302`).
   Also `totalCost = price * ceil(qty/(stackCount or 1))` (`:254`) books `-0` for currency-cost
   purchases. Fix: arm a pending record and confirm against the matching `PLAYER_MONEY` delta —
   same queue as item 6. For mail, confirm on `MAIL_SUCCESS`.
8. **AH: the 5% cut is subtracted twice.** `ah_sold` is booked at `totalCopper`, already net
   (`AuctionTracking.lua:220-228`), then `ah_fee` at `-ahFee` (`:236`). Book gross+fee, or net with
   no fee row.
9. **`ah_refund` is never emitted anywhere.** Declared `Ledger.lua:41`, documented
   `AuctionTracking.lua:17`, and `OnPlayerMoney` (`:102-157`) has no positive-delta branch at all;
   the expired branch (`:174-180`) only logs. Expired-auction deposits are lost, and
   `IsAtAuctionHouse()` suppresses the unclaimed catcher too.
10. **Outbid refunds lost, phantom purchase kept.** `OnPlaceBid` (`:348-360`) sets
    `_pendingPurchase` for any bid, booked as `ah_bought` (`:132`); the refund is a positive delta
    with no handler, so the expense stays forever. Bid-sourced pendings also carry no `itemID`.
11. **Single-slot AH pendings** — `_pendingDeposit`/`_pendingPurchase` (`:31-32`) overwritten at
    `:312,337`; five quick commodity posts yield one merged entry.
12. **Repair cost lost and mislabelled guild-paid.** `_goldBeforeRepair` snapshots at
    `MERCHANT_SHOW` (`RepairTracking.lua:238-242`); auto-sell income makes `actualCost` negative,
    the `< repairCost*0.5` heuristic (`:262`) fires "guild", and `:264-270` logs `repair_guild`
    with `value = 0`. Fix: snapshot INSIDE the `hooksecurefunc("RepairAllItems")` body and use the
    hook's own `useGuildFunds` argument — already passed at `:245` and ignored. Log guild-paid
    repairs with the real cost so guild spend is visible. **Not order-gated (see Sequencing).**
13. **MailHelper's automation bypasses MailTracking entirely.** `_pendingSend` is captured only from
    `SendMailMailButton:HookScript("PreClick")` (`MailTracking.lua:75`); `MailHelper.lua:617` calls
    `SendMail` directly so it never fires and `OnMailSendSuccess` bails at `:151`.
    `MailHelper.lua:796` calls `AutoLootMailItem` which is not among MailTracking's hooks
    (`TakeInboxMoney:114`, `TakeInboxItem:129`) — auto-loot is invisible too. And `IsAtMailbox()`
    suppresses the unclaimed catcher, so the gold isn't even booked as `other_income`. **AH
    proceeds arrive by mail, so for anyone using the automation, AH income is entirely absent.**
    Fix: log at the action site — extract `MailTracking:LogInboxMail(index)` and
    `MailTracking:CapturePendingSend(recipient, money, items)` and call from both paths.
14. **Guild bank attributes other members' gold moves to the player.** `GuildBankTracking.lua:269-323`
    infers direction from the guild bank's own delta and assumes "it was us" (comment `:296-305`),
    then `IM:Print`s to chat. Guild-funded repairs land as INCOME. Fix: only log when the player's
    own gold moved by the matching amount in the opposite direction within a window — reuse the
    same amount-keyed claim machinery. Guild bank state is also per-guild shared data persisted
    nowhere; if it ever enters net worth, key it `guildBanks[guildName]` with a `lastSeen`.
15. **Postage never logged.** `SendMail` costs 30c/mail; nothing records it, in an addon whose
    headline feature is a gold ledger.
16. **Alt-to-alt mail counted as real income AND expense.** `TRANSFER_TYPES` (`Database.lua:750-753`)
    lists only the warband pair. Fix: classify `mail_gold_sent`/`mail_gold_recv` as transfers when
    `entry.src` matches a key in `db.global.characters` or `mailHelper.alts`.
17. **`TradeTracking` clears `_inTrade` at `OnTradeComplete` (`:417`), before `TRADE_CLOSED`** — late
    trade money escapes the guard and is double-booked. Dies with item 6.
18. **Bank item transfers attributed to the wrong bank.** `_detectedBankType`
    (`BankItemTracking.lua:25,514-547`) is set at frame-show and never revisited; in TWW both banks
    live in one frame and tab switches fire no new event, so every transfer for the session is
    typed by whichever tab opened first. Detection is also a bag-only diff (`_SnapshotBags:30-46`)
    driven by `BAG_UPDATE_DELAYED`, so looting/crafting while the frame is open FABRICATES deposits
    complete with a chat line (`:117`). `GuildBankTracking:127-160` has the identical producer.
    Fix: resolve the type at process time via `C_Bank.IsAccountBankPanelShown()` (already used at
    `:539`), and diff the BANK side as well as the bag side so a transfer requires a matching
    counterpart — that identifies direction AND which bank, and rejects loot/consumption. Extract
    the duplicated snapshot/diff helper once so both files get the fix. Note the project docs blame
    a nil `_lastBankType`; **that variable no longer exists — the module was rewritten.**
19. **`VendorTracking:SnapshotBags` iterates `bagID = 0, 4`** (`:78`), missing the reagent bag that
    `IM:GetBagIDsToScan()` includes. Reagent-bag sells are unattributable.
20. `IM:ParseMoneyFromMessage` (`Core.lua:715-727`) matches only English unit names and
    `LootTracking.lua:142` gates on `find(msgLower,"loot")` — on a non-enUS client the loot entry
    is missing and only the duplicate lands. Decide: localize, or document the enUS assumption
    with a real trigger.

### W3 — account-shared data + the second accounting system

1. **Login zeroes the account-shared warband bank AND fabricates a transfer.**
   `WarbandBankTracking.lua:64` calls `InitializeWarbandGold()` unconditionally in `OnEnable`
   (i.e. at `ADDON_LOADED`, nowhere near a bank); the guard at `:74` is `currentGold >= 0` so 0 is
   ACCEPTED and `IM:SetWarbandBankGold(0)` also stamps `warbandBankGoldUpdated = time()`
   (`Database.lua:881-885`) — destroyed data relabelled as fresh. Then `_lastWarbandGold = 0` makes
   the next real `ACCOUNT_MONEY` compute `delta = +fullBalance` → a phantom `warbank_deposit` for
   the entire balance (`:132-139`). `NetWorth.lua:401-415` has the identical `>= 0` hole and is
   wired to `ACCOUNT_MONEY`, `BANKFRAME_OPENED`, `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`.
   `IM:SetWarbandBankGold` also coerces `nil`→0 (`copper or 0`), so the sink has no rejection path
   either. **`IM:UpdateCharacterGold` already implements exactly this guard for character gold
   (`Database.lua:598`)** — the warband writers just don't. Fix at the single writer: reject a
   write that lowers a nonzero stored value unless the account bank is actually reachable, treat
   `nil`/`0` as UNKNOWN not zero, don't stamp the timestamp on a rejected write, never reset
   `_lastWarbandGold` to 0 (leave it `nil` and skip the first delta), delete the `OnEnable` init,
   and collapse the two writers into one — `NetWorth` should READ `IM:GetWarbandBankGold()`, not
   write it.
2. **Warband bank ITEM value is multiplied by the alt count.** `CalculateInventoryValue(true)`
   folds `Enum.BagIndex.AccountBankTab_1..5` into one scalar (`NetWorth.lua:227-252`) persisted to
   the CURRENT character's `inventoryValue` (`:257-262`); `GetAccountBreakdown` (`:317-319,379`)
   then sums every character and adds warband gold on top. Five alts who opened a bank = 5× the
   warband contents. `IM:GetAccountNetWorth` (`Database.lua:865-873`) repeats the bug independently.
3. **Bank value evaporates when you walk away.** The same scalar holds bags-only OR bags+bank
   depending on which handler fired last; bank contents are included only while
   `BankFrame:IsShown()` (`:184`), and the next `BAG_UPDATE_DELAYED` (`:69-79`) or `PLAYER_MONEY`
   (`:47-54`) recomputes bags-only and overwrites. `GetInventoryValue` (`:277-281`) falls through
   to `UpdateInventoryValue(false)`, doing the same.
   **Fix 2+3+5 as ONE change**: `CalculateInventoryValue` returns `(bagsValue, bankValue,
   warbandValue)`; bags refresh freely, bank persists with its own `bankValueTimestamp` and is
   never overwritten by a bags-only pass, and warband value is stored ONCE GLOBALLY next to the
   already-correctly-global `warbandBankInventory` (`Database.lua:157-161`). `GetAccountBreakdown`
   adds the global warband value exactly once. Same treatment for the dead `GetAccountNetWorth`.
4. **`UpdateInventoryValue` dereferences a nil `charData`** (`NetWorth.lua:257-262`).
   `IM:GetCharacterData` is documented to return nil on early load (`Database.lua:556-562`) with
   "CALLERS MUST handle nil" at `:536-537`; `UpdateCharacterGold` guards it (`:586-590`), this
   doesn't. Reachable from the `PLAYER_MONEY` 0.1s handler (`:48-53`) and the 2s login timer
   (`:128-130`). The error aborts the enclosing `C_Timer` callback, so paired work in that closure
   never runs.
5. **Reagent bag counted twice.** `IM:GetBagIDsToScan()` already appends `Enum.BagIndex.ReagentBag`
   (`NetWorth.lua:156`, `Filters.lua:647-657`); `NetWorth.lua:170-181` scans bag 5 again behind
   `if C_Container.GetContainerNumSlots(5) then` — **always true, because Lua treats `0` as
   truthy**. Delete `:170-181`; `GetBagIDsToScan` is the single source of truth.
6. **Empty scans clobber good snapshots, and the retry is dead code.** `ScanBags`
   (`InventorySnapshot.lua:228-276`) returns `true` whenever `IM.db.global` and `charKey` exist —
   it never reports whether an item was read (`:275`) — so `TryScanWithRetry`'s exponential backoff
   (`:63-82`) never fires: attempt 1 always "succeeds". `snapshot.bags = items` assigns
   unconditionally at `:270`, same shape at `:306` (bank) and `:328` (reagentBank).
7. **`ScanWarbandBank` destroys account-shared data unconditionally.** `:337-374` writes
   `IM.db.global.warbandBankInventory = { timestamp = time(), items = items }` at `:368-371` even
   when `tabIDs` is nil/empty (the `if tabIDs` guard at `:346-348` skips the LOOP, not the WRITE)
   — and stamps a fresh timestamp on the emptiness.
   **Fix 6+7 as one rule at the write sites**: never replace a non-empty stored snapshot with an
   empty one; make `ScanBags` return `false` when `totalSlots == 0` so the retry actually retries;
   `ScanWarbandBank` additionally needs an "is the account bank readable" precondition before it
   may write at all.
8. **Two accounting systems written in parallel forever.** The v1→v2 migration copied `sellHistory`
   into `transactions` and never stopped the legacy writers: loot is handled by BOTH
   `SellHistory.lua:98` and `LootTracking.lua:115` (both call `IM:AddLootHistoryEntry`);
   `BuyMerchantItem` is hooked TWICE (`SellHistory.lua:106`, `VendorTracking.lua:235`, both calling
   `IM:AddPurchaseHistoryEntry` at `:126`/`:265`); auction sales twice (`SellHistory.lua:193`,
   `AuctionTracking.lua:241`); protected-item buyback THREE times (`VendorTracking.lua:284` ledger
   plus legacy at `:293` and `ItemLock.lua:157`). SellHistory's copies also skip the vendor/AH/
   mailbox context guards `LootTracking.lua:43-70` has, so they fire in contexts the design
   excludes. `UI/Panels/History.lua:38` renders the doubled legacy store while the Dashboard reads
   the other; `sellHistory` is capped at 100 (`Database.lua:399-402`) so `GetTotalGoldEarned`/
   `GetTransactionStats` are truncated. Fix: delete SellHistory's writers
   (`RegisterLootTracking`/`RegisterPurchaseTracking`/`RegisterAuctionTracking` and their handlers,
   `SellHistory.lua:26-40,52-99,101-131,133-206`), keep the read/format helpers, point
   `Panels/History.lua:38` at `IM:GetLedgerStats`, remove the duplicate
   `IM:AddBuybackHistoryEntry` at `ItemLock.lua:157`, and add the v3 migration below.
9. **Dead SellHistory stats read a field nothing writes.** `IM:AddHistoryEntry` writes `value`,
   never `sellPrice` (`Database.lua:384-394`), so `GetStatistics` (`SellHistory.lua:289-291`)
   always returns zeros, `ExportToString` (`:324`) prints `0c` per row, and `GetSessionTotal`
   (`:359`) would raise nil arithmetic. All three are unreferenced outside the file — latent, not
   live. `GetTodaysSales` (`:348`) also still uses UTC midnight, a bug already fixed in
   `Ledger:GetDatePresets` (`Ledger.lua:241-246`). Delete all four with item 8.
10. **The v3 migration.** Must, in ONE pass and provably idempotently: drop
    `db.global.sellHistory` AND remove it from `defaults` (because `_mergeDefaults:181-192`
    re-adds any nil default key, so deleting the data alone will not hold); normalize character
    keys **[SEE THE CORRECTION BELOW — NOT via `GetNormalizedRealmName()`]** across `characters`,
    `inventorySnapshots`, `mailHelper.alts`, `mailHelper.rules[i].alt` and
    `transactions.entries[i].char`, merging
    colliding entries by newest `lastSeen`; and repoint `dashboard.ledgerCharFilter` (an INDEX,
    `Database.lua:140`) or convert it to a key. **Verified offline in Docker Lua 5.1 by running
    `IM:InitializeDatabase()` twice against a copy of the real SavedVariables and deep-comparing
    (the second run must be a no-op). NO backup table, NO restore command, NO release gate — user
    decision on record.** Release checklist carries one advisory `cp` line.
    **CONDUCTOR CORRECTION — a second design error in this brief, and the dangerous one.**
    `GetNormalizedRealmName()` is valid ONLY for the producer (`IM:GetCharacterKey`, where the
    subject IS the current character). **It takes no argument and returns the CURRENT player's
    normalized realm** — it is not a normalizer of an arbitrary realm string. Applied to STORED
    keys it rewrites every alt's key to the running character's realm, and the "merge colliding
    entries by newest `lastSeen`" clause above then merges characters that were never the same
    character: silent, unrecoverable destruction of alts' gold and snapshot rows, with no backup.
    The migration must use a **pure string transform over the realm half of each stored key**,
    injected through the migration's `opts` — the migration is specified as a pure function with no
    WoW API, and the Docker harness stubs only `Debug`/`Print`/`PrintError`/`time`/`date`, so a WoW
    API call there is unexecutable in the proof that is supposed to catch this. The transform must
    be proven **output-equal to `GetNormalizedRealmName()` for the owner's actual realms** (print it
    in-game during W0, assert equality offline), because normalized realm names strip punctuation
    and accents, not just spaces — a naive space-strip is NOT equivalent.

11. **`GetCharacterKey` is the producer for realm drift.** `GetNormalizedRealmName` appears zero
    times in the tree. Normalize at the producer (`Database.lua:542-552`) so the class dies, then
    migrate existing keys. Without this, a realm rename or connected-realm partner permanently
    double-counts gold and the only remedy is the "delete ALL" at `Panels/Dashboard.lua:262-277`.
12. **Add per-row character delete** so a stale/transferred character can be removed without a full
    wipe. `inventorySnapshots` are also never pruned for deleted characters.
13. **`IM:SplitCharacterKey` helper** replacing the greedy `:match("^(.+)-")` at all **24** sites
    listed in the Landscape. `^([^-]+)-(.+)$` next to `GetCharacterKey`.
14. **`UpdateCharacterGold`'s zero-guard is permanent** (`Database.lua:598`) — a character who
    genuinely spends to zero keeps a stale snapshot forever, overstating net worth. Require two
    consecutive zero readings, or gate on time-since-login.
15. **Currencies are never captured**, though `C_CurrencyInfo` needs no bank or vendor visit.
    `currencyFavorites` (`Database.lua:144-146`) is the only currency state;
    `Modules/CurrencySearch.lua` is purely a search box over Blizzard's `TokenFrame`. Fix: on
    `PLAYER_ENTERING_WORLD` and debounced `CURRENCY_DISPLAY_UPDATE`, walk
    `GetCurrencyListSize`/`GetCurrencyListInfo`/`GetCurrencyInfo` and store account-wide
    currencies ONCE GLOBALLY (same rule as the warband bank) and genuinely per-character ones
    under `characters[charKey].currencies`.
16. **Ledger insert is O(n) and growth is unbounded.** `table.insert(t, 1, entry)`
    (`Database.lua:644`) shifts the whole array per transaction; `PurgeOldEntries` (`:799`) prunes
    by age only and `maxAgeDays = 0` disables it entirely (`:801`, default 30 at `:78`). Append at
    the tail, reverse in the read path, add a hard `maxEntries` cap.
17. **`_GetCachedItemInfo` is keyed two ways** — `itemLink or itemID` (`Filters.lua:515`) vs
    `info.itemID` (`:679,711`). Two entries per item, and the queue's displayed `totalValue` comes
    from a different lookup than the sell decision used.
18. **`blockLockedPost` (`Database.lua:119`) has no reader** — `AuctionHouseProtection.lua:132,157`
    always shows the confirm popup regardless of the setting.

### W4 — dashboard correctness + factory debt (fence applies: ADD ONLY)

1. **The ledger summary describes a different set than the rows.** `filters.search` goes into BOTH
   `IM:GetLedgerStats(filters)` (`Dashboard.lua:1530`) and `Ledger:GetFormattedEntries(filters)`
   (`:1532`), both routing through `IM:GetTransactions` where the test is
   `if filters.search and include and entry.link` (`Database.lua:725`) — **so every gold-only entry
   with no `entry.link` passes search unconditionally** and lands in the totals. Then
   `Dashboard.lua:1534-1555` re-filters the formatted array over a wider field set. Search "repair"
   → 4 rows shown, totals spanning the whole retention window. Fix: strip `filters.search` before
   both data calls, filter ONCE client-side over the full field set, compute income/expense from
   that same post-filter array (skipping `TRANSFER_TYPES` to match `Database.lua:750-753`), and fix
   the producer to search `entry.link or entry.src or ""`. Three callers of `GetTransactions` are
   affected and enumerated: `Database.lua:757`, `Ledger.lua:168`, `Ledger.lua:180`.
2. **Searching a character name deletes every item transaction** — item-bearing rows are dropped by
   the DB gate before the client filter at `:1544` can test `entry.charName`. Same for
   `entry.typeLabel` at `:1546`. Dies with item 1.
3. **`entry.itemName` (`Dashboard.lua:1543`) is never set** by `Ledger:FormatEntry`
   (`Ledger.lua:130-164`) — always `""`. Populate or drop the term.
4. **Ledger rows are never class-colored.** `:1625` reads `entry.charClass`, which `FormatEntry`
   never sets, so every row falls to the gray fallback — while Net Worth (`:1451`) and Inventory
   (`:1311-1315`) DO color the same characters. Fix in `Ledger.lua:158-161`:
   `formatted.charClass = (IM.db.global.characters[entry.char] or {}).class`, exactly the lookup
   `InventorySnapshot:CreateSearchResult` already does at `:479-482`.
5. **Frame leak in 2 of 3 refresh paths.** `_framePool.networth` (`Dashboard.lua:30`) and
   `.inventory` (`:32`) are declared and never read; `GetPooledFrame` is called at exactly one site
   (`:1591`, ledger). `RefreshNetWorth` creates raw frames at `:1435`, `RefreshInventory` at
   `:1097,1113,1208,1272,1326`, and both orphan the previous set with `child:SetParent(nil)`
   (`:1422-1425,1032-1036`) — which is what makes the leak permanent. Trigger is hot:
   `NetWorth.lua:47` (`PLAYER_MONEY`) and `:69` (`BAG_UPDATE_DELAYED`) → `QueueUIRefresh` →
   `Core.lua:698` → `RefreshContent`. Fix: `GetPooledFrame` + `ReleaseAllFrames` mirroring
   `RefreshLedger:1581-1619` (create FontStrings only when `not row.topLine`), and delete the
   `SetParent(nil)` loops. **The project's own CLAUDE.md claims pooling is implemented — it is, in
   one of three paths.**
6. **Dashboard bypasses the factory** — 5 raw `UIDropDownMenuTemplate` (`:503,536,569,877,936`)
   despite `UI:CreateDropdown`/`ShowDropdownMenu` already existing; 2 raw `EditBox` (`:430,811`)
   with no factory equivalent; 21 hardcoded `|cff……` literals (17 of them `|cff8c8c9b` at
   `:753,790,1018,1106,1173,1181,1233,1245,1342,1352,1356,1448,1464,1473,1697,1708,1712`, plus
   `:183,185,186,693,1298`) despite `UI.hexColors` existing and already being used at `:1560-1561`.
   **This is WHY the palette rework couldn't reach the Dashboard — it doesn't read tokens.** Fix:
   migrate the dropdowns onto the existing API, ADD a plain text-input factory (`UI:CreateSearchBox`
   — the two search boxes at `:418-485` and `:799-858` are a 60-line copy-paste including the
   debounce), replace every hex literal with `UI:ColorText`/`UI.hexColors`, and ADD
   `UI:CreateItemRow` (see item 7) and `UI:CreateHairline` (BagUI B6's producer). **All additive —
   the fence forbids changing any of the 12 frozen signatures or `CreateScrollFrame`'s geometry, and
   `UI.layout` gets new keys only.**
7. **Every item link in the Dashboard is inert.** `SetHyperlinksEnabled`, `OnHyperlinkEnter` and
   `OnHyperlinkClick` appear **zero times in the entire addon**. Rows render quality-colored
   `[Item Name]` links — the universal hover affordance — and deliver nothing; the 24×24 item icon
   at `:1281-1289` is on a plain Frame and isn't hoverable either. Fix: ADD `UI:CreateItemRow` as a
   `Button` with `SetHyperlinksEnabled(true)`, `OnHyperlinkEnter` → `GameTooltip:SetHyperlink`,
   `OnHyperlinkClick` → `SetItemRef` (gives shift-link and dressing-room free), icon `OnEnter` →
   `SetItemByID`; route `RefreshInventory` (`:1292-1300`) and `RefreshLedger` (`:1610-1652`)
   through it.
8. **Money formatting.** `IM:FormatMoney` (`Core.lua:277-294`) hardcodes `|cffffd700`, not the
   palette's `money` token `#F0B23A` (`UI/Core.lua:52`) — and because the returned string carries
   its own color codes, every surrounding `SetTextColor(unpack(UI.colors.money))` is a no-op
   (`Dashboard.lua:292,303,320,348,1456`). It always appends silver and copper (headline reads
   `4,312,908g 44s 12c`) and returns `"0c"` for zero. Fix: point the gold segment at
   `UI.hexColors.money`, suppress silver/copper above 1000g, ADD `IM:FormatMoneyIcon` using
   `GetCoinTextureString` for the five headline rows (`:1409-1413`), ADD `IM:FormatMoneyShort`
   (`4.31M`/`312.4k`) for the per-character column (`:1455,1463-1465`).
9. **Long names wrap into rows too short for two lines** — `:1292-1294` (48px row also holding a
   location line) and `:1610-1614` (32px row); FontStrings word-wrap by default, so text collides
   or clips mid-glyph with no ellipsis. `SetWordWrap(false)` + `SetMaxLines(1)`; the tooltip from
   item 7 then carries the full name.
10. **Search boxes are `SetSize(320, 20)`** (`:431,812`) in a 420px-default frame (`:91`) with 8px
    insets (`:225-226`) ≈ 404 usable — clipped out of the box, and `OnSizeChanged` (`:132-159`)
    resizes only the three scroll children, never the inputs. Anchor `RIGHT` with an inset instead
    of `SetSize` and it tracks every resize for free. (W0 item 5 settles whether the third filter
    dropdown also overflows at the 350px minimum, `:101`.)
11. **The ledger character filter is persisted as an INDEX** (`:607`) into an alphabetically-sorted
    list re-derived at `:618-630`; a newly-transacting character shifts every index by one, so
    after a reload the filter shows a name and the rows belong to someone else. `typeIndex`/
    `dateIndex` (`:521,554`) share the flaw latently. Persist identities (`ledgerCharKey`,
    `preset.label`), keep the index as runtime state.
12. **Inventory filter state is discarded on reload** while the ledger persists four keys, and
    neither `_inventoryPaginationLimit` (`:764`) nor `_paginationLimit` (`:24`) is reset on
    `Dashboard:Show` (`:1741`) or tab switch (`:201-215`) — so reopening after "Show More" re-renders
    up to 300 rows as the first paint.

### W5 — features whose data is already computed and thrown away

1. **Nothing renders any timestamp.** `charData.lastSeen` (`Database.lua:570,604`) is carried into
   `charInfo` (`NetWorth.lua:358`) and consumed by nothing; `lastInventoryUpdate`
   (`NetWorth.lua:262`), `snapshot.timestamp` (`InventorySnapshot.lua:271`), `bankTimestamp`
   (`:307`), `reagentBankTimestamp` (`:329`) all have ZERO display consumers; the Inventory summary
   even stores `timestamp` per entry (`Dashboard.lua:1068,1082`) and only sorts by count. Only
   warband GOLD gets an "as of" line, and only in the settings panel
   (`UI/Panels/Dashboard.lua:42-46`) — the one place a user won't look. **An alt not logged in for
   six months contributes its gold to the headline total with the same visual authority as live
   data.** Fix: age column on Net Worth character rows (`:1459-1465`), per-source age on Inventory
   summary rows (before the `>` arrow at `:1171-1173`) and in browse-mode header (`:1243-1245`) and
   in the character dropdown (`:917`), and a stale suffix on the Warband Bank row (`:301-304`).
   Escalate `textDim` → `warning` past 7 days → `error` past 30. **This is the highest
   trust-per-line-of-code item in the whole plan and it is the honest answer to requirement 5.**
2. **No trend — "am I richer than last week" is unanswerable.** No gold history is stored (no
   `goldHistory` anywhere; `characters[charKey]` holds only current `gold`). Fix without a new
   table: a delta line under Total Net Worth (`:346-349`) from
   `IM:GetLedgerStats({minDate = time()-7*86400}).netGold`, rendered `↑ +142,000g` in `success` /
   `↓` in `error`, **labelled "gold flow, 7 days" not "net worth change"** because that is what it
   honestly is. For a true curve later, append `{ts, netWorth}` to a capped ring buffer in
   `NetWorth:OnPlayerLogout` (`:136`) — one entry per logout — and draw a sparkline.
3. **No share-of-total** (`:1432-1468`) — nine rows of large numbers; working out that the banker
   holds 78% is manual division per row. Fix: a `money`-token texture at ~0.18 alpha behind each
   pooled row, width-scaled to `charInfo.netWorth / breakdown.total.netWorth`, plus a right-aligned
   `12.4%` in `textDim`. Turns the list into a distribution chart at zero interaction cost.
4. **Character rows are dead ends** — plain `Frame`s (`:1435`), no `OnEnter`/`OnClick`, and sort
   order is hardcoded `netWorth` descending inside the module (`NetWorth.lua:365-367`) so the UI
   cannot offer one. Contrast the Inventory summary rows (`:1113-1149`), which are proper Buttons.
   Fix: Button (free with item W4-5's pooling), `OnClick` → set `_ledgerFilters.charKey` +
   `frame.SelectTab("ledger")`, right-click → Inventory tab; add a clickable column header row
   above `:357-366` toggling a view-level `_networthSort`.
5. **"Total Net Worth" mixes gold with a partial proxy.** `inventoryValue` is vendor sell price only
   (`NetWorth.lua:161`), is `0` for any character never logged in with the addon, and includes bank
   contents only if a bank happened to be open — and the character sort ranks on this hybrid
   (`:365`), so a freshly-scanned alt outranks a richer un-scanned one. Fix: rank by `gold`
   (comparable across all characters), keep net worth as a secondary column, rename the row at
   `:324-332` to `Inventory (vendor value)`, and make "Liquid Gold" (`:313-321`) the visually
   dominant figure. Replace the vague "Inventory requires vendor price data (login to each
   character)" hint (`:352-354`) with a live `Inventory value missing for 4 of 9 characters`.
6. **The Ledger is a flat tape with no grouping or category totals** (`:1587-1664`, 10 rows at a
   time, `:24`) — despite `IM:GetLedgerStats` ALREADY returning `stats.counts[type]`
   (`Database.lua:772`) and `Ledger:GetTypePresets` (`:258-274`) already grouping all 40 types into
   13 semantic buckets. "Where did my gold go this week" currently takes 13 dropdown selections
   with hand-written arithmetic. Fix: a collapsible "By category" block between the summary box
   (`:635`) and the Transactions header (`:712`), computed from the same post-filter array as W4-1;
   `UI:CreateRailRow`-style lines with label left, net right in `success`/`error`, and a 2px
   `money`-token bar scaled to `|net| / maxAbsNet`; each row click-through to that type filter.
   **This is what turns the tab from a log into a ledger.**
7. **Default date filter is "All Time"** (`:18,410` → `dateIndex = 5`, `Ledger.lua:253`) — the
   least useful option and the most expensive first paint. Make it `3` (Last 7 Days), which also
   makes the summary box a de-facto weekly report.
8. **`Ledger:ExportToString` (`:179-222`) is filter-aware, strips color codes, has a header row —
   and zero callers**, while the sell-history equivalent IS wired to a button
   (`UI/Panels/History.lua:230`). Fix: an Export button in the bottom bar (`:239-257`) passing the
   CURRENT filter object built at `:1496-1524`, result in a `UI:CreatePanel` with a read-only
   multiline EditBox + `HighlightText()`, following the History pattern.
9. **`Ledger:GetSummaryString` (`:225`) and `NetWorth:GetSummaryString` (`NetWorth.lua:385`) have
   zero callers.** Decide: wire or delete. Do not leave them.
10. **Inventory answers "which alt" but not "how much total"** — one row per STACK, sorted
    alphabetically (`InventorySnapshot.lua:435-439`), 15 at a time, so "Ore" returns 30
    near-identical rows and the total needs hand-addition across pages. **`GetTotalItemCount`
    (`InventorySnapshot.lua:575-593`) already sums an item across every character AND the warband
    bank, and has zero callers.** Fix: group by `itemID` after `:1199` — one parent row per item
    with icon, link and right-aligned `N total` in `money`, per-character/per-location stacks as
    indented 20px sub-lines with the class colors already applied at `:1311-1315`, groups sorted by
    total descending, plus a `N items across M characters` count. **This is what makes the tab worth
    opening.**
11. **The Location filter is silently ignored in the default view.** `showSummary` is true whenever
    search is empty and `charIndex == 1` (`:1042`), and the summary branch returns at `:1186`
    without ever consulting `_inventoryFilters.location`. The dropdown accepts input, relabels
    itself, and changes nothing — worse than being disabled, because the user concludes the DATA is
    wrong. Fix: use it to choose which counts to sum (`:1054-1056` already breaks out
    `bags`/`bank`/`reagentBank` separately, so it's a one-line change) and reflect it in the header;
    or `Disable()` the dropdown while `showSummary`.
12. **"items" counts stacks, not items.** `:1054-1056` sums `#snapshot.bags` (occupied slots) and
    labels it `N items` (`:1168`); `:1089` does the same into `(N total items)`, and the summary
    sorts by this figure (`:1087`). 200 slots of single arrows reads "200 items"; 40 stacks of 200
    ore (8,000 items) reads "40". Fix: sum `item.quantity`, show `N stacks · M items` — both are
    useful, keep both.
13. **The Tips card claims "Ledger tracks gold only, not item transfers (yet)"**
    (`UI/Panels/Dashboard.lua:340`) — false: `Ledger.lua:34-35,54-57,64-65` define eight
    item-transfer types and the "Bank" preset filters them (`:271`).
14. Carry the `(Click character to browse)` hint pattern (`:1106`) to any newly-clickable row from
    item 4. **Discoverability is otherwise genuinely fine** — `/im dashboard` + `/im d`
    (`Core.lua:394-404`), four minimap paths (`MinimapButton.lua:84,235,307,324`), three settings
    deep-links (`UI/Panels/Dashboard.lua:73-110`, correctly targeting the `"Tracking"` tab present
    at `UI/Config.lua:22`), login advertisement (`Core.lua:361`), word-labelled tabs (`:189-193`),
    ESC closes (`:162`). Do not "fix" it.

### W6 — mail + vendor popup convergence

1. **The vendor popup never says WHY an item qualified**, though `Filters:GetAutoSellItems` returns
   `reason` per item (`Filters.lua:719`) from 12 labelled exit points (`:498-642`) and
   `AutoSellPopup:RefreshItems` (`:192-229`) drops it. The only "why" is one bottom line,
   `"Selling: Uncommon and below"` (`:165`), which is **wrong for junk-list items** — they override
   the quality gate entirely (`Filters.lua:553-562`). Fix: shift `itemLabel`'s right anchor from
   `-60` to `-140` (`:212`) and insert a reason column, `UI:ColorText(item.reason, ...)` with
   junk-list rows in the amber `warning` token precisely because they bypassed protections; replace
   the single filter line with `"6 by quality · 2 on junk list"`. **Cheapest high-value fix in the
   plan.**
2. **The sell list is capped at 8 inside a scroll frame that therefore never scrolls** —
   `maxItems = 8` then `"... and X more"` (`:187,232-237`), with content height set from the capped
   list (`:252`), so items 9..n are unviewable and the scrollbar is inert. No per-item opt-out, no
   right-click-to-protect. Contrast the mail popup, which renders every queued item with no cap
   (`MailPopup.lua:186`). Fix: remove the cap, make each row a Button with the tooltip/hyperlink
   treatment from W4-7, `OnClick` → `IM:ToggleWhitelist(item.itemID)`, plus a red
   `UI:CreateGlyphButton(row, "X", UI.colors.error)` that whitelists and refreshes — one click turns
   "about to be sold" into "protected forever", which is the action a user actually wants at that
   moment. Footer hint in the existing `bottomBar`.
3. **Buyback is the only undo and the UI never mentions it.** `ItemLock._CheckAndBuybackLockedItems`
   (`:134-168`) already scans `GetBuybackItemLink(1..12)` and repurchases — but only for
   WHITELISTED items, i.e. the case where selling shouldn't have happened at all. For a normal
   mis-sale there is no undo and no text telling the player WoW will sell it back at cost before
   they leave. Fix: an "Undo last sale" `UI:CreateButton` in `bottomBar`, shown only when
   `GetNumBuybackItems() > 0` and the last run sold something (track itemIDs in `_sessionStats`),
   walking the buyback list. **Even without the button, change the `FinishSelling` (`:310-318`)
   chat line to name buyback.** The wording alone is worth shipping.
4. **Repair has a silent dead branch.** With `useGuildFunds = true` and `fallbackToPersonal = false`
   (`Database.lua:37-40`), if the guild can't pay, the guard at `AutoRepair.lua:84` is false, the
   function falls through to `return false` at `:102`, and **nothing prints** — gear stays broken
   with no explanation. Fix: an `else` at `:93` naming the cause and the next step (guild balance,
   repair cost, which setting to change).
5. **Repair is invisible in the popup.** `AutoRepair:GetRepairCost()` (`:117-122`) exists with zero
   callers. Fix: when `CanMerchantRepair()`, show cost under `totalValueLabel` with the funding
   source, and after a repair show the source actually used.
6. **Zero progress feedback during a sale and no way to stop one.**
   `AutoSellPopup:UpdateStatus(message)` (`:291-295`) has a body of
   `-- Could update a status label if needed` and is called from nowhere; selling walks the queue at
   0.15s/item (`AutoSell.lua:282`) so 40 items is a six-second sale showing the unchanged pre-sale
   list. `AutoSell:CancelSelling()` (`:92-99`) is fully implemented with **no UI affordance** — a
   sale can't be stopped except by closing the merchant. Fix: implement the stub against the shape
   the mail popup already proved (`MailPopup.lua:312-342`); `sellBtn.text` → `"Stop"` while
   `_isSelling`, routed to `CancelSelling`.
7. **Merchant rejections are debug-only.** `AutoSell.lua:289-302` marks `_rejectedItems`, backs the
   stats out and moves on (`:294`); same for "item moved" (`:218`) and "no longer passes filters"
   (`:245`). An item no vendor will buy is indistinguishable from one that sold. Fix: accumulate
   `_sessionStats.rejected`, append to the `FinishSelling` line, and keep rejected rows visible
   greyed in the reason column from item 1.
8. **Every mail failure is invisible.** `OnMailFailed` (`MailHelper.lua:256-259`) is
   `_currentRecipient = nil` plus an `IM:Debug` line, which prints nothing unless `/im debug` is
   on. A recipient typo, a full mailbox, a mail throttle and "you can't mail that" all land in the
   same hole. **Rule creation accepts any string as a recipient** (`Panels/MailHelper.lua:399-400`)
   and appends the current realm with no validation, though `MailHelper:GetAlts()` (`:262-294`)
   holds every known character. Fix: `IM:PrintError` naming cause + next step + the rule name,
   surface it on the popup's status line, and warn at Add-Rule time when the recipient isn't a
   known character.
9. **The 12-attachment cap is silent** (`MailHelper.lua:594-621`) — Send on a 30-item queue looks
   complete, `OnMailSendSuccess` wipes the whole queue (`:248`), and the popup refreshes off a
   fixed `C_Timer.After(1, ...)` (`MailPopup.lua:174-177`) that races the async send: if the send
   confirms slower than 1s, the queue shows items already in the mail. Fix: report `"Sent 12 of
   30"`, label the button `"Send 12/30"` via `sendBtn.text:SetText`, and chain on
   `MAIL_SEND_SUCCESS` rather than a timer (folds into W1-6).
10. **Postage is never shown before committing** — Send All across 4 alts silently spends 1s 20c.
    Fix: a second summary line, `ceil(items/12)` mails × 30c. (Logging is W2-15.)
11. **No preview, no confirm, no per-item opt-out, and rows aren't inspectable.**
    `MailHelper:RemoveFromQueue` (`:548`), `ClearAltQueue` (`:558`), `ClearQueue` (`:566`) and
    `AddToQueue` (`:531`) are **called from nowhere in the tree**; item names are FontStrings on
    plain `Frame`s (`MailPopup.lua:187-210`) with no `EnableMouse` and no `SetHyperlinksEnabled`, so
    you cannot hover to see what an item is or shift-click it. **You are asked to approve a list you
    cannot inspect.** Fix: rows as Buttons with tooltip + `CHATLINK` handling, plus an X glyph
    wired to `RemoveFromQueue` — which also wires up the dead API.
12. **Rules cannot be tested and 4 of 5 filter types are unreachable.** `AddRule` hardcodes
    `filterType = "classID"` (`Panels/MailHelper.lua:405`) and the validator rejects anything but
    `%d+`/`%d+_%d+` (`:395`), while `FILTER_TYPES` implements `quality`, `name`, `vendorPrice` and
    `soulbound` (`MailHelper.lua:35-146`). The user is told to type raw class integers and go hover
    items to find them (`:433-434`), with no "matches N items" preview, so a rule's blast radius is
    unknown until the mailbox opens. Fix: (a) a live match count in `RefreshRulesList` (`:290,352`)
    — free, because `AddRule` already triggers `AutoFillQueue` — plus a Preview button running the
    typed filter without saving; (b) replace the numeric EditBox with `UI:CreateDropdown` over
    `IM.ITEM_CLASS_NAMES` (`Filters.lua:86-103`) and a subclass dropdown via `GetItemSubClassInfo`
    (the row renderer already decodes these for display at `:329-344`), and expose `soulbound`
    (W1-5 depends on it).
13. **Mail Helper needs a `/reload` to turn on, with no hint.** `OnEnable` returns early before any
    `RegisterEvent` when `mailHelper.enabled` is false (`MailHelper.lua:148-154`); the checkbox
    flips the flag and calls `AutoFillQueue` but never registers `MAIL_SHOW`, so enabling it
    mid-session appears permanently broken. `OnMailShow` already re-checks `enabled` at `:196`, so
    **the guard at `:151` is redundant AND harmful** — delete the early return, move the queue
    restore below it.
14. **`sendAllBtn:SetText("Send All")` (`MailPopup.lua:228`) is a silent no-op** —
    `UI:CreateButton` never calls `SetFontString` (`UI/Core.lua:526-530`), so `Button:SetText`
    writes to a fontstring that doesn't exist. Harmless here (the label is already right from
    construction) but it is exactly the anti-pattern the project's own CLAUDE.md documents, sitting
    in shipped code; the correct form is used at `:315,334,348`. **Durable fix: ADD
    `button.SetText = function(self,t) self.text:SetText(t) end` in the factory
    (`UI/Core.lua:530`) — provably invisible to BagUI (see fence).**
15. **`Disable()`/`Enable()` on a factory button has no visual effect** — the factory defines no
    disabled appearance, yet both popups call them (`AutoSellPopup.lua:154,158`;
    `MailPopup.lua:320,338,352`), so a dead Sell All looks identical to a live one. Fix in the
    factory: also set `button.text:SetTextColor(unpack(UI.colors.textDisabled))` (token exists at
    `UI/Core.lua:37`) and drop the backdrop, restoring on enable. **Provably invisible to BagUI.**
16. **Both popups destroy and rebuild every row per refresh** (`MailPopup.lua:124-127,152-217`;
    `AutoSellPopup.lua:178-181,192-229`) via `child:Hide(); child:SetParent(nil)` then `CreateFrame`
    — against the project's own pooling mandate. In the mail popup this runs on a 0.3s-debounced
    `BAG_UPDATE` (`:263-272`), and `BAG_UPDATE` fires **per mail looted**, so auto-looting 40 mails
    churns hundreds of frames WoW never reclaims. `UI/Panels/History.lua:116-119` repeats the
    pattern. Fix: ADD a shared `UI:AcquireItemRow`/`ReleaseItemRows` keyed by parent next to
    `CreateItemListRow` (`UI/Core.lua:1482`), hiding rather than reparenting; convert all three.
17. **Protections are invisible at the moment they matter.** The overlay system is good
    (`OverlayFactory.lua:407-475`, priority-ordered) but it paints ITEM BUTTONS, and `ItemLock`
    refreshes them 0.2s after `MERCHANT_SHOW` (`:99-101`) — the exact tick `SellJunk` starts
    (`AutoSell.lua:71-74`). A player with closed bags (the normal case at a vendor) sees no
    protection state at all, and the popup carries no whitelist/junk marker. Fix: fold it into the
    popup — the reason column from item 1 plus a `UI:ColorText(n .. " protected", "success")` count
    in the summary, from the same bag scan.
18. **Layout tokens used as vertical offsets** — `AutoSellPopup.lua:77,83` use
    `UI.layout.buttonWidth` (80) as a Y offset, and `MailPopup.lua:223` computes
    `totalHeight = UI.layout.buttonWidth + ...`, with the height clamp at `:224` inheriting the
    coupling. Works today by coincidence; silently shifts both item lists the day button widths are
    tuned. **ADD** a `contentTopOffset` key (the fence permits new keys).
19. **Scroll content width snapshotted before layout** (`MailPopup.lua:58-61`,
    `AutoSellPopup.lua:95-98`) — `scrollContent:SetSize(scrollFrame:GetWidth(), 1)` at Create time
    while the popup is hidden and two-sided anchors haven't resolved. Marked probable, settled by
    W0-5. Fix is free either way: set the width at refresh time when shown.
20. **Consistency: the popups converged on paint, not interaction.** Both are 280px, `MakeRounded`,
    `DIALOG` strata, `CreateHeader`, draggable, `UISpecialFrames` — but they diverge on item cap,
    per-row value, progress contract, cancel affordance, auto-refresh, close-with-parent
    (`MailFrame:HookScript("OnHide")` vs `MERCHANT_CLOSED` only) and height strategy. Fix, **last,
    once both call sites have stopped moving**: hoist a shared `UI:CreateQueuePopup(name, title,
    opts)` owning frame/header/scroll body/bottom bar/progress line/Stop wiring, leaving each file
    only a row renderer and an action handler. That is the honest version of the convergence the
    recent commits started, and it makes items 2/6/16/19 one fix each instead of two.

### W-BagUI — invisible-only fixes (the five visible ones are approval-gated, see below)

1. **B1 — closing the bag with the header X or ESCAPE leaves `_isVisible` stuck true, and the
   hidden window rebuilds itself forever.** `UI/BagUI/Core.lua:20,631-646,657-659,669-670,583-601`.
   BagUI keeps a parallel visibility flag maintained only inside its own `Show`/`Hide`, but two
   FACTORY-installed controls hide the raw frame directly and never route through them:
   `CreatePanel`'s `OnKeyDown` ESCAPE (`UI/Core.lua:400-406`) and `CreateHeader`'s close button
   (`UI/Core.lua:509-511`). There is no `OnHide` script to reconcile. Consequences:
   `BAG_UPDATE_DELAYED` and `PLAYER_EQUIPMENT_CHANGED` still see `_isVisible == true` and run a
   full teardown/rebuild of every item button + `GatherItems` + all overlay recomputation +
   `FitHeightToContent` **on an invisible window, indefinitely**; `RecentItems:MarkAllSeen()`
   (`:632-635`) never runs so Recent markers never clear; and `Toggle()` (`:649-655`) needs two `B`
   presses to reopen. Fix: add `frame:SetScript("OnHide", ...)` in `Create()` doing the
   `MarkAllSeen` + `ClearSearchFilter` + flag bookkeeping, and make `BagUI:Hide()` just call
   `_bagFrame:Hide()` — or make `_isVisible` a derived read of `IsShown()`. **Do NOT fix this by
   changing `CreatePanel`/`CreateHeader` — those are fenced.** Note: the audit labelled this
   `[VISIBLE]` because the close sound moves to the X/ESC paths and Recent markers start clearing
   on those paths (which matches the documented intent at `:626-630`). **Treat as approval-gated
   with a strong recommendation — the performance win is large and the behavior change is small.**
2. **B3 — no canonical bag iterator, so 3 of 6 call sites forgot the nil guard.**
   `CategoryView.lua:347-348` iterates `1, numSlots` with no `or 0`, and is called from
   `CategoryView:Refresh` **outside** the `pcall`s at `:158,195`; `BagUI/Core.lua:727-728` compares
   nil with a number and aborts `Refresh`; `BagData.lua:287,297` likewise. Guarded sites for
   contrast: `BagUI/Core.lua:910,915`, `ItemButton.lua:53`, `RecentItems.lua:174,193,227`,
   `CategoryView.lua:372`. With script errors off, a bag swap renders nothing after the pools were
   already released. **Upstream fix: one shared `IM:ForEachTrackedBagSlot(fn)` / at minimum
   `IM:GetTrackedBagIDs()` + `or 0`, routing all six sites through it — which also kills BagData's
   hardcoded `5` vs `Enum.BagIndex.ReagentBag` divergence.** `[INVISIBLE]`
3. **B5 — `ItemButton:Clear` zeroes the SHARED virtual bag frame's ID.** `ItemButton.lua:257-280`
   (esp. `:264-267`) does `button:GetParent():SetID(0)`, but that parent is the per-bag virtual
   frame cached in `scrollContent._imBagFrames` (`:317-329`) and **shared by every button in that
   bag**; `ReleaseAll` (`:244-255`) calls `Clear` on each active button, stomping it repeatedly. Any
   virtual bag frame not re-populated next pass (e.g. all its items filtered out by search) keeps
   `ID == 0` and claims to be the backpack. Latent today because `SetItem` re-asserts
   `bagFrame:SetID(bagID)` at `:341` and stale buttons are hidden — but
   `ContainerFrameItemButtonTemplate` resolves which item you are clicking from exactly that field,
   so this is the "using an item acts on the wrong bag" class. Fix: delete the line; virtual bag
   frames are permanent identity holders, set the ID once at creation (`:323`). Keep
   `button:SetID(0)`. `[INVISIBLE]`
4. **B4 — MasonryLayout's non-positive-width "safety check" is a no-op and a negative width reaches
   `header:SetSize`.** `MasonryLayout.lua:155-162`: the guard recomputes the identical expression it
   just rejected, yielding `-12` for `containerWidth = 0` and `-52` for the `CategoryView:191`
   fallback; the negative width goes to `header:SetSize` (`CategoryView.lua:794`), errors, and the
   error is swallowed by the per-section `pcall` at `:708` — producing "Bag section 'X' failed to
   render" for every section. Reachable because `Create()` (`BagUI/Core.lua:465-467`) never seeds
   `scrollFrame.content:SetWidth(...)` the way `ResizeForSettings:874-889` explicitly does, so the
   first render depends entirely on the factory's `OnSizeChanged` having fired. Fix: make the guard
   real with a `math.max` floor, have `GetItemsPerRow` reject non-positive input explicitly instead
   of relying on `math.max(1, ...)` masking it, and seed the scroll-child width in `Create()` with
   the same expression `ResizeForSettings` uses. `[INVISIBLE]` — only changes a path that currently
   prints errors and draws nothing.
5. **B7 — per-refresh `string.format` and a `pairs(button)` scan run whether debug is on or off.**
   `IM:Debug` (`Core.lua:174-181`) no-ops when disabled but its ARGUMENTS are evaluated first:
   `ItemButton.lua:343` runs a format with four `GetID()` calls **per item per refresh**;
   `CategoryView.lua:182` five `GetWidth()` calls plus a format per refresh; more at
   `ItemButton.lua:334-335`, `CategoryView.lua:202-203,216-217,221,732-733,763`,
   `MasonryLayout.lua:164-165,179,239-240`, `BagUI/Core.lua:197-198,820,852,869,887`. Separately
   `SetItem` calls `SetItemCraftingQualityOverlay` then walks **every key of the button table**
   (`:464-477`) calling `GetAtlas()` on each table-valued child, per item per refresh, and
   permanently re-anchors Blizzard's overlay each time. Given B1 keeps this running on a hidden
   window and B6 is undebounced, this is the dominant garbage source during looting. Fix: add an
   `IM:IsDebug()` predicate and guard the hot-path calls (or delete the per-item ones outright);
   cache the resolved overlay child as `button._imCraftingPip` on first discovery. `[INVISIBLE]`
6. **B8 — `BAG_UPDATE_DELAYED` and `PLAYER_EQUIPMENT_CHANGED` trigger an undebounced full rebuild.**
   `BagUI/Core.lua:581-602` calls `Refresh()` synchronously; the search path IS debounced (0.15s,
   `:42-58`) and the settings sliders are (0.12s, `Panels/BagUI.lua:109-135`).
   `PLAYER_EQUIPMENT_CHANGED` fires **twice per swap** and once per slot on an equipment-set change
   — up to ~16 full rebuilds for one click — and `BagData.lua:486-488` queues its own refresh on the
   same event, doubling the work. Each rebuild is `ReleaseAll` + `GatherItems` (up to 3×
   `GetItemInfo` per item) + full `SetItem` of every button + `OverlayFactory:Update` per item
   (which calls `Filters:ShouldAutoSell`) + `FitHeightToContent`. Fix: one `BagUI:QueueRefresh()`
   using the existing debounce shape at `:49-57`, routing both handlers through it; keep `Show()`
   calling `Refresh()` directly so opening stays instant. **`[INVISIBLE]` at 0.15-0.2s;
   `[VISIBLE — needs approval]` if set to the 0.5s the project standard names, since half a second
   of stale icons after a loot is perceptible. Plan the 0.2s version.**
7. **B9 — `button._imOverlay` is a dead frame created once per pooled button.** Created at
   `ItemButton.lua:212-216`; the only other reference is the always-empty child loop at `:270-274`.
   `UpdateOverlay:494-501` passes **`button`**, not `button._imOverlay`, to `OverlayFactory:Update`,
   which parents its own overlay to the button (`OverlayFactory.lua:180-184`). The overlay system
   moved and the old per-button frame was never removed. Cost: one orphan Frame per pooled button —
   **200+ pre-created at `PLAYER_LOGIN`** (`CalculatePoolSize:65`), none ever drawn — plus a wasted
   `{...:GetChildren()}` table allocation per button per `ReleaseAll`. Delete `:212-216` and
   `:269-274` (grep confirms nothing else touches `_imOverlay`). `[INVISIBLE]`
8. **B12 — override-binding calls have no `InCombatLockdown` guard.**
   `BagUI/Core.lua:961-1002`, called from `:1365,1381-1382,1390,1424` and
   `Panels/BagUI.lua:71,94`. `SetOverrideBindingClick`/`ClearOverrideBindings` are combat-restricted
   and two call sites are event handlers that can fire in combat (`UPDATE_BINDINGS` `:1379`,
   `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/_HIDE` `:1387,1408`); `_toggleButton` is a
   `SecureActionButtonTemplate` whose OnClick is swapped at runtime (`:1393,1418-1422`), also
   protected. Worse than an error: `:1381-1382` clears then re-sets, so a failure between the two
   leaves the user with **no working bag key** until the next `UPDATE_BINDINGS`. Fix: one
   `BagUI:ApplyBindingOverrides()` that both Setup and Clear route through, deferring to
   `PLAYER_REGEN_ENABLED` when locked down. Unverified in-game; the API restriction is documented.
   `[INVISIBLE]`
9. **B13 — dead code.** Resize scaffolding: `SetResizable`/`SetResizeBounds` (`:246-247`),
   `resizeGrip` (`:550-561`) **which is `Hide()`n at `:553`**, and `BagUI:OnResize` (`:780-797`) —
   the grip is the only caller of `StartSizing`, so `OnResize` and its `settings.height` persistence
   are unreachable. `ItemButton:ResizeButton` (`:553-558`) has no callers and a **different scale
   contract** from `ResizeAll` (`:560-571`) — it divides by 37 without the `+17` border
   compensation, so it would be wrong if called. `BagUI/Core.lua:906-920` computes `totalSlots`/
   `defaultItemsPerRow` then discards them (`:924` hardcodes 10). `settings.scale` (`:936`) never
   read. `settings.columns` read at `MasonryLayout.lua:350`, never written, and `Calculate:131`
   forces `columns = 1` anyway. `SIZING.SCROLL_CONTENT_INSET` (`:131`) declared, never read (the
   literal `22` is used at `:885` instead). `ItemButton.lua:290` gates a dump on
   `IM.db.global.debugMode`; **the real flag is `debug`** (`Core.lua:175,500`), so `:289-303` is
   unreachable. Fix: delete all of it (git is the archive); either use `SCROLL_CONTENT_INSET` at
   `:885` or delete it; fix or delete the `debugMode` block. **If the user wants edge resizing back
   that is a feature request, not a cleanup — ask, don't assume.** `[INVISIBLE]`
10. **B14 (invisible half) — the button pool can never grow, so items silently vanish.**
    `ItemButton.lua:48-66` sizes the pool `max(totalSlots × 2, 200)` once at `PLAYER_LOGIN` and
    `:72-73` refuses to re-run, so later bag upgrades aren't accounted for; on exhaustion
    `Acquire` (`:230-242`) returns nil and `RenderCategory:756-757` **silently skips the item** with
    only a debug line. Fix: grow on demand — `_buttonPool[#_buttonPool+1] = self:CreateButton(...)`
    — which removes the failure mode entirely rather than raising a constant. `[INVISIBLE]`
    (The duplicate-render half is approval-gated, below.)
11. **B15 — convention drift.** Missing `_` prefix on file-local helpers:
    `ItemButton.lua:48` (`CalculatePoolSize`), `CategoryView.lua:583` (`IsCurrencyToken`),
    `BagUI/Core.lua:509` (`CreateMeter`), `:1112` (`CloseAllBagFrames`). ~11 others are correct, so
    the convention is followed ~80%. Fix: rename the four. `[INVISIBLE]`
12. **B15 (lifecycle) — the subsystem has no module lifecycle at all.** `BagUI` is not a registered
    module; it hangs off `IM.UI` and registers four `IM:RegisterEvent` handlers **at file scope**
    (`BagUI/Core.lua:1343,1379,1387,1408`), as does `BagIntegration` (`:293`), and
    `BagUI:RegisterEvents` (`:581`) is called from inside `Create()`. Consequence: those four
    handlers cannot be unregistered or reordered, which is why `Create()` has to be called from
    inside a `PLAYER_LOGIN` handler that also does hooking and conflict detection (`:1343-1376`).
    `CustomCategories.lua:266-268` has an `OnInitialize` that is a comment only.
    **Do NOT force BagUI into `RegisterModule` — that buys nothing and reshuffles load order.**
    Fix: either give it a `BagUI:OnLogin()` that the single `PLAYER_LOGIN` handler calls (so the
    sequencing is readable), or add one sentence to CLAUDE.md stating that `UI.*` namespaces use
    file-scope registration by design. `[INVISIBLE]`
13. **`RecentItems:OnEnable` returns early and silently if `BagData` is absent**
    (`RecentItems.lua:90-94`), permanently disabling own-flag tracking with no diagnostic — which
    would make the Recent section cover only Blizzard's flags, a partial invisible degradation
    (`Diagnose:215-220` would reveal it). Add a diagnostic. `[INVISIBLE]`
14. **The highest-risk hidden coupling in the subsystem, for the record:** lock/junk CLICKS are not
    handled by BagUI at all — `ItemButton.lua:218-221` relies on `ItemLock`/`JunkList` hooking
    `ContainerFrameItemButtonMixin.OnClick` (`ItemLock.lua:414`, `JunkList.lua:48`), which works
    only because these buttons inherit `ContainerFrameItemButtonTemplate`. **If `ItemLock`/
    `JunkList` ever switch to hooking Blizzard's NAMED bag buttons, Alt+Click dies in the custom bag
    with no error.** No wave changes those hooks — but W1/W6 touch `ItemLock`, so the plan must
    state this as a do-not-break invariant with a smoke check.
15. **`IM.ITEM_CLASS_NAMES` is a hand-synced ordering key.** `CategoryView.lua:601,625` reads it
    un-nil-guarded, and `GetCategoryOrder:647-659` keys on the DISPLAY STRING — so renaming a value
    silently re-labels AND re-orders bag categories. Real fragility; note as an invariant.
    Also for the record: **`CustomCategories` has no effect on the custom bag view** —
    it is consumed only by `BagData._GetItemCategory` (`BagData.lua:167-172`) and the bag UI does
    not use `BagData` at all (it scans containers directly, `CategoryView.lua:341-397`), despite
    `CustomCategories.lua:4` saying "Custom category management for the Bag UI". Missing feature,
    not a regression — **surface to the user as a question, do not build it.**

#### W-BagUI approval-gated items (present to the user ONE AT A TIME; do not implement unapproved)

- **B2** — `FitHeightToContent` (`BagUI/Core.lua:693-711`) ignores 28px of `CreateScrollFrame`
  chrome (container insets 10+10 at `UI/Core.lua:1016-1017`, ScrollFrame insets 4+4 at
  `:1029-1030`), so the viewport is always ~20px shorter than the content it must show: the last
  row is clipped and a scrollbar appears even though the window was just sized to fit. Fix by
  MEASURING (`_bagFrame.scrollFrame.scrollFrame:GetHeight()`, exposed at `UI/Core.lua:1146`) rather
  than adding a fourth mirrored constant. **Visible: the window grows ~20px and the scrollbar
  disappears when content fits — a hand-tuned dimension.** Unverified in-game.
- **B6** — the rail's two hairlines never render: `railRule` (`:391-395`) and `railHeadingRule`
  (`:406-410`) are created, sized, anchored and `SetVertexColor`'d but **never call `SetTexture`**,
  so they draw nothing (compare the working `footerRule:476-481`). The design intent is spelled out
  in the comments at `:384-385` and `:397-399`. **Visible: adds two lines to the window the owner
  has never seen.** Root cause is the absence of a `UI:CreateHairline` factory (added in W4-6).
- **B10** — palette violations: the RETIRED amber `|cffffb000` is still used at
  `Panels/BagUI.lua:240,241(×2),242,243,244` and `UI/BagIntegration.lua:181`, so the bag settings
  Tips card renders in the old accent and clashes with the cyan used elsewhere in the same window.
  Plus hardcoded colors at `BagUI/Core.lua:330,1254,1276,1309,1336`, `CategoryView.lua:140,142`
  (a grey that is neither `textDim` nor `textDisabled`), `Panels/BagUI.lua:30,50,66,69,89`,
  `Panels/UI.lua:49,69,80,91,102`. **Ancestor**: `OverlayFactory`'s `COLORS` table
  (`OverlayFactory.lua:44-65`) is a SECOND palette with no relationship to `UI.colors`; `SetColors`
  (`:511-527`) exists, nothing calls it, and its own comment admits existing overlays won't update.
  The `Panels/UI.lua:69,80,91,102` swatches restate overlay colors and should be sourced from
  `OverlayFactory:GetColors()`. **Visible: every one changes an on-screen color.**
- **B11** — in `subcategory` mode, uncached items are stuck in "Other" until an unrelated bag event.
  `GetItemSubcategory` (`CategoryView.lua:606-643,664-692`) deliberately uses `GetItemInfo` (comment
  `:607-608`) because `GetItemInfoInstant` doesn't return `equipLoc` reliably; `GetItemInfo` returns
  nil for uncached items so everything falls to `return "Other"` (`:642`). The `ItemStats` refresh
  callback that exists precisely to re-render on `GET_ITEM_INFO_RECEIVED` is **filtered to the two
  stat modes** (`BagUI/Core.lua:1348-1356`). `category` mode is unaffected (synchronous
  `GetItemInfoInstant`). Fix: drop the mode filter at `:1352` — re-rendering on late item data is
  correct for every mode. **Visible: items visibly jump out of "Other" a fraction of a second
  after opening the bag.**
- **B14 (visible half)** — an item belonging to two equipment sets renders twice.
  `CategoryView.lua:489-498` sets `claimed[item] = true` once but then inserts the item into EVERY
  matching set's list, so one bag slot yields N buttons with the same `bagID`/`slotID` — and
  `ItemButton:GetButton(bagID, slotID)` (`:532-540`) returns only the first, so a targeted
  single-slot update refreshes one copy and leaves the other stale. **Decision required: render a
  shared item only in its first set (matching how `claimed` is used for Recent), or keep the
  duplication and document it.**

### W7 — documentation truth-up (`.claude/CLAUDE.md`, registry)

1. **The `local module = self` rule is wrong and expensive.** CLAUDE.md calls it CRITICAL and claims
   "24 of 25 modules violate" it, prescribing a 25-file sweep. In Lua `self` is an ordinary
   parameter and a closure over it captures a stable upvalue — `local module = self` produces a
   **byte-identical binding**. It would matter only if the module table were reassigned after
   `OnEnable`, and `IM.modules[name]` never is (`Core.lua:96-107`, called once per file at load).
   Recon also found the pattern IS used in `AutoSell.lua:31`, `MailHelper.lua:149`,
   `FlightTracking.lua:25`, `VendorTracking.lua:26`, `WarbandBankTracking.lua:22`,
   `UnclaimedGoldTracking.lua:53`, `BagData.lua:474`, `RecentItems.lua:91`, `BagIntegration.lua:36`
   and others — so the "1 of 25" claim is false in both directions. **Downgrade to a style
   preference and cancel the sweep.** The genuine lifecycle hazard is `pairs(IM.modules)` (W2-1).
2. **The palette is wrong.** CLAUDE.md documents amber `#FFB000` as the primary accent; `UI/Core.lua:41`
   has been cyan `#3FA9F5` since the restyle, `:52` reserves amber `#F0B23A` for money only, and
   `:56`'s `warning` is commented "deliberately NOT the accent".
3. **The interface version is wrong** — CLAUDE.md says `110002`, the `.toc` says `120100`. Note
   `publish.sh` never rewrites `## Interface:`, so the 1.4.0 bump is a manual edit.
4. **`.analysis/` does not exist.** CLAUDE.md cites eight report files (`bugs.md`,
   `performance.md`, `consistency.md`, `redundancy.md`, `cleanup.md`, `documentation.md`, `ux.md`,
   `report.md`) and "Issue #1"/"Bug #1" references throughout. **Every one is a dangling pointer.**
   Either restore them or strip the references; per the decision-records rule, current state plus a
   `git log --grep` anchor is the correct shape.
5. **The pooling claim is true in one of three paths** (W4-5).
6. **BankItemTracking's documented root cause is stale** — CLAUDE.md blames a nil `_lastBankType`;
   that variable no longer exists, the module was rewritten, and the real defect is
   frame-open-time type detection (W2-18).
7. **`Database.lua:103` still comments that warband gold is "manual entry - no API available"** —
   disproved by the code itself (`C_Bank.FetchDepositedMoney`).
8. **The documented module list is badly out of date** — absent from CLAUDE.md entirely:
   `CustomCategories`, `ItemStats`, `RecentItems`, `BagData`, the whole `UI/BagUI/*` subsystem,
   `GuildBankTracking`, `FlightTracking`, `TransmogTracking`, `BarberTracking`, `BMAHTracking`,
   `UnclaimedGoldTracking`. The documented filter-priority list also asserts a quality-protection
   step that does not exist in code (W1-1) — fix the code, then the doc.
9. **Dead/orphaned code to remove once proven dead**: `UI/Panels/Ledger.lua` (146 lines) and
   `UI/Panels/NetWorth.lua` (169 lines), absent from the `.toc`, unreachable, still carrying
   amber-era styling, and both absorbed refactor commits (`927cdee`, `b7fc08c`) that changed
   nothing a user can see. Also `IM:GetAccountGold`/`IM:GetAccountNetWorth`
   (`Database.lua:856-873`, zero callers, and `GetAccountNetWorth` reimplements
   `GetAccountBreakdown` while independently inheriting W3-2 and W3-5); `IM.OnDatabaseReady`
   (invoked `Database.lua:269-271`, defined nowhere); `defaults.char` (`:164-167`, empty, never
   read); the two overlapping welcome messages (`Core.lua:16,110-118,353-363`).
   **`UI/Panels/History.lua` is a CANDIDATE only** — recon did not read `UI/Panels/Dashboard.lua`
   past line 40 or `UI/Panels/Currency.lua`, and 4 panels are reachable ONLY by dynamic string
   lookup `UI.Panels[panel.module]` (`UI/Panels/Selling.lua:53`). **Prove death in both directions
   before deleting anything** (no-duct-tape rule: "absence from the view you're looking at is a
   theory, not proof").

---

## Verification — there is no test harness, so this is the plan's weakest joint

**Every phase must carry an in-game smoke checklist as its exit criteria.** A phase whose exit
criteria is "the file loads" is not done. The available instruments:

- `/reload`, `/im debug` (`Core.lua:498-501`), and the 500-line debug ring buffer dumpable via
  `IM:GetDebugLogString()` (`Core.lua:183`).
- **Docker Lua 5.1 for anything that is pure table manipulation** — verified working:
  `docker run --rm -v /tmp:/w -w /w akorn/lua:5.1-alpine lua script.lua`. This covers the v3
  migration (mandatory: run `IM:InitializeDatabase()` twice against a copy of the real
  SavedVariables, deep-compare, second run must be a no-op), and can cover `Filters` decision
  logic and the new claim queue if they are extracted as pure functions taking explicit inputs.
  **Prefer designing the new claim queue and the migration as pure functions precisely so they can
  be tested at all.** Do NOT use npm `fengari`/`lua-in-js` — Lua 5.3 semantics.
- `green-check` buys nothing here; do not plan a phase around it.

Smoke checks the plan must include somewhere, at minimum: a legendary with a vendor price survives
a merchant visit at every `maxQuality` setting · a fresh-profile install sells nothing without
consent · mail to a full mailbox and to a typo'd recipient both report a cause · a multi-alt Send
All either sends every mail or reports which failed · loot 12g and confirm exactly ONE ledger entry
· a warband deposit produces exactly one transfer entry and no `other_expense` · log in without
visiting a bank and confirm warband gold is unchanged and no phantom transfer appears · a
guildmate's deposit produces no entry on your ledger · ledger search "repair" and confirm the
summary totals match the visible rows · Alt+Click and Ctrl+Alt+Click still lock/junk inside the
CUSTOM bag (the W-BagUI-14 invariant) · close the bag with X, loot ten items, confirm no rebuild
occurs.

---

## Instruction to the planner

Write **one OPORD-tier `plan.md`** at
`.claude/plans/active/audit-remediation/plan.md`, `status: pending_approval`.

- Every numbered finding above must appear in exactly one phase. **Nothing may be dropped, and
  nothing may be left implicit.** If you believe an item is not worth fixing, say so explicitly
  with all four no-duct-tape deferral fields (WHAT · WHY with a concrete cost · COST to fix later ·
  TRIGGER event) — "low value" is not a WHY.
- **Cluster by root cause, not by file.** Where several findings share an ancestor (W2-2..6 → the
  amount-keyed claim queue; W3-2/3/5 → the `CalculateInventoryValue` split; W3-8/9 → retiring
  SellHistory's writers; W3-11/13 → `GetCharacterKey` + one migration; W4-1/2 → filter-once;
  B3 → one bag iterator), the plan must state the single ancestor fix and list the symptoms that
  die with it. One fix at the ancestor, not one patch per symptom.
- Draw phase boundaries where the blast-radius table says they are cheap, and respect the
  sequencing evidence — **only the `_claimedThisCycle` item is gated on the module-order fix.**
  Do not serialize W2 behind itself; the refutations are load-bearing.
- The fence is a hard constraint in every phase that touches `UI/Core.lua`: **ADD ONLY.** No
  changes to the 12 frozen signatures, to `CreateScrollFrame`'s geometry, or to any existing
  `UI.layout` value. New keys and new functions are fine.
- The five approval-gated BagUI items and B1 are **steps that stop and ask**, not steps that
  implement. Model them as explicit user-decision gates.
- Every phase gets an in-game smoke checklist as exit criteria. The migration phase additionally
  gets the Docker double-run proof.
- Include a risk table with initial and residual tiers. If any HIGH/EX-HIGH residual stands, emit
  an unsigned override block — the conductor will take it to the user; **do not sign it yourself
  and do not soften a tier to avoid one.**
- The release phase covers: the manual `## Interface:` edit, `publish.sh`'s hard gates (clean tree,
  no untracked files, branch `main`, monotonic version), one 1.4.0 publish, and the advisory `cp`
  line for SavedVariables.
- Out of scope, state explicitly: the two `pending_approval` plans in `active/`; any redesign of the
  bag UI; any migration backup mechanism.
- Per the decision-records rule, the plan carries current state plus a one-clause anchor. Rationale
  and evidence belong in the commit messages, not in ADR sections inside `plan.md`.
