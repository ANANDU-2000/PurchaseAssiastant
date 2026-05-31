# MASTER CHECKLIST — Production Rebuild

**Project:** PurchaseAssistant (Harisree Warehouse)  
**Started:** 2026-05-31  
**Last Updated:** 2026-05-31

---

## PHASE 1 — FULL PROJECT AUDIT ✅ COMPLETE

- [x] Scan Flutter app structure
- [x] Scan backend structure
- [x] Scan admin_web structure
- [x] Identify duplicate pages (3 found)
- [x] Identify duplicate providers (12 found)
- [x] Identify duplicate APIs (4 found)
- [x] Identify duplicate services (5 found)
- [x] Identify dead code (8 files/dirs)
- [x] Identify state rebuild loops (3 found)
- [x] Identify network storms (4 found)
- [x] Identify stock logic errors (6 CRITICAL)
- [x] Identify memory leaks (2 found)
- [x] Generate DUPLICATE_AUDIT_REPORT.md

---

## PHASE 2 — STOCK ENGINE REBUILD ✅ COMPLETE

- [x] Remove `compute_expected_system_qty` bad formula
- [x] Implement correct formula: System Stock = Opening + Verified Deliveries + Quick Purchases + Manual Adjustments - Sales - Damages - Usage
- [x] Remove `warehouse_diff_qty` nonsensical calculation (now uses Physical vs System diff)
- [x] Remove `system_stock_out_of_sync` over-triggering logic (now uses 5% / 1-unit threshold)
- [x] Verify Opening Stock enforcement exists (API endpoint + frontend banner)
- [x] Verify delivery verification gate exists (cannot commit stock before staff_verified/partial status)
- [x] Created `stock_engine_constants.py` — Single Source of Truth for stock formulas, movement kinds, delivery states
- [x] Added movement helper functions: `movement_sales_qty_map`, `movement_damage_qty_map`, `movement_usage_qty_map`, `movement_manual_adjustment_net_map`
- [x] Fixed Flutter `StockRowMetrics.isSystemOutOfSync` to use relaxed threshold
- [x] Fixed `item_stock_snapshot_card.dart` out-of-sync logic
- [x] Fixed `item_stock_metric_strip.dart` out-of-sync logic
- [x] Added comprehensive tests for new formula
- [x] Verified delivery status state machine is correct: pending→dispatched→arrived→staff_verified→stock_committed
- [ ] TODO (Phase 3 UI): Remove "Expected Stock" display cards
- [ ] TODO (Phase 3 UI): Remove "Sync Purchase To Stock" UI actions
- [ ] TODO (Phase 3 UI): Remove purchase-total-as-inventory cards

---

## PHASE 3 — STOCK UI REBUILD 🔲 PENDING

- [ ] Rebuild Stock List columns (Item, System Stock, Physical Stock, Difference, Pending Delivery, Status, Last Updated, Verified By)
- [ ] Implement color rules (Green=Healthy, Orange=Low, Red=Out, Blue=Pending Verification, Purple=Pending Delivery)
- [ ] Rebuild Item Details Page (7 sections, no duplicates, no empty space)
- [ ] Fix Low Stock Dashboard (API errors, 401s, null states, loading loops, pagination, cache)
- [ ] Remove duplicate cards from item detail
- [ ] Remove excess scrolling/white space

---

## PHASE 4 — DASHBOARD REBUILDS 🔲 PENDING

- [ ] Rebuild Owner Dashboard (Critical Alerts → Stock Overview → Purchase Overview → Pending Deliveries → Verification Needed → Low Stock → Out Of Stock → Expenses → Tools → Recent Activity)
- [ ] Rebuild Staff Dashboard (Today's Tasks → Pending Deliveries → Verification Queue → Physical Count Tasks → Barcode Tasks → Low Stock → Tools → Recent Activity)
- [ ] Hide financial data from Staff (Profit, Expenses, Owner Analytics, Financial Reports)
- [ ] Remove empty cards
- [ ] Remove placeholder data

---

## PHASE 5 — PURCHASE ORDER, NOTIFICATIONS, USER MANAGEMENT 🔲 PENDING

- [ ] Rebuild Purchase Order display (all required fields + status colors)
- [ ] Fix notification system (remove loops, duplicates)
- [ ] Implement role-based notifications (Owner vs Staff)
- [ ] Fix User Management UX (scrolling, tabs, filters, pagination, layouts)

---

## PHASE 6 — PERFORMANCE, DATABASE, NETWORK, RESPONSIVE 🔲 PENDING

- [ ] Achieve First Load < 2 seconds
- [ ] Achieve Page Switch < 300ms
- [ ] Achieve API Response < 500ms
- [ ] Remove duplicate API calls
- [ ] Remove refresh loops
- [ ] Remove unnecessary rebuilds
- [ ] Remove polling storms
- [ ] Remove provider loops
- [ ] Remove memory leaks
- [ ] Fix Supabase indexes
- [ ] Fix N+1 queries
- [ ] Implement caching strategy
- [ ] Implement request cancellation
- [ ] Implement retry strategy
- [ ] Implement offline handling
- [ ] Fix responsive design (mobile, tablet, desktop, landscape, portrait)

---

## PHASE 7 — FINAL VALIDATION & REPORTS 🔲 PENDING

- [ ] Generate COMPLETED_TASKS.md
- [ ] Generate REMAINING_TASKS.md
- [ ] Generate BUG_REPORT.md
- [ ] Generate PERFORMANCE_REPORT.md
- [ ] Generate DATABASE_REPORT.md
- [ ] Generate PRODUCTION_READINESS_REPORT.md
- [ ] All MD files pass validation
- [ ] No duplicate code remaining
- [ ] No critical errors
- [ ] No crashes
- [ ] No loading loops
- [ ] No broken navigation
- [ ] No incorrect stock calculations
- [ ] No broken permissions
- [ ] No UI overflow
- [ ] No blank pages
- [ ] No network storms
- [ ] No memory leaks
