# AI Purchase Scanner V2 — Matching Engine

The matcher resolves three entity classes from raw OCR/LLM text:

1. **Supplier** (`suppliers.name`, `business_id`-scoped).
2. **Broker** (`brokers.name`, `business_id`-scoped).
3. **Catalog item** (`catalog_items.name`, `business_id`-scoped, optional `category_id` filter).

Output (per entity): `(matched_id, matched_name, confidence ∈ [0,1], match_state ∈ {auto, needs_confirmation, unresolved}, candidates[])`.

Entry point: `backend/app/services/scanner_v2/matcher.py`.

---

## 1. Pipeline

```
raw_text
  │
  ▼  normalize()  (lowercase, NFKC, strip punctuation, collapse whitespace)
  │
  ▼  Manglish/Malayalam transliteration layer
  │
  ▼  exact alias hit  (catalog_aliases.normalized_name == query)  → score 100
  │
  ▼  rapidfuzz.token_sort_ratio + rapidfuzz.partial_ratio (max of both)
  │
  ▼  bucket → {auto ≥92, needs_confirmation 70–91, unresolved <70}
  │
  ▼  return top-3 candidates (always)
```

Aliases short-circuit fuzzy match because they encode user-confirmed corrections. No single-character or empty alias is ever inserted.

---

## 2. Normalization

```python
def normalize(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).lower().strip()
    s = re.sub(r"[\u200b-\u200f\ufeff]", "", s)         # zero-width
    s = re.sub(r"[^\w\u0d00-\u0d7f\s]", " ", s)         # keep word chars + Malayalam block
    s = re.sub(r"\s+", " ", s).strip()
    return s
```

Examples:

| input | normalize |
| --- | --- |
| `"SURAJ TRADERS  "` | `"suraj traders"` |
| `"Suger 50 KG."` | `"suger 50 kg"` |
| `"ബാർലി റൈസ്"` | `"ബാർലി റൈസ്"` |
| `"BARLI Rice 50KG"` | `"barli rice 50kg"` |

---

## 3. Manglish / Malayalam transliteration

Manglish is Malayalam written in Latin letters. We do not run a full transliterator (overkill); instead we apply a rule table on common trader vocabulary and Malayalam Unicode block matches:

```python
MANGLISH_TO_EN = {
    "ari":   "rice",
    "ari ":  "rice ",
    "pacha ari": "raw rice",
    "pacha":  "raw",
    "ponni":  "ponni",
    "soona":  "sona",
    "barli":  "barley",
    "barly":  "barley",
    "suger":  "sugar",
    "shakkara": "sugar",
    "kachiya": "boiled",
    "matta":  "matta",
    "thuvarra": "tur",
    "uzhunnu": "urad",
    "cheru pa-yar": "green gram",
    "cheru payar": "green gram",
}
```

Plus generic OCR fixes (`0` ↔ `o`, `1` ↔ `l/i` only when surrounded by digits, etc.).

For Malayalam-script input, we additionally compute a transliteration to Latin (rough) and fuzzy-match against catalog. We keep both candidate sets and take the **max** score.

---

## 4. Alias precedence

`catalog_aliases` ([backend/app/models/ai_engine.py](../backend/app/models/ai_engine.py)) holds workspace-specific user corrections. Lookup order:

1. `alias_type` matches the entity class.
2. `business_id == ctx.business_id`.
3. `normalized_name == normalize(raw_text)`.

If hit, `confidence = 1.0`, `match_state = auto`. We still populate `candidates` (top 2 fuzzy alternatives) for transparency.

If multiple aliases collide (rare), we pick the **most recent** by `created_at` and emit `parse_warnings += ["alias_collision"]`.

---

## 5. Fuzzy matching

We use `rapidfuzz` (already in [requirements.txt](../backend/requirements.txt)). Two scorers blended:

```python
score = max(
    fuzz.token_sort_ratio(q, candidate),
    fuzz.partial_ratio(q, candidate),
    fuzz.WRatio(q, candidate)            # rapidfuzz weighted ratio for short strings
)
```

We pick the per-candidate maximum, then rank descending. For shorter queries (< 4 chars) we require `partial_ratio ≥ 95` to count, otherwise we down-weight to avoid false positives.

The matcher draws candidates from this SQL (one query per type):

```sql
-- supplier
SELECT id, name FROM suppliers WHERE business_id = :bid
-- broker
SELECT id, name FROM brokers   WHERE business_id = :bid
-- item
SELECT id, name FROM catalog_items WHERE business_id = :bid
```

For very large catalogs we add a SQL `ILIKE %first_token%` shortlist before scoring (only when count > 500).

---

## 6. Confidence buckets

