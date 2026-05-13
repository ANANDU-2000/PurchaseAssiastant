# Critical runtime failures (P0) — status

This document maps **production-blocking failure modes** to the current mitigation in the Purchase Assistant Flutter app (`flutter_app/lib/`). For implementation detail, see the linked sibling docs.

## 1. Global error boundary trapping users

**Risk:** Any `FlutterError` replacing the entire app with a recovery screen; back navigation not clearing state.

**Current behavior:** [`flutter_app/lib/app.dart`](../../flutter_app/lib/app.dart) — `_HexaErrorBoundary` installs `FlutterError.onError`. In **non-debug** builds, `_hexaFlutterErrorLikelyNonFatal(details)` returns true for common layout/viewport strings (`RenderFlex`, `overflowed`, `BoxConstraints`, `viewport`) so those **do not** call `setState` with `_error`. **Retry** clears `_error`; **Go to Home** clears and calls `onGoHome` → `ref.read(appRouterProvider).go('/home')`.

**Residual risk:** Other exception types still surface the full-screen boundary; true fatals should remain recoverable via Go Home. In **debug**, all errors still surface (easier diagnosis).

**See:** [FLUTTER_ERROR_BOUNDARY_FIX.md](FLUTTER_ERROR_BOUNDARY_FIX.md)

## 2. PDF / share / print throwing into global handler

**Risk:** Unhandled async errors from PDF generation or `Printing.sharePdf` bubbling to `FlutterError.onError`.

**Current behavior:** [`flutter_app/lib/core/services/purchase_pdf.dart`](../../flutter_app/lib/core/services/purchase_pdf.dart) — `sharePurchasePdf`, `printPurchasePdf`, `downloadPurchasePdf`, `sharePurchaseFullInvoicePdf` return `Future<bool>`; failures are caught, debug-logged, return `false`. Call sites (e.g. [`purchase_home_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart), [`purchase_detail_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart), [`purchase_saved_sheet.dart`](../../flutter_app/lib/features/purchase/presentation/widgets/purchase_saved_sheet.dart)) should show SnackBar + Retry when `ok == false`.

**See:** [PDF_EXPORT_HARDENING.md](PDF_EXPORT_HARDENING.md)

## 3. Keyboard obscuring primary actions (Continue, Save)

**Risk:** Fixed bottom bars hidden behind the software keyboard on iPhone (especially Dynamic Island / large keyboards).

**Current behavior:** Purchase wizard uses `resizeToAvoidBottomInset: true` and bottom padding from `MediaQuery.viewInsetsOf(ctx).bottom` (see [`purchase_entry_wizard_v2.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart)). Catalog **Edit item** uses `showModalBottomSheet` with keyboard-aware padding (see [`catalog_item_detail_page.dart`](../../flutter_app/lib/features/catalog/presentation/catalog_item_detail_page.dart)).

**See:** [KEYBOARD_AND_SAFEAREA_AUDIT.md](KEYBOARD_AND_SAFEAREA_AUDIT.md), [IPHONE16PRO_LAYOUT_FIXES.md](IPHONE16PRO_LAYOUT_FIXES.md)

## 4. Reports “infinite loading” / empty vs error confusion

**Risk:** Spinner with contradictory empty copy; no retry after network failure.

**Current behavior:** [`reports_provider.dart`](../../flutter_app/lib/core/providers/reports_provider.dart) — `reportsPurchasesPayloadProvider`, Hive cache, merged list (`reportsPurchasesMergedProvider`), retries in `_loadReportsPurchases`; UI separates loading / error / empty in [`reports_page.dart`](../../flutter_app/lib/features/reports/presentation/reports_page.dart).

**See:** [REPORTS_PROVIDER_STABILITY.md](REPORTS_PROVIDER_STABILITY.md)

## 5. Purchase history list empty while KPIs show data

**Risk:** Layout giving ListView zero height, or filters dropping all rows.

**Current behavior:** [`purchase_home_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart) uses `tradePurchasesListProvider` + `purchaseHistoryValueSortProvider` and structured layout; if a regression appears, verify filter pipeline and `Expanded` around the list.

**See:** [PURCHASE_HISTORY_RENDER_FIX.md](PURCHASE_HISTORY_RENDER_FIX.md)

## Verification checklist

- Trigger a deliberate layout overflow in a **debug** build: confirm release/profile heuristic behavior matches expectations.
- Simulate PDF failure (airplane mode after doc build if needed): confirm SnackBar, no full-screen trap.
- iPhone-class device: open purchase wizard supplier step, focus field, confirm Continue remains reachable.

## Phase 2 (not implemented in Phase 1)

Dashboard priority reorder, shell FAB ergonomics, App Store–style search depth, and calmer offline copy are tracked in [FINAL_PRODUCTION_UX_READINESS.md](FINAL_PRODUCTION_UX_READINESS.md).
