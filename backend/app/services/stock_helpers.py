"""Shared stock router helpers (extracted from stock.py)."""
from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, datetime, time, timezone
from decimal import Decimal
from typing import Literal

from sqlalchemy import and_, case, desc, func, literal, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    CatalogItem,
    CategoryType,
    DailyUsageLog,
    ItemCategory,
    StaffPurchaseLog,
    StockMovement,
    Supplier,
    TradePurchase,
    TradePurchaseLine,
    User,
)
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.stock_physical_count import StockPhysicalCount
from app.schemas.stock import (
    OpeningStockSetupItemOut,
    OpeningStockSetupSummaryOut,
    RecentPurchaseOut,
    StockListItemOut,
)
from app.services.stock_inventory import (
    catalog_reorder,
    catalog_stock_qty,
    movement_delivered_qty_map,
    stock_status,
)
from app.services.unit_normalization import (
    catalog_stock_unit,
    current_stock_kg as stock_qty_kg_equivalent,
    line_qty_in_stock_unit,
)

StatusFilter = Literal["all", "low", "critical", "out", "shortage"]
OpeningSetupStatus = Literal["pending", "completed", "all"]
SortBy = Literal["name", "stock_asc", "stock_desc", "recent"]

_DELIVERED_TRUCK_MAX_DAYS = 5
_PURCHASE_ADJ_TYPES = frozenset({"purchase", "purchase_reversal", "purchase_adjustment"})

def _user_display(user: User) -> str:
    if user.name and user.name.strip():
        return user.name.strip()
    return user.username or user.email
async def _supplier_name(db: AsyncSession, item: CatalogItem) -> str | None:
    if item.last_supplier_id:
        r = await db.execute(select(Supplier.name).where(Supplier.id == item.last_supplier_id))
        n = r.scalar_one_or_none()
        if n:
            return n
    return None
def _days_since_last_purchase(item: CatalogItem) -> int | None:
    if not item.last_purchase_at:
        return None
    last_purchase_at = item.last_purchase_at
    if last_purchase_at.tzinfo is None:
        last_purchase_at = last_purchase_at.replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - last_purchase_at
    return max(0, delta.days)
def _needs_eviction(
    item: CatalogItem,
    *,
    is_perishable: bool,
    current: Decimal,
) -> bool:
    if not is_perishable or current <= 0:
        return False
    days = item.eviction_days
    if days is None or days <= 0:
        return False
    since = _days_since_last_purchase(item)
    if since is None:
        return False
    return since > days
