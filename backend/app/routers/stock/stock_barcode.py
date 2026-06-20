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


from app.services.stock_variance_notifications import _last_purchase_expected_qty_map
router = APIRouter()

_BARCODE_LOOKUP_CACHE_TTL_SEC = 30.0
_BARCODE_LOOKUP_CACHE_MAX = 500
_barcode_lookup_cache: dict[tuple[uuid.UUID, str], tuple[float, dict]] = {}


def _barcode_lookup_cache_get(
    business_id: uuid.UUID, code: str
) -> dict | None:
    key = (business_id, code.lower())
    entry = _barcode_lookup_cache.get(key)
    if entry is None:
        return None
    ts, payload = entry
    if monotonic() - ts > _BARCODE_LOOKUP_CACHE_TTL_SEC:
        _barcode_lookup_cache.pop(key, None)
        return None
    return payload
def _barcode_lookup_cache_set(
    business_id: uuid.UUID, code: str, payload: dict
) -> None:
    if len(_barcode_lookup_cache) >= _BARCODE_LOOKUP_CACHE_MAX:
        for stale_key in list(_barcode_lookup_cache.keys())[
            : _BARCODE_LOOKUP_CACHE_MAX // 2
        ]:
            _barcode_lookup_cache.pop(stale_key, None)
    _barcode_lookup_cache[(business_id, code.lower())] = (monotonic(), payload)
@router.get("/barcode/lookup", response_model=BarcodeLookupOut)
async def barcode_lookup(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    code: str = Query(..., min_length=1),
):
    code_s = code.strip()
    cached = _barcode_lookup_cache_get(business_id, code_s)
    if cached is not None:
        return BarcodeLookupOut(**cached)

    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.barcode == code_s,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if item is None:
        r2 = await db.execute(
            select(CatalogItem).where(
                CatalogItem.business_id == business_id,
                CatalogItem.item_code == code_s,
                CatalogItem.deleted_at.is_(None),
            )
        )
        item = r2.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    label, phys_map = await asyncio.gather(
        _barcode_label(db, business_id, item),
        sh._latest_physical_count_map(db, business_id, [item.id]),
    )
    phys = phys_map.get(item.id)
    out = BarcodeLookupOut(
        id=item.id,
        name=item.name,
        item_code=item.item_code,
        barcode=getattr(item, "barcode", None),
        current_stock=label.current_stock or catalog_stock_qty(item),
        reorder_level=catalog_reorder(item),
        unit=label.unit,
        last_purchase_date=label.last_purchase_date,
        last_purchase_qty=label.last_purchase_qty,
        last_purchase_unit=label.last_purchase_unit,
        last_purchase_rate=label.last_purchase_rate,
        supplier_name=label.supplier_name,
        physical_stock_qty=phys.counted_qty if phys else None,
        physical_stock_counted_at=phys.counted_at if phys else None,
        physical_stock_counted_by=phys.counted_by_name if phys else None,
        last_stock_updated_at=getattr(item, "last_stock_updated_at", None),
        last_stock_updated_by=getattr(item, "last_stock_updated_by", None),
    )
    _barcode_lookup_cache_set(
        business_id, code_s, out.model_dump(mode="json")
    )
    return out
async def _barcode_label(
    db: AsyncSession, business_id: uuid.UUID, item: CatalogItem
) -> BarcodeLabelOut:
    cat_name: str | None = None
    if item.category_id:
        cr = await db.execute(select(ItemCategory.name).where(ItemCategory.id == item.category_id))
        cat_name = cr.scalar_one_or_none()
    purchases = await sh._recent_purchases(db, item, limit=1)
    lp = purchases[0] if purchases else None
    sup = await sh._supplier_name(db, item)
    bc = getattr(item, "barcode", None) or item.item_code
    return BarcodeLabelOut(
        id=item.id,
        barcode=bc,
        item_code=item.item_code,
        item_name=item.name,
        category_name=cat_name,
        unit=item.stock_unit or item.default_unit,
        current_stock=catalog_stock_qty(item),
        last_purchase_date=lp.purchase_date if lp else None,
        last_purchase_qty=lp.qty if lp else None,
        last_purchase_unit=lp.unit if lp else None,
        last_purchase_rate=lp.rate if lp else None,
        supplier_name=sup,
    )
