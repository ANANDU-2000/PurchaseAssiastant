"""Purchase damage / short-delivery reports."""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import TradePurchase, TradePurchaseLine, User
from app.models.purchase_damage_report import PurchaseDamageReport
from app.models.contacts import Supplier
from app.services.notification_emitter import (
    CATEGORY_PURCHASE,
    PRIORITY_HIGH,
    emit_notification,
)

_DAMAGE_LABELS = {
    "damaged": "damaged",
    "short": "short-delivered",
    "missing": "missing",
    "returned": "returned",
}

_VALID_REASONS = frozenset({"torn_bag", "wet_damage", "wrong_item", "short_weight", "other"})
_VALID_STATUS = frozenset({"pending", "approved", "returned", "rejected"})
_OWNER_PATCH_STATUS = frozenset({"approved", "returned", "rejected"})


def reason_to_damage_type(reason: str | None) -> str:
    if reason == "short_weight":
        return "short"
    if reason == "wrong_item":
        return "missing"
    return "damaged"


async def _load_purchase(
    db: AsyncSession, *, business_id: uuid.UUID, purchase_id: uuid.UUID
) -> TradePurchase:
    tp = (
        await db.execute(
            select(TradePurchase).where(
                TradePurchase.id == purchase_id,
                TradePurchase.business_id == business_id,
            )
        )
    ).scalar_one_or_none()
    if tp is None:
        raise LookupError("Purchase not found")
    return tp


async def _resolve_item_name(
    db: AsyncSession,
    *,
    purchase_id: uuid.UUID,
    item_name: str | None,
    catalog_item_id: uuid.UUID | None,
) -> str:
    name = (item_name or "").strip()
    if name:
        return name[:500]
    if catalog_item_id is None:
        raise ValueError("item_name or catalog_item_id is required")
    line = (
        await db.execute(
            select(TradePurchaseLine.item_name).where(
                TradePurchaseLine.trade_purchase_id == purchase_id,
                TradePurchaseLine.catalog_item_id == catalog_item_id,
            )
        )
    ).scalar_one_or_none()
    if line:
        return str(line).strip()[:500]
    raise ValueError("catalog_item_id not found on this purchase")


async def _supplier_name(db: AsyncSession, tp: TradePurchase) -> str:
    if not tp.supplier_id:
        return "supplier"
    sup = (
        await db.execute(select(Supplier.name).where(Supplier.id == tp.supplier_id))
    ).scalar_one_or_none()
    return str(sup).strip() if sup else "supplier"


async def _emit_damage_notification(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: User,
    tp: TradePurchase,
    damaged_items_count: int,
    dedupe_suffix: str,
) -> None:
    supplier_name = await _supplier_name(db, tp)
    staff_name = (user.name or user.email or "Staff").strip()
    ref = (tp.human_id or str(purchase_id)).strip()
    n = max(1, damaged_items_count)
    item_word = "item" if n == 1 else "items"
    title = f"Damage reported — {supplier_name}"
    body = (
        f"{staff_name} reported {n} damaged {item_word} in purchase #{ref}"
    )
    await emit_notification(
        db,
        business_id=business_id,
        kind="damage_report",
        title=title,
        body=body,
        priority=PRIORITY_HIGH,
        category=CATEGORY_PURCHASE,
        dedupe_key=f"damage_report:{purchase_id}:{dedupe_suffix}",
        action_route=f"/purchase/detail/{purchase_id}",
        triggered_by_user_id=user.id,
        related_purchase_id=purchase_id,
        target_roles=["owner", "admin", "manager"],
        payload={"damaged_items_count": n, "purchase_ref": ref},
    )


