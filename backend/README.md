# HEXA — FastAPI backend

## Setup

1. Copy [../.env.example](../.env.example) to `backend/.env` (or symlink). With Docker Compose from repo root:
  `DATABASE_URL=postgresql+asyncpg://hexa:hexa@localhost:5432/hexa`
2. Create venv and install:
  ```bash
   python -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
  ```
3. **PostgreSQL:** apply migrations (the API no longer runs `create_all` on Postgres — schema is Alembic-only):
  ```bash
   .venv\Scripts\alembic upgrade head
  ```
   **SQLite / `HEXA_USE_SQLITE=1`:** tables are still created at startup from models (dev convenience).
4. Run (from `backend/`):
  ```bash
   .venv\Scripts\python -m uvicorn app.main:app --reload
  ```
   API: [http://localhost:8000](http://localhost:8000) — OpenAPI: [http://localhost:8000/docs](http://localhost:8000/docs)

## Dev auth

- `POST /v1/auth/register` with `{"email":"you@example.com","username":"you","password":"your-secure-password"}` → JWT (`TokenPair`).
- `POST /v1/auth/login` with `{"email":"you@example.com","password":"..."}` → JWT.
- `POST /v1/auth/refresh` with `{"refresh_token":"..."}` → new tokens.
- `GET /v1/me/businesses` — use `Authorization: Bearer <access>`.

Optional: set `SUPERADMIN_BOOTSTRAP_EMAIL` to your first account email to grant super admin on registration.

- `POST /v1/auth/google` with `{"id_token":"<Google ID token>"}` — requires `GOOGLE_OAUTH_CLIENT_IDS` in `.env` (same Web client ID as Flutter `GOOGLE_OAUTH_CLIENT_ID`). See [flutter_app README](../flutter_app/README.md) for Google Cloud and iOS URL scheme setup.

## Layout

See [docs/architecture.md](../docs/architecture.md) and [docs/api/openapi.yaml](../docs/api/openapi.yaml).

## Production: default catalog + suppliers (client deliverable)

All workspaces store catalog data **per** `business_id`. To give every tenant the same master list from [../data/files](../data/files) (categories, subcategories, items, suppliers):

1. **API host:** set `DATABASE_URL` (or Supabase `DATABASE_POOLER_URL` + `DATABASE_POOLER_PASSWORD`). **Do not** set `HEXA_USE_SQLITE=1` on the server. On **Render**, add the same variables in the web service **Environment** tab; when `DATABASE_POOLER_URL` is set, the app uses it for the DB engine (see `[app/database.py](app/database.py)`).
2. **JSON files on the server:** the API needs the three files for `POST /v1/me/bootstrap-workspace` when a workspace is empty. Either run from a checkout that includes `../data/files`, or set `**SEED_DATA_DIR`** in `.env` to an **absolute** directory path containing the files (see root `.env.example`).
3. **Migrations:** from `backend/`, with production `DATABASE_URL` in the environment: `python -m alembic upgrade head`.
4. **Validate + backfill all existing businesses (one-time):**
  - `python -m scripts.validate_seed_data`
  - `python -m scripts.seed_all_businesses --dry-run` (optional preview)
  - `python -m scripts.seed_all_businesses`
5. **Flutter:** set production `API_BASE_URL` in build defines so the app hits this API.
6. **Note:** the seed does not create `trade_purchases` — dashboard “totals” may stay zero until users add purchases; catalog/suppliers will still be populated.

Security: the Supabase **database password** (from Project Settings) goes in `DATABASE_URL`; the **publishable/anon** client key is not a Postgres DSN and must not be used as `DATABASE_URL`.

## Tests

Requires `DATABASE_URL` (same as runtime). Install test deps:

```bash
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m pytest tests\ -q
```

## Observability & Render

**Dashboard → your Web Service → Logs** — everything stdout/stderr is searchable.

1. `**GET /health`** — lightweight liveness + config flags (no DB).
2. `**GET /health/ready**` — **DB readiness**: runs `SELECT 1`, returns JSON `db_ms`. Use as **Render Health Check Path** (`/health/ready`) so deploys flip unhealthy when Postgres/pooler is down. Expect **503** + log line `health_ready: SELECT 1 failed` when the database is unreachable.
3. `**GET /health/db-check`** — verifies key tables (`trade_purchases`, `item_categories`).

Startup logs one line:

`Observability: log_level=… slow_http_warning_ms=… request_id_echo=… sentry=…`

**Tune via env** (see root `.env.example`): `HTTP_SLOW_REQUEST_WARNING_MS` (default **500** — requests slower than this log `SLOW_HTTP …`), `HTTP_PROPAGATE_REQUEST_ID` (**true** — sets `X-Request-Id` / `X-Process-Time-Ms` on responses), `LOG_LEVEL`, `DATABASE_SLOW_QUERY_LOG_MS`, `API_READ_BUDGET_SECONDS`, `SENTRY_DSN`.

**Grepping logs:** `HTTP_JSON` (structured one-line JSON for `/v1/businesses/*`, slow requests, read-budget misses, and 4xx+), `READ_BUDGET_EXCEEDED` (GET `/reports/*` or catalog/category lists over `API_READ_BUDGET_SECONDS`), `SLOW_HTTP`, `VERY_SLOW_HTTP`, `HTTP 503`, `Postgres warmup failed`, `database`, `x-database-unavailable` (from connectivity middleware on business routes). List endpoints also emit `**list_suppliers ok`**, `**list_brokers ok**`, `**list_catalog_items ok**` with `count` and `ms` for slow-empty triage.

**Postgres / Render:** Before deploy, `SELECT version_num FROM alembic_version;` must match the revision you ship. If Supabase SQL and Alembic both touch the same revision, align `alembic_version` or the next upgrade can abort (`exit 3`). Prefer **Pre-Deploy** `alembic upgrade head` and a **Start** command that only runs `uvicorn` when using `WEB_CONCURRENCY=1` to avoid port scan timeouts during long DDL.

**Flutter:** each API call sends `**X-Request-Id`**; on failure (debug builds) DevTools/console prints it — paste into Render log search to match the same request on the server.

**Cursor MCP:** with **Render** and **Supabase** MCP servers enabled and authenticated in Cursor, you can list workspaces/services and Supabase projects from the IDE; connectivity is per your API keys, not implied by the repo alone.