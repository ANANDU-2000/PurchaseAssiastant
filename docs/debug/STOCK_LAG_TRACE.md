## Operator: daily physical remaining (sugar example)

1. Purchase + delivery of sugar **100** → **System** qty = 100 (ledger).
2. Staff daily floor check: save **Physical** remaining 99, then later 80.
3. **Diff** column / sheet = Physical − System (e.g. −1, then −20).
4. System stays 100 until someone uses **System** mode (owner/manager).
5. Activity tab shows physical edits; filter **Today's physical** for today’s floor log.
6. Item history **Physical** chip lists per-item floor remaining trail.

See also Activity merge + `GET …/stock/physical-counts/recent`.

---

# Stock lag / save / Activity — trace notes (2026-08-08)

No secrets. Live topology: Vercel Flutter → `api.harisreeagency.online` (Windows + Cloudflare Tunnel) → Postgres on PC6.

## Operator checks (before code)

| Check | Expected |
|-------|----------|
| Web host | **https://purchase-assiastant.vercel.app** only |
| Typo hosts (`assiantant`, `assiatant`, `assistant`) | Wrong project / Render — do not use |
| Network filter `onrender` | **0** hits |
| `GET /health/ready` | `alembic_version` **069_owner_ops_tables**, `schema_ok: true` |
| Render `my-purchases-api.onrender.com` | Suspended — ignore |

## Product: SAVE PHYSICAL COUNT

- POST `…/stock/{id}/physical-count` writes `stock_physical_counts` only.
- **Does not** change system ledger `current_stock`.
- Snackbar: “Physical saved — system ledger unchanged…”
- UI must update **Physical / Diff** columns via row patch; System qty stays the same by design.

## Debug instrumentation (this change)

**Client (debug builds):**

- Dio interceptor stamps `_stock_storm_sw` and logs `[STOCK_TIMING]` for stock GETs.
- `StockApiStormMonitor` counts `stock/list`, `shell-bundle`, `audit/recent`, `alerts/summary`, `delivery-counts` per 10s window → `[STOCK_STORM_SUMMARY]`.
- Flush on Activity seed/timeout and physical save success.

**Server:**

- `stock.shell_bundle` / `stock.shell_bundle cache_hit` duration logs.
- `stock.audit_recent` duration + row count.

Correlate with client `x-request-id` header.

## P0 fixes shipped in same pass

1. Activity: no hard-invalidate every tab switch (soft refresh if >2 min stale).
2. Activity: 15s timeout on audit snapshot; seed from shell-bundle `audit_recent`.
3. Stock tab return: invalidate **shell-bundle only** (list derives on page 1).
4. Health expect head aligned to **069** (matches live PC6 until 070 is pushed).

## How to reproduce timing

1. Open canonical Vercel host, Stock tab.
2. Switch Activity once; watch console for `[STOCK_ACTIVITY]` / `[STOCK_STORM_*]`.
3. Save a physical count; confirm snackbar + Physical column; System unchanged.
4. On PC6 API logs: search `stock.shell_bundle` / `stock.audit_recent`.
