# Trade purchase — client payload contract (v2)

`PurchaseDraft` in `lib/features/purchase/domain/purchase_draft.dart` maps 1:1 to FastAPI `TradePurchaseCreateRequest` (`backend/app/schemas/trade_purchases.py`).

## Header (optional unless noted)

- `purchase_date` — ISO `yyyy-MM-dd` (required in API)
- `invoice_number` — string, max 64, sent only if non-empty
- `supplier_id` — UUID string, **required for save** (enforced in UI + server)
- `broker_id` — UUID, only if set
- `status` — always `confirmed` on save from wizard
- `payment_days` — int 0..3650, only if set
- `discount` — header discount **percent** (0–100), only if &gt; 0; maps to `headerDiscountPercent` in draft
- `commission_percent` — broker % on net after line math, only if &gt; 0
- `delivered_rate`, `billty_rate` — non-negative, sent if parsed
- `freight_amount` — only if &gt; 0
- `freight_type` — `included` or `separate`

## Lines (`lines[]`)

Each `PurchaseLineDraft` → `TradePurchaseLineIn`:

- `item_name` — required
- `qty` — &gt; 0
- `unit` — required, max 32
- `landing_cost` — **required, &gt; 0** (no separate “rate” field)
- `catalog_item_id` — optional UUID
- `selling_cost` — optional, maps from `sellingPrice` in client
- `tax_percent` — optional
- `discount` — line discount %, maps from `lineDiscountPercent`

HSN and other API-only fields are omitted unless added later (optional on API).

## Totals

Single source: `strictFooterBreakdown` + `computeTradeTotals` in
`lib/features/purchase/state/purchase_draft_provider.dart` (same math as previous wizard).
