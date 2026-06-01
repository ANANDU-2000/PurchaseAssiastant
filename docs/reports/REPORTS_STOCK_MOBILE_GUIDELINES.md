# Reports Stock Mobile Guidelines

**Date:** 2026-06-01  
**Target widths:** 320, 375, 390, 414 px

## Layout rules

1. **No horizontal page scroll** — only filter chip row may scroll horizontally inside its band.
2. **No name truncation on cards** — item names wrap naturally (`Text` without `maxLines: 1`).
3. **Touch targets ≥ 48dp** — KPI chips, filter chips, sort button, card tap area.
4. **Safe area** — tab content uses shell padding; bottom list padding 24px.

## Typography at mobile

| Element | Style | Notes |
|---------|-------|-------|
| Item name | `HexaDsType.h3` w600 | Wraps on 2+ lines OK |
| Category | `bodySm` | Single line preferred; wraps if needed |
| Stock qty | `metricPrimary` 26px w800 | Largest element on card |
| Movement label | `labelCaps` | 11px uppercase |
| Movement value | `bodyPrimary` w500 | Full phrase "3 days ago" |
| Usage lines | `bodyPrimary` w500 | `7d →` / `30d →` prefix |
| Badge | `labelCaps` 10px | Pill, not full width |

## Card spacing

- Horizontal margin: 12px
- Card gap: 10px
- Internal padding: 12px
- Left border: 4px fixed

## KPI / filter chips

- `Wrap` for KPI bar (summary) — wraps to second row on 320px
- Filter row: `SingleChildScrollView` horizontal — prevents chip squeeze
- Chip min height: 40dp

## Stock number format

- Comma thousands: `2,500`
- Unit uppercase: `BAG`, `KG`, `TIN`
- Near-integer tolerance via `formatStockQtyNumber` (0.001)

## Sort sheet

- Modal bottom sheet with drag handle
- SafeArea inset for home indicator
- ListTile per sort option (48dp min)

## Empty state

- Centered icon + message
- No blank white screen

## Performance

- Single API fetch (`operationalReportsProvider`)
- Filter/sort/search client-side on parsed list
- `SliverList.separated` for lazy build

## Accessibility

- Status not color-only: badge text repeats status name
- Left border supplements badge for quick scan

## Do not

- Use ellipsis on item names in Stock cards
- Show DioException / HTTP codes
- Hide search behind overlay on Stock tab
