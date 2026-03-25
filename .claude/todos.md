# Todos: InventoryManager

## Current Goal
General maintenance and feature work

## Active Phases

### Community Bug Report Triage (In Progress)
- [x] "Duplicate axe at vendor" from equipment set — NOT OUR BUG (vendor buyback / server desync)
- [ ] Review any additional user reports

### BagUI Bug Fixes (In Progress)
- [x] Fix SetScale position bug - divide SetPoint offsets by button scale (ROOT CAUSE of right-side cutoff)
- [x] Fix stack overflow in CategoryView:Refresh - header frame leak causing GetChildren() C stack overflow (user confirmed fix good)
- [x] Fix Item Upgrade vendor opening Blizzard bags instead of ours - added ContainerFrame OnShow suppression hooks + show our bags on FRAME_SHOW
- [x] Fix mystery numbers on item icons - was ilvl/count overlap, already fixed in code (unpublished)
- [x] Add profession reagent quality pips (1/2/3 star tiers) to item icons - using Blizzard's SetItemCraftingQualityOverlay, repositioned to BOTTOMLEFT
- [x] Test at various icon sizes (16, 20, 24, 28, 32) - user confirmed good
- [x] Verify no left/right icon cutoff - user confirmed good
- [ ] Verify scrollbar properly reflects content height
- [ ] Clean up debug logging after fix confirmed

### Post-hooksecurefunc Regression Fixes
- [x] Alt+click lock not working
- [x] Ctrl+Alt+click junk toggle
- [x] Debug log spam loop
- [x] AutoSell module scope bug
- [x] Click-to-sell in bags not working
- [x] Merchant reject infinite loop
- [x] Alt+click double-firing
- [x] Ctrl+Alt+click double-firing
- [x] Infinite loop fix v2 and v3
- [x] Test vendor buy tracking after hooksecurefunc conversion - no issues reported, presumed good
- [x] Test repair tracking after hooksecurefunc conversion - no issues reported, presumed good
- [x] Test mail tracking after hooksecurefunc conversion - no issues reported, presumed good

### Feature Requests
- [ ] Bank UI - community requested, extend BagUI pattern to bank/warband bank

### UX Improvements
- [ ] Improve category exclusion descriptions/tooltips - clarify what "Trade Goods" vs "Crafting Reagents" covers (fish/leather/ore = Trade Goods classID 7, not Crafting Reagents classID 5)

### Misc Bug Fixes
- [x] SellHistory nil message
- [ ] Settings panel blocking keybinds - user says it used to work, investigate
- [ ] MoneyFrame tooltip error - happens on item hover, might be Blizzard bug

## Completed
- [2026-03-24] Duplicate axe report triaged - not our bug
- [2026-03-09] CategoryView stack overflow fix - header frame pooling
- [2026-01-30] SetScale position fix, tainted string fixes
- [2026-01-29] Bag UI search bar fix, Currency search placeholder fix, Auto-Loot Mail Feature
- [2026-01-27] Debug cleanup, Item Upgrade taint fix
