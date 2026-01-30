# Todos: InventoryManager

## Current Goal
General maintenance and feature work

## Active Phases

### BagUI Icon Resizer Polish
- [x] Add debug dump function to ItemButton.lua
- [x] Trigger dump on first SetItem call
- [x] Clean up debug code (put behind `/im debug` flag)
- [x] Fix category header positioning - headers now anchor to first item (CategoryView.lua)
- [ ] Verify headers follow icon size changes (waiting for user test)
- [ ] Identify actual border element from debug output (if still needed)

### Item Upgrade Taint Fix
- [x] Identify cause (SetOverrideBindingClick active during secure interactions)
- [x] Add secure interaction type tracking
- [x] Clear override bindings on PLAYER_INTERACTION_MANAGER_FRAME_SHOW
- [x] Restore override bindings on PLAYER_INTERACTION_MANAGER_FRAME_HIDE
- [x] Add secure interaction checks to BagIntegration.lua (RefreshAllOverlays, hooks)
- [x] Add secure interaction checks to ItemLock.lua (all hooks, _HookButton, _HookContainerFrames, _HookCombinedBags)
- [x] Add secure interaction checks to JunkList.lua (OnClick, ContainerFrame_Update hooks)
- [x] Add comprehensive debug logging for all hook entry points
- [x] Disable toggle button entirely during secure interactions (OnClick=nil, Hide)
- [x] Add secure interaction checks to ToggleAllBags/OpenAllBags hooks (normal + priority)
- [x] Convert StaticPopup_Show replacement to hooksecurefunc (ROOT CAUSE!)
- [x] Convert BuyMerchantItem replacements to hooksecurefunc (SellHistory, VendorTracking)
- [x] Convert BuybackItem replacement to hooksecurefunc (VendorTracking)
- [x] Convert RepairAllItems replacement to hooksecurefunc (RepairTracking)
- [x] Convert SendMail/TakeInboxMoney/TakeInboxItem replacements to hooksecurefunc (MailTracking)
- [x] Fix ItemButton.lua ToggleItemLock method call (method didn't exist)
- [x] Item Upgrade vendor taint - FIXED

### Post-hooksecurefunc Regression Fixes
- [x] Alt+click lock not working - back to HookScript("OnClick"), removed overlay mouse capture
- [x] Ctrl+Alt+click junk toggle - fixed missing JunkList:UpdateOverlay method call
- [x] Debug log spam loop - added verbose parameter to ShouldAutoSell/GetAutoSellItems
- [x] AutoSell module scope bug - added `local module = self` to SellJunk()
- [x] Click-to-sell in bags not working - overlay was eating clicks, removed mouse capture
- [x] Merchant reject infinite loop - added _rejectedItems tracking for unsellable items
- [x] Alt+click double-firing - REMOVED duplicate handler from ItemButton.lua (ItemLock.lua already handles it via ContainerFrameItemButtonMixin hook)
- [x] Ctrl+Alt+click double-firing - REMOVED duplicate handler from ItemButton.lua (JunkList.lua already handles it)
- [x] Infinite loop fix v2 - FinishSelling now only reschedules for valid items, not pending items
- [ ] Test vendor buy tracking after hooksecurefunc conversion
- [ ] Test repair tracking after hooksecurefunc conversion
- [ ] Test mail tracking after hooksecurefunc conversion

### Completed This Session
- [x] Fix WSL symlink to WoW addon folder
- [x] Update publish.sh to auto-update Core.lua version
- [x] Remove "AutoSell module enabled" log message
- [x] Item Upgrade taint fix - clear override bindings during secure interactions

## Future (Not Yet Planned)
Things mentioned but not fully discussed - will plan when we get there:
- (none)

## Completed
- [2026-01-29] Bag UI search bar fix - Added padding, border, uses UI.layout constants
- [2026-01-29] Currency search placeholder fix - Hide placeholder on text input
- [2026-01-29] Auto-Loot Mail Feature - Added Loot All button, auto-loot on open setting, COD skip setting
- [2026-01-27] Debug cleanup - Removed rogue print() calls from GuildBankTracking.lua
