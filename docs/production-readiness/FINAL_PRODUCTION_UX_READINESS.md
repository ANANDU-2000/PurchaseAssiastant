# Final production UX readiness

## Executive summary

Phase 1 focused on **crash resistance**, **keyboard-safe** critical flows, **reports/purchase list** stability, **PDF** error containment, **supplier suggestions**, and **navigation/search** parity with the shell—without redesigning the whole dashboard or introducing duplicate business logic.

**If you have an external “Deep UX & Bug Fix Report”** whose table marks rows **❌**, treat that table as **historical findings**, not the live backlog for this tree. This file and the sibling `*.md` notes describe what is **implemented here**; remaining work is **device QA** and optional polish.

## Phase 2 status (was “roadmap only”—now partially shipped)

| ID | Theme | Status in this repo |
|----|-------|---------------------|
| 16 | Home dashboard hierarchy (overdue / payments / today first) | **Shipped (initial):** `_HomeTraderPriorityStrip` and related ordering in [`home_page.dart`](../../flutter_app/lib/features/home/presentation/home_page.dart). Further tuning optional. |
| 17 | Bottom navigation + FAB | **Shipped:** Search branch + thumb FAB in [`shell_screen.dart`](../../flutter_app/lib/features/shell/shell_screen.dart). |
| 18 | Global search depth | **Partial:** sticky embedded search, segmented chips (incl. Contacts), recents + Clear, larger targets in [`search_page.dart`](../../flutter_app/lib/features/search/presentation/search_page.dart). Deeper “App Store” polish optional. |
| 19 | Offline / network tone | **Shipped:** calmer default copy in [`api_degraded_provider.dart`](../../flutter_app/lib/core/providers/api_degraded_provider.dart); top banner + Retry in [`app.dart`](../../flutter_app/lib/app.dart). |
| 20 | Async errors + regression discipline | **Shipped:** `PlatformDispatcher.onError` hook in [`main.dart`](../../flutter_app/lib/main.dart) (see [FLUTTER_ERROR_BOUNDARY_FIX.md](FLUTTER_ERROR_BOUNDARY_FIX.md)). **Ongoing:** CI `flutter analyze` / device smoke on Dynamic Island class. |

## Shipped in Phase 1 (verify in tree)

| Theme | Primary locations |
|-------|-------------------|
| Scoped fatal error UI + benign async hook | [`flutter_app/lib/app.dart`](../../flutter_app/lib/app.dart) `_HexaErrorBoundary`, `_hexaFlutterErrorLikelyNonFatal`, Go Home + Retry; [`main.dart`](../../flutter_app/lib/main.dart) `_installHexaPlatformAsyncErrorHook` |
| PDF bool + SnackBar pattern | [`purchase_pdf.dart`](../../flutter_app/lib/core/services/purchase_pdf.dart); call sites in purchase home / detail / saved sheet |
| Invoice PDF header metadata | [`purchase_invoice_pdf_layout.dart`](../../flutter_app/lib/core/services/purchase_invoice_pdf_layout.dart) |
| Catalog edit keyboard-safe sheet | [`catalog_item_detail_page.dart`](../../flutter_app/lib/features/catalog/presentation/catalog_item_detail_page.dart) |
| Wizard keyboard inset | [`purchase_entry_wizard_v2.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart) |
| Supplier inline suggest stability | [`party_inline_suggest_field.dart`](../../flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart) |
| Reports loading / merge / retry | [`reports_provider.dart`](../../flutter_app/lib/core/providers/reports_provider.dart), [`reports_page.dart`](../../flutter_app/lib/features/reports/presentation/reports_page.dart) |
| Purchase history sort + delivery UX | [`purchase_home_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart), [`trade_purchases_provider.dart`](../../flutter_app/lib/core/providers/trade_purchases_provider.dart) |
| Item history refresh | [`item_history_page.dart`](../../flutter_app/lib/features/item/presentation/item_history_page.dart) + **`itemHistoryLinesProvider`** |
| Report tile typography | [`reports_item_tile.dart`](../../flutter_app/lib/features/reports/presentation/reports_item_tile.dart) |
| Shell Search tab | [`shell_screen.dart`](../../flutter_app/lib/features/shell/shell_screen.dart), [`shell_branch_provider.dart`](../../flutter_app/lib/features/shell/shell_branch_provider.dart) |
| API degraded banner | [`app.dart`](../../flutter_app/lib/app.dart) + [`api_degraded_provider.dart`](../../flutter_app/lib/core/providers/api_degraded_provider.dart) — friendly inline copy + Retry |

## Documentation index (`docs/production-readiness/`)

1. [CRITICAL_RUNTIME_FAILURES.md](CRITICAL_RUNTIME_FAILURES.md)  
2. [FLUTTER_ERROR_BOUNDARY_FIX.md](FLUTTER_ERROR_BOUNDARY_FIX.md)  
3. [KEYBOARD_AND_SAFEAREA_AUDIT.md](KEYBOARD_AND_SAFEAREA_AUDIT.md)  
4. [IPHONE16PRO_LAYOUT_FIXES.md](IPHONE16PRO_LAYOUT_FIXES.md)  
5. [SUPPLIER_SUGGESTION_ENGINE_FIX.md](SUPPLIER_SUGGESTION_ENGINE_FIX.md)  
6. [REPORTS_PROVIDER_STABILITY.md](REPORTS_PROVIDER_STABILITY.md)  
7. [PURCHASE_HISTORY_RENDER_FIX.md](PURCHASE_HISTORY_RENDER_FIX.md)  
8. [PDF_EXPORT_HARDENING.md](PDF_EXPORT_HARDENING.md)  
9. [NAVIGATION_AND_SEARCH_REBUILD.md](NAVIGATION_AND_SEARCH_REBUILD.md)  
10. [FINAL_PRODUCTION_UX_READINESS.md](FINAL_PRODUCTION_UX_READINESS.md) (this file)

## Verification commands

```bash
cd flutter_app
flutter analyze
flutter test
```

Add **device** smoke: purchase wizard keyboard, supplier suggest, reports period toggles, PDF share cancel/fail, item history open, home breakdown navigation.

## Tracker hygiene (optional)

If your process requires it, sync root trackers (`PROJECT_STATUS.md`, `BUGS.md`, `PROGRESS_LOG.md`, etc.) with a one-line note pointing to this folder—no requirement to duplicate technical detail.

## Preserved invariants

- Riverpod + existing purchase/tax/unit/report **SSOT** on backend and shared Dart models must not be forked for UI convenience.  
- AI scan / draft purchase rules from workspace master rules remain unchanged by this documentation pass.
