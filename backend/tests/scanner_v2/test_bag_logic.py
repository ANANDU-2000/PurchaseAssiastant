"""Tests for ``scanner_v2.bag_logic`` covering the cases in
``docs/AI_SCANNER_TEST_CASES.md`` §A (T-A.01 .. T-A.14).
"""

from __future__ import annotations

from decimal import Decimal

import pytest

from app.services.scanner_v2.bag_logic import (
    detect_unit_type,
    infer_weight_per_unit_kg,
    normalize_bag_kg,
)
from app.services.scanner_v2.types import ItemRow


def _row(**kw) -> ItemRow:
    """Build an ItemRow with sensible defaults for tests."""
    base: dict = {"raw_name": kw.pop("raw_name", "Item")}
    base.update(kw)
    return ItemRow(**base)


def D(s: str | int | float) -> Decimal:
    return Decimal(str(s))


# ---------------- detect_unit_type ---------------- #

@pytest.mark.parametrize(
    "name,expected",
    [
        ("Sugar 50kg", "BAG"),
        ("Barli Rice 50 KG", "BAG"),
        ("Atta 25kg", "BAG"),
        ("Wheat 30kg bag", "BAG"),
        ("Pulses 10kg", "BAG"),
        ("Mustard 5kg", "BAG"),
        ("Ruchi 15kg tin", "TIN"),
        ("Oil 15 ltr tin", "TIN"),
        ("Choco box", "BOX"),
        ("Some packet", "BOX"),
        ("Sona Masuri", "BAG"),  # via catalog default
        ("Pacha Ari", "KG"),
    ],
)
def test_detect_unit_type_with_catalog_hint(name, expected):
    catalog = {"default_unit": "BAG"} if "Masuri" in name or "Pacha" not in name else None
    if name == "Pacha Ari":
        catalog = {"default_unit": "KG"}
    got = detect_unit_type(name, catalog=catalog)
    assert got == expected, f"{name} → {got} expected {expected}"


def test_detect_unit_type_explicit_kg_wins_over_name_weight():
    # T-A.08: name has 50 KG but unit is kg → KG (do not multiply)
    assert detect_unit_type("Sona Masuri 50 KG", explicit_unit="kg") == "KG"


def test_detect_unit_type_tin_beats_kg_token():
    assert detect_unit_type("Coconut Oil 15kg tin", catalog={"default_unit": "BAG"}) == "TIN"


def test_detect_unit_type_no_hint_defaults_kg():
    assert detect_unit_type("Random thing") == "KG"


# ---------------- infer_weight_per_unit_kg ---------------- #

@pytest.mark.parametrize(
    "name,expected",
    [
        ("Sugar 50 kg", D("50")),
        ("Sugar 50kg", D("50")),
        ("Atta 25kg", D("25")),
        ("Wheat 30kg bag", D("30")),
        ("Pulses 10kg", D("10")),
        ("Mustard 5kg", D("5")),
        ("Crazy 350kg", None),    # T-A.14 sanity reject
        ("No weight here", None),
    ],
)
def test_infer_weight(name, expected):
    got = infer_weight_per_unit_kg(name)
    if expected is None:
        assert got is None
    else:
        assert got == expected


# ---------------- normalize_bag_kg ---------------- #

def test_t_a_01_sugar_50kg_x_100_bag():
    item = _row(
        raw_name="Sugar 50kg",
        unit_type="BAG",
        bags=D("100"),
    )
    warns = normalize_bag_kg(item, catalog={"default_unit": "BAG", "default_kg_per_bag": D("50")})
    assert item.unit_type == "BAG"
    assert item.weight_per_unit_kg == D("50.000")
    assert item.bags == D("100")
    assert item.total_kg == D("5000.000")
    assert "BAG_KG_REMAINDER" not in warns


def test_t_a_02_only_total_kg_given_catalog_bag_50():
    item = _row(
        raw_name="Sugar 50kg",
        unit_type="BAG",
        total_kg=D("5000"),
    )
    normalize_bag_kg(item, catalog={"default_unit": "BAG", "default_kg_per_bag": D("50")})
    assert item.bags == D("100")
    assert item.weight_per_unit_kg == D("50.000")
    assert item.total_kg == D("5000")


