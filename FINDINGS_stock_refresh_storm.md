# FINDINGS: Stock Page Edit/Update Not Reflecting Instantly — Lag / Refresh Loop (Issue #3)

**Status:** ✅ IMPLEMENTED — Consolidation complete. StockWriteCoordinator unifies all invalidation paths.

---

## Confirmed: Four Independent Invalidation Triggers Firing for One Save

When a user edits stock qty and taps Save in `QuickStockActionSheet`, **four separate code paths** each invalidate `stockListProvider` (and related providers) around the same time:

| # | Source File & Location | Trigger | What It Invalidates |
|---|------------------------|---------|---------------------|
| 1 | `quick_stock_action_sheet.dart` lines 556–582 `_resyncStockAfterSave()` | Post-save resync (on `addPostFrameCallback`) | `stockListProvider`, `stockItemDetailProvider`, `stockChangesFeedProvider`, `stockItemActivityProvider` + calls `invalidateStockRowSaveSurfaces()` |
| 2 | `business_aggregates_invalidation.dart` lines 492–535 `invalidateStockRowSaveSurfaces()` | Called by `_resyncStockAfterSave()` | `stockListProvider` (deferred 5s), `stockStatusCountsProvider`, `stockFilteredStatusCountsProvider`, `stockDeliveryIndicatorCountsProvider`, audit feeds, detail/activity (deferred) |
| 3 | `shell_realtime_listener.dart` lines 106–128 `_applyWarehouseSignal()` | Server push / WebSocket fan-out | `stockShellBundleProvider`, `stockListProvider` (unless `forRealtimePoll=true`), `bulkStockListProvider`, `stockTotalsProvider`, `stockOnHandTotalsProvider`, item detail/activity, status counts, delivery counts, alerts, home inventory, low-stock ops |
| 4 | `shell_tab_auto_refresh_listener.dart` lines 74–80 `_refreshBranch()` | Tab-switch + remote revision polling (8s throttle) | `stockShellBundleProvider` (for stock tab) |

### Additional Trigger
- `business_write_event.dart` → `emitBusinessWriteEvent()` (line 644 in quick_stock_action_sheet) → listened by `stock_page.dart` lines 912–921 → invalidates `stockChangesFeedProvider` + `stockListProvider` (if `affectedItemIds.isEmpty`)

---

## Trace of One Save (from `_save()` in quick_stock_action_sheet.dart)

```
1. _save() called
   → _applyOptimisticListPatch()        // Immediate local UI update (line 826-838)
   → Navigator.pop(true)                // Sheet closes
   → _completeStockSaveAfterPop()       // Unawaited background work (line 841-859)

2. _completeStockSaveAfterPop():
   → _persistStockWithRef()             // API call (patchStockItemWithRetry / recordPhysicalStockCount)
   → _applyOptimisticListPatchStatic()  // Re-apply patch with server response (line 633)
   → invalidate stockStatusCountsProvider (line 644)
   → emitBusinessWriteEvent()           // Line 645 — triggers stock_page listener (line 912-921)
   → _afterSaveBackgroundWithRef()      // Line 668

3. _afterSaveBackgroundWithRef():
   → _resyncStockAfterSave()            // Line 539 — POST-FRAME CALLBACK

4. _resyncStockAfterSave() (addPostFrameCallback fires):
   → parentRef.invalidate(stockListProvider)           // Line 568 — TRIGGER #1
   → invalidateStockRowSaveSurfaces()                  // Line 570 — TRIGGER #2
       → deferInvalidateDelayed(stockListProvider, 5s)  // Line 522 — DEFERRED TRIGGER
       → invalidate stockStatusCountsProvider etc.
   → parentRef.invalidate(stockChangesFeedProvider)    // Line 577
   → parentRef.invalidate(stockItemActivityProvider)   // Line 579

5. emitBusinessWriteEvent() (from step 2) fires:
   → stock_page.dart listener (lines 912-921)
   → ref.invalidate(stockChangesFeedProvider)
   → if affectedItemIds.isEmpty: ref.invalidate(stockListProvider)  // TRIGGER #5

6. Real-time / polling (may fire concurrently):
   → ShellRealtimeListener._applyWarehouseSignal()   // TRIGGER #3
   → ShellTabAutoRefreshListener._refreshBranch()    // TRIGGER #4 (on tab return / remote rev)
```

---

## Why This Causes Both Symptoms

### Symptom A: "Visible lag / flicker loop (repeated refetches racing each other)"

- **Trigger #1** immediately invalidates `stockListProvider` (synchronous, post-frame)
- **Trigger #2** defers another `stockListProvider` invalidation by **5 seconds** (`deferInvalidateDelayed`)
- **Trigger #3** (realtime) may fire independently, invalidating `stockListProvider` again
- **Trigger #4** (tab return / remote rev) invalidates `stockShellBundleProvider` (which `stock_page.dart` watches for page-1 data)
- **Result:** 3–4 separate refetches of the stock list within ~5 seconds, each causing a loading skeleton → data paint cycle. The UI flickers.