async def _last_trade_meta_map(
    db: AsyncSession,
    items: list[CatalogItem],
) -> dict[uuid.UUID, tuple[str | None, bool | None]]:
    tp_ids = {i.last_trade_purchase_id for i in items if i.last_trade_purchase_id}
    if not tp_ids:
        return {}
    r = await db.execute(
        select(
            TradePurchase.id,
            TradePurchase.human_id,
            TradePurchase.delivery_status,
        ).where(
            TradePurchase.id.in_(tp_ids),
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
    )
    by_tp = {
        row[0]: (
            row[1],
            (row[2] or "").strip().lower() == "stock_committed",
        )
        for row in r.all()
    }
    out: dict[uuid.UUID, tuple[str | None, bool | None]] = {}
    for item in items:
        tid = item.last_trade_purchase_id
        if tid and tid in by_tp:
            hid, delivered = by_tp[tid]
            out[item.id] = (hid, delivered)
    return out
def _item_to_list_row(
    item: CatalogItem,
    category_name: str | None,
    subcategory_name: str | None,
    supplier_name: str | None,
    *,
    period_purchased_qty: Decimal | None = None,
    period_usage_qty: Decimal | None = None,
    period_variance_qty: Decimal | None = None,
    ledger_variance_qty: Decimal | None = None,
    current_stock_kg: Decimal | None = None,
    stock_unit: str | None = None,
    needs_verification: bool = False,
    purchased_today_qty: Decimal | None = None,
    usage_today_qty: Decimal | None = None,
    is_perishable: bool = False,
    last_purchase_human_id: str | None = None,
    last_purchase_delivered: bool | None = None,
    last_line_qty: Decimal | None = None,
    last_purchase_at: datetime | None = None,
    has_pending_order: bool = False,
    pending_order_days: int | None = None,
    pending_delivery_qty: Decimal | None = None,
    physical_stock_qty: Decimal | None = None,
    physical_stock_difference_qty: Decimal | None = None,
    physical_stock_counted_at: datetime | None = None,
    physical_stock_counted_by: str | None = None,
    total_delivered_qty: Decimal | None = None,
    total_pending_delivery_qty: Decimal | None = None,
    last_movement_at: datetime | None = None,
) -> StockListItemOut:
    cur = catalog_stock_qty(item)
    warehouse_diff: Decimal | None = None
    if period_purchased_qty is not None:
        # Canonical warehouse diff semantics:
        # positive => system stock exceeds period purchased quantity (excess),
        # negative => system stock below period purchased quantity (deficit).
        warehouse_diff = cur - period_purchased_qty
    ro = catalog_reorder(item)
    unit = stock_unit or item.stock_unit or item.default_unit or item.selling_unit
    kg_equiv = (
        current_stock_kg
        if current_stock_kg is not None
        else stock_qty_kg_equivalent(item, cur)
    )
    ledger_var = ledger_variance_qty if ledger_variance_qty is not None else period_variance_qty
    return StockListItemOut(
        id=item.id,
        item_code=item.item_code,
        name=item.name,
        category_name=category_name,
        subcategory_name=subcategory_name,
        current_stock=cur,
        reorder_level=ro,
        unit=unit,
        stock_unit=unit,
        current_stock_kg=kg_equiv,
        rack_location=item.rack_location,
        supplier_name=supplier_name,
        stock_status=stock_status(cur, ro),
        last_stock_updated_at=item.last_stock_updated_at,
        last_stock_updated_by=item.last_stock_updated_by,
        last_movement_at=last_movement_at,
        last_trade_purchase_id=getattr(item, "last_trade_purchase_id", None),
        period_purchased_qty=period_purchased_qty,
        period_usage_qty=period_usage_qty,
        period_variance_qty=ledger_var,
        ledger_variance_qty=ledger_var,
        needs_verification=needs_verification,
        purchased_today_qty=purchased_today_qty,
        usage_today_qty=usage_today_qty,
        days_since_last_purchase=_days_since_last_purchase(item),
        needs_eviction=_needs_eviction(item, is_perishable=is_perishable, current=cur),
        is_perishable=is_perishable,
        missing_barcode=not (getattr(item, "barcode", None) and str(item.barcode).strip()),
        missing_item_code=not (item.item_code and str(item.item_code).strip()),
        barcode=getattr(item, "barcode", None),
        last_purchase_human_id=last_purchase_human_id,
        last_purchase_delivered=last_purchase_delivered,
        last_line_qty=last_line_qty,
        last_purchase_at=last_purchase_at,
        has_pending_order=has_pending_order,
        pending_order_days=pending_order_days,
        pending_delivery_qty=pending_delivery_qty,
        physical_stock_qty=physical_stock_qty,
        physical_stock_difference_qty=physical_stock_difference_qty,
        physical_stock_counted_at=physical_stock_counted_at,
        physical_stock_counted_by=physical_stock_counted_by,
        warehouse_diff_qty=warehouse_diff,
        opening_stock_qty=getattr(item, "opening_stock_qty", None),
        opening_stock_set_at=getattr(item, "opening_stock_set_at", None),
        opening_stock_set_by=getattr(item, "opening_stock_set_by", None),
        opening_stock_locked=bool(getattr(item, "opening_stock_locked", False)),
        stock_version=int(getattr(item, "stock_version", 0) or 0),
        total_delivered_qty=total_delivered_qty,
        total_pending_delivery_qty=total_pending_delivery_qty,
        public_token=getattr(item, "public_token", None),
    )
async def _lifetime_purchase_qty_maps(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> tuple[dict[uuid.UUID, Decimal], dict[uuid.UUID, Decimal]]:
    """Lifetime delivered vs undelivered purchase line qty (stock unit). PLAN.MD V2 Task 7."""
    if not item_ids:
        return {}, {}
    r = await db.execute(
        select(TradePurchaseLine, CatalogItem, TradePurchase.is_delivered)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.status.notin_(("deleted", "cancelled")),
            TradePurchaseLine.catalog_item_id.in_(item_ids),
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    pending: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    for line, cat_item, is_delivered in r.all():
        cid = line.catalog_item_id
        if cid is None:
            continue
        qty = line_qty_in_stock_unit(line, cat_item)
        if qty <= 0:
            continue
        if is_delivered:
            continue
        pending[cid] += qty
    delivered = await movement_delivered_qty_map(db, business_id, item_ids)
    return delivered, dict(pending)
async def _pending_order_meta_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, tuple[bool, int | None, Decimal | None]]:
    """Undelivered purchase lines per catalog item (truck icon + pending qty on stock UI)."""
    if not item_ids:
        return {}
    r = await db.execute(
        select(TradePurchaseLine, CatalogItem, TradePurchase.purchase_date)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.delivery_status.notin_(("stock_committed", "cancelled")),
            TradePurchase.status.notin_(("deleted", "cancelled")),
            TradePurchaseLine.catalog_item_id.in_(item_ids),
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    today = date.today()
    qty_by_item: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    oldest_by_item: dict[uuid.UUID, date] = {}
    for line, item, purchase_date in r.all():
        cid = line.catalog_item_id
        if cid is None:
            continue
        qty_by_item[cid] += line_qty_in_stock_unit(line, item)
        if purchase_date is not None:
            pd = purchase_date.date() if isinstance(purchase_date, datetime) else purchase_date
            prev = oldest_by_item.get(cid)
            if prev is None or pd < prev:
                oldest_by_item[cid] = pd
    out: dict[uuid.UUID, tuple[bool, int | None, Decimal | None]] = {}
    for cid, total_qty in qty_by_item.items():
        days: int | None = None
        oldest = oldest_by_item.get(cid)
        if oldest is not None:
            days = max(0, (today - oldest).days)
        qty_out = total_qty if total_qty > 0 else None
        out[cid] = (True, days, qty_out)
    return out
async def _latest_physical_count_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, StockPhysicalCount]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(StockPhysicalCount)
        .where(
            StockPhysicalCount.business_id == business_id,
            StockPhysicalCount.item_id.in_(item_ids),
        )
        .order_by(StockPhysicalCount.item_id, desc(StockPhysicalCount.counted_at))
    )
    out: dict[uuid.UUID, StockPhysicalCount] = {}
    for row in r.scalars().all():
        out.setdefault(row.item_id, row)
    return out
_DELIVERED_TRUCK_MAX_DAYS = 5
def _resolve_period_query(
    period_start: str | None,
    period_end: str | None,
    date_from: str | None,
    date_to: str | None,
) -> tuple[str | None, str | None]:
    ps = period_start if (period_start and str(period_start).strip()) else date_from
    pe = period_end if (period_end and str(period_end).strip()) else date_to
    return ps, pe
def _parse_period_dates(
    period_start: str | None, period_end: str | None
) -> tuple[date | None, date | None]:
    # Route handlers called directly (not via HTTP) may pass FastAPI Query() defaults.
    if not isinstance(period_start, str) or not isinstance(period_end, str):
        return None, None
    ps_raw = period_start.strip()
    pe_raw = period_end.strip()
    if not ps_raw or not pe_raw:
        return None, None
    try:
        ps = date.fromisoformat(ps_raw[:10])
        pe = date.fromisoformat(pe_raw[:10])
        return ps, pe
    except ValueError:
        return None, None
def _classify_delivery_indicator(
    *,
    has_pending_order: bool,
    pending_delivery_qty: Decimal | None,
    last_purchase_human_id: str | None,
    last_purchase_delivered: bool | None,
    last_purchase_at: datetime | None,
) -> Literal["none", "pending", "delivered"]:
    pending_del = pending_delivery_qty or Decimal(0)
    if has_pending_order or pending_del > 0:
        return "pending"
    po = (last_purchase_human_id or "").strip()
    if po and last_purchase_delivered is True:
        if last_purchase_at is not None:
            at = last_purchase_at
            if at.tzinfo is None:
                at = at.replace(tzinfo=timezone.utc)
            days = max(0, (datetime.now(timezone.utc) - at).days)
            if days > _DELIVERED_TRUCK_MAX_DAYS:
                return "none"
        return "delivered"
    if po and last_purchase_delivered is False:
        return "pending"
    return "none"
async def _last_movement_at_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, datetime]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(StockMovement.item_id, func.max(StockMovement.created_at)).where(
            StockMovement.business_id == business_id,
            StockMovement.item_id.in_(item_ids),
        ).group_by(StockMovement.item_id)
    )
    return {row[0]: row[1] for row in r.all() if row[1] is not None}
