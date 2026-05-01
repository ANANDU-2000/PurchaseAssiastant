"""cloud_expenses and cloud_payment_history for workspace billing reminder

Revision ID: 004_cloud_exp
Revises: 003_contact_email
Create Date: 2026-04-25
"""

from typing import Union

from alembic import op
import sqlalchemy as sa

revision: str = "004_cloud_exp"
down_revision: Union[str, None] = "003_contact_email"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()

    def _has(name: str) -> bool:
        return sa.inspect(bind).has_table(name)

    if not _has("cloud_expenses"):
        op.create_table(
            "cloud_expenses",
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("business_id", sa.Uuid(), nullable=False),
            sa.Column("name", sa.String(length=128), nullable=False),
            sa.Column("amount_inr", sa.Numeric(18, 4), nullable=False),
            sa.Column("due_day", sa.Integer(), nullable=False),
            sa.Column("last_paid_date", sa.Date(), nullable=True),
            sa.Column("next_due_date", sa.Date(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("business_id", name="uq_cloud_expenses_business"),
        )
        op.create_index(op.f("ix_cloud_expenses_business_id"), "cloud_expenses", ["business_id"], unique=True)
        op.create_index(op.f("ix_cloud_expenses_next_due_date"), "cloud_expenses", ["next_due_date"], unique=False)

    if not _has("cloud_payment_history"):
        op.create_table(
            "cloud_payment_history",
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("business_id", sa.Uuid(), nullable=False),
            sa.Column("amount_inr", sa.Numeric(18, 4), nullable=False),
            sa.Column("paid_on", sa.Date(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index(
            op.f("ix_cloud_payment_history_business_id"), "cloud_payment_history", ["business_id"], unique=False
        )
        op.create_index(op.f("ix_cloud_payment_history_paid_on"), "cloud_payment_history", ["paid_on"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_cloud_payment_history_paid_on"), table_name="cloud_payment_history")
    op.drop_index(op.f("ix_cloud_payment_history_business_id"), table_name="cloud_payment_history")
    op.drop_table("cloud_payment_history")
    op.drop_index(op.f("ix_cloud_expenses_next_due_date"), table_name="cloud_expenses")
    op.drop_index(op.f("ix_cloud_expenses_business_id"), table_name="cloud_expenses")
    op.drop_table("cloud_expenses")
