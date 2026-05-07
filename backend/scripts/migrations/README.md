# SQL snippets (`scripts/migrations/`)

## Canonical schema: Alembic

**Application tables** are owned by **Alembic** (`backend/alembic/versions/`). For any Postgres environment (local Docker, Supabase, Render):

```bash
cd backend
# DATABASE_URL=postgresql+asyncpg://...  (unset HEXA_USE_SQLITE for Postgres)
python -m alembic upgrade head
```

This creates/updates all trade purchase, catalog, broker, and related tables through revision **017** (and later).

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

If you add new SQL here, document whether it is **one-off** or should become a **new Alembic revision** so production stays single-source.