def test_t_a_03_total_kg_with_remainder():
    item = _row(
        raw_name="Sugar 50kg",
        unit_type="BAG",
        total_kg=D("4970"),
    )
    warns = normalize_bag_kg(item, catalog={"default_unit": "BAG", "default_kg_per_bag": D("50")})
    assert "BAG_KG_REMAINDER" in warns
    assert item.bags == D("99")  # rounded


def test_t_a_04_barli_rice_50kg_bags_40():
    item = _row(raw_name="Barli Rice 50kg", unit_type="BAG", bags=D("40"))
    normalize_bag_kg(item, catalog={"default_unit": "BAG", "default_kg_per_bag": D("50")})
    assert item.total_kg == D("2000.000")
    assert item.weight_per_unit_kg == D("50.000")


def test_t_a_05_ruchi_15kg_tin():
    item = _row(raw_name="Ruchi 15kg tin", unit_type="TIN", qty=D("10"))
    normalize_bag_kg(item, catalog={"default_unit": "TIN", "default_weight_per_tin": D("15")})
    assert item.unit_type == "TIN"
    assert item.weight_per_unit_kg == D("15.000")
    # qty acted as count → bags=10, total_kg=150
    assert item.bags == D("10")
    assert item.total_kg == D("150.000")


def test_t_a_07_kg_unit_no_name_weight():
    item = _row(raw_name="Pacha Ari", unit_type="KG", qty=D("120"))
    warns = normalize_bag_kg(item, catalog={"default_unit": "KG"})
    assert item.unit_type == "KG"
    assert item.bags is None
    assert item.weight_per_unit_kg is None
    assert item.total_kg == D("120.000")
    assert "KG_UNIT_BAGS_DROPPED" not in warns


def test_t_a_08_kg_unit_with_50kg_in_name_does_not_multiply():
    # explicit unit forces KG; name's "50 KG" must be ignored
    item = _row(raw_name="Sona Masuri 50 KG", unit_type="KG", qty=D("200"))
    warns = normalize_bag_kg(item, catalog={"default_unit": "KG"})
    assert item.total_kg == D("200.000")
    assert item.bags is None
    assert item.weight_per_unit_kg is None
    # qty stays = 200, NOT 200 * 50
    assert item.qty == D("200.000")
    assert "KG_UNIT_BAGS_DROPPED" not in warns


def test_t_a_09_wheat_30kg_bag_50():
    item = _row(raw_name="Wheat 30kg bag", unit_type="BAG", bags=D("50"))
    normalize_bag_kg(item, catalog={"default_unit": "BAG"})
    assert item.weight_per_unit_kg == D("30.000")
    assert item.total_kg == D("1500.000")


def test_t_a_10_atta_25kg_bags_80():
    item = _row(raw_name="Atta 25kg", unit_type="BAG", bags=D("80"))
    normalize_bag_kg(item, catalog={"default_unit": "BAG"})
    assert item.weight_per_unit_kg == D("25.000")
    assert item.total_kg == D("2000.000")


def test_t_a_11_pulses_10kg_bags_12():
    item = _row(raw_name="Pulses 10kg", unit_type="BAG", bags=D("12"))
    normalize_bag_kg(item, catalog={"default_unit": "BAG"})
    assert item.weight_per_unit_kg == D("10.000")
    assert item.total_kg == D("120.000")


def test_t_a_12_mustard_5kg_bags_4():
    item = _row(raw_name="Mustard 5kg", unit_type="BAG", bags=D("4"))
    normalize_bag_kg(item, catalog={"default_unit": "BAG"})
    assert item.weight_per_unit_kg == D("5.000")
    assert item.total_kg == D("20.000")


def test_t_a_13_mixed_unit_inconsistency_flags_remainder():
    """User supplied bags=100, weight=50 implies 5000kg but total_kg=5005 — mismatch."""
    item = _row(
        raw_name="Sugar 50kg",
        unit_type="BAG",
        bags=D("100"),
        total_kg=D("5005"),
    )
    warns = normalize_bag_kg(item, catalog={"default_unit": "BAG", "default_kg_per_bag": D("50")})
    assert "BAG_KG_REMAINDER" in warns


def test_t_a_14_weight_outside_band_returns_none():
    assert infer_weight_per_unit_kg("Crazy 350kg") is None
