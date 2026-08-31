# FINDINGS: Uncaught Post-Save Promise Rejection

## Summary
After a successful stock save (physical or system), the app logs `[STOCK_SAVE_SUCCESS]` then immediately throws an uncaught exception. The save genuinely succeeds on the server, but the **background resync/invalidation chain** that runs after the save is not properly awaited or wrapped in try/catch.

## Root Cause
In `features/stock/presentation/quick_stock_action_sheet.dart`:

1. **Line 843-860**: `_completeStockSaveAfterPop()` is called via `unawaited()` — fire-and-forget
2. **Line 670-678**: Inside the try block, `_afterSaveBackgroundWithRef()` is awaited
3. **Line 528-552**: `_afterSaveBackgroundWithRef()` awaits `_resyncStockAfterSave()`
4. **Line 560-583**: `_resyncStockAfterSave()` uses `WidgetsBinding.instance.addPostFrameCallback((_) { ... })` — **this is the problem**

The `addPostFrameCallback` schedules work for the **next frame** (after the current function returns). Any exceptions thrown inside that callback are **unhandled** because:
- The callback runs outside the try/catch block in `_completeStockSaveAfterPop()`
- It's a native Dart async callback, not a Future that can be caught

When the callback executes, it calls:
- `parentRef.invalidate(stockChangesFeedProvider)`
- `parentRef.invalidate(stockItemActivityProvider(itemId))`
- `parentRef.invalidate(stockItemDetailProvider(itemId))`
- `invalidateStockRowSaveSurfaces()` which triggers more invalidations

If any of these invalidated providers throw during their rebuild (e.g., the untyped empty map TypeError from CONFIRMED #1), the error becomes an **unhandled promise rejection**.

## Evidence from Console
```
[STOCK_SAVE_SUCCESS] status=null
```
Immediately followed by an uncaught exception stack trace showing the post-save invalidation chain.

## Affected Files
- `features/stock/presentation/quick_stock_action_sheet.dart` — lines 528-583 (`_resyncStockAfterSave`), 670-678 (`_afterSaveBackgroundWithRef`), 843-860 (`_save`)

## Fix Strategy
Wrap the `addPostFrameCallback` body in a try/catch with proper logging. This ensures:
1. Errors in post-save invalidation don't become unhandled rejections
2. The save success toast still shows (already shown before this runs)
3. We get visibility into any real issues for debugging
4. The UI remains responsive — the user already got confirmation

## Implementation
Change `_resyncStockAfterSave` to wrap the callback body in try/catch:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  try {
    // ... existing invalidation logic ...
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[STOCK_STORM] RESYNC_AFTER_SAVE error (caught): $e\n$st');
    }
    // Don't rethrow — this is background reconciliation, not user-facing
  }
});
```

This is a safe, low-risk fix that eliminates the unhandled promise without changing any user-visible behavior.