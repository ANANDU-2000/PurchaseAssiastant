# HEXA Purchase Assistant

Flutter + FastAPI purchase tracking with in-app AI assistant (`/ai` → `POST .../ai/chat`), profit clarity, analytics, and Price Intelligence (PIP).

## Docs

| Doc | Description |
|-----|-------------|
| [Master PRD](docs/master-prd.md) | Product scope, roles, non-goals |
| [Architecture](docs/architecture.md) | System diagram and modules |
| [Data model](docs/data-model.md) | Entities and relationships |
| [OpenAPI](docs/api/openapi.yaml) | API contract (v0.1) |
| [Flutter architecture](docs/flutter-architecture.md) | App structure, state, offline |
| [Screen map & UX](docs/ux/screen-map.md) | Pages and Figma workflow |
| [WhatsApp flows](docs/ux/whatsapp-flows.md) | Legacy webhook notes (optional forks) |
| [Super Admin](docs/admin-panel.md) | Admin surface plan |
| [Ops](docs/ops.md) | Rate limits, webhooks, monitoring |
| [Delivery phases](docs/delivery-phases.md) | MVP → Phase 4 + testing |

## Quick start

1. **Database:** `docker compose up -d` (or use your own Postgres).
2. **Env:** copy [.env.example](.env.example) to `backend/.env` and set `DATABASE_URL`, e.g.  
   `postgresql+asyncpg://hexa:hexa@localhost:5432/hexa` when using the compose Postgres.
3. **API:**
   ```bash
   cd backend
   python -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
   .venv\Scripts\python -m uvicorn app.main:app --reload
   ```
4. **Admin:** `cd admin_web && npm install && npm run dev` → http://localhost:5173  
5. **Flutter:** install Flutter SDK, then `cd flutter_app && flutter create . && flutter pub get && flutter run`

## Environment

Copy [.env.example](.env.example) to `backend/.env` and fill secrets. Never commit real keys.

## API base URL and reports routes

The Flutter app resolves the API host via `API_BASE_URL` (default `http://127.0.0.1:8000`); on web, see [flutter_app/lib/core/config/app_config.dart](flutter_app/lib/core/config/app_config.dart) for `resolvedApiBaseUrl` so the page origin and API origin line up. Trade reports (`GET /v1/businesses/{id}/reports/trade-suppliers` and related breakdowns) are registered in the FastAPI `main` module. If the client shows **404** on `/reports/*` while the code in this repo includes those routers, the running `uvicorn` process is likely an older build or a different port—restart the API from this branch and point the app at the same base URL. A one-time `debugPrint` may appear in the console on the first 404 to `/reports/*` (Dio layer).

## First deploy and seed data

After migrations and a fresh database, you can load baseline catalog and GST suppliers from JSON
(`python -m scripts.seed_catalog_and_suppliers --business-id=<uuid>`, see
[backend/scripts/README.md](backend/scripts/README.md)), then optionally bulk-import additional
suppliers from your CSV: `python -m scripts.seed_suppliers_from_csv --business-id=<uuid>`.
Re-running these scripts is safe: they skip rows that already match (GST, or name + phone).
When you add `data/products_categories_items/Products list.xlsx`, use
[data/products_categories_items/README.txt](data/products_categories_items/README.txt) as the
intended place for a future Excel-to-catalog script.

## Repo layout

- `flutter_app/` — Flutter client (run `flutter create .` after installing Flutter — see `flutter_app/README.md`)
- `backend/` — FastAPI API (`backend/.venv`, `uvicorn app.main:app --reload`)
- `admin_web/` — Super admin (`npm run dev` in `admin_web/`)
- `docker-compose.yml` — local PostgreSQL + Redis

## Principles

- **Landing cost** is always **manual** at entry.
- **AI** parses and formats only; **backend** owns logic and profit math.
- **Preview → confirm** before persisting any entry.

## Figma

UI work follows `.cursor/rules/figma-design-system.mdc` and the UX docs above.