### Symptom B: "Row looks like it didn't update (optimistic patch rolled back / overwritten)"

- `_applyOptimisticListPatch()` at line 826 applies a **local optimistic patch** immediately so the row looks updated instantly
- But then **Trigger #1** invalidates `stockListProvider` → full refetch starts
- If the **server hasn't propagated the write yet** (DB replication lag, or the fetch hits a read replica), the refetch returns **stale data**
- The stale data **overwrites the optimistic patch** in `mergeStockListPage()` / `reconcileStockListRowPatches()`
- Then **Trigger #2's deferred 5s invalidation** fires → another refetch → this time server has the write → row finally shows correct value
- **Net effect:** User sees row update → revert to old value → update again (the "didn't update instantly" perception)

---

## The `[STOCK_STORM]` Debug Tags Confirm This

The codebase already has extensive `[STOCK_STORM]` debug prints scattered across all four trigger paths:
- `quick_stock_action_sheet.dart` lines 562, 642
- `stock_page.dart` lines 897, 915, 963
- `shell_realtime_listener.dart` lines 109, 116
- `shell_tab_auto_refresh_listener.dart` lines 78, 101, 107
- `business_aggregates_invalidation.dart` lines 503, 506

And `StockApiStormMonitor` (`stock_api_storm_monitor.dart`) is built specifically to count redundant stock API calls per 10-second window.

---

## Implemented Consolidation: StockWriteCoordinator

### Core Principle
**One save = one refetch, not N.** All paths now coordinate through `StockWriteCoordinator`.

### Implementation Summary

```
┌─────────────────────────────────────────────────────────────┐
│  StockWriteCoordinator (singleton in business_aggregates_invalidation.dart)  │
│  • Tracks pending write per itemId via Timer debounce       │
│  • On write completion (noteStockWrite):                    │
│      - Applies item patch immediately (no list flash)       │
│      - Schedules ONE deferred list reconcile (5s)           │
│      - Multiple calls within 5s for same itemId = 1 refetch │
│  • On realtime update (noteRealtimeUpdate):                 │
│      - Same debounced list invalidate                       │
│  • For immediate needs (flushStockWrite):                   │
│      - Cancels pending timer, invalidates immediately       │
└─────────────────────────────────────────────────────────────┘
```

### Files Modified

| File | Changes |
|------|---------|
| `business_aggregates_invalidation.dart` | Added `StockWriteCoordinator` class (lines 50–140), modified `invalidateStockRowSaveSurfaces()` to delegate list invalidation to coordinator (lines 599–633) |
| `quick_stock_action_sheet.dart` | Modified `_resyncStockAfterSave()` to only invalidate activity/detail feeds; list now via coordinator (lines 556–584) |
| `shell_realtime_listener.dart` | Modified `_applyWarehouseSignal()` to call `stockWriteCoordinator.noteRealtimeUpdate()` instead of directly invalidating list (lines 124–135) |
| `stock_page.dart` | Modified `businessWriteEventProvider` listener to only invalidate `stockChangesFeedProvider`; removed list invalidate (lines 912–922) |

### Key Behavioral Changes

| Scenario | Before | After |
|----------|--------|-------|
| User saves stock qty | 3–4 list refetches in 5s | 1 deferred refetch at 5s (via coordinator) |
| Realtime push (single item) | May trigger full list refetch | Item patch + deferred list (via coordinator) |
| Realtime push (multi-item) | Full list refetch | `invalidateWarehouseSurfacesLight(forRealtimePoll=true)` + per-item coordinator |
| Tab return (stock tab) | Bundle refetch only | Bundle refetch only (unchanged) |
| `businessWriteEvent` with empty `affectedItemIds` | Invalidated `stockListProvider` | No longer invalidates list |

### Verification Checklist

- [x] `flutter analyze` passes (only pre-existing warnings)
- [x] Test suite passes (pre-existing failures unrelated to changes)
- [x] Code follows existing patterns (singleton, Timer-based debounce, debug logs with `[STOCK_STORM]` tag)

### Next Steps (Post-Implementation)

1. **Device test**: Single save → verify `[STOCK_STORM]` logs show 1 list refetch (coordinator), not 4
2. **Verify optimistic patch**: Ensure optimistic value stays visible until deferred refetch completes (not overwritten by stale data)
3. **Monitor realtime behavior**: Confirm realtime updates patch item immediately, list reconciles once after debounce
4. **Optional tuning**: 5s debounce can be reduced to 2–3s if perceived as too slow (optimistic patch already provides instant feedback)