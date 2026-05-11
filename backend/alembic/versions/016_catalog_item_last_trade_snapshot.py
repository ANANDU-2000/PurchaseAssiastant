"""Catalog item: last trade snapshot for unified search and UI.

Revision ID: 016_catalog_item_last_trade_snapshot
Revises: 015_trade_purchase_commission_mode
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "016_catalog_item_last_trade_snapshot"
down_revision: Union[str, None] = "015_trade_purchase_commission_mode"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return any(c["name"] == column for c in insp.get_columns(table))


def _fk_exists(bind, table: str, cols: tuple[str, ...], referred: str) -> bool:
    insp = sa.inspect(bind)
    for fk in insp.get_foreign_keys(table):
        if tuple(fk["constrained_columns"]) == cols and fk["referred_table"] == referred:
            return True
    return False


def upgrade() -> None:
    bind = op.get_bind()
    if not _has_column("catalog_items", "last_selling_rate"):
        op.add_column("catalog_items", sa.Column("last_selling_rate", sa.Numeric(12, 2), nullable=True))
    if not _has_column("catalog_items", "last_supplier_id"):
        op.add_column("catalog_items", sa.Column("last_supplier_id", sa.Uuid(), nullable=True))
    if not _has_column("catalog_items", "last_broker_id"):
        op.add_column("catalog_items", sa.Column("last_broker_id", sa.Uuid(), nullable=True))
    if not _has_column("catalog_items", "last_trade_purchase_id"):
        op.add_column("catalog_items", sa.Column("last_trade_purchase_id", sa.Uuid(), nullable=True))
    if not _has_column("catalog_items", "last_line_qty"):
        op.add_column("catalog_items", sa.Column("last_line_qty", sa.Numeric(12, 3), nullable=True))
    if not _has_column("catalog_items", "last_line_unit"):
        op.add_column("catalog_items", sa.Column("last_line_unit", sa.String(length=32), nullable=True))
    if not _has_column("catalog_items", "last_line_weight_kg"):
        op.add_column("catalog_items", sa.Column("last_line_weight_kg", sa.Numeric(14, 3), nullable=True))
    op.create_index(
        "ix_catalog_items_last_supplier_id",
        "catalog_items",
        ["last_supplier_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        "ix_catalog_items_last_broker_id",
        "catalog_items",
        ["last_broker_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        "ix_catalog_items_last_trade_purchase_id",
        "catalog_items",
        ["last_trade_purchase_id"],
        unique=False,
        if_not_exists=True,
    )
    if not _fk_exists(bind, "catalog_items", ("last_supplier_id",), "suppliers"):
        op.create_foreign_key(
            "fk_catalog_items_last_supplier_id_suppliers",
            "catalog_items",
            "suppliers",
            ["last_supplier_id"],
            ["id"],
            ondelete="SET NULL",
        )
    if not _fk_exists(bind, "catalog_items", ("last_broker_id",), "brokers"):
        op.create_foreign_key(
            "fk_catalog_items_last_broker_id_brokers",
            "catalog_items",
            "brokers",
            ["last_broker_id"],
            ["id"],
            ondelete="SET NULL",
        )
    if not _fk_exists(bind, "catalog_items", ("last_trade_purchase_id",), "trade_purchases"):
        op.create_foreign_key(
            "fk_catalog_items_last_trade_purchase_id_trade_purchases",
            "catalog_items",
            "trade_purchases",
            ["last_trade_purchase_id"],
            ["id"],
            ondelete="SET NULL",
        )


def downgrade() -> None:
    op.drop_constraint(
        "fk_catalog_items_last_trade_purchase_id_trade_purchases",
        "catalog_items",
        type_="foreignkey",
    )
    op.drop_constraint("fk_catalog_items_last_broker_id_brokers", "catalog_items", type_="foreignkey")
    op.drop_constraint("fk_catalog_items_last_supplier_id_suppliers", "catalog_items", type_="foreignkey")
    op.drop_index("ix_catalog_items_last_trade_purchase_id", table_name="catalog_items")
    op.drop_index("ix_catalog_items_last_broker_id", table_name="catalog_items")
    op.drop_index("ix_catalog_items_last_supplier_id", table_name="catalog_items")
    op.drop_column("catalog_items", "last_line_weight_kg")
    op.drop_column("catalog_items", "last_line_unit")
    op.drop_column("catalog_items", "last_line_qty")
    op.drop_column("catalog_items", "last_trade_purchase_id")
    op.drop_column("catalog_items", "last_broker_id")
    op.drop_column("catalog_items", "last_supplier_id")
    op.drop_column("catalog_items", "last_selling_rate")
