"""SSOT: ensure schema exists, backfill supplier_id / catalog_item_id, NOT NULL (Postgres).

Revision ID: 007_ssot_tp_fks
Revises: 006_cloud_pay_meta
"""

from __future__ import annotations

from typing import Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect, text
from sqlalchemy.dialects.postgresql import UUID as PG_UUID

revision: str = "007_ssot_tp_fks"
down_revision: Union[str, None] = "006_cloud_pay_meta"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return

    # Fresh Postgres (no startup create_all): materialize full schema from models once.
    insp = inspect(bind)
    if not insp.has_table("trade_purchases"):
        from app.models import Base  # noqa: PLC0415 — Alembic runtime import

        Base.metadata.create_all(bind=bind)
        insp = inspect(bind)

    if not insp.has_table("trade_purchases") or not insp.has_table("trade_purchase_lines"):
        return

    # --- Backfill supplier_id on trade_purchases ---
    bind.execute(
        text(
            """
            UPDATE trade_purchases tp
            SET supplier_id = s.id
            FROM (
              SELECT DISTINCT ON (business_id) business_id, id
              FROM suppliers
              ORDER BY business_id, created_at
            ) s
            WHERE tp.supplier_id IS NULL AND tp.business_id = s.business_id
            """
        )
    )

    bind.execute(
        text(
            """
            INSERT INTO suppliers (id, business_id, name, created_at)
            SELECT gen_random_uuid(), b.id, '(Legacy) Auto supplier', NOW()
            FROM businesses b
            WHERE EXISTS (
              SELECT 1 FROM trade_purchases tp
              WHERE tp.business_id = b.id AND tp.supplier_id IS NULL
            )
            AND NOT EXISTS (SELECT 1 FROM suppliers s WHERE s.business_id = b.id)
            """
        )
    )

    bind.execute(
        text(
            """
            UPDATE trade_purchases tp
            SET supplier_id = s.id
            FROM (
              SELECT DISTINCT ON (business_id) business_id, id
              FROM suppliers
              ORDER BY business_id, created_at
            ) s
            WHERE tp.supplier_id IS NULL AND tp.business_id = s.business_id
            """
        )
    )

    # --- Backfill catalog_item_id on lines (name match) ---
    bind.execute(
        text(
            """
            UPDATE trade_purchase_lines tpl
            SET catalog_item_id = ci.id
            FROM trade_purchases tp
            JOIN catalog_items ci
              ON ci.business_id = tp.business_id
            WHERE tpl.trade_purchase_id = tp.id
              AND tpl.catalog_item_id IS NULL
              AND lower(trim(ci.name)) = lower(trim(tpl.item_name))
            """
        )
    )

    bind.execute(
        text(
            """
            UPDATE trade_purchase_lines tpl
            SET catalog_item_id = sub.item_id
            FROM trade_purchases tp
            JOIN LATERAL (
              SELECT id AS item_id FROM catalog_items ci
              WHERE ci.business_id = tp.business_id
              ORDER BY ci.created_at
              LIMIT 1
            ) sub ON true
            WHERE tpl.trade_purchase_id = tp.id
              AND tpl.catalog_item_id IS NULL
            """
        )
    )

    # Businesses with lines but zero catalog items: seed General + placeholder item
    rows = bind.execute(
        text(
            """
            SELECT DISTINCT tp.business_id
            FROM trade_purchases tp
            JOIN trade_purchase_lines tpl ON tpl.trade_purchase_id = tp.id
            WHERE tpl.catalog_item_id IS NULL
            """
        )
    ).fetchall()
    for (bid,) in rows:
        cid = bind.execute(
            text("SELECT id FROM item_categories WHERE business_id = :bid LIMIT 1"),
            {"bid": bid},
        ).scalar()
        if cid is None:
            cid = bind.execute(
                text(
                    """
                    INSERT INTO item_categories (id, business_id, name, created_at)
                    VALUES (gen_random_uuid(), :bid, 'General', NOW())
                    RETURNING id
                    """
                ),
                {"bid": bid},
            ).scalar()
        has_placeholder = bind.execute(
            text(
                "SELECT id FROM catalog_items WHERE business_id = :bid AND name = '(Legacy) Unmatched line' LIMIT 1"
            ),
            {"bid": bid},
        ).scalar()
        if has_placeholder is None:
            bind.execute(
                text(
                    """
                    INSERT INTO catalog_items (
                      id, business_id, category_id, name, default_unit, created_at
                    )
                    VALUES (
                      gen_random_uuid(), :bid, :cid, '(Legacy) Unmatched line', 'unit', NOW()
                    )
                    """
                ),
                {"bid": bid, "cid": cid},
            )

    bind.execute(
        text(
            """
            UPDATE trade_purchase_lines tpl
            SET catalog_item_id = sub.item_id
            FROM trade_purchases tp
            JOIN LATERAL (
              SELECT id AS item_id FROM catalog_items ci
              WHERE ci.business_id = tp.business_id
              ORDER BY ci.created_at
              LIMIT 1
            ) sub ON true
            WHERE tpl.trade_purchase_id = tp.id
              AND tpl.catalog_item_id IS NULL
            """
        )
    )

    n_sup = bind.execute(text("SELECT COUNT(*) FROM trade_purchases WHERE supplier_id IS NULL")).scalar()
    n_line = bind.execute(
        text("SELECT COUNT(*) FROM trade_purchase_lines WHERE catalog_item_id IS NULL")
    ).scalar()
    if n_sup and int(n_sup) > 0:
        raise RuntimeError(
            f"007_ssot_tp_fks: {n_sup} trade_purchases still have NULL supplier_id; fix data manually."
        )
    if n_line and int(n_line) > 0:
        raise RuntimeError(
            f"007_ssot_tp_fks: {n_line} trade_purchase_lines still have NULL catalog_item_id; fix data manually."
        )

    _uuid = PG_UUID(as_uuid=True)
    op.alter_column(
        "trade_purchases",
        "supplier_id",
        existing_type=_uuid,
        nullable=False,
    )
    op.alter_column(
        "trade_purchase_lines",
        "catalog_item_id",
        existing_type=_uuid,
        nullable=False,
    )


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    _uuid = PG_UUID(as_uuid=True)
    op.alter_column(
        "trade_purchase_lines",
        "catalog_item_id",
        existing_type=_uuid,
        nullable=True,
    )
    op.alter_column(
        "trade_purchases",
        "supplier_id",
        existing_type=_uuid,
        nullable=True,
    )
