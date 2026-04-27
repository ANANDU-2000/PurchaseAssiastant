"""Add landing/selling/profit subtotal columns to trade_purchases; backfill from lines.

Revision ID: 008_tp_profit
Revises: 007_ssot_tp_fks
"""

from __future__ import annotations

from typing import Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import text

revision: str = "008_tp_profit"
down_revision: Union[str, None] = "007_ssot_tp_fks"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    for col, cname in (
        ("total_landing_subtotal", "Total line landing (qty × rate) before header charges"),
        ("total_selling_subtotal", "Total line selling when set"),
        ("total_line_profit", "Selling subtotal minus landing subtotal when selling present"),
    ):
        if not _has_column(bind, "trade_purchases", col):
            op.add_column(
                "trade_purchases",
                sa.Column(col, sa.Numeric(18, 4), nullable=True),
            )
    # Backfill from lines (kg lines use per-kg × qty × weight)
    bind.execute(
        text(
            """
            WITH agg AS (
              SELECT
                trade_purchase_id,
                COALESCE(SUM(
                  CASE
                    WHEN kg_per_unit IS NOT NULL AND landing_cost_per_kg IS NOT NULL
                    THEN (qty::numeric) * (kg_per_unit::numeric) * (landing_cost_per_kg::numeric)
                    ELSE (qty::numeric) * (landing_cost::numeric)
                  END
                ), 0) AS landing_sum,
                COALESCE(SUM(
                  CASE
                    WHEN selling_cost IS NULL THEN 0
                    WHEN kg_per_unit IS NOT NULL AND landing_cost_per_kg IS NOT NULL
                    THEN (qty::numeric) * (kg_per_unit::numeric) * (selling_cost::numeric)
                    ELSE (qty::numeric) * (selling_cost::numeric)
                  END
                ), 0) AS selling_sum
              FROM trade_purchase_lines
              GROUP BY trade_purchase_id
            )
            UPDATE trade_purchases tp
            SET
              total_landing_subtotal = agg.landing_sum,
              total_selling_subtotal = NULLIF(agg.selling_sum, 0),
              total_line_profit = CASE
                WHEN NULLIF(agg.selling_sum, 0) IS NULL THEN NULL
                ELSE agg.selling_sum - agg.landing_sum
              END
            FROM agg
            WHERE tp.id = agg.trade_purchase_id
            """
        )
    )


def _has_column(bind, table: str, col: str) -> bool:
    r = bind.execute(
        text(
            """
            SELECT 1 FROM information_schema.columns
            WHERE table_name = :t AND column_name = :c
            """
        ),
        {"t": table, "c": col},
    ).first()
    return r is not None


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    for col in (
        "total_line_profit",
        "total_selling_subtotal",
        "total_landing_subtotal",
    ):
        if _has_column(bind, "trade_purchases", col):
            op.drop_column("trade_purchases", col)
