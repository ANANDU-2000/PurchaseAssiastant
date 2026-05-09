# Task checklist — ERP mobile UX

Legend: `[x]` done · `[~]` partial · `[ ]` pending  

## P0 — Critical (this sprint track)

- [x] Exclude **deleted** and **cancelled** purchases from `buildTradeReportAgg` and statement PDF lines (`trade_report_aggregate.dart`)
- [x] Exclude same from **home dashboard** `_aggregate` (`home_dashboard_provider.dart`)
- [x] Home donut: cap ring size (~max **35% viewport height**) — keep chart, reduce wasted space (`home_page.dart`, `home_spend_ring_diameter.dart`)
- [x] Home breakdown: avoid **duplicate** heavy spinner vs ring loading; slimmer loading strip (`home_page.dart`)
- [x] Reports: **search** field `scrollPadding` when keyboard open (`reports_page.dart`)
- [x] Reports empty state: full-width actions + **Scan bill** / **New purchase** shortcuts (`reports_page.dart`)
- [x] Scan bill footer: **Continue** button no awkward wrap (`scan_purchase_v2_page.dart`)
- [x] Roadmap + checklist docs (`docs/ERP_MOBILE_UX_ROADMAP.md`, this file)
- [x] **Reports Overview** tab: adaptive **donut** (pack-mix by ₹), **≤35% viewport**, shimmer loading, compact empty + actions (`reports_overview_chart_section.dart`, `reports_page.dart`)
- [x] Reports Overview: **no search field** (list tabs keep search + keyboard padding)

## P1 — High

- [x] Virtualize / efficient lists: **Reports** full-screen list uses `ListView.builder` with single filtered pass per open (`reports_full_list_page.dart`); **Catalog** categories use `ListView.builder` when non-empty (`catalog_page.dart`). (Optional later: `flutter_list_view` / Sliver if lists grow past ~1k rows.)
- [x] Memoize heavy chart paths: `RepaintBoundary` on Home + Reports Overview donut + **Reports** tab list body (`home_page.dart`, `reports_overview_chart_section.dart`, `reports_page.dart`)
- [x] Collapsible report header: **Hide / show summary** (totals card) via chevron on the date row (`reports_page.dart`)
- [x] Backend + client: unified search **recent purchases** use report-eligible statuses only (`reports_eligible_only` in `trade_purchase_service.py` + `search.py`); client also filters **deleted / cancelled / draft** for cached responses (`search_page.dart`)

## P2 — Platform shortcuts & PWA

- [x] Settings → **Quick actions** card (scan, new purchase, resume draft, voice, history) (`settings_page.dart`)
- [x] Launcher / home-screen shortcuts (Android + iOS via `quick_actions`: `launcher_quick_actions.dart`, bootstrap in `app.dart`)
- [x] PWA: `web/manifest.json` (**standalone**, **shortcuts**, **lang** / **categories**); install **splash** overlay + `flutter-first-frame` + 15s fallback (`web/index.html`)

## P3 — OCR & automation (release scope)

- [x] **Catalog search / fuzzy:** Shipped — unified search **substring + fuzzy fallback** + ranking (`search.py`, client `catalog_fuzzy.dart`). Further **synonym / ERP alias tables** = future enhancement if the client requests it.
- [x] **WhatsApp automation:** Shipped baseline — flows + internal cron; **env** documented in **`.env.example`**. Production ops: configure Cloud API, cron secret, monitor logs/Sentry (no code blockers for handoff).

## Validation

- [x] **Backend:** `cd backend && pytest -q`; production guard **`HEXA_USE_SQLITE`** (`test_production_settings.py`).
- [x] **Flutter:** `cd flutter_app && flutter analyze && flutter test`.
- [x] **Reports aggregates:** `trade_report_aggregate_test.dart` — **deleted + cancelled** excluded from totals and statement lines.
- [x] **Home donut bounds:** `home_spend_ring_diameter_test.dart` — diameter respects **34% viewport cap**, **220 / 200 px ceilings**, and width ratio (substitutes manual “oversized ring” check).

## Production handoff (operator)

1. **`APP_ENV=production`**, strong **`JWT_*`**, **`DEV_RETURN_OTP=false`**, Postgres **`DATABASE_URL`** (or pooler + password split). **Never** set **`HEXA_USE_SQLITE=1`** on the server (API **fails fast** if SQLite is on in production).
2. Run **`alembic upgrade head`** against production DB (see `backend/docs/migrations_and_backfill.md`).
3. **`CORS_ORIGINS`** / **`TRUSTED_HOSTS`** match deployed web + admin origins.
4. Optional: **`SENTRY_DSN`**, tune **`DATABASE_POOL_SIZE`** / **`API_READ_BUDGET_SECONDS`** under load.
