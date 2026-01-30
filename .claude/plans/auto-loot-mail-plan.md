# Plan: Auto-Loot Mail Feature

Created: 2026-01-29
Status: pending_approval

## Requirements (Restated)

**Goal**: Add auto-loot functionality for mail attachments (items + gold)

**User Decision**: When bags are full → Stop and notify (show message about remaining items)

**Behavior Options**:
1. Button trigger in MailPopup (manual control)
2. Auto-loot on mailbox open (optional setting)
3. **Chosen approach**: Both - make it configurable

**Integration Point**: Mail Helper settings panel + MailPopup UI

## Research Findings

### WoW Mail API
- `AutoLootMailItem(index)` - Loots all attachments (gold + items) from a single mail
- `GetInboxNumItems()` - Returns total mail count
- `GetInboxHeaderInfo(index)` - Returns mail header info including attachment count
- `GetInboxItem(index, attachmentIndex)` - Returns attachment info
- `GetInboxItemLink(index, attachmentIndex)` - Returns item link
- `TakeInboxMoney(index)` - Takes gold only
- `TakeInboxItem(index, attachmentIndex)` - Takes single item
- `MAIL_SUCCESS` event - Fires after successful loot
- `MAIL_INBOX_UPDATE` event - Fires when inbox changes

### Throttling Requirement
- Mail API calls must be throttled (0.5s minimum between calls) to avoid "Internal Mail Database Error"
- Existing MailTracking.lua already has `MAIL_THROTTLE = 0.5` constant

### Bag Space Detection
- `C_Container.GetContainerNumFreeSlots(bagID)` - Returns free slot count per bag
- Need to sum across all bags to get total free space

### Existing Patterns to Reuse
1. **MailTracking.lua hooks** - Already hooks `TakeInboxMoney` and `TakeInboxItem` for logging
2. **MailHelper.lua** - Has `_atMailbox` state tracking, `MAIL_SHOW`/`MAIL_CLOSED` events
3. **MailPopup.lua** - Has button creation patterns, debounced bag updates
4. **UI:CreateButton()** - Existing button factory
5. **IM:Print()` / `IM:PrintError()** - User messaging

## Risks & Blockers

| Risk | Mitigation |
|------|------------|
| Throttling issues causing "Internal Mail Database Error" | Use 0.5s delay between AutoLootMailItem calls |
| Bags filling mid-loot | Check free slots before each mail, stop with notification |
| COD mail being auto-looted (costs gold) | Skip COD mail (check via `GetInboxHeaderInfo`) |
| AH/System mail mixed with regular | Loot all - no filtering needed (user can choose to use feature or not) |
| Existing MailTracking hooks conflicting | AutoLootMailItem internally calls the same APIs - hooks should still fire |

## Design Decisions

### Setting Location
Add to `IM.db.global.mailHelper`:
```lua
mailHelper = {
    enabled = true,           -- existing
    autoFillOnOpen = false,   -- existing (unused, repurpose?)
    autoLootOnOpen = false,   -- NEW: auto-start looting when mailbox opens
    skipCOD = true,           -- NEW: skip COD mail (avoid unexpected costs)
    alts = {},                -- existing
    rules = {},               -- existing
}
```

### UI Changes
1. **MailPopup.lua**: Add "Loot All" button next to "Send All"
2. **MailHelper panel**: Add two checkboxes:
   - "Auto-loot mail on open" (default: OFF)
   - "Skip COD mail" (default: ON)

### Module Placement
Add auto-loot logic to `MailHelper.lua` (not MailTracking) because:
- MailHelper already manages the MailPopup UI
- MailHelper already tracks `_atMailbox` state
- Keeps mail "sending" and "receiving" in same module

## Phases

### Phase 1: Database & Settings
**Objective**: Add settings infrastructure
**Files**:
- `Database.lua` - Add new mailHelper defaults
**Steps**:
1. Add `autoLootOnOpen = false` to mailHelper defaults
2. Add `skipCOD = true` to mailHelper defaults
**Verification**: `/reload` and verify defaults via `/im debug`

