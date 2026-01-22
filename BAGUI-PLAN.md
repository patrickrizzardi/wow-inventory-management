# InventoryManager Bag UI - Implementation Plan

## Overview

**Goal**: Build a full bag replacement UI integrated into InventoryManager with deep feature integration (locks, junk borders, overlays) and a custom category system that overrides Blizzard's default categories.

**Key Requirements**:
1. Full bag replacement (hooks `OpenAllBags`, `ToggleBag`, etc.)
2. Toggle in settings to switch between our UI and Blizzard bags (default: ours)
3. All existing IM overlays work seamlessly (lock icons, junk borders, sell indicators)
4. IM-defined categories based on classID/subClassID mapping, custom categories override
5. Alt+Right-click context menu for quick category assignment (Alt = IM actions)
6. Settings panel for bulk category management (works even when using Blizzard bags)
7. Combat lockdown protection - gate bag operations on `not InCombatLockdown()`

---

## Architecture

### File Structure

```
InventoryManager/
├── Modules/
│   ├── CustomCategories.lua    -- Category data management (SavedVariables)
│   ├── BagData.lua             -- Bag scanning, caching, diffing, events
│   └── BagHooks.lua            -- One-time bag function wrapping, dispatcher
├── UI/
│   ├── BagUI/
│   │   ├── Core.lua            -- Main bag frame, visibility, layout
│   │   ├── Container.lua       -- Bag container frames, layout orchestration
│   │   ├── ItemSlot.lua        -- Individual item slot (click handling, overlays)
│   │   ├── CategorySection.lua -- Collapsible category headers + item grids
│   │   ├── ContextMenu.lua     -- Configurable modifier + right-click menu
│   │   └── Search.lua          -- Search/filter bar (UI-local cache, no TTL)
│   └── Panels/
│       └── Categories.lua      -- Settings panel for category management
```

### Module Responsibilities

#### `Modules/CustomCategories.lua`
- CRUD operations for custom categories
- Item-to-category assignments (stored by itemID)
- Category ordering/priority
- SavedVariables schema:
```lua
IM.db.global.customCategories = {
    categories = {
        [1] = { id = 1, name = "Raid Consumables", order = 1 },
        [2] = { id = 2, name = "Transmog Farm", order = 2 },
    },
    itemAssignments = {
        [itemID] = categoryID,  -- e.g., [12345] = 1
    },
    nextCategoryID = 3,  -- Auto-increment
}
```

#### `Modules/BagHooks.lua`
- **One-time wrapper** - Stores original bag functions ONCE on first load
- **Early load order** - Listed early in .toc file (before other UI modules)
- **No rewrap on /reload** - `_initialized` flag prevents double-wrapping
- Prevents "last writer wins" conflicts with other addons
- Provides central dispatcher that checks IM settings
- Pattern:
```lua
local BagHooks = {}
local _originals = {}
local _initialized = false

function BagHooks:Initialize()
    if _initialized then return end
    _initialized = true

    -- Store originals exactly once
    _originals.OpenAllBags = OpenAllBags
    _originals.CloseAllBags = CloseAllBags
    _originals.ToggleAllBags = ToggleAllBags
    -- ... etc

    -- Replace with dispatchers (once, never again)
    OpenAllBags = function(...) self:DispatchOpenAll(...) end
    CloseAllBags = function(...) self:DispatchCloseAll(...) end
    ToggleAllBags = function(...) self:DispatchToggleAll(...) end
end

function BagHooks:DispatchOpenAll(...)
    if InCombatLockdown() then return end
    if IM.db.global.useIMBags then
        BagUI:Show()
    else
        _originals.OpenAllBags(...)
    end
end
```

#### `Modules/BagData.lua`
- **Central data layer** - UI components consume this, never scan bags directly
- **Bag IDs covered** (use Enum.BagIndex for clarity):
  - `0` = Backpack (Enum.BagIndex.Backpack)
  - `1-4` = Bag slots
  - `5` = Reagent Bag (Enum.BagIndex.ReagentBag) - optional toggle in settings
