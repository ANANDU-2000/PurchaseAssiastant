import asyncio
import hashlib
import json
import logging
import uuid
from collections import defaultdict
from time import monotonic
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse, Response
from sqlalchemy import and_, case, desc, func, literal, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.deps import get_current_user, require_membership, require_permission, require_role
from app.services.staff_audit import log_staff_activity, log_staff_activity_best_effort
from app.services.notification_emitter import CATEGORY_STAFF, publish_notification_changed
from app.services.stock_inventory import (
    catalog_reorder,
    catalog_stock_qty,
    compute_inventory_summary,
    compute_stock_alerts_summary,
    movement_delivered_qty_map,
    stock_status,
)
from app.models import (
    Broker,
    CatalogItem,
    CategoryType,
    DailyUsageLog,
    ItemCategory,
    Membership,
    StaffActivityLog,
    StaffChecklistCompletion,
    StaffChecklistTemplate,
    StockMovement,
    Supplier,
    TradePurchase,
    TradePurchaseLine,
    User,
)
from app.models.notification import AppNotification
from app.models.reorder_list import ReorderListEntry
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.stock_physical_count import StockPhysicalCount
from app.models.staff_purchase_log import StaffPurchaseLog
from app.schemas.stock_audit import StockVerifyCountIn
from app.schemas.stock import (
    BarcodeBatchIn,
    BarcodeBatchOut,
    BarcodeLabelOut,
    BarcodeLookupOut,
    StockAdjustmentOut,
    StockVarianceOut,
    StockDetailOut,
    StockIntelligenceOut,
    StockDeliveryIndicatorCountsOut,
    StockListItemOut,
    StockListItemMinimalOut,
    StockListOut,
    StockListCompactOut,
    StockPatchIn,
    RecentPurchaseOut,
    ReorderListEntryOut,
    ReorderListOut,
    ReorderListPatchIn,
    InventorySummaryOut,
    OpeningStockIn,
    OpeningStockMissingOut,
    OpeningStockSetupOut,
    OpeningStockSetupItemOut,
    OpeningStockSetupSummaryOut,
    PhysicalStockCountIn,
    PhysicalStockCountOut,
    StockTotalsOut,
    StockAlertsSummaryOut,
    WarehouseAlertsSummaryOut,
    LowStockOpsSummaryOut,
    LowStockOpsItemOut,
    LowStockOpsOut,
    StaffPurchaseLogIn,
    StaffPurchaseLogOut,
    QuickPurchaseIn,
    QuickPurchaseOut,
    StockActivityEventOut,
    StockItemActivityOut,
    StockMovementOut,
    StockPhysicalUpdateIn,
    StockPhysicalUpdateOut,
)
from app.services import trade_query as tq
from app.services.staff_view import should_redact_financials
from app.services.low_stock_priority import compute_low_stock_priority
from app.services.low_stock_ops_enrichment import (
    derive_lifecycle_stage,
    item_is_disputed,
    open_dispute_item_ids,
    rejected_audit_item_ids,
    reorder_status_map,
)
from app.services.stock_movement_service import (
    NegativeStockError,
    StaleStockVersionError,
    apply_stock_movement,
    apply_stock_movement_with_retry,
)
from app.services.realtime_events import publish_business_event
from app.services.stock_variance_notifications import (
    maybe_notify_staff_system_stock_edit,
    maybe_notify_stock_variance,
)
from app.services.stock_tracking_profile import profile_from_catalog_item
from app.services.unit_normalization import (
    catalog_stock_unit,
    current_stock_kg as stock_qty_kg_equivalent,
    line_qty_in_stock_unit,
)
from app.services import stock_helpers as sh
from app.services.stock_helpers import OpeningSetupStatus, SortBy, StatusFilter

logger = logging.getLogger(__name__)


from app.routers.stock.stock_audit import _movement_out, _staff_purchase_out
router = APIRouter()