async def _today_purchased_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    today: date,
) -> dict[uuid.UUID, Decimal]:
    return await _period_purchased_map(db, business_id, item_ids, today, today)
async def _today_usage_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    today: date,
) -> dict[uuid.UUID, Decimal]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(DailyUsageLog.item_id, DailyUsageLog.used_qty).where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.usage_date == today,
            DailyUsageLog.item_id.in_(item_ids),
        )
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}
async def _period_purchased_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    period_start: date,
    period_end: date,
    *,
    delivered_only: bool = True,
) -> dict[uuid.UUID, Decimal]:
    """Sum received purchase line qty normalized to each item's stock unit."""
    if not item_ids:
        return {}
    filters = [
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date >= period_start,
        TradePurchase.purchase_date <= period_end,
        TradePurchase.status.notin_(("cancelled", "deleted")),
        TradePurchaseLine.catalog_item_id.in_(item_ids),
        CatalogItem.business_id == business_id,
        CatalogItem.deleted_at.is_(None),
    ]
    if delivered_only:
        filters.append(
            TradePurchase.delivery_status.in_(("stock_committed", "partial", "staff_verified"))
        )
    stmt = (
        select(TradePurchaseLine, CatalogItem)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(*filters)
    )
    r = await db.execute(stmt)
    totals: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    for line, item in r.all():
        totals[item.id] += line_qty_in_stock_unit(line, item)
    staff = await _staff_quick_purchased_map(
        db, business_id, item_ids, period_start, period_end
    )
    for iid, qty in staff.items():
        totals[iid] += qty
    return dict(totals)
