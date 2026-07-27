BEGIN;

-- Preflight: clamp any legacy negative on-hand qty to zero before adding CHECK.
UPDATE catalog_items
SET current_stock = 0
WHERE current_stock < 0;

ALTER TABLE catalog_items
  DROP CONSTRAINT IF EXISTS chk_current_stock_non_negative;

ALTER TABLE catalog_items
  ADD CONSTRAINT chk_current_stock_non_negative
  CHECK (current_stock >= 0);

COMMIT;
