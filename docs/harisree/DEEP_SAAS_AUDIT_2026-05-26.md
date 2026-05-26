# Deep SaaS Audit - Harisree Warehouse ERP

Date: 2026-05-26

Scope: read-only production launch audit of the current Flutter app, FastAPI backend, Supabase schema/advisors, docs, workflows, and the 83 screenshots under `Screenshot 2026-05-26 162218 - Copy`.

## Evidence Base

- Flutter routes: mapped from `flutter_app/lib/core/router/app_router.dart`, including owner shell routes, staff shell routes, barcode, purchase, stock, reports, catalog, settings, operations, notifications, and admin routes.
- Backend APIs: mapped from `backend/app/main.py` and 23 router modules under `backend/app/routers`.
- Core stock logic: reviewed `backend/app/services/trade_purchase_service.py`, `backend/app/services/stock_inventory.py`, `backend/app/services/unit_normalization.py`, `backend/app/services/stock_tracking_profile.py`, `backend/app/routers/stock.py`, and purchase/stock schemas.
- UI state and offline flows: reviewed `flutter_app/lib/core/providers/stock_providers.dart`, `flutter_app/lib/core/providers/business_aggregates_invalidation.dart`, `flutter_app/lib/core/services/offline_store.dart`, `flutter_app/lib/core/services/offline_sync_service.dart`, `flutter_app/lib/core/services/stock_offline_sync.dart`, stock screens, purchase wizard, barcode scanner, and PDF actions.
- Supabase state: live public schema has 2,773 catalog items, 3,988 suppliers, 62 trade purchases, 113 trade purchase lines, 20 stock adjustment rows, `alembic_version = 036_staff_purchase_logs`, and many legacy SaaS tables still present.
- Screenshot coverage: reviewed auth/home/stock/purchase/detail/reports/notifications/settings/opening stock/staff cash purchase/barcode print/PDF/label preview/user profile/activity/checklist/mobile and desktop variants.

## Scorecards

- Production Readiness Score: 68/100. Core app works and automated checks previously passed, but stock concurrency, ledger reconciliation, permissions, RLS posture, and operational offline behavior are not launch-grade.
- Scalability Score: 58/100. Current catalog size already shows pain: stock list and low-stock flows load and sort all rows in Python, then run per-row supplier lookups.
- Security Score: 55/100. FastAPI membership checks exist, but backend authorization is too broad for payment/delivery/report/catalog actions; Supabase RLS is enabled without policies across most tables; public QR exposes live stock.
- Mobile UX Score: 72/100. Many screens are usable and mobile-first, but high-value warehouse flows still need denser rows, sticky actions, clearer empty states, and faster tap paths.
- Warehouse Efficiency Score: 63/100. Staff scan, count, and cash purchase flows exist, but offline replay is manual, stock update semantics are confusing, and owner audit visibility is fragmented.

## Critical Issues

### C1. Concurrent Stock Writes Can Lose Updates

Problem: stock mutations read `CatalogItem.current_stock`, calculate a new value in Python, assign `item.current_stock`, and commit without row-level locks or atomic SQL updates.

Root cause: `backend/app/services/stock_inventory.py` applies deltas after `select(CatalogItem)`; `backend/app/routers/stock.py` performs direct assignments for staff cash purchases, opening stock, stock patch, and undo; `backend/app/services/stock_audit_service.py` also assigns counted stock directly. No path uses `SELECT ... FOR UPDATE`, an optimistic version column, or `UPDATE current_stock = current_stock + delta WHERE ...`.

Affected files:

- `backend/app/services/stock_inventory.py`
- `backend/app/routers/stock.py`
- `backend/app/services/stock_audit_service.py`
- `backend/app/services/trade_purchase_service.py`

Affected workflow: two staff members confirm delivery, update stock, scan-count the same item, or log cash purchase at the same time.

Reproduction steps:

1. Open the same item on two devices.
2. Device A logs a staff cash purchase of `+2`.
3. Device B verifies physical stock or confirms delivery while A's request is in flight.
4. The later commit overwrites the earlier read-derived value.

Data corruption risk: high. On-hand stock can silently miss one operation.

Financial risk: high. Reorder, inventory value, purchase reconciliation, and owner reports become wrong.

Recommended scalable fix: centralize every stock mutation in a transaction-safe stock ledger service. Use row locks or atomic SQL deltas for additive operations, version checks for absolute counts, and a mandatory stock ledger row per mutation. Return the committed row version to the client.

Prevention strategy: add concurrent integration tests with two async sessions updating the same `CatalogItem`; reject stale absolute counts unless the request includes the last observed stock version.

### C2. Ledger Variance Counts Undelivered And Deleted Purchases As Expected Stock

Problem: stock variance and period purchase maps treat purchase lines as purchased stock even when a purchase is still pending delivery or soft-deleted.

Root cause: `_period_purchased_map()` in `backend/app/routers/stock.py` filters only `TradePurchase.status != "cancelled"`. It does not exclude `status == "deleted"` and does not require `TradePurchase.is_delivered == true`. `_ledger_variance_map()` then uses this all-time purchased map as expected stock.

Affected files:

- `backend/app/routers/stock.py`
- `backend/app/services/trade_purchase_service.py`
- `flutter_app/lib/features/stock/presentation/stock_table_row.dart`
- `flutter_app/lib/core/providers/stock_providers.dart`

Affected workflow: purchase order created but not received, then owner opens stock list, intelligence, variance feed, reports, or warehouse health.

Reproduction steps:

1. Create a purchase with `is_delivered = false`.
2. Open stock list or item intelligence.
3. The pending purchase contributes to expected purchased quantity while current stock remains unchanged.
4. If the purchase is deleted, it can still remain in expected stock because only cancelled is filtered.

Business impact: owners see false stock mismatch and incorrect purchased period quantities. Staff may be sent to verify inventory that is not actually missing.

Recommended scalable fix: split `ordered_qty`, `received_qty`, and `current_stock_delta` semantics. Ledger reconciliation should use delivered/received purchases only. Period analytics can show ordered and received separately.

Prevention strategy: add tests for pending, delivered, cancelled, and deleted purchases against `_period_purchased_map()`, `_ledger_variance_map()`, stock list, and item intelligence responses.

### C3. Sensitive Purchase Actions Are Backend Membership-Only

Problem: backend endpoints for delivery toggles, payment patching, and mark-paid only require business membership, while delete/edit/create have stronger permissions.

Root cause: `backend/app/routers/trade_purchases.py` uses `require_membership` for `PATCH /payment`, `PATCH /delivery`, and `POST /mark-paid`. The Flutter router redirects staff away from owner routes, but client routing is not a security boundary.

Affected files:

- `backend/app/routers/trade_purchases.py`
- `flutter_app/lib/core/router/app_router.dart`
- `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`
- `flutter_app/lib/features/staff/presentation/staff_receive_shipment_page.dart`

Affected workflow: staff or any authenticated member can call APIs directly to mark delivery pending/received or mark a purchase paid.

Business impact: unauthorized changes can alter stock, financial status, payment visibility, and delivery audit history.

Recommended scalable fix: use explicit permissions: `purchase_delivery_confirm`, `purchase_payment_edit`, and `purchase_mark_paid`. Staff receiving flow can keep a limited `delivery_receive` permission, but revocation/payment should be manager/owner only.

Prevention strategy: add API authorization tests for staff, manager, owner, and super admin for each mutating purchase endpoint.

### C4. Supabase RLS Is Enabled But Has No Policies Across Production Tables

Problem: Supabase advisor reports RLS enabled with no policies on nearly every public table, including `catalog_items`, `trade_purchases`, `trade_purchase_lines`, `stock_adjustment_log`, `users`, `memberships`, `suppliers`, `staff_activity_log`, `stock_physical_counts`, and `staff_purchase_logs`.

Root cause: the application uses FastAPI service-role style database access and has not implemented Supabase client-side RLS policies. RLS is enabled mainly as a linter/security posture, but no table policies define tenant isolation for direct Supabase access.

Affected files and systems:

- Supabase public schema
- `backend/sql/*.sql`
- `backend/alembic/versions/*.py`
- `backend/app/database.py`
- all data tables exposed if a non-service Supabase client is introduced later

