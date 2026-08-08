# HEXA Purchase Assistant

Warehouse ERP for **New Harisree Agency** — trade purchases, stock ledger, barcode ops, and owner reports. Flutter (Riverpod) + FastAPI + PostgreSQL, deployed as a **PWA** (Vercel) with API via Cloudflare Tunnel / Windows host (see [DEPLOYMENT.md](DEPLOYMENT.md)).

## Product overview

| Area | Detail |
|------|--------|
| **Stack** | Flutter client · FastAPI · Postgres · optional Redis · GitHub Actions |
| **Platforms** | Web/PWA (desktop + mobile browsers) |
| **Purchases** | Trade purchases (`trade_purchases` + `trade_purchase_lines`) — preview → confirm |
| **Stock** | Catalog-linked qty, physical vs system ledger, optimistic version + 409 retry |
| **Barcode** | Scan, search, unknown code → create or assign |
| **Reports** | Trade-backed KPIs (`/reports/trade-*`) |
| **Roles** | Owner, manager, staff |

**Data truth:** Spend KPIs use **trade** endpoints. Line money: weight lines → `qty × kg_per_unit × landing_cost_per_kg`; else `qty × landing_cost`.

## Docs

| Doc | Purpose |
|-----|---------|
| [AGENTS.md](AGENTS.md) | Engineering rules (agents read this) |
| [PLAN.md](PLAN.md) | Feature roadmap |
| [TASKS.md](TASKS.md) | Current execution board |
| [DESIGN.md](DESIGN.md) | Design system |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Architecture reference |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Deployment |
| [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md) | Test sign-off |
| [backend/sql/MIGRATION_INDEX.md](backend/sql/MIGRATION_INDEX.md) | Migrations |

## Quick start

1. **Database:** `docker compose up -d` (or your own Postgres).
2. **Env:** copy [.env.example](.env.example) to `backend/.env` and set `DATABASE_URL` (compose example: `postgresql+asyncpg://hexa:hexa@localhost:5432/hexa`).
3. **API:**
   ```bash
   cd backend
   python -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
   .venv\Scripts\python -m uvicorn app.main:app --reload
   ```
4. **Flutter web:** `cd flutter_app && flutter pub get && flutter build web --release`

> **Note:** Web-only PWA. Native platform folders are not shipped. UI is responsive via the PWA manifest and service worker in `flutter_app/web/`.

## Environment

Copy [.env.example](.env.example) to `backend/.env`. Never commit real keys.

Flutter resolves the API host via `API_BASE_URL` (default `http://127.0.0.1:8000`); on web see `flutter_app/lib/core/config/app_config.dart`. If `/reports/*` returns 404 while this repo includes those routers, restart uvicorn from this branch and align the client base URL.

## Seed data

After migrations: `python -m scripts.seed_catalog_and_suppliers --business-id=<uuid>` (commands: [backend/scripts/README.md](backend/scripts/README.md)). Seed JSON field map: [data/files/README.md](data/files/README.md). Optional CSV: `python -m scripts.seed_suppliers_from_csv --business-id=<uuid>`. Scripts skip existing matches.

Flutter client notes: [flutter_app/README.md](flutter_app/README.md). Alembic revision gaps: [backend/alembic/versions/README.md](backend/alembic/versions/README.md). Cleanup contract: [docs/ai/16_cleanup_findings.md](docs/ai/16_cleanup_findings.md).

## Repo layout

- `flutter_app/` — Flutter client
- `backend/` — FastAPI (`uvicorn app.main:app --reload`)
- `docker-compose.yml` — local PostgreSQL + Redis
- `docs/archive/` — historical audits and prompts (not active instructions)