async def _staff_quick_purchased_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    period_start: date,
    period_end: date,
) -> dict[uuid.UUID, Decimal]:
    """Staff quick purchases in period (stock list PURCHASE column)."""
    if not item_ids:
        return {}
    start_dt = datetime.combine(period_start, time.min, tzinfo=timezone.utc)
    end_dt = datetime.combine(period_end, time.max, tzinfo=timezone.utc)
    r = await db.execute(
        select(
            StaffPurchaseLog.item_id,
            func.coalesce(func.sum(StaffPurchaseLog.qty), 0),
        )
        .where(
            StaffPurchaseLog.business_id == business_id,
            StaffPurchaseLog.item_id.in_(item_ids),
            StaffPurchaseLog.created_at >= start_dt,
            StaffPurchaseLog.created_at <= end_dt,
        )
        .group_by(StaffPurchaseLog.item_id)
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}
async def _catalog_item_ids_purchased_in_period(
    db: AsyncSession,
    business_id: uuid.UUID,
    period_start: date,
    period_end: date,
) -> set[uuid.UUID]:
    """Distinct catalog items with trade or staff quick purchase qty in period."""
    trade_r = await db.execute(
        select(TradePurchaseLine.catalog_item_id.distinct())
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.purchase_date >= period_start,
            TradePurchase.purchase_date <= period_end,
            TradePurchase.status.notin_(("cancelled", "deleted")),
            TradePurchase.delivery_status.in_(
                ("stock_committed", "partial", "staff_verified")
            ),
            TradePurchaseLine.catalog_item_id.isnot(None),
        )
    )
    ids = {row[0] for row in trade_r.all() if row[0] is not None}
    start_dt = datetime.combine(period_start, time.min, tzinfo=timezone.utc)
    end_dt = datetime.combine(period_end, time.max, tzinfo=timezone.utc)
    staff_r = await db.execute(
        select(StaffPurchaseLog.item_id.distinct()).where(
            StaffPurchaseLog.business_id == business_id,
            StaffPurchaseLog.created_at >= start_dt,
            StaffPurchaseLog.created_at <= end_dt,
        )
    )
    ids.update(row[0] for row in staff_r.all() if row[0] is not None)
    return ids
