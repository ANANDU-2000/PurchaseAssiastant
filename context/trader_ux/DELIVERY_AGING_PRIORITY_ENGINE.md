# Delivery aging priority engine

## Scope

Pure **presentation + sort** logic for “goods not received” — **no** change to how `is_delivered` is persisted or how backend computes status.

## API

| Symbol | Role |
|--------|------|
| `undeliveredDaysSincePurchase(TradePurchase p)` | Local calendar days from purchase date to today |
| `undeliveredAgingBandFromDays(int d)` | Maps days → `neutral` / `warning` / `strong` / `critical` |
| `undeliveredAgingColors(UndeliveredAgingBand b)` | Returns `(bg, border, fg)` for chip |

## Thresholds (product)

- **0–2** days: neutral slate  
- **3–5**: warning orange  
- **6–9**: strong orange  
- **10+**: critical red  

## Sorting

When primary filter is **`pending_delivery`** or **`delivery_stuck`**, purchases sort by:

1. Descending **pending age** (undelivered days).  
2. Then **newer purchase date**.  
3. Then **humanId** (stable tie-break).

Delivered / irrelevant rows get age `-1` and sink in that sort.

## File

- `flutter_app/lib/core/purchase/delivery_aging.dart`

## Cross-links

- `PURCHASE_HISTORY_DELIVERY_TRACKING.md`
