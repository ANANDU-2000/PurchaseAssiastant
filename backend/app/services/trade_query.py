"""Shared trade purchase line queries — single source of truth for value + status filters.

All dashboard mapping, reports, and recommendations must use these helpers so numbers
match everywhere. See docs in deterministic engine plan.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import and_, case
from sqlalchemy.sql.elements import ColumnElement

from app.models import TradePurchase, TradePurchaseLine

# Purchases that contribute to trade analytics (line-level join uses same list).
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
    """Line spend: weight lines use qty × kg_per_unit × landing_cost_per_kg."""
    kpu = TradePurchaseLine.kg_per_unit
    lcpk = TradePurchaseLine.landing_cost_per_kg
    weight_ok = and_(kpu.isnot(None), lcpk.isnot(None), kpu > 0, lcpk > 0)
    return case(
        (weight_ok, TradePurchaseLine.qty * kpu * lcpk),
        else_=TradePurchaseLine.qty * TradePurchaseLine.landing_cost,
    )


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
