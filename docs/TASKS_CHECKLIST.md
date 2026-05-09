# Task checklist — ERP mobile UX

Legend: `[x]` done · `[~]` partial · `[ ]` pending  

## P0 — Critical (this sprint track)

- [x] Exclude **deleted** and **cancelled** purchases from `buildTradeReportAgg` and statement PDF lines (`trade_report_aggregate.dart`)
- [x] Exclude same from **home dashboard** `_aggregate` (`home_dashboard_provider.dart`)
- [x] Home donut: cap ring size (~max **35% viewport height**) — keep chart, reduce wasted space (`home_page.dart`)
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

## P3 — OCR & automation

- [ ] Alias / fuzzy catalog matching pipeline (server + client ranking)
- [ ] WhatsApp automation: queue visibility, retries, env docs

## Validation

- [ ] Manual: Reports month range with mix of active + deleted purchases → totals match expectations
- [ ] Manual: Home donut visible, not oversized on iPhone / medium Android
- [x] `flutter test test/trade_report_aggregate_test.dart` (run after aggregate changes)
