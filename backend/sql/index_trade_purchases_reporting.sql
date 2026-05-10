-- Reporting index: filter purchases by business + date (reports / dashboard).
-- Trade purchases use `status` for cancellation/deletion (no `deleted_at` column on this table).

create index if not exists idx_trade_purchases_business_purchase_date
  on trade_purchases (business_id, purchase_date desc);
