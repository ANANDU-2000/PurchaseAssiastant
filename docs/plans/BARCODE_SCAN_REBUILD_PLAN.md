# BARCODE SCAN REBUILD PLAN
**Priority:** CRITICAL — affects daily warehouse operations  
**Date:** 2026-06-01

---

## OBJECTIVE

1. After scan: show **Purchased Qty** + **Current Stock** as distinct prominent tiles
2. Scan detail in **read-only mode** (public QR, no login) must show same info
3. Barcode scan must work **without app** via standard phone camera → web browser
4. **Edit** in scan detail must be truly read-only for read-only users; edit only for privileged users

---

## PART 1 — Fix `ScanItemStockSummaryCard` (3-tile layout)

### File: `flutter_app/lib/features/barcode/presentation/widgets/scan_item_stock_summary_card.dart`

**Current:** 2-tile row (System Stock + Physical Count) + 1-line footer for last purchase  
**Target:** 3-tile row (Current Stock + Last Purchase + Physical Count)

**Tile definitions:**

| Tile | Label | Value | Color |
|------|-------|-------|-------|
| 1 | Current Stock | `current_stock + unit` | Green `#0E4F46` |
| 2 | Last Purchased | `last_purchase_qty + last_purchase_unit` + date below | Amber `#B45309` |
| 3 | Physical Count | `physical_stock_qty + unit` or "Not counted" | Blue `#2563EB` |

**Required API fields (verify backend returns these from `/v1/businesses/{id}/barcode/lookup`):**
- `current_stock` ✅ (exists)
- `physical_stock_qty` ✅ (exists)
- `last_purchase_qty` ✅ (exists but may be null)
- `last_purchase_unit` ✅ (exists)
- `last_purchase_date` ✅ (exists)
- `last_purchase_rate` ✅ (exists)
- `last_purchase_supplier` — verify: is `supplier_name` returned?

**Widget change:**
```dart
// Replace current Row(...) in ScanItemStockSummaryCard.build()
Row(
  children: [
    Expanded(
      child: _StockTile(
        label: 'Current Stock',
        qty: system,
        unit: unit,
        accent: const Color(0xFF0E4F46),
        subtitle: _lastUpdatedLine(item),
      ),
    ),
    const SizedBox(width: 6),
    Expanded(
      child: _PurchaseTile(  // NEW WIDGET
        qty: lpQty,
        unit: lpUnit,
        date: lpDate,
        rate: lpRate,
      ),
    ),
    const SizedBox(width: 6),
    Expanded(
      child: _StockTile(
        label: 'Physical Count',
        qty: physical,
        unit: unit,
        accent: const Color(0xFF2563EB),
        subtitle: physical != null
            ? [if (physAt != null) daysAgoLabel(physAt), if (physBy.isNotEmpty) physBy]
                .where((s) => s.isNotEmpty).join(' · ')
            : 'Not counted yet',
        emptyHint: '—',
      ),
    ),
  ],
),

// NEW: _PurchaseTile widget
class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({this.qty, required this.unit, this.date, this.rate});
  final double? qty;
  final String unit;
  final DateTime? date;
  final double? rate;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFB45309);
    final unitUp = unit.isNotEmpty ? unit.toUpperCase() : '';
    final value = qty != null && qty! > 0
        ? '${formatStockQtyNumber(qty!)}${unitUp.isNotEmpty ? ' $unitUp' : ''}'
        : 'None';
    final sub = [
      if (date != null) ScanItemStockSummaryCard.daysAgoLabel(date),
      if (rate != null && rate! > 0) '₹${rate!.toStringAsFixed(rate == rate!.roundToDouble() ? 0 : 2)}',
    ].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last Purchase',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accent, height: 1.1)),
          const SizedBox(height: 4),
          Text(sub.isNotEmpty ? sub : 'No purchases yet',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        ],
      ),
    );
  }
}
```

---

## PART 2 — Fix `PublicItemScanPage` (read-only, no login)

