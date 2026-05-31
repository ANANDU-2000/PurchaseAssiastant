# DUPLICATE AUDIT REPORT

**Project:** PurchaseAssistant (Harisree Warehouse)  
**Date:** 2026-05-31  
**Auditor:** Production Rebuild Engine  
**Status:** PHASE 1 COMPLETE

---

## EXECUTIVE SUMMARY

| Category | Count | Severity |
|----------|-------|----------|
| Duplicate Pages/Routes | 3 | MEDIUM |
| Duplicate/Overlapping Providers | 12 | HIGH |
| Duplicate API Endpoints | 4 | HIGH |
| Duplicate Backend Services | 5 | MEDIUM |
| Dead Code / Unused Files | 8 | LOW |
| State/Performance Issues | 9 | CRITICAL |
| Stock Logic Issues | 6 | CRITICAL |
| Network Storm Risks | 4 | HIGH |

---

## 1. DUPLICATE PAGES

### 1.1 Dashboard vs Home Feature Duplication
- **File:** `features/dashboard/presentation/home_page.dart`
- **Content:** `export '../../home/presentation/home_page.dart';`
- **Issue:** The entire `features/dashboard/` directory exists solely as a re-export barrel to `features/home/`. This creates confusion and an unnecessary indirection layer.
- **Action:** DELETE `features/dashboard/` directory. Update imports.

### 1.2 Scan Purchase Page Wrapper
- **File:** `features/purchase/presentation/scan_purchase_page.dart`
- **Content:** Thin wrapper that just renders `ScanPurchaseV2Page()`
- **Issue:** Dead indirection layer from v1→v2 migration. The old `ScanPurchasePage` class is now a pass-through.
- **Action:** Route directly to `ScanPurchaseV2Page`. Remove wrapper.

### 1.3 Page Transitions Files
- **File:** `core/router/page_transitions.dart` + `core/router/page_transitions_v2.dart`
- **Issue:** Two page transition files exist. Only `page_transitions.dart` is imported by `app_router.dart`.
- **Action:** Verify `page_transitions_v2.dart` is unused. Delete if confirmed dead.

---

## 2. DUPLICATE/OVERLAPPING PROVIDERS

### 2.1 Stock-Related Providers (HIGH DUPLICATION)

| Provider | File | Overlap With |
|----------|------|-------------|
| `stockTotalsProvider` | `stock_providers.dart` | `stockOnHandTotalsProvider` — both call `getStockTotals` with different period logic |
| `stockItemIntelligenceProvider` | `stock_providers.dart` | `itemDetailBundleProvider` in `item_detail_providers.dart` — both fetch item detail data |
| `stockItemActivityProvider` | `stock_providers.dart` | `stockItemAuditProvider` — overlapping item audit/activity data |
| `lowStockByCategoryProvider` | `stock_providers.dart` | `lowStockOperationsPageProvider` in `low_stock_providers.dart` — both fetch low-stock items |
| `stockStatusCountsProvider` | `stock_providers.dart` | `stockAlertCountsProvider` in `home_owner_dashboard_providers.dart` — derived counter that watches the same source |

### 2.2 Dashboard/Home Providers (EXCESSIVE OVERLAP)

| Provider | File | Issue |
|----------|------|-------|
| `homeDashboardDataProvider` | `home_dashboard_provider.dart` | Master dashboard data with SWR caching |
| `homeOwnerPeriodDashboardProvider` | `home_owner_dashboard_providers.dart` | Reads from same homeDashboardDataProvider |
| `homeTodayDashboardDataProvider` | `home_owner_dashboard_providers.dart` | Separate API call for today-only data |
| `homeMonthDashboardDataProvider` | `home_owner_dashboard_providers.dart` | Separate API call for month data |
| `homeDashboardSyncCacheProvider` | `home_dashboard_provider.dart` | Reads same Hive cache as main provider |

**Issue:** 5 providers all serve dashboard data with slightly different date ranges but none share API calls efficiently. Each period change potentially triggers 3+ separate network requests.

### 2.3 Notification Providers (TRIPLE LAYER)

| Provider | File |
|----------|------|
| `notificationsProvider` | `notifications_provider.dart` — manual/local state |
| `appNotificationsListProvider` | `server_notifications_provider.dart` — server-fetched list |
| `mergedNotificationFeedProvider` | `notifications_provider.dart` — merges both above |
| `notificationCenterCoordinatorProvider` | `notification_center_provider.dart` — orchestrator |

**Issue:** Three layers of notification state that are ALL watched simultaneously by the shell screen AND the home page (double-watch pattern). `notificationCenterCoordinatorProvider` is watched in BOTH `ShellScreen` AND `HomePage`, causing duplicate orchestration cycles.

