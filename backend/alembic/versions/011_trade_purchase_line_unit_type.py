"""Add canonical unit_type to trade_purchase_lines (backfilled from unit).

Revision ID: 011_tp_line_unit_type
Revises: 010_tp_line_decimals
Create Date: 2026-05-01
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "011_tp_line_unit_type"
down_revision: Union[str, None] = "010_tp_line_decimals"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return any(c["name"] == column for c in insp.get_columns(table))


def upgrade() -> None:
    if not _has_column("trade_purchase_lines", "unit_type"):
        op.add_column("trade_purchase_lines", sa.Column("unit_type", sa.String(16), nullable=True))
    bind = op.get_bind()
    dialect = bind.dialect.name
    if dialect == "sqlite":
        op.execute(
            """
            UPDATE trade_purchase_lines
            SET unit_type = CASE
              WHEN unit IS NULL OR TRIM(unit) = '' THEN 'other'
              WHEN UPPER(unit) LIKE '%SACK%' OR UPPER(unit) LIKE '%BAG%' THEN 'bag'
              WHEN UPPER(unit) LIKE '%BOX%' THEN 'box'
              WHEN UPPER(unit) LIKE '%TIN%' THEN 'tin'
              WHEN UPPER(unit) LIKE '%KG%' THEN 'kg'
              ELSE 'other'
            END
            """
        )
    else:
        op.execute(
            """
            UPDATE trade_purchase_lines
            SET unit_type = CASE
              WHEN unit IS NULL OR TRIM(BOTH FROM unit::text) = '' THEN 'other'
              WHEN UPPER(unit::text) LIKE '%SACK%' OR UPPER(unit::text) LIKE '%BAG%' THEN 'bag'
              WHEN UPPER(unit::text) LIKE '%BOX%' THEN 'box'
              WHEN UPPER(unit::text) LIKE '%TIN%' THEN 'tin'
              WHEN UPPER(unit::text) LIKE '%KG%' THEN 'kg'
              ELSE 'other'
            END
            """
        )


def downgrade() -> None:
    if _has_column("trade_purchase_lines", "unit_type"):
        op.drop_column("trade_purchase_lines", "unit_type")
