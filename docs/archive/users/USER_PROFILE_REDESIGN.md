# User Profile Redesign

**Date:** 2026-06-01

## Layout

```
┌─────────────────────────────────────┐
│ ← User profile          [Edit] [⋮]  │  ← collapses to avatar + name
├─────────────────────────────────────┤
│ A  Amal                             │
│    Staff · Active                   │
│    Warehouse: Harisree Workspace    │
│    email · phone · Last active      │
├─────────────────────────────────────┤
│ Overview | Activity | Permissions   │  ← pinned, no horizontal scroll
├─────────────────────────────────────┤
│ (tab content)                       │
└─────────────────────────────────────┘
```

## Header (compact)

- Avatar 44px (expanded) → 28px (collapsed title)
- Name 22px bold
- Role + status pills (not oversized Chips)
- Warehouse, email, phone, last active on one screenful
- **Edit user** — only visible primary button
- **⋮ menu** — Reset password, Copy email, Block, Deactivate, Delete

## Tabs (3 only)

| Tab | Content |
|-----|---------|
| Overview | KPI grid: Purchases, Stock updates, Items created, Scans |
| Activity | Timeline + chips: All / Stock / Purchases / Items / Ledger |
| Permissions | Grouped toggles (owner/admin edit; manager read-only banner) |

## Removed from top-level tabs

Stock, Purchases, Items, Ledger → nested under **Activity**.

## Sticky behavior

- `NestedScrollView` + `SliverAppBar` pinned
- `TabBar` in `SliverAppBar.bottom` stays fixed while scrolling
- Collapsed title shows mini avatar + name

## Edit flow

Bottom sheet: name, email, phone, role (non-owner). Saves via `patchBusinessUser`.

## Files

- `user_profile_page.dart` — shell
- `users/user_profile_header.dart`
- `users/user_overview_kpi_grid.dart`
- `users/user_activity_tab.dart`
- `users/user_permission_groups.dart`
- `users/user_profile_providers.dart`