async def create_damage_report(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: User,
    qty_damaged: Decimal,
    item_name: str | None = None,
    damage_type: str | None = None,
    catalog_item_id: uuid.UUID | None = None,
    unit: str | None = None,
    reason: str | None = None,
    photo_url: str | None = None,
    notes: str | None = None,
    emit_notification: bool = True,
    damaged_items_in_batch: int | None = None,
) -> PurchaseDamageReport:
    tp = await _load_purchase(db, business_id=business_id, purchase_id=purchase_id)
    resolved_name = await _resolve_item_name(
        db,
        purchase_id=purchase_id,
        item_name=item_name,
        catalog_item_id=catalog_item_id,
    )

    reason_norm = (reason or "").strip().lower() or None
    if reason_norm and reason_norm not in _VALID_REASONS:
        raise ValueError("Invalid reason")

    if damage_type:
        dt = damage_type.strip().lower()
    elif reason_norm:
        dt = reason_to_damage_type(reason_norm)
    else:
        raise ValueError("damage_type or reason is required")

    if dt not in _DAMAGE_LABELS:
        raise ValueError("Invalid damage_type")

    row = PurchaseDamageReport(
        id=uuid.uuid4(),
        business_id=business_id,
        purchase_id=purchase_id,
        catalog_item_id=catalog_item_id,
        item_name=resolved_name,
        qty_damaged=qty_damaged,
        unit=(unit or "").strip()[:32] or None,
        damage_type=dt,
        reason=reason_norm,
        status="pending",
        photo_url=(photo_url or "").strip()[:2000] or None,
        notes=(notes or "").strip()[:4000] or None,
        reported_by_user_id=user.id,
    )
    db.add(row)

    if emit_notification:
        count = damaged_items_in_batch if damaged_items_in_batch is not None else 1
        await _emit_damage_notification(
            db,
            business_id=business_id,
            purchase_id=purchase_id,
            user=user,
            tp=tp,
            damaged_items_count=count,
            dedupe_suffix=str(row.id),
        )

    await db.commit()
    await db.refresh(row)
    return row


async def list_damage_reports(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
) -> list[tuple[PurchaseDamageReport, str | None]]:
    await _load_purchase(db, business_id=business_id, purchase_id=purchase_id)

    r = await db.execute(
        select(PurchaseDamageReport, User.name)
        .outerjoin(User, PurchaseDamageReport.reported_by_user_id == User.id)
        .where(
            PurchaseDamageReport.business_id == business_id,
            PurchaseDamageReport.purchase_id == purchase_id,
        )
        .order_by(PurchaseDamageReport.created_at.desc())
    )
    return list(r.all())


async def count_pending_damage_reports(
    db: AsyncSession, *, business_id: uuid.UUID
) -> int:
    n = (
        await db.execute(
            select(func.count())
            .select_from(PurchaseDamageReport)
            .where(
                PurchaseDamageReport.business_id == business_id,
                PurchaseDamageReport.status == "pending",
            )
        )
    ).scalar_one()
    return int(n or 0)


async def update_damage_report_status(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    report_id: uuid.UUID,
    status: str,
    notes: str | None = None,
) -> PurchaseDamageReport:
    st = status.strip().lower()
    if st not in _OWNER_PATCH_STATUS:
        raise ValueError("Invalid status")

    row = (
        await db.execute(
            select(PurchaseDamageReport).where(
                PurchaseDamageReport.id == report_id,
                PurchaseDamageReport.business_id == business_id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise LookupError("Damage report not found")

    prev_status = (row.status or "pending").strip().lower()
    row.status = st
    if notes is not None:
        extra = notes.strip()[:4000]
        if extra:
            row.notes = (
                f"{row.notes}\n---\n{extra}" if row.notes else extra
            )
    await db.commit()
    await db.refresh(row)

    if st == "approved" and prev_status != st:
        await _emit_damage_acknowledged_notification(
            db,
            business_id=business_id,
            row=row,
        )
        await db.commit()

    return row


async def _emit_damage_acknowledged_notification(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    row: PurchaseDamageReport,
) -> None:
    if not row.reported_by_user_id:
        return
    from app.services.notification_emitter import (
        CATEGORY_PURCHASE,
        PRIORITY_MEDIUM,
        emit_notification,
    )

    item_label = (row.item_name or "item").strip()
    await emit_notification(
        db,
        business_id=business_id,
        user_ids=[row.reported_by_user_id],
        kind="damage_acknowledged",
        title=f"Damage acknowledged — {item_label}",
        body=f"Your report was marked {row.status}",
        priority=PRIORITY_MEDIUM,
        category=CATEGORY_PURCHASE,
        dedupe_key=f"damage_acknowledged:{row.id}:{row.status}",
        action_route=f"/purchase/detail/{row.purchase_id}",
        related_purchase_id=row.purchase_id,
    )


def damage_report_to_out(
    row: PurchaseDamageReport, reporter_name: str | None = None
) -> dict:
    return {
        "id": row.id,
        "created_at": row.created_at,
        "reported_by": (reporter_name or "").strip() or None,
        "purchase_id": row.purchase_id,
        "catalog_item_id": row.catalog_item_id,
        "item_name": row.item_name,
        "qty_damaged": row.qty_damaged,
        "unit": row.unit,
        "damage_type": row.damage_type,
        "reason": row.reason,
        "status": row.status or "pending",
        "photo_url": row.photo_url,
        "notes": row.notes,
    }