- Caches all item data (itemID, itemLink, name, classID, quality, count, etc.)
- **UI-local cache** - separate from Filters.lua cache, no TTL, keyed by itemID
- **Cache invalidation events** (refresh triggers):
  - `BAG_UPDATE_DELAYED` - bag contents changed (primary)
  - `ITEM_LOCK_CHANGED` - item locked/unlocked by game
  - `ITEM_UNLOCKED` - item unlocked
  - `GET_ITEM_INFO_RECEIVED` - async item info loaded
  - `PLAYER_MONEY` - gold changed (for display)
  - Future: `PLAYERBANKSLOTS_CHANGED` if bank support added
- Listens to BAG_UPDATE_DELAYED but only rescans changed bags (via bag ID argument)
- **Diffing**: Compares previous vs current state, emits granular events:
  - `OnBagItemAdded(bagID, slotID, itemData)`
  - `OnBagItemRemoved(bagID, slotID, itemData)`
  - `OnBagItemChanged(bagID, slotID, oldData, newData)` (count changed, etc.)
  - `OnBagItemMoved(fromBag, fromSlot, toBag, toSlot, itemData)`
- Provides lookup methods:
  - `BagData:GetAllItems()` - returns cached item list
  - `BagData:GetItemAt(bagID, slotID)` - returns cached item data
  - `BagData:SearchByName(query)` - searches cached names (no API calls)
- Item data structure:
```lua
{
    bagID = 0,
    slotID = 1,
    itemID = 12345,
    itemLink = "|cff...|r",
    name = "Healing Potion",
    classID = 0,        -- From GetItemInfoInstant
    subClassID = 1,
    quality = 1,
    count = 20,
    isLocked = false,   -- IM whitelist status
    isJunk = false,     -- IM junk list status
    customCategoryID = nil,  -- From CustomCategories
    displayCategory = "Consumables",  -- Resolved category name
}
```

#### `UI/BagUI/Core.lua`
- Main bag window frame (dark theme matching IM style)
- Hooks into Blizzard bag functions:
  - `OpenAllBags()`, `CloseAllBags()`, `ToggleAllBags()`
  - `OpenBag(bagID)`, `CloseBag(bagID)`, `ToggleBag(bagID)`
  - `OpenBackpack()`, `CloseBackpack()`, `ToggleBackpack()`
- Respects the "use Blizzard bags" toggle setting
- Contains:
  - Title bar with close button
  - Search bar
  - Money display
  - Bag slot buttons (toggle individual bags)
  - Scrollable category container

#### `UI/BagUI/Container.lua`
- **Consumes BagData events** - does NOT scan bags directly
- Orchestrates layout: receives item data, groups by category, positions slots
- Listens to BagData events (OnBagItemAdded, OnBagItemRemoved, etc.)
- Triggers re-layout only when BagData emits changes (not on every event)
- Groups items by resolved `displayCategory` from BagData

#### `UI/BagUI/ItemSlot.lua`
- Individual item slot frame (button with icon)
- Displays:
  - Item icon with count overlay
  - Quality border (color-coded)
  - Lock overlay (from IM.db.global.whitelist)
  - Junk overlay (from IM.db.global.junkList)
  - Sell indicator (when at vendor)
- Click handling (priority order - first match wins):
  1. `Ctrl+Alt+Click`: Toggle junk (IM)
  2. `Alt+Shift+Right-click`: Open category menu (IM, configurable)
  3. `Alt+Click`: Toggle lock (IM)
  4. `Shift+Click`: Chat link (WoW default - preserved)
  5. `Ctrl+Click`: Dressup/try-on (WoW default - preserved)
  6. `Left-click`: Pick up item (WoW default)
  7. `Right-click`: Use item (WoW default)
- **Modifier priority documented in UI** - tooltip on bag settings explains order
- Tooltip on hover (with IM tooltip additions)
- Frame pooling for performance (see lifecycle details below)

