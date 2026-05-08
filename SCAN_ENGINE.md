# SCAN ENGINE — notes for agents

## Scope

Purchase bill scanning (handwritten / photo) → structured **`ScanResult`** JSON → **purchase entry wizard** (`PurchaseEntryWizardV2`) → `/scan-purchase-v2/update` + `/confirm` creates purchase (when opened from scan with `scan_token`).

## Code map (verify paths after refactors)

- Backend pipeline: `backend/app/services/scanner_v3/` (and related routers under `backend/app/routers/` — search `scanPurchaseBillV3`, `scan_purchase`).
- Flutter client: `flutter_app/lib/core/api/hexa_api.dart` (`scanPurchaseBillV3StartMultipart`, `scanPurchaseBillV3Status`), thin preview UI `scan_purchase_v2_page.dart`.
- **Unified search:** `GET /v1/businesses/{id}/search` accepts optional **`supplier_id`** — ranks `catalog_items` with fuzzy relevance + supplier history (see `backend/app/routers/search.py`).
- **Unified editing:** Scan maps to `PurchaseDraft` via `flutter_app/lib/features/purchase/mapping/ai_scan_purchase_draft_map.dart`; user continues in `purchase_entry_wizard_v2.dart` at `/purchase/new` with route `extra.aiScan` (`token`, `baseScan`). Legacy `/purchase/scan-draft` redirects there if something still links to it.
- **Embedded legacy scan:** `purchase_bill_scan_panel.dart` applies the same **`/search`** catalog autocomplete pattern as AI scan v2 item edit (supplier-scoped when linked).
- After fuzzy item match, **pack gate** (`scanner_v2/pack_gate.py`) may demote `auto` matches when catalog pack kg / unit channel disagrees with the line (see `MATCH_ENGINE.md`).

## Policy

- **Vision / LLM extraction with strict JSON** — no duplicate ad-hoc parsers for the same journey.
- Preserve **raw** fields where schema allows; normalized fields for matching.
- Multi-page: **not yet first-class** — document API shape when `images[]` lands.

## Mandatory draft sequence (product policy — `MASTER_CURSOR_RULES.md`)

End-to-end: **upload → extraction → structured JSON → match engine → user-reviewed draft in purchase wizard → validation → backend totals → create.**  
The Flutter **scan page** does only upload, progress, preview, and **Continue** into **`PurchaseEntryWizardV2`**; it does not replace the wizard. Final create from scan uses **`scan_token`** + update + confirm so totals stay **backend-authoritative**.

## Logging

Prefer structured logs for: scan_token, stage transitions, validation errors, `not_a_bill` / fingerprint outcomes (no secrets, no raw API keys).

## Related docs

- `docs/AI_PURCHASE_DRAFT_ENGINE.md`
- `context/rules/AI_SCANNER_SYSTEM_PROMPT.md`