@router.get("/items/{item_id}/purchase-intelligence")
async def get_item_purchase_intelligence(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    rows_r = await db.execute(
        select(
            TradePurchaseLine.qty,
            TradePurchase.created_at,
            TradePurchase.supplier_id,
        )
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchaseLine.catalog_item_id == item_id,
            TradePurchase.status.notin_(("cancelled", "deleted")),
        )
        .order_by(desc(TradePurchase.created_at))
        .limit(12)
    )
    rows = rows_r.all()
    if not rows:
        return {"suggested_qty": None, "avg_interval_days": None, "default_supplier": None}

    qtys = [float(r[0] or 0) for r in rows]
    avg_qty = sum(qtys) / max(len(qtys), 1)

    dates = [r[1] for r in rows if r[1] is not None]
    avg_interval_days = None
    if len(dates) >= 2:
        ordered = sorted(dates)
        diffs = []
        for i in range(len(ordered) - 1):
            d = (ordered[i + 1] - ordered[i]).days
            if d > 0:
                diffs.append(d)
        if diffs:
            avg_interval_days = round(sum(diffs) / len(diffs))

    supplier_counts: dict[str, int] = {}
    for _, _, sid in rows:
        if sid is None:
            continue
        k = str(sid)
        supplier_counts[k] = supplier_counts.get(k, 0) + 1
    top_supplier = max(supplier_counts, key=lambda k: supplier_counts[k]) if supplier_counts else None
    default_supplier = None
    if top_supplier:
        supp_r = await db.execute(
            select(Supplier.id, Supplier.name).where(Supplier.id == top_supplier)
        )
        srow = supp_r.first()
        if srow:
            default_supplier = {"id": str(srow[0]), "name": srow[1] or "Supplier"}

    return {
        "suggested_qty": round(avg_qty),
        "avg_interval_days": avg_interval_days,
        "default_supplier": default_supplier,
    }
async def _membership_role_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_ids: set[uuid.UUID],
) -> dict[uuid.UUID, str]:
    if not user_ids:
        return {}
    r = await db.execute(
        select(Membership.user_id, Membership.role).where(
            Membership.business_id == business_id,
            Membership.user_id.in_(user_ids),
        )
    )
    return {uid: (role or "staff") for uid, role in r.all()}
def _staff_activity_event(ev: StaffActivityLog, *, actor_role: str | None) -> StockActivityEventOut:
    details = ev.details if isinstance(ev.details, dict) else {}
    before = details.get("before") if isinstance(details.get("before"), dict) else {}
    after = details.get("after") if isinstance(details.get("after"), dict) else {}
    qty_before = before.get("system_qty")
    qty_after = after.get("counted_qty")
    delta = None
    if qty_before is not None and qty_after is not None:
        try:
            delta = Decimal(str(qty_after)) - Decimal(str(qty_before))
        except Exception:
            delta = None
    title = ev.action_type.replace("_", " ").title()
    if ev.action_type == "PHYSICAL_STOCK_COUNT":
        title = "Physical count recorded"
    elif ev.action_type == "STOCK_UPDATE":
        title = "Stock updated"
    return StockActivityEventOut(
        id=str(ev.id),
        kind=ev.action_type,
        title=title,
        qty_before=Decimal(str(qty_before)) if qty_before is not None else None,
        qty_after=Decimal(str(qty_after)) if qty_after is not None else None,
        delta_qty=delta,
        actor_name=ev.user_name,
        actor_role=actor_role,
        notes=details.get("notes") if isinstance(details.get("notes"), str) else None,
        created_at=ev.created_at,
        source_type="staff_activity_log",
        source_id=str(ev.id),
    )