#### `UI/BagUI/CategorySection.lua`
- Collapsible section with header + item grid
- Header shows:
  - Category name
  - Item count
  - Collapse/expand arrow
- Items displayed in grid layout within section
- Blizzard categories:
  - Equipment, Consumables, Trade Goods, Quest Items, Miscellaneous, etc.
- Custom categories render FIRST (higher priority)
- Empty sections are hidden

#### `UI/BagUI/ContextMenu.lua`
- **Configurable modifier binding** (setting in General panel):
  - `Alt+Shift+Right-click` (default, safest - avoids all conflicts)
  - `Alt+Right-click` (conflicts with compare tooltip)
  - `Ctrl+Shift+Right-click` (alternative)
  - `Disabled` (use Settings panel only)
- Menu options:
  - "Add to Category" → submenu with all custom categories
  - "Lock Item" / "Unlock Item" (toggle based on current state)
  - "Mark as Junk" / "Unmark Junk" (toggle)
  - Separator
  - "Remove from Category" (only if in custom category)
  - "+ New Category..." (opens name input dialog)
- **Scope indicator**: Menu header shows "Applies to all [Item Name]"
- Uses Blizzard's dropdown menu system or custom implementation

#### `UI/BagUI/Search.lua`
- Search input field at top of bag window
- **Uses BagData cache** - calls `BagData:SearchByName()`, no live API calls
- Filters items by cached name (case-insensitive)
- Non-matching items are dimmed (not hidden) for context
- Clear button (X) to reset search
- Debounced input (0.3s delay before filtering)
- Shows "Loading..." state if cache warming (edge case on first open)

#### `UI/Panels/Categories.lua`
- Settings panel tab for category management
- Features:
  - "New Category" button
  - List of categories (collapsible, shows items inside)
  - Edit category name (pencil icon)
  - Delete category (trash icon, with confirmation)
  - Reorder categories (drag handle or up/down buttons)
  - Search box to find and add items by name
  - Drag item from bags to category in this panel
- Tip text explaining Alt+Right-click in bags

---

## Implementation Phases

### Phase 1: Foundation (Core + Basic Display)
1. Create `Modules/BagData.lua` with caching, diffing, and event system
2. Create `Modules/CustomCategories.lua` with SavedVariables schema
3. Create `UI/BagUI/Core.lua` with basic frame and bag hooks
4. Create `UI/BagUI/ItemSlot.lua` with frame pooling (see lifecycle below)
5. Create `UI/BagUI/Container.lua` consuming BagData events
6. Add settings toggle: "Use InventoryManager Bags" (default on)
7. Add combat lockdown check: `if InCombatLockdown() then return end`
8. Basic grid layout (no categories yet, just all items)

**Milestone**: Bags open/close with our UI showing all items

### Phase 2: Category System
1. Implement category detection via `GetItemInfoInstant()` → classID/subClassID mapping
2. Add CLASS_TO_CATEGORY mapping table (see Technical Details)
3. Create `UI/BagUI/CategorySection.lua` with collapsible headers
4. Group items by resolved displayCategory
5. Add collapse/expand state persistence (SavedVariables)

**Milestone**: Items grouped by IM-defined categories

### Phase 3: Custom Categories
1. Add custom category CRUD to `CustomCategories.lua`
2. Implement category priority (custom > IM default categories)
3. Create `UI/BagUI/ContextMenu.lua` for Alt+Right-click
4. Add "New Category" dialog
5. Items in custom categories removed from default categories

**Milestone**: Can create custom categories and assign items via Alt+Right-click

### Phase 4: IM Integration
1. Integrate lock overlay from existing `OverlayFactory.lua`
2. Integrate junk overlay
3. Add Alt+Click lock toggle
4. Add Ctrl+Alt+Click junk toggle
5. Add sell indicator (when merchant open)
6. Verify all existing overlay logic works

**Milestone**: Full feature parity with current bag overlay system

### Phase 5: Settings Panel
1. Create `UI/Panels/Categories.lua`
2. Add to Config.lua tab registration
3. Implement category list with edit/delete
4. Implement item search and add
5. Implement category reordering

