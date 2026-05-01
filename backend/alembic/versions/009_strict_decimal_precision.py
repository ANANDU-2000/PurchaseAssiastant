"""Enforce strict decimal precision for purchase accounting.

Revision ID: 009_strict_decimal_precision
Revises: 008_tp_profit
Create Date: 2026-04-30
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "009_strict_decimal_precision"
down_revision: Union[str, None] = "008_tp_profit"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _alter_numeric(table: str, column: str, precision: int, scale: int, *, nullable: bool = True) -> None:
    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        # SQLite stores NUMERIC affinity without enforcing precision; runtime
        # SQLAlchemy models and validators still enforce strict decimal scale.
        return
    op.alter_column(
        table,
        column,
        type_=sa.Numeric(precision, scale),
        existing_type=sa.Numeric(),
        nullable=nullable,
        postgresql_using=f"{column}::numeric({precision},{scale})",
    )


def upgrade() -> None:
    # Trade purchase header: money/rates/totals.
    _alter_numeric("trade_purchases", "paid_amount", 14, 2, nullable=False)
    _alter_numeric("trade_purchases", "discount", 5, 2)
    _alter_numeric("trade_purchases", "commission_percent", 5, 2)
    _alter_numeric("trade_purchases", "delivered_rate", 12, 2)
    _alter_numeric("trade_purchases", "billty_rate", 12, 2)
    _alter_numeric("trade_purchases", "freight_amount", 12, 2)
    _alter_numeric("trade_purchases", "total_qty", 12, 3)
    _alter_numeric("trade_purchases", "total_amount", 14, 2, nullable=False)
    _alter_numeric("trade_purchases", "total_landing_subtotal", 14, 2)
    _alter_numeric("trade_purchases", "total_selling_subtotal", 14, 2)
    _alter_numeric("trade_purchases", "total_line_profit", 14, 2)

    # Trade purchase lines: quantity, rates, weights, percentages.
    _alter_numeric("trade_purchase_lines", "qty", 12, 3, nullable=False)
    _alter_numeric("trade_purchase_lines", "landing_cost", 12, 2, nullable=False)
    _alter_numeric("trade_purchase_lines", "kg_per_unit", 12, 3)
    _alter_numeric("trade_purchase_lines", "landing_cost_per_kg", 12, 2)
    _alter_numeric("trade_purchase_lines", "selling_cost", 12, 2)
    _alter_numeric("trade_purchase_lines", "discount", 5, 2)
    _alter_numeric("trade_purchase_lines", "tax_percent", 5, 2)

    # Catalog defaults and learned supplier defaults.
    _alter_numeric("catalog_items", "default_kg_per_bag", 12, 3)
    _alter_numeric("catalog_items", "default_items_per_box", 12, 3)
    _alter_numeric("catalog_items", "default_weight_per_tin", 12, 3)
    _alter_numeric("catalog_items", "tax_percent", 5, 2)
    _alter_numeric("catalog_items", "default_landing_cost", 12, 2)
    _alter_numeric("catalog_items", "default_selling_cost", 12, 2)
    _alter_numeric("catalog_items", "last_purchase_price", 12, 2)
    _alter_numeric("catalog_variants", "default_kg_per_bag", 12, 3)
    _alter_numeric("supplier_item_defaults", "last_price", 12, 2)
    _alter_numeric("supplier_item_defaults", "last_discount", 5, 2)
    _alter_numeric("suppliers", "default_discount", 5, 2)
    _alter_numeric("suppliers", "default_delivered_rate", 12, 2)
    _alter_numeric("suppliers", "default_billty_rate", 12, 2)
    _alter_numeric("brokers", "commission_value", 12, 2)


def downgrade() -> None:
    for table, columns in {
        "trade_purchases": [
            "paid_amount",
            "discount",
            "commission_percent",
            "delivered_rate",
            "billty_rate",
            "freight_amount",
            "total_qty",
            "total_amount",
            "total_landing_subtotal",
            "total_selling_subtotal",
            "total_line_profit",
        ],
        "trade_purchase_lines": [
            "qty",
            "landing_cost",
            "kg_per_unit",
            "landing_cost_per_kg",
            "selling_cost",
            "discount",
            "tax_percent",
        ],
        "catalog_items": [
            "default_kg_per_bag",
            "default_items_per_box",
            "default_weight_per_tin",
            "tax_percent",
            "default_landing_cost",
            "default_selling_cost",
            "last_purchase_price",
        ],
        "catalog_variants": ["default_kg_per_bag"],
        "supplier_item_defaults": ["last_price", "last_discount"],
        "suppliers": ["default_discount", "default_delivered_rate", "default_billty_rate"],
        "brokers": ["commission_value"],
    }.items():
        for column in columns:
            _alter_numeric(table, column, 18, 4)
