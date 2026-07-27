"""Add brokers.image_url for profile / statement branding."""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import text

revision: str = "017_broker_image_url"
down_revision: Union[str, None] = "016_catalog_item_last_trade_snapshot"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return any(c["name"] == column for c in insp.get_columns(table))


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        op.execute(
            text("ALTER TABLE brokers ADD COLUMN IF NOT EXISTS image_url VARCHAR(1024)"),
        )
    elif not _has_column("brokers", "image_url"):
        op.add_column("brokers", sa.Column("image_url", sa.String(length=1024), nullable=True))


def downgrade() -> None:
    op.drop_column("brokers", "image_url")
