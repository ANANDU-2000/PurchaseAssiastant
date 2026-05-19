# Harisree documentation hub

Canonical product documentation for the Harisree Purchase Assistant (warehouse + purchase + stock).

## Read order (every Cursor session)

1. **[MASTER_REFERENCE.md](MASTER_REFERENCE.md)** — infra, UX system, page matrix, priorities, deploy (read first)
2. **[../../CURRENT_CONTEXT.md](../../CURRENT_CONTEXT.md)** — current focus and key paths
3. **[../../PROGRESS_LOG.md](../../PROGRESS_LOG.md)** — what changed and when
4. **[FEATURES_DEEP_PLAN.md](FEATURES_DEEP_PLAN.md)** — owner-visibility and feature deep specs (when relevant)

## Before any API or app test

**Step 0:** Resume Render (`my-purchases-api`) and verify `curl https://my-purchases-api.onrender.com/health` returns ok. See MASTER_REFERENCE § STEP 0.

## Files in this folder

| File | Purpose |
|------|---------|
| `MASTER_REFERENCE.md` | Single source for Harisree decisions, costs, pages, todos |
| `FEATURES_DEEP_PLAN.md` | Detailed feature specs (feed, variance, health score, etc.) |

## Related docs (repo root)

- `CURRENT_CONTEXT.md`, `PROGRESS_LOG.md`, `BUGS.md`, `TASKS.md` — session trackers
- `ALL_REMAINING_BLOCKERS.md` — known blockers (if present)
