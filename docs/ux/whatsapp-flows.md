# WhatsApp Flows — HEXA Purchase Assistant

**Channel:** 360dialog → Backend webhook → Same business rules as app.

---

## Principles

1. Parse (AI) → Validate (backend) → **Missing fields asked** → Preview message → **YES/NO** → Persist.
2. AI never computes profit or landing cost; backend does after structured fields are confirmed.
3. Rate limits per phone / tenant (see `docs/ops.md`).

---

## Flow A — Text Entry

```
User: "Rice 50kg 42 Ravi"
  → Webhook receives message
  → AI returns structured draft { item, qty, unit, price, supplier_name?, ... }
  → Backend validates; asks for missing (e.g. landing cost, selling price)
  → Bot: "Preview: Rice 50 kg @ ₹42, Supplier Ravi. Landing? Selling?"
  → User fills or sends next message
  → Preview full line + profit summary
  → "Reply YES to save or NO to cancel"
  → On YES: create entry; echo confirmation + short insight (from backend rules)
```

---

## Flow B — Query / PIP

```
User: "Oil 1200 ok?"
  → Resolve item "Oil", price 1200
  → Backend loads price intelligence (cached aggregates)
  → Reply with compact card: Avg, High, Low, Trend, Position %, suggestion line (negotiate / wait)
```

---

## Flow C — Overview / Analytics Snippet

```
User: "Overview"
  → Backend aggregates for default period (e.g. this month)
  → Short text + optional link to app for charts
```

---

## Flow D — Update

```
User: "Change last entry selling to 1350"
  → Identify last entry or ask clarification
  → Preview delta → YES/NO → audit log
```

---

## Flow E — Voice (Phase 4)

```
Audio message
  → STT → text → same as Flow A
  → Low confidence → "Did you mean …?"
```

---

## Flow F — Image (Phase 4)

```
Image
  → OCR → structured draft → validate → same preview/confirm
```

---

## Duplicate Detection

If draft matches **item + qty + date** with existing row:

> "Possible duplicate. Reply YES to save anyway."

---

## Error Messages (User-Facing)

- Unclear parse: ask one focused question.  
- Invalid unit: list allowed units (kg, box, piece).  
- Server error: generic retry message; log id for support.

---

## Webhook Contract (Summary)

- **Verify** 360dialog signature (secret in env).  
- **Idempotency** on message id to avoid double processing.  
- **Outbound** replies within SLA (target < 2s for simple text; async jobs for heavy OCR).