### File: `flutter_app/lib/features/barcode/presentation/public_item_scan_page.dart`

**Target layout:**
```
[AppBar: "Item Lookup — Harisree"]

[Hero section]
ITEM NAME (large, bold)
Category · Subcategory

[3-tile stock row — same as ScanItemStockSummaryCard]

[Details row]
Item Code: ABC-001    Rack: A-12
Barcode: 8901234567890

[Last purchase row]
Purchased: 5 BAG from Krishna Trading on 28 May (3 days ago) @ ₹120/bag

[Footer]
"Read-only view · Open Harisree app to update stock"
[Open App button — deep link]
```

**Code changes:**
```dart
// Replace entire body ListView with:
body: FutureBuilder<Map<String, dynamic>>(
  future: _load,
  builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) {
      return const _PublicLoadingSkeleton();  // NEW: shimmer skeleton
    }
    if (snap.hasError) { ... }
    final data = snap.data ?? const {};
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Hero: item name
        Text(data['name']?.toString() ?? 'Item',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        if (categoryLabel.isNotEmpty)
          Text(categoryLabel, style: HexaDsType.body(13, color: HexaDsColors.textMuted)),
        const SizedBox(height: 16),
        
        // Prominent current stock headline
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0E4F46).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF0E4F46).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CURRENT STOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0E4F46))),
                  const SizedBox(height: 4),
                  Text(
                    '${formatQtyForDisplay(coerceToDouble(data['current_stock']))} ${unit.toUpperCase()}',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0E4F46)),
                  ),
                ],
              )),
              // Status badge
              _StatusBadge(status: data['status']?.toString() ?? 'healthy'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        
        // 3-tile card
        ScanItemStockSummaryCard(item: data, showTitle: false),
        const SizedBox(height: 16),
        
        // Item meta
        _MetaRow('Item Code', data['item_code']?.toString() ?? '—'),
        _MetaRow('Barcode', data['barcode']?.toString() ?? '—'),
        _MetaRow('Rack', data['rack_location']?.toString() ?? '—'),
        const SizedBox(height: 24),
        
        // Footer
        const Text(
          'Read-only · Open the Harisree app to update stock.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
      ],
    );
  },
),
```

---

## PART 3 — Web scan without app login (new feature)

### Backend: New public endpoint

**File:** `backend/app/routers/public_items.py`

```python
# Add new route alongside existing /public/items/{token}.json
@router.get("/public/lookup")
async def public_barcode_lookup(
    barcode: str = Query(..., min_length=1, max_length=100),
    business: str = Query(..., description="Business slug or public ID"),
    db: AsyncSession = Depends(get_async_db),
):
    """
    Public unauthenticated barcode lookup.
    Rate-limited to 60/min per IP.
    Returns stock info without sensitive business data.
    """
    # Look up business by slug
    biz = await db.execute(
        select(Business).where(Business.public_slug == business, Business.deleted_at.is_(None))
    )
    biz = biz.scalar_one_or_none()
    if biz is None:
        raise HTTPException(404, "Business not found")
    
    # Look up item by barcode
    item = await db.execute(
        select(CatalogItem)
        .where(CatalogItem.business_id == biz.id, CatalogItem.barcode == barcode, CatalogItem.deleted_at.is_(None))
    )
    item = item.scalar_one_or_none()
    if item is None:
        raise HTTPException(404, "Item not found")
    
    return {
        "id": str(item.id),
        "name": item.name,
        "item_code": item.item_code,
        "barcode": item.barcode,
        "current_stock": float(item.current_stock or 0),
        "unit": item.default_unit or "",
        # ... other public fields, NO prices, NO supplier details
    }
```

### Flutter: Add web-accessible barcode scan page

