"""Smart unit intelligence: master_units, packaging tables, catalog_items columns.

Revision ID: 019_smart_unit_intelligence
Revises: 018_purchase_scan_traces
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "019_smart_unit_intelligence"
down_revision: Union[str, None] = "018_purchase_scan_traces"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Idempotent on Postgres when objects already exist (e.g. manual Supabase SQL
    # applied before `alembic_version` was bumped). Avoids deploy exit 3 on re-run.
    op.create_table(
        "master_units",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("unit_code", sa.String(length=32), nullable=False),
        sa.Column("display_name", sa.String(length=128), nullable=True),
        sa.Column("category", sa.String(length=64), nullable=True),
        sa.Column("conversion_supported", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("unit_code", name="uq_master_units_unit_code"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_master_units_active"),
        "master_units",
        ["active"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_master_units_unit_code"),
        "master_units",
        ["unit_code"],
        unique=False,
        if_not_exists=True,
    )

    op.add_column(
        "catalog_items",
        sa.Column("normalized_name", sa.String(length=512), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("selling_unit", sa.String(length=32), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("stock_unit", sa.String(length=32), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("display_unit", sa.String(length=32), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("package_type", sa.String(length=32), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("package_size", sa.Numeric(14, 4), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("package_measurement", sa.String(length=16), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("package_volume", sa.Numeric(14, 4), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("package_weight", sa.Numeric(14, 4), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("conversion_factor", sa.Numeric(14, 6), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("ai_detected_unit", sa.String(length=32), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("smart_classification", sa.String(length=64), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("unit_confidence", sa.Numeric(5, 2), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("packaging_confidence", sa.Numeric(5, 2), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("is_loose_item", sa.Boolean(), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("is_packaged_item", sa.Boolean(), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("auto_detect_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("ml_profile", sa.JSON(), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("validation_status", sa.String(length=32), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        if_not_exists=True,
    )
    op.add_column(
        "catalog_items",
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_catalog_items_deleted_at"),
        "catalog_items",
        ["deleted_at"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_catalog_items_normalized_name"),
        "catalog_items",
        ["normalized_name"],
        unique=False,
        if_not_exists=True,
    )

    op.create_table(
        "item_packaging_profiles",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("catalog_item_id", sa.Uuid(), nullable=False),
        sa.Column("package_type", sa.String(length=32), nullable=True),
        sa.Column("package_size", sa.Numeric(14, 4), nullable=True),
        sa.Column("package_measurement", sa.String(length=16), nullable=True),
        sa.Column("selling_unit", sa.String(length=32), nullable=True),
        sa.Column("stock_unit", sa.String(length=32), nullable=True),
        sa.Column("display_unit", sa.String(length=32), nullable=True),
        sa.Column("conversion_factor", sa.Numeric(14, 6), nullable=True),
        sa.Column("confidence_score", sa.Numeric(5, 2), nullable=True),
        sa.Column("ai_generated", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("updated_by_learning", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"]),
        sa.ForeignKeyConstraint(["catalog_item_id"], ["catalog_items.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_item_packaging_profiles_business_id"),
        "item_packaging_profiles",
        ["business_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_item_packaging_profiles_catalog_item_id"),
        "item_packaging_profiles",
        ["catalog_item_id"],
        unique=False,
        if_not_exists=True,
    )

    op.create_table(
        "ocr_item_aliases",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("alias", sa.String(length=512), nullable=False),
        sa.Column("normalized_alias", sa.String(length=512), nullable=False),
        sa.Column("catalog_item_id", sa.Uuid(), nullable=False),
        sa.Column("confidence", sa.Numeric(5, 2), nullable=True),
        sa.Column("source", sa.String(length=32), nullable=True),
        sa.Column("usage_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"]),
        sa.ForeignKeyConstraint(["catalog_item_id"], ["catalog_items.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "normalized_alias", "catalog_item_id", name="uq_ocr_alias_item_norm"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_ocr_item_aliases_business_id"),
        "ocr_item_aliases",
        ["business_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_ocr_item_aliases_catalog_item_id"),
        "ocr_item_aliases",
        ["catalog_item_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_ocr_item_aliases_normalized_alias"),
        "ocr_item_aliases",
        ["normalized_alias"],
        unique=False,
        if_not_exists=True,
    )

    op.create_table(
        "smart_unit_rules",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=True),
        sa.Column("keyword_pattern", sa.String(length=255), nullable=False),
        sa.Column("category", sa.String(length=128), nullable=True),
        sa.Column("resulting_unit", sa.String(length=32), nullable=True),
        sa.Column("package_type", sa.String(length=32), nullable=True),
        sa.Column("confidence", sa.Numeric(5, 2), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_smart_unit_rules_business_id"),
        "smart_unit_rules",
        ["business_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_smart_unit_rules_category"),
        "smart_unit_rules",
        ["category"],
        unique=False,
        if_not_exists=True,
    )

    op.create_table(
        "item_learning_history",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("catalog_item_id", sa.Uuid(), nullable=False),
        sa.Column("detected_pattern", sa.String(length=512), nullable=True),
        sa.Column("selected_unit", sa.String(length=32), nullable=True),
        sa.Column("corrected_by_user", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("learning_score", sa.Numeric(8, 3), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"]),
        sa.ForeignKeyConstraint(["catalog_item_id"], ["catalog_items.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_item_learning_history_business_id"),
        "item_learning_history",
        ["business_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_item_learning_history_catalog_item_id"),
        "item_learning_history",
        ["catalog_item_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_item_learning_history_created_at"),
        "item_learning_history",
        ["created_at"],
        unique=False,
        if_not_exists=True,
    )

    op.create_table(
        "unit_confidence_logs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("catalog_item_id", sa.Uuid(), nullable=True),
        sa.Column("source", sa.String(length=64), nullable=True),
        sa.Column("score", sa.Numeric(5, 2), nullable=True),
        sa.Column("payload_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"]),
        sa.ForeignKeyConstraint(["catalog_item_id"], ["catalog_items.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_unit_confidence_logs_business_id"),
        "unit_confidence_logs",
        ["business_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_unit_confidence_logs_catalog_item_id"),
        "unit_confidence_logs",
        ["catalog_item_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_unit_confidence_logs_created_at"),
        "unit_confidence_logs",
        ["created_at"],
        unique=False,
        if_not_exists=True,
    )

    op.create_table(
        "ai_item_profiles",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("catalog_item_id", sa.Uuid(), nullable=False),
        sa.Column("profile_json", sa.JSON(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"]),
        sa.ForeignKeyConstraint(["catalog_item_id"], ["catalog_items.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "catalog_item_id", name="uq_ai_item_profile_item"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_ai_item_profiles_business_id"),
        "ai_item_profiles",
        ["business_id"],
        unique=False,
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_ai_item_profiles_catalog_item_id"),
        "ai_item_profiles",
        ["catalog_item_id"],
        unique=False,
        if_not_exists=True,
    )

    op.create_table(
        "smart_package_rules",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=True),
        sa.Column("keyword_pattern", sa.String(length=255), nullable=False),
        sa.Column("package_type", sa.String(length=32), nullable=False),
        sa.Column("priority", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_smart_package_rules_business_id"),
        "smart_package_rules",
        ["business_id"],
        unique=False,
        if_not_exists=True,
    )

    # Seed canonical units (idempotent; works on SQLite + Postgres).
    now = datetime.now(timezone.utc)
    seed_rows = [
        ("BAG", "Bag", "count"),
        ("KG", "Kilogram", "weight"),
        ("BOX", "Box", "count"),
        ("PCS", "Pieces", "count"),
        ("TIN", "Tin", "count"),
        ("PACK", "Pack", "count"),
        ("SACK", "Sack", "count"),
        ("LTR", "Litre", "volume"),
        ("ML", "Millilitre", "volume"),
        ("GM", "Gram", "weight"),
        ("CAN", "Can", "count"),
        ("BOTTLE", "Bottle", "count"),
        ("CASE", "Case", "count"),
        ("ROLL", "Roll", "count"),
        ("TRAY", "Tray", "count"),
    ]
    bind = op.get_bind()
    dialect = bind.dialect.name if bind is not None else "postgresql"
    for code, dname, cat in seed_rows:
        if dialect == "sqlite":
            op.execute(
                sa.text(
                    "INSERT OR IGNORE INTO master_units (id, unit_code, display_name, category, conversion_supported, active, created_at) "
                    "VALUES (:id, :code, :dname, :cat, 1, 1, :ts)"
                ).bindparams(
                    id=str(uuid.uuid4()),
                    code=code,
                    dname=dname,
                    cat=cat,
                    ts=now,
                )
            )
        else:
            op.execute(
                sa.text(
                    "INSERT INTO master_units (id, unit_code, display_name, category, conversion_supported, active, created_at) "
                    "VALUES (CAST(:id AS uuid), :code, :dname, :cat, true, true, :ts) ON CONFLICT (unit_code) DO NOTHING"
                ).bindparams(id=str(uuid.uuid4()), code=code, dname=dname, cat=cat, ts=now)
            )


def downgrade() -> None:
    op.drop_index(op.f("ix_smart_package_rules_business_id"), table_name="smart_package_rules")
    op.drop_table("smart_package_rules")

    op.drop_index(op.f("ix_ai_item_profiles_catalog_item_id"), table_name="ai_item_profiles")
    op.drop_index(op.f("ix_ai_item_profiles_business_id"), table_name="ai_item_profiles")
    op.drop_table("ai_item_profiles")

    op.drop_index(op.f("ix_unit_confidence_logs_created_at"), table_name="unit_confidence_logs")
    op.drop_index(op.f("ix_unit_confidence_logs_catalog_item_id"), table_name="unit_confidence_logs")
    op.drop_index(op.f("ix_unit_confidence_logs_business_id"), table_name="unit_confidence_logs")
    op.drop_table("unit_confidence_logs")

    op.drop_index(op.f("ix_item_learning_history_created_at"), table_name="item_learning_history")
    op.drop_index(op.f("ix_item_learning_history_catalog_item_id"), table_name="item_learning_history")
    op.drop_index(op.f("ix_item_learning_history_business_id"), table_name="item_learning_history")
    op.drop_table("item_learning_history")

    op.drop_index(op.f("ix_smart_unit_rules_category"), table_name="smart_unit_rules")
    op.drop_index(op.f("ix_smart_unit_rules_business_id"), table_name="smart_unit_rules")
    op.drop_table("smart_unit_rules")

    op.drop_index(op.f("ix_ocr_item_aliases_normalized_alias"), table_name="ocr_item_aliases")
    op.drop_index(op.f("ix_ocr_item_aliases_catalog_item_id"), table_name="ocr_item_aliases")
    op.drop_index(op.f("ix_ocr_item_aliases_business_id"), table_name="ocr_item_aliases")
    op.drop_table("ocr_item_aliases")

    op.drop_index(op.f("ix_item_packaging_profiles_catalog_item_id"), table_name="item_packaging_profiles")
    op.drop_index(op.f("ix_item_packaging_profiles_business_id"), table_name="item_packaging_profiles")
    op.drop_table("item_packaging_profiles")

    op.drop_index(op.f("ix_catalog_items_normalized_name"), table_name="catalog_items")
    op.drop_index(op.f("ix_catalog_items_deleted_at"), table_name="catalog_items")
    op.drop_column("catalog_items", "archived_at")
    op.drop_column("catalog_items", "deleted_at")
    op.drop_column("catalog_items", "validation_status")
    op.drop_column("catalog_items", "ml_profile")
    op.drop_column("catalog_items", "auto_detect_enabled")
    op.drop_column("catalog_items", "is_packaged_item")
    op.drop_column("catalog_items", "is_loose_item")
    op.drop_column("catalog_items", "packaging_confidence")
    op.drop_column("catalog_items", "unit_confidence")
    op.drop_column("catalog_items", "smart_classification")
    op.drop_column("catalog_items", "ai_detected_unit")
    op.drop_column("catalog_items", "conversion_factor")
    op.drop_column("catalog_items", "package_weight")
    op.drop_column("catalog_items", "package_volume")
    op.drop_column("catalog_items", "package_measurement")
    op.drop_column("catalog_items", "package_size")
    op.drop_column("catalog_items", "package_type")
    op.drop_column("catalog_items", "display_unit")
    op.drop_column("catalog_items", "stock_unit")
    op.drop_column("catalog_items", "selling_unit")
    op.drop_column("catalog_items", "normalized_name")

    op.drop_index(op.f("ix_master_units_unit_code"), table_name="master_units")
    op.drop_index(op.f("ix_master_units_active"), table_name="master_units")
    op.drop_table("master_units")