async def _activity_stock_item_header(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
) -> StockDetailOut:
    """Lightweight catalog row for activity response (client also fetches full stock detail)."""
    r = await db.execute(
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    row = r.one_or_none()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    catalog_item, category_name, subcategory_name = row
    supplier_name = await sh._supplier_name(db, catalog_item)
    phys = (await sh._latest_physical_count_map(db, business_id, [item_id])).get(item_id)
    phys_qty = phys.counted_qty if phys else None
    spec_diff = phys.difference_qty if phys else None
    if spec_diff is None and phys_qty is not None:
        spec_diff = phys_qty - catalog_stock_qty(catalog_item)
    list_row = sh._item_to_list_row(
        catalog_item,
        category_name,
        subcategory_name,
        supplier_name,
        physical_stock_qty=phys_qty,
        physical_stock_difference_qty=spec_diff,
        physical_stock_counted_at=phys.counted_at if phys else None,
        physical_stock_counted_by=phys.counted_by_name if phys else None,
    )
    return StockDetailOut(**list_row.model_dump(), recent_purchases=[])
@router.get("/{item_id}/activity", response_model=StockItemActivityOut)
async def stock_item_activity(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    membership: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0, le=5000),
    kind: str | None = Query(None, description="Comma-separated movement kinds filter (purchase,physical_count,damage,correction,sale,transfer,staff_purchase_log,staff_activity_log)."),
):
    item = await _activity_stock_item_header(db, business_id, item_id)
    kinds = [k.strip() for k in (kind or "").split(",") if k.strip()]
    movement_q = (
        select(StockMovement)
        .where(
            StockMovement.business_id == business_id,
            StockMovement.item_id == item_id,
        )
        .order_by(desc(StockMovement.created_at))
        .offset(offset)
        .limit(limit)
    )
    if kinds:
        movement_q = movement_q.where(StockMovement.movement_kind.in_(kinds))
    movement_r = await db.execute(movement_q)
    movements = list(movement_r.scalars().all())
    purchase_q = (
        select(StaffPurchaseLog)
        .where(
            StaffPurchaseLog.business_id == business_id,
            StaffPurchaseLog.item_id == item_id,
        )
        .order_by(desc(StaffPurchaseLog.created_at))
        .offset(offset)
        .limit(limit)
    )
    if kinds and "staff_purchase_log" not in kinds:
        purchase_q = purchase_q.where(literal(False))
    purchase_r = await db.execute(purchase_q)
    purchases = list(purchase_r.scalars().all())
    staff_q = (
        select(StaffActivityLog)
        .where(
            StaffActivityLog.business_id == business_id,
            StaffActivityLog.item_id == item_id,
        )
        .order_by(desc(StaffActivityLog.created_at))
        .offset(offset)
        .limit(limit)
    )
    if kinds:
        # staff log uses action_type as kind, but keep it behind explicit allow.
        allow_staff = "staff_activity_log" in kinds
        if not allow_staff:
            staff_q = staff_q.where(literal(False))
    staff_r = await db.execute(staff_q)
    staff_events = list(staff_r.scalars().all())
    actor_ids: set[uuid.UUID] = {m.actor_id for m in movements if m.actor_id}
    actor_ids |= {ev.user_id for ev in staff_events if ev.user_id}
    role_map = await _membership_role_map(db, business_id, actor_ids)
    events: list[StockActivityEventOut] = []
    for m in movements:
        title = {
            "quick_purchase": "Purchase quantity added",
            "physical_count": "Physical stock updated",
            "delivery_receive": "Purchase delivered to system",
            "damage": "Damage recorded",
            "correction": "System stock corrected",
            "sale": "Sale adjustment",
        }.get(m.movement_kind, m.movement_kind.replace("_", " ").title())
        events.append(
            StockActivityEventOut(
                id=str(m.id),
                kind=m.movement_kind,
                title=title,
                qty_before=m.qty_before,
                qty_after=m.qty_after,
                delta_qty=m.delta_qty,
                unit=m.stock_unit,
                reason=m.reason,
                notes=m.notes,
                actor_name=m.actor_name,
                actor_role=role_map.get(m.actor_id) if m.actor_id else None,
                created_at=m.created_at,
                source_type=m.source_type,
                source_id=str(m.source_id) if m.source_id else None,
            )
        )
    for p in purchases:
        events.append(
            StockActivityEventOut(
                id=str(p.id),
                kind="staff_purchase_log",
                title="Staff purchase entry",
                delta_qty=p.qty,
                unit=p.unit,
                notes=p.notes,
                actor_name=p.created_by_name,
                supplier_name=p.supplier_name,
                broker_name=getattr(p, "broker_name", None),
                created_at=p.created_at,
                source_type="staff_purchase_log",
                source_id=str(p.id),
            )
        )
    for ev in staff_events:
        events.append(
            _staff_activity_event(
                ev,
                actor_role=role_map.get(ev.user_id) if ev.user_id else None,
            )
        )
    events.sort(key=lambda e: e.created_at, reverse=True)
    return StockItemActivityOut(
        item=item,
        movements=[_movement_out(m, item_name=item.name) for m in movements],
        purchases=[_staff_purchase_out(p) for p in purchases],
        activity=events[:limit],
    )
