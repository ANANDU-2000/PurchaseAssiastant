"""Reports sourced from trade_purchases + trade_purchase_lines (wholesale flow)."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, case, func, literal, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership
from app.models import CatalogItem, CategoryType, ItemCategory, Membership, TradePurchase, TradePurchaseLine, User
from app.models.contacts import Supplier

router = APIRouter(prefix="/v1/businesses/{business_id}/reports", tags=["reports-trade"])


def _trade_line_amount_expr():
    """Line spend: weight snapshot uses qty × kg_per_unit × landing_cost_per_kg."""
    kpu = TradePurchaseLine.kg_per_unit
    lcpk = TradePurchaseLine.landing_cost_per_kg
    weight_ok = and_(kpu.isnot(None), lcpk.isnot(None), kpu > 0, lcpk > 0)
    return case(
        (weight_ok, TradePurchaseLine.qty * kpu * lcpk),
        else_=TradePurchaseLine.qty * TradePurchaseLine.landing_cost,
    )


# Count purchases that have real lines for reporting. Must stay aligned with
# trade_purchase_summary so KPI totals and line-based breakdowns do not disagree
# (e.g. "paid" / "overdue" rows were missing from line reports before this).
_TRADE_STATUS_IN_REPORTS = (
    "saved",
    "confirmed",
    "paid",
    "partially_paid",
    "overdue",
    "due_soon",
)


def _trade_purchase_status_ok():
    return TradePurchase.status.in_(_TRADE_STATUS_IN_REPORTS)


def _trade_purchase_date_filter(
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
):
    return and_(
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date >= date_from,
        TradePurchase.purchase_date <= date_to,
        _trade_purchase_status_ok(),
    )


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
    del user
    q = select(
        func.count(TradePurchase.id).label("deals"),
        func.coalesce(func.sum(TradePurchase.total_amount), 0).label("total_purchase"),
        func.coalesce(func.sum(TradePurchase.total_qty), 0).label("total_qty"),
    ).where(TradePurchase.business_id == business_id)
    if date_from:
        q = q.where(TradePurchase.purchase_date >= date_from)
    if date_to:
        q = q.where(TradePurchase.purchase_date <= date_to)
    if supplier_id:
        q = q.where(TradePurchase.supplier_id == supplier_id)
    q = q.where(_trade_purchase_status_ok())
    m = (await db.execute(q)).mappings().one()
    deals = int(m["deals"] or 0)
    total_purchase = float(m["total_purchase"] or 0)
    total_qty = float(m["total_qty"] or 0)
    avg_cost = (total_purchase / total_qty) if total_qty > 0 else 0.0
    return {
        "deals": deals,
        "total_purchase": total_purchase,
        "total_qty": total_qty,
        "avg_cost": avg_cost,
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
        tq = float(r["total_qty"] or 0)
        tp = float(r["total_purchase"] or 0)
        out.append(
            {
                "item_name": (r["item_name"] or "Unknown").strip() or "Unknown",
                "total_qty": tq,
                "unit": (r["unit"] or "").strip() or "—",
                "total_purchase": tp,
                "total_profit": 0.0,
                "line_count": int(r["line_count"] or 0),
                "purchase_count": int(r["deals"] or 0),
                "avg_landing": (tp / tq) if tq > 1e-12 else 0.0,
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
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    q = (
        select(
            Supplier.id,
            func.coalesce(Supplier.name, "Unknown").label("supplier_name"),
            func.count(func.distinct(TradePurchase.id)).label("deals"),
            func.coalesce(func.sum(TradePurchase.total_amount), 0).label("total_purchase"),
            func.coalesce(func.sum(TradePurchase.total_qty), 0).label("total_qty"),
        )
        .select_from(TradePurchase)
        .outerjoin(Supplier, Supplier.id == TradePurchase.supplier_id)
        .where(bf)
        .group_by(Supplier.id, Supplier.name)
        .having(func.count(func.distinct(TradePurchase.id)) > 0)
        .order_by(func.coalesce(func.sum(TradePurchase.total_amount), 0).desc())
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