async def _period_usage_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    period_start: date,
    period_end: date,
) -> dict[uuid.UUID, Decimal]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(
            DailyUsageLog.item_id,
            func.coalesce(func.sum(DailyUsageLog.used_qty), 0),
        )
        .where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.usage_date >= period_start,
            DailyUsageLog.usage_date <= period_end,
            DailyUsageLog.item_id.in_(item_ids),
        )
        .group_by(DailyUsageLog.item_id)
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}
_PURCHASE_ADJ_TYPES = frozenset({"purchase", "purchase_reversal", "purchase_adjustment"})
async def _ledger_variance_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    items: list[CatalogItem],
) -> dict[uuid.UUID, Decimal | None]:
    """
    Reconcile on-hand stock vs all-time purchases − usage ± manual adjustments.

    Returns None when item has no movement history to reconcile.
    """
    if not items:
        return {}
    item_ids = [i.id for i in items]
    all_purchased = await _period_purchased_map(
        db,
        business_id,
        item_ids,
        date(1970, 1, 1),
        date(2099, 12, 31),
    )
    usage_r = await db.execute(
        select(
            DailyUsageLog.item_id,
            func.coalesce(func.sum(DailyUsageLog.used_qty), 0),
        )
        .where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.item_id.in_(item_ids),
        )
        .group_by(DailyUsageLog.item_id)
    )
    all_usage = {row[0]: Decimal(row[1] or 0) for row in usage_r.all()}
    adj_r = await db.execute(
        select(
            StockAdjustmentLog.item_id,
            func.coalesce(func.sum(StockAdjustmentLog.new_qty - StockAdjustmentLog.old_qty), 0),
        )
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id.in_(item_ids),
            StockAdjustmentLog.adjustment_type.notin_(_PURCHASE_ADJ_TYPES),
        )
        .group_by(StockAdjustmentLog.item_id)
    )
    adj_net = {row[0]: Decimal(row[1] or 0) for row in adj_r.all()}
    out: dict[uuid.UUID, Decimal | None] = {}
    for item in items:
        purchased = all_purchased.get(item.id, Decimal(0))
        usage = all_usage.get(item.id, Decimal(0))
        adj = adj_net.get(item.id, Decimal(0))
        if purchased == 0 and usage == 0 and adj == 0:
            out[item.id] = None
            continue
        expected = purchased - usage + adj
        out[item.id] = catalog_stock_qty(item) - expected
    return out
def _needs_verification(
    current: Decimal, purchased: Decimal, *, threshold_pct: float = 0.1
) -> bool:
    if purchased <= 0:
        return False
    delta = abs(current - purchased)
    return delta / purchased > Decimal(str(threshold_pct))
def _sort_stock_rows(
    rows: list[tuple[CatalogItem, str | None, str | None]],
    sort: SortBy,
) -> None:
    if sort == "stock_asc":
        rows.sort(key=lambda t: catalog_stock_qty(t[0]))
    elif sort == "stock_desc":
        rows.sort(key=lambda t: catalog_stock_qty(t[0]), reverse=True)
    elif sort == "recent":
        rows.sort(
            key=lambda t: t[0].last_stock_updated_at
            or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )
    else:
        rows.sort(key=lambda t: (t[0].name or "").lower())


def _catalog_stock_sql_exprs():
    cur = func.coalesce(CatalogItem.current_stock, 0)
    ro = func.coalesce(CatalogItem.reorder_level, 0)
    return cur, ro


def _stock_status_sql_filter(status_val: StatusFilter):
    """SQL WHERE fragments matching stock_status() semantics."""
    if status_val == "all":
        return None
    cur, ro = _catalog_stock_sql_exprs()
    half_ro = ro * literal(Decimal("0.5"))
    out_cond = cur <= 0
    critical_cond = and_(ro > 0, cur > 0, cur <= half_ro)
    low_reorder = and_(ro > 0, cur > half_ro, cur <= ro)
    low_no_reorder = and_(ro <= 0, cur > 0, cur < literal(Decimal("1")))
    low_cond = or_(low_reorder, low_no_reorder)
    if status_val == "out":
        return out_cond
    if status_val == "critical":
        return critical_cond
    if status_val == "low":
        return low_cond
    if status_val == "shortage":
        return or_(out_cond, critical_cond, low_cond)
    return None


def _apply_stock_list_order(stmt, sort: SortBy):
    cur, _ = _catalog_stock_sql_exprs()
    if sort == "stock_asc":
        return stmt.order_by(cur.asc())
    if sort == "stock_desc":
        return stmt.order_by(cur.desc())
    if sort == "recent":
        return stmt.order_by(desc(CatalogItem.last_stock_updated_at).nullslast())
    return stmt.order_by(func.lower(CatalogItem.name).asc())


