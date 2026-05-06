# AI Purchase Scanner V2 — Specification (Authoritative)

> **Audience:** every contributor and AI agent touching the scanner pipeline.
> **Status:** v2 (in build).  v1 (`/v1/me/scan-purchase`) remains live for fallback.
> **Owner module:** `backend/app/services/scanner_v2/` and `flutter_app/lib/features/purchase/.../scan_v2/`.

This document is the **single source of truth** for what the AI Purchase Scanner is, what it must do, and what it must never do. If reality drifts from this spec, fix reality or update this spec — never both implicitly.

---

## 1. Problem statement

Wholesale grocery / rice / sugar / trading shops in Kerala receive purchase information as:

- Handwritten broker notes (English / Malayalam / Manglish / mixed).
- WhatsApp text or screenshot.
- Printed supplier bill.
- Photo of paper note with shorthand (e.g. `P 56 / S 57 / delivered 36`).

We must convert that input into a **validated, editable, structured purchase entry** that ultimately becomes a single row in `trade_purchases` + N rows in `trade_purchase_lines` ([backend/app/models/trade_purchase.py](../backend/app/models/trade_purchase.py)). Wrong data here corrupts every downstream report, so accuracy and validation come before convenience.

---

## 2. Non-goals (explicit)

- We are **not** a generic invoice OCR. We do not try to support GST tax invoices for retail.
- We do **not** auto-save AI output. Every save passes through user confirmation.
- We do **not** invent values. Missing fields are returned as `null` and surfaced to the user.
- We do **not** retrain a model. "Learning" means writing rows into `catalog_aliases` (see `AI_SCANNER_MATCHING_ENGINE.md`).
- We do **not** replace the existing wizard ([purchase_entry_wizard_v2.dart](../flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart)). The scanner produces a draft that the wizard can also edit.

---

## 3. Architecture (hybrid, 7 steps)

```
┌──────────────┐  multipart   ┌───────────────────────────────┐
│ Flutter v2   │─────────────▶│ POST /v1/me/scan-purchase-v2  │
│ Scan page    │              │  (FastAPI)                    │
└──────────────┘              └───────────────────────────────┘
                                          │
                       ┌──────────────────┼──────────────────┐
                       ▼                  ▼                  ▼
               Google Vision      OpenAI multimodal     Gemini→Groq
               DOCUMENT_TEXT      (gpt-4o-mini)         (existing)
                       │                  │                  │
                       └──────────────────┼──────────────────┘
                                          ▼
                            OpenAI gpt-4o-mini text→JSON parse
                                          │
                                          ▼
                       Matching engine (rapidfuzz + CatalogAlias)
                                          │
                                          ▼
                              Bag/unit logic + Validators
                                          │
                                          ▼
                          Duplicate detector (warn, not block)
                                          │
                                          ▼
                          ScanResult JSON  +  scan_token (HMAC)
                                          │
                                          ▼
                          Flutter editable table preview
                                          │
                                          ▼
                 (user edits → /correct writes aliases)
                                          │
                                          ▼
                 POST /v1/me/scan-purchase-v2/confirm
                                          │
                                          ▼
        services.trade_purchase_service.create_trade_purchase  →  DB
```

The 7 user-visible steps you listed map to the diagram thus:

1. Flutter uploads image. → multipart POST.
2. Backend OCR extracts text. → Vision (preferred) or OpenAI multimodal.
3. LLM parses OCR text into structured JSON. → `gpt-4o-mini`.
4. Backend validation engine runs. → `validators.py`.
5. Return editable preview UI. → JSON matching `AI_SCANNER_JSON_SCHEMA.md`.
6. User confirms. → `/confirm` endpoint with `scan_token`.
7. Save validated purchase. → existing `trade_purchase_service.create_trade_purchase`.

---

## 4. Provider strategy & priority

Configured by env (`backend/.env`, see [.env.example](../.env.example)). We never log keys.


| Stage                         | Primary                                              | Secondary                                          | Tertiary                                                   |
| ----------------------------- | ---------------------------------------------------- | -------------------------------------------------- | ---------------------------------------------------------- |
| Vision/OCR                    | Google Vision (`OCR_API_KEY`) when `ENABLE_OCR=true` | OpenAI multimodal `gpt-4o-mini` (`OPENAI_API_KEY`) | Gemini Flash free (`GEMINI_API_KEY` / `GOOGLE_AI_API_KEY`) |
| Text → JSON                   | OpenAI `gpt-4o-mini`                                 | Gemini `gemini-2.0-flash`                          | Groq `llama-3.3-70b-versatile`                             |
| Embeddings (future, optional) | OpenAI `text-embedding-3-small`                      | —                                                  | —                                                          |