### 2.4 Activity/History Providers

| Provider | File | Issue |
|----------|------|-------|
| `homeRecentActivityFeedProvider` | `home_owner_dashboard_providers.dart` | Fetches purchases + stock audits + staff logs |
| `homeWarehouseActivityFullProvider` | `home_owner_dashboard_providers.dart` | Same function, larger limits |
| `homeRecentPurchasesCompactProvider` | `home_owner_dashboard_providers.dart` | DEPRECATED — still defined & potentially watched |

---

## 3. DUPLICATE API ENDPOINTS (BACKEND)

### 3.1 Dashboard vs Reports Overlap
- **`/v1/businesses/{id}/dashboard`** (`routers/dashboard.py`) — Month-based purchase totals + category + item slices
- **`/v1/businesses/{id}/reports/home-overview`** (`routers/reports_trade.py`) — Date-range purchase totals + category + item slices + subcategories + suppliers

**Issue:** Both endpoints compute fundamentally identical data (total purchase, categories, items) using the same underlying `trade_query` service. The only difference is period granularity (month vs arbitrary date range).

### 3.2 Stock List vs Low Stock Operations
- **`GET /v1/businesses/{id}/stock/list?status=low`** — Returns low-stock items from stock list endpoint
- **`GET /v1/businesses/{id}/stock/low-stock/operations`** — Separate endpoint for low-stock operations view

**Issue:** Both endpoints query the same `CatalogItem` table with status filtering. The operations endpoint adds priority scoring but the base query is duplicated.

### 3.3 Stock Totals vs Inventory Summary
- **`GET /v1/businesses/{id}/stock/totals`** — Unit bucket totals (bags/boxes/tins/kg)
- **`GET /v1/businesses/{id}/stock/inventory/summary`** — Same buckets + total value

**Issue:** Overlapping computations. Inventory summary is a superset of totals.

### 3.4 Scanner V2 + V3 Coexistence
- **`backend/app/services/scanner_v2/`** — 8 files, full pipeline
- **`backend/app/services/scanner_v3/`** — 1 file (pipeline.py)
- **`backend/app/services/purchase_scan_service.py`** — Legacy scan logic
- **`backend/app/services/purchase_scan_ai.py`** — AI scan logic

**Issue:** 4 different scanner implementations coexist. Unclear which is the production path.

---

## 4. DUPLICATE BACKEND SERVICES

### 4.1 Entry Intent Resolution
- `entry_intent_resolution.py` — v1 entry parsing
- `entry_intent_resolution_v2.py` — v2 entity field resolver (imported by v1)
- **Issue:** Both exist but v1 imports from v2. Unclear ownership.

### 4.2 Stock Services Overlap
- `stock_inventory.py` — Core stock qty computation + delivery commit
- `stock_movement_service.py` — Movement ledger application
- `stock_audit_service.py` — Audit logging
- `stock_tracking_profile.py` — Profile derivation
- `stock_variance_notifications.py` — Variance detection

**Issue:** `stock_inventory.py` contains 350+ lines of delivery-commit logic that duplicates what `stock_movement_service.py` should own. Both call `apply_stock_movement` but have independent paths for legacy DBs.

### 4.3 Unit Services
- `unit_normalization.py`
- `unit_resolution_service.py`
- `purchase_line_unit_validation.py`
- `trade_unit_type.py`

**Issue:** 4 separate services handling unit conversion/validation with potentially overlapping logic.

---

## 5. DEAD CODE / UNUSED FILES