Business impact: direct Supabase integrations, future mobile Supabase clients, or leaked credentials can behave unexpectedly. With anon/authenticated keys, tables are effectively inaccessible; with service keys, RLS is bypassed, so app security depends entirely on FastAPI.

Recommended scalable fix: choose one security model explicitly. If FastAPI is the only data gateway, keep service credentials server-only and document RLS as deny-by-default. If Supabase clients will read/write directly, add tenant-scoped policies using membership claims and test them.

Prevention strategy: add a database security checklist to release QA: no service key in clients, no direct Supabase data access without policies, and advisors reviewed before deploy.

## High Priority Issues

### H1. Stock List Pagination Loads All Catalog Rows Before Slicing

Problem: `/stock/list`, `/stock/low`, and purchased-in-period filtering fetch all matching catalog rows, compute status in Python, sort in memory, then slice.

Root cause: `_query_items()` in `backend/app/routers/stock.py` executes the full query with no database `LIMIT/OFFSET`, filters by computed status in Python, and sorts in Python. `/stock/low` asks for up to 10,000 rows. Each returned page also calls `_supplier_name()` per row.

Affected files:

- `backend/app/routers/stock.py`
- `flutter_app/lib/core/providers/stock_providers.dart`
- `flutter_app/lib/features/stock/presentation/stock_page.dart`
- `flutter_app/lib/features/barcode/presentation/bulk_barcode_print_page.dart`

Business impact: the live database already has 2,773 catalog items. At 10,000+ SKUs this becomes slow, expensive, and fragile on Render free-tier or mobile networks.

Recommended fix: move filtering, status bucketing, and sorting into SQL. Add `LIMIT/OFFSET`. Batch supplier names by `last_supplier_id`. Add indexes for `business_id`, `deleted_at`, `current_stock`, `reorder_level`, `last_stock_updated_at`, lower-name search, item code, barcode, and category/type filters.

### H2. Catalog And Contact Mutations Use Broad Membership Instead Of Permissions

Problem: many catalog and contacts mutating endpoints use `require_membership`, not role or permission checks.

Root cause: `backend/app/routers/catalog.py` and `backend/app/routers/contacts.py` rely on membership for create/update/delete in several routes.

Affected workflow: staff with membership can potentially create, rename, delete, or alter catalog and supplier records through direct API calls even if the UI hides those actions.

Business impact: wrong item names, unit profiles, supplier links, and barcodes can corrupt purchase matching and warehouse labels.

Recommended fix: add permission checks: `catalog_view`, `catalog_edit`, `supplier_edit`, `barcode_edit`, `reorder_edit`. Keep staff-scanner quick-create behind a narrow permission and owner review.

### H3. Offline Stock Queue Is Manual And Separate From The Main Offline Sync Loop

Problem: queued stock verify/audit actions are not replayed by the periodic `OfflineSyncService`; they only replay when the barcode page calls `stockOfflineSyncProvider.syncNow()`.

Root cause: `flutter_app/lib/core/services/offline_sync_service.dart` only handles `trade_purchase_create`; stock queue replay lives separately in `flutter_app/lib/core/services/stock_offline_sync.dart`.

Affected files:

- `flutter_app/lib/core/services/offline_store.dart`
- `flutter_app/lib/core/services/offline_sync_service.dart`
- `flutter_app/lib/core/services/stock_offline_sync.dart`
- `flutter_app/lib/core/providers/stock_offline_queue_provider.dart`
- `flutter_app/lib/features/barcode/presentation/warehouse_scan_action_sheet.dart`

Affected workflow: staff scans and queues stock verification offline, leaves scanner page, assumes it will sync later, but it remains pending until manual sync.

Recommended fix: make one durable write queue with typed handlers for purchases, stock verify, stock audit lines, staff cash purchases, and barcode assignments. Show a global sync badge and conflict queue.

### H4. Public Item QR Exposes Live Warehouse Stock Without Expiry Or Scope

Problem: `/public/items/{token}` returns item name, category, item code, barcode, current stock, stock status, rack location, and last update without auth.

Root cause: `backend/app/routers/public_items.py` uses a long opaque token but no expiry, revocation state, rate limit, or data-minimization mode.

Business impact: a leaked label photo can expose stock and rack intelligence to customers, competitors, or ex-staff. Reprinting labels does not rotate tokens.

Recommended fix: reduce public payload to item identity and maybe reorder contact details. Keep stock/rack behind authenticated scan. Add token rotation/revocation and rate limiting.

### H5. Legacy SaaS Tables And Rows Remain In Production Schema

Problem: after code cleanup, Supabase still contains SaaS-era tables and rows including `cloud_expenses`, `cloud_payment_history`, `whatsapp_report_schedules`, `billing_payments`, `business_subscriptions`, `assistant_sessions`, `assistant_decisions`, and related AI profile/log tables.

Root cause: code was removed but data cleanup/migration was not completed.

Business impact: future audits, backups, schema explorers, and reports can confuse current product scope. Old rows may contain stale vendor/payment/schedule data.

Recommended fix: create a migration plan to archive or drop unused SaaS tables after confirming no current backend imports use them. Export sensitive historical rows before deletion if needed.

### H6. Purchase PDF Export Shows User-Facing Failure Without Root-Cause Recovery

Problem: screenshots show `Preparing PDF...` followed by `Failed to export PDF` on purchase detail.

Root cause: the Flutter PDF action catches and returns a generic failure; the purchase detail page likely cannot distinguish font/layout/share/download failures. The UX gives no retry mode or fallback download path.

Affected files:

- `flutter_app/lib/core/services/pdf_actions.dart`
- `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`
- screenshot `Screenshot 2026-05-26 163004.png`
- screenshot `Screenshot 2026-05-26 163024.png`

Business impact: invoices and purchase records cannot be shared or printed reliably during receiving/accounting work.

Recommended fix: log structured PDF failure category, add fallback "download raw PDF" and "share text summary", and add a golden PDF test for purchase detail with multi-line items and Indian currency.

## Medium Priority Issues

### M1. Notification Empty States Show Section Header Without Useful Message

Problem: notifications screen shows `EARLIER` with a blank page for the selected tab.

Root cause: the notification grouping UI renders a section label even when the filtered list is empty.

Affected files:

- `flutter_app/lib/features/notifications/presentation/notifications_page.dart`
- screenshots `Screenshot 2026-05-26 162232.png`, `Screenshot 2026-05-26 163055.png`

Recommended fix: render a clear empty state per filter: "No purchase alerts", "No stock alerts", with one relevant action.

### M2. Reorder Setup Skeleton Can Look Like A Stuck Page

Problem: `Set reorder levels` screenshot shows only pale skeleton rows, no loading label, retry, or progress context.

Affected files:

- `flutter_app/lib/features/catalog/presentation/catalog_setup_reorder_levels_page.dart`
- screenshot `Screenshot 2026-05-26 162422.png`

Recommended fix: add title context, a short loading message, timeout/error state, and keep prior rows visible during refresh.

### M3. Staff Cash Purchase Logs Are Useful But Not Financially Reconciled

Problem: `staff_purchase_logs` adds stock and stores amount/supplier text, but it does not create a supplier payable, receipt, approval item, or cash reconciliation entry.

Affected files:

- `backend/app/routers/stock.py`
- `backend/app/models/staff_purchase_log.py`
- `flutter_app/lib/features/staff/presentation/staff_quick_purchase_page.dart`
- `flutter_app/lib/features/stock/presentation/staff_purchase_logs_page.dart`
- screenshot `Screenshot 2026-05-26 164338.png`

Business impact: stock increases without a matching accounting/audit workflow for petty cash.

Recommended fix: route cash purchases to an owner approval ledger with optional supplier match, attachment, and daily cash close.

### M4. Stock Update Modal Allows Ambiguous Absolute Updates

Problem: the quick stock sheet defaults to physical count and absolute new quantity, while reason chips include sale/damage/correction. Staff may think they are entering a delta.

Affected files:

- `flutter_app/lib/features/stock/presentation/stock_compact_update_sheet.dart`
- `flutter_app/lib/features/stock/presentation/update_stock_sheet.dart`
- screenshots `Screenshot 2026-05-26 164021.png`, `Screenshot 2026-05-26 164030.png`

