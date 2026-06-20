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


from app.routers.stock.stock_audit import create_staff_purchase_log, _movement_out
from app.routers.stock.stock_detail import get_stock_item
router = APIRouter()

async def _opening_setup_summary(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> OpeningStockSetupSummaryOut:
    base = (
        CatalogItem.business_id == business_id,
        CatalogItem.deleted_at.is_(None),
    )
    total_r = await db.execute(select(func.count(CatalogItem.id)).where(*base))
    pending_r = await db.execute(
        select(func.count(CatalogItem.id)).where(
            *base,
            CatalogItem.opening_stock_set_at.is_(None),
        )
    )
    total = int(total_r.scalar_one() or 0)
    pending = int(pending_r.scalar_one() or 0)
    completed = max(0, total - pending)
    last_r = await db.execute(
        select(CatalogItem.opening_stock_set_at, CatalogItem.opening_stock_set_by)
        .where(*base, CatalogItem.opening_stock_set_at.isnot(None))
        .order_by(desc(CatalogItem.opening_stock_set_at))
        .limit(1)
    )
    last_row = last_r.one_or_none()
    last_at = last_row[0] if last_row else None
    last_by = last_row[1] if last_row else None
    return OpeningStockSetupSummaryOut(
        pending_count=pending,
        completed_count=completed,
        total_count=total,
        last_updated_at=last_at,
        last_updated_by=last_by,
    )
async def _query_opening_setup_items(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    q: str,
    setup_status: OpeningSetupStatus,
    stock_status_val: StatusFilter,
    category: str,
    subcategory: str,
    missing_barcode: bool,
    missing_item_code: bool,
    supplier_id: uuid.UUID | None,
    unit: str,
    updated_today: bool,
    updated_by: str,
    page: int,
    per_page: int,
) -> tuple[int, list[tuple[CatalogItem, str | None, str | None]]]:
    stmt = (
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    if q.strip():
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(
            or_(
                func.lower(CatalogItem.name).like(like),
                func.lower(func.coalesce(CatalogItem.item_code, "")).like(like),
                func.lower(func.coalesce(CatalogItem.barcode, "")).like(like),
                func.lower(func.coalesce(CategoryType.name, "")).like(like),
                func.lower(func.coalesce(ItemCategory.name, "")).like(like),
            )
        )
    if category.strip():
        stmt = stmt.where(func.lower(ItemCategory.name) == category.strip().lower())
    if subcategory.strip():
        stmt = stmt.where(func.lower(CategoryType.name) == subcategory.strip().lower())
    if supplier_id is not None:
        stmt = stmt.where(CatalogItem.last_supplier_id == supplier_id)
    if unit.strip():
        u = unit.strip().lower()
        stmt = stmt.where(
            or_(
                func.lower(func.coalesce(CatalogItem.stock_unit, "")) == u,
                func.lower(func.coalesce(CatalogItem.default_unit, "")) == u,
            )
        )
    if updated_today:
        today = date.today()
        stmt = stmt.where(
            func.date(CatalogItem.opening_stock_set_at) == today,
        )
    if updated_by.strip():
        like = f"%{updated_by.strip().lower()}%"
        stmt = stmt.where(
            func.lower(func.coalesce(CatalogItem.opening_stock_set_by, "")).like(like)
        )

    rows = (await db.execute(stmt)).all()
    out: list[tuple[CatalogItem, str | None, str | None]] = []
    for item, cat_name, type_name in rows:
        is_pending = item.opening_stock_set_at is None
        if setup_status == "pending" and not is_pending:
            continue
        if setup_status == "completed" and is_pending:
            continue
        if missing_barcode and (item.barcode and str(item.barcode).strip()):
            continue
        if missing_item_code and (item.item_code and str(item.item_code).strip()):
            continue
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        st = stock_status(cur, ro)
        if stock_status_val != "all" and st != stock_status_val:
            continue
        out.append((item, cat_name, type_name))

    out.sort(key=lambda t: ((0 if t[0].opening_stock_set_at is None else 1), (t[0].name or "").lower()))
    total = len(out)
    start = (page - 1) * per_page
    return total, out[start : start + per_page]
def _opening_setup_item_row(
    item: CatalogItem,
    cat_name: str | None,
    type_name: str | None,
    supplier_name: str | None,
) -> OpeningStockSetupItemOut:
    base = sh._item_to_list_row(item, cat_name, type_name, supplier_name)
    is_pending = item.opening_stock_set_at is None
    missing_bc = not (getattr(item, "barcode", None) and str(item.barcode).strip())
    data = base.model_dump()
    data["setup_status"] = "pending" if is_pending else "completed"
    data["barcode_state"] = "missing" if missing_bc else "ok"
    return OpeningStockSetupItemOut(**data)
@router.get("/opening/setup", response_model=OpeningStockSetupOut)
async def list_opening_stock_setup(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    q: str = Query(""),
    status: OpeningSetupStatus = Query("all"),
    stock_status: StatusFilter = Query("all"),
    category: str = Query(""),
    subcategory: str = Query(""),
    missing_barcode: bool = Query(False),
    missing_item_code: bool = Query(False),
    supplier_id: uuid.UUID | None = Query(None),
    unit: str = Query(""),
    updated_today: bool = Query(False),
    updated_by: str = Query(""),
):
    summary = await _opening_setup_summary(db, business_id)
    total, rows = await _query_opening_setup_items(
        db,
        business_id,
        q=q,
        setup_status=status,
        stock_status_val=stock_status,
        category=category,
        subcategory=subcategory,
        missing_barcode=missing_barcode,
        missing_item_code=missing_item_code,
        supplier_id=supplier_id,
        unit=unit,
        updated_today=updated_today,
        updated_by=updated_by,
        page=page,
        per_page=per_page,
    )
    items: list[OpeningStockSetupItemOut] = []
    items_dict = {item.id: item for item, _, _ in rows}
    sup_map = await sh._supplier_names_bulk(db, items_dict)
    for item, cat_name, type_name in rows:
        sup = sup_map.get(item.id)
        items.append(_opening_setup_item_row(item, cat_name, type_name, sup))
    return OpeningStockSetupOut(
        summary=summary,
        items=items,
        total=total,
        page=page,
        per_page=per_page,
    )
@router.get("/inventory-summary", response_model=InventorySummaryOut)
async def stock_inventory_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
) -> InventorySummaryOut:
    """On-hand stock valuation (landing cost × qty) and unit buckets for owner home."""
    del _m
    payload = await compute_inventory_summary(db, business_id)
    return InventorySummaryOut(**payload)
async def _stock_totals_purchased_in_period(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> StockTotalsOut:
    """Sum purchased quantities in [date_from, date_to] for home period chips."""
    bag_expr = tq.trade_line_qty_bags_expr()
    box_expr = tq.trade_line_qty_boxes_expr()
    tin_expr = tq.trade_line_qty_tins_expr()
    kg_expr = tq.trade_line_weight_expr()
    bf = tq.trade_purchase_date_filter(business_id, date_from, date_to)
    deleted_filter = getattr(TradePurchase, "deleted_at", None)
    if deleted_filter is not None:
        bf = bf & TradePurchase.deleted_at.is_(None)
    r = await db.execute(
        select(
            func.coalesce(func.sum(bag_expr), 0),
            func.coalesce(func.sum(kg_expr), 0),
            func.coalesce(func.sum(box_expr), 0),
            func.coalesce(func.sum(tin_expr), 0),
            func.count(func.distinct(TradePurchaseLine.catalog_item_id)),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(bf)
    )
    row = r.one()
    return StockTotalsOut(
        total_items=int(row[4] or 0),
        total_bags=float(row[0] or 0),
        total_kg=float(row[1] or 0),
        total_boxes=float(row[2] or 0),
        total_tins=float(row[3] or 0),
    )
@router.get("/totals", response_model=StockTotalsOut)
async def stock_totals(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
) -> StockTotalsOut:
    """On-hand totals by default; with period_start/end, purchased qty in range."""
    del _m
    if period_start and period_end:
        try:
            d_from = date.fromisoformat(str(period_start)[:10])
            d_to = date.fromisoformat(str(period_end)[:10])
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid period_start or period_end (use YYYY-MM-DD)",
            ) from exc
        if d_from > d_to:
            d_from, d_to = d_to, d_from
        return await _stock_totals_purchased_in_period(db, business_id, d_from, d_to)

    base = CatalogItem.business_id == business_id
    if hasattr(CatalogItem, "deleted_at"):
        base = base & CatalogItem.deleted_at.is_(None)
    r = await db.execute(
        select(
            func.count(CatalogItem.id),
            func.coalesce(
                func.sum(
                    case(
                        (CatalogItem.default_unit == "bag", CatalogItem.current_stock),
                        else_=0,
                    )
                ),
                0,
            ),
            func.coalesce(
                func.sum(
                    case(
                        (
                            CatalogItem.default_unit == "bag",
                            CatalogItem.current_stock
                            * func.coalesce(CatalogItem.default_kg_per_bag, 0),
                        ),
                        (CatalogItem.default_unit == "kg", CatalogItem.current_stock),
                        else_=0,
                    )
                ),
                0,
            ),
            func.coalesce(
                func.sum(
                    case(
                        (CatalogItem.default_unit == "box", CatalogItem.current_stock),
                        else_=0,
                    )
                ),
                0,
            ),
            func.coalesce(
                func.sum(
                    case(
                        (CatalogItem.default_unit == "tin", CatalogItem.current_stock),
                        else_=0,
                    )
                ),
                0,
            ),
        ).where(base)
    )
    row = r.one()
    return StockTotalsOut(
        total_items=int(row[0] or 0),
        total_bags=float(row[1] or 0),
        total_kg=float(row[2] or 0),
        total_boxes=float(row[3] or 0),
        total_tins=float(row[4] or 0),
    )
@router.get("/reorder", response_model=ReorderListOut)
async def list_reorder_entries(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    status: str = "pending",
):
    st = (status or "pending").strip().lower()
    if st not in ("pending", "ordered", "done", "all"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid status filter")

    q = (
        select(ReorderListEntry, CatalogItem)
        .join(CatalogItem, CatalogItem.id == ReorderListEntry.item_id)
        .where(
            ReorderListEntry.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
        .order_by(ReorderListEntry.created_at.desc())
    )
    if st != "all":
        q = q.where(ReorderListEntry.status == st)
    rows = (await db.execute(q)).all()
    items_dict = {item.id: item for _, item in rows}
    sup_map = await sh._supplier_names_bulk(db, items_dict)
    items: list[ReorderListEntryOut] = []
    for entry, item in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        sup = sup_map.get(item.id)
        purchases = await sh._recent_purchases(db, item, limit=1)
        lp = purchases[0] if purchases else None
        items.append(
            ReorderListEntryOut(
                id=entry.id,
                item_id=item.id,
                item_name=item.name,
                item_code=item.item_code,
                current_stock=cur,
                reorder_level=ro,
                unit=item.default_unit,
                status=entry.status,
                added_by_name=entry.added_by_name,
                supplier_name=sup,
                last_purchase_rate=lp.rate if lp else None,
                created_at=entry.created_at,
                updated_at=entry.updated_at,
            )
        )
    return ReorderListOut(items=items, total=len(items))
@router.patch("/reorder/{entry_id}", response_model=ReorderListEntryOut)
async def patch_reorder_entry(
    business_id: uuid.UUID,
    entry_id: uuid.UUID,
    body: ReorderListPatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(ReorderListEntry, CatalogItem)
        .join(CatalogItem, CatalogItem.id == ReorderListEntry.item_id)
        .where(
            ReorderListEntry.id == entry_id,
            ReorderListEntry.business_id == business_id,
        )
    )
    row = r.first()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Reorder entry not found")
    entry, item = row
    entry.status = body.status
    entry.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(entry)
    return ReorderListEntryOut(
        id=entry.id,
        item_id=item.id,
        item_name=item.name,
        item_code=item.item_code,
        current_stock=catalog_stock_qty(item),
        reorder_level=catalog_reorder(item),
        unit=item.default_unit,
        status=entry.status,
        added_by_name=entry.added_by_name,
        created_at=entry.created_at,
        updated_at=entry.updated_at,
    )
@router.delete("/reorder/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reorder_entry(
    business_id: uuid.UUID,
    entry_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(ReorderListEntry).where(
            ReorderListEntry.id == entry_id,
            ReorderListEntry.business_id == business_id,
        )
    )
    entry = r.scalar_one_or_none()
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Reorder entry not found")
    await db.delete(entry)
    await db.commit()
@router.get("/opening/missing", response_model=OpeningStockMissingOut)
async def missing_opening_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(100, ge=1, le=500),
):
    r = await db.execute(
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.opening_stock_set_at.is_(None),
        )
        .order_by(CatalogItem.name.asc())
        .limit(limit)
    )
    rows = r.all()
    count_r = await db.execute(
        select(func.count(CatalogItem.id)).where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.opening_stock_set_at.is_(None),
        )
    )
    items_dict = {item.id: item for item, _, _ in rows}
    sup_map = await sh._supplier_names_bulk(db, items_dict)
    items = [
        sh._item_to_list_row(item, cat_name, type_name, sup_map.get(item.id))
        for item, cat_name, type_name in rows
    ]
    return OpeningStockMissingOut(
        items=items,
        missing_count=int(count_r.scalar_one() or 0),
    )
@router.post("/{item_id}/quick-purchase", response_model=QuickPurchaseOut)
async def create_item_quick_purchase(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: QuickPurchaseIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    staff_body = StaffPurchaseLogIn(
        item_id=item_id,
        qty=body.qty,
        supplier_id=body.supplier_id,
        broker_id=body.broker_id,
        notes=body.notes,
        idempotency_key=body.idempotency_key,
    )
    log = await create_staff_purchase_log(business_id, staff_body, db, user, membership)
    movement_r = await db.execute(
        select(StockMovement).where(StockMovement.id == log.stock_movement_id)
    )
    movement = movement_r.scalar_one_or_none()
    if movement is None:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Stock movement missing")
    item = await get_stock_item(business_id, item_id, db, membership)
    return QuickPurchaseOut(
        purchase_log=log,
        movement=_movement_out(movement, item_name=item.name),
        item=item,
    )
@router.post("/{item_id}/reorder", status_code=status.HTTP_201_CREATED)
async def add_item_to_reorder_list(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
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

    ex = await db.execute(
        select(ReorderListEntry).where(
            ReorderListEntry.business_id == business_id,
            ReorderListEntry.item_id == item_id,
            ReorderListEntry.status == "pending",
        ).limit(1)
    )
    row = ex.scalar_one_or_none()
    display = sh._user_display(user)
    if row is not None:
        row.added_by = user.id
        row.added_by_name = display
        row.updated_at = datetime.now(timezone.utc)
    else:
        db.add(
            ReorderListEntry(
                id=uuid.uuid4(),
                business_id=business_id,
                item_id=item_id,
                added_by=user.id,
                added_by_name=display,
                status="pending",
            )
        )
    await db.commit()
    return {"ok": True, "item_id": str(item_id), "status": "pending"}