@router.get("/{item_id}/intelligence", response_model=StockIntelligenceOut)
async def get_stock_intelligence(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
):
    r = await db.execute(
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    row = r.one_or_none()
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    item, cat_name, type_name = row
    supplier_name = await sh._supplier_name(db, item)
    cur = catalog_stock_qty(item)
    ro = catalog_reorder(item)
    unit = item.stock_unit or item.default_unit or item.selling_unit
    purchased = Decimal("0")
    period_usage = Decimal("0")
    ps, pe = sh._parse_period_dates(period_start, period_end)
    if ps and pe:
        m = await sh._period_purchased_map(db, business_id, [item_id], ps, pe)
        purchased = m.get(item_id, Decimal("0"))
        um = await sh._period_usage_map(db, business_id, [item_id], ps, pe)
        period_usage = um.get(item_id, Decimal("0"))
    ledger_map = await sh._ledger_variance_map(db, business_id, [item])
    ledger_var = ledger_map.get(item_id)
    su = catalog_stock_unit(item)
    purchases = await sh._recent_purchases(db, item)
    if should_redact_financials(_m.role):
        purchases = [
            p.model_copy(update={"rate": None}) if hasattr(p, "model_copy") else p
            for p in purchases
        ]
    adj_r = await db.execute(
        select(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(8)
    )
    adjustments = [
        StockAdjustmentOut.model_validate(a) for a in adj_r.scalars().all()
    ]
    profile = profile_from_catalog_item(item)
    return StockIntelligenceOut(
        id=item.id,
        item_code=item.item_code,
        name=item.name,
        category_name=cat_name,
        subcategory_name=type_name,
        supplier_name=supplier_name,
        barcode=getattr(item, "barcode", None),
        default_kg_per_bag=getattr(item, "default_kg_per_bag", None),
        stock_unit=su,
        stock_tracking=profile.as_dict(),
        current_stock_kg=stock_qty_kg_equivalent(item, cur),
        last_stock_updated_at=getattr(item, "last_stock_updated_at", None),
        last_stock_updated_by=getattr(item, "last_stock_updated_by", None),
        current_stock=cur,
        reorder_level=ro,
        unit=unit,
        stock_status=stock_status(cur, ro),
        period_purchased_qty=purchased,
        period_usage_qty=period_usage,
        period_variance_qty=ledger_var,
        ledger_variance_qty=ledger_var,
        needs_verification=(
            abs(ledger_var) / purchased > Decimal("0.1")
            if ledger_var is not None and purchased > 0
            else sh._needs_verification(cur, purchased)
        ),
        recent_purchases=purchases,
        recent_adjustments=adjustments,
    )
@router.get("/item/{item_id}/summary")
async def get_stock_item_summary(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    """Lightweight row fields for list patch reconciliation after a stock write."""
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    phys = (await sh._latest_physical_count_map(db, business_id, [item_id])).get(item_id)
    cur = catalog_stock_qty(item)
    phys_qty = phys.counted_qty if phys else None
    spec_diff = phys.difference_qty if phys else None
    if spec_diff is None and phys_qty is not None:
        spec_diff = phys_qty - cur
    updated_at = item.last_stock_updated_at or item.updated_at
    return {
        "id": str(item.id),
        "current_stock": float(cur),
        "physical_stock_qty": float(phys_qty) if phys_qty is not None else None,
        "physical_stock_difference_qty": float(spec_diff) if spec_diff is not None else None,
        "physical_stock_counted_at": phys.counted_at.isoformat() if phys and phys.counted_at else None,
        "stock_version": getattr(item, "stock_version", None),
        "updated_at": updated_at.isoformat() if updated_at else None,
    }
@router.get("/{item_id}/bundle")
async def stock_item_bundle(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    membership: Annotated[Membership, Depends(require_membership)],
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
):
    """Single round-trip for item detail warm-up (detail + activity + intelligence + catalog)."""
    from app.routers.catalog import get_catalog_item

    detail, activity, intelligence, catalog = await asyncio.gather(
        get_stock_item(
            business_id,
            item_id,
            db,
            membership,
            period_start=period_start,
            period_end=period_end,
        ),
        stock_item_activity(
            business_id,
            item_id,
            db,
            membership,
        ),
        get_stock_intelligence(
            business_id,
            item_id,
            db,
            membership,
            period_start=period_start,
            period_end=period_end,
        ),
        get_catalog_item(business_id, item_id, membership, db),
    )
    return {
        "detail": detail,
        "activity": activity,
        "intelligence": intelligence,
        "catalog_snapshot": catalog,
    }
@router.get("/{item_id}", response_model=StockDetailOut)
async def get_stock_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
):
    r = await db.execute(
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    row = r.one_or_none()
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    item, cat_name, type_name = row
    sup = await sh._supplier_name(db, item)
    phys = (await sh._latest_physical_count_map(db, business_id, [item_id])).get(item_id)
    trade_meta = await sh._last_trade_meta_map(db, [item])
    meta = trade_meta.get(item_id, (None, None))
    valid_last_trade = meta[0] is not None
    last_delivered = meta[1] if valid_last_trade else False
    last_lq = getattr(item, "last_line_qty", None) if valid_last_trade else None
    last_pur_at = getattr(item, "last_purchase_at", None) if valid_last_trade else None
    movement_delivered = await movement_delivered_qty_map(db, business_id, [item_id])
    total_delivered = movement_delivered.get(item_id, Decimal(0))
    _, pending_lifetime_map = await sh._lifetime_purchase_qty_maps(
        db, business_id, [item_id]
    )
    total_pending_lifetime = pending_lifetime_map.get(item_id)
    pend = (await sh._pending_order_meta_map(db, business_id, [item_id])).get(
        item_id, (False, None, None)
    )
    ps, pe = sh._parse_period_dates(period_start, period_end)
    purchased = None
    usage = None
    ledger_var = None
    verify = False
    if ps and pe:
        period_map = await sh._period_purchased_map(db, business_id, [item_id], ps, pe)
        purchased = period_map.get(item_id)
        usage_map = await sh._period_usage_map(db, business_id, [item_id], ps, pe)
        usage = usage_map.get(item_id)
        ledger_map = await sh._ledger_variance_map(db, business_id, [item])
        ledger_var = ledger_map.get(item_id)
        cur = catalog_stock_qty(item)
        if ledger_var is not None and purchased is not None and purchased > 0:
            verify = abs(ledger_var) / purchased > Decimal("0.1")
        elif purchased is not None and purchased > 0:
            verify = sh._needs_verification(cur, purchased)
    base = sh._item_to_list_row(
        item,
        cat_name,
        type_name,
        sup,
        period_purchased_qty=purchased,
        period_usage_qty=usage,
        ledger_variance_qty=ledger_var,
        stock_unit=catalog_stock_unit(item),
        needs_verification=verify,
        last_purchase_human_id=meta[0] if valid_last_trade else None,
        last_purchase_delivered=last_delivered,
        last_line_qty=last_lq,
        last_purchase_at=last_pur_at,
        has_pending_order=pend[0],
        pending_order_days=pend[1],
        pending_delivery_qty=pend[2],
        physical_stock_qty=phys.counted_qty if phys else None,
        physical_stock_difference_qty=phys.difference_qty if phys else None,
        physical_stock_counted_at=phys.counted_at if phys else None,
        physical_stock_counted_by=phys.counted_by_name if phys else None,
        total_delivered_qty=total_delivered,
        total_pending_delivery_qty=total_pending_lifetime or pend[2],
    )
    purchases = await sh._recent_purchases(db, item)
    if should_redact_financials(_m.role):
        purchases = [
            p.model_copy(update={"rate": None}) if hasattr(p, "model_copy") else p
            for p in purchases
        ]
    return StockDetailOut(**base.model_dump(), recent_purchases=purchases)
def _physical_count_out(
    item: CatalogItem,
    entry: StockPhysicalCount,
) -> PhysicalStockCountOut:
    return PhysicalStockCountOut(
        id=entry.id,
        item_id=entry.item_id,
        item_name=item.name,
        system_qty=entry.system_qty,
        counted_qty=entry.counted_qty,
        difference_qty=entry.difference_qty,
        purchased_qty=entry.purchased_qty,
        stock_unit=entry.stock_unit,
        period_start=entry.period_start.isoformat() if entry.period_start else None,
        period_end=entry.period_end.isoformat() if entry.period_end else None,
        notes=entry.notes,
        counted_by_name=entry.counted_by_name,
        counted_at=entry.counted_at,
    )
@router.post("/{item_id}/opening-stock", response_model=StockDetailOut)
async def set_opening_stock(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: OpeningStockIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_role("owner", "super_admin"))],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    qty = Decimal(body.qty)
    prev_opening = getattr(item, "opening_stock_qty", None)
    already_set = item.opening_stock_set_at is not None
    if already_set and prev_opening is not None and qty != prev_opening:
        if not (body.reason and body.reason.strip()):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="Reason required when changing opening stock",
            )
    reason = (body.reason or "").strip() or "Opening stock setup"
    notes = body.notes.strip() if body.notes else None
    idem = body.idempotency_key
    if not idem and already_set:
        idem = f"opening_stock:{item_id}:{uuid.uuid4().hex[:12]}"
    try:
        result = await apply_stock_movement(
            db,
            business_id=business_id,
            item_id=item_id,
            user=user,
            movement_kind="opening_stock",
            mode="absolute",
            qty=qty,
            reason=reason,
            notes=notes,
            source_type="opening_stock_setup",
            idempotency_key=idem,
        )
    except NegativeStockError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    item = result.item
    display = sh._user_display(user)
    now = datetime.now(timezone.utc)
    item.opening_stock_qty = qty
    item.opening_stock_set_at = now
    item.opening_stock_set_by = display
    item.opening_stock_locked = True
    await db.commit()
    await db.refresh(result.movement)
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item_id),
            "movement_id": str(result.movement.id),
            "kind": "opening_stock",
        },
    )
    return await get_stock_item(
        business_id,
        item_id,
        db,
        _m,
        period_start=None,
        period_end=None,
    )
