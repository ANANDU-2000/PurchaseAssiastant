BEGIN;

-- DB-001: reconcile legacy rows where opening stock exists but current_stock stayed zero.
-- Use opening_stock_qty as seed and exclude opening_stock movements to avoid double-counting.
UPDATE catalog_items ci
SET current_stock = GREATEST(
  0,
  COALESCE(ci.opening_stock_qty, 0) + COALESCE((
    SELECT SUM(sm.delta_qty)
    FROM stock_movements sm
    WHERE sm.business_id = ci.business_id
      AND sm.item_id = ci.id
      AND sm.movement_kind <> 'opening_stock'
  ), 0)
)
WHERE ci.deleted_at IS NULL
  AND COALESCE(ci.opening_stock_qty, 0) > 0
  AND COALESCE(ci.current_stock, 0) = 0;

-- DB-006: final guardrail normalization before constraints/index-heavy paths.
UPDATE catalog_items
SET current_stock = 0
WHERE deleted_at IS NULL
  AND current_stock < 0;

-- DB-007: purchase lifecycle history (event-sourced state transitions).
CREATE TABLE IF NOT EXISTS purchase_lifecycle_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id UUID NOT NULL REFERENCES trade_purchases(id) ON DELETE CASCADE,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  from_status VARCHAR(50),
  to_status VARCHAR(50) NOT NULL,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_name VARCHAR(200),
  notes TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ple_purchase
  ON purchase_lifecycle_events(purchase_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ple_business
  ON purchase_lifecycle_events(business_id, created_at DESC);

-- DB-005: delivery discrepancy tracking.
CREATE TABLE IF NOT EXISTS delivery_discrepancies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  purchase_id UUID NOT NULL REFERENCES trade_purchases(id) ON DELETE CASCADE,
  purchase_line_id UUID REFERENCES trade_purchase_lines(id) ON DELETE SET NULL,
  catalog_item_id UUID REFERENCES catalog_items(id) ON DELETE SET NULL,
  ordered_qty NUMERIC(12, 3) NOT NULL,
  received_qty NUMERIC(12, 3) NOT NULL,
  damage_qty NUMERIC(12, 3) NOT NULL DEFAULT 0,
  missing_qty NUMERIC(12, 3) NOT NULL DEFAULT 0,
  discrepancy_type VARCHAR(50) CHECK (discrepancy_type IN ('short', 'damage', 'over', 'mixed')),
  truck_number VARCHAR(100),
  driver_name VARCHAR(200),
  invoice_number VARCHAR(100),
  broker_id UUID,
  notes TEXT,
  photo_urls TEXT[] NOT NULL DEFAULT '{}',
  reported_by UUID REFERENCES users(id) ON DELETE SET NULL,
  reported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_dd_purchase
  ON delivery_discrepancies(purchase_id);
CREATE INDEX IF NOT EXISTS idx_dd_business_date
  ON delivery_discrepancies(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dd_unresolved
  ON delivery_discrepancies(business_id, resolved_at)
  WHERE resolved_at IS NULL;

-- Older production DBs may not have public.contacts; add FK only when present.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'contacts'
  ) THEN
    ALTER TABLE delivery_discrepancies
      DROP CONSTRAINT IF EXISTS delivery_discrepancies_broker_id_fkey;
    ALTER TABLE delivery_discrepancies
      ADD CONSTRAINT delivery_discrepancies_broker_id_fkey
      FOREIGN KEY (broker_id)
      REFERENCES contacts(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- DB-002 / DB-008: performance indexes for hot paths (lines table may lack business_id/created_at).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'trade_purchase_lines' AND column_name = 'business_id'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'trade_purchase_lines' AND column_name = 'created_at'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'trade_purchase_lines' AND column_name = 'deleted_at'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_tpl_biz_date_item
      ON trade_purchase_lines(business_id, created_at DESC, catalog_item_id)
      WHERE deleted_at IS NULL;
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'trade_purchase_lines' AND column_name = 'business_id'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'trade_purchase_lines' AND column_name = 'created_at'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_tpl_biz_date_item
      ON trade_purchase_lines(business_id, created_at DESC, catalog_item_id);
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'trade_purchase_lines' AND column_name = 'created_at'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_tpl_biz_date_item
      ON trade_purchase_lines(created_at DESC, catalog_item_id);
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'trade_purchase_lines' AND column_name = 'catalog_item_id'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_tpl_biz_date_item
      ON trade_purchase_lines(catalog_item_id)
      WHERE catalog_item_id IS NOT NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'trade_purchase_lines'
      AND column_name = 'deleted_at'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_trade_purchase_lines_catalog_item_id
      ON trade_purchase_lines(catalog_item_id)
      WHERE deleted_at IS NULL AND catalog_item_id IS NOT NULL;
  ELSE
    CREATE INDEX IF NOT EXISTS idx_trade_purchase_lines_catalog_item_id
      ON trade_purchase_lines(catalog_item_id)
      WHERE catalog_item_id IS NOT NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'stock_movements'
      AND column_name = 'business_id'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_stock_movements_item_date
      ON stock_movements(item_id, created_at DESC)
      WHERE business_id IS NOT NULL;
  ELSE
    CREATE INDEX IF NOT EXISTS idx_stock_movements_item_date
      ON stock_movements(item_id, created_at DESC);
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'staff_activity_log'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_staff_activity_log_biz_date
      ON staff_activity_log(business_id, created_at DESC);
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'trade_purchases'
      AND column_name = 'deleted_at'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_trade_purchases_biz_status_date
      ON trade_purchases(business_id, status, created_at DESC)
      WHERE deleted_at IS NULL;
  ELSE
    CREATE INDEX IF NOT EXISTS idx_trade_purchases_biz_status_date
      ON trade_purchases(business_id, status, created_at DESC);
  END IF;
END $$;

-- Ensure barcode uniqueness index exists without creating a duplicate physical index.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'catalog_items'
      AND indexdef ILIKE '%(business_id, barcode)%'
      AND indexdef ILIKE '%WHERE barcode IS NOT NULL%'
      AND indexdef ILIKE '%deleted_at IS NULL%'
  ) THEN
    CREATE UNIQUE INDEX idx_catalog_items_barcode_business
      ON catalog_items(business_id, barcode)
      WHERE barcode IS NOT NULL AND deleted_at IS NULL;
  END IF;
END $$;

-- DB-009: add optional pin flag + cleanup helper for stale saved views.
ALTER TABLE report_saved_views
  ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS ix_report_saved_views_created_at
  ON report_saved_views(created_at DESC);

CREATE OR REPLACE FUNCTION cleanup_report_saved_views(retention interval DEFAULT interval '1 year')
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  DELETE FROM report_saved_views
  WHERE created_at < now() - retention
    AND COALESCE(is_pinned, false) = false;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

COMMIT;
