"""Notify owners when physical stock count diverges from post-purchase expectation."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, Membership
from app.models.notification import AppNotification
from app.models.stock_adjustment import StockAdjustmentLog

_VARIANCE_MIN_UNITS = Decimal("2")
_VARIANCE_MIN_RATIO = Decimal("0.02")


async def _last_purchase_expected_qty(
    db: AsyncSession, business_id: uuid.UUID, item_id: uuid.UUID
) -> Decimal | None:
    r = await db.execute(
        select(StockAdjustmentLog.new_qty)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
            StockAdjustmentLog.adjustment_type == "purchase",
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(1)
    )
    row = r.scalar_one_or_none()
    return Decimal(row) if row is not None else None


def _is_material_variance(expected: Decimal, found: Decimal) -> bool:
    delta = abs(found - expected)
    if delta < _VARIANCE_MIN_UNITS:
        if expected > 0 and (delta / expected) >= _VARIANCE_MIN_RATIO:
            return True
        return False
    return True


async def maybe_notify_stock_variance(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    adjustment_type: str,
    new_qty: Decimal,
) -> tuple[Decimal | None, Decimal | None]:
    """If verification/correction diverges from last purchase qty, queue owner notifications."""
    if adjustment_type not in ("verification", "correction", "manual"):
        return None, None
    expected = await _last_purchase_expected_qty(db, business_id, item_id)
    if expected is None:
        return None, None
    if not _is_material_variance(expected, new_qty):
        return None, None

    delta = new_qty - expected
    ir = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
        )
    )
    item = ir.scalar_one_or_none()
    if not item:
        return None, None

    unit = item.stock_unit or item.default_unit or ""
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    mems = await db.execute(
        select(Membership.user_id).where(Membership.business_id == business_id)
    )
    for (uid,) in mems.all():
        dedupe = f"stock_variance:{item_id}:{day}:{uid}"
        ex = await db.execute(
            select(AppNotification.id).where(
                AppNotification.business_id == business_id,
                AppNotification.dedupe_key == dedupe,
            ).limit(1)
        )
        if ex.scalar_one_or_none() is not None:
            continue
        db.add(
            AppNotification(
                id=uuid.uuid4(),
                business_id=business_id,
                user_id=uid,
                kind="stock_variance",
                title="Stock variance",
                body=(
                    f"{item.name}: expected {_fmt(expected)} {unit}, "
                    f"found {_fmt(new_qty)} {unit} ({_fmt(delta)} diff)"
                ),
                payload={
                    "item_id": str(item_id),
                    "item_name": item.name,
                    "expected_qty": float(expected),
                    "found_qty": float(new_qty),
                    "variance_delta": float(delta),
                    "unit": unit,
                },
                dedupe_key=dedupe,
            )
        )
    return expected, delta


def _fmt(v: Decimal) -> str:
    if v == v.to_integral_value():
        return str(int(v))
    return f"{v:.2f}"
