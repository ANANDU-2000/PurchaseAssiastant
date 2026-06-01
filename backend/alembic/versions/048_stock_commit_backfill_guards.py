"""Backfill committed qty and add stock movement lookup index."""

from alembic import op

revision = "048_stock_commit_backfill_guards"
down_revision = "047_purchase_line_received_qty"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_stock_movements_purchase_lookup
        ON stock_movements (business_id, source_type, source_id, item_id, movement_kind);
        """
    )
    op.execute(
        """
        WITH committed_qty AS (
          SELECT
            tp.id AS purchase_id,
            COALESCE(
              SUM(
                CASE
                  WHEN tpl.received_qty IS NOT NULL AND tpl.qty IS NOT NULL AND tpl.qty > 0
                    THEN COALESCE(tpl.qty_in_stock_unit, tpl.qty) * tpl.received_qty / tpl.qty
                  ELSE COALESCE(tpl.qty_in_stock_unit, tpl.qty, 0)
                END
              ),
              0
            ) AS committed_qty
          FROM trade_purchases tp
          JOIN trade_purchase_lines tpl ON tpl.trade_purchase_id = tp.id
          WHERE tp.delivery_status = 'stock_committed'
            AND tp.status NOT IN ('deleted', 'cancelled')
          GROUP BY tp.id
        )
        UPDATE trade_purchases tp
        SET delivered_qty_committed = committed_qty.committed_qty
        FROM committed_qty
        WHERE tp.id = committed_qty.purchase_id
          AND (tp.delivered_qty_committed IS NULL OR tp.delivered_qty_committed <= 0);
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_stock_movements_purchase_lookup;")

