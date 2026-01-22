# InventoryManager Review (Pre-BagUI)

## High-Impact Bugs / Correctness

1. **Unclaimed gold double-logging**
   - `IM:ClaimGoldChange()` exists but is never called.
   - Modules that log gold changes outside of tracked contexts will also be logged as `other_income/other_expense`.
   - Affects: quest rewards, flight costs, transmog, barber, etc.
   - Evidence:
     - `Modules/Tracking/UnclaimedGoldTracking.lua` (uses `ClaimGoldChange`, but no callers)
     - `Modules/Tracking/QuestTracking.lua` (logs quest gold without claim)
     - `Modules/Tracking/FlightTracking.lua` (logs flight cost without claim)
     - `Modules/Tracking/TransmogTracking.lua` (logs costs without claim)
   - Fix direction:
     - Call `IM:ClaimGoldChange()` in modules that log gold.
     - Or expand `IsInTrackedContext()` to cover all modules that log gold deltas.

2. **Reagent bag counted twice in NetWorth**
   - `IM:GetBagIDsToScan()` already includes reagent bag.
   - NetWorth scans reagent bag again manually.
   - Results in inflated inventory value and extra scan cost.
   - Evidence:
     - `Modules/NetWorth.lua` scans `IM:GetBagIDsToScan()` then explicitly scans bag `5`.
   - Fix direction:
     - Remove the explicit reagent bag scan in NetWorth.

## Performance / CPU / Memory Hotspots

1. **TooltipInfo scans all bags on every hover**
   - `TooltipInfo:FindItemInBags()` loops all bags and slots per tooltip.
   - This is high-frequency and expensive when hovering items.
   - Evidence: `Modules/TooltipInfo.lua`.
   - Fix direction:
     - Use tooltip owner to derive bag/slot when possible.
     - Cache recent bag lookup results (itemID -> bag/slot).

2. **Redundant bag scans across modules**
   - `NetWorth` and `InventorySnapshot` both scan on `BAG_UPDATE_DELAYED`.
   - Each has its own debounce but still duplicates work.
   - Evidence: `Modules/NetWorth.lua`, `Modules/InventorySnapshot.lua`.
   - Fix direction:
     - Introduce shared bag snapshot/cache service.
     - Fan out to NetWorth + InventorySnapshot from a single scan.

3. **JunkList overlay refresh is aggressive**
   - Full refresh on `BAG_UPDATE_DELAYED` and `ContainerFrame_Update`.
   - Duplicates ItemLock refreshes (similar bag scans).
   - Evidence: `Modules/JunkList.lua`.
   - Fix direction:
     - Debounce refreshes, or route through a shared overlay refresh manager.

4. **SavedVariables growth risk**
   - `InventorySnapshot` stores full snapshots per character with no pruning.
   - Can grow large on alt-heavy accounts.
   - Evidence: `Modules/InventorySnapshot.lua`.
   - Fix direction:
     - Add max entries, or store only latest snapshot per character.
     - Optionally compress by itemID/quantity.

## UX / User-Facing Issues

1. **Always-on debug `print()` spam**
   - `GuildBankTracking.lua` prints debug to chat even when debug is disabled.
   - This is noisy and user-visible.
   - Evidence: `Modules/Tracking/GuildBankTracking.lua`.
   - Fix direction:
     - Replace `print()` with `IM:Debug()` or guard behind `db.global.debug`.

2. **Global function overrides can conflict**
   - Several modules replace global functions (mail, vendor, repair, auction).
   - Risk of addon conflicts or double-wrapping.
   - Evidence:
     - `Modules/Tracking/MailTracking.lua`
     - `Modules/Tracking/VendorTracking.lua`
     - `Modules/Tracking/RepairTracking.lua`
     - `Modules/Tracking/AuctionTracking.lua`
   - Fix direction:
     - Centralize hook/override strategy (store originals once, guard re-hook).
     - Add safety checks to avoid multiple wraps.

## Recommended Pre-BagUI Cleanup (High ROI)

1. Add `IM:ClaimGoldChange()` to gold-logging modules (quest, flight, transmog, barber, etc.).
2. Remove duplicate reagent scan in NetWorth.
3. Debounce and centralize bag overlay refreshes (ItemLock + JunkList).
4. Avoid full bag scans on tooltip hover; cache bag/slot lookup.
5. Replace always-on debug `print()`s in GuildBankTracking.
6. Introduce shared bag snapshot cache for NetWorth + InventorySnapshot.

