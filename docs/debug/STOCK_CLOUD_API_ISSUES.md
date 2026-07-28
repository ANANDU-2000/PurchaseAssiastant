# Stock cloud API issues — live evidence inventory

Captured 2026-07-28 against production:

- Web: https://purchase-assiastant.vercel.app
- API: https://my-purchases-api.onrender.com
- DB: Render Postgres `harisree-db` (`dpg-d8fu1p77f7vs73eooiu0-a`)

## Evidence summary

| Source | Finding |
|--------|---------|
| User UI (item detail) | **Could not load stock summary / verification log / analytics** |
| Login footer (user screenshot) | **Build c7370bb** (stale SW/cache). Live production was later **d577b8f** — hard refresh required |
| Render logs | `GET …/stock/{itemId}/bundle` → **HTTP 500** |
| Exact exception | `sqlalchemy.exc.InvalidRequestError: This session is provisioning a new connection; concurrent operations are not permitted` (`isce`) |
| Same window | `get_catalog_item failed` for item `cae3355b-…`; `GET …/stock/{id}` often **200** but slow (~1.8s); parallel `shell-bundle` 200s |
| Health | `/health/ready` ok; alembic `068_physical_count_idempotency_key` |

## P0 — break item detail / “all cloud data failed”

### ISSUE-01 — `/stock/{id}/bundle` shared-session gather (root cause)
- **Where:** `backend/app/routers/stock/stock_detail.py` → `stock_item_bundle`
- **Bug:** `asyncio.gather(get_stock_item, stock_item_activity, get_stock_intelligence, get_catalog_item)` all share one `AsyncSession`
- **Effect:** 500 → Flutter item-detail warm-up fails → summary/analytics/verification cards show load errors
- **Status:** fix — sequential awaits on the same session

### ISSUE-02 — same-pattern stock gathers
- `stock_list.py` shell-bundle `asyncio.gather(..., db=db)` (~462)
- `stock_list.py` warehouse alerts concurrent `db.execute` gather (~764)
- `stock_barcode.py` barcode lookup gather (~188)
- (Tracked, later): `home_operational_bundle.py`, `reports_trade.py`
- **Status:** fix stock paths in this pass

### ISSUE-03 — UI error fan-out
- Three cards gate on `stockItemDetailProvider` error (`item_stock_snapshot_card`, `item_analytics_section`, `item_physical_verification_card`)
- One poisoned/failed detail fetch looks like “everything cloud failed”
- **Status:** track; revisit only if still broken after ISSUE-01

## P1 — reliability / UX

### ISSUE-04 — client refetch storm
- Multiple parallel identical `shell-bundle` requests in Render logs
- **Status:** track (client debounce / cache) — not required for P0 500 fix

### ISSUE-05 — stale Vercel build in browser
- User saw `c7370bb` while production was newer
- **Mitigation:** hard refresh / clear site data for `purchase-assiastant.vercel.app`

### ISSUE-06 — slow detail + unit mismatch
- `GET /stock/{id}` ~1.8s+; warnings `stock=pcs line=box` (qty not applied)
- **Status:** track (perf / data quality)

### ISSUE-07 — notification dedupe noise
- `UniqueViolationError` on `uq_notifications_dedupe`
- **Status:** track

## Out of scope this pass

Full 360 audit of purchases/reports/home routes; Flutter error-card redesign beyond making stock detail load.
