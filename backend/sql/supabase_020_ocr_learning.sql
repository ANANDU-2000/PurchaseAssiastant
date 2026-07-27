-- OCR / scan correction learning (Supabase-compatible).
-- Apply via Supabase SQL editor or migration pipeline when ready.

create table if not exists public.ocr_item_aliases (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  raw_text text not null,
  catalog_item_id uuid not null,
  hit_count int not null default 1,
  last_used_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (business_id, raw_text)
);

create index if not exists idx_ocr_item_aliases_business
  on public.ocr_item_aliases (business_id);

create table if not exists public.ocr_correction_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  user_id uuid,
  field text not null,
  raw_value text,
  corrected_to text,
  catalog_item_id uuid,
  supplier_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_ocr_correction_events_business_created
  on public.ocr_correction_events (business_id, created_at desc);