**Milestone**: Categories manageable from settings (works with Blizzard bags too)

### Phase 6: Polish
1. Implement `UI/BagUI/Search.lua`
2. Add money display
3. Add bag slot toggles (show/hide individual bags)
4. Persist window position
5. Add reagent bag support
6. Handle bag slot purchase flow
7. Performance optimization pass

**Milestone**: Feature complete, polished UI

---

## Technical Details

### Bag Hooking Strategy

**Approach**: Store originals, replace with wrappers, add combat lockdown protection.

```lua
-- In BagUI/Core.lua OnEnable

local module = self

-- Store original functions BEFORE replacing
local origOpenAllBags = OpenAllBags
local origCloseAllBags = CloseAllBags
local origToggleAllBags = ToggleAllBags
local origOpenBag = OpenBag
local origCloseBag = CloseBag
local origToggleBag = ToggleBag

-- Replace with wrappers
function OpenAllBags(frame, forceOpen)
    -- Combat lockdown protection
    if InCombatLockdown() then return end

    if IM.db.global.useIMBags then
        module:Show()
    else
        origOpenAllBags(frame, forceOpen)
    end
end

function CloseAllBags()
    if InCombatLockdown() then return end

    if IM.db.global.useIMBags then
        module:Hide()
    else
        origCloseAllBags()
    end
end

function ToggleAllBags()
    if InCombatLockdown() then return end

    if IM.db.global.useIMBags then
        module:Toggle()
    else
        origToggleAllBags()
    end
end

-- Individual bag functions redirect to all-bags when using IM bags
function OpenBag(bagID)
    if InCombatLockdown() then return end

    if IM.db.global.useIMBags then
        module:Show()  -- IM bags show all bags together
    else
        origOpenBag(bagID)
    end
end

-- ... similar for CloseBag, ToggleBag
```

**Note**: We're replacing global functions, not using hooksecurefunc, because we need to PREVENT the original when our bags are enabled. hooksecurefunc only runs AFTER the original.

### Category Detection via classID/subClassID

**Note**: `C_Container.GetContainerItemInfo()` does NOT return "Blizzard categories" - it returns raw classID/subClassID. We define our own category mapping.

