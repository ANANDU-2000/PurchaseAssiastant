# LOW STOCK SYSTEM REBUILD

## Previous defects
- Header/filter clipping due to fixed pinned sliver height.
- Server filter chips could empty the list while summary still showed counts.
- Duplicate search + owner action card cluttered mobile UX.

## Current IA (2026-05-28)
- **Routes:** `/stock/low-stock` (owner), `/staff/low-stock` (staff) → `LowStockDashboardPage`.
- **Data:** `lowStockByCategoryProvider` (stock list, client grouped) — not `/low-stock/operations` filter chips.
- **Tabs:** All low · Pending order · Out · Purchased (period from Home) · Pending delivery.
- **Tree:** Category → subcategory → expandable items; each category/subcategory row shows **LOW** and **OUT** red badges.
- **Search:** One field + scope chips (All / Category / Subcategory / Item), 200ms debounce, client-side.
- **Item row:** BAG | TIN | BOX | KG columns; stock progress line; role actions (owner: order/reorder/update; staff: inform owner/reorder/update/receive).

## Deprecated
- `LowStockOperationsPage` — kept in repo, not routed.
- `LowStockOwnerPage` / `StaffLowStockPage` — thin wrappers to dashboard.

## Owner/Staff intent
- Owner: reorder + purchase from low-stock context.
- Staff: notify owner + physical stock update + receive pending deliveries.

## Related (same sprint)
- Staff home: tools first, low-stock attention tile → `/staff/low-stock`.
- Stock list columns: SYSTEM / PHYS / DIFF (no purchased column in table).
- Item detail: `ItemStockSnapshotCard` + `ItemDeliveryStatusCard` (no legacy hero grid).