@router.post("/{item_id}/physical-count", response_model=PhysicalStockCountOut)
async def record_physical_stock_count(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: PhysicalStockCountIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
    force: bool = Query(
        False,
        description=(
            "No-op for this route: physical count is observation-only and does not "
            "use stock_version optimistic locking."
        ),
    ),
):
    """Record a physical count without mutating authoritative stock.

    Does not read ``last_seen_stock_version`` or bump ``stock_version``; concurrent
    system stock edits do not block this endpoint (no 409 from version drift).
    """
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    counted = Decimal(body.counted_qty)
    system_qty = catalog_stock_qty(item)
    ps, pe = sh._parse_period_dates(body.period_start, body.period_end)
    purchased_qty: Decimal | None = None
    if ps and pe:
        purchased_qty = (await sh._period_purchased_map(db, business_id, [item_id], ps, pe)).get(
            item_id, Decimal("0")
        )
    display = sh._user_display(user)
    entry = StockPhysicalCount(
        business_id=business_id,
        item_id=item_id,
        system_qty=system_qty,
        counted_qty=counted,
        difference_qty=counted - system_qty,
        purchased_qty=purchased_qty,
        stock_unit=catalog_stock_unit(item),
        period_start=ps,
        period_end=pe,
        notes=body.notes.strip() if body.notes else None,
        counted_by=user.id,
        counted_by_name=display,
    )
    db.add(entry)
    await db.flush()
    await log_staff_activity_best_effort(
        db,
        business_id=business_id,
        user=user,
        action_type="PHYSICAL_STOCK_COUNT",
        item_id=item_id,
        item_name=item.name,
        before_data={"system_qty": float(system_qty)},
        after_data={
            "counted_qty": float(counted),
            "difference_qty": float(counted - system_qty),
        },
    )
    await db.commit()
    await db.refresh(entry)
    return _physical_count_out(item, entry)
