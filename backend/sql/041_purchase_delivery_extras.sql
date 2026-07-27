-- Purchase delivery pipeline extras (dispatch_note, committed qty, index)
ALTER TABLE trade_purchases
  ADD COLUMN IF NOT EXISTS dispatch_note TEXT,
  ADD COLUMN IF NOT EXISTS delivered_qty_committed NUMERIC(12,3);

CREATE INDEX IF NOT EXISTS ix_trade_purchases_delivery_status
  ON trade_purchases (business_id, delivery_status, created_at DESC);
