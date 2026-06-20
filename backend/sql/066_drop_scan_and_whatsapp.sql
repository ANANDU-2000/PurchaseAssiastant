-- Drop AI bill scan tables and WhatsApp contact columns (feature removed).

DROP TABLE IF EXISTS purchase_scan_traces CASCADE;
DROP TABLE IF EXISTS catalog_aliases CASCADE;

ALTER TABLE businesses DROP COLUMN IF EXISTS accounts_whatsapp_number;
ALTER TABLE suppliers DROP COLUMN IF EXISTS whatsapp_number;
ALTER TABLE brokers DROP COLUMN IF EXISTS whatsapp_number;
