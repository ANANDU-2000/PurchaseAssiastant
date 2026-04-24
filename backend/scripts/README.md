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

## `monthly_payment_reminder`

Logic lives in `app/services/monthly_payment_reminder.py`. A daily 08:00 Asia/Kolkata job is registered in `app/main.py` (extend with real DB scan + notifications).
