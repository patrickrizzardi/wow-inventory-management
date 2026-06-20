# Plan: BagUI Dynamic Width/Height Sizing

Created: 2026-01-30
Status: pending_approval

## Requirements (restated)

**User Goal**: BagUI frame should dynamically grow/shrink in WIDTH and adjust scroll HEIGHT based on icon size changes.

**Current Problem**:
- Icons on both left and right sides are being cut off when icon size changes
- The frame width calculation doesn't match actual rendered content
- Scroll content height/width is calculated separately from actual rendered bounds

**Constraints**:
- Width: Frame width should auto-expand to fit all icons (clamped 480-1200)
- Height: Frame height stays FIXED, but scroll content must properly report its height so scrollbar works
- All math components must be accounted for: icon size, icon border/padding (17px), gaps between icons (paddingSmall), category padding, column gaps, scrollbar width

**Success Criteria**:
1. All icons visible at any icon size (no left/right cutoff)
2. Scrollbar properly reflects content height
3. Width updates immediately when icon size changes in settings

## Root Cause Analysis

The problem is **scattered width calculations that don't match reality**:

### Current Width Calculation Chain (3 different places, likely inconsistent):

1. **BagUI/Core.lua:Create()** (lines 85-101) - Initial frame creation:
   ```lua
   local itemSize = iconSize + 17  -- icon + border
   local itemRowWidth = (itemSize * itemsPerRow) + (paddingSmall * (itemsPerRow - 1))
   local columnContentWidth = paddingSmall + itemRowWidth
   local contentWidth = categoryPadding + (columnContentWidth * columns) + (columnGap * (columns - 1)) + categoryPadding
   local totalWidth = contentWidth + 60  -- scrollbar + margins
   ```

2. **BagUI/Core.lua:ResizeForSettings()** (lines 548-574) - Same calculation, duplicated

3. **MasonryLayout.lua:Calculate()** (line 83) - DIFFERENT calculation:
   ```lua
   local columnWidth = math.floor((containerWidth - totalPadding - totalGaps) / columns)
   ```
   MasonryLayout receives `containerWidth` and works backwards - it doesn't set width, it reacts to it.

4. **CategoryView.lua:RenderCategory()** (lines 617-682) - Uses positions from MasonryLayout, tracks bounds AFTER the fact

### The Bug:
- Core.lua calculates required width FORWARD (icon → row → column → frame)
- MasonryLayout calculates column width BACKWARD (frame → columns → available width)
- These calculations use different padding/margin constants
- The `+60` magic number in Core.lua (scrollbar + margins) doesn't match actual UI structure

### Specific Issues:
1. `itemRowWidth` calculation uses `paddingSmall` for gaps, but `IM.UI.layout.paddingSmall` = 4
2. The `+17` for border comes from ContainerFrameItemButtonTemplate scaled size, but buttons use `SetScale()` so actual pixel size varies
3. `contentWidth + 60` is a hardcoded fudge factor that doesn't account for actual margins

## Proposed Solution: Single Source of Truth

### Approach: **Calculate Width From Actual Constants**

Create ONE canonical width calculator that both Create() and ResizeForSettings() use:

```lua
function BagUI:CalculateRequiredWidth()
    local settings = self:GetSettings()
    local iconSize = settings.iconSize or 20
    local columns = settings.columns or 2
    local itemsPerRow = settings.itemsPerRow or 6

    -- All constants in ONE place
    local BUTTON_BORDER_PADDING = 17  -- ContainerFrameItemButtonTemplate overhead
    local SCROLL_CONTAINER_MARGIN = 10  -- From CreateScrollFrame fill mode
    local SCROLLBAR_AREA = 18  -- scrollbar width (10) + margin (8)
    local SCROLL_CONTENT_PADDING = 22  -- From content width calc in CreateScrollFrame

    local layout = IM.UI.layout
    local paddingSmall = layout.paddingSmall or 4
    local categoryPadding = layout.cardSpacing or 10
    local columnGap = categoryPadding * 2  -- Consistent with MasonryLayout

    -- Item size (what buttons actually take up)
    local itemSize = iconSize + BUTTON_BORDER_PADDING

    -- Row of items: N items + (N-1) gaps
    local itemRowWidth = (itemSize * itemsPerRow) + (paddingSmall * (itemsPerRow - 1))

    -- Each column: inner padding + items
    local columnContentWidth = paddingSmall + itemRowWidth

    -- All columns + gaps between them + outer padding
    local contentAreaWidth = categoryPadding + (columnContentWidth * columns) + (columnGap * (columns - 1)) + categoryPadding

    -- Frame = content + scroll container margins + scrollbar + scroll content padding
    local frameWidth = contentAreaWidth + (SCROLL_CONTAINER_MARGIN * 2) + SCROLLBAR_AREA + 4

    return math.max(480, math.min(1200, frameWidth))
end
```

### Phase 1: Centralize Width Calculation

**Objective**: Single function for width, used everywhere

**Files**: `UI/BagUI/Core.lua`

**Steps**:
1. Add `BagUI:CalculateRequiredWidth()` function with all constants documented
2. Replace inline calculation in `Create()` with call to new function
3. Replace inline calculation in `ResizeForSettings()` with call to new function
4. Add debug logging to track calculated vs actual dimensions

**Verification**: `/reload` and compare debug output at different icon sizes

### Phase 2: Fix Scroll Content Width Tracking

**Objective**: Scroll content reports actual content bounds, not calculated estimates

**Files**: `UI/BagUI/CategoryView.lua`, `UI/BagUI/Core.lua`

**Steps**:
1. In `CategoryView:Refresh()`, track actual `maxX` from rendered items (already partial - `contentBounds.maxX`)
2. After rendering, call new `BagUI:OnContentRendered(contentBounds)`
3. In Core.lua, check if actual content width exceeds scroll container width
4. If overflow detected, trigger width expansion via `ResizeForSettings()` + re-render

**Verification**: Render at different sizes, check no horizontal overflow

### Phase 3: Fix Height/Scrollbar

**Objective**: Scroll content height properly tracks rendered content

**Files**: `UI/BagUI/CategoryView.lua`

**Steps**:
1. Already tracks `contentBounds.maxY` - verify it includes full item height + padding
2. Set scroll content height from `contentBounds.maxY` (already happening but may be wrong)
3. Verify scrollbar updates correctly after content height change

**Verification**: Fill bags with items, scroll to bottom, verify last row fully visible

### Phase 4: Trigger Resize on Settings Change

**Objective**: Icon size slider immediately triggers full recalculation

**Files**: `UI/Panels/BagUI.lua` (or wherever settings slider lives)

**Steps**:
1. Find icon size slider OnValueChanged handler
2. Ensure it calls `BagUI:ResizeForSettings()` AND `BagUI:Refresh()`
3. Add small debounce if slider causes performance issues

**Verification**: Drag icon size slider, watch frame width update smoothly

## Risks & Blockers

1. **Button Scale vs Pixel Size**: Buttons use `SetScale()` which affects all descendants. The `itemSize = iconSize + 17` assumes 17px is constant, but scaled buttons may report different pixel sizes via `GetWidth()`. May need to track scaled size directly.

2. **Anchor Chains**: Headers anchor to first item button. If button positions change during resize, header anchors should auto-update, but need to verify.

3. **Performance**: Excessive re-renders during slider drag could cause lag. Will add debounce if needed.

4. **Minimum Width**: 480px minimum may still be too narrow for some column/itemsPerRow combos. May need to make minimum dynamic.

## Implementation Order

1. Phase 1 (Centralize width) - Foundation, must be right before others
2. Phase 4 (Settings trigger) - Quick win, ensures resize actually happens
3. Phase 2 (Content width tracking) - Fixes overflow detection
4. Phase 3 (Height) - Final polish

Estimated complexity: Medium. Main risk is getting the constants right. Will need iterative testing at multiple icon sizes.
