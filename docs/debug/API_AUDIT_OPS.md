# API Audit — Phase 9: Warehouse / Ops

**Date:** 2026-07-28  
**Routers:** `operations.py`, `stock_audits.py`, `stock/stock_list.py` (warehouse alerts), `stock/stock_ops.py`, `stock/stock_detail.py` (verify-count), `stock_audit_service.py`

## Prod evidence

- No sampled **5xx** on `/operations*`, `/stock-audits*`, `/warehouse*`
- Shared-session `asyncio.gather` already sequentialized on warehouse alert paths

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| OPS-H1 | High | Checklist summary counted `distinct(task_key)` only — morning+evening same key undercounted | **Fixed** |
| OPS-H2 | High | `usage_submit` new `DailyUsageLog` left `source_id=None` on stock movement | **Fixed** |
| OPS-H3 | High | `snapshots/materialize` any member → require `stock_edit` | **Fixed** |
| OPS-C1 | Critical | `verify-count` looked up client idempotency key but never stored it → retry could overwrite stock | **Fixed** |
| OPS-C2 | Critical | PUT stock-audit `items.clear()` after applied lines → complete could invent/erase stock | **Fixed** |
| OPS-H4 | High | Inventory summary exposed `total_value_inr` to staff | **Fixed** (redact) |
| OPS-H5 | High | Warehouse checklist total counted business **and** global templates | **Fixed** |
| OPS-H6 | High | Reorder list leaked `last_purchase_rate` to staff | **Fixed** |
| OPS-M1 | Medium | `_ensure_default_templates` flush-only (no commit until route commits) | Track |
| OPS-M2 | Medium | Checklist complete does not validate `task_key` against templates | Track |

## Fixes (this pass)

- Checklist done: `distinct(slot:task_key)` in ops summary + warehouse alerts
- Usage: assign + `flush` new log before `apply_stock_movement`
- Materialize: `require_permission("stock_edit")`
- `apply_audit_line_to_stock(..., idempotency_key=)` threaded from verify-count
- PUT audit rejects replace when any line is `applied` / `pending_approval`
- Staff: zero `total_value_inr`; null `last_purchase_rate`
- Warehouse template denominator mirrors `_templates_for_business`

## Tests

- `tests/test_stock_audit.py` — `test_verify_count_idempotency_key_prevents_double_apply`
- Existing ops / warehouse alert / inventory summary suites

## Open Critical

**None** for Warehouse/Ops after this pass.

## Next

Exports → Utilities → Public.
