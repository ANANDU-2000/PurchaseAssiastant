"""Transaction-safe stock movement ledger helpers."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Literal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, User
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.stock_movement import StockMovement
from app.services.staff_audit import log_staff_activity
from app.services.stock_inventory import catalog_stock_qty
from app.services.unit_normalization import catalog_stock_unit

MovementMode = Literal["absolute", "delta"]


class StaleStockVersionError(ValueError):
    def __init__(self, *, current_version: int, current_qty: Decimal):
        super().__init__("Stock changed. Refresh and try again.")
        self.current_version = current_version
        self.current_qty = current_qty


@dataclass(frozen=True)
class StockMovementResult:
    movement: StockMovement
    item: CatalogItem
    duplicate: bool = False


def _actor_name(user: User) -> str:
    return (user.name or user.username or user.email or "User").strip()


def _activity_type_for(kind: str) -> str:
    k = (kind or "").strip().lower()
    if k == "quick_purchase":
        return "STOCK_QUICK_PURCHASE"
    if k == "damage":
        return "STOCK_DAMAGE_RECORDED"
    if k == "correction":
        return "STOCK_CORRECTION_RECORDED"
    if k == "sale":
        return "STOCK_SALE_ADJUSTMENT"
    if k == "opening_stock":
        return "OPENING_STOCK_SET"
    return "STOCK_PHYSICAL_UPDATE"


def _adjustment_type_for(kind: str) -> str:
    mapping = {
        "quick_purchase": "purchase",
        "physical_count": "verification",
        "damage": "damaged",
        "correction": "correction",
        "sale": "sale",
        "opening_stock": "opening_stock",
        "delivery_receive": "purchase",
        "delivery_revoke": "purchase_reversal",
        "usage": "usage",
        "undo": "correction",
    }
    return mapping.get((kind or "").strip().lower(), "manual")


async def _locked_item(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
) -> CatalogItem | None:
    stmt = (
        select(CatalogItem)
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
        .with_for_update()
    )
    r = await db.execute(stmt)
    return r.scalar_one_or_none()


async def apply_stock_movement(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    user: User,
    movement_kind: str,
    mode: MovementMode,
    qty: Decimal,
    reason: str | None,
    notes: str | None = None,
    source_type: str | None = None,
    source_id: uuid.UUID | None = None,
    idempotency_key: str | None = None,
    metadata: dict[str, Any] | None = None,
    last_seen_stock_version: int | None = None,
    create_projection: bool = True,
    create_activity: bool = True,
) -> StockMovementResult:
    """Apply one stock event and write ledger/projection rows in the same DB transaction.

    The caller owns commit/rollback. Additive operations use `mode="delta"` and
    absolute physical counts use `mode="absolute"`.
    """

    idem = (idempotency_key or "").strip()
    if idem:
        existing_r = await db.execute(
            select(StockMovement).where(
                StockMovement.business_id == business_id,
                StockMovement.idempotency_key == idem,
            )
        )
        existing = existing_r.scalar_one_or_none()
        if existing is not None:
            item = await _locked_item(db, business_id=business_id, item_id=existing.item_id)
            if item is None:
                raise ValueError("Item not found")
            return StockMovementResult(existing, item, duplicate=True)
    else:
        idem = f"{movement_kind}:{item_id}:{uuid.uuid4().hex}"

    item = await _locked_item(db, business_id=business_id, item_id=item_id)
    if item is None:
        raise ValueError("Item not found")

    current_version = int(getattr(item, "stock_version", 0) or 0)
    before = catalog_stock_qty(item)
    if last_seen_stock_version is not None and last_seen_stock_version != current_version:
        raise StaleStockVersionError(current_version=current_version, current_qty=before)

    raw_qty = Decimal(qty)
    if mode == "absolute":
        after = raw_qty
        delta = after - before
    else:
        delta = raw_qty
        after = before + delta
    if after < 0:
        raise ValueError("Stock cannot be negative")

    display = _actor_name(user)
    now = datetime.now(timezone.utc)
    unit = catalog_stock_unit(item)
    item.current_stock = after
    item.stock_version = current_version + 1
    item.last_stock_updated_at = now
    item.last_stock_updated_by = display

    movement = StockMovement(
        id=uuid.uuid4(),
        business_id=business_id,
        item_id=item_id,
        movement_kind=movement_kind,
        delta_qty=delta,
        qty_before=before,
        qty_after=after,
        stock_unit=unit,
        reason=(reason or "").strip() or None,
        notes=(notes or "").strip() or None,
        source_type=source_type,
        source_id=source_id,
        idempotency_key=idem,
        actor_id=user.id,
        actor_name=display,
        metadata_json=metadata or None,
        created_at=now,
    )
    db.add(movement)

    if create_projection:
        db.add(
            StockAdjustmentLog(
                business_id=business_id,
                item_id=item_id,
                old_qty=before,
                new_qty=after,
                adjustment_type=_adjustment_type_for(movement_kind),
                reason=movement.reason or reason,
                updated_by=user.id,
                updated_by_name=display,
                updated_at=now,
            )
        )

    if create_activity:
        await log_staff_activity(
            db,
            business_id=business_id,
            user=user,
            action_type=_activity_type_for(movement_kind),
            item_id=item_id,
            item_name=item.name,
            details={
                "movement_kind": movement_kind,
                "source_type": source_type,
                "source_id": str(source_id) if source_id else None,
                "stock_unit": unit,
                "reason": movement.reason,
                "notes": movement.notes,
                "idempotency_key": idem,
            },
            before_data={
                "qty": float(before),
                "stock_version": current_version,
            },
            after_data={
                "qty": float(after),
                "delta_qty": float(delta),
                "stock_version": current_version + 1,
            },
        )

    return StockMovementResult(movement, item)
