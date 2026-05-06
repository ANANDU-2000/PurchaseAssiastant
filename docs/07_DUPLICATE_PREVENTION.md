# 07 — Duplicate Prevention (No Double Saves / No Double Invoices)

## Prevent these duplicates

- Same invoice number saved twice for the same supplier
- Same supplier + same date + same amount + same item set (double tap / retry)
- Same scan confirmed twice (scan token replay)

## Policy

- At scan time: warn “Possible duplicate purchase”
- At confirm-save time: return 409 unless `force_duplicate=true`

## Signals

- `purchase_date`
- `supplier_id`
- `invoice_number` (when provided)
- `total_amount` tolerance ±₹1
- item fingerprint (ids + qty + package type)

## UI behaviour

409 modal shows suspects and offers:
- Open existing
- Edit
- Save anyway (forces duplicate)

