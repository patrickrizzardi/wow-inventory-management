# Session State: InventoryManager

**Last Updated**: 2026-03-24

---

## Critical Rules (synced from ~/.claude/CLAUDE.md)

1. **Push back FIRST**: Challenge bad ideas before helping.
2. **Personality (TOP PRIORITY)**: Be Cortana - snarky battle buddy, not corporate.
3. **Agent delegation (PROACTIVE)**: Delegate WITHOUT being asked. Fast=search/lint, Default=features, Strong=security.
4. **CLAUDE.md after compaction**: Re-read rules + personality.
5. **Plans & TODOs**: Multi-step plans → immediately write `.claude/todos.md`. Suggest /plan before non-trivial work.
6. **Speculation**: Default to novel approaches. Mark speculation clearly.
7. **Decision tracking**: NEW → append to Active Decisions (with WHY).

---

## Current Context (REPLACE each update)

**Goal**: Reviewing user-reported bugs from community feedback
**Immediate Task**: Triaging user bug reports to see if they're already fixed or need investigation

**In Progress**:
- Reviewing community bug reports
- First report: "duplicate axe at vendor" from equipment set interaction — ANALYZED, NOT OUR BUG
  - Addon cannot create/duplicate items (server-side only)
  - Likely vendor buyback tab, equipment set ghost icon, or NA server desync
  - Equipment set protection in Filters.lua:576-580 is working correctly
  - AutoSell.lua:209-221 verifies items exist before selling

**Waiting On**:
- User may have more bug reports to review

**Previously Applied (from earlier sessions)**:
- Stack overflow in CategoryView:Refresh - header frame pooling fix
- SetScale position bug - ItemButton:SetPosition() divides x/y by button scale
- Tainted string bug - All chat message string ops wrapped in pcall
- Item Upgrade vendor taint - hooksecurefunc conversions

---

## Environment & Commands (CRITICAL - often lost after compaction)

**WoW Addon**: No containers, no DB. Direct Lua files symlinked to WoW addon folder.
**Testing**: `/reload` in WoW client, `/im debug` for verbose logging

---

## Active Decisions (append with reasoning)

- [2026-03-24] **Duplicate axe report = not our bug**: Analyzed AutoSell, Filters, and AutoSellPopup code. Addon cannot create items. User likely seeing vendor buyback tab or equipment set ghost after NA server issues.
- [2026-03-09] **Header frame pooling**: Same pattern as ItemButton pooling. CreateFrame every refresh was leaking frames as children of scrollContent, causing stack overflow when GetChildren() pushed them all onto Lua C stack.

---

## Superseded/Archived

- (none)

---

## Remember for This Project

- CategoryView headers now pooled via `_headerPool`/`_activeHeaders` (same pattern as ItemButton)
- Never use `{frame:GetChildren()}` pattern in WoW Lua - can overflow C stack with many children
- FontStrings on pooled frames stored as `header._imHeaderText` for reuse
- WoW addons CANNOT create/duplicate items - only server can. Always clarify this to users worried about item duplication.
