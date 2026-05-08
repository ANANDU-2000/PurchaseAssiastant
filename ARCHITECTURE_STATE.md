# ARCHITECTURE STATE

## Stack

- **Mobile:** Flutter (`flutter_app/`), Riverpod, GoRouter.
- **API:** FastAPI (`backend/`), async SQLAlchemy, Postgres-compatible DB.
- **Admin web:** `admin_web/` (when in scope).

## Data ownership

- **Authoritative financial totals:** computed on **server** at save time and for aggregates; clients render.
- **Month dashboard (`GET /dashboard?month=`):** aggregates only purchases whose `status` is in `trade_query.TRADE_STATUS_IN_REPORTS` (same contract as trade summary reports); excludes `deleted`, `draft`, `cancelled`.
- **Scan JSON:** keyed by `scan_token` until confirm; edits persisted via scan update endpoint before confirm.

## Primary user journeys

1. Manual purchase entry (`PurchaseEntryWizardV2` and related).
2. Scan bill → draft map provider → **Purchase draft wizard** → confirm → trade purchase created.

## Caching

- Flutter: Riverpod providers; invalidate on mutation routes (purchases, catalog, contacts).
- Avoid optimistic UI that contradicts server totals without rollback.

## Related specs

- `context/rules/MASTER_CURSOR_RULES.md`
- `docs/AI_PURCHASE_VALIDATION_AND_SAFETY.md`
