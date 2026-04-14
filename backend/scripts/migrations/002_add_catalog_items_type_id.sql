-- Category → Type → Item: optional type_id on catalog_items (older DBs may lack this column).
-- Run once on Postgres (Supabase / Render) if startup ALTER did not run or failed.

ALTER TABLE catalog_items
  ADD COLUMN IF NOT EXISTS type_id UUID NULL;

CREATE INDEX IF NOT EXISTS ix_catalog_items_type_id ON catalog_items (type_id);

-- FK only when category_types exists (created by app migrations / create_all).
DO $migration$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'category_types')
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint WHERE conname = 'catalog_items_type_id_fkey'
     ) THEN
    ALTER TABLE catalog_items
      ADD CONSTRAINT catalog_items_type_id_fkey
      FOREIGN KEY (type_id) REFERENCES category_types(id) ON DELETE SET NULL;
  END IF;
END
$migration$;
