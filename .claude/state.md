# Session State: InventoryManager

**Last Updated**: 2026-01-30

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

**Goal**: BagUI icon cutoff fix at larger icon sizes
**Immediate Task**: User testing SetScale position fix

**In Progress**:
- Waiting for user to test both fixes

**Fixes Applied**:
1. SetScale position bug - ItemButton:SetPosition() divides x/y by button scale
2. Tainted string bug - All chat message string ops wrapped in pcall(string.match/lower/find)
   - Core.lua: ParseMoneyFromMessage, ExtractItemLinkFromMessage
   - AuctionTracking.lua: OnSystemMessage, OnMoneyMessage
   - LootTracking.lua: OnItemLoot qty extraction, OnMoneyLoot auction/loot checks

**Waiting On**:
- User to /reload and test icon sizes + taint fix

**Recently Completed**:
- Fixed SetScale root cause of icon cutoff at sizes > 20
- Fixed tainted string errors in 6 spots across 3 files

---

## Environment & Commands (CRITICAL - often lost after compaction)

**Container Setup**:
- Containers Running: {Yes/No}
- Start Command: {e.g., `docker compose up -d`}
- Exec Pattern: {e.g., `docker compose exec api`}

**Database**:
- Connection: {e.g., localhost:3306}
- Which DB: {e.g., myapp_dev}

**Package Manager**: {bun/npm/yarn}

**Common Commands**:
```bash
# Start
{command}

# Test
{command}

# Build
{command}
```

---

## Active Decisions (append with reasoning)

- [2026-01-27] **{decision}**: {reasoning}

---

## Superseded/Archived

- (none yet)

---

## Remember for This Project

- {project-specific context}
- {user preferences}
