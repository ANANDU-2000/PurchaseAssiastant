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