```
score ≥ 92  → auto-select          → match_state=auto
70..91      → needs_confirmation   → ask "Did you mean X?"
<70         → unresolved            → red, picker required
```

`confidence` field is `score / 100`. We propagate `match_state` to the UI for pill colour and gating.

---

## 7. Top-3 candidates

We always return up to 3 alternatives ordered by score with their own normalized confidence, so the UI can render "Did you mean?" sheets without a second round-trip.

```python
def top_candidates(query: str, rows: list[tuple[uuid, str]], limit: int = 3) -> list[Candidate]:
    ranked = rank_ids_by_token_sort(query, rows, limit=limit, score_cutoff=55)
    return [Candidate(id=uid, name=name_by_id[uid], confidence=score/100) for uid, score in ranked]
```

---

## 8. Unit type detection (item-only, post-match)

Sequence:

1. **Catalog wins.** If `matched_catalog_item_id` is set and `catalog_items.default_unit` is non-null → that wins.
2. **Suffix tokens.** Inspect raw_name (case-insensitive):
   - `tin`, `tins`, `\d+ ?ltr ?tin` → `TIN`.
   - `box`, `pkt`, `packet` → `BOX`.
   - `bag`, `bags`, `sack` → `BAG`.
   - `pcs`, `piece`, `pc` → `PCS`.
   - `kgs?` (without bag/tin/box context) → `KG`.
   - `ltr`, `liter` (without tin) → `LTR`.
3. **Default-unit + KG token.** If catalog's `default_unit` is BAG and name contains `5 KG | 10 KG | 15 KG | 25 KG | 30 KG | 50 KG` → unit_type=BAG. This is the rule from your spec; the KG token marks weight-per-bag, not quantity.
4. **Fallback.** If still ambiguous → `unit_type = catalog.default_unit ?? 'KG'`.

### Weight-per-unit derivation

```python
def infer_weight_per_unit_kg(name: str) -> Decimal | None:
    m = re.search(r"(\d{1,3}(?:\.\d{1,2})?)\s*KG\b", name.upper())
    if not m: return None
    v = Decimal(m.group(1))
    if v <= 0 or v > 200: return None        # sanity band; sacks ≤ 200 kg
    return v
```

If catalog provides `default_kg_per_bag` we prefer that and only override when name explicitly contradicts (with `parse_warning: "weight_overridden_from_name"`).

### Bag↔kg back-fill (the spec's auto-conversion)

```python
def normalize_bag_kg(item):
    wpu = item.weight_per_unit_kg
    if item.unit_type == "BAG":
        if item.bags and wpu and not item.total_kg:
            item.total_kg = item.bags * wpu
        elif item.total_kg and wpu and not item.bags:
            item.bags = (item.total_kg / wpu).quantize(0)
            if item.bags * wpu != item.total_kg:
                item.warnings.append("BAG_KG_REMAINDER")
    elif item.unit_type == "KG":
        item.bags = None                         # never spurious bags
        if item.qty and not item.total_kg:
            item.total_kg = item.qty
```

The spec example `Sugar 50kg x 100 bag → bag_count=100, weight_per_bag=50, total_kg=5000` is exactly this code path applied.

---

## 9. Determinism

The matcher is **pure**: same DB state + same input → same output. No random tie-breaking. Ties on equal score resolve by lexical name asc.

## 10. Workspace isolation

Every SQL query filters by `business_id`. We never expose suppliers/items from a different workspace. Aliases likewise scoped.

## 11. Performance

- Per query: at most 3 SQL SELECTs (supplier, broker, item rows). With shortlist by `ILIKE` on first token when catalog > 500 items.
- Fuzzy scoring is in-process Rust (rapidfuzz) — sub-millisecond for typical Kerala catalog sizes (≤ 2 000 items).
- Whole match call budget: ≤ 100 ms.

## 12. Caching

We do not cache aliases or rows in-process — the DB is fast enough and we want fresh data after `/correct` writes. If profiling shows otherwise, we can add an `lru_cache` keyed by `(business_id, schema_version)`.

## 13. Tests (`backend/tests/scanner_v2/test_matcher_buckets.py`)

| input | expected match | bucket |
| --- | --- | --- |
| `suraj` | SURAJ TRADERS | auto |
| `surya` (when typo) | SURAJ TRADERS | needs_confirmation |
| `randomgibberish` | None | unresolved |
| `barly` | BARLI RICE | needs_confirmation OR auto via alias if seeded |
| `suger` | SUGAR (catalog) | needs_confirmation |
| `riyas` | RIYAS (broker) | auto |
| Malayalam `സുരാജ്` (when seed has it) | SURAJ TRADERS | auto via alias |

These cases double as the integration-level acceptance gates.
