# SPEC 10 — PERFORMANCE & BACKEND RELIABILITY
> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS
| Task | Status |
|------|--------|
| DB pool pre_ping | ✅ Done |
| DB pool size reduced for free tier | ✅ Done |
| Retry interceptor on Dio | ✅ (`dio_auto_retry_interceptor.dart` exists) |
| `/health/ready` endpoint | ✅ Done (DB ping + 503 on failure) |
| Flutter warmup on launch | ✅ Done (onSlow sets “Connecting…” banner) |
| Provider `keepAlive` + 5min cache | ✅ Done |
| Selective invalidation (not on every page open) | ⚠️ Partial (kept providers alive; invalidation still mutation-driven elsewhere) |
| "Connecting…" skeleton on cold start | ✅ Done (banner via `apiDegradedProvider`) |
| UptimeRobot keep-warm setup | ❌ (manual — not code) |
| `stored_bill_total` mismatch fix | ✅ Done (server totals include charges in `compute_totals`) |
| Supabase index for purchase_date queries | ⚠️ Migration 012 adds some indexes |

---

## FILES TO EDIT
```
backend/app/routers/health.py   (or main.py if health inline)
backend/app/services/entry_write.py
flutter_app/lib/core/providers/trade_purchases_provider.dart
flutter_app/lib/core/providers/purchase_prefill_provider.dart
flutter_app/lib/core/api/api_warmup.dart
flutter_app/lib/core/api/hexa_api.dart
```

---

## WHAT TO DO

### ⚠️ TASK 10-A: Verify `/health/ready` pings DB

**File:** `backend/app/main.py` or `backend/app/routers/health.py`

```python
@router.get("/health/ready")
async def health_ready(db: AsyncSession = Depends(get_db)):
    """Returns 200 if DB is reachable, 503 if not."""
    try:
        await db.execute(text("SELECT 1"))
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"DB unreachable: {e}")
```

If this endpoint already exists with DB ping, mark ✅.

---

### ❌ TASK 10-B: Provider keepAlive + cache

**File:** `trade_purchases_provider.dart` and `purchase_prefill_provider.dart`

For list providers that are fetched on every page open, add keepAlive:

```dart
// In each list provider (suppliers, brokers, catalog, purchases):
@Riverpod(keepAlive: true)
Future<List<...>> suppliersList(SuppliersListRef ref) async {
  ref.keepAlive();
  // Fetch from API...
}
```

**Invalidate ONLY after a mutation (purchase save, supplier create, etc.):**
```dart
// After saving a purchase:
ref.invalidate(tradePurchasesProvider);
// Do NOT call ref.invalidate on every build/navigation
```

---

### ❌ TASK 10-C: "Connecting…" skeleton on cold start

**File:** `api_warmup.dart`

```dart
// If warmup takes >3 seconds, the app shell should show a gentle loading state
// Not a blank screen, not a crash

class ApiWarmup {
  static Future<void> warmup({
    required String baseUrl,
    VoidCallback? onSlow,  // called if >3s elapsed
  }) async {
    final timer = Timer(const Duration(seconds: 3), () => onSlow?.call());
    try {
      final dio = Dio()
        ..options.connectTimeout = const Duration(seconds: 30)
        ..options.receiveTimeout = const Duration(seconds: 30);
      await dio.get('$baseUrl/health/ready');
      timer.cancel();
    } catch (e) {
      timer.cancel();
      // Warmup failed — app continues anyway, individual requests will retry
      debugPrint('Warmup failed: $e');
    }
  }
}
```

**In `main.dart` or `app.dart`:**
```dart
// Show subtle banner while warming:
if (_isWarming) {
  return MaterialBanner(
    content: const Text('Connecting to server…'),
    actions: [const SizedBox.shrink()],
    backgroundColor: Colors.orange.shade50,
  );
}
```

---

### ❌ TASK 10-D: Fix stored_bill_total mismatch

**File:** `backend/app/services/entry_write.py`

When a purchase is saved or updated, recompute `total_amount` to include ALL charges:

```python
def compute_total_amount(
    lines_total: Decimal,
    freight: Decimal | None,
    commission_amount: Decimal | None,
    billty_rate: Decimal | None,
    delivered_rate: Decimal | None,
    header_discount: Decimal | None,
) -> Decimal:
    return (
        lines_total
        + (freight or Decimal(0))
        + (commission_amount or Decimal(0))
        + (billty_rate or Decimal(0))
        + (delivered_rate or Decimal(0))
        - (header_discount or Decimal(0))
    )
```

**Also run the SQL fix on existing data:**
```sql
-- Run in Supabase SQL editor:
UPDATE trade_purchases tp
SET total_amount = (
  SELECT COALESCE(SUM(
    CASE
      WHEN l.kg_per_unit > 0 AND l.unit IN ('bag', 'sack')
        THEN l.qty * l.kg_per_unit * l.landing_cost_per_kg
      ELSE l.qty * l.purchase_rate
    END
    * (1 + COALESCE(l.tax_percent, 0) / 100)
    * (1 - COALESCE(l.discount_percent, 0) / 100)
  ), 0)
  + COALESCE(tp.freight, 0)
  + COALESCE(tp.commission_amount, 0)
  + COALESCE(tp.billty_rate, 0)
  + COALESCE(tp.delivered_rate, 0)
  - COALESCE(tp.header_discount, 0)
  FROM trade_purchase_lines l
  WHERE l.purchase_id = tp.id
)
WHERE tp.business_id = '<YOUR_BUSINESS_ID>';
```

---

## MANUAL TASK: UptimeRobot Keep-Warm

**Not a code task — do this in browser:**

1. Go to https://uptimerobot.com (free account)
2. Add New Monitor:
   - Type: HTTP(s)
   - URL: `https://YOUR_APP_NAME.onrender.com/health`
   - Check interval: 5 minutes
3. This prevents Render free tier cold starts (10–30 second delays)
4. Alternative: Render paid plan $7/mo eliminates cold starts permanently

---

## VALIDATION
- [ ] `/health/ready` returns `{"status":"ok"}` when DB is reachable
- [ ] `/health/ready` returns 503 when DB unreachable
- [ ] Suppliers list NOT re-fetched on every wizard open
- [ ] Suppliers list IS re-fetched after adding a new supplier
- [ ] Cold start (after 15min idle): "Connecting…" banner shown, not blank screen
- [ ] `stored_bill_total` matches `total_amount` for all purchases (SQL fix applied)
