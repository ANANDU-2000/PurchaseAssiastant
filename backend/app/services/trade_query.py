"""Shared trade purchase line queries: value and report status filters."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import and_, case, func, literal, or_
from sqlalchemy.sql.elements import ColumnElement

from app.models import TradePurchase, TradePurchaseLine


TRADE_STATUS_IN_REPORTS: tuple[str, ...] = (
    "saved",
    "confirmed",
    "paid",
    "partially_paid",
    "overdue",
    "due_soon",
)


def trade_purchase_status_in_reports() -> ColumnElement[bool]:
    return TradePurchase.status.in_(TRADE_STATUS_IN_REPORTS)


def trade_line_amount_expr() -> ColumnElement:
    """Line spend: prefer stored canonical line total, fallback to legacy math."""
    kpu = TradePurchaseLine.kg_per_unit
    lcpk = TradePurchaseLine.landing_cost_per_kg
    weight_ok = and_(kpu.isnot(None), lcpk.isnot(None), kpu > 0, lcpk > 0)
    computed = case(
        (weight_ok, TradePurchaseLine.qty * kpu * lcpk),
        else_=TradePurchaseLine.qty
        * func.coalesce(TradePurchaseLine.purchase_rate, TradePurchaseLine.landing_cost),
    )
    return func.coalesce(TradePurchaseLine.line_total, computed)


def trade_line_qty_when_unit_type(
    *,
    canonical: str,
    legacy_like_patterns: tuple[str, ...],
) -> ColumnElement:
    """Qty counted toward bag/box/tin rollups using [unit_type] with LIKE fallback for unmigrated rows."""
    ut = TradePurchaseLine.unit_type
    legs = [func.upper(TradePurchaseLine.unit).like(pat) for pat in legacy_like_patterns]
    legacy = legs[0] if len(legs) == 1 else or_(*legs)
    matched = or_(ut == canonical, and_(ut.is_(None), legacy))
    return case((matched, TradePurchaseLine.qty), else_=literal(0.0))


def trade_line_qty_bags_expr() -> ColumnElement:
    return trade_line_qty_when_unit_type(canonical="bag", legacy_like_patterns=("%SACK%", "%BAG%"))


def trade_line_qty_boxes_expr() -> ColumnElement:
    return trade_line_qty_when_unit_type(canonical="box", legacy_like_patterns=("%BOX%",))


def trade_line_qty_tins_expr() -> ColumnElement:
    return trade_line_qty_when_unit_type(canonical="tin", legacy_like_patterns=("%TIN%",))


def trade_line_weight_expr() -> ColumnElement:
    """Physical kg movement for dashboards/reports."""
    kpu = func.coalesce(TradePurchaseLine.weight_per_unit, TradePurchaseLine.kg_per_unit)
    weight_ok = and_(kpu.isnot(None), kpu > 0)
    utype = TradePurchaseLine.unit_type
    kg_fallback = or_(
        utype == literal("kg"),
        and_(utype.is_(None), func.upper(TradePurchaseLine.unit).like("%KG%")),
    )
    legacy = case(
        (weight_ok, TradePurchaseLine.qty * kpu),
        else_=case((kg_fallback, TradePurchaseLine.qty), else_=literal(0)),
    )
    return func.coalesce(TradePurchaseLine.total_weight, legacy)


def trade_line_selling_expr() -> ColumnElement:
    selling = func.coalesce(TradePurchaseLine.selling_rate, TradePurchaseLine.selling_cost)
    return case(
        (selling.isnot(None), TradePurchaseLine.qty * selling),
        else_=0,
    )


def trade_line_profit_expr() -> ColumnElement:
    return func.coalesce(TradePurchaseLine.profit, trade_line_selling_expr() - trade_line_amount_expr())


def trade_purchase_date_filter(
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
):
    return and_(
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date >= date_from,
        TradePurchase.purchase_date <= date_to,
        trade_purchase_status_in_reports(),
    )
