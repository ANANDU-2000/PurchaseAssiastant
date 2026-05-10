"""Unit resolution from item name + category (wholesale pack semantics)."""

from __future__ import annotations

from decimal import Decimal

import pytest

from app.models.catalog import CatalogItem
from app.services.unit_resolution_service import resolve_for_catalog_item, resolve_from_text


@pytest.mark.parametrize(
    "name,category,brand,expect_unit,expect_size,expect_measure",
    [
        ("SUGAR 50KG", "SUGAR", False, "BAG", Decimal("50"), "KG"),
        ("SUGAR 50 KG", "SUGAR", False, "BAG", Decimal("50"), "KG"),
        ("JEERAKAM 30 KG", "SPICES", False, "BAG", Decimal("30"), "KG"),
        ("RUCHI 850GM", "BRANDED_GROCERY", False, "BOX", Decimal("850"), "GM"),
        ("RUCHI 850GM", "BRANDED_GROCERY", True, "BOX", Decimal("850"), "GM"),
        ("DALDA 15LTR", "OIL", False, "TIN", Decimal("15"), "LTR"),
    ],
)
def test_resolve_name_category_matrix(
    name: str,
    category: str,
    brand: bool,
    expect_unit: str,
    expect_size: Decimal,
    expect_measure: str,
) -> None:
    u = resolve_from_text(name, category_name=category, brand_detected=brand)
    assert u.selling_unit == expect_unit
    assert u.package_size == expect_size
    assert u.package_measurement == expect_measure


def test_sugar_bag_sack_package_type() -> None:
    u = resolve_from_text("SUGAR 50KG", category_name="SUGAR")
    assert u.package_type == "SACK"


def test_unverified_piece_catalog_row_is_overridden_by_strong_pack_rule() -> None:
    item = CatalogItem(
        name="RUCHI 425 GM",
        selling_unit="PCS",
        stock_unit="PCS",
        display_unit="PCS",
        unit_confidence=Decimal("95"),
        smart_classification="legacy_import",
        validation_status=None,
    )

    u = resolve_for_catalog_item(item, item_name="RUCHI 425 GM", category_name="BRANDED_GROCERY")

    assert u.selling_unit == "BOX"
    assert u.package_size == Decimal("425")
    assert u.package_measurement == "GM"
    assert u.rule_id and u.rule_id.endswith("+override_unverified_row")
