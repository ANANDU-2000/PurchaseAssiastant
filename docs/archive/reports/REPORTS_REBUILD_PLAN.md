# Reports Rebuild Plan

**Date:** 2026-06-01  
**Scope:** Flutter `flutter_app/lib/features/reports/`

## Phases

| Phase | Deliverable |
|-------|-------------|
| 1 | Five docs under `docs/reports/` |
| 2 | Four primary tabs; legacy URL redirects |
| 3 | `ReportsTopBar` + unified filter provider |
| 4 | Tab content: KPI-first Overview, sectioned Purchases/Stock |
| 5 | Export/search wired to filters |
| 6 | Dead code removal + tests |

## File map

| New / major | Role |
|-------------|------|
| `shell/reports_top_bar.dart` | Inline search, filter, export |
| `shell/reports_primary_tabs.dart` | Single 4-tab row |
| `core/providers/reports_filtered_provider.dart` | SSOT filtered agg + lists |
| `widgets/reports_overview_kpi_grid.dart` | 9 KPI cards |
| `filters/reports_filter_sheet.dart` | Collapsible drawer sections |

## Acceptance

- One tab row (Overview, Items, Purchases, Stock)
- No More sheet, no Activity tab, no Bag/Box/Tin chips on screen
- Filters in one drawer; search always visible
- KPIs above charts on Overview
- `flutter analyze` clean; smoke tests pass
