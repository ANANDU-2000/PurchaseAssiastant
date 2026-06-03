# Backup setup — Harisree Purchase Assistant

## 1. Database (GitHub Actions → Render Postgres)

| Item | Value |
|------|--------|
| Workflow | `.github/workflows/db-backup.yml` |
| Schedule | Sundays **03:00 UTC** |
| Manual run | GitHub → **Actions** → **db-backup** → **Run workflow** |
| Secret | `RENDER_DB_EXTERNAL_URL` (Render → harisree-db → **Connect** → external URL) |
| Artifacts | `harisree_render_YYYYMMDD.pgdump` (pg_restore) + `harisree_render_YYYYMMDD.sql` (plain text) |
| Retention | **90 days** per artifact |

Verify the secret: run workflow once; step **Verify database URL secret** must pass.

## 2. Owner app exports (Settings → Export & Backup)

| Export | Format | Contents |
|--------|--------|----------|
| Stock inventory | `.xlsx` | All items: qty, reorder, category, supplier, status |
| Purchases (this month) | `.pdf` | Trade bills in current calendar month |

Requires `export_access` (owner, admin, manager by default).

On **mobile**, files are also saved under app documents:

`warehouse_exports/{year}/{month}/stock/` and `.../purchases/`

## 3. ZIP trade backup (existing)

**Settings → Export & Backup → Download ZIP** — CSV purchase lines (month / 90 days / all).

## 4. Local copy reminder

Owners see a monthly dismissible banner on **Settings** linking to Export & Backup.
