## SCANNER VALIDATION (QUALITY GATES)

Scanner output is **unsafe** unless all gates below are satisfied or explicitly confirmed by the user.

---

## Gate A — Supplier / Broker matching

- **Supplier matched**:
  - Supplier is selected from directory (has `supplier_id`)
  - OR user explicitly confirms free-text supplier name
- **Broker**:
  - Optional, but if present it must be selected from directory OR explicitly confirmed

Fail behavior:

- Block Apply if supplier is missing or not confirmed.

---

## Gate B — Line completeness (per row)

For every line row:

- item_name present and not placeholder
- qty > 0
- unit is valid (`kg|bag|sack|box|tin|ltr|unit`)
- purchase_rate > 0

Fail behavior:

- Block Apply and highlight the row/field.

---

## Gate C — Weight math consistency

Rules:

- If unit is **KG**:
  - `line_kg = qty`
  - **Do not** apply name weight (`50 KG`) as a multiplier
- If unit is **BAG/SACK**:
  - If kg/unit is known (from catalog or name): validate qty × kgPerUnit
  - If kg/unit unknown: allow but mark as “weight unknown” (no silent inference unless explicitly shown)
- If unit is **BOX/TIN**:
  - If name has `X KG` and treated as single-pack weight: validate qty × X
  - Else weight may be unknown until user fills box/tin geometry fields

Fail behavior:

- If computed kg is inconsistent with explicit total_weight snapshot (when present) beyond tolerance → show warning and require user confirmation.

---

## Gate D — Rate sanity

- purchase_rate must be reasonable (>0)
- if selling_rate present:
  - allow selling < purchase (loss), but show warning badge
- if both P and S are missing/0 → block Apply

---

## Gate E — Duplicates

- Duplicate item rows (same normalized item name + same unit) should be merged or flagged.
- If duplicates exist: show warning and allow user to merge or confirm.

---

## Gate F — Preview confirmation

Before applying:

- Show preview table + totals
- User must tap a confirmation action (Apply)
- If any warnings exist, show a “Review warnings” section

---

## Validation checklist (developer)

- OCR failure still allows manual edit
- LLM failure falls back to heuristic parser
- “Apply to purchase” never saves to DB directly
- All blocking rules enforced consistently