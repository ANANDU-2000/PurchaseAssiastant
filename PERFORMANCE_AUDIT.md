# Performance audit — baseline (Phase 5)

**Status:** Baseline template. Fill with **measured** numbers from DevTools / `EXPLAIN ANALYZE` / API logs per release.

## Targets (track after baseline)

| Surface | Target |
|---------|--------|
| Screen first paint | under 500 ms (warm) |
| Tab switch | under 150 ms |
| Search debounce | under 120 ms |
| Dashboard primary chart + cards | under 700 ms |

## Slowest Flutter screens (to measure)

| Route / screen | Notes |
|----------------|-------|
| `/purchase/new` wizard | Large `setState` surface — see `sprint1_audit_collect.py` → `flutter_setstate_large_widgets` |
| `/analytics` | Large StatefulWidget |
| `/purchase/scan` / scan draft | Image decode + preview |

## Riverpod / rebuild hints

- Prefer `ref.watch(provider.select((x) => x.field))` over broad watches on large drafts.
- List builders: `ListView.builder` / slivers with stable keys for purchase lines.

## Backend / SQL (to measure)

| Area | File |
|------|------|
| Trade reports | `backend/app/services/trade_query.py`, `backend/app/routers/reports_trade.py` |
| Search | `backend/app/routers/search.py` |

## Next steps

1. Record Flutter Timeline + Network for the three slowest user journeys (purchase create, reports, search).
2. Add Postgres `EXPLAIN (ANALYZE, BUFFERS)` for top 5 report queries; add indexes from `DB_CONSISTENCY_AUDIT.md`.
