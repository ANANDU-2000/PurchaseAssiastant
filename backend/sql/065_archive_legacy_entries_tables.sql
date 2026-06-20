-- Archive legacy entries tables (data retained, router removed).

DO $$
BEGIN
  IF to_regclass('public.entries') IS NOT NULL
     AND to_regclass('public._archived_entries') IS NULL THEN
    ALTER TABLE entries RENAME TO _archived_entries;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.entry_line_items') IS NOT NULL
     AND to_regclass('public._archived_entry_line_items') IS NULL THEN
    ALTER TABLE entry_line_items RENAME TO _archived_entry_line_items;
  END IF;
END $$;
