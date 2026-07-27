ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS tax_mode VARCHAR(16) DEFAULT 'exclusive';
