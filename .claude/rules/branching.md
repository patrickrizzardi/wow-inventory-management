# Branching

Single-developer project. **Commit directly to `main`.** No feature branch is required for
plan execution, including multi-phase OPORD plans; each phase seals as its own commit on `main`
carrying its `Plan-Phase: <plan-id>#<N>` trailer.

- No pull request gate. Close-out commits on `main` like any other phase.
- Never push to `origin` without direct authorization.
- Answered by the owner 2026-09-08; matches the standing statement in `.claude/CLAUDE.md`.
