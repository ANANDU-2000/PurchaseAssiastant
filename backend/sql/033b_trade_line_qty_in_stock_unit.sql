-- Normalized purchase line qty in catalog stock_unit (audit + rollups).
ALTER TABLE trade_purchase_lines
  ADD COLUMN IF NOT EXISTS qty_in_stock_unit NUMERIC(12, 3);

COMMENT ON COLUMN trade_purchase_lines.qty_in_stock_unit IS
  'Qty converted to catalog_items.stock_unit at confirm time (e.g. bags for SUGAR 50 KG).';
