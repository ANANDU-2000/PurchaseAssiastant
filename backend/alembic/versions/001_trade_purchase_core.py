"""Bootstrap full ORM schema for Alembic-first runs (CI SQLite, fresh DB).

Revision ID: 001_trade_purchase_core
Revises:
Create Date: 2026-04-18

"""

from typing import Sequence, Union

from alembic import op

import app.models as _registered_models  # noqa: F401 — attach all tables to Base.metadata
from app.models.base import Base

revision: str = "001_trade_purchase_core"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Local dev often relies on API `Base.metadata.create_all`. CI and fresh SQLite
    # runs `alembic upgrade head` first, so we must materialize schema here; later
    # revisions use defensive checks (e.g. `_has_column`) when models already include
    # the same columns.
    bind = op.get_bind()
    Base.metadata.create_all(bind=bind)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS trade_purchase_lines")
    op.execute("DROP TABLE IF EXISTS trade_purchase_drafts")
    op.execute("DROP TABLE IF EXISTS trade_purchases")
    op.execute("DROP TABLE IF EXISTS broker_supplier_m2m")
    op.execute("DROP TABLE IF EXISTS broker_supplier_links")
