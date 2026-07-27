ALTER TABLE catalog_items
  ADD COLUMN IF NOT EXISTS public_token VARCHAR(64);

UPDATE catalog_items
SET public_token = md5(random()::text || clock_timestamp()::text || id::text)
WHERE public_token IS NULL OR public_token = '';

ALTER TABLE catalog_items
  ALTER COLUMN public_token SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_catalog_items_public_token
  ON catalog_items(public_token);

