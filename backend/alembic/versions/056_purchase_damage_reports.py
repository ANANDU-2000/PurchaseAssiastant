"""purchase_damage_reports table

Revision ID: 056_purchase_damage_reports
Revises: 055_business_whatsapp_contact
"""

from typing import Union

from alembic import op
import sqlalchemy as sa

revision: str = "056_purchase_damage_reports"
down_revision: Union[str, None] = "055_business_whatsapp_contact"
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    bind = op.get_bind()
    return name in sa.inspect(bind).get_table_names()


def upgrade() -> None:
    if _has_table("purchase_damage_reports"):
        return
    op.create_table(
        "purchase_damage_reports",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("purchase_id", sa.Uuid(), nullable=False),
        sa.Column("item_name", sa.String(length=500), nullable=False),
        sa.Column("qty_damaged", sa.Numeric(18, 4), nullable=False),
        sa.Column("damage_type", sa.String(length=32), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("reported_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["purchase_id"], ["trade_purchases.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reported_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_purchase_damage_reports_purchase_id",
        "purchase_damage_reports",
        ["purchase_id"],
    )
    op.create_index(
        "ix_purchase_damage_reports_business_id",
        "purchase_damage_reports",
        ["business_id"],
    )


def downgrade() -> None:
    if _has_table("purchase_damage_reports"):
        op.drop_table("purchase_damage_reports")