Business impact: entering `2` for "damage" can set stock to 2 instead of subtracting 2.

Recommended fix: separate "Set counted stock" and "Adjust by delta" modes with distinct labels and previews: before, delta, after.

### M5. Owner User Profile Metrics Are Too Shallow For Audit

Problem: user profile shows zeros and generic totals but not last action, risky action, device, source, before/after, or approval state.

Affected files:

- `flutter_app/lib/features/settings/presentation/user_profile_page.dart`
- `backend/app/routers/users.py`
- screenshot `Screenshot 2026-05-26 163152.png`

Recommended fix: owner profile should surface high-risk actions, stock edits, approvals, sign-in sessions, and last device activity.

## UX Problems

- Stock low page on desktop shows many pink cards with repeated "Reorder level" and "Notify owner" buttons. The workflow is visually noisy and not table-efficient for 534 items.
- Owner home has many quick action bubbles and cards; mobile is usable but hierarchy competes between opening stock, KPIs, suppliers, scan, stock, add item, purchase, reports, barcode, users.
- Reports donut is readable but crowded in the center and mixes rupees, bag counts, box counts, and kg counts in small red/blue text.
- Bulk print desktop layout is strong, but row columns are very narrow; selected state, preview state, and print/download actions compete in the bottom bar.
- Label PDF output is dense and practical, but the header overlaps or compresses around "SL 51" and "100 of 100"; long item names can crowd the barcode area.
- Empty pages such as Staff cash purchases and Notifications use too much blank space and no primary action.
- Mobile purchase history works, but pending/delivered badges are small; staff receiving needs a clearer "receive now" CTA per pending order.
- Daily checklist has only checkboxes and percentages; it does not explain impact or deep-link to usage/stock verification tasks.

## Business Logic Problems

- Purchase creation and stock mutation are correctly separated by delivery state, but derived stock analytics do not consistently follow that invariant.
- Staff cash purchase increases stock immediately without an approval/finance ledger, which is operationally convenient but weak for cash control.
- Opening stock can override current stock and lock the value, but override governance is only owner/admin plus logs; there is no two-step confirmation for large catalog-wide setup mistakes.
- Public QR exposes live stock and rack, which may conflict with business privacy expectations for shelf labels.
- `stock_status()` treats `cur <= 0` as out regardless of reorder level, but unknown opening-stock rows with zero are also operational setup items. "Out" and "setup missing" should be separate states.
- Low-stock notifications are generated hourly in backend lifespan but there is no visible owner preference page for thresholds, quiet hours, or alert dedupe policy.

## Stock Engine Problems

- Stock writes are not atomic under concurrency.
- Ledger variance includes pending/deleted purchases.
- Physical count records do not mutate stock, while verify-count does. This is technically good, but UI labels must make this distinction extremely clear.
- Undo reverts the user's latest stock adjustment but does not verify the current stock still equals that adjustment's `new_qty`; it can undo on top of someone else's later change.
- Staff cash purchase and direct patch paths duplicate stock mutation logic instead of using one service.
- Purchase delivery revoke can fail if stock went below the purchase quantity; this protects negative stock but leaves the purchase in an awkward business state requiring manual reconciliation.

## Warehouse Workflow Problems

- Staff still has multiple entry paths: scan action sheet, stock row update, quick cash purchase, receive shipment, daily checklist, and purchase history. These should collapse into a single "Work queue" flow.
- Low-stock page exposes 534 items, which is too large for daily action. It needs priority grouping by category, supplier, stockout risk, and recent movement.
- Opening stock setup lists 534 items one-by-one. There is no bulk import, category batch, or "set all zero reviewed" operation.
- Owner audit is spread across user profile, stock changes, stock history, activity, notifications, and reports; there is no single warehouse activity timeline.
- Staff cash purchase has no receipt photo, approval, petty cash account, or daily close state.
- Checklist items are static and not connected enough to task completion. "Closing stock verification" should open the scanner/count workflow.

## Barcode Problems

- Scanner debounce is code/time based, but not operation-id based. A slow lookup can still cause repeated action sheets if different camera detections happen around the same item.
- Manual barcode assignment depends on the already-loaded catalog provider. If the catalog is empty/stale, user gets "Load catalog first" instead of an inline search API.
- Barcode scan queues stock verification offline, but replay is manual from the scanner page.
- Public QR token is long but permanent and no-auth.
- Barcode lookup supports code128 and QR only; EAN/UPC retail packs may be missed unless scanner formats are expanded.

## Printing Problems

- Purchase PDF export failed in real screenshot with no actionable recovery.
- Bulk PDF caps at 100 labels but the visible selection can be 534 items; users need clearer "100 selected for this PDF, 434 remaining" workflow and batch pagination.
- Thermal printing is still browser/OS print-dialog dependent. There is no printer profile, paper calibration, or one-click saved layout for real warehouses.
- Label PDF is dense and prints useful data, but long names/barcodes can collide in small cells.
- Web download/share/print paths differ by platform and need device QA on Android, Chrome desktop, and common thermal printer drivers.

## Desktop UX Problems

- Desktop stock/bulk print tables use only part of the available width for high-value operational columns.
- Left NavigationRail is helpful, but several owner workflows still open full-screen mobile-style pages instead of desktop split panes.
- Bulk print has a good preview pane; stock list should copy this pattern with a right-side item detail/update panel.
- Reports desktop screenshots still look mobile-stretched in places. Desktop needs fixed columns, keyboard shortcuts, and export actions aligned in the header.
- Settings and user management can use a two-pane layout: users list left, profile/audit detail right.

## Mobile UX Problems

- Mobile stock update bottom sheets are functional but dense; reason chips and quantity input need larger thumb targets and clearer absolute-vs-delta mode.
- Home has many round quick actions; staff and owner should see role-specific top 3 actions with secondary actions collapsed.
- Reports page has small text in charts and crowded category rows.
- Purchase detail bottom action bar has four equal buttons; "Edit", "Share", "Print", "PDF" are not equally frequent. Primary should be "Receive/Mark Pending" or "Share PDF" depending status.
- Notifications/search/filter icons are small in the top-right and hard to understand without labels.

## Staff Workflow Improvements

- Build a staff dashboard around "Scan item", "Receive pending purchase", "Count stock", "Log cash buy", and "My queue".
- Make barcode-first the default. From scanner result, show one sheet with current stock, expected pending delivery, last update, and three buttons: Count, Receive, Cash Buy.
- Replace multi-page low stock with a prioritized "Today's warehouse tasks" list.
- Add offline queue status globally, not only in scanner.
- Add numeric keypad shortcuts: +1, +5, +10, set counted, subtract damage.
- Require reason only when stock changes; prefill reason from action context.
- Add draft recovery for cash purchase and photo receipt.

## Owner/Admin Workflow Improvements

- Add one owner "Audit Center" with stock changes, staff actions, pending approvals, cash purchases, delivery changes, and risky mismatches.
- Add role permission matrix UI backed by API tests: stock edit, receive delivery, payment edit, catalog edit, barcode edit, reports view, users manage.
- Add owner approval for staff cash purchases over a threshold.
- Add weekly stock risk summary: top mismatches, long-pending deliveries, stale stock, missing barcodes, opening stock missing.
- Add user profile audit timeline with before/after values and source device.

## Recommended Architecture Improvements

- Create one backend `StockMutationService` for all stock mutations. Every path should call it with mutation type, expected version, source workflow, actor, reason, and optional linked document id.
- Add a normalized stock ledger table with signed deltas and absolute counts. `CatalogItem.current_stock` should be a cached projection updated transactionally.
- Replace client-only role assumptions with backend permission dependencies on every mutating endpoint.
- Move stock list filtering/sorting/pagination into SQL and add batch maps for supplier/meta data.
- Build one offline write queue with idempotency keys and handlers for all write types.
- Add a backend idempotency key to purchase creation, delivery confirm, stock verify, barcode assignment, and staff cash purchase.
- Move large widgets into smaller view models/selectors to reduce rebuild surfaces in `stock_page.dart`, `purchase_entry_wizard_v2.dart`, and `purchase_home_page.dart`.

## Performance Improvements

