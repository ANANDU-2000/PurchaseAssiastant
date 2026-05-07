# App issues tracker (Production readiness)

This file tracks the reported UX + reliability issues across **all tabs** and critical flows.

## Legend

- **status**: `open` | `in_progress` | `fixed` | `needs_verification`
- **verify**: how to confirm on device/web

## Global reliability

1. **Tab switch triggers full-app refetch / request storm**
  - **status**: in_progress
  - **evidence**: Browser Network shows repeated `trade-purchases?limit=50&offset=0` XHR canceled/pending.
  - **hypothesis**: Reports page invalidation was busting full purchase workspace on refresh/retry.
  - **fix**: Reports refresh now invalidates **only** `reportsPurchasesPayloadProvider` (no global workspace invalidation).
  - **verify**:
    - Open Reports → switch tabs → confirm `/trade-purchases` calls do not endlessly cancel/restart.
    - Retry in Reports does not trigger Home/History reload.
2. **Offline/Retry UX forces manual tapping; pages look “stuck”**
  - **status**: open
  - **verify**: throttle network → observe Reports/Home banners + recovery without repeated retries.

## Purchase History

1. **History summary shows 0 “this month” despite purchases in period**
  - **status**: fixed
  - **root cause**: calendar month vs analytics/report period mismatch (May vs Apr→May window).
  - **fix**: History header now uses `analyticsDateRangeProvider` period (same as Reports).
  - **verify**: when Reports shows purchases for 8 Apr→7 May, History header shows non-zero counts/₹.
2. **Pack totals visibility (bags/kg/boxes/tins) not prominent**
  - **status**: needs_verification
  - **fix**: History month/period pack line now uses darker emphasis color.
  - **verify**: on small phones, totals remain readable without truncation.
3. **Period selection is hard (date-from/to)**
  - **status**: fixed
  - **fix**: Added a compact History period picker (Today / Week / Month / Year / Custom) aligned with Reports.
  - **verify**: History pill “Month/Week/…” opens a bottom sheet; selecting changes both History and Reports totals instantly.
4. **Serial number missing / unclear**
  - **status**: fixed
  - **fix**: history rows now show a compact left serial (`1.` / `2.` …) for quick verbal referencing.
  - **verify**: scroll list; serial stays stable for the visible sorted list.

## Reports

1. **Reports refresh causes heavy reload**
  - **status**: fixed
  - **fix**: `_bumpInvalidate()` no longer calls `invalidatePurchaseWorkspace(ref)`.
  - **verify**: menu Refresh / pull-to-refresh / empty-state Retry only refetches reports payload.
2. **“View more” discoverability / list density**
  - **status**: fixed
  - **fix**: tighter row padding + replaced small “View more” text button with a clearer CTA: “View full list (N)”.
  - **verify**: Reports → Suppliers/Brokers tab shows compact rows and a clear full-list button.

## Forms / keyboard overlap

1. **Terms page keyboard overlaps fields / Continue**
  - **status**: needs_verification
  - **fix**: removed fixed-height wrappers in Terms fields to prevent clipping/overlap under keyboard + large text scale.
  - **verify**: iPhone + small Android, open keyboard on commission/discount/narration → fields remain usable; Continue reachable via scroll.
2. **Add item page advanced fields cramped / overlap**
  - **status**: needs_verification
  - **fix**: added extra scroll padding to Advanced TextFields so they scroll above keyboard instead of being covered.
  - **verify**: Add/Edit line → Advanced → focus Discount/Tax/Freight/Notes with keyboard open → no overlap.

## Data correctness

1. **Auto-refresh after actions (create/edit/delete/paid/share) inconsistent**
  - **status**: needs_verification
  - **verify**:
    - Create purchase → History updates without manual refresh
    - Edit purchase → History/Reports reflect changes
    - Mark paid → status updates
    - Share PDF → History remains consistent

## Next steps

- Capture **Render logs** during a “storm” moment (request-id + errors) and add as evidence here.
- Add device QA checklist links:
  - `docs/70_HISTORY_QA_CHECKLIST.md`
  - `docs/60_PRODUCTION_QA_CHECKLIST.md`

- Re-test after fixes in this session:
  - Reports list density + “View full list (N)”
  - Terms fields with keyboard open (small phones + large text scale)
  - Add/Edit item → Advanced fields with keyboard open (tax/notes)