| File/Directory | Reason |
|----------------|--------|
| `features/dashboard/` | Re-export barrel only |
| `features/purchase/presentation/scan_purchase_page.dart` | Thin wrapper (dead indirection) |
| `core/router/page_transitions_v2.dart` | Not imported anywhere |
| `homeRecentPurchasesCompactProvider` | Marked @deprecated in code |
| `backend/app/services/intent_stub.py` | Stub service — likely dev artifact |
| `backend/app/services/scanner_v2/` or `scanner_v3/` | One version should be removed |
| `flutter_app/build_error_full.txt`, `build_log.txt`, `build_verbose.txt`, `clean_analyze.txt`, `analyze_errors.txt` | Build artifacts committed to repo |
| `schema_missing_cols.sql`, `schema_expected.json` (root)` | Audit artifacts, not production code |

---

## 6. STATE & PERFORMANCE ISSUES (CRITICAL)

### 6.1 Provider Rebuild Loops
- **Home Page watches `notificationCenterCoordinatorProvider`** which in turn watches `appNotificationsListProvider` + `warehouseAlertsProvider`. These are ALSO watched by `ShellScreen`. Double-watching causes redundant API calls on every shell branch change.
- **`homeDashboardDataProvider` uses `Future.microtask`** for background refresh — when period changes, old microtasks may still be in flight while new ones launch (race condition mitigated by `bustGeneration` but adds complexity).

### 6.2 Polling Storm
- **Home page creates a 60-second polling timer** (`_rtPollHome`) that invalidates ALL dashboard + stock + alert providers.
- **On app resume**, another refresh fires with 320ms debounce.
- **Shell screen also watches `notificationCenterCoordinatorProvider`** which re-triggers on every invalidation.
- **Result:** Every 60 seconds, 8-12 API calls fire simultaneously from the home tab.

### 6.3 Multiple API Calls for Same Data
- `homeRecentActivityFeedProvider` makes 3 parallel API calls (`listTradePurchases` + `listStockAuditRecent` + `listStaffPurchaseLogs`)
- `homeWarehouseActivityFullProvider` makes the SAME 3 calls with different limits
- Both are invalidated together on home refresh → 6 calls for the same screen section.

### 6.4 IndexedStack Keep-Alive Issue
- All shell tabs stay mounted via IndexedStack. The home page has logic to SizedBox.shrink() when not visible, but providers still fire `watch()` chains.
- `providerSkipApi` guards exist but are inconsistently applied across the 46+ providers.

### 6.5 Bulk Stock Fetch (Network Storm)
- `bulkStockListProvider` pages up to 40 requests × 100 items = 4000 items loaded serially.
- No cancellation mechanism — switching away mid-load wastes bandwidth.

### 6.6 `_fetchTradePurchasesForHomeRange` Unbounded Loop
- Can loop 50000/500 = 100 iterations for a business with many purchases.
- No cancellation, no timeout within the loop.

### 6.7 Low Stock Category Provider — Full Table Scan
- `lowStockByCategoryProvider` calls `_fetchStockListAllPages` with `status: 'all'` and up to 10 pages × 200 items.
- Then filters CLIENT-SIDE for low/out/critical.
- Should use `status: 'shortage'` or `status: 'low'` server-side.

### 6.8 Cache TTL Mismatch
- `stockListCacheProvider` — 30s TTL
- `stockOnHandTotalsProvider` — 3min TTL
- `stockStatusCountsProvider` — 2min TTL
- **Result:** Stock list shows new data while totals/status badges show stale data for up to 2.5 minutes.

### 6.9 Home Dashboard `_dashInflight` Memory Leak
- `_dashInflight` map uses string keys but `.remove()` only fires on `.whenComplete()`.
- If a future throws before `.whenComplete()` runs (Dart edge case), the key persists indefinitely.
- `_homeOverviewSnapMemory` grows unbounded (no eviction policy).

---

## 7. STOCK LOGIC ISSUES (CRITICAL)

### 7.1 `compute_expected_system_qty` Formula is WRONG
**File:** `backend/app/services/stock_inventory.py`
```python
def compute_expected_system_qty(opening_stock_qty, total_delivered_qty, *, total_quick_purchase_qty=None):
    return opening + delivered + quick
