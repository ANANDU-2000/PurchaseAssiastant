# All remaining blockers

1. Wire `ocr_learning_service` into scan **confirm** path with real `AsyncSession` upserts + RLS on `ocr_item_aliases` / `ocr_correction_events`.
2. Matcher: read aliases table before fuzzy catalog pass; cap alias hit rate to avoid poisoning.
3. Performance: measure and fix top 3 slow screens; add confirmed indexes from `EXPLAIN` (not blind).
4. Soft delete: systematic audit of every list endpoint + Flutter providers.
5. Integration tests: full purchase create E2E (API + optional Flutter `integration_test`).

**Non-blockers (nice-to-have):** Golden image tests for PDF layout; v3 scanner async UX polish.
