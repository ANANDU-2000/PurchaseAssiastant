# 105 — SCAN_REVIEW_SCREEN

## Layout requirements

### Top

- Full image preview (zoomable)

### Middle

- Live extracted fields:
  - Supplier (editable)
  - Broker (editable)
  - Payment days (editable)
  - Charges (delivered/billty/freight/discount) when detected

### Bottom

- Editable detected rows:
  - Item
  - Qty + Unit
  - Package size (kg per bag, etc.)
  - Purchase / Selling / Delivered rates
  - Auto-calculated totals (kg + amount)

### Sticky actions

- **Retake**
- **Edit**
- **Create Purchase**

## Non-empty rule

If *anything* is detected, show it. Never show an empty review state.

