-- Canonical 5-unit warehouse profiles (KG / BAG / BOX / TIN / PC).
-- Data-only migration; columns unchanged.

UPDATE catalog_items
SET default_unit = 'kg',
    package_type = 'LOOSE',
    stock_unit = 'KG',
    display_unit = 'KG',
    selling_unit = COALESCE(selling_unit, 'KG')
WHERE deleted_at IS NULL
  AND (
    default_unit = 'kg'
    OR UPPER(COALESCE(package_type, '')) IN ('LOOSE', 'LOOSE_KG')
  );

UPDATE catalog_items
SET default_unit = 'bag',
    package_type = 'SACK',
    stock_unit = 'BAG',
    display_unit = 'BAG',
    selling_unit = COALESCE(selling_unit, 'BAG')
WHERE deleted_at IS NULL
  AND (
    default_unit = 'bag'
    OR UPPER(COALESCE(package_type, '')) IN ('SACK', 'WHOLESALE_BAG', 'BAG')
  );

UPDATE catalog_items
SET default_unit = 'piece',
    package_type = 'PIECE',
    stock_unit = 'PIECE',
    display_unit = 'PC',
    selling_unit = COALESCE(selling_unit, 'PCS')
WHERE deleted_at IS NULL
  AND (
    default_unit = 'piece'
    OR UPPER(COALESCE(package_type, '')) IN ('RETAIL_PACKET', 'PIECE', 'PCS')
  );

UPDATE catalog_items
SET default_unit = 'box',
    package_type = 'BOX',
    stock_unit = 'BOX',
    display_unit = 'BOX'
WHERE deleted_at IS NULL
  AND (
    default_unit = 'box'
    OR UPPER(COALESCE(package_type, '')) IN ('BOX', 'CARTON', 'CASE')
  );

UPDATE catalog_items
SET default_unit = 'tin',
    package_type = 'TIN',
    stock_unit = 'TIN',
    display_unit = 'TIN'
WHERE deleted_at IS NULL
  AND (
    default_unit = 'tin'
    OR UPPER(COALESCE(package_type, '')) IN ('TIN', 'CAN')
  );

UPDATE catalog_items
SET default_items_per_box = 1
WHERE deleted_at IS NULL
  AND default_unit = 'box'
  AND (default_items_per_box IS NULL OR default_items_per_box <= 0);
