"""Hourly-ish job: insert in-app notifications for catalog items below reorder level."""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, Membership
from app.routers.stock import _fetch_low_stock_candidates
from app.services.low_stock_priority import compute_low_stock_priority
from app.services.notification_emitter import (
    CATEGORY_WAREHOUSE,
    PRIORITY_HIGH,
    PRIORITY_CRITICAL,
    emit_notification,
)

logger = logging.getLogger(__name__)


async def run_low_stock_notification_scan(db: AsyncSession) -> int:
    """Create deduped low-stock notifications for all members of affected businesses."""
    now = datetime.now(timezone.utc)
    day = now.strftime("%Y-%m-%d")

    q = await db.execute(
        select(
            CatalogItem.id,
            CatalogItem.business_id,
            CatalogItem.name,
            CatalogItem.current_stock,
            CatalogItem.reorder_level,
            CatalogItem.stock_unit,
            CatalogItem.default_unit,
        ).where(
            CatalogItem.deleted_at.is_(None),
            CatalogItem.archived_at.is_(None),
            CatalogItem.reorder_level.isnot(None),
            CatalogItem.reorder_level > 0,
            CatalogItem.current_stock.isnot(None),
            CatalogItem.current_stock < CatalogItem.reorder_level,
        )
    )
    low_rows = q.all()
    if not low_rows:
        return 0

    inserted = 0
    for item_id, business_id, name, cur, reorder, stock_unit, default_unit in low_rows:
        mems = await db.execute(
            select(Membership.user_id).where(Membership.business_id == business_id)
        )
        user_ids = [row[0] for row in mems.all()]
        unit = (stock_unit or default_unit or "units").strip()
        n = await emit_notification(
            db,
            business_id=business_id,
            user_ids=user_ids,
            kind="low_stock",
            title=f"Low stock: {name}",
            body=f"{cur} {unit} left (reorder at {reorder})",
            priority=PRIORITY_HIGH,
            category=CATEGORY_WAREHOUSE,
            dedupe_key=f"low_stock:{item_id}:{day}",
            action_route=f"/catalog/item/{item_id}",
            related_item_id=item_id,
            payload={
                "item_id": str(item_id),
                "current_stock": float(cur) if cur is not None else None,
                "reorder_level": float(reorder) if reorder is not None else None,
            },
        )
        inserted += n

    if inserted:
        await db.commit()

    # P1: mismatch + delayed deep-link notifications for owners.
    mismatch_inserted = 0
    business_ids = {row[1] for row in low_rows}
    for business_id in business_ids:
        mem_rows = await db.execute(
            select(Membership).where(Membership.business_id == business_id).limit(20)
        )
        mems = mem_rows.scalars().all()
        if not mems:
            continue

        membership = next(
            (
                mm
                for mm in mems
                if (mm.role or "").lower() in ("owner", "admin", "manager")
            ),
            mems[0],
        )

        merged: dict[uuid.UUID, object] = {}
        for status in ("low", "critical", "out"):
            _, chunk = await _fetch_low_stock_candidates(
                business_id=business_id,
                db=db,
                membership=membership,
                q="",
                category="",
                subcategory="",
                status=status,  # type: ignore[arg-type]
                period_start=None,
                period_end=None,
                fetch_per_page=120,
                max_pages=6,
            )
            merged.update(chunk)

        for it in merged.values():
            pr = compute_low_stock_priority(it)
            if pr.mismatch_flag:
                diff = getattr(it, "physical_stock_difference_qty", None)
                diff_f = float(diff) if diff is not None else 0.0
                mismatch_inserted += await emit_notification(
                    db,
                    business_id=business_id,
                    kind="stock_mismatch",
                    title=f"Stock mismatch: {getattr(it, 'name', '')}",
                    body=f"Physical/system difference: {diff_f:+.2f}",
                    priority=PRIORITY_CRITICAL,
                    category=CATEGORY_WAREHOUSE,
                    dedupe_key=f"stock_mismatch:{it.id}:{day}",
                    action_route="/stock/low-stock?filter=disputed",
                    related_item_id=it.id,
                    owner_only=True,
                )

            if pr.delayed_flag:
                pending_days = getattr(it, "pending_order_days", None) or 0
                supplier_name = (getattr(it, "supplier_name", None) or "").strip()
                mismatch_inserted += await emit_notification(
                    db,
                    business_id=business_id,
                    kind="supplier_delayed",
                    title=f"Supplier delayed purchase: {getattr(it, 'name', '')}",
                    body=f"Pending for {pending_days} days"
                    + (f" — supplier: {supplier_name}" if supplier_name else ""),
                    priority=PRIORITY_HIGH,
                    category=CATEGORY_WAREHOUSE,
                    dedupe_key=f"supplier_delayed:{it.id}:{day}",
                    action_route="/stock/low-stock?filter=delayed",
                    related_item_id=it.id,
                    owner_only=True,
                )

    if mismatch_inserted:
        await db.commit()

    return inserted + mismatch_inserted
