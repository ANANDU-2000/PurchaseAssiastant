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
