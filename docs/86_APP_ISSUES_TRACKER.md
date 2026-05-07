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

3. **History summary shows 0 “this month” despite purchases in period**
   - **status**: fixed
   - **root cause**: calendar month vs analytics/report period mismatch (May vs Apr→May window).
   - **fix**: History header now uses `analyticsDateRangeProvider` period (same as Reports).
   - **verify**: when Reports shows purchases for 8 Apr→7 May, History header shows non-zero counts/₹.

4. **Pack totals visibility (bags/kg/boxes/tins) not prominent**
   - **status**: needs_verification
   - **fix**: History month/period pack line now uses darker emphasis color.
   - **verify**: on small phones, totals remain readable without truncation.

5. **Serial number missing / unclear**
   - **status**: open
   - **verify**: confirm if required in row UI; if yes add leading small index.

## Reports

6. **Reports refresh causes heavy reload**
   - **status**: fixed
   - **fix**: `_bumpInvalidate()` no longer calls `invalidatePurchaseWorkspace(ref)`.
   - **verify**: menu Refresh / pull-to-refresh / empty-state Retry only refetches reports payload.

7. **“View more” discoverability / list density**
   - **status**: open
   - **verify**: adjust list tile density, add clearer “View full list” affordance.

## Forms / keyboard overlap

8. **Terms page keyboard overlaps fields / Continue**
   - **status**: open
   - **verify**: iPhone + small Android, open keyboard on commission/discount/narration → Continue always visible or scrollable.

9. **Add item page advanced fields cramped / overlap**
   - **status**: open
   - **verify**: open Advanced, enter values, ensure no clipped labels and summary card doesn’t overflow.

## Data correctness

10. **Auto-refresh after actions (create/edit/delete/paid/share) inconsistent**
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

