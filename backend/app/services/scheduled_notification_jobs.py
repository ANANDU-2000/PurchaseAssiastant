"""Scheduled in-app notifications: idle deliveries, evening physical-count reminder."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Business, TradePurchase
from app.services.notification_emitter import (
    CATEGORY_PURCHASE,
    CATEGORY_WAREHOUSE,
    PRIORITY_HIGH,
    PRIORITY_MEDIUM,
    emit_notification,
)

logger = logging.getLogger(__name__)

_IDLE_STATUSES = frozenset({"dispatched", "in_transit"})


async def run_idle_delivery_notification_scan(db: AsyncSession) -> int:
    """Notify owners when a purchase stays dispatched/in_transit ≥2 hours."""
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=2)
    day = now.strftime("%Y-%m-%d")

    rows = (
        await db.execute(
            select(TradePurchase).where(
                TradePurchase.delivery_status.in_(tuple(_IDLE_STATUSES)),
                TradePurchase.dispatched_at.isnot(None),
                TradePurchase.dispatched_at <= cutoff,
            )
        )
    ).scalars().all()
    if not rows:
        return 0

    inserted = 0
    for tp in rows:
        hid = tp.human_id or str(tp.id)[:8]
        n = await emit_notification(
            db,
            business_id=tp.business_id,
            kind="delivery_idle",
            title=f"Delivery idle · {hid}",
            body="Dispatched 2+ hours ago — follow up or mark arrived",
            priority=PRIORITY_HIGH,
            category=CATEGORY_PURCHASE,
            dedupe_key=f"delivery_idle:{tp.id}:{day}",
            action_route=f"/purchase/detail/{tp.id}",
            related_purchase_id=tp.id,
            owner_only=True,
            payload={"purchase_id": str(tp.id), "delivery_status": tp.delivery_status},
        )
        inserted += n

    if inserted:
        await db.commit()
    return inserted


async def run_evening_physical_count_reminder(db: AsyncSession) -> int:
    """Daily owner reminder to verify physical stock (18:00 IST job)."""
    now = datetime.now(timezone.utc)
    day = now.strftime("%Y-%m-%d")

    biz_rows = (await db.execute(select(Business.id))).all()
    if not biz_rows:
        return 0

    inserted = 0
    for (business_id,) in biz_rows:
        n = await emit_notification(
            db,
            business_id=business_id,
            kind="physical_count_reminder",
            title="Evening stock check",
            body="Review physical counts on the warehouse floor before closing",
            priority=PRIORITY_MEDIUM,
            category=CATEGORY_WAREHOUSE,
            dedupe_key=f"evening_physical:{business_id}:{day}",
            action_route="/stock",
            owner_only=True,
        )
        inserted += n

    if inserted:
        await db.commit()
    return inserted
