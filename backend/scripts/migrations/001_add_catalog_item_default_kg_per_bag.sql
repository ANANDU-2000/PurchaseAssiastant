-- Add optional default kg/bag on catalog items (wholesale bag weight hint when default_unit = bag).
-- Run once against Postgres (Supabase) or any deployment missing this column.

ALTER TABLE catalog_items
  ADD COLUMN IF NOT EXISTS default_kg_per_bag NUMERIC(18, 4) NULL;