```lua
-- GetItemInfoInstant(itemID) returns: itemID, itemType, itemSubType,
--   itemEquipLoc, icon, classID, subClassID

-- WoW Item Class IDs (from Wowpedia):
-- 0 = Consumable, 1 = Container, 2 = Weapon, 3 = Gem, 4 = Armor
-- 5 = Reagent, 7 = Tradeskill, 8 = Item Enhancement, 9 = Recipe
-- 12 = Quest, 15 = Miscellaneous, 16 = Glyph, 17 = Battle Pet, 18 = WoW Token

-- Primary mapping (classID → display category)
-- For finer control, we also check subClassID where needed
local CLASS_TO_CATEGORY = {
    [0]  = "Consumables",     -- Consumable
    [1]  = "Containers",      -- Container (bags)
    [2]  = "Equipment",       -- Weapon
    [3]  = "Gems",            -- Gem
    [4]  = "Equipment",       -- Armor
    [5]  = "Reagents",        -- Reagent (distinct from Trade Goods)
    [7]  = "Trade Goods",     -- Tradeskill
    [8]  = "Enhancements",    -- Item Enhancement (enchants, etc.)
    [9]  = "Recipes",         -- Recipe
    [12] = "Quest Items",     -- Quest
    [15] = "Miscellaneous",   -- Miscellaneous (includes mounts, pets, tokens)
    [16] = "Glyphs",          -- Glyph
    [17] = "Battle Pets",     -- Battle Pet
    [18] = "Miscellaneous",   -- WoW Token
}

-- SubClass overrides for finer categorization
-- Format: SUBCLASS_OVERRIDES[classID][subClassID] = "Category"
local SUBCLASS_OVERRIDES = {
    [0] = {  -- Consumable subclasses
        [0] = "Consumables",    -- Generic
        [1] = "Consumables",    -- Potion
        [2] = "Consumables",    -- Elixir
        [3] = "Consumables",    -- Flask
        [5] = "Food & Drink",   -- Food & Drink (split out if desired)
        [7] = "Consumables",    -- Bandage
        [8] = "Consumables",    -- Other
        [9] = "Consumables",    -- Vantus Rune
    },
    [7] = {  -- Tradeskill subclasses
        [1]  = "Trade Goods",   -- Parts
        [5]  = "Trade Goods",   -- Cloth
        [6]  = "Trade Goods",   -- Leather
        [7]  = "Trade Goods",   -- Metal & Stone
        [8]  = "Trade Goods",   -- Cooking
        [9]  = "Trade Goods",   -- Herb
        [10] = "Trade Goods",   -- Elemental
        [11] = "Trade Goods",   -- Other
        [12] = "Trade Goods",   -- Enchanting
        [16] = "Trade Goods",   -- Inscription
    },
    [15] = {  -- Miscellaneous subclasses
        [0] = "Junk",           -- Junk (grey quality misc)
        [1] = "Reagents",       -- Reagent (moved to Reagents)
        [2] = "Companions",     -- Companion Pets (split out)
        [3] = "Holiday",        -- Holiday items (split out)
        [4] = "Miscellaneous",  -- Other
        [5] = "Mounts",         -- Mount (split out)
    },
}

-- Additional category for currency-like items (detected by other means)
-- "Tokens" category: items that function as currency but aren't in Currency tab
-- Detection: Check if item has "Currency" in tooltip or specific itemIDs
-- This requires a curated list or heuristic, not just classID/subClassID

-- Category display order (custom always first)
local CATEGORY_ORDER = {
    -- Custom categories inserted dynamically at top
    "Equipment",
    "Consumables",
    "Food & Drink",  -- Split from Consumables via subclass
    "Trade Goods",
    "Quest Items",
    "Reagents",
    "Gems",
    "Enhancements",
    "Recipes",
    "Containers",
    "Mounts",        -- Split from Miscellaneous
    "Companions",    -- Split from Miscellaneous (battle pets, companion pets)
    "Battle Pets",
    "Holiday",       -- Split from Miscellaneous
    "Glyphs",
    "Miscellaneous",
    "Junk",          -- Poor quality items (quality == 0)
}

local function GetItemCategory(itemID)
    -- Check custom category first (highest priority)
    local customCatID = IM.db.global.customCategories.itemAssignments[itemID]
    if customCatID then
        local cat = CustomCategories:GetByID(customCatID)
        if cat then return cat.name, true end  -- true = is custom
    end

    -- Get classID/subClassID via GetItemInfoInstant (cached, fast)
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)

    -- Check for junk quality (poor = 0)
    local _, _, quality = GetItemInfo(itemID)
    if quality == 0 then
        return "Junk", false
    end

    -- Check subclass override first, then fall back to class mapping
    local subOverrides = SUBCLASS_OVERRIDES[classID]
    if subOverrides and subOverrides[subClassID] then
        return subOverrides[subClassID], false
    end

    -- Fall back to primary class mapping
    local category = CLASS_TO_CATEGORY[classID] or "Miscellaneous"
    return category, false
end
```

### Frame Pooling for ItemSlots

**Lifecycle**: Acquire on diff-add, release on diff-remove, reuse on diff-change.

