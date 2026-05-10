# Database consistency audit (Phase 9)

## Principles

- Financial truth on server; migrations reversible where possible.
- Indexes for foreign keys used in filters (`business_id`, `purchase_date`, `supplier_id`).

## Suggested indexes (apply after `EXPLAIN` confirms)

See [`backend/sql/index_trade_purchases_reporting.sql`](backend/sql/index_trade_purchases_reporting.sql) (created in this milestone) for a starting `trade_purchases` reporting index.

## Nullable / legacy columns

- Audit `trade_purchase_lines` for nullable `catalog_item_id` on legacy OCR rows.
- `rate_context` JSON on lines: nullable for old rows; clients use `effectiveRateContext` fallbacks.

## Repair jobs (dry-run only in repo)

- Do **not** auto-mutate production totals without operator-approved scripts and backup.
- Optional: script to list lines where `line_total` disagrees with `line_money` + line freight (read-only report).

## OCR learning tables

- [`backend/sql/supabase_020_ocr_learning.sql`](backend/sql/supabase_020_ocr_learning.sql) — `ocr_item_aliases`, `ocr_correction_events`.
