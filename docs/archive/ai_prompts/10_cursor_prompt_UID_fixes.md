# Cursor Prompt — Fix UID-001 through UID-005 (Desktop UI issues)

Implements `docs/ai/09_UID_desktop_fixes_SPEC.md`.

## Scope lock

Only touch files listed under each task, plus files discovered as the actual root cause
(list extras in the summary). Do not refactor unrelated features or design-token mass sweeps.

## Task 1 — UID-001: blank `/stock` on direct load/reload

Investigate boot overlay race (`remove_boot_overlay_web.dart`, `main.dart` bootstrap), router
session gating (`app_router.dart`, `post_auth_route.dart`), and session restore
(`session_notifier.dart`). Keep HTML splash until Flutter bootstrap/loader has a painted frame —
do not only lengthen RAF delay.

## Task 2 — UID-002: mismatched low-stock counts

Home chip vs KPI: same source or explicit labels (`home_owner_dashboard_body.dart`,
`home_dashboard_provider.dart`).

## Task 3 — UID-003: pending badge legibility

Separate qty and day-count in stock row truck badge (`stock_row_metrics.dart`). Reuse
`HexaDsWarehouse.gap` / `HexaDsSpace.xs`.

## Task 4 — UID-004: modal overlapping action buttons

Desktop stock row actions sheet must not sit on detail CTAs without a clear scrim or
left-biased placement (`stock_row_actions.dart`, `showHexaBottomSheet` host if needed).

## Task 5 — UID-005: modal subtitle vs Physical

Relabel “Stock in hand” as System (or match Physical) in `stock_row_actions.dart` (+ twin
sheets if same string).
