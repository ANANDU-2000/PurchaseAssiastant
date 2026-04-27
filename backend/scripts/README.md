# Backend scripts

## `admin_reset.py`

Resets data for local / staging maintenance.

```bash
cd backend
python scripts/admin_reset.py --purchases-only
python scripts/admin_reset.py --full-reset
```

Requires `DATABASE_URL` / settings pointing at a Postgres (async) instance.

## `seed_catalog_and_suppliers.py`

Seeds categories, product hints, and suppliers from `data/files/` (or `SEED_DATA_DIR`).

**Production / Supabase:** set `DATABASE_URL` to your live `postgresql+asyncpg://…` DSN (same as the API), clear `HEXA_USE_SQLITE` in that shell, resolve `businesses.id` (Supabase SQL or `python -m scripts.op_supabase_stack` to list rows), then:

`python -m scripts.seed_catalog_and_suppliers --business-id=<uuid>` (add `--dry-run` first if you want a rollback preview).

## `validate_seed_data.py`

Checks that every key in `products_by_category_seed.json` exists as a subcategory `name` in
`categories_seed.json` (must match or `seed_catalog_and_suppliers` raises).

```bash
cd backend
python -m scripts.validate_seed_data
```

## `seed_suppliers_from_csv.py`

Imports suppliers from `data/supplers/Customer List.csv` (Name, GSTIN, PhoneNumbers, Address)
with idempotent upsert semantics (same GST, or same name + phone tail). Example:

```bash
cd backend
set DATABASE_URL=...
python -m scripts.seed_suppliers_from_csv --business-id=<uuid> [--dry-run]
```

## `monthly_payment_reminder`

Logic lives in `app/services/monthly_payment_reminder.py`. A daily 08:00 Asia/Kolkata job is registered in `app/main.py` (extend with real DB scan + notifications).

## `op_supabase_stack.py`

End-to-end for a **Postgres** `DATABASE_URL` (same as production): `verify_db_connection` → `alembic upgrade head` → list `businesses` → optional `seed_catalog_and_suppliers`.

```powershell
cd backend
$env:HEXA_USE_SQLITE = ""
$env:DATABASE_URL = "postgresql+asyncpg://..."
python -m scripts.op_supabase_stack
python -m scripts.op_supabase_stack --list-businesses
python -m scripts.op_supabase_stack --no-verify
python -m scripts.op_supabase_stack --seed --business-id <uuid>
python -m scripts.op_supabase_stack --seed-all-businesses --seed-all-dry-run
python -m scripts.op_supabase_stack --seed-all-businesses
```

Refuses to run if `HEXA_USE_SQLITE=1` or if `DATABASE_URL` is still SQLite. See [../docs/migrations_and_backfill.md](../docs/migrations_and_backfill.md) (Supabase / production section).

## `seed_all_businesses.py`

Runs idempotent JSON seed + mandatory defaults for every business.

```powershell
cd backend
$env:HEXA_USE_SQLITE = ""
$env:DATABASE_URL = "postgresql+asyncpg://..."
python -m scripts.seed_all_businesses --dry-run
python -m scripts.seed_all_businesses
```
