"""Replay stock movement chains and sync catalog current_stock from ledger deltas."""

from alembic import op

revision = "050_stock_ledger_replay_current_stock"
down_revision = "049_stock_ledger_sql_backfill"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        WITH replay AS (
          SELECT
            sm.id,
            sm.item_id,
            COALESCE(
              SUM(sm.delta_qty) OVER (
                PARTITION BY sm.item_id ORDER BY sm.created_at, sm.id
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
              ),
              0
            ) AS new_before,
            SUM(sm.delta_qty) OVER (
              PARTITION BY sm.item_id ORDER BY sm.created_at, sm.id
              ROWS UNBOUNDED PRECEDING
            ) AS new_after
          FROM stock_movements sm
        )
        UPDATE stock_movements sm
        SET qty_before = r.new_before, qty_after = r.new_after
        FROM replay r
        WHERE sm.id = r.id;

        UPDATE catalog_items ci
        SET
          current_stock = tail.qty_after,
          last_stock_updated_at = NOW()
        FROM (
          SELECT DISTINCT ON (sm.item_id)
            sm.item_id,
            sm.qty_after
          FROM stock_movements sm
          ORDER BY sm.item_id, sm.created_at DESC, sm.id DESC
        ) tail
        WHERE ci.id = tail.item_id
          AND ci.deleted_at IS NULL;
        """
    )


def downgrade() -> None:
    pass