- Use database pagination for stock list and low-stock pages.
- Replace per-row `_supplier_name()` queries with one batched supplier lookup.
- Add missing indexes from Supabase performance advisor, especially `daily_usage_logs.item_id`, `reorder_list.item_id`, `staff_activity_log.item_id`, `stock_physical_counts.item_id`, `staff_purchase_logs.created_by`, and catalog created/updated user FKs.
- Add trigram or full-text search for catalog item name/item code/barcode.
- Cache report/dashboard aggregates with invalidation from stock/purchase writes.
- Limit PDF generation rows by device memory and split batches with explicit progress.
- Add server-side export endpoints for large PDF/report exports instead of building all bytes in Flutter.

## Security Improvements

- Add backend permission dependencies to every mutating catalog/contact/purchase/payment/delivery endpoint.
- Decide and document FastAPI-only versus Supabase-direct security. If Supabase-direct is possible, implement tenant RLS policies.
- Keep service-role keys server-only and verify no Flutter/web env leaks.
- Reduce public QR payload and add revocation/rotation.
- Add audit events for payment, delivery, stock, catalog, barcode, and permission changes.
- Add rate limits for auth, scan upload, public QR, and barcode lookup.
- Remove or archive legacy SaaS tables with sensitive historical data after backup.

## API Improvements

- Standardize error payloads with codes for duplicate purchase, negative stock, stale stock version, permission denied, PDF/export failure, and validation failures.
- Add idempotency keys for mutating endpoints.
- Add optimistic concurrency fields to stock detail/list responses.
- Split purchase ordered vs received state in APIs.
- Add server-side `stock/list` filters for supplier, missing barcode, missing code, reorder, unit, and purchased-in-period.
- Add cursor pagination for audit feeds, user activity, notifications, and purchase history.
- Add a dedicated endpoint for owner audit center.

## Database Improvements

- Add stock ledger/projection model.
- Add row version or `updated_at` concurrency checks to `catalog_items`.
- Add indexes for stock list filters, stock adjustment lookups, physical count item/time, staff activity item/user/time, and daily usage item/date.
- Add explicit constraints for unit fields where possible: `stock_unit`, `default_unit`, `unit_type`, package profile fields.
- Add separate fields for `ordered_qty`, `received_qty`, and `counted_qty` semantics in analytics views.
- Archive/drop dead SaaS tables after data review.
- Add RLS policies or document deny-by-default depending on final security model.

## Missing Features

- Global offline queue and conflict resolution.
- Warehouse audit center.
- Approval workflow for staff cash buys and large stock corrections.
- Multi-warehouse/location/bin support.
- Damage/expiry tracking with reason-specific reports.
- Supplier reorder recommendations by lead time and recent usage.
- Saved filters and quick filter presets for stock.
- Bulk opening stock import/update.
- Printer profile management for label sizes and thermal printers.
- Owner notification preferences and alert thresholds.
- Staff task queue tied to daily checklist.
- Inventory valuation report using backend-authoritative landing rates.

## Production Readiness Checklist

- Add concurrent stock mutation tests.
- Fix delivered/deleted semantics in stock variance and period purchase maps.
- Tighten backend permissions for payment, delivery, catalog, contacts, barcode, and reports.
- Decide Supabase RLS security model and clear advisors.
- Move stock list pagination/sorting/filtering to SQL.
- Batch supplier/meta lookups in stock APIs.
- Unify offline write queue and automatic replay.
- Fix purchase PDF export failure and add PDF golden tests.
- Add Android camera, barcode, PDF, print, offline, keyboard, and sign-out manual QA.
- Archive or remove dead SaaS schema and rows after backup.

## Final Refactor Plan

### Phase 1 - Stop Data Corruption And Permission Drift

- Implement transaction-safe stock mutation service with row locks or atomic updates.
- Fix `_period_purchased_map()` to exclude deleted and separate ordered from received.
- Add backend permission checks to purchase payment/delivery and catalog/contact mutations.
- Add regression tests for pending/delivered/cancelled/deleted purchase stock analytics.

### Phase 2 - Make Stock Page Scalable

- Rewrite `/stock/list` to use SQL pagination, sorting, and filters.
- Batch supplier, pending order, physical count, and trade meta maps.
- Add DB indexes from advisor plus search indexes.
- Redesign desktop stock as a split-pane dense table and mobile stock as compact action rows.

### Phase 3 - Harden Warehouse Operations

- Merge offline queues and add conflict resolution.
- Add owner audit center and cash purchase approvals.
- Add idempotency keys to delivery, stock update, staff cash purchase, and purchase creation.
- Build global sync status and retry UI.

### Phase 4 - Reporting, Printing, And Enterprise UX

- Fix purchase PDF export and add server-side export option.
- Add printer profiles and batch label continuation.
- Add saved filters, keyboard shortcuts, and owner risk dashboards.
- Add RLS policies or formal FastAPI-only security documentation.

## Exact Next Steps Priority Order

1. Fix stock concurrency by centralizing mutations and adding row locking/atomic updates.
2. Fix stock ledger expected quantity to use received purchases and exclude deleted purchases.
3. Tighten backend permissions for purchase payment/delivery and catalog/contact writes.
4. Rewrite stock list query path to true SQL pagination with batched supplier/meta lookups.
5. Unify offline queue replay for purchase and stock writes.
6. Fix purchase PDF export failure and add device PDF QA.
7. Reduce public QR data exposure and add token rotation/revocation.
8. Add owner audit center for staff actions, stock changes, delivery toggles, and cash buys.
9. Clean up legacy SaaS tables and Supabase RLS advisor findings.
10. Redesign stock page for dense mobile rows and desktop split-pane operations.

---

# HEXA Purchase Assistant - Full SaaS Product Analysis & Redesign Report

App: Harisree Agency Purchase Assistant

Stack: Flutter with Riverpod and GoRouter, FastAPI, SQLAlchemy async ORM, Supabase PostgreSQL, Vercel-hosted Flutter web, Render-hosted API, and a React/Vite admin surface in the repository.

Analysis date: 2026-05-26

Production score at analysis: 68/100 evidence-backed launch readiness. A product/UX-only score can reasonably read closer to 72/100, but the lower number is the safer enterprise-launch score because stock concurrency, permission hardening, RLS posture, and offline replay are production risks.

Prepared for: HexaStack Solutions / Harisree Agency deployment.

## Table Of Contents

- App Structure Analysis
- UI/UX Audit - Every Major Page And Flow
- Workflow Analysis
- Security And Data Integrity Audit
- Performance Audit
- Code Quality Audit
- Top 20 Highest Impact Features
- Missing Pages
- Navigation Redesign
- Enterprise-Level Improvements
- Feature Roadmap
- Production Readiness Scoring
- Kerala Market GTM Summary

## Section 1 - App Structure Analysis

### What This App Is

HEXA Purchase Assistant is a warehouse operations ERP for Kerala wholesale and distribution businesses. The current real deployment is Harisree Agency, a grain/spice wholesale workflow with heavy use of purchase entry, stock tracking, supplier/broker records, barcode labels, staff operations, reports, and owner audit views.

The product handles:

- Purchase entry with manual wizard and OpenAI Vision bill scanning.
- Delivery-confirmed stock updates.
- Barcode scanning, barcode assignment, public QR labels, and bulk PDF labels.
- Stock list, low-stock, reorder, physical count, opening stock, and staff cash purchase flows.
- Reports with BI ring charts, category/subcategory/item drilldowns, period comparisons, movement views, and a first-pass sales comparison page.
- Owner/staff route separation, user management, activity logs, and settings/help/backup surfaces.

### Architecture Overview

```text
Flutter app (mobile + web)
  Riverpod providers
  GoRouter owner/staff shells
  Dio HTTP client
  Hive local cache and offline queues
  PDF generation, share, download, and barcode scan UI

FastAPI backend
  SQLAlchemy async ORM
  Alembic migrations, current head 036_staff_purchase_logs
  23 router modules under backend/app/routers
  OpenAI Vision bill scan pipeline through scanner_v2 and scanner_v3 endpoints
  APScheduler jobs for due-soon tick and DB keepalive, plus low-stock background scan

Supabase PostgreSQL
  Public schema with RLS enabled broadly
  Current live data includes 2,773 catalog items, 3,988 suppliers, 62 purchases, and 113 purchase lines
  Advisors currently report RLS enabled without policies across most public tables

Admin / operations
  React/Vite admin web exists in repo
  API health/ready routes exist
  Render + Vercel deployment posture documented in Harisree docs
```