```lua
-- In ItemSlot.lua
local slotPool = {}
local activeSlots = {}  -- keyed by "bagID-slotID"

function ItemSlot:Acquire(bagID, slotID)
    local key = bagID .. "-" .. slotID
    local slot = table.remove(slotPool) or CreateItemSlotFrame()
    slot.key = key
    activeSlots[key] = slot
    return slot
end

function ItemSlot:Release(bagID, slotID)
    local key = bagID .. "-" .. slotID
    local slot = activeSlots[key]
    if slot then
        slot:Hide()
        slot:ClearAllPoints()
        slot:ClearItem()
        activeSlots[key] = nil
        table.insert(slotPool, slot)
    end
end

function ItemSlot:Get(bagID, slotID)
    local key = bagID .. "-" .. slotID
    return activeSlots[key]
end

function ItemSlot:ReleaseAll()
    for key, slot in pairs(activeSlots) do
        slot:Hide()
        slot:ClearAllPoints()
        slot:ClearItem()
        table.insert(slotPool, slot)
    end
    wipe(activeSlots)
end

-- Usage pattern with BagData events:
-- OnBagItemAdded: ItemSlot:Acquire() → UpdateSlot()
-- OnBagItemRemoved: ItemSlot:Release()
-- OnBagItemChanged: ItemSlot:Get() → UpdateSlot() (reuse existing frame)
-- OnBagItemMoved: Release old position, Acquire new (or just update position)
```

### Context Menu Structure

```lua
-- Alt+Right-click menu (Alt = IM actions, avoids Shift/Ctrl conflicts)
local menuData = {
    { text = "Add to Category", hasArrow = true, menuList = {
        -- Dynamically populated with custom categories
        { text = "Raid Consumables", func = function() AddToCategory(itemID, 1) end },
        { text = "Transmog Farm", func = function() AddToCategory(itemID, 2) end },
        { text = "", disabled = true },  -- Separator
        { text = "+ New Category...", func = function() ShowNewCategoryDialog(itemID) end },
    }},
    { text = "", disabled = true },  -- Separator
    { text = "Lock Item", func = function() ToggleLock(itemID) end },
    { text = "Mark as Junk", func = function() ToggleJunk(itemID) end },
    { text = "", disabled = true },  -- Separator
    { text = "Remove from Category", func = function() RemoveFromCategory(itemID) end,
      hidden = function() return not IsInCustomCategory(itemID) end },
}
```

### Event Handling

```lua
-- Events to register in Container.lua
local REFRESH_EVENTS = {
    "BAG_UPDATE_DELAYED",      -- Bag contents changed
    "ITEM_LOCK_CHANGED",       -- Item locked/unlocked (by game)
    "ITEM_UNLOCKED",           -- Item unlocked
    "BAG_SLOT_FLAGS_UPDATED",  -- Bag type changed
    "PLAYER_MONEY",            -- Gold changed (for display)
}

-- IM-specific events (custom, not WoW events)
-- Listen for whitelist/junkList changes to update overlays
```

### Settings Toggle Behavior

```lua
-- In Database.lua defaults
IM.defaults.global.useIMBags = true  -- Default to our bags

-- In General settings panel
UI:CreateCheckbox(parent, "Use InventoryManager Bags",
    "Replace default bags with InventoryManager's bag UI. " ..
    "Disable to use Blizzard bags with overlay features.",
    function() return IM.db.global.useIMBags end,
    function(value)
        IM.db.global.useIMBags = value
        -- Close any open bags and re-open with new system
        CloseAllBags()
    end
)
```

---

## UI Specifications

### Main Bag Window

