# User Permission System Redesign

**Date:** 2026-06-01

## Backend keys (`permissions.py`)

| Key | Group | UI label |
|-----|-------|----------|
| `stock_edit` | Inventory | Edit stock |
| `delete_access` | Inventory | Delete items |
| `purchase_create` | Purchases | Create purchase |
| `purchase_edit` | Purchases | Edit purchase |
| `reports_access` | Reports | View reports |
| `export_access` | Reports | Export reports |
| `analytics_access` | Reports | Analytics dashboard |
| `barcode_print` | Printing | Barcode print |
| `user_manage` | Administration | Manage users |

## UI pattern

```
Inventory
┌─────────────────────────────┐
│ Edit stock            [on]  │
│ Delete items          [off] │
└─────────────────────────────┘

Purchases
┌─────────────────────────────┐
│ Create purchase       [on]  │
│ Edit purchase         [off] │
└─────────────────────────────┘
...
```

- Compact rows: label + subtitle + `Switch.adaptive`
- Entire row tappable (44px min height)
- Single **Save permissions** at bottom

## Role gating

| Role | Permissions tab |
|------|-----------------|
| Owner / Admin | Edit + save |
| Manager | Read-only banner (API PATCH returns 403) |
| Staff | N/A (cannot open user management) |

## API

- `GET /users/{id}/permissions` — load
- `PATCH /users/{id}/permissions` — owner/admin only

No DB migration — uses existing `memberships.permissions_json`.

## Client sync

`session_permissions.dart` mirrors `ROLE_DEFAULTS`; grouped UI uses same keys as backend.