### What Is Good

Flutter architecture:

- Feature folders under `flutter_app/lib/features` give the app room to scale by domain.
- GoRouter shell routing cleanly separates owner shell and staff shell at a high level.
- Riverpod providers are centralized for stock, reports, home dashboard, purchase list, notifications, and session state.
- Shared design-system primitives exist: `HexaDsType`, `HexaOp`, `FriendlyLoadError`, `HexaErrorCard`, and app-level error helpers.
- Purchase entry uses a wizard and review-before-save pattern, which is the right structure for financial/stock data.
- Offline primitives exist through Hive: cached dashboard data, purchase wizard drafts, queued trade purchase writes, and queued stock verify actions.
- Barcode and PDF flows are advanced for this stage: scanner, bulk labels, PDF actions, web download, and mobile share/print support are already present.

Backend architecture:

- Routers are domain-separated: stock, purchases, catalog, contacts, reports, operations, users, notifications, exports, health, scanner routes under `me`, and public item QR.
- Models and schemas are separate, with SQLAlchemy models in `backend/app/models` and Pydantic schemas in `backend/app/schemas`.
- Purchase stock mutation invariant is mostly correct on the main path: purchase creation does not increment stock; delivery confirmation increments stock; delivery revoke/cancel/delete attempts to revert.
- `stock_tracking_profile.py`, `unit_normalization.py`, and purchase line validation encode Kerala warehouse unit semantics better than a generic inventory app.
- `staff_view.py` redacts financial rates for staff in some stock intelligence paths.
- `db_resilience.py`, Sentry initialization, request IDs, and health routes show production thinking.

Business logic:

- Delivery-confirmed stock mutation is a strong core invariant.
- Physical count can record a count without mutating stock, while verify-count can apply a counted value when intended.
- Staff cash purchase flow exists for warehouse reality, even though it needs accounting/approval hardening.
- Reorder list, opening stock, missing barcode, missing code, daily usage, checklist, stock audits, and notifications are already represented in code.

### What Is Poorly Structured

Critical structure issues:

- Stock mutation logic is scattered. `stock_inventory.py`, `stock.py`, `stock_audit_service.py`, operations usage, staff cash purchase, opening stock, undo, and purchase delivery each mutate or reason about stock differently. This is the top architecture risk.
- Backend permissions are inconsistent. Some high-risk endpoints use explicit permissions, while payment patching, delivery patching, scanner confirm, many catalog/contact mutations, and several report endpoints are membership-only.
- Owner/staff routing exists, but manager/admin behavior is not fully productized in Flutter. The backend permissions know about roles beyond staff/owner, but the app shell logic is primarily owner versus staff.
- Scanner v2 and scanner v3 coexist in `backend/app/routers/me.py`. This is not automatically bad because v2 and v3 serve different endpoint contracts, but the migration boundary needs explicit documentation to avoid editing the wrong pipeline.
- Legacy/duplicate UI wrappers exist. For example, `features/analytics/presentation/full_reports_page.dart` exports the reports page, and `features/purchase/presentation/scan_purchase_page.dart` wraps the v2 scan page. These should be documented as compatibility shims or removed after route verification.
- `reports_page.dart` remains too large for safe long-term maintenance. It owns too much report orchestration, tabs, exports, and UI state.
- Several global providers are reused across surfaces where scoped state is safer: stock list, stock operational filters, and bulk barcode printing can leak query/filter state across flows.

Scalability concerns:

- `backend/app/routers/stock.py` loads and filters all matching catalog rows in Python before slicing pages.
- `_supplier_name()` creates per-row supplier lookups on stock list rows.
- `backend/app/routers/dashboard.py` uses `_dashboard_month_cache`, an in-process dictionary that disappears on deploy/restart and will not work across multiple API instances.
- There is no durable job queue. APScheduler inside the API process is acceptable for early single-client use, but it is not a reliable enterprise background job layer.
- Supabase RLS is enabled without policies across most public tables. If the product ever introduces direct Supabase client reads/writes, the current posture must change before launch.

Technical debt summary:

- Duplicate or compatibility files: medium. Some wrappers are harmless, but the production path must be documented.
- Stock mutation architecture: high.
- Permission model enforcement: high.
- In-process cache/background jobs: medium.
- Reports and purchase wizard file size: medium/high.
- Manager/admin product role support: medium.
- Dead SaaS schema leftovers: high for security/audit clarity, medium for runtime.

## Section 2 - UI/UX Audit - Every Major Page And Flow

### Splash / Get Started / Login

Current problems:

- Render/API cold starts or network failures can create a perceived indefinite wait unless splash surfaces a timed recovery state.
- Login should speak the user's language: "Phone number or username" is clearer than "identifier".
- Returning staff open the app many times per day; password-only repeat login is slow.
- Offline/degraded API state should be visible immediately after auth restore.

Recommended improvements:

- Add an 8-10 second splash timeout with "Check connection" and Retry.
- Add value bullets on the get-started screen: purchases, live stock, barcode scan.
- Add biometric quick login after first successful login.
- Add offline/degraded banner in the shell when Dio marks the API/database degraded.

New features:

- Biometric login on `flutter_app/lib/features/auth/presentation/login_page.dart`.
- Network timeout and cached-session recovery on splash.
- First-run onboarding if catalog is empty.

### Owner Home (`/home`)

Current problems:

- Home is useful but dense. Screenshots show many cards, quick actions, a health sheet, opening stock warning, period chips, and KPI cards competing for attention.
- Owner's first morning questions are not pinned together: today's spend, pending deliveries, and low-stock/out-of-stock count.
- Quick actions include role terms like Users, which should read Staff for warehouse owners.
- Home dashboard data invalidation touches many providers; several provider paths can reload on tab switches or manual invalidation.
- Desktop/tablet width is underused. Owner home should become a control center, not a stretched phone page.

Recommended improvements:

- Add a pinned 3-KPI strip: Today Spend, Pending Delivery, Low/Out Stock.
- Rename Users to Staff in owner-facing quick actions.
- Make Warehouse Health actionable: each row deep-links to low stock, pending delivery, missing labels, or stock mismatch.
- Use a two-column desktop layout: left for daily control, right for activity/alerts/reports.
- Keep home providers warm for 60 seconds with `ref.keepAlive()` where safe.

New features:

- Daily digest card: yesterday spend, received deliveries, stock changes, pending actions.
- Staff activity today count with drilldown to user activity.
- Reorder-now quick card from low-stock summary.

### Stock (`/stock`)

Current problems:

- The app has 500+ item workflows, but stock list still behaves like a paged flat list with several client-side filters.
- Client-side supplier/missing barcode/reorder/unit filters over paged data can hide matching rows on later pages.
- Desktop stock table should use split-pane master/detail. Current dense rows are heading in the right direction but still squeeze high-value columns.
- Absolute stock update versus delta adjustment is not clear enough. A staff member can enter "2" for a damage action and accidentally set stock to 2 instead of subtracting 2.
- Opening stock setup for 534 items is too repetitive without category progress, bulk review, import, or mark-zero-reviewed.

Recommended improvements:

- Move stock operational filters into API query parameters.
- Add server-side search over name, item code, and barcode.
- Add a desktop right-side detail/update panel.
- Separate "Set counted stock" from "Adjust by delta" with explicit before/delta/after preview.
- Add category-group mode and saved filters.

New features:

- Add to reorder from a stock row.
- Physical count campaign/session.
- Stock snapshot export PDF/CSV.
- Bulk opening stock import and category review.

### Purchase Home (`/purchase`)

Current problems:

- Date-range handling has a real bug: `tradePurchasesListProvider` sends `purchase_to = toDate.add(Duration(days: 1))` while the backend treats `purchase_to` as inclusive. This can show an extra day.
- Payment/delivery actions exist but backend authorization is too broad.
- Pending delivery should be a first-class filter and action path.
- Purchase cards need a clear hierarchy: supplier, purchase ID, item summary, amount, payment state, delivery state.
- PDF export failure is visible in screenshots as a raw failure snackbar.

Recommended improvements:

- Fix the inclusive date contract for purchase list queries.
- Add payment due summary strip: overdue, due today, due this week.
- Add a dedicated pending-delivery filter.
- Make purchase ID visible in the list.
- Add robust PDF failure recovery: retry, download, share text summary.

New features:

- Bulk select and mark paid.
- Create purchase from reorder list.
- Better duplicate warning before save.

### Purchase Entry Wizard (`/purchase/new`)

Current problems:

- `purchase_entry_wizard_v2.dart` orchestrates too much state, async prefetch, focus, draft, supplier/broker, item entry, save, scan merge, and retry behavior.
- Supplier/item suggestion overlays remain a high-risk mobile keyboard surface.
- The wizard does heavy prefetch after first paint; this is useful but can compete with slow Render/mobile networks.
- Scan bill should be a primary entry choice, not a secondary path hidden in the flow.

Recommended improvements:

- Present first choice: Scan Bill or Manual Entry.
- Keep terms in an advanced/collapsible section where supplier defaults can prefill it.
- Add a sticky running total: item count and total amount.
- Show "Draft auto-saved" visibly.
- Split orchestration further into controllers/view models and step widgets.

New features:

- Smart default rates from last supplier/item line.
- Post-save stock impact card showing which items changed stock and which did not because delivery is pending.
- Local OCR fallback only if product requirements justify the added package and device footprint.

### Reports (`/reports`)

Current problems:

- `flutter_app/lib/features/reports/presentation/reports_page.dart` is too large and owns too many responsibilities.
- Reports use several parallel provider paths, which increases mismatch risk.
- Tabs are numerous for mobile and rely on horizontal discovery.
- Sales comparison is a first pass with pasted rows, not full PDF/XLSX import.
- PDF/share actions are not consistently surfaced in every tab and PDF generation can fail.

Recommended improvements:

- Split reports into tab files and route-aware tab state.
- Use one range-scoped report bundle provider where practical.
- Collapse mobile tabs to Overview, Categories, Items, Suppliers, Movement, More.
- Add one-tap PDF/share per tab with graceful fallback.
- Promote Sales Comparison upload as a Phase 2 feature.

New features:

- Tally XLSX upload for sales comparison.
- Supplier aging report.
- Year-over-year and period-over-period summary.
- Stock Health report combining slow, dead, low, out, stale, and missing labels.

### Notifications (`/notifications`)

Current problems:

- Empty states can show headers without useful content.
- Badge/source merging needs simplification around server unread count versus local stock alert concepts.
- Notification preferences are shown as future or partially available in the UI.
- Tapping raw `actionRoute` with `context.push` can create shell navigation mismatches.

Recommended improvements:

- Use server unread count as the authoritative badge.
- Route notification taps through a shell-aware navigation helper.
- Hide empty section headers and show per-tab empty states.
- Add mark-all-read and preference management in a dedicated notifications settings page.

New features:

- Snooze notification.
- Alert threshold preferences.
- Real-time or short-poll badge update, depending on final Supabase/FastAPI security model.

### Settings (`/settings`)

Current problems:

- Settings mixes account, branding, quick actions, notifications, business operations, backup/help, and hidden admin access in a long scroll.
- Backup/auto-backup expectations are not fully implemented.
- Branding upload lacks strong PDF preview context.
- Sign out all devices and session revocation are missing or not surfaced as a first-class owner action.

Recommended improvements:

- Split Settings into subpages: Profile, Business/Branding, Notifications, Backup, Staff/Users, About.
- Show backup last-run/manual export status.
- Add PDF header preview for logo/title.
- Add sign out all devices backed by server session revocation.

### Staff Home (`/staff/home`)

Current problems:

- Staff action paths exist but are split across scan, stock, quick purchase, pending deliveries, activity, checklist, and history.
- Staff should not see financial stock value or report-level financial context.
- Pending delivery card must be permission-aware.
- The primary staff action should be one-tap scan from anywhere.

Recommended improvements:

- Make center scan FAB launch camera directly.
- Add "My Tasks Today": receive, count, low/out stock, cash buy approval pending.
- Hide delivery actions if permission is absent.
- Keep count-only metrics on staff home.

### Barcode Scan And Print

Current problems:

- Scanner formats are currently restricted to Code128 and QR, missing EAN/UPC/ITF/Code39 style real product labels.
- Scanner lifecycle can keep camera active under sheets/routes.
- Printed Code128 payload can be truncated/stripped by Flutter while backend stores a longer/different barcode.
- Bulk search hints mention barcode, but stock backend search does not search barcode.
- Public item QR exposes live stock/rack/update data without auth.
- Bulk PDF cancellation is not truly cancellable mid-generation.

Recommended improvements:

- Add common barcode symbologies.
- Pause scanner during lookup and while modal/route is active.
- Enforce printable barcode constraints server-side or use QR for long/non-ASCII payloads.
- Add barcode to backend stock search.
- Rename "Thermal" to "Thermal-size PDF" unless direct printer protocols are implemented.
- Minimize public QR payload and add rotation/revocation/no-store/noindex.

### Contacts / Suppliers / Brokers

Current problems:

- Contact and catalog mutations are too broadly membership-authorized in the backend.
- Supplier detail needs outstanding amount and payment aging more prominently.
- WhatsApp is a real Kerala workflow but not first-class enough in supplier actions.
- Broker commission visibility should be clearer.

Recommended improvements:

- Add WhatsApp deep link to supplier/broker phone fields.
- Add supplier aging summary and payment statement PDF.
- Add broker commission month-to-date card.
- Harden supplier/broker create/update/delete permissions.

## Section 3 - Workflow Analysis

### Workflow 1: Owner Morning Routine

Current state:

1. Open app and land on Home.
2. Inspect opening stock, low stock, pending delivery, and purchase metrics in separate cards/sheets.
3. Tap Stock or Purchase to act.
4. Manually go to supplier/contact or purchase entry.

Friction points:

- Owner's top actions are not summarized in one fixed strip.
- Low-stock and reorder workflow is split across stock, reorder list, contacts, and purchase wizard.
- Pending delivery needs a clearer receive/verify pipeline.

Redesigned workflow:

1. Home shows pinned KPI strip: Today Spend, Pending Delivery, Low/Out Stock.
2. Tap Low/Out Stock to open prioritized reorder list.
3. Tap item to contact last supplier, WhatsApp supplier, or create purchase draft from reorder.
4. Staff receives delivery; owner sees stock and activity update.

### Workflow 2: Staff Stock Verification

Current state:

1. Staff opens app.
2. Navigates to stock or scan.
3. Finds item by search/scan.
4. Opens update/count sheet.
5. Enters quantity and optional reason.

Friction points:

- Scan path and stock path are separate mental models.
- Offline queued stock verification is manual to replay.
- Absolute-versus-delta update semantics can cause mistakes.

Redesigned workflow:

1. Staff taps center Scan from anywhere.
2. Scan result sheet shows current stock, unit, last update, pending delivery, and last supplier.
3. Staff chooses Count Stock or Adjust Damage/Sale.
4. Count mode is absolute; Adjust mode is delta.
5. Save shows confirmed before/after and queued/synced state.

### Workflow 3: Purchase Entry With Bill Scan

Current state:

1. User opens purchase wizard or scan page.
2. Scan pipeline reads bill and produces draft, or manual wizard captures supplier/items/terms.
3. Review and save.
4. Delivery state later controls stock update.

Friction points:

- Scan Bill is not dominant enough.
- Supplier/broker server match can be lost if local matching nulls a server ID.
- Suggestion overlays and keyboard need strict QA.
- The user needs a clearer post-save stock impact summary.

Redesigned workflow:

1. User chooses Scan Bill or Manual Entry.
2. Scan bill returns supplier, broker, line items, confidence, and warnings.
3. Low-confidence fields are highlighted.
4. Review shows item receipt layout and stock impact: ordered now, received later.
5. Save creates pending delivery by default unless explicitly received.

### Workflow 4: Reorder To Purchase

Current state:

- Reorder list can be created from stock, but purchase creation remains manual.

Redesigned workflow:

1. Reorder page groups low/out items by supplier.
2. Owner selects items and taps Create Purchase.
3. Wizard opens with supplier and reorder items prefilled.
4. Owner edits rates/quantities and saves as pending delivery.

