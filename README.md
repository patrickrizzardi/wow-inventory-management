# InventoryManager

A comprehensive inventory management addon for World of Warcraft featuring auto-sell, item protection, gold tracking, and an optional bag replacement UI.
[Donate](https://www.paypal.com/donate/?business=5BBHTUHKML2SL&no_recurring=0&item_name=Help+me+continue+to+improve+and+update+the+addons+you+love&currency_code=USD)

---

## Features

### Auto-Sell
Automatically sells junk items when you visit a vendor.

Saves time by handling gray items automatically while protecting anything you actually want to keep.

- Quality threshold filtering (gray, white, green, etc.)
- Category exclusions (consumables, recipes, trade goods, housing items, pets, mounts, toys, currency tokens)
- Subcategory filtering (e.g., exclude only "Trade Goods &gt; Cooking")
- Custom exclusions via classID or classID_subclassID
- Soulbound item handling (protect all OR only sell soulbound)
- Uncollected transmog protection
- Equipment set protection

### Item Lock (Whitelist)
Protect specific items from being sold, auto-sold, or destroyed.

Useful for items you want to keep permanently — lock once and never worry about accidentally vendoring them.

- **Alt+Click** any item to toggle lock
- Lock icon overlay in bags
- Overrides all auto-sell rules

### Junk List
Force specific items to always be sold regardless of quality or category.

Handles items that are technically "good" quality but worthless to you — mark them as junk and they'll auto-sell like grays.

- **Ctrl+Alt+Click** any item to toggle junk status
- Skull overlay on marked items
- Overrides protections (except whitelist)

### Visual Indicators
See at a glance what will happen to each item when you visit a vendor.

- Green highlight on items that will be auto-sold
- Red null symbol on unsellable items (toggleable)
- Tooltip shows why an item is or isn't being sold
- Lock and junk icons in bags

### Gold Ledger
Tracks all gold income and expenses across every source.

Useful for understanding where your gold actually comes from and goes — no more guessing why you're broke.

- Loot, vendor sales/purchases, quest rewards
- Repair costs, auction house transactions
- Mail, trades, flight costs
- Transmog and barber costs
- Warband bank and guild bank transfers
- Black Market Auction House

### Net Worth Dashboard
View total gold across all characters with per-character breakdown and inventory value estimates.

Gives you a complete picture of your account's wealth without logging into each alt.

Access via `/im dashboard` or by clicking the gold display in the IM bag UI.

### Cross-Character Inventory Search
Search for items across all your alts by name. Shows character, location, and quantity.

Answers "which alt has my enchanting mats?" in seconds instead of logging through characters.

### Currency Search
Adds a search box directly to Blizzard's Currency tab (Character Frame → Currency).

Makes finding specific currencies faster since the list has grown massive over the years. No separate window — just type in the search box that appears in the existing currency panel.

### Mail Helper
Configure mail routing rules to suggest which alt should receive specific items.

Streamlines sending items to the right character — set up rules once and get suggestions automatically.

### Bag UI (Optional)
A category-organized bag replacement. Can be toggled off to use Blizzard's default bags.

Provides organized inventory view by item type without needing a separate bag addon. Completely optional — disable it if you prefer Blizzard's bags or another addon.

- Items grouped by category
- Reagent bag shown separately
- Equipment sets as categories
- All IM overlays work (locks, junk, sell highlights)
- Adjustable columns, scale, and window size
- Click gold to open dashboard

---

## Usage

### Quick Start
1. Install and `/reload`
2. Visit a vendor — auto-sell popup appears
3. Configure via `/im` or minimap button

### Item Actions
| Action | Result |
|--------|--------|
| **Alt+Click** | Toggle lock — prevents selling/destroying |
| **Ctrl+Alt+Click** | Toggle junk — forces auto-sell |

### Keybinds (IM Bags)
| Key | Action |
|-----|--------|
| **B** | Toggle bags |
| **Escape** | Close bags |

### Slash Commands
| Command | Description |
|---------|-------------|
| `/im` | Open settings |
| `/im dashboard` | Open dashboard |
| `/im inventory` | Search inventory |
| `/im bags` | Toggle IM bags |
| `/im sell` | Trigger auto-sell (at vendor) |
| `/im repair` | Trigger repair (at vendor) |
| `/im lock` | Lock/unlock hovered item |
| `/im junk` | Toggle junk on hovered item |
| `/im status` | Show status |
| `/im minimap` | Toggle minimap button |
| `/im debug` | Toggle debug mode |
| `/im reset` | Reset settings |
| `/im help` | List commands |

---

## Settings

Access via `/im`, minimap button, or gear icon in the bag UI.

| Tab | Description |
|-----|-------------|
| **General** | Auto-sell, auto-repair, tooltip options |
| **Bag UI** | IM bags toggle, layout settings |
| **UI** | Minimap button, auto-open, overlays |
| **Selling** | Sub-tabs: |
| ↳ Auto-Sell | Quality threshold, filters |
| ↳ Protections | Category exclusions, soulbound rules, custom exclusions |
| ↳ Whitelist | Manage locked items |
| ↳ Junk List | Manage forced junk items |
| **Dashboard** | Data retention settings |
| **Mail Helper** | Mail routing rules |
| **Currencies** | Currency search options |

---

## Tips

- Enable tooltip info in General to see classID_subclassID on items for custom exclusions
- The null symbol shows unsellable items that can still be destroyed — use Item Lock for full protection
- Equipment sets are automatically protected
- Click the gold amount in the IM bag UI to open the dashboard

---

*By Cheddarbound*
