# Wave 2 — Duplicate & dead-code sweep (read-only)

**Date:** 2026-08-08  
**Evidence:** `VERIFIED_CODE`  
**Policy:** No deletes in this wave — sign-off required before any removal/rename.

## Backend routers

| Metric | Count |
|--------|------:|
| `backend/app/routers/**/*.py` | 26 (incl. 2 `__init__.py`) → **24 modules** |

### stock naming (not path duplicates)

| File | Role | Mount |
|------|------|-------|
| `routers/stock_audits.py` | Audit **sessions** CRUD | `/v1/businesses/{id}/stock-audits` |
| `routers/stock/stock_audit.py` | Adjustment / audit **feed** | `/v1/businesses/{id}/stock/audit/...` |

`legacy_router` in `stock_audits.py` is defined but **not** `include_router`'d in `main.py`.

**Proposed (needs sign-off):** rename `stock/stock_audit.py` → `stock/stock_adjustments.py` (module only; **no route path changes**).

## Archive scripts (`backend/scripts/archive/`)

Already labeled ARCHIVED for Render cutover leftovers. Keep under `archive/` only. Names include: `_render_cutover_env.py`, `migrate_supabase_to_render.py`, `ops/apply_render_env_cleanup.py`, `ops/apply_render_upgrade_061…065.py`, `render.yaml`, seed scripts, schema compare helpers.

## Flutter providers

| Metric | Count |
|--------|------:|
| `**/*provider*.dart` under `lib/` | **63** |

Canonical list providers are **single-definition**:
- `stockListProvider` → `stock_list_providers.dart`
- `tradePurchasesListProvider` → `trade_purchases_provider.dart`
- `stock_providers.dart` is a barrel export, not a second list provider

Near-names (related, not dupes): `bulkStockListProvider`, `homeOutOfStockListProvider`, alert purchase providers.

## Sign-off checklist (blocked until owner confirms)

- [ ] Approve module rename `stock_audit.py` → `stock_adjustments.py`
- [ ] Approve any archive move to `_deprecated/` or deletion
- [ ] Approve merging any overlapping providers (none flagged as true dupes yet)