### Workflow 5: Month-End Reporting

Current state:

- User opens Reports, chooses range/tabs, and exports/shares if available.
- PDF/export reliability needs hardening.
- Sales comparison supports pasted rows, not Tally upload.

Redesigned workflow:

1. Reports remembers last period and can sync with Home period.
2. Each tab has Share PDF.
3. Supplier aging, stock health, category BI, and sales comparison are separate clear reports.
4. Tally XLSX upload compares sales movement to app stock/purchases.

## Section 4 - Security And Data Integrity Audit

### Critical: Stock Write Race Conditions

Risk level: critical.

Every stock mutation path must become transaction-safe. Current read-compute-write flows in `backend/app/services/stock_inventory.py`, `backend/app/routers/stock.py`, and `backend/app/services/stock_audit_service.py` can lose updates under concurrent staff activity.

Required fix pattern:

```python
# Directionally correct pattern, not final code.
UPDATE catalog_items
SET current_stock = current_stock + :delta,
    last_stock_updated_at = now()
WHERE id = :item_id
  AND business_id = :business_id
  AND current_stock + :delta >= 0
RETURNING current_stock;
```

For absolute physical counts, use row version checks or `SELECT ... FOR UPDATE` and record a ledger event.

### Critical: Purchase/Stock Semantics Drift

Risk level: critical.

Operational stock views must not count pending, draft, saved, cancelled, or deleted purchases as received stock. Current stock period maps in `backend/app/routers/stock.py` need a shared "stock-affecting purchase" filter.

Fix:

- Use delivered purchases for stock ledger expected quantity.
- Use separate ordered/pending quantity fields for procurement visibility.
- Exclude deleted/cancelled/draft/saved from received-stock rollups.

### Critical: Permission Enforcement Gaps

Risk level: high/critical.

Sensitive endpoints that currently use broad membership must require explicit permissions:

- Purchase payment patch and mark-paid.
- Purchase delivery confirm/revoke.
- Scanner purchase confirm.
- Catalog/category/item mutation.
- Supplier/broker mutation.
- Financial report endpoints.
- Cross-user activity queries.

Recommended permission keys:

- `purchase_create`
- `purchase_edit`
- `purchase_payment_edit`
- `purchase_delivery_receive`
- `stock_edit`
- `catalog_edit`
- `contacts_edit`
- `reports_access`
- `users_manage`

### Critical: Supabase RLS Posture

Risk level: high.

Supabase advisors show RLS enabled without policies across most public tables. The app may currently rely on FastAPI as the sole data gateway, but this must be explicit. If any client-side Supabase Data API access is planned, policies must be implemented first.

Safe choices:

- FastAPI-only: service key never leaves backend, direct Supabase data access is not used, RLS is deny-by-default and documented.
- Supabase-direct: add tenant policies using secure claims/app metadata and membership tables, then test anon/authenticated behavior.

### Business ID Isolation

Most audited endpoints include `business_id` filters, but this must remain a mandatory checklist for every ID-based endpoint. The safe pattern is:

```python
where(Model.id == resource_id, Model.business_id == business_id)
```

Add regression tests for cross-business item, supplier, purchase, stock, user activity, and barcode access.

### Soft Delete And Legacy Schema

The product uses `deleted_at` in key models. Every list/search/report must filter deleted rows consistently. Supabase still contains legacy SaaS tables/rows such as cloud expenses, WhatsApp schedules, billing/subscriptions, and AI assistant tables. These should be archived or removed after backup to avoid future audit confusion.

### Auth, Sessions, And Rate Limits

- Login, forgot-password, reset-password, refresh, scan/OCR, and public QR need explicit rate limiting.
- Refresh should re-check blocked/deleted/inactive users.
- User sessions should support sign out all devices and token revocation for sensitive businesses.
- Validation error responses should strip raw submitted inputs.

## Section 5 - Performance Audit

### Issue 1: Stock List Does Not Scale

`backend/app/routers/stock.py` fetches matching catalog rows, filters/sorts in Python, and then slices. This is the largest immediate backend performance risk.

Fix:

- Push filters and sorting into SQL.
- Use `LIMIT/OFFSET` or cursor pagination.
- Batch supplier names and related meta maps.
- Add search indexes for name, item code, barcode, category, type, stock status components, and last updated.

### Issue 2: In-Process Dashboard Cache

`_dashboard_month_cache` in `backend/app/routers/dashboard.py` is process memory. Render deploys/restarts clear it, and multi-instance deployments would diverge.

Fix:

- Use database/materialized aggregates or Redis when the product grows.
- For current single-client scale, a materialized summary table refreshed by explicit mutation invalidation is enough.

### Issue 3: Provider Reloads And Query State Leakage

Home, reports, stock, and bulk print share several provider surfaces. Some providers need keepAlive TTL; others need scoping by page/surface.

Fix:

- Add 60-second keepAlive to safe home/dashboard providers.
- Split stock query/filter providers by surface: owner stock, staff stock, bulk print, and drilldown context.
- Centralize report range providers.

### Issue 4: Reports Page Provider Waterfall

Reports have multiple overlapping provider paths. They should be consolidated around one range-scoped report bundle with selectors for tabs.

Fix:

- One API payload or one provider bundle per range.
- Derived providers for tabs.
- Avoid re-fetching unchanged base data on tab switch.

### Issue 5: PDF Generation And Export Reliability

PDF generation can block UI and screenshots show export failures.

Fix:

- Move heavy PDF generation to isolates where feasible.
- Add specific failure categories.
- Add fallback download/share flows.
- Add golden tests for purchase/report/label PDFs.

### Issue 6: India/Kerala Latency

Kerala to US/Oregon/US-East infra adds avoidable latency. The app already uses optimistic/cached UX in some places, but enterprise rollout should prefer closer regions.

Fix:

- Move Render API to Singapore or closest viable region when deployment constraints allow.
- Keep Supabase region strategy aligned for the primary market.
- Add stale-while-revalidate UI for stock/report/home reads.

## Section 6 - Code Quality Audit

### Issue 1: Stock Domain Needs One Service

All stock changes should flow through one backend service. It should record source workflow, actor, before/after, delta, linked purchase/cash/audit document, and idempotency key.

### Issue 2: Role Model Needs Product Alignment

Backend permissions include role templates beyond a simple owner/staff product. Flutter routing should explicitly support owner, manager/admin, and staff behaviors instead of relying on "not staff means owner shell" assumptions.

### Issue 3: Reports Page Is Too Large

Split `flutter_app/lib/features/reports/presentation/reports_page.dart` into:

- `reports_page.dart` for shell/orchestration.
- `reports_overview_tab.dart`.
- `reports_categories_tab.dart`.
- `reports_items_tab.dart`.
- `reports_suppliers_tab.dart`.
- `reports_movement_tab.dart`.
- `reports_sales_comparison_tab.dart`.
- `reports_stock_health_tab.dart`.

### Issue 4: Compatibility Wrappers Need Documentation

Files such as `scan_purchase_page.dart` and `full_reports_page.dart` may be route wrappers. Keep them only if routes depend on them, and add a comment naming the real implementation.

### Issue 5: CI Gates Are Needed

Manual reminders are not enough. Add CI for:

- `flutter analyze`.
- targeted Flutter tests.
- backend `pytest`.
- backend import check.
- migration head check.

### Issue 6: Error Handling Is Uneven

The app has good error widgets, but many mutation paths still use raw snackbars. Standardize all mutation failures through domain error helpers with user-facing copy.

## Section 7 - Top 20 Highest Impact Features

