"""Trade purchase core tables (idempotent no-op; dev uses SQLAlchemy create_all).

Revision ID: 001_trade_purchase_core
Revises:
Create Date: 2026-04-18

"""

from typing import Sequence, Union

from alembic import op

revision: str = "001_trade_purchase_core"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Tables are created by API `Base.metadata.create_all` for local/SQLite.
    # For strict Alembic-only deploys, replace this with explicit op.create_table(...)
    # matching `app.models.trade_purchase` and run `alembic upgrade head`.
    pass


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS trade_purchase_lines")
    op.execute("DROP TABLE IF EXISTS trade_purchase_drafts")
    op.execute("DROP TABLE IF EXISTS trade_purchases")
    op.execute("DROP TABLE IF EXISTS broker_supplier_links")
