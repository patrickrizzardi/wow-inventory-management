# Todos: InventoryManager

## Current Goal
General maintenance and feature work

## Active Phases

### Icon Border Resize Bug
- [x] Add debug dump function to ItemButton.lua
- [x] Trigger dump on first SetItem call
- [x] Clean up debug code (put behind `/im debug` flag)
- [ ] Identify actual border element from debug output (waiting for user test)
- [ ] Apply correct resize method to border element

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
- [ ] User testing to confirm fix works
- [ ] If still failing, confirm InventoryManager is the cause (disable addon test)

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