@router.post("/{item_id}/physical-update", response_model=StockPhysicalUpdateOut)
async def update_physical_stock(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: StockPhysicalUpdateIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
    force: bool = Query(
        False,
        description=(
            "Skip optimistic version check after explicit user warning (staff/owner)."
        ),
    ),
):
    kind = {
        "verification": "physical_count",
        "damaged": "damage",
        "correction": "correction",
        "sale": "sale",
    }.get(body.adjustment_type, "physical_count")
    # Only verification may tolerate small read drift; corrections/deltas must
    # reject stale versions so two staff devices cannot apply conflicting edits.
    version_tolerance = 2 if body.adjustment_type == "verification" else 0
    try:
        result = await apply_stock_movement_with_retry(
            db,
            business_id=business_id,
            item_id=item_id,
            user=user,
            movement_kind=kind,
            mode="absolute",
            qty=Decimal(body.counted_qty),
            reason=body.reason,
            notes=body.notes,
            source_type="physical_update",
            idempotency_key=body.idempotency_key,
            last_seen_stock_version=body.last_seen_stock_version,
            force_version=force,
            version_tolerance=version_tolerance,
        )
    except StaleStockVersionError as e:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": "STALE_STOCK_VERSION",
                "message": str(e),
                "current_stock": str(e.current_qty),
                "stock_version": e.current_version,
            },
        ) from e
    except NegativeStockError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from e
    except ValueError as e:
        if str(e) == "Item not found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found") from e
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    await maybe_notify_stock_variance(
        db,
        business_id=business_id,
        item_id=item_id,
        adjustment_type=body.adjustment_type,
        new_qty=result.movement.qty_after,
    )
    counted = Decimal(body.counted_qty)
    system_before = result.movement.qty_before
    ps, pe = sh._parse_period_dates(body.period_start, body.period_end)
    purchased_qty: Decimal | None = None
    if ps and pe:
        purchased_qty = (
            await sh._period_purchased_map(db, business_id, [item_id], ps, pe)
        ).get(item_id, Decimal("0"))
    item_r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    count_item = item_r.scalar_one_or_none()
    if count_item is not None:
        display = sh._user_display(user)
        db.add(
            StockPhysicalCount(
                business_id=business_id,
                item_id=item_id,
                system_qty=system_before,
                counted_qty=counted,
                difference_qty=counted - system_before,
                purchased_qty=purchased_qty,
                stock_unit=catalog_stock_unit(count_item),
                period_start=ps,
                period_end=pe,
                notes=body.notes.strip() if body.notes else None,
                counted_by=user.id,
                counted_by_name=display,
            )
        )
    await db.commit()
    await db.refresh(result.movement)
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item_id),
            "movement_id": str(result.movement.id),
            "kind": kind,
        },
    )
    item = await get_stock_item(business_id, item_id, db, membership)
    return StockPhysicalUpdateOut(
        item=item,
        movement=_movement_out(
            result.movement,
            item_name=item.name,
            duplicate=result.duplicate,
        ),
    )
