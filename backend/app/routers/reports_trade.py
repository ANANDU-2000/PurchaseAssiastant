"""Reports sourced from trade_purchases + trade_purchase_lines (wholesale flow)."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy import String, and_, case, func, literal, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership
from app.models import CatalogItem, CategoryType, ItemCategory, Membership, TradePurchase, TradePurchaseLine, User
from app.models.contacts import Supplier
from app.services import trade_mapping as trade_map
from app.services import trade_query as tq

router = APIRouter(prefix="/v1/businesses/{business_id}/reports", tags=["reports-trade"])

_trade_line_amount_expr = tq.trade_line_amount_expr
_trade_purchase_date_filter = tq.trade_purchase_date_filter


async def _trade_suppliers_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> list[dict[str, Any]]:
    """Same rows as GET /trade-suppliers (line-based amounts, report status filter)."""
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    q = (
        select(
            Supplier.id,
            func.coalesce(Supplier.name, "Unknown").label("supplier_name"),
            func.count(func.distinct(TradePurchase.id)).label("deals"),
            func.coalesce(func.sum(amt), 0.0).label("total_purchase"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("total_qty"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(Supplier, Supplier.id == TradePurchase.supplier_id)
        .where(bf)
        .group_by(Supplier.id, Supplier.name)
        .having(func.count(func.distinct(TradePurchase.id)) > 0)
        .order_by(func.coalesce(func.sum(amt), 0.0).desc())
    )
    rows = (await db.execute(q)).mappings().all()
    return [
        {
            "supplier_id": str(r["id"]) if r["id"] is not None else "",
            "supplier_name": str(r["supplier_name"] or "Unknown"),
            "purchase_count": int(r["deals"] or 0),
            "deals": int(r["deals"] or 0),
            "total_purchase": float(r["total_purchase"] or 0),
            "total_qty": float(r["total_qty"] or 0),
            "total_profit": 0.0,
            "avg_landing": 0.0,
            "margin_pct": 0.0,
        }
        for r in rows
    ]


@router.get("/trade-supplier-broker-map")
async def trade_supplier_broker_map(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> dict[str, Any]:
    """Item-level trade lines to (supplier, broker) with vwap; optional z-scores and best-supplier recs (deals>=2)."""
    del _m
    detail, recs = await trade_map.item_supplier_broker_rows(db, business_id, date_from, date_to)
    return {"rows": detail, "recommendations": recs}


@router.get("/trade-dashboard-snapshot")
async def trade_dashboard_snapshot(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> dict[str, Any]:
    """Single payload matching report definitions: summary, unit rollups, categories with line items, types, top items."""
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    kpu = TradePurchaseLine.kg_per_unit
    lcpk = TradePurchaseLine.landing_cost_per_kg

    weight_ok = and_(kpu.isnot(None), lcpk.isnot(None), kpu > 0, lcpk > 0)
    kg_expr = case(
        (weight_ok, TradePurchaseLine.qty * kpu),
        else_=case(
            (func.upper(TradePurchaseLine.unit).like("%KG%"), TradePurchaseLine.qty),
            else_=0.0,
        ),
    )
    roll = (
        select(
            func.coalesce(
                func.sum(
                    case(
                        (func.upper(TradePurchaseLine.unit).like("%BAG%"), TradePurchaseLine.qty),
                        else_=0.0,
                    )
                ),
                0.0,
            ).label("total_bags"),
            func.coalesce(
                func.sum(
                    case(
                        (func.upper(TradePurchaseLine.unit).like("%BOX%"), TradePurchaseLine.qty),
                        else_=0.0,
                    )
                ),
                0.0,
            ).label("total_boxes"),
            func.coalesce(
                func.sum(
                    case(
                        (func.upper(TradePurchaseLine.unit).like("%TIN%"), TradePurchaseLine.qty),
                        else_=0.0,
                    )
                ),
                0.0,
            ).label("total_tins"),
            func.coalesce(func.sum(kg_expr), 0.0).label("total_kg"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(bf)
    )
    roll_row = (await db.execute(roll)).mappings().one()

    sum_q = select(
        func.count(func.distinct(TradePurchase.id)).label("deals"),
        func.coalesce(func.sum(amt), 0.0).label("total_purchase"),
        func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("total_qty"),
    ).select_from(TradePurchaseLine).join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id).where(bf)
    srow = (await db.execute(sum_q)).mappings().one()
    total_purchase = float(srow["total_purchase"] or 0)
    total_qty = float(srow["total_qty"] or 0)
    deals = int(srow["deals"] or 0)
    avg_landing = (total_purchase / total_qty) if total_qty > 1e-12 else 0.0

    items = await trade_items_breakdown(business_id, _m, db, date_from, date_to)
    types = await trade_types_breakdown(business_id, _m, db, date_from, date_to)

    cat_id_key = case(
        (ItemCategory.id.isnot(None), func.cast(ItemCategory.id, String)),
        else_=literal("_uncat"),
    ).label("category_id")
    cn = func.coalesce(ItemCategory.name, "Uncategorised").label("category_name")
    nest_q = (
        select(
            cat_id_key,
            cn,
            TradePurchaseLine.item_name,
            func.max(TradePurchaseLine.unit).label("unit"),
            func.coalesce(func.sum(amt), 0.0).label("amount"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("qty"),
            func.max(TradePurchaseLine.catalog_item_id).label("catalog_item_id"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(CatalogItem, CatalogItem.id == TradePurchaseLine.catalog_item_id)
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .where(bf)
        .group_by(cat_id_key, cn, TradePurchaseLine.item_name)
    )
    flat = (await db.execute(nest_q)).mappings().all()
    cat_map: dict[str, dict[str, Any]] = {}
    for r in flat:
        cid = str(r["category_id"] or "_uncat")
        cname = str(r["category_name"] or "Uncategorised")
        if cid not in cat_map:
            cat_map[cid] = {
                "category_id": cid,
                "category_name": cname,
                "total_purchase": 0.0,
                "total_qty": 0.0,
                "units": {"bags": 0.0, "boxes": 0.0, "tins": 0.0},
                "items": [],
            }
        unit = str(r["unit"] or "")
        uu = unit.upper()
        qv = float(r["qty"] or 0)
        am = float(r["amount"] or 0)
        cat_map[cid]["total_purchase"] += am
        cat_map[cid]["total_qty"] += qv
        if "BAG" in uu:
            cat_map[cid]["units"]["bags"] += qv
        if "BOX" in uu:
            cat_map[cid]["units"]["boxes"] += qv
        if "TIN" in uu:
            cat_map[cid]["units"]["tins"] += qv
        ci = r["catalog_item_id"]
        cat_map[cid]["items"].append(
            {
                "name": (r["item_name"] or "—").strip() or "—",
                "qty": qv,
                "unit": unit,
                "amount": am,
                "catalog_item_id": str(ci) if ci is not None else None,
            }
        )
    for c in cat_map.values():
        c["items"].sort(key=lambda x: x["amount"], reverse=True)

    detail, recs = await trade_map.item_supplier_broker_rows(db, business_id, date_from, date_to)
    suppliers = await _trade_suppliers_rows(db, business_id, date_from, date_to)
    cids = {d["catalog_item_id"] for d in detail if d.get("catalog_item_id")}
    scores: list[float] = []
    for cid in cids:
        zs = [r.get("vwap_zscore") for r in detail if r.get("catalog_item_id") == cid]
        sc = trade_map.consistency_score_from_zscores(zs)
        if sc is not None:
            scores.append(sc)
    portfolio_consistency = sum(scores) / len(scores) if scores else None

    return {
        "from": date_from.isoformat(),
        "to": date_to.isoformat(),
        "summary": {
            "deals": deals,
            "total_purchase": total_purchase,
            "total_qty": total_qty,
            "avg_landing": avg_landing,
        },
        "unit_totals": {
            "total_kg": float(roll_row["total_kg"] or 0),
            "total_bags": float(roll_row["total_bags"] or 0),
            "total_boxes": float(roll_row["total_boxes"] or 0),
            "total_tins": float(roll_row["total_tins"] or 0),
        },
        "categories": list(cat_map.values()),
        "subcategories": types,
        "item_slices": items,
        "suppliers": suppliers,
        "recommendations": recs,
        "consistency": {"portfolio_score": portfolio_consistency},
    }


@router.get("/trade-summary")
async def trade_purchase_summary(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    date_from: date | None = Query(None, alias="from"),
    date_to: date | None = Query(None, alias="to"),
    supplier_id: uuid.UUID | None = Query(None),
):
    """
    Line-based totals: same [trade_line_amount_expr] and status filter as
    /trade-items and /trade-dashboard-snapshot. Header [TradePurchase.total_amount]
    can differ (freight/rounding); report KPIs use line sums.
    """
    del user
    amt = tq.trade_line_amount_expr()
    conditions = [
        TradePurchase.business_id == business_id,
        tq.trade_purchase_status_in_reports(),
    ]
    if date_from is not None:
        conditions.append(TradePurchase.purchase_date >= date_from)
    if date_to is not None:
        conditions.append(TradePurchase.purchase_date <= date_to)
    if supplier_id is not None:
        conditions.append(TradePurchase.supplier_id == supplier_id)
    q = (
        select(
            func.count(func.distinct(TradePurchase.id)).label("deals"),
            func.coalesce(func.sum(amt), 0.0).label("total_purchase"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("total_qty"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(and_(*conditions))
    )
    m = (await db.execute(q)).mappings().one()
    deals = int(m["deals"] or 0)
    total_purchase = float(m["total_purchase"] or 0)
    total_qty = float(m["total_qty"] or 0)
    avg_cost = (total_purchase / total_qty) if total_qty > 1e-12 else 0.0

    kpu = TradePurchaseLine.kg_per_unit
    lcpk = TradePurchaseLine.landing_cost_per_kg
    weight_ok = and_(kpu.isnot(None), lcpk.isnot(None), kpu > 0, lcpk > 0)
    kg_expr = case(
        (weight_ok, TradePurchaseLine.qty * kpu),
        else_=case(
            (func.upper(TradePurchaseLine.unit).like("%KG%"), TradePurchaseLine.qty),
            else_=0.0,
        ),
    )
    roll_q = (
        select(
            func.coalesce(
                func.sum(
                    case(
                        (func.upper(TradePurchaseLine.unit).like("%BAG%"), TradePurchaseLine.qty),
                        else_=0.0,
                    )
                ),
                0.0,
            ).label("total_bags"),
            func.coalesce(
                func.sum(
                    case(
                        (func.upper(TradePurchaseLine.unit).like("%BOX%"), TradePurchaseLine.qty),
                        else_=0.0,
                    )
                ),
                0.0,
            ).label("total_boxes"),
            func.coalesce(
                func.sum(
                    case(
                        (func.upper(TradePurchaseLine.unit).like("%TIN%"), TradePurchaseLine.qty),
                        else_=0.0,
                    )
                ),
                0.0,
            ).label("total_tins"),
            func.coalesce(func.sum(kg_expr), 0.0).label("total_kg"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(and_(*conditions))
    )
    roll_row = (await db.execute(roll_q)).mappings().one()

    return {
        "deals": deals,
        "total_purchase": total_purchase,
        "total_qty": total_qty,
        "avg_cost": avg_cost,
        "unit_totals": {
            "total_kg": float(roll_row["total_kg"] or 0),
            "total_bags": float(roll_row["total_bags"] or 0),
            "total_boxes": float(roll_row["total_boxes"] or 0),
            "total_tins": float(roll_row["total_tins"] or 0),
        },
    }


@router.get("/trade-items")
async def trade_items_breakdown(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    del _m
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    q = (
        select(
            TradePurchaseLine.item_name,
            func.coalesce(func.sum(amt), 0).label("total_purchase"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0).label("total_qty"),
            func.count(TradePurchaseLine.id).label("line_count"),
            func.count(func.distinct(TradePurchaseLine.trade_purchase_id)).label("deals"),
            func.max(TradePurchaseLine.unit).label("unit"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(bf)
        .group_by(TradePurchaseLine.item_name)
        .order_by(func.coalesce(func.sum(amt), 0).desc())
    )
    rows = (await db.execute(q)).mappings().all()
    out: list[dict[str, Any]] = []
    for r in rows:
        qty = float(r["total_qty"] or 0)
        tp = float(r["total_purchase"] or 0)
        out.append(
            {
                "item_name": (r["item_name"] or "Unknown").strip() or "Unknown",
                "total_qty": qty,
                "unit": (r["unit"] or "").strip() or "—",
                "total_purchase": tp,
                "total_profit": 0.0,
                "line_count": int(r["line_count"] or 0),
                "purchase_count": int(r["deals"] or 0),
                "avg_landing": (tp / qty) if qty > 1e-12 else 0.0,
            }
        )
    return out


@router.get("/trade-suppliers")
async def trade_suppliers_breakdown(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    del _m
    return await _trade_suppliers_rows(db, business_id, date_from, date_to)


@router.get("/trade-categories")
async def trade_categories_breakdown(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    del _m
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    cat_key = func.coalesce(ItemCategory.name, "Uncategorized")
    qty_sum = func.coalesce(func.sum(TradePurchaseLine.qty), 0)
    q = (
        select(
            cat_key.label("category_name"),
            func.count(TradePurchaseLine.id).label("line_count"),
            func.count(func.distinct(TradePurchaseLine.catalog_item_id)).label("item_count"),
            func.coalesce(func.sum(amt), 0).label("total_purchase"),
            qty_sum.label("total_qty"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(CatalogItem, CatalogItem.id == TradePurchaseLine.catalog_item_id)
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .where(bf)
        .group_by(cat_key)
        .order_by(func.coalesce(func.sum(amt), 0).desc())
    )
    rows = (await db.execute(q)).mappings().all()
    return [
        {
            "category_name": str(r["category_name"] or "Uncategorized"),
            "category": str(r["category_name"] or "Uncategorized"),
            "line_count": int(r["line_count"] or 0),
            "item_count": int(r["item_count"] or 0),
            "total_purchase": float(r["total_purchase"] or 0),
            "total_profit": 0.0,
            "total_qty": float(r["total_qty"] or 0),
            "type_name": "—",
        }
        for r in rows
    ]


@router.get("/trade-types")
async def trade_types_breakdown(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    """Category → subcategory: spend grouped by CategoryType (catalog `type_id`) with parent category name."""
    del _m
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    parent_cat = func.coalesce(ItemCategory.name, "Uncategorized").label("category_name")
    type_label = case(
        (CatalogItem.type_id.is_(None), literal("No type")),
        else_=func.coalesce(CategoryType.name, "Unknown"),
    ).label("type_name")
    qty_sum = func.coalesce(func.sum(TradePurchaseLine.qty), 0)
    q = (
        select(
            parent_cat,
            type_label,
            func.coalesce(func.sum(amt), 0).label("total_purchase"),
            qty_sum.label("total_qty"),
            func.count(TradePurchaseLine.id).label("line_count"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(CatalogItem, CatalogItem.id == TradePurchaseLine.catalog_item_id)
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .outerjoin(CategoryType, CategoryType.id == CatalogItem.type_id)
        .where(bf)
        .group_by(parent_cat, type_label)
        .order_by(func.coalesce(func.sum(amt), 0).desc())
    )
    rows = (await db.execute(q)).mappings().all()
    return [
        {
            "type_name": str(r["type_name"] or "No type"),
            "category_name": str(r["category_name"] or "Uncategorized"),
            "subcategory": str(r["type_name"] or "No type"),
            "line_count": int(r["line_count"] or 0),
            "total_purchase": float(r["total_purchase"] or 0),
            "total_qty": float(r["total_qty"] or 0),
            "total_profit": 0.0,
        }
        for r in rows
    ]
