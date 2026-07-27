"""Catalog create — simplified 5-unit warehouse flow (unit + schema tests)."""

import pytest
from pydantic import ValidationError

from app.routers.catalog import CatalogItemCreate, _parse_kg_from_item_name


def test_parse_kg_from_item_name():
    assert _parse_kg_from_item_name("SUGAR 50KG") == 50.0
    assert _parse_kg_from_item_name("TRUSALT 25kg") == 25.0
    assert _parse_kg_from_item_name("NO WEIGHT") is None


def test_catalog_create_bag_infers_kg_from_name():
    import uuid

    body = CatalogItemCreate(
        category_id=uuid.uuid4(),
        name="SUGAR 50KG",
        default_unit="bag",
    )
    assert body.default_kg_per_bag == 50.0


def test_catalog_create_bag_without_kg_raises():
    import uuid

    with pytest.raises(ValidationError):
        CatalogItemCreate(
            category_id=uuid.uuid4(),
            name="SUGAR BULK",
            default_unit="bag",
        )


def test_catalog_create_box_defaults_items_per_box():
    import uuid

    body = CatalogItemCreate(
        category_id=uuid.uuid4(),
        name="TEA BOX",
        default_unit="box",
    )
    assert body.default_items_per_box == 1.0


def test_catalog_create_tin_no_conversion_required():
    import uuid

    body = CatalogItemCreate(
        category_id=uuid.uuid4(),
        name="COCONUT OIL TIN",
        default_unit="tin",
    )
    assert body.default_weight_per_tin is None


def test_catalog_create_piece_and_kg():
    import uuid

    kg = CatalogItemCreate(
        category_id=uuid.uuid4(),
        name="RICE LOOSE",
        default_unit="kg",
    )
    assert kg.default_unit == "kg"

    pc = CatalogItemCreate(
        category_id=uuid.uuid4(),
        name="NAIL PC",
        default_unit="piece",
    )
    assert pc.default_unit == "piece"