@router.get("/barcode/{item_id}", response_model=BarcodeLabelOut)
async def barcode_label(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
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
    return await _barcode_label(db, business_id, item)
async def _latest_purchase_by_item(
    db: AsyncSession,
    items: dict[uuid.UUID, CatalogItem],
) -> dict[uuid.UUID, RecentPurchaseOut]:
    """One query for latest purchase line per catalog item (bulk label print)."""
    if not items:
        return {}
    ids = list(items.keys())
    r = await db.execute(
        select(TradePurchaseLine, TradePurchase, Supplier.name)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .outerjoin(Supplier, TradePurchase.supplier_id == Supplier.id)
        .where(TradePurchaseLine.catalog_item_id.in_(ids))
        .order_by(
            TradePurchaseLine.catalog_item_id,
            desc(TradePurchase.purchase_date),
        )
    )
    out: dict[uuid.UUID, RecentPurchaseOut] = {}
    for line, tp, sup_name in r.all():
        cid = line.catalog_item_id
        if cid in out:
            continue
        item = items.get(cid)
        if item is None:
            continue
        pd = tp.purchase_date
        if pd is not None and not isinstance(pd, datetime):
            from datetime import date as date_cls

            if isinstance(pd, date_cls):
                pd = datetime.combine(pd, datetime.min.time(), tzinfo=timezone.utc)
        su = catalog_stock_unit(item)
        qty_su = line_qty_in_stock_unit(line, item)
        out[cid] = RecentPurchaseOut(
            id=tp.id,
            invoice_number=tp.invoice_number,
            human_id=tp.human_id,
            purchase_date=pd,
            qty=line.qty,
            unit=line.unit,
            entered_qty=line.qty,
            entered_unit=line.unit,
            qty_in_stock_unit=qty_su,
            stock_unit=su,
            rate=getattr(line, "landing_cost", None) or getattr(line, "purchase_rate", None),
            supplier_name=sup_name,
        )
    return out
def _barcode_label_from_parts(
    item: CatalogItem,
    *,
    category_name: str | None,
    lp: RecentPurchaseOut | None,
    supplier_name: str | None,
) -> BarcodeLabelOut:
    bc = getattr(item, "barcode", None) or item.item_code
    return BarcodeLabelOut(
        id=item.id,
        barcode=bc,
        item_code=item.item_code,
        item_name=item.name,
        category_name=category_name,
        unit=item.stock_unit or item.default_unit,
        current_stock=catalog_stock_qty(item),
        last_purchase_date=lp.purchase_date if lp else None,
        last_purchase_qty=lp.qty if lp else None,
        last_purchase_unit=lp.unit if lp else None,
        last_purchase_rate=lp.rate if lp else None,
        supplier_name=supplier_name,
    )
@router.post("/barcode/batch", response_model=BarcodeBatchOut)
async def barcode_batch(
    business_id: uuid.UUID,
    body: BarcodeBatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("barcode_print"))],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.id.in_(body.item_ids),
            CatalogItem.deleted_at.is_(None),
        )
    )
    items = {i.id: i for i in r.scalars().all()}
    if not items:
        return BarcodeBatchOut(labels=[])
    lp_map = await _latest_purchase_by_item(db, items)
    sup_map = await sh._supplier_names_bulk(db, items)
    cat_map = await sh._category_names_bulk(db, items)
    labels: list[BarcodeLabelOut] = []
    for iid in body.item_ids:
        item = items.get(iid)
        if item:
            labels.append(
                _barcode_label_from_parts(
                    item,
                    category_name=cat_map.get(item.id),
                    lp=lp_map.get(item.id),
                    supplier_name=sup_map.get(item.id),
                )
            )
    return BarcodeBatchOut(labels=labels)
