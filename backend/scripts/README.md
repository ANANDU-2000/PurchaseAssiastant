# Backend scripts

Seed JSON lives in repo [`data/files/`](../../data/files/) (field map: [`data/files/README.md`](../../data/files/README.md)). Override with `SEED_DATA_DIR`.

Archived Render cutover scripts: [`archive/`](archive/) — do not run in production paths.

## `admin_reset.py`

```bash
cd backend
python scripts/admin_reset.py --purchases-only
python scripts/admin_reset.py --full-reset
```

Requires Postgres `DATABASE_URL` (async).

## `seed_catalog_and_suppliers.py`

```bash
cd backend
python -m scripts.seed_catalog_and_suppliers --business-id=<uuid> [--dry-run]
```

## `validate_seed_data.py`

```bash
cd backend
python -m scripts.validate_seed_data
```

## `seed_suppliers_from_csv.py`

```bash
cd backend
python -m scripts.seed_suppliers_from_csv --business-id=<uuid> [--dry-run]
```

CSV default: `data/supplers/Customer List.csv` (idempotent on GST or name+phone).

## `op_supabase_stack.py`

Postgres-only: verify DB → `alembic upgrade head` → list businesses → optional seed.

```powershell
cd backend
$env:HEXA_USE_SQLITE = ""
$env:DATABASE_URL = "postgresql+asyncpg://..."
python -m scripts.op_supabase_stack
python -m scripts.op_supabase_stack --list-businesses
python -m scripts.op_supabase_stack --seed --business-id <uuid>
```

## `seed_all_businesses.py`

```powershell
cd backend
python -m scripts.seed_all_businesses --dry-run
python -m scripts.seed_all_businesses
```
