"""Single source of truth for **trade purchase line money** and **line weight**.

All purchase / selling / profit math for confirmed trade flows should delegate here.
Header-level freight, discount, and commission stay in ``trade_purchase_service``.
"""

from __future__ import annotations

from decimal import Decimal

from app.schemas.trade_purchases import TradePurchaseCreateRequest, TradePurchaseLineIn
from app.services import decimal_precision as dp
from app.services.trade_report_line_mirror import trade_line_weight_sql_python
from app.services.trade_unit_type import derive_trade_unit_type, parse_kg_per_bag_from_name


def _dec(x) -> Decimal:
    return Decimal(str(x))


def simple_purchase_total(*, qty: Decimal | float | int, purchase_rate: Decimal | float | int) -> Decimal:
    """qty × purchase_rate (no tax/discount)."""
    return dp.total(_dec(qty) * _dec(purchase_rate))


def simple_selling_total(*, qty: Decimal | float | int, selling_rate: Decimal | float | int) -> Decimal:
    """qty × selling_rate."""
    return dp.total(_dec(qty) * _dec(selling_rate))


def simple_profit(*, purchase_total: Decimal, selling_total: Decimal) -> Decimal:
    """selling_total − purchase_total (never folds profit into purchase)."""
    return dp.total(_dec(selling_total) - _dec(purchase_total))


def line_gross_base(li: TradePurchaseLineIn) -> Decimal:
    """Pre-discount line landing gross (weight-priced or unit-priced).

    Weight-priced path matches ``trade_query.trade_line_amount_expr`` / reports:
    only when ``kg_per_unit * landing_cost_per_kg`` agrees with the unit landing
    rate within ₹0.05 (avoids inconsistent snapshots inflating totals).
    """
    qty = _dec(li.qty)
    kpu = li.kg_per_unit
    lcpk = li.landing_cost_per_kg
    landing = _dec(li.purchase_rate) if li.purchase_rate is not None else _dec(li.landing_cost)
    if kpu is not None and lcpk is not None and landing is not None:
        derived = _dec(kpu) * _dec(lcpk)
        if _dec(kpu) > 0 and _dec(lcpk) > 0 and abs(derived - landing) <= Decimal("0.05"):
            return qty * _dec(kpu) * _dec(lcpk)
    return qty * landing


def line_item_freight_charges(li: TradePurchaseLineIn) -> Decimal:
    """Per-line freight (when separate) + delivered + billty."""
    freight_type = li.freight_type
    freight = li.freight_value
    freight_dec = _dec(freight) if freight is not None and freight_type == "separate" else Decimal("0")
    delivered = _dec(li.delivered_rate) if li.delivered_rate is not None else Decimal("0")
    billty = _dec(li.billty_rate) if li.billty_rate is not None else Decimal("0")
    return freight_dec + delivered + billty


def line_money(li: TradePurchaseLineIn) -> Decimal:
    """Authoritative line purchase amount (discount + tax on landing gross)."""
    base = line_gross_base(li)
    ld = _dec(li.discount) if li.discount is not None else Decimal("0")
    after_disc = base * (Decimal("1") - dp.clamp_percent(ld) / Decimal("100"))
    tax = _dec(li.tax_percent) if li.tax_percent is not None else Decimal("0")
    return after_disc * (Decimal("1") + dp.clamp_percent(tax, Decimal("1000")) / Decimal("100"))


def line_total_weight(li: TradePurchaseLineIn) -> Decimal:
    """Kg roll-up aligned with ``trade_query.trade_line_weight_expr`` + BAG name fallback.

    SQL has no ``50 KG`` name parse; for API/wizard lines we derive missing kg/bag from
    ``item_name`` so preview matches persisted totals after save.
    """
    ut = (li.unit or "").strip().upper()
    kpu_src = li.weight_per_unit if li.weight_per_unit is not None else li.kg_per_unit
    if (
        derive_trade_unit_type(li.unit) == "bag"
        and (kpu_src is None or _dec(kpu_src) <= 0)
    ):
        parsed = parse_kg_per_bag_from_name(li.item_name)
        if parsed is not None:
            li_adj = li.model_copy(update={"weight_per_unit": parsed, "kg_per_unit": parsed})
            return trade_line_weight_sql_python(li_adj, persisted_total_weight_kg=None, unit_type_db=None)
    base = trade_line_weight_sql_python(li, persisted_total_weight_kg=None, unit_type_db=None)
    if base > 0:
        return base
    # Legacy PCS/other rows with explicit weight_per_unit only (not in SQL weight expr).
    if li.weight_per_unit is not None and ut not in ("BOX", "TIN", "BAG") and "KG" not in ut:
        return dp.total_weight(_dec(li.qty) * _dec(li.weight_per_unit))
    return Decimal("0")


def line_profit(li: TradePurchaseLineIn, req: TradePurchaseCreateRequest) -> Decimal | None:
    """Revenue (qty×selling_rate) minus fully-loaded purchase cost for the line."""
    del req  # reserved for future header coupling; charges are line-local today
    if li.selling_rate is None:
        return None
    revenue = _dec(li.qty) * _dec(li.selling_rate)
    total_cost = line_money(li) + line_item_freight_charges(li)
    return dp.total(revenue - total_cost)


def line_landing_gross_in(li: TradePurchaseLineIn) -> Decimal:
    return line_gross_base(li)


def line_selling_gross_in(li: TradePurchaseLineIn) -> Decimal:
    if li.selling_cost is None:
        return Decimal("0")
    if li.kg_per_unit is not None and li.landing_cost_per_kg is not None:
        return _dec(li.qty) * _dec(li.kg_per_unit) * _dec(li.selling_cost)
    return _dec(li.qty) * _dec(li.selling_cost)