```
**Problem:** This ONLY adds (opening + deliveries + quick purchases). It does NOT subtract:
- Sales
- Damages  
- Transfers
- Manual deductions

**Result:** Expected stock is ALWAYS inflated. Every item shows "out of sync" because expected > actual.

### 7.2 `system_stock_out_of_sync` Flag Over-Triggers
**File:** `backend/app/routers/stock.py` (line ~185-195)
```python
out_of_sync = (
    (opening > 0 or delivered_lifetime > 0 or quick_lifetime > 0)
    and abs(cur - expected) > Decimal("0.001")
)
```
Since `expected` is always inflated (7.1), this flag fires for almost every item that has had any usage/sales/damage.

### 7.3 Stock Update Before Verification Path Exists
**File:** `backend/app/services/stock_inventory.py` → `apply_confirmed_purchase_stock()`
- Stock is updated when `delivery_status == "stock_committed"` 
- BUT there's no mandatory verification step before `stock_committed` can be set
- The `purchase_status.py` service can transition directly to `stock_committed` without warehouse verification

### 7.4 `warehouse_diff_qty` Calculation is Misleading
```python
warehouse_diff = cur - period_purchased_qty
```
This computes `current_stock - purchases_in_period` which has NO business meaning. Current stock includes opening stock and all historical movements — comparing it to a single period's purchases is nonsensical.

### 7.5 Physical Stock vs System Stock Coupling
- Physical stock count (`StockPhysicalCount`) exists but is only used for DISPLAY
- There is NO mechanism to auto-flag items where `physical != system`
- No "pending verification" status is derived from count age

### 7.6 Opening Stock Not Enforced
- Opening stock setup page exists
- `openingStockMissingProvider` fetches missing count
- BUT no hard gate prevents purchase/stock operations when opening stock is missing
- Only a banner is shown — operations continue with `0` baseline

---

## 8. NETWORK AUDIT ISSUES

### 8.1 No Request Deduplication
- `DioAutoRetryInterceptor` exists but only handles retry logic
- No request coalescing for identical concurrent calls
- When home refreshes, 3 providers may call `listStockAuditRecent` simultaneously

### 8.2 No Global Request Cancellation
- Page navigation does not cancel in-flight requests
- `autoDispose` cleans up providers but Dio requests continue to completion
- Wasted bandwidth + potential stale state writes

### 8.3 Health Preflight Adds Latency
- `homeDashboard` does a health preflight before the actual API call (cold start wake-up)
- This adds 500-1500ms to first load on mobile
- Should be eliminated or run in parallel

### 8.4 No Offline Queue for Writes
- `offline_sync_service.dart` and `stock_offline_sync.dart` exist but only for stock updates
- Purchase creation has no offline queue

---

## 9. RESPONSIVE / UI ISSUES

### 9.1 Excessive Provider Nesting in Home Page
- Home page `build()` method has 8 `ref.listen()` calls
- Each listen re-evaluates on EVERY provider change in the chain
- Heavy render cycle for what should be a simple dashboard

### 9.2 CustomScrollView Overflow Risk
- Home page uses nested `SliverToBoxAdapter` with unbounded `Column` children
- On small screens with many alerts, content can overflow before scroll physics engage

---

## 10. PACKAGE AUDIT

### Potentially Unused Packages
| Package | Reason to Verify |
|---------|-----------------|
| `quick_actions` | Only meaningful if app shortcuts are implemented — verify usage |
| `local_auth` | Biometric lock feature — verify if active |
| `image` | Image manipulation — may only be used for barcode generation |

### Package Version Risks
| Package | Current | Note |
|---------|---------|------|
| `flutter_riverpod: ^2.6.1` | OK — latest 2.x |
| `go_router: ^14.6.2` | OK |
| `dio: ^5.7.0` | OK |
| `hive: ^2.2.3` | Consider migration to Isar or Hive v4 |

---

## 11. RECOMMENDATIONS (Priority Order)

### IMMEDIATE (Before any feature work)
1. **Remove `features/dashboard/` re-export barrel**
2. **Remove `scan_purchase_page.dart` wrapper**
3. **Remove deprecated `homeRecentPurchasesCompactProvider`**
4. **Remove build artifact files from repo**
5. **Fix double-watch of `notificationCenterCoordinatorProvider`** — only watch in ShellScreen OR HomePage, not both

### HIGH PRIORITY (Phase 2-3)
6. **Fix `compute_expected_system_qty`** — must subtract sales/damages/transfers
7. **Remove `warehouse_diff_qty`** computation — meaningless metric
8. **Add verification gate before `stock_committed`** transition
9. **Consolidate dashboard providers** — one provider per unique API call, derived providers for transformations
10. **Implement request cancellation** in Dio for navigation events

### MEDIUM PRIORITY (Phase 4-6)
11. **Merge `scanner_v2` + `scanner_v3`** into single production pipeline
12. **Consolidate unit services** into single `unit_engine` module
13. **Fix low-stock provider** to use server-side status filtering
14. **Add eviction policy** to `_homeOverviewSnapMemory`
15. **Reduce home polling** to 120s with smart invalidation on push events

---

## 12. FILES TO DELETE

```
flutter_app/lib/features/dashboard/                    (entire directory)
flutter_app/lib/features/purchase/presentation/scan_purchase_page.dart
flutter_app/lib/core/router/page_transitions_v2.dart   (verify unused first)
flutter_app/build_error_full.txt
flutter_app/build_log.txt
flutter_app/build_verbose.txt
flutter_app/clean_analyze.txt
flutter_app/analyze_errors.txt
/schema_missing_cols.sql                               (root - audit artifact)
/schema_expected.json                                  (root - audit artifact)
```

---

## AUDIT VERDICT

**This codebase is NOT production-ready.** The stock engine has fundamental formula errors that produce incorrect data for every user. The provider architecture has systemic over-fetching patterns that degrade performance. The notification system has triple-layer redundancy that causes unnecessary API calls.

**Root causes are not UX bugs — they are architectural decisions that need reversal:**
1. Stock formula excludes deductions (sales/damages)
2. Expected stock concept is fundamentally broken
3. Home dashboard attempts to be smart about caching but creates more complexity than it solves
4. No single source of truth for stock calculations
5. No enforcement of the delivery verification workflow

**Next Step:** PHASE 2 — Stock Engine Rebuild (fix the formula, enforce workflow, remove bad metrics)
