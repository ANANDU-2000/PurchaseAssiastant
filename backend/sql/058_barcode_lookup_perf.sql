-- Barcode lookup: item_code + barcode scan paths (business scoped).
CREATE INDEX IF NOT EXISTS idx_catalog_items_business_item_code
  ON catalog_items (business_id, item_code)
  WHERE deleted_at IS NULL AND item_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_catalog_items_business_barcode_lookup
  ON catalog_items (business_id, barcode)
  WHERE deleted_at IS NULL AND barcode IS NOT NULL;
