"""Master rebuild package rule tests for backend totals.

Mirrors `flutter_app/test/package_rules_test.dart` so backend math agrees with
the wizard preview:
- BAG: `qty bags × per_bag_kg = total_kg` (auto-derive per_bag_kg from item name).
- BOX/TIN: count-only (zero kg).
"""

from __future__ import annotations

from decimal import Decimal

from app.schemas.trade_purchases import TradePurchaseLineIn
from app.services.line_totals_service import line_total_weight
from app.services.trade_unit_type import (
    derive_trade_unit_type,
    parse_kg_per_bag_from_name,
)


def _line(**kw) -> TradePurchaseLineIn:
    """Bypass schema validation so we can probe `line_total_weight` with the
    legacy partial inputs the backend must still tolerate (BAG without
    weight_per_unit must auto-derive kg from the item name)."""
    base = {
        "catalog_item_id": "00000000-0000-0000-0000-000000000001",
        "item_name": "Rice",
        "qty": Decimal("1"),
        "unit": "BAG",
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


def test_parse_kg_per_bag_sugar_50_kg() -> None:
    assert parse_kg_per_bag_from_name("SUGAR 50 KG") == Decimal("50")


def test_parse_kg_per_bag_rice_26_kg() -> None:
    assert parse_kg_per_bag_from_name("RICE 26 KG") == Decimal("26")


def test_parse_kg_per_bag_lowercase_no_space() -> None:
    assert parse_kg_per_bag_from_name("rice 30kg") == Decimal("30")


def test_parse_kg_per_bag_returns_none_when_missing() -> None:
    assert parse_kg_per_bag_from_name("Plain Rice") is None
    assert parse_kg_per_bag_from_name(None) is None
    assert parse_kg_per_bag_from_name("") is None


def test_parse_kg_per_bag_rejects_unrealistic_values() -> None:
    # Year-like numbers in IDs/dates must not be treated as kg/bag.
    assert parse_kg_per_bag_from_name("INV-2025 KG") is None


def test_line_total_weight_bag_with_explicit_weight_per_unit() -> None:
    li = _line(
        item_name="SUGAR 50 KG",
        qty=Decimal("100"),
        unit="BAG",
        kg_per_unit=Decimal("50"),
        landing_cost_per_kg=Decimal("55"),
    )
    assert line_total_weight(li) == Decimal("5000.000")


def test_line_total_weight_bag_falls_back_to_name_when_weight_missing() -> None:
    """[Bug 2 fix] 100 bags × name-derived 50 kg = 5000 kg, never 100."""
    li = _line(item_name="SUGAR 50 KG", qty=Decimal("100"), unit="BAG")
    assert line_total_weight(li) == Decimal("5000.000")


def test_line_total_weight_bag_returns_zero_when_no_weight_or_name_hint() -> None:
    li = _line(item_name="Plain Rice", qty=Decimal("100"), unit="BAG")
    assert line_total_weight(li) == Decimal("0")


def test_line_total_weight_box_is_zero() -> None:
    """BOX is count-only — kg always zero."""
    li = _line(
        item_name="SUNRICH 400GM BOX",
        qty=Decimal("100"),
        unit="BOX",
    )
    assert line_total_weight(li) == Decimal("0")


def test_line_total_weight_tin_is_zero_even_with_weight_per_tin() -> None:
    li = _line(
        item_name="RBD 15LTR TIN",
        qty=Decimal("50"),
        unit="TIN",
        weight_per_tin=Decimal("15"),
    )
    assert line_total_weight(li) == Decimal("0")


def test_line_total_weight_kg_unit_uses_qty() -> None:
    li = _line(item_name="Loose rice", qty=Decimal("125"), unit="KG")
    assert line_total_weight(li) == Decimal("125.000")


def test_derive_trade_unit_type_canonical_set() -> None:
    assert derive_trade_unit_type("BAG") == "bag"
    assert derive_trade_unit_type("SACK") == "bag"  # legacy normalization
    assert derive_trade_unit_type("BOX") == "box"
    assert derive_trade_unit_type("CARTON BOX") == "box"
    assert derive_trade_unit_type("TIN") == "tin"
    assert derive_trade_unit_type("KG") == "kg"