@router.post("/{item_id}/verify-count", response_model=StockDetailOut)
async def verify_stock_count(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: StockVerifyCountIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    """Physical count from barcode scan — sets stock to counted qty with mandatory reason on variance."""
    from app.services.stock_audit_service import apply_audit_line_to_stock
    r = await db.execute(
        select(CatalogItem)
        .options(selectinload(CatalogItem.category))
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    old_qty = catalog_stock_qty(item)
    counted = Decimal(body.counted_qty)
    if counted < 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Stock cannot be negative")
    diff = old_qty - counted
    if diff != 0 and not (body.reason and body.reason.strip()):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Reason required when counted stock differs from system",
        )

    await apply_audit_line_to_stock(
        db,
        business_id=business_id,
        user=user,
        item=item,
        counted_qty=counted,
        adjustment_type=body.adjustment_type,
        reason=body.reason + (f" — {body.notes}" if body.notes else ""),
        audit_id=None,
    )
    await log_staff_activity_best_effort(
        db,
        business_id=business_id,
        user=user,
        action_type="BARCODE_COUNT_VERIFY",
        item_id=item_id,
        item_name=item.name,
        before_data={"qty": float(old_qty)},
        after_data={"qty": float(counted), "type": body.adjustment_type},
    )
    await maybe_notify_stock_variance(
        db,
        business_id=business_id,
        item_id=item_id,
        adjustment_type=body.adjustment_type,
        new_qty=counted,
    )
    await db.commit()
    await db.refresh(item)
    return await get_stock_item(business_id, item_id, db, membership)
@router.patch("/{item_id}", response_model=StockDetailOut)
async def patch_stock_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: StockPatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
    force: bool = Query(
        False,
        description=(
            "Skip optimistic version check after explicit user warning (staff/owner)."
        ),
    ),
):
    item_r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = item_r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    role = (_membership.role or "").strip().lower()
    if bool(getattr(item, "opening_stock_locked", False)) and role not in (
        "owner",
        "super_admin",
        "admin",
    ):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail="Opening stock is locked — only the owner can adjust this item",
        )
    kind = {
        "verification": "physical_count",
        "damaged": "damage",
        "correction": "correction",
        "sale": "sale",
    }.get(body.adjustment_type, body.adjustment_type)
    version_tolerance = 2 if body.adjustment_type == "verification" else 0
    try:
        result = await apply_stock_movement_with_retry(
            db,
            business_id=business_id,
            item_id=item_id,
            user=user,
            movement_kind=kind,
            mode="absolute",
            qty=Decimal(body.new_qty),
            reason=body.reason or body.adjustment_type,
            source_type="stock_patch",
            idempotency_key=body.idempotency_key,
            last_seen_stock_version=body.last_seen_stock_version,
            force_version=force,
            version_tolerance=version_tolerance,
        )
    except StaleStockVersionError as e:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": "STALE_STOCK_VERSION",
                "message": str(e),
                "current_stock": str(e.current_qty),
                "stock_version": e.current_version,
            },
        ) from e
    except NegativeStockError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from e
    except ValueError as e:
        if str(e) == "Item not found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found") from e
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    await maybe_notify_stock_variance(
        db,
        business_id=business_id,
        item_id=item_id,
        adjustment_type=body.adjustment_type,
        new_qty=result.movement.qty_after,
        triggered_by_user_id=user.id,
    )
    item = result.item
    unit = catalog_stock_unit(item) or item.default_unit or ""
    await maybe_notify_staff_system_stock_edit(
        db,
        business_id=business_id,
        item_id=item_id,
        item_name=item.name,
        unit=unit,
        old_qty=result.movement.qty_before,
        new_qty=result.movement.qty_after,
        actor_user_id=user.id,
        actor_display=sh._user_display(user),
        actor_role=_membership.role or "",
    )
    await db.commit()
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item_id),
            "movement_id": str(result.movement.id),
            "kind": kind,
        },
    )

    return await get_stock_item(business_id, item_id, db, _membership)
