"""Smoke tests for backend unit resolution (package size vs selling unit)."""

from __future__ import annotations

from decimal import Decimal

from app.services.unit_resolution_service import resolve_from_text


def test_sugar_50kg_bag_sack() -> None:
    u = resolve_from_text("SUGAR 50KG", category_name="SUGAR")
    assert u.selling_unit == "BAG"
    assert u.package_type == "SACK"
    assert u.package_size == Decimal("50")
    assert u.package_measurement == "KG"


def test_ruchi_850gm_box_brand() -> None:
    u = resolve_from_text("RUCHI 850GM", category_name="BRANDED_GROCERY", brand_detected=True)
    assert u.selling_unit == "BOX"
    assert u.package_size == Decimal("850")


def test_dalda_15ltr_tin() -> None:
    u = resolve_from_text("DALDA 15LTR", category_name="OIL")
    assert u.selling_unit == "TIN"
    assert u.package_size == Decimal("15")
