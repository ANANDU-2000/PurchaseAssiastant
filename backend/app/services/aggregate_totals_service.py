"""Aggregated totals built only from ``line_totals_service`` primitives."""

from __future__ import annotations

from decimal import Decimal

from app.schemas.trade_purchases import TradePurchaseCreateRequest, TradePurchaseLineIn
from app.services import decimal_precision as dp
from app.services.line_totals_service import line_item_freight_charges, line_money


def _dec(x) -> Decimal:
    return Decimal(str(x))


def aggregate_landing_selling_profit(
    req: TradePurchaseCreateRequest,
) -> tuple[Decimal, Decimal | None, Decimal | None]:
    """SSOT line subtotals (tax/disc-inclusive line money + per-line charges)."""
    lines = req.lines
    land = sum((line_money(li) + line_item_freight_charges(li)) for li in lines)
    sell = sum((_dec(li.qty) * _dec(li.selling_rate)) for li in lines if li.selling_rate is not None)
    if sell <= 0:
        return dp.total(land), None, None
    return dp.total(land), dp.total(sell), dp.total(sell - land)
