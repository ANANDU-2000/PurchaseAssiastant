# Reports Stock UX Redesign

**Date:** 2026-06-01  
**Persona:** Warehouse owner / manager (daily ERP use)

## 3-second decision model

```
Scan KPI bar → filter chip → sort → read card qty + border color → tap for detail
```

## Card anatomy

```
┌─█──────────────────────────────────┐  ← 4px left border (status color)
│ SUGAR 50 KG                        │  Level 1: semi-bold name
│ Category: Rice                     │
│                                    │
│ 2,500 BAG                          │  Level 2: bold 26px stock
│                                    │
│ LAST MOVEMENT                      │  Level 3: caps label + value
│ 3 days ago                         │
│                                    │
│ USED                               │
│ 7d → 0 BAG                         │
│ 30d → 20 BAG                       │
│                                    │
│ [ Slow Moving ]                    │  Level 4: status badge
└────────────────────────────────────┘
```

## Status system

| Status | Badge | Border | When |
|--------|-------|--------|------|
| Active | Green | Green | On-hand, recent movement, 7d usage possible |
| Slow Moving | Yellow | Yellow | 7–29 days idle, no 7d usage |
| Very Slow | Orange | Orange | 30–59 days idle |
| Dead Stock | Red | Red | 60d+ idle or stale purchase rule |
| Fast Moving | Blue | Blue | `used_7d > 0` |
| No Activity | Gray | Gray | No movement ever, zero usage |

Backend key: `movement_status` on each item.

## Summary KPI bar (clickable)

```
[● Active 120] [● Slow 30] [● Dead 2] [● Fast 45]
```

- Tap toggles filter (tap again → All)
- Dot color matches status family

## Filter row

```
[All (120)] [Active (80)] [Slow (30)] [Dead (2)] [Fast (45)]
```

Horizontal scroll on narrow screens; full labels with counts.

## Sort sheet

- Highest / Lowest stock
- Most / Least used (7d)
- Recently moved / Oldest movement
- A–Z

## Search

Always visible in Reports top bar when Stock tab active.  
Placeholder: **Search item name…**  
Matches name, category, item code.

## Empty states

| Filter | Copy |
|--------|------|
| Dead | No dead stock found. |
| Slow | No slow-moving items found. |
| Fast | No fast-moving items in this window. |
| Active | No active items with on-hand stock. |
| All + search | No stock items match your search. |

## Deep links

Legacy URLs (`?tab=stock&section=dead`) pre-select filter chip via `highlightSection`.

## Removed patterns

- ❌ `Current stock: 2500 bags` label prefix
- ❌ Section-per-category vertical stack
- ❌ "Open Stock tab for full ledger" placeholder sections
- ❌ Idle-day bucket badges ("7d idle")

## Success metrics

- Owner identifies dead stock without scrolling past unrelated sections
- Stock quantity readable at arm's length on phone
- Filter + sort change list in <300ms (client-side on cached API payload)
