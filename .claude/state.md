# Session State: InventoryManager

**Last Updated**: 2026-01-29

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

**Goal**: General maintenance / feature additions
**Immediate Task**: User testing converted hooks (vendor buy, repair, mail tracking)

**In Progress**:
- Icon border resize bug - debug dump behind `/im debug` flag, waiting for user to test
- Testing converted hooks (vendor buy, repair, mail tracking)

**Recently Completed** (last 3-5 items):
- FIXED Alt+click/Ctrl+Alt+click double-firing - removed duplicate handlers from ItemButton.lua (ItemLock.lua & JunkList.lua already handle via ContainerFrameItemButtonMixin hook)
- FIXED Infinite loop v2 - FinishSelling now only reschedules for valid items, not pending items
- FIXED Merchant reject loop - items merchant won't buy now tracked in _rejectedItems list
- FIXED Worth display - GetAutoSellItems now includes totalValue in returned items
- FIXED Item Upgrade taint - root cause was StaticPopup_Show function replacement

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
