# History filter system

## API (`listTradePurchases`)

Driven by **`_tradeListApiStatus`** + optional **`purchase_from` / `purchase_to`** from the filter sheet.

| Primary | API `status` |
|---------|----------------|
| all | omit |
| due | omit (client filter) |
| paid | `paid` |
| draft | `draft` |
| due_soon (legacy route) | `due_soon` |

| Secondary | API `status` |
|-----------|----------------|
| overdue | `overdue` |
| pending | omit (client: `confirmed`) |
| paid | **unused** — use primary `paid` |

## Client-only

- **Due** primary: outstanding / due_soon / overdue / confirmed with `remaining > 0` (see `_matchesDuePrimary`).
- **Supplier / broker** contains (case-insensitive substring).
- **Package type**: `bag` / `box` / `tin` / `mixed` via `purchaseHistoryMatchesPackKindFilter`.
- **Sort**: latest vs oldest (`purchaseHistorySortNewestFirstProvider`).

## Route query `filter=`

- `pending`, `overdue` → secondary + `all` primary.
- `paid` → primary `paid` (not secondary).
- `due_soon` / `due_today` → primary `due`.
