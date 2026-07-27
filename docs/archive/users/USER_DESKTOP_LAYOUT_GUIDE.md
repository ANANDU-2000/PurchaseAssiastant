# User Desktop Layout Guide

**Date:** 2026-06-01  
**Widths:** 768, 1024, 1440 px

## User Management (≥1024px)

```
┌──────────────────┬─────────────────────┐
│ Search + filters │                     │
│ User list (4)    │ Detail panel (5)    │
│                  │                     │
└──────────────────┴─────────────────────┘
```

- Removed vertical sidebar filter column (was duplicate of chips)
- List + compact preview panel; **Open full profile** for tabs
- Detail panel: compact summary + menu actions (not full button row)

## User Profile (all desktop widths)

- Overview KPI: **4-column** grid
- Same sticky 3-tab bar as mobile
- Nested scroll: header collapses to avatar + name in app bar title
- Max content width follows app scaffold (no extra empty margins in cards)

## Information density target

~30–40% less vertical scroll vs previous design:

- Removed 4 top-level tabs (merged into Activity)
- Removed heavy OutlinedButton action row from header
- List card height reduced ~25%

## Keyboard

- Search field focusable from tab order
- Tab bar keyboard navigable (Material default)