**Route to add in `app_router.dart`:**
```dart
GoRoute(
  path: '/lookup',  // e.g. harisree.app/lookup?barcode=8901234&business=harisree
  pageBuilder: (context, state) => iosPushPage(
    key: state.pageKey,
    child: PublicBarcodeLookupPage(
      barcode: state.uri.queryParameters['barcode'] ?? '',
      businessSlug: state.uri.queryParameters['business'] ?? '',
    ),
  ),
),
```

**New page:** `public_barcode_lookup_page.dart` — same UI as `PublicItemScanPage` but fetches by barcode.

### QR label format update

Update barcode label QR to encode:
- If business has public slug: `https://harisree.app/scan/{token}` (existing, preferred — shows full detail)
- For external EAN labels: staff can type barcode at `harisree.app/lookup?barcode=X&business=harisree`

---

## PART 4 — Read-only vs edit enforcement

**Verify current behavior:**
- `sessionIsStockReadOnly(session)` returns true for Viewer role
- `_WarehouseScanActionBodyState._save()` checks this and shows snackbar

**Current gap:**  
Read-only users still see the quantity input field and the save button (just disabled). This is confusing. The entire edit form should be hidden for read-only users.

**Fix in `_WarehouseScanActionBody`:**
```dart
@override
Widget build(BuildContext context) {
  final session = ref.watch(sessionProvider);
  final isReadOnly = session == null || sessionIsStockReadOnly(session);
  
  if (isReadOnly) {
    // Show only info card, no edit form
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScanItemStockSummaryCard(item: widget.item),
        const SizedBox(height: 12),
        Text(
          'Read-only account. Ask owner to update stock.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
  
  // ... existing edit form for privileged users
}
```

---

## PART 5 — Testing checklist

| Test | Expected | Pass |
|------|----------|------|
| Scan item → sheet shows 3 tiles (Stock, Purchased, Physical) | 3 tiles visible | [ ] |
| Tile 2 shows last purchased qty + unit + date + rate | e.g. "5 BAG · 3 days ago · ₹120" | [ ] |
| If never purchased → Tile 2 shows "None / No purchases yet" | "None" | [ ] |
| Public QR scan → current stock shown prominently (32px font) | Large number visible | [ ] |
| Public QR scan → 3-tile row visible | Same layout | [ ] |
| Read-only user scans → edit form hidden, info only | No save button | [ ] |
| Safari iOS scan → upload photo fallback shown | Not blank | [ ] |
| Web URL `/lookup?barcode=X&business=harisree` → item page | Item found | [ ] |
| Web URL with unknown barcode → "Item not found" message | Error state | [ ] |

---

## FILES TO CHANGE

1. `flutter_app/lib/features/barcode/presentation/widgets/scan_item_stock_summary_card.dart` — Add `_PurchaseTile`, 3-tile layout
2. `flutter_app/lib/features/barcode/presentation/public_item_scan_page.dart` — Prominent stock headline, 3-tile layout
3. `flutter_app/lib/features/barcode/presentation/warehouse_scan_action_sheet.dart` — Hide edit for read-only users
4. `flutter_app/lib/core/router/app_router.dart` — Add `/lookup` route
5. `flutter_app/lib/features/barcode/presentation/public_barcode_lookup_page.dart` — NEW FILE
6. `backend/app/routers/public_items.py` — Add `GET /public/lookup` endpoint
7. `backend/app/routers/catalog.py` — Verify `supplier_name` returned in barcode lookup response

## CURSOR PROMPT (use this exactly)

```
Implement BARCODE_SCAN_REBUILD_PLAN.md Part 1:
- File: flutter_app/lib/features/barcode/presentation/widgets/scan_item_stock_summary_card.dart
- Replace the 2-tile Row with a 3-tile Row: [Current Stock][Last Purchase][Physical Count]
- Add new _PurchaseTile StatelessWidget (amber #B45309 color, shows lpQty+lpUnit as headline, date+rate as subtitle, "No purchases yet" if null)
- Update ScanItemStockSummaryCard to extract lpRate from item['last_purchase_rate']
- Do not change any other files in this step
```
