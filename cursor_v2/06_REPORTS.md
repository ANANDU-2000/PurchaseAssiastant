# SPEC 06 — REPORTS PAGE

> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS


| Task                                                | Status                                         |
| --------------------------------------------------- | ---------------------------------------------- |
| Date filter uses `purchase_date` (not `created_at`) | ✅ Fixed in trade_query.py                      |
| "Match Home period" sync button                     | ✅ Done                                         |
| Overview / Items / Suppliers / Brokers tabs         | ✅ Done                                         |
| Gray text → readable dark text                      | ✅ Done (`HexaColors.textBody` + explicit dark amounts) |
| Total weight shown per period                       | ✅ Done (`_summaryHeader` kg/bags/boxes/tins)   |
| Reports page shows ₹0 (empty list vs Home)         | ✅ Mitigated (`trade-summary` deals check + unfiltered fetch + local date filter + Hive) |
| "Total spend" wording removed                       | ✅ Done (not used; "TOTAL AMOUNT" / purchased copy) |
| Horizontal scroll tables removed → cards            | ✅ Done (`ReportsItemTile` + item detail list)  |


---

## FILES TO EDIT

```
flutter_app/lib/features/reports/presentation/reports_page.dart
flutter_app/lib/features/reports/presentation/reports_item_detail_page.dart
```

---

## WHAT TO DO

### ❌ TASK 06-A: Fix gray text across reports page

**File:** `reports_page.dart` and `reports_item_detail_page.dart`

**Find-and-replace in both files:**

```
Colors.grey.shade400  →  const Color(0xFF888888)
Colors.grey.shade500  →  const Color(0xFF555555)
Colors.grey.shade600  →  const Color(0xFF333333)
Colors.grey           →  const Color(0xFF555555)
```

**Specific overrides:**

```dart
// Section labels (ITEMS, SUPPLIERS etc.)
TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.8,
  color: const Color(0xFF888888),
)

// Values (amounts, weights)
TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w700,
  color: const Color(0xFF1A1A1A),
)

// Row secondary text (dates, IDs)
TextStyle(fontSize: 11, color: const Color(0xFF888888))
```

---

### ❌ TASK 06-B: Show total weight in Overview tab

**File:** `reports_page.dart`

In the Overview section, below or next to the total purchase amount, add:

```dart
// After the ₹X total amount widget:
Row(
  children: [
    _metricTile('Total kg', _fmtKg(data.totalWeightKg)),
    _metricTile('Total bags', _fmtNum(data.totalBags)),
    // show boxes/tins only if > 0
    if (data.totalBoxes > 0)
      _metricTile('Total boxes', _fmtNum(data.totalBoxes)),
  ],
)
```

Where `_metricTile` is a small labeled card.

---

### ❌ TASK 06-C: Remove horizontal scroll tables from items tab

**File:** `reports_item_detail_page.dart`

The items tab may show a horizontal `DataTable` or scrollable table. Replace with
vertical cards:

```
┌────────────────────────────────────────────────┐
│ BARLI RICE                         ₹2,49,900  │
│ 5,000 kg  ·  P: ₹48/kg  ·  S: ₹55/kg         │
│ 3 purchases  |  Apr 2026                       │
└────────────────────────────────────────────────┘
```

Use `ListView.builder` with card items, no horizontal scroll anywhere.

---

### ❌ TASK 06-D: Remove "total spend" from reports

**File:** `reports_page.dart`

Replace:

- "Total spend" → "Total purchased"
- "Total purchase amount" → "Total amount"

---

## SPEC: Reports Page Layout

```
AppBar: "Reports"    [⋮ more options]

[Month ▾]   6 Apr → 5 May    [← →]    [Match Home]

┌────────────────────────────────────────────────┐
│ TOTAL AMOUNT                      ₹10,85,244  │
│ Total kg: 15,000   Total bags: 300             │
└────────────────────────────────────────────────┘

[ Overview ] [ Items ] [ Suppliers ] [ Brokers ]

── Overview ────────────────────────────────────

5 purchases this period

BARLI RICE         5,000 kg        ₹2,49,900
SUGAR 50 KG        5,000 bags      ₹2,75,000
Basmathu           200 bags        ₹2,70,185
...

── Items tab ───────────────────────────────────

[search]

┌──────────────────────────────────────────────┐
│ BARLI RICE                       ₹2,49,900  │
│ 5,000 kg  ·  P:₹48/kg  ·  S:₹55/kg         │
└──────────────────────────────────────────────┘
```

---

## VALIDATION

- Reports shows actual purchases (not ₹0) for current month
- All text visible — no light gray on white background
- Total weight shown in overview
- No horizontal scroll anywhere
- "Total spend" text not found anywhere