### Phase 2: Core Auto-Loot Logic
**Objective**: Implement looting engine with throttling and bag checks
**Files**:
- `Modules/MailHelper.lua` - Add auto-loot methods
**Steps**:
1. Add `_lootQueue` state and `_isLooting` flag
2. Add `MailHelper:GetFreeBagSlots()` helper
3. Add `MailHelper:StartAutoLoot()` method:
   - Scan inbox for lootable mail
   - Skip COD if setting enabled
   - Build loot queue
4. Add `MailHelper:ProcessLootQueue()` with 0.5s throttle:
   - Check bag space before each mail
   - Call `AutoLootMailItem(index)`
   - Handle `MAIL_INBOX_UPDATE` to continue queue
   - Stop and notify if bags full
5. Add `MailHelper:StopAutoLoot()` method
6. Add `MailHelper:IsLooting()` method
**Verification**: Manual testing at mailbox with debug enabled

### Phase 3: MailPopup UI Button
**Objective**: Add "Loot All" button to popup
**Files**:
- `UI/MailPopup.lua` - Add button and status display
**Steps**:
1. Add "Loot All" button in bottom bar (left of Send All)
2. Button text changes to "Stop" when looting
3. Add looting status text (e.g., "Looting 3/10...")
4. Disable button when no mail to loot
**Verification**: Visual inspection, button functionality

### Phase 4: Settings Panel UI
**Objective**: Add configuration options
**Files**:
- `UI/Panels/MailHelper.lua` - Add checkboxes
**Steps**:
1. Add "Auto-Loot Settings" section after config card
2. Add checkbox: "Auto-loot mail when mailbox opens"
3. Add checkbox: "Skip COD mail when looting"
**Verification**: Settings persist after `/reload`

### Phase 5: Auto-Loot on Open (Optional)
**Objective**: Implement auto-start behavior
**Files**:
- `Modules/MailHelper.lua` - Modify `OnMailShow()`
**Steps**:
1. In `OnMailShow()`, check if `autoLootOnOpen` enabled
2. If enabled, call `StartAutoLoot()` after short delay (0.5s)
3. Show popup with progress
**Verification**: Toggle setting, open/close mailbox, verify behavior

## Implementation Notes

### Bag Space Calculation
```lua
function MailHelper:GetFreeBagSlots()
    local free = 0
    for _, bagID in ipairs(IM:GetBagIDsToScan()) do
        local freeSlots = C_Container.GetContainerNumFreeSlots(bagID)
        free = free + (freeSlots or 0)
    end
    return free
end
```

### COD Detection
```lua
local _, _, _, _, money, CODAmount = GetInboxHeaderInfo(index)
local isCOD = (CODAmount or 0) > 0
```

### Throttled Looting Pattern
```lua
local LOOT_DELAY = 0.5

function MailHelper:ProcessLootQueue()
    if #_lootQueue == 0 then
        self:OnLootingComplete()
        return
    end

    local freeSlots = self:GetFreeBagSlots()
    if freeSlots == 0 then
        self:StopAutoLoot("Bags full! " .. #_lootQueue .. " mail remaining.")
        return
    end

    local index = table.remove(_lootQueue, 1)
    AutoLootMailItem(index)

    -- Continue after delay
    C_Timer.After(LOOT_DELAY, function()
        if _isLooting then
            self:ProcessLootQueue()
        end
    end)
end
```

## Files Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `Database.lua` | Modify | Add 2 new mailHelper settings |
| `Modules/MailHelper.lua` | Modify | Add auto-loot methods (~80 lines) |
| `UI/MailPopup.lua` | Modify | Add Loot All button + status |
| `UI/Panels/MailHelper.lua` | Modify | Add 2 checkboxes |

**Estimated LOC**: ~120-150 new lines

## Testing Checklist

- [ ] Loot single mail with items
- [ ] Loot single mail with gold only
- [ ] Loot mail with items + gold
- [ ] Loot multiple mails in sequence
- [ ] Verify 0.5s throttle prevents errors
- [ ] Fill bags, verify stop + notification
- [ ] Test COD skip setting
- [ ] Test auto-loot on open setting
- [ ] Verify MailTracking still logs transactions
- [ ] Verify Stop button works mid-loot
- [ ] Verify works after `/reload`
