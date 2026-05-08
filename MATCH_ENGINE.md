# MATCH ENGINE — notes for agents

## Goal

Map extracted strings → **existing** suppliers, brokers, catalog items with **confidence** and **unit/pack safety**. Never silently match incompatible retail vs wholesale SKUs.

## Intended priority

1. Exact alias (DB)  
2. Normalized exact  
3. Supplier purchase history  
4. Unit / pack-size consistency  
5. Bag/kg consistency vs item master  
6. Trigram / fuzzy (Postgres `pg_trgm` when enabled)  
7. Semantic / embedding fallback (optional, last)

## Code map

- Search unified endpoints: `backend/app/routers/search.py` (and related services).
- Scanner normalization / candidate attachment: scanner v2/v3 pipeline modules (`scanner_v3/pipeline.py`, matchers).
- **Pack-size / unit-channel gate (P0 safety):** after fuzzy match, `scanner_v2/pack_gate.py` demotes `auto` → `needs_confirmation` when kg hints or unit channel (bag vs piece) conflict with `CatalogItem` (`default_kg_per_bag`, name kg token, `default_unit`). Wired from `scanner_v2/pipeline.py` `_match_items` (used by v3).

## Required behaviors

- **Unit mismatch → low confidence / block auto-match** — user must confirm.
- Unknown entities: **confirm create**, no silent insert for supplier/broker/item when policy forbids.

## Related

- `context/rules/MASTER_CURSOR_RULES.md` (strict matching section)
