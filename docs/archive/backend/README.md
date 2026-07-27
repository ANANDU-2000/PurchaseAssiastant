# SQL snippets (`scripts/migrations/`)

## Canonical schema: Alembic

**Application tables** are owned by **Alembic** (`backend/alembic/versions/`). For any Postgres environment (local Docker, Supabase, Render):

```bash
cd backend
# DATABASE_URL=postgresql+asyncpg://...  (unset HEXA_USE_SQLITE for Postgres)
python -m alembic upgrade head
```

This creates/updates all trade purchase, catalog, broker, and related tables through revision **020** (and later).

### Release checklist (Postgres / Supabase / Render)

1. **Single schema owner:** Either run **only** `python -m alembic upgrade head`, **or** apply a hand-written SQL pack (e.g. [`supabase_019_smart_unit_intelligence.sql`](../../sql/supabase_019_smart_unit_intelligence.sql)) **and** set `alembic_version.version_num` to match the latest revision you intend. Never leave `alembic_version` on **018** while tables/columns from **019** already exist — the next `upgrade` will fail (`exit 3` on Render).
2. **Verify before deploy:** `SELECT version_num FROM alembic_version;` must equal the migration chain you ship.
3. **Render:** Prefer **Pre-Deploy Command** `cd backend && alembic upgrade head` and a **Start Command** that only runs `uvicorn` (see root `.env.example` / `AUTO_MIGRATE`). Running a long migration in the same boot step as the web process can delay binding `$PORT` and trigger Render **port scan timeout** when `WEB_CONCURRENCY=1`.

## Optional: `op_supabase_stack`

End-to-end verify + upgrade + list businesses:

```bash
cd backend
python -m scripts.op_supabase_stack
```

See `scripts/README.md`.

## Files in this folder

| File | Purpose |
|------|---------|
| `001_add_catalog_item_default_kg_per_bag.sql` | Historical / manual patch — prefer Alembic if already merged. |
| `002_add_catalog_items_type_id.sql` | Same. |
| `003_add_ai_decision_engine_tables.sql` | **Supplemental** (`assistant_*`, `catalog_aliases`). Not in Alembic yet; run **only** if those features are enabled and models expect these tables. Idempotent (`IF NOT EXISTS`). |
| [`../../sql/supabase_019_smart_unit_intelligence.sql`](../../sql/supabase_019_smart_unit_intelligence.sql) | Optional mirror of Alembic **019** for Supabase SQL editor. If used, bump `alembic_version` to `019_smart_unit_intelligence` (or rely on Alembic only). |

If you add new SQL here, document whether it is **one-off** or should become a **new Alembic revision** so production stays single-source.
