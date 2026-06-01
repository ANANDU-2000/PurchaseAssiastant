# User Mobile Layout Guide

**Date:** 2026-06-01  
**Widths:** 320, 375, 390, 414 px

## User Management list

- Search bar full width; filter icon 48×48 dp with badge
- Primary filter chips horizontal scroll (4 chips max)
- `UserCompactCard`: name wraps, no ellipsis on email if short enough
- Card vertical padding 10px (was 12+)
- Popup menu ⋯ on right — 48dp touch target

## User Profile

- `SliverAppBar` expandedHeight 148px (was ~280+ effective)
- 3 tabs fit without horizontal scroll (`isScrollable: false`)
- Overview KPI: **2-column** grid
- Permissions: full-width grouped cards, switches shrink-wrapped
- Activity subsection chips: horizontal scroll OK (inside tab only)

## Typography (mobile)

| Element | Size | Weight |
|---------|------|--------|
| Page title | 24 | 800 |
| User name | 22 | 700 |
| Section header | 16–18 | 600 |
| KPI value | 24 | 800 |
| Supporting | 12 | 400–500 |

## Do not

- Horizontal scroll on primary profile tabs
- Hide tabs behind header card
- Show raw DioException / HTTP codes

## Accessibility

- Touch targets ≥ 44px (chips, menu, switches)
- Status pills use text + color (not color-only)
