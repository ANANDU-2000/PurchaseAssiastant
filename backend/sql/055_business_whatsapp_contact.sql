-- Migration 055: accounts staff WhatsApp for purchase order sharing
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS accounts_whatsapp_number VARCHAR(20);