**Rule:** if a stage cannot be reached (no key, http error, timeout, malformed JSON) we fall through to the next provider and record the failover chain in `scan_meta.failover` of the response. We never silently fail; UI receives a non-2xx only when **all** providers fail.

---

## 5. Functional contract

### Input

- `multipart/form-data` with `image: UploadFile` (JPEG/PNG/WebP) and query `business_id: uuid`.
- Auth: same JWT Bearer used elsewhere; user must have `Membership` for `business_id`.
- Image hard limit: 8 MB (matches existing v1).

### Output

JSON exactly as defined in [AI_SCANNER_JSON_SCHEMA.md](AI_SCANNER_JSON_SCHEMA.md). Top-level fields:

- `supplier`, `broker` — `{raw_text, matched_id, matched_name, confidence}`.
- `items[]` — line items with `unit_type`, `weight_per_unit_kg`, `bags`, `total_kg`, `purchase_rate`, `selling_rate`, `line_total`, `notes`, plus match data.
- `charges` — `delivered_rate`, `billty_rate`, `freight_amount`, `discount_percent`.
- `broker_commission` — `{type: "percent"|"fixed_per_unit"|"fixed_total", value, applies_to: "kg"|"bag"|"box"|"tin"|"once"|null}`.
- `payment_days`.
- `confidence_score` (0..1).
- `needs_review` (bool, true if any field bucket < 92).
- `warnings[]` — structured `{code, severity, target, message}` (see `AI_SCANNER_VALIDATIONS.md`).
- `scan_token` — HMAC-signed payload-hash (server-only secret); required to confirm save.
- `scan_meta` — `{provider_used, failover[], parse_warnings[], image_bytes_in, ocr_chars}` (debug-only).

### Side effects

- **None.** This endpoint is read-only for `trade_purchases`. It may write to `catalog_aliases` only when the user later POSTs `/correct`.

---

## 6. Save / confirm flow

1. UI receives `ScanResult` + `scan_token`.
2. User edits any field. Edits are local only.
3. On confirm save, UI sends `POST /v1/me/scan-purchase-v2/confirm` with the **edited** payload + the original `scan_token`.
4. Server re-runs validators on the edited payload. If any blocking error → 422.
5. Server runs duplicate detection (`AI_SCANNER_DUPLICATE_PREVENTION.md`). If duplicate → 409 unless `force_duplicate=true`.
6. Server calls `trade_purchase_service.create_trade_purchase(...)` (the **only** save path; reports/PDF stay correct).
7. Server returns `{trade_purchase_id, human_id}`.

**Why `scan_token`?** To prove a save came from a real scan (so we can track scan-derived KPIs and so we can defensively rate-limit). It is **not** required for the user to keep the original AI numbers — they can edit anything.

---

## 7. Confidence policy

Per resolved entity (supplier, broker, each item):

- **score ≥ 92** → auto-select. Field shows green pill. No prompt.
- **70 ≤ score < 92** → "needs_confirmation". Field shows amber pill with "Did you mean X?" sheet listing top 3 candidates.
- **score < 70** → "unresolved". Field shows red pill. User MUST pick from a full picker before save.

`confidence_score` (top-level) = weighted average of supplier (0.25), broker (0.10), items mean (0.55), charges presence (0.10). `needs_review` = `confidence_score < 0.92` OR any field bucket below 92 OR any blocking validation warning.

---

## 8. Bag detection rules (critical)

See [AI_SCANNER_MATCHING_ENGINE.md](AI_SCANNER_MATCHING_ENGINE.md) §"Unit type detection" for the precise rules. Summary:

- If the **catalog item's `default_unit == 'BAG'`** AND name contains a recognised bag-weight token (`5/10/15/25/30/50 KG`), force `unit_type = BAG`.
- If name contains `tin` (e.g. `Ruchi 15kg tin`, `Oil 15 ltr tin`) → `unit_type = TIN` regardless of `KG` token.
- If name contains `box` or `pkt` → `unit_type = BOX`.
- If only `kg` quantity is given for a known bag product → derive `bags = round(total_kg / weight_per_unit_kg)`. If `total_kg % weight_per_unit_kg != 0` → emit warning `BAG_KG_REMAINDER`.
- Never multiply qty by name-weight when `unit_type == 'KG'`.

---

## 9. Matching engine

