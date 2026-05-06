# AI Purchase Scanner V2 — Test Cases

Every case below is implemented either as a Python unit test (`backend/tests/scanner_v2/...`), a Flutter widget test (`flutter_app/test/features/purchase/scan_v2/...`), or a manual smoke test (marked **MS**).

The goal: cover every important code path with a deterministic, reproducible scenario. Each test name maps to the table.

---

## A — Bag logic (T-A.*)

| id | scenario | input | expected |
| --- | --- | --- | --- |
| T-A.01 | sugar 50kg x 100 bag | name="Sugar 50kg", qty=100, unit=bag | unit_type=BAG, weight_per_unit_kg=50, bags=100, total_kg=5000 |
| T-A.02 | only total kg given (catalog says BAG, default 50) | name="Sugar 50kg", total_kg=5000 | bags=100, weight_per_unit_kg=50 |
| T-A.03 | total kg with remainder | name="Sugar 50kg", total_kg=4970 | warn BAG_KG_REMAINDER, bags≈99 |
| T-A.04 | barli rice 50kg | name="Barli Rice 50kg", bags=40 | total_kg=2000 |
| T-A.05 | ruchi 15kg tin | name="Ruchi 15kg tin", qty=10 | unit_type=TIN, weight_per_unit_kg=15, total_kg=150 |
| T-A.06 | oil 15 ltr tin | name="Oil 15 ltr tin", qty=10 | unit_type=TIN, total_kg=null, total_ltr if known |
| T-A.07 | KG unit no name weight | name="Pacha Ari", qty=120, unit=kg | unit_type=KG, total_kg=120, no bags |
| T-A.08 | KG unit with 50KG in name → ignored | name="Sona Masuri 50 KG", qty=200, unit=kg | warn weight_overridden_from_name absent (KG wins), total_kg=200 |
| T-A.09 | 30kg variant | "Wheat 30kg bag", qty=50 | total_kg=1500, weight=30 |
| T-A.10 | 25kg variant | "Atta 25kg", bags=80 | total_kg=2000 |
| T-A.11 | 10kg variant | "Pulses 10kg", bags=12 | total_kg=120 |
| T-A.12 | 5kg variant | "Mustard 5kg", bags=4 | total_kg=20 |
| T-A.13 | mixed unit (bag + qty kg) | name="Sugar 50kg", bags=100, total_kg=5005 | blocker BAG_COUNT_MISMATCH |
| T-A.14 | weight outside band | name="Crazy 350kg" | weight=null (sanity reject) |

---

## B — Matching engine (T-B.*)

| id | scenario | expected match | bucket |
| --- | --- | --- | --- |
| T-B.01 | "suraj" → "SURAJ TRADERS" | match | auto |
| T-B.02 | "Surya" (typo) | "SURAJ TRADERS" | needs_confirmation |
| T-B.03 | "barly" | "BARLI RICE" | needs_confirmation OR auto via alias |
| T-B.04 | "suger" | "SUGAR" | needs_confirmation |
| T-B.05 | "riyas" → broker | "RIYAS" | auto |
| T-B.06 | "kkkk" (broker shorthand) → empty if no alias | null | unresolved |
| T-B.07 | Malayalam supplier name (alias seeded) | match | auto |
| T-B.08 | random gibberish | null | unresolved |
| T-B.09 | catalog 2000 items, "soona masoori" | "SONA MASURI" | auto |
| T-B.10 | alias precedence over fuzzy | "burly" with alias "burly→BARLI" | auto |

---

## C — Validation (T-C.*)

One per code from `AI_SCANNER_VALIDATIONS.md`:

| id | rule | trigger fixture | expected severity |
| --- | --- | --- | --- |
| T-C.01 | BAG_COUNT_MISMATCH | bags=100, wpu=50, total_kg=4500 | blocker |
| T-C.02 | KG_MISMATCH | unit=kg, qty=120, total_kg=130 | blocker |
| T-C.03 | DUPLICATE_ITEM_ROW | two rows same catalog_item_id+unit_type | warn |
| T-C.04 | IMPOSSIBLE_RATE | purchase_rate=-5 | blocker |
| T-C.05 | MISSING_SUPPLIER | supplier.matched_id=null | blocker (on confirm) |
| T-C.06 | UNRESOLVED_BROKER | broker.raw_text="x", matched_id=null | warn |
| T-C.07 | MISSING_QUANTITY | bags/qty/total_kg all 0 | blocker |
| T-C.08 | WRONG_UNIT_TYPE | catalog default=BAG, scan unit=PCS | blocker |
| T-C.09 | ZERO_KG | total_kg=0, unit=BAG | warn |
| T-C.10 | NEGATIVE_AMOUNT | line_total=-100 | blocker |
| T-C.11 | MALFORMED_RATE | purchase_rate="56.789x" | blocker |
| T-C.12 | OCR_CORRUPTION | item name "Sug@@r 50kg" | warn |
| T-C.13 | LINE_TOTAL_DRIFT | server recompute differs >₹1 | warn |
| T-C.14 | GRAND_TOTAL_DRIFT | sum lines ≠ total_amount | warn |

---

## D — Duplicate prevention (T-D.*)

