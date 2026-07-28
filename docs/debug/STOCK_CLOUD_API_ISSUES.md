# Cloud API issues — shared-session `asyncio.gather` (isce) inventory

Captured / audited 2026-07-28 against production:

- Web: https://purchase-assiastant.vercel.app
- API: https://my-purchases-api.onrender.com
- DB: Render Postgres `harisree-db` (`dpg-d8fu1p77f7vs73eooiu0-a`)

## Evidence summary (stock item detail)

| Source | Finding |
|--------|---------|
| User UI (item detail) | **Could not load stock summary / verification log / analytics** |
| Login footer (user screenshot) | **Build c7370bb** (stale SW/cache). Later builds: **d577b8f**, **a52dd46** — hard refresh required |
| Render logs | `GET …/stock/{itemId}/bundle` → **HTTP 500** |
| Exact exception | `sqlalchemy.exc.InvalidRequestError: This session is provisioning a new connection; concurrent operations are not permitted` (`isce`) |
| Same window | `get_catalog_item failed` for item `cae3355b-…`; `GET …/stock/{id}` often **200** but slow (~1.8s); parallel `shell-bundle` 200s |
| Health | `/health/ready` ok; alembic `068_physical_count_idempotency_key` |

## Root cause (all ISSUE-01 / 02 / 08–11)

SQLAlchemy `AsyncSession` forbids concurrent operations. `asyncio.gather(...)` with multiple coroutines that call `db.execute` / helpers on **one** request session → `isce` → HTTP 500.

**Fix pattern:** sequential `await`s on the shared session (no parallel sessions in these passes).

---

## Full gather audit (repo-wide)

Repo search: `asyncio.gather` / `create_task` + shared request `db` under `backend/app`.

### Fixed — stock

| Route | File | Status |
|-------|------|--------|
| `GET …/stock/{id}/bundle` | `stock_detail.py` → `stock_item_bundle` | Sequential (ISSUE-01) |
| `GET …/stock/shell-bundle` | `stock_list.py` → `stock_shell_bundle` | Sequential (ISSUE-02) |
| `GET …/stock/warehouse/alerts-summary` | `stock_list.py` → `warehouse_alerts_from_stock` | Sequential (ISSUE-02) |
| `GET …/stock/barcode/lookup` | `stock_barcode.py` | Sequential (ISSUE-02) |

### Fixed — home / reports (this pass)

| ID | Endpoint(s) | Code | Status |
|----|-------------|------|--------|
| **ISSUE-08** | `GET …/reports/trade-dashboard-snapshot` and `GET …/reports/home-overview` | `_compute_trade_dashboard_snapshot_payload` ~625 — 3× `db.execute` gather | Sequential |
| **ISSUE-09** | Same | Same function ~634 — 4 breakdown helpers gather | Sequential |
| **ISSUE-10** | Same | Same function ~779 — 5× `_count_scalar` gather | Sequential |
| **ISSUE-11** | `GET …/reports/home-overview?shell_bundle=true` (Flutter Home) | `build_home_operational_bundle` ~61 | Sequential |

### Safe (not same-session concurrent DB)

- `main.py` background jobs: own `async_session_factory()` per tick
- Health / `wait_for` timeout wrappers (single execute)
- Sequential `execute_with_retry` in dashboard/search/catalog
- `reports_item_bundle` sequential

**Audit complete:** no other live `asyncio.gather` sites sharing a request `AsyncSession` remain in `backend/app` after ISSUE-08…11.

---

## P0 history — item detail

### ISSUE-01 — `/stock/{id}/bundle` shared-session gather
- **Status:** fixed — sequential awaits

### ISSUE-02 — same-pattern stock gathers
- **Status:** fixed stock paths; home/reports tracked as ISSUE-08…11 then fixed

### ISSUE-03 — UI error fan-out
- Three cards gate on `stockItemDetailProvider` error
- **Status:** track; revisit only if still broken after ISSUE-01

---

## P1 — reliability / UX (track only)

### ISSUE-04 — client refetch storm
- Multiple parallel identical `shell-bundle` requests
- **Status:** track (client debounce / cache)

### ISSUE-05 — stale Vercel build in browser
- **Mitigation:** hard refresh / clear site data for `purchase-assiastant.vercel.app`

### ISSUE-06 — slow detail + unit mismatch
- `GET /stock/{id}` ~1.8s+; warnings `stock=pcs line=box`
- **Status:** track (perf / data quality)

### ISSUE-07 — notification dedupe noise
- `UniqueViolationError` on `uq_notifications_dedupe`
- **Status:** track

## Out of scope

Flutter UI redesign; client refetch debounce; notification UniqueViolation; inventing parallel DB sessions / pool changes for speed.
