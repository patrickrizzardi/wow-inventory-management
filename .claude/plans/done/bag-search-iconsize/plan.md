# Plan: Bag Search Bar + Icon Size Slider

Created: 2026-01-29
Status: completed

## Requirements (Restated)

1. **Search Bar in Bag UI**: Add a search input below the header that filters items by:
   - Item name (partial match)
   - Item level (ilvl)
   - Category/subcategory name

2. **Icon Size Slider**: Add a slider in Bag UI settings to adjust icon size:
   - Default: 20px (current)
   - Range: 16-32px (reasonable min/max)
   - Live preview with debounce (like existing width slider)

3. **Dynamic Bag Resizing**: Bag width should auto-adjust when icon size changes to fit items correctly (width is derived from `itemSize * itemsPerRow + padding`).

## Architecture Analysis

### Current State

- **Item size calculation**: `UI/BagUI/MasonryLayout.lua:22-26` - `GetItemSize()` returns `UI.layout.iconSize + 17`
- **ItemButton creation**: `UI/BagUI/ItemButton.lua:80` - hardcoded `UI.layout.iconSize + 17`
- **BagUI width calc**: `UI/BagUI/Core.lua:36` - hardcoded `itemSize = 37`
- **BagUI settings**: Stored in `IM.db.global.bagUI` - has `columns`, `itemsPerRow`, `height`, `viewMode`, `showItemSets`
- **Settings panel**: `UI/Panels/BagUI.lua` - already has debounced refresh pattern via `ScheduleLayoutRefresh()`

### How Sizing Works Currently

1. `BagUI:Create()` calculates initial width from `itemSize=37` (hardcoded)
2. `BagUI:ResizeForSettings()` recalculates width when columns/itemsPerRow change
3. `MasonryLayout:GetItemSize()` reads `UI.layout.iconSize` (currently always 20)
4. `ItemButton:CreateButton()` sizes buttons from `UI.layout.iconSize`

### Design Decision: Where to Store Icon Size

**Option A**: Store in `IM.db.global.bagUI.iconSize` (persisted per-account)
**Option B**: Modify `UI.layout.iconSize` directly (affects ALL UI, not just bags)

**Chosen**: Option A - Store in bagUI settings. We'll use `IM.db.global.bagUI.iconSize` and have `MasonryLayout:GetItemSize()` read from there when available.

## Risks & Blockers

1. **ItemButton pool already created**: Buttons are pre-created at login with current size. Changing icon size requires either:
   - Recreate buttons (expensive, potential taint issues)
   - Resize existing buttons dynamically (preferred)

2. **Virtual bag frames**: `ItemButton.lua` creates virtual bag frames that may cache size. Need to verify resize propagates.

3. **Search filter performance**: Filtering 200+ items on every keystroke could lag. Need debounce.

4. **Category/subcategory search**: Need to match against `CategoryView:GetItemCategory()` / `GetItemSubcategory()` output.

## Phases

### Phase 1: Icon Size Setting + Dynamic Resize

**Objective**: Add icon size slider that dynamically resizes bag UI and items.

**Files**:
- `Database.lua` - Add `iconSize` default to bagUI settings
- `UI/Panels/BagUI.lua` - Add icon size slider with debounce
- `UI/BagUI/MasonryLayout.lua` - Update `GetItemSize()` to read from settings
- `UI/BagUI/ItemButton.lua` - Update `CreateButton()` to use dynamic size + add resize method
- `UI/BagUI/Core.lua` - Update width calculation to use dynamic icon size

**Steps**:
1. Add `iconSize = 20` default to `Database.lua` under bagUI
2. In `MasonryLayout:GetItemSize()`, read from `IM.db.global.bagUI.iconSize` if set
3. Add `ItemButton:ResizeButton(button, newSize)` method to resize existing buttons
4. Add `ItemButton:ResizeAll()` to resize all pooled buttons
5. Update `BagUI:Create()` to use dynamic item size
6. Update `BagUI:ResizeForSettings()` to call `ItemButton:ResizeAll()` and recalc width
7. Add icon size slider to `UI/Panels/BagUI.lua` with same debounce pattern as other sliders

**Verification**: Change icon size slider, verify bag resizes and items display correctly.

---

### Phase 2: Search Bar UI

**Objective**: Add search input to bag header with visual feedback.

**Files**:
- `UI/BagUI/Core.lua` - Add search bar below header

**Steps**:
1. Create search bar frame below header (above content container)
2. Add search icon + editbox + clear button
3. Store reference to editbox in `_bagFrame.searchBox`
4. Adjust `contentContainer` anchor to account for search bar height
5. Connect `OnTextChanged` to `BagUI:SetSearchFilter(text)`
6. Add placeholder text "Search items..."

**Verification**: Search bar appears, typing works, clear button clears.

---

### Phase 3: Search Filter Logic

**Objective**: Implement filtering that hides non-matching items.

**Files**:
- `UI/BagUI/CategoryView.lua` - Add filter to `GatherItems()` or `Refresh()`
- `UI/BagUI/Core.lua` - Add `SetSearchFilter()` and store filter state

**Steps**:
1. Add `_searchFilter = ""` state variable in `BagUI/Core.lua`
2. Add `BagUI:SetSearchFilter(text)` that stores filter + calls `Refresh()`
3. Add `BagUI:GetSearchFilter()` accessor
4. In `CategoryView:GatherItems()`, skip items that don't match filter
5. Match logic:
   - Empty filter = show all
   - ilvl filter with operators: `>400`, `>=400`, `<400`, `<=400`, `=400`, or just `400` (exact match)
   - Text filter = match item name OR category/subcategory name (case-insensitive)
6. Add debounce (0.15s) to avoid refresh on every keystroke

**Verification**: Type in search, verify items filter correctly by name/ilvl/category.

---

### Phase 4: Polish & Edge Cases

**Objective**: Handle edge cases and improve UX.

**Files**:
- `UI/BagUI/Core.lua` - Clear search on hide
- `UI/BagUI/CategoryView.lua` - Handle empty categories gracefully

**Steps**:
1. Clear search filter when bag closes (`BagUI:Hide()`)
2. Hide empty categories (categories with 0 matching items after filter)
3. Show "No items found" message when filter matches nothing
4. Escape key clears search if focused, otherwise closes bag
5. Add search bar focus on Ctrl+F keybind (optional)

**Verification**: Full workflow - search, filter, clear, close, reopen - all smooth.

---

## Summary

| Phase | Files Modified | Key Changes |
|-------|---------------|-------------|
| 1 | Database.lua, UI/Panels/BagUI.lua, UI/BagUI/MasonryLayout.lua, UI/BagUI/ItemButton.lua, UI/BagUI/Core.lua | Icon size setting + dynamic resize |
| 2 | UI/BagUI/Core.lua | Search bar UI |
| 3 | UI/BagUI/CategoryView.lua, UI/BagUI/Core.lua | Filter logic |
| 4 | UI/BagUI/Core.lua, UI/BagUI/CategoryView.lua | Polish |

## Decisions

1. **ilvl search syntax**: Support comparison operators:
   - `400` or `=400` → exact match (ilvl == 400)
   - `>400` → ilvl > 400
   - `>=400` → ilvl >= 400
   - `<400` → ilvl < 400
   - `<=400` → ilvl <= 400

2. **Search scope**: Includes reagent bag items (same as current behavior)

3. **Icon size range**: 16-32px