| id | fixture | expected |
| --- | --- | --- |
| T-D.01 | exact dup (date, supplier, amount, kg, items) | suspect score 1.0 |
| T-D.02 | amount off ₹0.5 | suspect |
| T-D.03 | amount off ₹2 | not dup |
| T-D.04 | total_kg off 0.5 % | suspect |
| T-D.05 | total_kg off 5 % | not dup |
| T-D.06 | jaccard 0.65 | not dup |
| T-D.07 | jaccard 0.8 with amount close | suspect |
| T-D.08 | supplier mismatch | not dup |
| T-D.09 | confirm with `force_duplicate=true` | row created |
| T-D.10 | confirm without flag, with suspect | 409 with payload |

---

## E — End-to-end pipeline (T-E.*)

Each test mocks Vision, OpenAI multimodal, OpenAI text JSON.

| id | scenario | expected |
| --- | --- | --- |
| T-E.01 | Happy path: vision ok → JSON ok → all auto-matched | 200 with valid ScanResult; needs_review=false; warnings=[] |
| T-E.02 | Vision fails → multimodal ok | 200 with `provider_used="openai_multimodal"`, `failover[].vision.ok=false` |
| T-E.03 | All providers fail | 502 SCAN_PROVIDERS_DOWN |
| T-E.04 | Vision returns empty | 415 OCR_NO_TEXT |
| T-E.05 | LLM returns malformed JSON twice | parse retried then 502 LLM_PARSE_FAILED |
| T-E.06 | image > 8 MB | 400 IMAGE_TOO_LARGE |
| T-E.07 | empty body | 400 EMPTY_IMAGE |
| T-E.08 | non-member business_id | 403 FORBIDDEN_BUSINESS |
| T-E.09 | broker note shorthand "P 56 / S 57 / delivered 36" | parsed: purchase_rate=56, selling_rate=57, delivered_rate=36 |
| T-E.10 | Malayalam-only image | parsed with Malayalam supplier hit via alias |
| T-E.11 | Manglish item names | matched via Manglish layer |
| T-E.12 | Two same items in one note | DUPLICATE_ITEM_ROW warn |
| T-E.13 | Confirm happy path | 200 with `trade_purchase_id`, `human_id` |
| T-E.14 | Confirm with edited rates | server recomputes line_total; persisted match edits |
| T-E.15 | Confirm with low-confidence supplier | 422 MATCH_UNRESOLVED |

---

## F — Alias learning (T-F.*)

| id | scenario | expected |
| --- | --- | --- |
| T-F.01 | user corrects "suger" → SUGAR catalog id | row inserted in `catalog_aliases` |
| T-F.02 | next scan with "suger" | match auto via alias |
| T-F.03 | duplicate correction (same raw + ref) | idempotent (no extra row) |
| T-F.04 | correction across workspaces | scoped to business_id only |
| T-F.05 | malicious type/ref_id | 400 with field error |

---

## G — Flutter UI (T-G.*) — widget tests

| id | scenario | expected |
| --- | --- | --- |
| T-G.01 | table renders 5 visible cols at 393pt | no horizontal scroll, no overflow exceptions |
| T-G.02 | tap cell to edit, change "100" → "120" | totals update locally |
| T-G.03 | dirty + back press | confirmation dialog shown |
| T-G.04 | discard → exits without save | provider state reset |
| T-G.05 | Resume banner after kill+reopen | banner offers Resume |
| T-G.06 | confidence pill green ≥92 | colour token glass.success |
| T-G.07 | confidence pill amber 70–91 | tap opens "Did you mean?" sheet |
| T-G.08 | confidence pill red <70 | save disabled until pick |
| T-G.09 | line "more" sheet edit delivered_rate | persists locally |
| T-G.10 | save success | navigates to /purchase, snack bar shown |
| T-G.11 | save 409 dup | duplicate modal shown |
| T-G.12 | save 422 validation | strip + cell underline; save disabled |
| T-G.13 | offline | scan button disabled, banner |
| T-G.14 | text scale 1.15 | layout still fits |
| T-G.15 | screen rotated landscape | column layout switches gracefully (or remains portrait if locked) |

---

## H — Manual smoke (T-H.*) — **MS**

Run before declaring the build shippable.

| id | scenario | expected |
| --- | --- | --- |
| T-H.01 | scan a real handwritten Malayalam note from a known broker | parsed, items matched, save creates trade purchase |
| T-H.02 | scan a printed supplier bill | parsed, save creates trade purchase |
| T-H.03 | scan WhatsApp screenshot | parsed |
| T-H.04 | rotate phone & re-open during edit | no layout glitch |
| T-H.05 | kill app while editing | resume banner offers draft |
| T-H.06 | save → check History, Reports, Item Detail | row visible everywhere with the same date / amount |
| T-H.07 | open the saved purchase as PDF | Selling Rate column present, no duplicated totals, no glyph corruption |
| T-H.08 | search supplier name in global search | shows real last purchase rate (or null) — never invented |
| T-H.09 | low connectivity (4G) | loading states cycle correctly, no spinner forever |
| T-H.10 | OPENAI_API_KEY removed | scan still works via Gemini fallback |

---

## Coverage targets

- Backend lines covered: ≥ 90 % for `services/scanner_v2/`.
- Flutter lines covered: ≥ 80 % for `features/purchase/state/scan_v2_provider.dart` and table widgets.
- All `blocker` validation rules: 100 %.
- Manual smoke (T-H.01 – T-H.10): all green at QA gate.
