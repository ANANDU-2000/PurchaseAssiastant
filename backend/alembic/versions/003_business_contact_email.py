"""Add contact_email to businesses

Revision ID: 003_contact_email
Revises: 002_line_kg
Create Date: 2026-04-23
"""

from typing import Union

from alembic import op
import sqlalchemy as sa

revision: str = "003_contact_email"
down_revision: Union[str, None] = "002_line_kg"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "businesses",
        sa.Column("contact_email", sa.String(length=255), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("businesses", "contact_email")