- **Size**: ~400x500 base, resizable (persist dimensions)
- **Position**: Anchored to bottom-right (like default bags), persist position
- **Style**: Dark theme matching IM (background #141414, borders #4D4D4D)

```
┌─InventoryManager Bags ─────────────────────────[X]─┐
│ [🔍 Search...]                           💰 1,234g │
│ [Bag1][Bag2][Bag3][Bag4][Reagent]                  │
├────────────────────────────────────────────────────┤
│ ▼ Raid Consumables (5)                             │  ← Custom category
│   [Item][Item][Item][Item][Item]                   │
│                                                    │
│ ▼ Equipment (12)                                   │  ← Blizzard category
│   [Item][Item][Item][Item][Item][Item]             │
│   [Item][Item][Item][Item][Item][Item]             │
│                                                    │
│ ▼ Consumables (8)                                  │
│   [Item][Item][Item][Item][Item][Item]             │
│   [Item][Item]                                     │
│                                                    │
│ ▶ Trade Goods (23)                                 │  ← Collapsed
│                                                    │
│ ▼ Miscellaneous (4)                                │
│   [Item][Item][Item][Item]                         │
└────────────────────────────────────────────────────┘
```

### Item Slot Visuals

- **Size**: 37x37 pixels (standard WoW icon size)
- **Spacing**: 4px between slots
- **Overlays** (layered, from bottom to top):
  1. Item icon
  2. Quality border (gray/white/green/blue/purple/orange)
  3. Lock icon (top-left, golden, from existing OverlayFactory)
  4. Junk indicator (red tint or X overlay)
  5. Count text (bottom-right)
  6. Sell indicator (coin icon when at vendor)
  7. Search dim (50% opacity when filtered out)

### Category Header

- **Height**: 22px
- **Style**: Subtle separator, not a full card
- **Elements**:
  - Collapse arrow (▼/▶)
  - Category name (amber #FFB000 for custom, white for Blizzard)
  - Item count in parentheses (gray)

### Context Menu

- Standard Blizzard dropdown styling
- Width: Auto-fit to content
- Appears at cursor position

---

## Integration Points

### Existing Systems to Integrate

| System | File | Integration Method |
|--------|------|-------------------|
| Lock overlay | `OverlayFactory.lua` | Call `OverlayFactory:GetOverlay()` or extract logic |
| Lock status | `ItemLock.lua` | Check `IM.db.global.whitelist[itemID]` |
| Junk status | `JunkList.lua` | Check `IM.db.global.junkList[itemID]` |
| Tooltip info | `TooltipInfo.lua` | Works automatically via hooks |
| Sell indicators | `AutoSell.lua` | Check if item would auto-sell |
| Filters | `Filters.lua` | Use `Filters:ShouldAutoSell()` for sell status |

### Settings Panel Integration

Add new tab to `UI/Config.lua`:
```lua
local tabs = {
    -- ... existing tabs ...
    { name = "Categories", panel = UI.Panels.Categories },
}
```

---

## Open Questions / Decisions Needed

1. **Reagent Bag**: Show as separate section or integrated with main bags?
2. **Empty Slots**: Show empty slots or hide them (compact view)?
3. **Bank Integration**: Scope creep - defer to future or include bank window replacement?
4. **Equipped Items**: Show equipped gear in a separate section or just bags?
5. **New Item Glow**: Add glow effect for newly looted items?
6. **Category Icons**: Custom icons for categories or just text headers?

---

## Design Decisions (Agreed)

### Category Assignment by itemID Only (MVP Scope)
- Custom categories assign by itemID, not itemLink/GUID
- "All Healing Potions" = one assignment, regardless of suffix/bonus
- **Rationale**: Categories group item TYPES, not individual instances
- **UX Requirement**: Context menu shows "Applies to all [Item Name]" to set expectation
- **Future**: Rule-based categories (ilvl, quality, suffix) are a separate feature

### Configurable Modifier Binding for Context Menu
- Default: `Alt+Shift+Right-click` (safest, avoids all conflicts)
- Options: Alt+Right-click, Ctrl+Shift+Right-click, Disabled
- **Rationale**: Alt alone conflicts with compare tooltips; make it user choice
- Setting lives in General panel under "Bag UI" section

### IM-Defined Categories via classID/subClassID Mapping
- Primary mapping by classID with subClassID overrides for finer control
- Explicit mapping table (not Blizzard's internal sort)
- Allows splits like "Reagents" vs "Trade Goods", "Mounts" vs "Miscellaneous"
- Mapping table is documented and testable

### One-Time Bag Hook Wrapper (BagHooks.lua)
- Store original bag functions exactly ONCE on addon load
- Central dispatcher checks settings, routes to IM or original
- Prevents "last writer wins" conflicts with other bag addons
- Never reassigns global functions after initialization

### Combat Lockdown Protection
- All bag open/close/toggle operations check `InCombatLockdown()`
- Bags already open remain visible (don't force-close in combat)
- Only PREVENTS opening/closing during combat, doesn't disable entirely
- Prevents taint from calling protected functions in combat

### Reagent Bag Handling
- Uses `Enum.BagIndex.ReagentBag` (bag ID 5) explicitly
- Optional toggle in settings: "Include Reagent Bag" (default: on)
- Separate visual section or integrated based on user preference (Open Question)

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Blizzard API changes | Abstract bag access through single module |
| Performance with many items | Frame pooling, debounced updates |
| Conflict with other bag addons | Check for conflicts, show warning if detected |
| Muscle memory for existing users | Toggle option, clear migration messaging |

---

## Success Criteria

- [ ] Bag replacement works seamlessly (open/close/toggle)
- [ ] All existing IM overlays display correctly
- [ ] Custom categories can be created/edited/deleted
- [ ] Items can be assigned via Alt+Right-click
- [ ] Items can be assigned via Settings panel
- [ ] Custom categories take priority over Blizzard categories
- [ ] Toggle between IM bags and Blizzard bags works
- [ ] Performance is acceptable (no lag with 100+ items)
- [ ] Persists window position, collapsed states, dimensions

---

## Estimated Scope

| Phase | Complexity | Files |
|-------|------------|-------|
| Phase 1: Foundation | Medium | 6 new files (BagHooks, BagData, Core, Container, ItemSlot, CustomCategories) |
| Phase 2: Categories | Medium | 1 new file (CategorySection) |
| Phase 3: Custom Categories | Medium | 1 new file (ContextMenu) + edits |
| Phase 4: IM Integration | Low | Edits only |
| Phase 5: Settings Panel | Medium | 1 new file (Categories panel) + edits |
| Phase 6: Polish | Low-Medium | 1 new file (Search) + edits |

Total: ~10 new files, ~2500-3500 lines of code

---

*Plan Version: 1.3*
*Created: 2026-01-21*
*Updated: 2026-01-21 - Round 3 GPT review feedback*
*Status: Ready for Implementation*

## Changelog

### v1.3 (2026-01-21)
- **Added**: Explicit cache invalidation events list (BAG_UPDATE_DELAYED, ITEM_LOCK_CHANGED, etc.)
- **Added**: Click handler priority order (numbered 1-7, first match wins)
- **Added**: Modifier priority documented in UI requirement
- **Added**: BagHooks early load order + no rewrap on /reload
- **Expanded**: Category mapping now includes Mounts, Companions, Holiday, Food & Drink splits
- **Added**: Note about Tokens category requiring curated list (not classID-based)

### v1.2 (2026-01-21)
- **Added**: `Modules/BagHooks.lua` for one-time bag function wrapping (prevents addon conflicts)
- **Changed**: Modifier binding now configurable (Alt+Shift+Right default, avoids compare tooltip conflict)
- **Added**: subClassID override table for finer category control (Mounts, Food & Drink, etc.)
- **Added**: UX requirement for category scope indicator ("Applies to all [Item Name]")
- **Added**: Explicit reagent bag handling via `Enum.BagIndex.ReagentBag`
- **Clarified**: BagData uses UI-local cache (no TTL), separate from Filters.lua cache
- **Clarified**: Combat lockdown only prevents open/close, doesn't force-close visible bags

### v1.1 (2026-01-21)
- **Fixed**: Category detection now uses classID/subClassID mapping via `GetItemInfoInstant()`, not assumed Blizzard categories
- **Changed**: Shift+Right-click → Alt+Right-click to avoid modifier conflicts
- **Added**: `Modules/BagData.lua` for centralized caching, diffing, and event emission
- **Added**: Combat lockdown checks (`InCombatLockdown()`) on all bag operations
- **Improved**: Frame pooling lifecycle with keyed slots and diff-based acquire/release
- **Added**: Design Decisions section documenting agreed scope (itemID-only categories, etc.)
- **Clarified**: Container.lua consumes BagData events, doesn't scan directly
- **Clarified**: Search uses cached item names, no live API calls