async def _query_items(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    q: str,
    category: str,
    subcategory: str,
    status_val: StatusFilter,
    sort: SortBy,
    page: int,
    per_page: int,
    missing_barcode: bool = False,
    missing_item_code: bool = False,
    reorder_only: bool = False,
    unit: str = "",
    whitelist_ids: set[uuid.UUID] | None = None,
):
    stmt = (
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    if whitelist_ids is not None:
        if not whitelist_ids:
            return 0, []
        stmt = stmt.where(CatalogItem.id.in_(whitelist_ids))
    if q.strip():
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(
            or_(
                func.lower(CatalogItem.name).like(like),
                func.lower(func.coalesce(CatalogItem.item_code, "")).like(like),
                func.lower(func.coalesce(CatalogItem.barcode, "")).like(like),
            )
        )
    if category.strip():
        stmt = stmt.where(func.lower(ItemCategory.name) == category.strip().lower())
    if subcategory.strip():
        stmt = stmt.where(func.lower(CategoryType.name) == subcategory.strip().lower())
    if unit.strip():
        u = unit.strip().lower()
        stmt = stmt.where(
            or_(
                func.lower(func.coalesce(CatalogItem.stock_unit, "")) == u,
                func.lower(func.coalesce(CatalogItem.default_unit, "")) == u,
            )
        )
    if missing_barcode:
        stmt = stmt.where(
            or_(
                CatalogItem.barcode.is_(None),
                func.trim(func.coalesce(CatalogItem.barcode, "")) == "",
            )
        )
    if missing_item_code:
        stmt = stmt.where(
            or_(
                CatalogItem.item_code.is_(None),
                func.trim(func.coalesce(CatalogItem.item_code, "")) == "",
            )
        )
    if reorder_only:
        cur, ro = _catalog_stock_sql_exprs()
        stmt = stmt.where(and_(ro > 0, cur <= ro))
    status_filter = _stock_status_sql_filter(status_val)
    if status_filter is not None:
        stmt = stmt.where(status_filter)

    count_stmt = select(func.count()).select_from(stmt.subquery())
    total = int((await db.execute(count_stmt)).scalar() or 0)
    if total == 0:
        return 0, []

    stmt = _apply_stock_list_order(stmt, sort)
    start = (page - 1) * per_page
    stmt = stmt.offset(start).limit(per_page)
    rows = (await db.execute(stmt)).all()
    return total, list(rows)


async def fetch_low_stock_top_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    limit: int = 6,
) -> list[dict]:
    """Top low-stock rows for home shell bundle (minimal list shape)."""
    _, rows = await _query_items(
        db,
        business_id,
        q="",
        category="",
        subcategory="",
        status_val="low",
        sort="stock_asc",
        page=1,
        per_page=limit,
    )
    if not rows:
        return []
    items_dict = {item.id: item for item, _, _ in rows}
    sup_map = await _supplier_names_bulk(db, items_dict)
    return [
        _item_to_list_row(item, cat_name, type_name, sup_map.get(item.id)).model_dump(
            mode="json"
        )
        for item, cat_name, type_name in rows
    ]


async def _supplier_names_bulk(
    db: AsyncSession, items: dict[uuid.UUID, CatalogItem]
) -> dict[uuid.UUID, str | None]:
    sup_ids = {i.last_supplier_id for i in items.values() if i.last_supplier_id}
    if not sup_ids:
        return {}
    r = await db.execute(select(Supplier.id, Supplier.name).where(Supplier.id.in_(sup_ids)))
    names = {row[0]: row[1] for row in r.all()}
    return {
        iid: names.get(item.last_supplier_id)
        for iid, item in items.items()
        if item.last_supplier_id
    }
async def _category_names_bulk(
    db: AsyncSession, items: dict[uuid.UUID, CatalogItem]
) -> dict[uuid.UUID, str | None]:
    cat_ids = {i.category_id for i in items.values() if i.category_id}
    if not cat_ids:
        return {}
    r = await db.execute(
        select(ItemCategory.id, ItemCategory.name).where(ItemCategory.id.in_(cat_ids))
    )
    names = {row[0]: row[1] for row in r.all()}
    return {
        iid: names.get(item.category_id)
        for iid, item in items.items()
        if item.category_id
    }
async def _recent_purchases(
    db: AsyncSession,
    item: CatalogItem,
    limit: int = 5,
) -> list[RecentPurchaseOut]:
    r = await db.execute(
        select(TradePurchaseLine, TradePurchase, Supplier.name)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .outerjoin(Supplier, TradePurchase.supplier_id == Supplier.id)
        .where(TradePurchaseLine.catalog_item_id == item.id)
        .order_by(desc(TradePurchase.purchase_date))
        .limit(limit)
    )
    su = catalog_stock_unit(item)
    out: list[RecentPurchaseOut] = []
    for line, tp, sup_name in r.all():
        pd = tp.purchase_date
        if pd is not None and not isinstance(pd, datetime):
            from datetime import date as date_cls

            if isinstance(pd, date_cls):
                pd = datetime.combine(pd, datetime.min.time(), tzinfo=timezone.utc)
        qty_su = line_qty_in_stock_unit(line, item)
        out.append(
            RecentPurchaseOut(
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
        )
    return out
