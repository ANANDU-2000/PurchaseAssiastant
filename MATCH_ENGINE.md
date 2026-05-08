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

## Required behaviors

- **Unit mismatch → low confidence / block auto-match** — user must confirm.
- Unknown entities: **confirm create**, no silent insert for supplier/broker/item when policy forbids.

## Related

- `context/rules/MASTER_CURSOR_RULES.md` (strict matching section)
