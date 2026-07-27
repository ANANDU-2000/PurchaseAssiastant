-- Purchase delivery pipeline (PLAN.MD V2 Task 3)
ALTER TABLE trade_purchases
  ADD COLUMN IF NOT EXISTS delivery_status VARCHAR(30) NOT NULL DEFAULT 'pending'
    CHECK (delivery_status IN (
      'pending','dispatched','in_transit','arrived',
      'staff_verifying','staff_verified','stock_committed','partial','cancelled'
    )),
  ADD COLUMN IF NOT EXISTS dispatched_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS arrived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS staff_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS staff_verified_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS staff_verified_by_name VARCHAR(255),
  ADD COLUMN IF NOT EXISTS stock_committed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS staff_verified_qty NUMERIC(12,3),
  ADD COLUMN IF NOT EXISTS truck_number VARCHAR(100),
  ADD COLUMN IF NOT EXISTS driver_contact VARCHAR(100);

UPDATE trade_purchases
SET delivery_status = 'stock_committed'
WHERE is_delivered = TRUE AND delivery_status = 'pending';
