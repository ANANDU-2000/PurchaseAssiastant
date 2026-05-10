# Global soft delete audit (Phase 7)

**Rule:** User-visible lists and aggregates must exclude tombstoned rows: `deleted_at` where present (e.g. catalog), or **`status`** in `deleted` / `cancelled` for `trade_purchases` (this table has no `deleted_at` column today).

## Backend surfaces to verify

| Router / service | Notes |
|------------------|-------|
| `trade_purchases` | List, detail, duplicates — filter `deleted_at` / status |
| `reports_trade` | Aggregates must exclude deleted purchases |
| `search` | No deleted catalog suppliers or purchases in default results |
| `dashboard` | Counts exclude deleted |
| `catalog` | Items / categories with tombstone |

## Flutter surfaces

| Feature | Expectation |
|---------|-------------|
| Purchase history | No deleted purchases unless “show deleted” admin mode |
| Ledger / supplier / item | Same |
| PDF / print | Uses server payload; server must not emit deleted lines |

## CI gate (recommended)

- Grep for raw `TradePurchase` list queries without `deleted_at` / status filter (manual review).
- Pytest: one fixture purchase marked deleted must not appear in report totals helper (add when query helper exists).

## Follow-up

- Enumerate every `select(TradePurchase` and `select(CatalogItem` in `backend/app` and tick filters.