See [AI_SCANNER_MATCHING_ENGINE.md](AI_SCANNER_MATCHING_ENGINE.md). High-level:

1. Lookup workspace-scoped `catalog_aliases` exact (normalized) match → score 100.
2. `rapidfuzz.token_sort_ratio` against `suppliers.name`, `brokers.name`, `catalog_items.name` filtered by `business_id`.
3. Manglish/Malayalam normalization layer before scoring.
4. Bucket the score → emit `confidence` 0..1 and `match_state` ∈ `auto|needs_confirmation|unresolved`.

---

## 10. Validation engine (13 rules)

See [AI_SCANNER_VALIDATIONS.md](AI_SCANNER_VALIDATIONS.md). All rules emit structured `warnings[]` entries. Severity in `{info, warn, blocker}`. Save endpoint refuses on any `blocker`.

The 13 rules: bag count mismatch, kg mismatch, duplicate item rows, duplicate purchase entries (warn), impossible rates (negative / >1e7), missing supplier (blocker on save), unresolved broker (warn), missing quantity (blocker), wrong unit type (blocker), zero kg (warn), negative amount (blocker), malformed rate (blocker), OCR corruption (warn).

---

## 11. Duplicate prevention

See [AI_SCANNER_DUPLICATE_PREVENTION.md](AI_SCANNER_DUPLICATE_PREVENTION.md). Inherits the existing `trade_purchase_service` algorithm and adds:

- **Item-set Jaccard similarity** ≥ 0.7 across `(catalog_item_id, qty, unit_type)`.
- `**total_kg` band** of ±1 % when both rows have a derivable kg.

UI shows "POSSIBLE DUPLICATE PURCHASE" sheet listing the suspects with date/amount/items, plus an "Ignore — save anyway" button that adds `force_duplicate=true`.

---

## 12. UX rules (must-have)

See [AI_SCANNER_UI_FLOW.md](AI_SCANNER_UI_FLOW.md). The hard constraints that this spec re-affirms:

- Full-viewport **table** preview, not cards.
- Visible columns at all times: `Item · Bags · Kg · P. Rate · S. Rate · Total`.
- Per-row "more" button reveals `delivered / billty / freight / discount / tax / notes`.
- Header advanced expander (collapsed by default): `delivered · billty · freight · payment days · broker commission · discount`.
- No horizontal scroll on iPhone 16 Pro (393 × 852 pt) at default text scale.
- Sticky bottom save bar with running ₹ total.
- Autosave draft into Hive every ≤ 1 second; resume banner if app reopens with unsaved.
- `PopScope` exit guard with "Unsaved purchase will be lost" dialog.
- Confidence pills inline; tap amber → "Did you mean X?" sheet.
- All edits are local; nothing hits the server until "Save".

---

## 13. Reports & search integrity

Saved scans land in `trade_purchases` via the canonical `trade_purchase_service.create_trade_purchase`, so every existing report (`/reports/trade-items`, `/reports/trade-suppliers`, `/reports/trade-summary`) sees them automatically.

Global search ([backend/app/routers/search.py](../backend/app/routers/search.py)) is hardened to **only** show numbers that come from a real `trade_purchase_lines` row — last purchase rate, last selling rate, last supplier, last purchase date. No averages, no synthesised values. Tracked under task `search-real-only` in the plan.

---

## 14. PDF integrity

We re-touch [purchase_invoice_pdf_layout.dart](../flutter_app/lib/core/services/purchase_invoice_pdf_layout.dart):

- Remove duplicate totals blocks.
- Drop oversized hero numbers.
- Add Selling Rate column.
- Highlight supplier/broker block.
- Tighten the safe-text whitelist in `pdf_text_safe.dart` (no broken Unicode glyphs).

---

## 15. Acceptance criteria

A scanner build is "shippable" only when **all** of the following are true:

- `pytest backend/tests -q` passes (no regressions in pre-existing tests).
- All new scanner_v2 tests pass.
- `flutter analyze` 0 errors / 0 warnings (the project enforces this).
- `flutter test` all green for `test/features/purchase/scan_v2/`.
- Manual: scan a known handwritten Malayalam test image and the resulting trade purchase appears in History, Reports, and Item Detail for the same date.
- No horizontal scroll on iPhone 16 Pro device or simulator at default text scale.
- PDF export of the saved purchase shows Selling Rate column and no duplicated totals.
- `PROGRESS_TRACKER.md` updated to reflect the latest state.

See `AI_SCANNER_TODO.md` for the ordered build checklist.