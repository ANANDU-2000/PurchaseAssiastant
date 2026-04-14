import calendar
import uuid
from datetime import date, timedelta
from collections import defaultdict
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import case, desc, func, literal, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_membership
from app.models import (
    Broker,
    CatalogItem,
    CatalogVariant,
    Entry,
    EntryLineItem,
    ItemCategory,
    Membership,
    Supplier,
)

router = APIRouter(prefix="/v1/businesses/{business_id}/analytics", tags=["analytics"])


class AnalyticsSummary(BaseModel):
    total_purchase: float
    total_qty_base: float
    total_profit: float
    purchase_count: int
    base_unit_label: str = "kg"


@router.get("/summary", response_model=AnalyticsSummary)
async def analytics_summary(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    base_filter = (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
    )
    purchase = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.qty * EntryLineItem.buy_price), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*base_filter)
    )
    profit = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*base_filter)
    )
    qty = await db.execute(
        select(func.coalesce(func.sum(func.coalesce(EntryLineItem.qty_base, EntryLineItem.qty)), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*base_filter)
    )
    cnt = await db.execute(
        select(func.count(Entry.id.distinct())).where(*base_filter)
    )
    return AnalyticsSummary(
        total_purchase=float(purchase.scalar() or 0),
        total_qty_base=float(qty.scalar() or 0),
        total_profit=float(profit.scalar() or 0),
        purchase_count=int(cnt.scalar() or 0),
    )


def _date_filter(business_id: uuid.UUID, from_date: date, to_date: date):
    return (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
    )


def _profit_trend_label(p_old: float, p_new: float) -> str:
    """Compare profit in first vs second half of the selected date range."""
    po = float(p_old or 0)
    pn = float(p_new or 0)
    if abs(po) < 1e-9 and abs(pn) < 1e-9:
        return "flat"
    if abs(po) < 1e-9:
        return "up" if pn > 1e-9 else "flat"
    if pn > po * 1.05:
        return "up"
    if pn < po * 0.95:
        return "down"
    return "flat"


def _prior_month_mtd_window(from_date: date, to_date: date) -> tuple[date, date] | None:
    """When the client sends month-start → today, map to the same MTD span last month."""
    if from_date.day != 1 or to_date < from_date:
        return None
    if from_date.year != to_date.year or from_date.month != to_date.month:
        return None
    if from_date.month == 1:
        py, pm = from_date.year - 1, 12
    else:
        py, pm = from_date.year, from_date.month - 1
    p_start = date(py, pm, 1)
    max_d = calendar.monthrange(py, pm)[1]
    p_end = date(py, pm, min(to_date.day, max_d))
    return p_start, p_end


async def _sum_profit(db: AsyncSession, business_id: uuid.UUID, from_date: date, to_date: date) -> float:
    bf = _date_filter(business_id, from_date, to_date)
    r = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    return float(r.scalar() or 0)


class HomeInsightAlert(BaseModel):
    code: str
    message: str
    severity: str = "info"


class HomeInsights(BaseModel):
    top_item: str | None = None
    top_item_profit: float | None = None
    worst_item: str | None = None
    worst_item_profit: float | None = None
    best_supplier_name: str | None = None
    best_supplier_profit: float | None = None
    """Month-to-date profit vs the same calendar range in the previous month (percent)."""
    profit_change_pct_prior_mtd: float | None = None
    negative_line_count: int = 0
    alerts: list[HomeInsightAlert]


@router.get("/insights", response_model=HomeInsights)
async def home_insights(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    # Top item by total profit
    q_top = (
        select(
            EntryLineItem.item_name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
        .group_by(EntryLineItem.item_name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    top = await db.execute(q_top)
    row = top.first()
    top_name = row[0] if row else None
    top_profit = float(row[1]) if row else None

    q_worst = (
        select(
            EntryLineItem.item_name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
        .group_by(EntryLineItem.item_name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).asc())
        .limit(1)
    )
    worst = await db.execute(q_worst)
    wrow = worst.first()
    worst_name = wrow[0] if wrow else None
    worst_profit = float(wrow[1]) if wrow else None

    q_best_sup = (
        select(
            Supplier.name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .where(*bf, Entry.supplier_id.isnot(None))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    bs = await db.execute(q_best_sup)
    bs_row = bs.first()
    best_supplier_name = bs_row[0] if bs_row else None
    best_supplier_profit = float(bs_row[1]) if bs_row else None

    cur_profit = await _sum_profit(db, business_id, from_date, to_date)
    mom_pct: float | None = None
    pw = _prior_month_mtd_window(from_date, to_date)
    if pw is not None:
        prev_profit = await _sum_profit(db, business_id, pw[0], pw[1])
        base = abs(prev_profit) if abs(prev_profit) > 1e-9 else 1.0
        mom_pct = ((cur_profit - prev_profit) / base) * 100.0

    alerts: list[HomeInsightAlert] = []
    entry_cnt = await db.execute(select(func.count(Entry.id.distinct())).where(*bf))
    n_entries = int(entry_cnt.scalar() or 0)
    if n_entries == 0:
        alerts.append(
            HomeInsightAlert(
                code="no_entries",
                message="No purchase entries in this period yet — add one from the dashboard.",
                severity="info",
            )
        )
    neg = await db.execute(
        select(func.count(EntryLineItem.id))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf, EntryLineItem.profit < 0)
    )
    n_neg = int(neg.scalar() or 0)
    if n_neg > 0:
        alerts.append(
            HomeInsightAlert(
                code="negative_profit_lines",
                message="Some lines show negative profit in this period.",
                severity="warning",
            )
        )
    return HomeInsights(
        top_item=top_name,
        top_item_profit=top_profit,
        worst_item=worst_name,
        worst_item_profit=worst_profit,
        best_supplier_name=best_supplier_name,
        best_supplier_profit=best_supplier_profit,
        profit_change_pct_prior_mtd=mom_pct,
        negative_line_count=n_neg,
        alerts=alerts,
    )


class ItemAnalyticsRow(BaseModel):
    item_name: str
    total_qty: float
    avg_landing: float
    total_profit: float
    line_count: int
    margin_pct: float = 0.0  # rough markup vs implied line cost (qty × avg landing)
    trend: str | None = None  # up|down|flat vs split range; None if single-day range
    category_name: str = ""
    type_name: str = ""
    supplier_name: str | None = None
    broker_name: str | None = None
    similar_item_names: list[str] = []


@router.get("/items", response_model=list[ItemAnalyticsRow])
async def analytics_items(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            EntryLineItem.item_name,
            func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            func.coalesce(func.avg(EntryLineItem.landing_cost), 0).label("al"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
            func.count(EntryLineItem.id).label("lc"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
        .group_by(EntryLineItem.item_name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
    )
    r = await db.execute(q)
    rows = r.all()
    trend_by_item: dict[str, str] = {}
    span_days = (to_date - from_date).days
    if span_days >= 1:
        mid = from_date + timedelta(days=span_days // 2)
        profit_x = func.coalesce(EntryLineItem.profit, 0)
        q_tr = (
            select(
                EntryLineItem.item_name,
                func.sum(case((Entry.entry_date <= mid, profit_x), else_=0)).label("p_old"),
                func.sum(case((Entry.entry_date > mid, profit_x), else_=0)).label("p_new"),
            )
            .select_from(EntryLineItem)
            .join(Entry, Entry.id == EntryLineItem.entry_id)
            .where(*bf)
            .group_by(EntryLineItem.item_name)
        )
        r_tr = await db.execute(q_tr)
        for tr in r_tr.all():
            trend_by_item[str(tr[0])] = _profit_trend_label(float(tr[1] or 0), float(tr[2] or 0))

    out: list[ItemAnalyticsRow] = []
    for row in rows:
        tq = float(row[1] or 0)
        al = float(row[2] or 0)
        tp = float(row[3] or 0)
        basis = tq * al
        margin_pct = (100.0 * tp / basis) if basis > 1e-9 else 0.0
        iname = str(row[0])
        tr = trend_by_item.get(iname) if span_days >= 1 else None
        out.append(
            ItemAnalyticsRow(
                item_name=iname,
                total_qty=tq,
                avg_landing=al,
                total_profit=tp,
                line_count=int(row[4] or 0),
                margin_pct=margin_pct,
                trend=tr,
            )
        )

    names = [x.item_name for x in out]
    if not names:
        return out

    # Best supplier / broker by summed profit per item_name
    q_sup = (
        select(
            EntryLineItem.item_name,
            Supplier.name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("sp"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .where(*bf, Entry.supplier_id.isnot(None), EntryLineItem.item_name.in_(names))
        .group_by(EntryLineItem.item_name, Supplier.name)
    )
    r_sup = await db.execute(q_sup)
    best_sup: dict[str, tuple[str, float]] = {}
    for row in r_sup.all():
        iname, sname, sp = str(row[0]), str(row[1]), float(row[2] or 0)
        prev = best_sup.get(iname)
        if prev is None or sp > prev[1]:
            best_sup[iname] = (sname, sp)

    q_br = (
        select(
            EntryLineItem.item_name,
            Broker.name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("bp"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .join(Broker, Broker.id == Entry.broker_id)
        .where(*bf, Entry.broker_id.isnot(None), EntryLineItem.item_name.in_(names))
        .group_by(EntryLineItem.item_name, Broker.name)
    )
    r_br = await db.execute(q_br)
    best_br: dict[str, tuple[str, float]] = {}
    for row in r_br.all():
        iname, bname, bp = str(row[0]), str(row[1]), float(row[2] or 0)
        prev = best_br.get(iname)
        if prev is None or bp > prev[1]:
            best_br[iname] = (bname, bp)

    q_meta = (
        select(
            EntryLineItem.item_name,
            func.max(ItemCategory.name).label("icn"),
            func.max(EntryLineItem.category).label("lcat"),
            func.max(CatalogItem.name).label("cin"),
            func.max(CatalogVariant.name).label("cvn"),
            func.max(CatalogItem.category_id).label("catid"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .outerjoin(CatalogItem, CatalogItem.id == EntryLineItem.catalog_item_id)
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .outerjoin(CatalogVariant, CatalogVariant.id == EntryLineItem.catalog_variant_id)
        .where(*bf, EntryLineItem.item_name.in_(names))
        .group_by(EntryLineItem.item_name)
    )
    r_meta = await db.execute(q_meta)
    meta_by_item: dict[str, tuple[str | None, str | None, str | None, str | None, uuid.UUID | None]] = {}
    for row in r_meta.all():
        meta_by_item[str(row[0])] = (row[1], row[2], row[3], row[4], row[5])

    by_cat: dict[uuid.UUID, list[str]] = defaultdict(list)
    r_pool = await db.execute(
        select(CatalogItem.name, CatalogItem.category_id)
        .where(CatalogItem.business_id == business_id)
    )
    for nm, cid in r_pool.all():
        if cid:
            by_cat[cid].append(str(nm))

    enriched: list[ItemAnalyticsRow] = []
    for row in out:
        iname = row.item_name
        icn, lcat, cin, cvn, cat_id = meta_by_item.get(
            iname, (None, None, None, None, None)
        )
        cat = (icn or lcat or "").strip() or "Uncategorized"
        typ = (cvn or cin or "").strip() or "—"
        sn = best_sup.get(iname)
        bn = best_br.get(iname)
        sim: list[str] = []
        if cat_id:
            pool = by_cat.get(cat_id, [])
            for cname in pool:
                if cname == iname:
                    continue
                if cname not in sim:
                    sim.append(cname)
                if len(sim) >= 5:
                    break
        enriched.append(
            row.model_copy(
                update={
                    "category_name": cat,
                    "type_name": typ,
                    "supplier_name": sn[0] if sn else None,
                    "broker_name": bn[0] if bn else None,
                    "similar_item_names": sim[:5],
                }
            )
        )
    return enriched


class CategoryAnalyticsRow(BaseModel):
    category: str
    type_name: str = "—"
    total_profit: float
    total_qty: float
    line_count: int
    best_item_name: str | None = None
    best_supplier_name: str | None = None


@router.get("/categories", response_model=list[CategoryAnalyticsRow])
async def analytics_categories(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    cat_key = func.coalesce(ItemCategory.name, EntryLineItem.category, literal("Uncategorized"))
    type_key = func.coalesce(CatalogVariant.name, CatalogItem.name, literal("—"))
    q = (
        select(
            cat_key.label("cat"),
            type_key.label("typ"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
            func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            func.count(EntryLineItem.id).label("lc"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .outerjoin(CatalogItem, CatalogItem.id == EntryLineItem.catalog_item_id)
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .outerjoin(CatalogVariant, CatalogVariant.id == EntryLineItem.catalog_variant_id)
        .where(*bf)
        .group_by(cat_key, type_key)
        .order_by(desc(func.coalesce(func.sum(EntryLineItem.profit), 0)))
    )
    r = await db.execute(q)
    cat_rows = r.all()

    q_best = (
        select(
            cat_key.label("cat"),
            type_key.label("typ"),
            EntryLineItem.item_name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("ip"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .outerjoin(CatalogItem, CatalogItem.id == EntryLineItem.catalog_item_id)
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .outerjoin(CatalogVariant, CatalogVariant.id == EntryLineItem.catalog_variant_id)
        .where(*bf)
        .group_by(cat_key, type_key, EntryLineItem.item_name)
    )
    r2 = await db.execute(q_best)
    best_item: dict[tuple[str, str], tuple[str, float]] = {}
    for row in r2.all():
        ck, tk, name, ip = str(row[0]), str(row[1]), str(row[2]), float(row[3] or 0)
        key = (ck, tk)
        prev = best_item.get(key)
        if prev is None or ip > prev[1]:
            best_item[key] = (name, ip)

    q_bsup = (
        select(
            cat_key.label("cat"),
            type_key.label("typ"),
            Supplier.name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("sp"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .outerjoin(CatalogItem, CatalogItem.id == EntryLineItem.catalog_item_id)
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .outerjoin(CatalogVariant, CatalogVariant.id == EntryLineItem.catalog_variant_id)
        .where(*bf, Entry.supplier_id.isnot(None))
        .group_by(cat_key, type_key, Supplier.name)
    )
    r3 = await db.execute(q_bsup)
    best_sup: dict[tuple[str, str], tuple[str, float]] = {}
    for row in r3.all():
        ck, tk, sname, sp = str(row[0]), str(row[1]), str(row[2]), float(row[3] or 0)
        key = (ck, tk)
        prev = best_sup.get(key)
        if prev is None or sp > prev[1]:
            best_sup[key] = (sname, sp)

    out: list[CategoryAnalyticsRow] = []
    for row in cat_rows:
        ck, tk = str(row[0]), str(row[1])
        key = (ck, tk)
        bip = best_item.get(key)
        bsp = best_sup.get(key)
        best_name = bip[0] if bip and bip[1] > 1e-9 else None
        best_supplier = bsp[0] if bsp and bsp[1] > 1e-9 else None
        out.append(
            CategoryAnalyticsRow(
                category=ck,
                type_name=tk if tk != "—" else "—",
                total_profit=float(row[2] or 0),
                total_qty=float(row[3] or 0),
                line_count=int(row[4] or 0),
                best_item_name=best_name,
                best_supplier_name=best_supplier,
            )
        )
    return out


class SupplierAnalyticsRow(BaseModel):
    supplier_id: uuid.UUID
    supplier_name: str
    deals: int
    avg_landing: float
    total_qty: float
    total_profit: float
    margin_pct: float = 0.0


@router.get("/suppliers", response_model=list[SupplierAnalyticsRow])
async def analytics_suppliers(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            Supplier.id,
            Supplier.name,
            func.count(Entry.id.distinct()).label("deals"),
            func.coalesce(func.avg(EntryLineItem.landing_cost), 0).label("al"),
            func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .where(*bf, Entry.supplier_id.isnot(None))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
    )
    r = await db.execute(q)
    out: list[SupplierAnalyticsRow] = []
    for row in r.all():
        al = float(row[3] or 0)
        tq = float(row[4] or 0)
        tp = float(row[5] or 0)
        basis = tq * al
        margin_pct = (100.0 * tp / basis) if basis > 1e-9 else 0.0
        out.append(
            SupplierAnalyticsRow(
                supplier_id=row[0],
                supplier_name=row[1],
                deals=int(row[2] or 0),
                avg_landing=al,
                total_qty=tq,
                total_profit=tp,
                margin_pct=margin_pct,
            )
        )
    return out


class SupplierItemBreakdownRow(BaseModel):
    item_name: str
    category: str = ""
    type_name: str = "—"
    total_qty: float
    avg_landing: float
    total_profit: float
    margin_pct: float = 0.0


@router.get(
    "/suppliers/{supplier_id}/items",
    response_model=list[SupplierItemBreakdownRow],
)
async def analytics_supplier_items(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = (
        *_date_filter(business_id, from_date, to_date),
        Entry.supplier_id == supplier_id,
    )
    q = (
        select(
            EntryLineItem.item_name,
            func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            func.coalesce(func.avg(EntryLineItem.landing_cost), 0).label("al"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
            func.max(ItemCategory.name).label("icn"),
            func.max(EntryLineItem.category).label("lcat"),
            func.max(CatalogVariant.name).label("cvn"),
            func.max(CatalogItem.name).label("cin"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .outerjoin(CatalogItem, CatalogItem.id == EntryLineItem.catalog_item_id)
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .outerjoin(CatalogVariant, CatalogVariant.id == EntryLineItem.catalog_variant_id)
        .where(*bf)
        .group_by(EntryLineItem.item_name)
        .order_by(desc(func.coalesce(func.sum(EntryLineItem.profit), 0)))
    )
    r = await db.execute(q)
    out: list[SupplierItemBreakdownRow] = []
    for row in r.all():
        tq = float(row[1] or 0)
        al = float(row[2] or 0)
        tp = float(row[3] or 0)
        basis = tq * al
        margin_pct = (100.0 * tp / basis) if basis > 1e-9 else 0.0
        icn, lcat, cvn, cin = row[4], row[5], row[6], row[7]
        cat = ((icn or lcat) or "").strip() or "Uncategorized"
        typ = (cvn or cin or "").strip() or "—"
        out.append(
            SupplierItemBreakdownRow(
                item_name=str(row[0]),
                category=cat,
                type_name=typ,
                total_qty=tq,
                avg_landing=al,
                total_profit=tp,
                margin_pct=margin_pct,
            )
        )
    return out


class BrokerAnalyticsRow(BaseModel):
    broker_id: uuid.UUID
    broker_name: str
    deals: int
    total_commission: float
    total_profit: float
    commission_pct_of_profit: float = 0.0


@router.get("/brokers", response_model=list[BrokerAnalyticsRow])
async def analytics_brokers(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            Broker.id,
            Broker.name,
            func.count(Entry.id.distinct()).label("deals"),
            func.coalesce(func.sum(Entry.commission_amount), 0).label("tc"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .join(Broker, Broker.id == Entry.broker_id)
        .where(*bf, Entry.broker_id.isnot(None))
        .group_by(Broker.id, Broker.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
    )
    r = await db.execute(q)
    out: list[BrokerAnalyticsRow] = []
    for row in r.all():
        tc = float(row[3] or 0)
        tp = float(row[4] or 0)
        denom = abs(tp) if abs(tp) > 1e-9 else 1.0
        commission_pct_of_profit = 100.0 * tc / denom
        out.append(
            BrokerAnalyticsRow(
                broker_id=row[0],
                broker_name=row[1],
                deals=int(row[2] or 0),
                total_commission=tc,
                total_profit=tp,
                commission_pct_of_profit=commission_pct_of_profit,
            )
        )
    return out
