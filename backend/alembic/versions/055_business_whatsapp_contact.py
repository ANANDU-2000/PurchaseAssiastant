"""Add accounts_whatsapp_number to businesses

Revision ID: 055_business_whatsapp_contact
Revises: 054_enable_rls_business_policies
"""

from typing import Union

from alembic import op
import sqlalchemy as sa

revision: str = "055_business_whatsapp_contact"
down_revision: Union[str, None] = "054_enable_rls_business_policies"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return any(c["name"] == column for c in insp.get_columns(table))


def upgrade() -> None:
    if not _has_column("businesses", "accounts_whatsapp_number"):
        op.add_column(
            "businesses",
            sa.Column("accounts_whatsapp_number", sa.String(length=20), nullable=True),
        )


def downgrade() -> None:
    if _has_column("businesses", "accounts_whatsapp_number"):
        op.drop_column("businesses", "accounts_whatsapp_number")
