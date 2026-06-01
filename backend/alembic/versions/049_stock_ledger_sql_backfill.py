"""Backfill stock_movements from legacy adjustment log + missing committed POs."""

from alembic import op

revision = "049_stock_ledger_sql_backfill"
down_revision = "048_stock_commit_backfill_guards"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        -- Phase 1: legacy stock_adjustment_log → stock_movements (idempotent)
        INSERT INTO stock_movements (
          id, business_id, item_id, movement_kind, delta_qty, qty_before, qty_after,
          stock_unit, reason, source_type, source_id, idempotency_key,
          actor_id, actor_name, metadata_json, created_at
        )
        SELECT
          gen_random_uuid(),
          sal.business_id,
          sal.item_id,
          CASE sal.adjustment_type
            WHEN 'purchase' THEN 'delivery_receive'
            WHEN 'verification' THEN 'physical_count'
            WHEN 'opening_stock' THEN 'opening_stock'
            ELSE 'correction'
          END,
          sal.new_qty - sal.old_qty,
          sal.old_qty,
          sal.new_qty,
          COALESCE(ci.stock_unit, ci.default_unit, ci.selling_unit),
          sal.reason,
          'legacy_adjustment',
          sal.id,
          'legacy_adj:' || sal.id::text,
          sal.updated_by,
          sal.updated_by_name,
          jsonb_build_object('legacy_adjustment_id', sal.id::text),
          sal.updated_at
        FROM stock_adjustment_log sal
        JOIN catalog_items ci ON ci.id = sal.item_id
        WHERE NOT EXISTS (
          SELECT 1 FROM stock_movements sm
          WHERE sm.idempotency_key = 'legacy_adj:' || sal.id::text
        );

        -- Phase 2: missing delivery_receive for stock_committed POs
        WITH line_qty AS (
          SELECT
            tp.id AS purchase_id,
            tp.business_id,
            tp.user_id AS actor_id,
            tp.human_id,
            COALESCE(tp.stock_committed_at, tp.delivered_at, tp.updated_at) AS committed_at,
            tpl.catalog_item_id AS item_id,
            SUM(
              CASE
                WHEN tpl.received_qty IS NOT NULL AND tpl.qty IS NOT NULL AND tpl.qty > 0
                  THEN ROUND(
                    COALESCE(tpl.qty_in_stock_unit, tpl.qty) * tpl.received_qty / tpl.qty,
                    3
                  )
                ELSE COALESCE(tpl.qty_in_stock_unit, tpl.qty, 0)
              END
            ) AS delta_qty
          FROM trade_purchases tp
          JOIN trade_purchase_lines tpl ON tpl.trade_purchase_id = tp.id
          WHERE tp.delivery_status = 'stock_committed'
            AND tp.status NOT IN ('deleted', 'cancelled')
            AND tpl.catalog_item_id IS NOT NULL
          GROUP BY
            tp.id, tp.business_id, tp.user_id, tp.human_id,
            tp.stock_committed_at, tp.delivered_at, tp.updated_at,
            tpl.catalog_item_id
          HAVING SUM(
            CASE
              WHEN tpl.received_qty IS NOT NULL AND tpl.qty IS NOT NULL AND tpl.qty > 0
                THEN COALESCE(tpl.qty_in_stock_unit, tpl.qty) * tpl.received_qty / tpl.qty
              ELSE COALESCE(tpl.qty_in_stock_unit, tpl.qty, 0)
            END
          ) > 0
        ),
        eligible AS (
          SELECT lq.*
          FROM line_qty lq
          WHERE NOT EXISTS (
            SELECT 1 FROM stock_movements sm
            WHERE sm.idempotency_key =
              'trade_purchase:' || lq.purchase_id::text || ':' || lq.item_id::text
          )
          AND NOT EXISTS (
            SELECT 1 FROM stock_adjustment_log sal
            WHERE sal.item_id = lq.item_id
              AND sal.adjustment_type = 'purchase'
              AND sal.reason ILIKE '%' || lq.human_id || '%'
          )
        ),
        ordered AS (
          SELECT
            e.*,
            ROW_NUMBER() OVER (
              PARTITION BY e.item_id ORDER BY e.committed_at, e.purchase_id
            ) AS seq
          FROM eligible e
        ),
        base AS (
          SELECT
            o.item_id,
            COALESCE(
              (
                SELECT sm.qty_after
                FROM stock_movements sm
                WHERE sm.item_id = o.item_id
                ORDER BY sm.created_at DESC, sm.id DESC
                LIMIT 1
              ),
              0
            ) AS base_qty
          FROM (SELECT DISTINCT item_id FROM ordered) o
        ),
        with_running AS (
          SELECT
            o.purchase_id,
            o.business_id,
            o.actor_id,
            o.human_id,
            o.committed_at,
            o.item_id,
            o.delta_qty,
            b.base_qty
              + COALESCE(
                  SUM(o.delta_qty) OVER (
                    PARTITION BY o.item_id ORDER BY o.seq
                    ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                  ),
                  0
                ) AS qty_before
          FROM ordered o
          JOIN base b ON b.item_id = o.item_id
        )
        INSERT INTO stock_movements (
          id, business_id, item_id, movement_kind, delta_qty, qty_before, qty_after,
          stock_unit, reason, source_type, source_id, idempotency_key,
          actor_id, actor_name, metadata_json, created_at
        )
        SELECT
          gen_random_uuid(),
          wr.business_id,
          wr.item_id,
          'delivery_receive',
          wr.delta_qty,
          wr.qty_before,
          wr.qty_before + wr.delta_qty,
          COALESCE(ci.stock_unit, ci.default_unit, ci.selling_unit),
          'Purchase received (' || wr.human_id || ')',
          'trade_purchase',
          wr.purchase_id,
          'trade_purchase:' || wr.purchase_id::text || ':' || wr.item_id::text,
          wr.actor_id,
          COALESCE(u.name, u.username, u.email, 'System'),
          jsonb_build_object(
            'purchase_id', wr.purchase_id::text,
            'human_id', wr.human_id,
            'backfill', true
          ),
          wr.committed_at
        FROM with_running wr
        JOIN catalog_items ci ON ci.id = wr.item_id
        LEFT JOIN users u ON u.id = wr.actor_id
        WHERE NOT EXISTS (
          SELECT 1 FROM stock_movements sm
          WHERE sm.idempotency_key =
            'trade_purchase:' || wr.purchase_id::text || ':' || wr.item_id::text
        );

        -- Phase 3: sync catalog_items.current_stock from ledger tail
        UPDATE catalog_items ci
        SET
          current_stock = lb.qty_after,
          last_stock_updated_at = NOW()
        FROM (
          SELECT DISTINCT ON (item_id)
            item_id,
            qty_after
          FROM stock_movements
          ORDER BY item_id, created_at DESC, id DESC
        ) lb
        WHERE ci.id = lb.item_id
          AND ci.deleted_at IS NULL;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DELETE FROM stock_movements
        WHERE idempotency_key LIKE 'legacy_adj:%'
           OR (metadata_json->>'backfill')::boolean IS TRUE;
        """
    )
