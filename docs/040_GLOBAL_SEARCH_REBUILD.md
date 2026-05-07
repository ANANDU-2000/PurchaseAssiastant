# 040 — GLOBAL_SEARCH_REBUILD

## 1. PURPOSE

Provide a single, fast “global search” that reliably finds:

- Catalog items (including “SUGAR 50 KG”)
- Catalog types (category/subcategory)
- Recent purchase bills (by `human_id`, supplier, item line)
- Suppliers / brokers / contacts

and shows trader-useful **last purchase snapshot** (rate + bags/kg + last bill id) so users can act without opening multiple pages.

## 2. PROBLEM STATEMENT

Wholesale traders need instant retrieval by short queries (typos, shorthand, Malayalam/Manglish) and need to see **last buy + quantity context** to make a decision. Current search historically felt inconsistent (empty results, missing bags/kg, slow).

## 3. CURRENT FAILURE

- Search results can feel “empty” due to slow fetch / retry confusion.
- Catalog item hits sometimes only show **last rate** but not **last bags/kg** even when the matched bill is on screen.
- Users report “Searching sugar shows no results” (root cause typically: backend search ranking or frontend section filtering + debounced query state mismatch).

## 4. TARGET BEHAVIOR

- Query like `sugar`, `suger`, Malayalam transliteration variants show the right catalog item(s).
- Catalog item result row shows:
  - Item name
  - **Last buy ₹**
  - **Last qty (bags/box/tin) + kg**
  - Last bill id (`PUR-…`)
  - Source (supplier/broker) when available
- Results load quickly, with correct loading/empty/error states.

## 5. UI RULES

- **No blank screen**: always show either results, “No matches”, or a recoverable error.
- **Section chips** must not hide results unexpectedly: default is “All”.
- **Row density**: at least 8–12 results visible on common phones.
- **Result row content**:
  - Title: item / supplier / bill id
  - Subtitle: last snapshot (rate + bags/kg + last bill)
  - Tertiary line: source / period when applicable
- **Retry**: single clear retry action; no “offline” message unless confirmed failed.

## 6. BACKEND RULES

- Unified search endpoint must return structured JSON only (no prose).
- Ranking must prefer:
  - exact token matches
  - prefix matches
  - fuzzy matches (typo tolerant)
  - Malayalam transliteration (when enabled)

Backend should return enough metadata for “last snapshot” without requiring extra calls.

## 7. DATABASE RULES

- Add/maintain indexes for:
  - catalog item name + code
  - supplier/broker normalized names
  - purchase `human_id`
- If fuzzy matching uses trigram / phonetic tables, keep them workspace-scoped (business_id).

## 8. API CONTRACTS

### Endpoint

`GET /v1/me/unified-search?q=...&business_id=...`

### Response (strict JSON)

Must include arrays:

- `catalog_items[]`
- `catalog_subcategories[]`
- `recent_purchases[]`
- `suppliers[]`
- `brokers[]`

Each `catalog_items[]` row must support:

- `id`, `name`
- `last_purchase_price`, `last_selling_rate`
- `last_line_qty`, `last_line_unit`, `last_line_weight_kg` (or enough to compute)
- `last_purchase_human_id`
- `last_supplier_name`, `last_broker_name`

## 9. VALIDATION RULES

- Never show “Last buy” unless value > 0.
- If unit is bag-like and kg-per-bag exists, compute kg consistently.
- If last snapshot is missing, show `—` and keep row tappable.

## 10. ERROR HANDLING

- Errors must be trader-friendly:
  - “Search failed. Tap Retry.”
- No raw stack traces.

## 11. LOADING STATES

- While loading: show progress indicator (or skeleton list).
- If cached results exist: keep them visible and show subtle “updating” indicator.

## 12. PERFORMANCE TARGETS

- p50 < 300ms, p95 < 900ms for search response (excluding cold-start).
- Frontend render should stay under 16ms per frame for list scrolling.

## 13. CACHE RULES

- Client-side cache TTL must be short (seconds) and keyed by `(business, query)`.
- Cache must never survive logout/business switch.

## 14. REALTIME SYNC RULES

- After a purchase create/update/delete, invalidate search cache for affected tokens or use a short TTL so new bills appear quickly.

## 15. EDGE CASES

- Query is empty → show instructional empty state.
- Very short query → still show results (min length 1).
- Malayalam-only query.
- Duplicate catalog item names in different types.

## 16. FAILURE RECOVERY

- If backend search fails:
  - show Retry
  - keep cached results if available
- If partial data exists (items but no bills), still render the section.

## 17. SECURITY RULES

- Search must be business-scoped and membership-checked.
- No cross-tenant leakage in fuzzy indices.

## 18. TEST CASES

- `sugar` returns “SUGAR 50 KG”
- `suger` (typo) still returns “SUGAR 50 KG”
- Query matches a bill id: `PUR-2026-0001`
- Query matches supplier name
- Cached results show while refreshing

## 19. ACCEPTANCE CHECKLIST

- “SUGAR 50 KG” appears for `sugar`
- Catalog result row shows last buy **and** last bags/kg
- Bills section shows matching line summary
- Retry works without full-app blink

## 20. FINAL EXPECTED OUTPUT

Global search that feels instant, never empty/fake, and always shows trader-actionable context (rate + bags/kg + last bill + source).

## 19. ACCEPTANCE CHECKLIST

## 20. FINAL EXPECTED OUTPUT