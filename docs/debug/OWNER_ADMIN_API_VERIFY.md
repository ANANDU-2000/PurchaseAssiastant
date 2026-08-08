# Owner/admin API verify — 2026-08-08 (updated migrate)

## Env (local `backend/.env` — keys only)

| Key | Status |
|-----|--------|
| DATABASE_URL | SET → `localhost:5433/harisree_db` (this Cursor PC) |
| JWT_SECRET / JWT_REFRESH_SECRET | SET |
| CREDENTIAL_ENCRYPTION_KEY | unset (falls back to JWT hash) |
| AI / WhatsApp optional keys | unset (use Settings credentials or env on server) |

Script: `python backend/scripts/check_env_keys.py` → **PASS**.

## Local Postgres + Alembic (this Cursor machine)

| Check | Result |
|-------|--------|
| Port 5432 + password from old URL | **FAIL** `InvalidPasswordError` |
| Port 5433 + working local postgres user | **PASS** (Postgres 17) |
| Created `harisree_db` if missing | yes |
| `alembic upgrade head` | **PASS** → `070_ai_whatsapp_ops (head)` |
| Tables 069/070 | `backup_logs`, `provider_credentials`, `staff_tasks`, `ai_usage_logs`, `whatsapp_delivery_logs` present |
| Note | Rev `001` `create_all` can pre-create ORM tables; `069`/`070` made **idempotent** to avoid DuplicateTable |

## Unit tests

`pytest tests/test_llm_failover_unit.py tests/test_owner_ops_unit.py` → **13 passed** (SQLite override; unrelated to Postgres password).

## Live smoke (`api.harisreeagency.online`)

| Check | Result |
|-------|--------|
| health/live | PASS 200 |
| health/ready db | PASS ok |
| alembic | **069_owner_ops_tables** + `schema_ok: true` (PC6 migrate + local EXPECTED sync) |

Stock lag / Activity / physical-save debug notes: [STOCK_LAG_TRACE.md](STOCK_LAG_TRACE.md).

## PC6 Windows Server (API host) — required separately

Cursor laptop DB ≠ PC6 `localhost` Postgres.

On PC6 (AnyDesk / Git Bash), after `git pull origin main`:

```bash
cd ~/Desktop/PurchaseAssistant/backend   # adjust path
# activate venv if used
python -c "from app.config import get_settings; print(get_settings().database_url.split('@')[-1])"
# expect host/db only, e.g. localhost:5432/harisree_db

alembic current
alembic upgrade head
alembic current
# expect: 070_ai_whatsapp_ops (head)
```

Align PC6 `.env` password with **that** machine’s Postgres (case-sensitive; encode `@` as `%40`). Then restart FastAPI / tunnel service.

## RBAC / features (code already shipped)

- Credentials / dashboard / WA: owner **or** admin
- WhatsApp Graph document send; AI media OCR `use_ai`