1. Transaction-safe stock mutation service. Highest data-integrity value; touches backend stock/purchase/audit paths.
2. Delivered-only stock ledger and expected quantity fix. Prevents false mismatches and wrong stock intelligence.
3. Backend permission hardening. Prevents staff/direct API misuse of payment, delivery, catalog, and reports.
4. SQL-backed stock list filters/search/pagination. Removes current scaling ceiling.
5. Unified offline queue with auto replay and conflict resolution. Critical for warehouse reliability.
6. Purchase PDF/export hardening. Fixes visible production failure in screenshots.
7. Public QR safety controls. Prevents inventory/rack exposure.
8. Pinned owner KPI strip. Makes Home a decision dashboard.
9. One-tap staff scan with action sheet. Reduces warehouse tap count.
10. Stock update absolute-vs-delta redesign. Prevents accidental stock overwrite.
11. WhatsApp supplier deep link. Matches Kerala business workflow.
12. Reorder-to-purchase draft. Connects low stock to procurement.
13. Manager/admin shell behavior. Aligns backend roles with product UX.
14. Tally XLSX sales comparison upload. High accounting value for wholesale customers.
15. Supplier payment aging ledger. Prevents payment misses and owner confusion.
16. Reports page split and report bundle provider. Reduces maintenance and data mismatch.
17. Barcode search parity. Makes "search barcode" actually work.
18. Scanner lifecycle and symbology expansion. Improves real scanner reliability.
19. Owner audit center. Makes staff/stock/payment changes accountable.
20. CI and monitoring baseline. Makes the app safer to iterate.

## Section 8 - Missing Pages

### Manager / Admin Operations Dashboard

Why needed: backend permissions support manager/admin-style workflows, but Flutter product routing is mostly owner versus staff.

Placement: shell branch or role-adaptive owner shell with restricted settings/user-management access.

Business impact: businesses can delegate purchase/stock/report work without giving full owner controls.

### Reorder To Purchase

Why needed: low-stock and reorder work should convert directly into a purchase draft.

Placement: `/stock/reorder`, with "Create purchase from selected".

Business impact: reduces duplicate item entry and speeds procurement.

### Supplier Payment Aging Ledger

Why needed: wholesale owners need supplier payable aging more than generic supplier details.

Placement: supplier detail page and reports supplier tab.

Business impact: prevents missed payments and improves supplier trust.

### Physical Count Campaign

Why needed: item-by-item counts are not enough for monthly or closing stock operations.

Placement: stock page AppBar and staff daily checklist.

Business impact: formal variance control and printable count report.

### Owner Audit Center

Why needed: audit data exists across stock adjustments, staff activity, notifications, users, and purchases, but no single owner view explains "who changed what".

Placement: Home quick action and Settings/Staff area.

Business impact: accountability without digging through separate pages.

### Business Onboarding Wizard

Why needed: new clients need guided setup for business profile, logo, categories, first items, suppliers, opening stock, and staff.

Placement: post-login redirect when workspace setup is incomplete.

Business impact: makes product repeatable beyond Harisree.

## Section 9 - Navigation Redesign

### Current Navigation Problems

- Owner mobile shell is broadly right, but Purchase is more daily than Reports and should be prioritized accordingly.
- Staff shell should always preserve staff chrome when opening scan, history, search, and stock actions.
- Some widgets use `context.push()` to shell roots, creating possible stack/tab mismatch.
- Desktop/tablet screens need NavigationRail plus split panes, not stretched mobile pages.

### Proposed Owner Mobile Shell

```text
Home | Stock | Scan FAB | Purchase | Reports
```

Rationale: Home is control center, Stock and Purchase are daily operations, Scan is the central warehouse action, Reports are periodic.

### Proposed Staff Mobile Shell

```text
Home | Stock | Scan FAB | History | Search
```

Rationale: staff need scan/count/receive/find/history, not owner reports.

### Proposed Desktop / Tablet Rail

```text
Top:
Home
Stock
Purchases
Reports
Search

Bottom:
Notifications
Settings
```

### Shell-Aware Navigation Rule

Add a navigation helper:

- Use `go` or shell branch navigation for shell roots.
- Use `push` for details, sheets, and subpages.
- Route notifications and home cards through this helper.

## Section 10 - Enterprise-Level Improvements

What makes the app feel less enterprise today:

- Some production states still show raw failures or blank pages.
- Owner audit visibility is spread across too many surfaces.
- Offline writes exist but are not one unified, automatic, trusted system.
- Reports and exports are not reliable enough for accounting handoff.
- Direct public QR pages reveal live operational details.
- Role permissions are stronger in concept than in endpoint enforcement.
- New-client onboarding is not productized.

What makes it production-grade:

- Data freshness indicators on every operational list/card.
- Unified offline queue with conflict review.
- Owner audit center with before/after and actor/source.
- Strong backend permission checks and tests.
- Durable stock ledger with transaction-safe projection.
- Professional PDF/export recovery.
- Real onboarding, workspace switcher, and business setup checklist.
- Monitoring, CI, and deployment health checks as required release gates.

## Section 11 - Feature Roadmap

### Phase 1 - Stabilize Enterprise Launch Readiness

Target: 1-2 weeks.

- Centralize stock mutations and add concurrency protection.
- Fix delivered-only stock analytics and deleted purchase filtering.
- Harden purchase payment/delivery/scanner/catalog/contact permissions.
- Fix purchase list date-range off-by-one.
- Add barcode search to backend stock search.
- Fix purchase PDF failure path.
- Add public QR safety limits.
- Add owner KPI strip and notification empty states.
- Add CI gates for Flutter analyze and backend tests.

### Phase 2 - Warehouse Workflow Speed

Target: 3-6 weeks.

- SQL-backed stock list filters and pagination.
- Staff scan-first workflow with unified result sheet.
- Reorder-to-purchase draft.
- Physical count campaign.
- Unified offline write queue.
- Supplier WhatsApp links and payment aging.
- Manager/admin role-aware shell behavior.
- Reports page split and report bundle provider.

### Phase 3 - Premium SaaS / AI Layer

Target: month 2-3.

- Scan Bill as the primary purchase entry mode.
- Tally XLSX/PDF sales comparison upload.
- Smart reorder suggestions using purchase/usage cadence.
- Price intelligence page using anonymized/internal historical pricing where legally and contractually safe.
- AI assistant for owner questions only after strict backend read permissions and audit logs are in place.
- Multi-business or multi-warehouse support with workspace switcher.
- Scheduled monthly report delivery after WhatsApp/API compliance review.

## Production Readiness Scoring

Current evidence-backed launch score: 68/100.

- Core purchase workflow: 82/100. Main delivery invariant is good; side paths need hardening.
- Stock management: 62/100. Useful features exist, but concurrency and ledger semantics block enterprise confidence.
- Reports and analytics: 70/100. Broad coverage, but large file/provider complexity and export issues remain.
- Security: 55/100. Auth exists; endpoint permissions and RLS posture need work.
- Performance: 58/100. Stock list and unbounded catalog/report patterns need SQL pagination and indexes.
- UX consistency: 72/100. Mobile-first screens are usable; stock density, empty states, and raw errors need improvement.
- Notifications: 60/100. Backend notifications exist; badge/realtime/preferences need product hardening.
- Code quality: 68/100. Good domain separation but several large files and duplicated state surfaces.
- Monitoring/release operations: 60/100. Health checks and Sentry hooks exist; CI and formal monitoring gates need completion.
- Multi-client readiness: 50/100. Strong single-client fit; onboarding, RLS/security model, workspace/role UX, and dead SaaS cleanup are needed.

Target after Phase 1 and Phase 2: 84-88/100, assuming stock concurrency, permissions, SQL pagination, offline queue, and PDF/export reliability are fixed.

## Kerala Market GTM Summary

Current app positioning: Purchase Assistant is accurate but generic. For a Kerala warehouse product, the strongest positioning is not "generic SaaS"; it is a godown stock and purchase control app for wholesale owners.

Possible names:

- GodownApp: immediately understandable for warehouse/godown operators.
- StockMitra: friendly and broad, better for multi-region SaaS.
- Hexa Godown: keeps the Hexa brand while communicating the category.
- Purchase Assistant can remain the internal product name while customer-facing branding uses a clearer warehouse term.

Suggested packaging:

- Starter: owner plus up to 3 staff, purchase, stock, barcode, reports.
- Warehouse Pro: unlimited staff, audit center, PDF exports, supplier aging, offline queue.
- Setup service: one-time catalog import, barcode label setup, staff training, and opening stock campaign.

First-client expansion path:

- Use Harisree as the reference workflow and case study after manual QA.
- Target nearby grain/spice wholesalers with similar supplier, broker, and stock pain.
- Lead with barcode stock accuracy, purchase bill scan, low-stock/reorder, and supplier payment aging.
- Avoid promising AI chat or direct WhatsApp automation until security, permissions, and core stock reliability are enterprise-grade.

