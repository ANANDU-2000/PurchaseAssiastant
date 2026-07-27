# HEXA Purchase Assistant

Warehouse ERP for **New Harisree Agency** — trade purchases, stock ledger, barcode ops, and owner reports. Flutter (Riverpod) + FastAPI + PostgreSQL, deployed as a **PWA** (Vercel) with API on **Render**.

## Product overview

| Area | Detail |
|------|--------|
| **Stack** | Flutter client · FastAPI · Postgres (Render) · optional Redis · GitHub Actions (CI, DB backup, API keep-alive) |
| **Platforms** | iOS/Android **PWA** (Safari/Chrome), **desktop/tablet Chrome** (NavigationRail shell), native builds optional |
| **Purchases** | Trade purchases (`trade_purchases` + `trade_purchase_lines`) — preview → confirm save; delivery pipeline; damage reports |
| **Stock** | Catalog-linked qty, physical count vs system ledger, optimistic version + 409 retry, low-stock alerts |
| **Barcode** | Camera scan, manual search, unknown code → create item or assign barcode |
| **Reports** | Trade-backed KPIs (`/reports/trade-*`) — not legacy `entries` analytics |
| **Sharing** | Purchase PDF + WhatsApp summary to accounts staff (number in Business Profile) |
| **Backup** | Weekly `pg_dump` (GitHub Actions) + in-app Export & Backup (stock Excel, monthly purchases PDF, ZIP) |
| **Roles** | Owner, manager, staff — permissions on stock edit, export, reports |

**Data truth:** Spend KPIs and report tables use **trade** endpoints. Line money: weight lines → `qty × kg_per_unit × landing_cost_per_kg`; else `qty × landing_cost`.

**Docs:** [Architecture](ARCHITECTURE.md) · [Deployment](DEPLOYMENT.md) · [Test results](docs/TEST_RESULTS.md) · [Migration index](backend/sql/MIGRATION_INDEX.md)

Also: in-app AI assistant (`/ai` → `POST .../ai/chat`), profit clarity, and Price Intelligence (PIP).

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
4. **Flutter web:** `cd flutter_app && flutter pub get && flutter build web --release && cd build/web`

> **Note:** This is a **web-only PWA**. Native platform folders (ios/, android/, windows/, macos/, linux/) have been removed. All UI is responsive across desktop and mobile browsers via the PWA manifest and service worker in `flutter_app/web/`.

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
- `docker-compose.yml` — local PostgreSQL + Redis

## Principles

- **Landing cost** is always **manual** at entry.
- **AI** parses and formats only; **backend** owns logic and profit math.
- **Preview → confirm** before persisting any entry.

## Figma

UI work follows `.cursor/rules/figma-design-system.mdc` and the UX docs above.
