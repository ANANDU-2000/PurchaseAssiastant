# Documentation layout

| Path | Purpose |
|------|---------|
| `harisree/` | Product truth, deploy, UX system (`MASTER_REFERENCE.md`) |
| `debug/` | Root-cause and investigation notes |
| `plans/` | Feature rebuild plans (e.g. barcode scan) |
| `archive/` | Historical plans, reports validation, session scratch |
| `users/` | User management UX specs |
| `TEST_RESULTS.md` | Latest regression sign-off snapshot |
| `DATA_SOURCE_RENDER.md` | Render / data source ops |

**Not in git by design:** root `PLAN.md`, `PROMPT.md`, agent `*_AUDIT.md` (see `.gitignore`).

**Backup:** `docs/backup/BACKUP_SETUP.md` — GitHub DB backups + owner app exports.

**Pre-client handoff:** [`PRE_CLIENT_AUDIT_RESULT.md`](../PRE_CLIENT_AUDIT_RESULT.md) — fixes, checklist, device smoke.

**Migrations:** `backend/sql/MIGRATION_INDEX.md`, `backend/docs/migrations_and_backfill.md`.

**Flutter cleanup:** `docs/cleanup/` — duplicate/orphan audit, migration plan, verification checklist.
