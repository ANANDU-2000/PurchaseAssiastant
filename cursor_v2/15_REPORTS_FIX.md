# 15 — REPORTS PAGE FIX (₹0 bug + UI)

> `@.cursor/00_STATUS.md` first

---

## STATUS


| Task                                                        | Status                                                       |
| ----------------------------------------------------------- | ------------------------------------------------------------ |
| **Reports shows ₹0 on Week view "30 Apr → 6 May"**          | ⚠️ Mitigated (parse guard + Hive; verify on device)          |
| **Reports shows ₹0 on Month view "7 Apr → 6 May"**          | ⚠️ Mitigated (same)                                          |
| Reports works on "Month" when "Offline/saved copy" shown    | ✅ Works (cached)                                             |
| Total kg/bags/boxes/tins displayed                          | ✅ Done                                                       |
| "Total amount" label (not "total spend")                    | ✅ Done                                                       |
| Basmathu shows ₹1,300→₹1,350 (wrong — should be ₹26→₹27/kg) | ✅ Fixed (kg-weighted `landingGross`/`sellingGross` → `…/kg`) |
| Reports tabs take too much vertical space                   | ✅ Fixed (single-row horizontal scroll, compact chips)        |
| Search in items/suppliers/brokers sub-tabs                  | ✅ Done                                                       |


---

## FILES TO EDIT

```
flutter_app/lib/core/providers/reports_provider.dart
flutter_app/lib/features/reports/presentation/reports_page.dart
backend/app/routers/me.py   (or wherever /reports endpoint lives)
backend/app/services/trade_query.py
```

---

## BUG C1: Reports ₹0 — Root cause analysis

**Screenshot evidence:** "Week" showing "30 Apr → 6 May" returns ₹0. But offline/cached shows ₹6,93,750.
Purchases exist on May 5 (PUR-2026-0005).

**The `analyticsDateRangeProvider` week window** computes "30 Apr → 6 May". 
May 5 purchase SHOULD be in this range.

**Likely cause:** The API is returning 200 with empty data because:

**Option A: The API date range is off-by-one**
The Flutter provider sends dates as `yyyy-MM-dd` strings.
The backend `purchase_date` column may be stored as `timestamp with timezone` (UTC).
A purchase on "5 May 2026 12:00 AM IST" = "4 May 2026 18:30 UTC".
If backend filters `purchase_date <= '2026-05-06'` but purchase is stored as `2026-05-04T18:30:00Z`,
the UTC date comparison would work. But if `purchase_date` is stored as `date` type (no timezone),
it should be fine.

**Check in Supabase SQL editor:**

```sql
SELECT id, human_id, purchase_date, created_at 
FROM trade_purchases 
WHERE business_id = 'YOUR_BIZ_ID'
ORDER BY purchase_date DESC LIMIT 5;
```

**Option B: Wrong API endpoint being called**

The Flutter provider `reportsPurchasesPayloadProvider` may be calling a different endpoint than expected.

**Find the actual API URL being called:**

```dart
// In reports_provider.dart, add debug logging:
debugPrint('Reports API call: from=${fromStr} to=${toStr} bizId=$bizId');
```

**Option C: `week` date range computed wrong**

In `reports_page.dart`, find `_DatePreset.week` case:

```dart
// Current:
_DatePreset.week => (today.subtract(const Duration(days: 6)), today),
// This gives: if today = May 6, then from = Apr 30, to = May 6
// That should include May 5 purchases. ✓
```

**Option D: Cache key mismatch** — provider reads stale cache with wrong date key

**Debug fix — in `reports_provider.dart`:**

```dart
// Add explicit cache-busting: invalidate on every date range change
// In reportsPurchasesPayloadProvider:
final range = ref.watch(analyticsDateRangeProvider);
ref.onDispose(() => debugPrint('Reports provider disposed for range: $range'));

// Force fresh fetch when date changes:
final df = DateFormat('yyyy-MM-dd');
final cacheKey = '${df.format(range.from)}_${df.format(range.to)}_$bizId';
ref.watch(_reportsCacheKeyProvider(cacheKey));  // forces rebuild on key change
```

**The real fix — ensure API is called with correct parameters:**

```dart
// In reports_provider.dart, find the fetch function:
final url = '${session.apiBase}/v1/reports/purchases'
    '?business_id=$bizId'
    '&purchase_from=${df.format(range.from)}'    // ← must be purchase_from not date_from
    '&purchase_to=${df.format(range.to)}'        // ← must be purchase_to not date_to
    '&limit=500';

// Check what the actual query param names are in the backend:
// backend/app/routers/ -- find the reports endpoint
```

**Backend check:**

```python
# In the reports endpoint, print the actual filter:
logger.info(
    "Reports query: biz=%s from=%s to=%s",
    business_id, purchase_from, purchase_to
)
# Then check Render logs to see if May purchases are within range
```

---

## FIX: Basmathu shows ₹1,300→₹1,350 (should be ₹26→₹27/kg)

**File:** `reports_page.dart` (items tab) or `reports_item_detail_page.dart`

The items tab shows `₹1,300 → ₹1,350` for Basmathu (bag item with 50 kg/bag).
This is the per-bag rate. Should show per-kg rate: `₹26 → ₹27/kg`.

**Find where item rates are displayed in reports.** Apply `formatLineRate()` from `lib/core/utils/line_display.dart`.

```dart
// Replace rate display in reports items tab:
import '../../../core/utils/line_display.dart';

// Instead of:
Text('₹${item.lastPRate} → ₹${item.lastSRate}')

// Use:
Text(formatLineRate(rate: item.lastPRate, rateType: 'purchase', unit: item.defaultUnit, kgPerUnit: item.kgPerUnit) +
    ' → ' +
    formatLineRate(rate: item.lastSRate, rateType: 'selling', unit: item.defaultUnit, kgPerUnit: item.kgPerUnit))
// Shows: "P ₹26/kg → S ₹27/kg"
```

---

## FIX: Reports tabs — compact layout

**File:** `reports_page.dart`

The tabs/sub-tabs (Overview/Items/Suppliers/Brokers + Group/Sort rows) take up too much vertical space.

**Current height used:** ~180pt for filters alone.
**Target:** ≤100pt for all filters.

**Replace multi-row filter layout with:**

```dart
// Single scrollable row for main tabs:
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(children: [
    _tabChip('Overview', _tab == 0, () => setState(() => _tab = 0)),
    _tabChip('Items', _tab == 1, () => setState(() => _tab = 1)),
    _tabChip('Suppliers', _tab == 2, () => setState(() => _tab = 2)),
    _tabChip('Brokers', _tab == 3, () => setState(() => _tab = 3)),
  ]),
),
// Sub-filters only when on Items tab:
if (_tab == 1)
  SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      _subChip('All', _group == 'all'),
      _subChip('Bags', _group == 'bag'),
      _subChip('Box', _group == 'box'),
      _subChip('Tin', _group == 'tin'),
      const SizedBox(width: 16),
      _subChip('Latest', _sort == 'latest'),
      _subChip('High qty', _sort == 'qty'),
    ]),
  ),
```

---

## VALIDATION

- Reports "Week (30 Apr → 6 May)" shows ₹6,93,750 (not ₹0)
- Reports "Month" shows correct total
- Basmathu shows "P ₹26/kg → S ₹27/kg" (not ₹1,300 → ₹1,350)
- Filter tabs fit in ≤100pt vertical space
- Retry button actually retries the API call