@router.post("/{item_id}/undo-last", response_model=StockDetailOut)
async def undo_last_stock_change(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    """Revert the user's most recent stock adjustment within 15 minutes."""
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=15)
    r = await db.execute(
        select(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
            StockAdjustmentLog.updated_by == user.id,
            StockAdjustmentLog.updated_at >= cutoff,
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(1)
    )
    log = r.scalar_one_or_none()
    if not log:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail="No recent stock change to undo",
        )
    if log.adjustment_type in ("opening_stock", "opening_stock_setup") and (
        _membership.role or ""
    ) not in (
        "owner",
        "super_admin",
        "admin",
    ):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail="Opening stock cannot be undone. Contact owner.",
        )
    item_r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = item_r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    revert_to = log.old_qty
    try:
        result = await apply_stock_movement(
            db,
            business_id=business_id,
            item_id=item_id,
            user=user,
            movement_kind="undo",
            mode="absolute",
            qty=revert_to,
            reason="Undo previous adjustment",
            source_type="undo",
            source_id=log.id,
            idempotency_key=f"undo:{log.id}",
        )
    except NegativeStockError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from e
    except ValueError as e:
        if str(e) == "Item not found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found") from e
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    await db.commit()
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item_id),
            "movement_id": str(result.movement.id),
            "kind": "undo",
        },
    )
    return await get_stock_item(business_id, item_id, db, _membership)
@router.post("/{item_id}/notify-owner", status_code=status.HTTP_201_CREATED)
async def notify_owner_about_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    alert: str = Query("reorder", pattern="^(reorder|missing_barcode)$"),
):
    """Staff/manager alert: ping business owners about this catalog item."""
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    mems = await db.execute(
        select(Membership.user_id, Membership.role).where(
            Membership.business_id == business_id,
            Membership.role.in_(("owner", "manager", "admin")),
        )
    )
    targets = [(row[0], row[1]) for row in mems.all() if row[0] != user.id]
    if not targets:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="No owner/manager to notify")

    display = sh._user_display(user)
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    cur = catalog_stock_qty(item)
    ro = catalog_reorder(item)
    if alert == "missing_barcode":
        kind = "missing_barcode"
        title = "Missing barcode label"
        body = f"{display} flagged {item.name} — needs packaging barcode + label print"
        dedupe_prefix = "missing_barcode"
        cta = "labels"
    else:
        kind = "reorder_request"
        title = "Reorder requested"
        body = f"{display} needs reorder for {item.name} ({cur} on hand, reorder {ro})"
        dedupe_prefix = "reorder_request"
        cta = "purchase"
    inserted = 0
    for uid, role in targets:
        dedupe = f"{dedupe_prefix}:{item_id}:{uid}:{day}"
        ex = await db.execute(
            select(AppNotification.id).where(
                AppNotification.business_id == business_id,
                AppNotification.dedupe_key == dedupe,
            ).limit(1)
        )
        if ex.scalar_one_or_none() is not None:
            continue
        item_route = f"/catalog/item/{item_id}"
        db.add(
            AppNotification(
                id=uuid.uuid4(),
                business_id=business_id,
                user_id=uid,
                kind=kind,
                title=title,
                body=body,
                payload={
                    "item_id": str(item_id),
                    "from_user_id": str(user.id),
                    "from_user_name": display,
                    "target_role": role,
                    "cta": cta,
                },
                action_route=item_route,
                dedupe_key=dedupe,
                category=CATEGORY_STAFF,
                priority="high",
                triggered_by_user_id=user.id,
            )
        )
        inserted += 1
    if inserted:
        await db.commit()
        publish_notification_changed(business_id)
    return {"ok": True, "notifications_created": inserted}
