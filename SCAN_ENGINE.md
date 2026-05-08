# SCAN ENGINE — notes for agents

## Scope

Purchase bill scanning (handwritten / photo) → structured **`ScanResult`** JSON → draft UI → confirm creates purchase.

## Code map (verify paths after refactors)

- Backend pipeline: `backend/app/services/scanner_v3/` (and related routers under `backend/app/routers/` — search `scanPurchaseBillV3`, `scan_purchase`).
- Flutter client: `flutter_app/lib/core/api/hexa_api.dart` (`scanPurchaseBillV3StartMultipart`, `scanPurchaseBillV3Status`), UI `scan_purchase_v2_page.dart`.
- After fuzzy item match, **pack gate** (`scanner_v2/pack_gate.py`) may demote `auto` matches when catalog pack kg / unit channel disagrees with the line (see `MATCH_ENGINE.md`).

## Policy

- **Vision / LLM extraction with strict JSON** — no duplicate ad-hoc parsers for the same journey.
- Preserve **raw** fields where schema allows; normalized fields for matching.
- Multi-page: **not yet first-class** — document API shape when `images[]` lands.

## Logging

Prefer structured logs for: scan_token, stage transitions, validation errors, `not_a_bill` / fingerprint outcomes (no secrets, no raw API keys).

## Related docs

- `docs/AI_PURCHASE_DRAFT_ENGINE.md`
- `context/rules/AI_SCANNER_SYSTEM_PROMPT.md`
