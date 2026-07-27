"""Parity: ``line_totals_service`` vs ``trade_report_line_mirror`` (SQL semantics)."""

from __future__ import annotations

from decimal import Decimal
import uuid

import pytest

from app.schemas.trade_purchases import TradePurchaseLineIn
from app.services.line_totals_service import line_gross_base, line_total_weight
from app.services.trade_report_line_mirror import (
    trade_line_computed_amount_python,
    trade_line_qty_bags_python,
    trade_line_qty_boxes_python,
    trade_line_qty_tins_python,
    trade_line_weight_sql_python,
)


def _line(**kw) -> TradePurchaseLineIn:
    base = {
        "catalog_item_id": uuid.uuid4(),
        "item_name": kw.get("item_name", "Test item"),
        "qty": Decimal("1"),
        "unit": "kg",
        "landing_cost": Decimal("100"),
        "purchase_rate": Decimal("100"),
        "selling_rate": None,
        "discount": None,
        "tax_percent": None,
        "weight_per_unit": None,
        "kg_per_unit": None,
        "landing_cost_per_kg": None,
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
    return TradePurchaseLineIn.model_construct(**base)


@pytest.mark.parametrize(
    "fixture_kw",
    [
        {"qty": Decimal("10"), "unit": "kg", "landing_cost": Decimal("55")},
        {
            "qty": Decimal("100"),
            "unit": "bag",
            "landing_cost": Decimal("2000"),
            "purchase_rate": Decimal("2000"),
            "kg_per_unit": Decimal("50"),
            "landing_cost_per_kg": Decimal("40"),
        },
        {
            "qty": Decimal("4"),
            "unit": "box",
            "landing_cost": Decimal("120"),
        },
    ],
)
def test_line_gross_base_matches_trade_query_mirror(fixture_kw: dict) -> None:
    li = _line(**fixture_kw)
    assert line_gross_base(li) == trade_line_computed_amount_python(li, persisted_line_total=None)


def test_inconsistent_weight_snapshot_falls_back_to_unit_rate() -> None:
    """When kpu*lcpk disagrees with landing, SQL and Python use qty × landing."""
    li = _line(
        qty=Decimal("10"),
        unit="bag",
        landing_cost=Decimal("80"),
        purchase_rate=Decimal("80"),
        kg_per_unit=Decimal("50"),
        landing_cost_per_kg=Decimal("2"),
    )
    assert line_gross_base(li) == Decimal("800")
    assert trade_line_computed_amount_python(li, persisted_line_total=None) == Decimal("800")


def test_persisted_line_total_short_circuits_mirror() -> None:
    li = _line(qty=Decimal("99"), unit="kg", landing_cost=Decimal("1"))
    stored = Decimal("123.45")
    assert trade_line_computed_amount_python(li, persisted_line_total=stored) == stored


def test_weight_sql_mirror_vs_line_total_weight_when_kpu_explicit() -> None:
    li = _line(
        qty=Decimal("100"),
        unit="BAG",
        landing_cost=Decimal("2000"),
        kg_per_unit=Decimal("50"),
        landing_cost_per_kg=Decimal("40"),
        item_name="SUGAR",
    )
    assert line_total_weight(li) == trade_line_weight_sql_python(li)


def test_weight_mirror_respects_persisted_total_weight() -> None:
    li = _line(
        qty=Decimal("10"),
        unit="BAG",
        landing_cost=Decimal("500"),
        kg_per_unit=Decimal("50"),
        landing_cost_per_kg=Decimal("10"),
    )
    assert trade_line_weight_sql_python(li, persisted_total_weight_kg=Decimal("999")) == Decimal("999.000")


def test_bag_box_tin_qty_rollups() -> None:
    bag = _line(qty=Decimal("12"), unit="SACK", landing_cost=Decimal("10"))
    assert trade_line_qty_bags_python(bag) == Decimal("12")
    box = _line(qty=Decimal("3"), unit="CARTON BOX", landing_cost=Decimal("10"))
    assert trade_line_qty_boxes_python(box) == Decimal("3")
    tin = _line(qty=Decimal("7"), unit="15LTR TIN", landing_cost=Decimal("10"))
    assert trade_line_qty_tins_python(tin) == Decimal("7")


def test_computed_amount_uses_persisted_line_total_when_set() -> None:
    """``trade_line_amount_expr`` / mirror: coalesce prefers stored ``line_total``."""
    li = _line(
        qty=Decimal("10"),
        unit="bag",
        landing_cost=Decimal("5000"),
        kg_per_unit=Decimal("50"),
        landing_cost_per_kg=Decimal("100"),
    )
    assert trade_line_computed_amount_python(li, persisted_line_total=Decimal("12345.67")) == Decimal(
        "12345.67"
    )
