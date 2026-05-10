"""Preview line total heuristics for scanner_v2 (BAG / BOX / TIN / KG)."""

from decimal import Decimal

from app.services.scanner_v2.pipeline import _compute_preview_line_total
from app.services.scanner_v2.types import ItemRow, Warning


def test_box_small_rate_per_kg_via_qty_and_wpu() -> None:
    w: list[Warning] = []
    it = ItemRow(
        raw_name="oil box",
        unit_type="BOX",
        qty=Decimal("10"),
        weight_per_unit_kg=Decimal("15"),
        purchase_rate=Decimal("120"),
    )
    assert _compute_preview_line_total(it, w) == Decimal("18000.00")  # 10 * 15 * 120


def test_tin_small_rate_prefers_total_kg_when_present() -> None:
    w: list[Warning] = []
    it = ItemRow(
        raw_name="ghee tin",
        unit_type="TIN",
        qty=Decimal("8"),
        total_kg=Decimal("96"),
        weight_per_unit_kg=Decimal("12"),
        purchase_rate=Decimal("45"),
    )
    assert _compute_preview_line_total(it, w) == Decimal("4320.00")  # 96 * 45


def test_box_large_rate_per_container() -> None:
    w: list[Warning] = []
    it = ItemRow(
        raw_name="gift box",
        unit_type="BOX",
        qty=Decimal("6"),
        purchase_rate=Decimal("850"),
    )
    assert _compute_preview_line_total(it, w) == Decimal("5100.00")


def test_bag_preview_requires_rate_context() -> None:
    w: list[Warning] = []
    it = ItemRow(
        raw_name="Sugar",
        unit_type="BAG",
        bags=Decimal("10"),
        weight_per_unit_kg=Decimal("50"),
        purchase_rate=Decimal("42"),
    )
    assert _compute_preview_line_total(it, w) is None
    assert any(x.code == "BAG_RATE_CONTEXT_REQUIRED" for x in w)


def test_bag_per_kg_with_context_computes() -> None:
    w: list[Warning] = []
    it = ItemRow(
        raw_name="Sugar",
        unit_type="BAG",
        bags=Decimal("10"),
        weight_per_unit_kg=Decimal("50"),
        purchase_rate=Decimal("42"),
        rate_context="per_kg",
    )
    assert _compute_preview_line_total(it, w) == Decimal("21000.00")


def test_bag_per_bag_with_context_computes() -> None:
    w: list[Warning] = []
    it = ItemRow(
        raw_name="Sugar",
        unit_type="BAG",
        bags=Decimal("10"),
        weight_per_unit_kg=Decimal("50"),
        purchase_rate=Decimal("2100"),
        rate_context="per_bag",
    )
    assert _compute_preview_line_total(it, w) == Decimal("21000.00")
