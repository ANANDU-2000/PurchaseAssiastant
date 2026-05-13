# Home dashboard UX rebuild

## Goals

- Put **operations first** (pending deliveries, totals) before exploratory analytics.
- Reduce top-bar clutter: **Search** moved to bottom shell tab; **Assistant** opens from toolbar (`ShellQuickRefActions`).
- Keep **SSOT**: all money and pack totals continue to come from existing providers (`homeDashboardDataProvider`, `homeShellReportsProvider`, `buildTradeReportAgg`).

## Current touchpoints (code)

| Area | File |
|------|------|
| App bar quick actions | `flutter_app/lib/features/home/presentation/home_page.dart` |
| Shared toolbar row | `flutter_app/lib/shared/widgets/shell_quick_ref_actions.dart` |
| Delivery alert strip | `home_page.dart` (shipments awaiting delivery → purchase history) |
| Breakdown / donut | `home_page.dart` + `home_breakdown_tab_providers.dart` |

## Implemented in this pass

- Home toolbar uses `ShellQuickRefActions(..., suppressToolbarSearch: true)` so **Search** is not duplicated (bottom nav tab).
- **Assistant** is reachable via toolbar push to `/assistant` (full-screen route).

## Recommended next (not all shipped)

1. **Reorder body sections**: move “shipments awaiting delivery” above the donut when count &gt; 0.
2. **Collapsible chart**: default collapse donut on small screens; expand on tap.
3. **KPI strip**: single row — pending delivery count · total INR · pack line (reuse `formatPurchaseHistoryMonthPackLine` patterns from history).

## Non-negotiables

- Do not recompute purchase totals client-side for “truth”; only layout and navigation change unless wired to existing backend/aggregate paths.

## Cross-links

- `MOBILE_NAVIGATION_REDESIGN.md` — shell + FAB.
- `THUMB_REACHABILITY_AUDIT.md` — primary actions near bottom/right.
