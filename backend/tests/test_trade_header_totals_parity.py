"""Header ``compute_totals`` vs ``line_totals_service`` + header freight/commission (no profit in purchase total)."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
import uuid

from app.schemas.trade_purchases import TradePurchaseCreateRequest, TradePurchaseLineIn
from app.services import decimal_precision as dp
from app.services.aggregate_totals_service import aggregate_landing_selling_profit
from app.services.line_totals_service import line_item_freight_charges, line_money
from app.services.trade_purchase_service import compute_totals


def _line(**kw: object) -> TradePurchaseLineIn:
    base: dict[str, object] = {
        "catalog_item_id": uuid.uuid4(),
        "item_name": "SUGAR 50KG",
        "qty": Decimal("2"),
        "unit": "bag",
        "landing_cost": Decimal("2500"),
        "purchase_rate": Decimal("2500"),
        "kg_per_unit": Decimal("50"),
        "landing_cost_per_kg": Decimal("50"),
        "selling_rate": Decimal("2600"),
        "discount": None,
        "tax_percent": None,
        "freight_type": None,
        "freight_value": None,
        "delivered_rate": None,
        "billty_rate": None,
        "box_mode": None,
        "items_per_box": None,
        "weight_per_item": None,
        "kg_per_box": None,
        "weight_per_tin": None,
        "hsn_code": None,
        "item_code": None,
        "description": None,
    }
    base.update(kw)
    return TradePurchaseLineIn.model_validate(base)


def test_header_total_matches_lines_plus_freight_and_percent_commission() -> None:
    lines = [_line()]
    req = TradePurchaseCreateRequest(
        purchase_date=date(2026, 5, 1),
        supplier_id=uuid.uuid4(),
        lines=lines,
        freight_amount=Decimal("100"),
        freight_type="separate",
        commission_percent=Decimal("5"),
        commission_mode="percent",
        discount=None,
    )
    qty_sum, total = compute_totals(req)
    line_roll = sum(line_money(li) + line_item_freight_charges(li) for li in lines)
    assert qty_sum == Decimal("2")
    assert line_roll == Decimal("5000")
    comm = dp.total(line_roll * dp.clamp_percent(Decimal("5")) / Decimal("100"))
    assert total == dp.total(line_roll + Decimal("100") + comm)


def test_profit_not_added_into_purchase_total() -> None:
    """Retail margin exists on lines but must not inflate ``total_amount``."""
    lines = [_line()]
    req = TradePurchaseCreateRequest(
        purchase_date=date(2026, 5, 1),
        supplier_id=uuid.uuid4(),
        lines=lines,
        freight_amount=None,
        freight_type=None,
        commission_percent=None,
        commission_mode="percent",
        discount=None,
    )
    land, _sell, prof = aggregate_landing_selling_profit(req)
    _, total = compute_totals(req)
    assert prof is not None and prof > 0
    assert total == land
    assert total + prof > total


def test_header_freight_skipped_when_any_line_has_item_level_charges() -> None:
    """If any line carries separate line freight, header freight is not stacked on top."""
    lines = [
        _line(
            freight_type="separate",
            freight_value=Decimal("40"),
        )
    ]
    req = TradePurchaseCreateRequest(
        purchase_date=date(2026, 5, 1),
        supplier_id=uuid.uuid4(),
        lines=lines,
        freight_amount=Decimal("60"),
        freight_type="separate",
        commission_percent=None,
        commission_mode="percent",
        discount=None,
    )
    _, total = compute_totals(req)
    line_roll = sum(line_money(li) + line_item_freight_charges(li) for li in lines)
    assert line_roll == Decimal("5040")
    assert total == line_roll


def test_header_freight_skipped_when_line_has_delivered_only() -> None:
    """Delivered / billty on a line count as item-level charges; header freight must not stack."""
    lines = [_line(delivered_rate=Decimal("25"))]
    req = TradePurchaseCreateRequest(
        purchase_date=date(2026, 5, 1),
        supplier_id=uuid.uuid4(),
        lines=lines,
        freight_amount=Decimal("999"),
        freight_type="separate",
        commission_percent=None,
        commission_mode="percent",
        discount=None,
    )
    _, total = compute_totals(req)
    line_roll = sum(line_money(li) + line_item_freight_charges(li) for li in lines)
    assert line_roll == Decimal("5025")
    assert total == line_roll


def test_header_percent_discount_applies_before_freight_and_commission() -> None:
    lines = [_line()]
    amt_before_disc = sum(line_money(li) + line_item_freight_charges(li) for li in lines)
    assert amt_before_disc == Decimal("5000")
    req = TradePurchaseCreateRequest(
        purchase_date=date(2026, 5, 1),
        supplier_id=uuid.uuid4(),
        lines=lines,
        freight_amount=Decimal("100"),
        freight_type="separate",
        commission_percent=Decimal("10"),
        commission_mode="percent",
        discount=Decimal("10"),
    )
    _, total = compute_totals(req)
    after_disc = amt_before_disc * Decimal("0.9")
    assert after_disc == Decimal("4500")
    comm = dp.total(after_disc * Decimal("10") / Decimal("100"))
    assert comm == Decimal("450")
    assert total == dp.total(after_disc + Decimal("100") + comm)


def test_line_tax_increases_roll_and_header_total() -> None:
    lines = [_line(tax_percent=Decimal("18"))]
    req = TradePurchaseCreateRequest(
        purchase_date=date(2026, 5, 1),
        supplier_id=uuid.uuid4(),
        lines=lines,
        freight_amount=None,
        freight_type=None,
        commission_percent=None,
        commission_mode="percent",
        discount=None,
    )
    _, total = compute_totals(req)
    line_roll = sum(line_money(li) + line_item_freight_charges(li) for li in lines)
    assert line_roll == Decimal("5900")
    assert total == line_roll


def test_flat_bag_commission_scales_by_bag_qty() -> None:
    lines = [_line()]
    req = TradePurchaseCreateRequest(
        purchase_date=date(2026, 5, 1),
        supplier_id=uuid.uuid4(),
        lines=lines,
        freight_amount=None,
        freight_type=None,
        commission_percent=None,
        commission_mode="flat_bag",
        commission_money=Decimal("15"),
        discount=None,
    )
    _, total = compute_totals(req)
    line_roll = sum(line_money(li) + line_item_freight_charges(li) for li in lines)
    assert line_roll == Decimal("5000")
    assert total == Decimal("5030")


def test_flat_kg_commission_scales_by_total_line_weight() -> None:
    lines = [_line()]
    req = TradePurchaseCreateRequest(
        purchase_date=date(2026, 5, 1),
        supplier_id=uuid.uuid4(),
        lines=lines,
        freight_amount=None,
        freight_type=None,
        commission_percent=None,
        commission_mode="flat_kg",
        commission_money=Decimal("2"),
        discount=None,
    )
    _, total = compute_totals(req)
    line_roll = sum(line_money(li) + line_item_freight_charges(li) for li in lines)
    assert line_roll == Decimal("5000")
    # 2 bags × 50 kg/bag = 100 kg × ₹2/kg commission
    assert total == Decimal("5200")
