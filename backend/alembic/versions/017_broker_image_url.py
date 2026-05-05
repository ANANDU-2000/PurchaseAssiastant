"""Add brokers.image_url for profile / statement branding."""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "017_broker_image_url"
down_revision: Union[str, None] = "016_catalog_item_last_trade_snapshot"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "brokers",
        sa.Column("image_url", sa.String(length=1024), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("brokers", "image_url")
