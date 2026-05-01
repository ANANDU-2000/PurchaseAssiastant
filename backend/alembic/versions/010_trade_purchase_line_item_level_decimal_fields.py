"""Add item-level purchase accounting decimal fields.

Revision ID: 010_trade_purchase_line_item_level_decimal_fields
Revises: 009_strict_decimal_precision
Create Date: 2026-04-30
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "010_trade_purchase_line_item_level_decimal_fields"
down_revision: Union[str, None] = "009_strict_decimal_precision"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return any(c["name"] == column for c in insp.get_columns(table))


def _add_column(table: str, column: sa.Column) -> None:
    if not _has_column(table, column.name):
        op.add_column(table, column)


def upgrade() -> None:
    _add_column("trade_purchase_lines", sa.Column("purchase_rate", sa.Numeric(12, 2), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("selling_rate", sa.Numeric(12, 2), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("freight_type", sa.String(16), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("freight_value", sa.Numeric(12, 2), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("delivered_rate", sa.Numeric(12, 2), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("billty_rate", sa.Numeric(12, 2), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("weight_per_unit", sa.Numeric(12, 3), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("total_weight", sa.Numeric(14, 3), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("line_total", sa.Numeric(14, 2), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("profit", sa.Numeric(14, 2), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("box_mode", sa.String(24), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("items_per_box", sa.Numeric(12, 3), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("weight_per_item", sa.Numeric(12, 3), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("kg_per_box", sa.Numeric(12, 3), nullable=True))
    _add_column("trade_purchase_lines", sa.Column("weight_per_tin", sa.Numeric(12, 3), nullable=True))

    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        op.execute(
            """
            UPDATE trade_purchase_lines
            SET purchase_rate = COALESCE(purchase_rate, landing_cost),
                selling_rate = COALESCE(selling_rate, selling_cost),
                weight_per_unit = COALESCE(weight_per_unit, kg_per_unit),
                line_total = COALESCE(
                    line_total,
                    CASE
                      WHEN kg_per_unit IS NOT NULL AND landing_cost_per_kg IS NOT NULL
                        THEN ROUND(qty * kg_per_unit * landing_cost_per_kg, 2)
                      ELSE ROUND(qty * landing_cost, 2)
                    END
                ),
                total_weight = COALESCE(
                    total_weight,
                    CASE
                      WHEN kg_per_unit IS NOT NULL THEN ROUND(qty * kg_per_unit, 3)
                      WHEN UPPER(unit) = 'KG' THEN ROUND(qty, 3)
                      ELSE NULL
                    END
                ),
                profit = COALESCE(
                    profit,
                    CASE
                      WHEN selling_cost IS NOT NULL THEN
                        ROUND(
                          CASE
                            WHEN kg_per_unit IS NOT NULL AND landing_cost_per_kg IS NOT NULL
                              THEN qty * kg_per_unit * selling_cost - qty * kg_per_unit * landing_cost_per_kg
                            ELSE qty * selling_cost - qty * landing_cost
                          END,
                          2
                        )
                      ELSE NULL
                    END
                )
            """
        )
        return

    op.execute(
        """
        UPDATE trade_purchase_lines
        SET purchase_rate = COALESCE(purchase_rate, landing_cost),
            selling_rate = COALESCE(selling_rate, selling_cost),
            weight_per_unit = COALESCE(weight_per_unit, kg_per_unit),
            line_total = COALESCE(
                line_total,
                CASE
                  WHEN kg_per_unit IS NOT NULL AND landing_cost_per_kg IS NOT NULL
                    THEN ROUND((qty * kg_per_unit * landing_cost_per_kg)::numeric, 2)
                  ELSE ROUND((qty * landing_cost)::numeric, 2)
                END
            ),
            total_weight = COALESCE(
                total_weight,
                CASE
                  WHEN kg_per_unit IS NOT NULL THEN ROUND((qty * kg_per_unit)::numeric, 3)
                  WHEN UPPER(unit) = 'KG' THEN ROUND(qty::numeric, 3)
                  ELSE NULL
                END
            ),
            profit = COALESCE(
                profit,
                CASE
                  WHEN selling_cost IS NOT NULL THEN
                    ROUND(
                      CASE
                        WHEN kg_per_unit IS NOT NULL AND landing_cost_per_kg IS NOT NULL
                          THEN (qty * kg_per_unit * selling_cost) - (qty * kg_per_unit * landing_cost_per_kg)
                        ELSE (qty * selling_cost) - (qty * landing_cost)
                      END,
                      2
                    )
                  ELSE NULL
                END
            )
        """
    )


def downgrade() -> None:
    for col in (
        "weight_per_tin",
        "kg_per_box",
        "weight_per_item",
        "items_per_box",
        "box_mode",
        "profit",
        "line_total",
        "total_weight",
        "weight_per_unit",
        "billty_rate",
        "delivered_rate",
        "freight_value",
        "freight_type",
        "selling_rate",
        "purchase_rate",
    ):
        if _has_column("trade_purchase_lines", col):
            op.drop_column("trade_purchase_lines", col)
