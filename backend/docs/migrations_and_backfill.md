# Migrations and backfill strategy

## Goals

- Introduce **trade purchase** tables without dropping legacy `entries` / `entry_line_items`.
- Extend **suppliers**, **brokers**, **catalog_items** with nullable wholesale fields (safe ALTER).
- Provide a **versioned** migration path (Alembic) for operators who prefer `alembic upgrade` over implicit `create_all`.

## Runtime behavior (development / small deploys)

- `Base.metadata.create_all` in `app/main.py` lifespan still creates **new** tables on boot.
- Column drift on existing DBs is handled with explicit `_ensure_*` ALTER blocks (same pattern as existing `place`, `whatsapp_number`, etc.).

## Alembic (production-oriented)

- Config: [alembic.ini](../alembic.ini), env: [alembic/env.py](../alembic/env.py).
- Initial revision: [alembic/versions/001_trade_purchase_core.py](../alembic/versions/001_trade_purchase_core.py) — creates `trade_purchases`, `trade_purchase_lines`, `trade_purchase_drafts`, `broker_supplier_links` if missing.

Run from `backend/`:

```bash
alembic upgrade head
```

Set `DATABASE_URL` to the same value the API uses (sync driver URL: use `postgresql://` or `sqlite:///...` — see `alembic/env.py` notes).

## Backfill (optional, controlled)

Planned job (not auto-run on API boot):

1. For each `entries` row in scope, insert `trade_purchases` with `human_id` allocated from sequence rules and `legacy_entry_id` reserved column **if added later** — current phase stores only forward-confirmed trade purchases from the new UI.
2. Map `entry_line_items` → `trade_purchase_lines` using `item_name`, `qty`, `unit`, `landing_cost`, `selling_price`, catalog FKs.

Rollback: keep legacy tables authoritative; delete `trade_purchases` rows where `source='backfill'` (future column) if a batch must be reversed.

## Safety

- All new columns nullable or defaulted.
- No destructive drops in phase 1.

## Supabase / production (real Postgres, no “all zeros”)

1. **Hosted API environment** (Render, Fly, VPS, etc.): set `DATABASE_URL` to `postgresql+asyncpg://...` (or use `DATABASE_POOLER_URL` + `DATABASE_POOLER_PASSWORD` for Supabase transaction pooler on port 6543 — see [app/database.py](../app/database.py)).
2. **Unset** or blank `HEXA_USE_SQLITE`. If it is `1` on the server, the app uses a local SQLite file and ignores Supabase, which produces empty metrics for clients talking to that API.
3. **Resume** a paused Supabase project (free tier) before testing; paused DBs time out or fail to connect.
4. **Migrations** from `backend/`: set `DATABASE_URL` to the same value the API uses, then `python -m alembic current` and `python -m alembic upgrade head`. A fresh empty Supabase instance usually has no revision drift; if `upgrade` errors on duplicate columns, you may need a one-time `alembic stamp <revision>` to match existing manual schema, then `upgrade head` again (see “Alembic” above).
5. **Verify** tables without starting uvicorn: `python -m scripts.verify_db_connection` with `CHECK_DATABASE_URL` = sync `postgresql://...` (and `CHECK_DATABASE_SSL=1` if your driver needs it). Do not print or commit the URL.
6. **Seed** catalog and suppliers: `python -m scripts.seed_catalog_and_suppliers --business-id=<UUID>` with `DATABASE_URL` pointing at Postgres. The UUID must be a row in `businesses` for the account you use in the app (sign up on the deployed API first, or read `businesses` in Supabase SQL). Wrong business id = seed succeeds but the app still looks empty.
7. **Operator helper** (verify + upgrade + list businesses + optional seed) when `DATABASE_URL` is Postgres:

```powershell
cd backend
$env:HEXA_USE_SQLITE = ""
$env:DATABASE_URL = "postgresql+asyncpg://..."   # or pooler: set in .env per app/database.py
python -m scripts.op_supabase_stack
python -m scripts.op_supabase_stack --seed --business-id <uuid>
```

8. **Secrets in chat or screenshots**: rotate the Supabase **database password** and **publishable/anon** keys in the project dashboard; never put anon keys in `DATABASE_URL`.
