-- Production catalog unit profile repair (run once after review in staging).
-- Harisree: default_unit is warehouse truth; stock_unit/package_type should align.

-- 1) Wholesale bag items: stock_unit should be BAG (not KG).
UPDATE catalog_items
SET
  stock_unit = 'BAG',
  package_type = COALESCE(NULLIF(package_type, ''), 'SACK'),
  package_measurement = COALESCE(package_measurement, 'KG'),
  package_size = COALESCE(package_size, default_kg_per_bag),
  validation_status = 'unit_profile_verified'
WHERE deleted_at IS NULL
  AND default_unit = 'bag'
  AND default_kg_per_bag IS NOT NULL
  AND default_kg_per_bag >= 20;

-- 2) Retail packets mis-tagged as bag (5–19 kg per "bag" — really per piece).
UPDATE catalog_items
SET
  default_unit = 'piece',
  stock_unit = 'PIECE',
  package_type = 'RETAIL_PACKET',
  package_measurement = 'KG',
  package_size = default_kg_per_bag,
  validation_status = 'unit_profile_verified'
WHERE deleted_at IS NULL
  AND default_unit = 'bag'
  AND default_kg_per_bag IS NOT NULL
  AND default_kg_per_bag > 0
  AND default_kg_per_bag < 20;

-- 3) Loose kg items
UPDATE catalog_items
SET
  stock_unit = 'KG',
  package_type = COALESCE(NULLIF(package_type, ''), 'LOOSE'),
  validation_status = 'unit_profile_verified'
WHERE deleted_at IS NULL
  AND default_unit = 'kg'
  AND (stock_unit IS NULL OR stock_unit <> 'KG');

-- Verify (read-only):
-- SELECT name, default_unit, stock_unit, package_type, default_kg_per_bag, current_stock
-- FROM catalog_items WHERE UPPER(name) LIKE '%SUGAR 50%' AND deleted_at IS NULL;
