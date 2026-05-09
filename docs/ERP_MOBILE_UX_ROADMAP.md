# ERP mobile UX & performance roadmap

This document tracks the **large-scope** goals from the master brief (reports, home analytics, OCR, PWA, shortcuts, WhatsApp). Implementation is incremental; see [TASKS_CHECKLIST.md](TASKS_CHECKLIST.md) for status.

## Principles

- **Keep** the circular / donut analytics ring on Home unless product explicitly replaces it — optimize **size**, **loading**, and **empty states**, do not remove charts blindly.
- **Deleted / cancelled** purchases must not affect aggregates, PDF rows, or search surfaces that represent “active” business data.
- Mobile-first: viewport caps, keyboard-safe search, no clipped primary CTAs.

## Phases (high level)

| Phase | Scope |
|-------|--------|
| P0 | Report/home aggregates honor lifecycle; debounced search; chart viewport cap; compact loading & empty states |
| P1 | Virtualized long lists; memoization hot spots; split/heavier caching for report APIs |
| P2 | PWA install polish; app shortcuts (Android/iOS) where supported by Flutter |
| P3 | OCR alias / normalization; inline correction UX; WhatsApp queue reliability |

## Related code (Flutter)

- Reports: `flutter_app/lib/features/reports/presentation/reports_page.dart`, **Overview donut** `flutter_app/lib/features/reports/presentation/reports_overview_chart_section.dart`
- Home + donut: `flutter_app/lib/features/home/presentation/home_page.dart`, `flutter_app/lib/widgets/spend_ring_chart.dart`
- Settings quick entry: `flutter_app/lib/features/settings/presentation/settings_page.dart` (**Quick actions**)
- Aggregates: `flutter_app/lib/core/reporting/trade_report_aggregate.dart`, `flutter_app/lib/core/providers/home_dashboard_provider.dart`
- Scan bill UI: `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`

## Out of scope for a single PR

- Full React Query / TanStack migration (web admin may differ from Flutter).
- Lock Screen widgets / Dynamic Island (requires native projects + entitlement).
- Complete offline FTS unless product commits to a local DB strategy.
