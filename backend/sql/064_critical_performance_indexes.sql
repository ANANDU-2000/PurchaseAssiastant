-- Critical hot-path indexes (low stock SQL filter, purchase lists, staff activity, movements).

DO $$
BEGIN
  IF to_regclass('public.catalog_items') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS ix_catalog_items_low_stock_filter
      ON catalog_items (business_id, current_stock, reorder_level)
      WHERE deleted_at IS NULL
        AND reorder_level IS NOT NULL
        AND reorder_level > 0;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.trade_purchases') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS ix_trade_purchases_biz_status_date
      ON trade_purchases (business_id, status, purchase_date DESC);

    CREATE INDEX IF NOT EXISTS ix_trade_purchases_biz_delivery_open
      ON trade_purchases (business_id, delivery_status)
      WHERE delivery_status IS DISTINCT FROM 'stock_committed';
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.staff_activity_log') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS ix_staff_activity_user_biz_action_time
      ON staff_activity_log (business_id, user_id, action_type, created_at);
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.stock_movements') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS ix_stock_movements_item_created_desc
      ON stock_movements (catalog_item_id, created_at DESC);
  END IF;
END $$;
