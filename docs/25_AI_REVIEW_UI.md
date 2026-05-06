# AI Review UI (v2)

## Layout (single scroll, no nested scroll)
Header → Hero upload card → Image preview → Scan status → Supplier/Broker → Items table → Charges → Sticky bottom actions.

## Items table (required)
Columns: `Item | Qty | Unit | P | S`
- Tap row → bottom sheet editor (compact)
- Confidence shown per row and for supplier/broker

## Sticky actions
- `Retake` / `Scan` / `Review & Create`

## Hard rules
- No raw OCR text dump
- No blank-row manual entry in main scan page
- Dense layout, minimal whitespace, iPhone 16 Pro friendly

