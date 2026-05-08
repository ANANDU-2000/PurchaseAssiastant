"""Unit tests for scanner item pack-size / unit-channel gate."""

from __future__ import annotations

from decimal import Decimal
from uuid import uuid4

from app.models.catalog import CatalogItem
from app.services.scanner_v2.pack_gate import (
    catalog_pack_kg_hint,
    extract_kg_hint_from_text,
    should_demote_item_match,
    unit_channel_conflict,
)
from app.services.scanner_v2.types import ItemRow


def test_extract_kg_hint_last_token():
    assert extract_kg_hint_from_text("Sugar 50kg") == Decimal("50")
    assert extract_kg_hint_from_text("BAKER CRAFT ICING SUGAR 1KG") == Decimal("1")


def test_unit_channel_bag_vs_piece():
    cat = CatalogItem(
        id=uuid4(),
        business_id=uuid4(),
        category_id=uuid4(),
        name="Retail pkt",
        default_unit="piece",
        default_kg_per_bag=None,
    )
    assert unit_channel_conflict("BAG", cat) is True


def test_demote_when_kg_hints_differ():
    cat = CatalogItem(
        id=uuid4(),
        business_id=uuid4(),
        category_id=uuid4(),
        name="SUGAR 50 KG",
        default_unit="bag",
        default_kg_per_bag=Decimal("50"),
    )
    row = ItemRow(
        raw_name="BAKER CRAFT ICING SUGAR 1KG",
        matched_catalog_item_id=cat.id,
        matched_name=cat.name,
        confidence=0.95,
        match_state="auto",
        unit_type="BAG",
        weight_per_unit_kg=None,
    )
    assert should_demote_item_match(row=row, catalog=cat) is True


def test_keep_when_kg_hints_align():
    cat = CatalogItem(
        id=uuid4(),
        business_id=uuid4(),
        category_id=uuid4(),
        name="SUGAR 50KG",
        default_unit="bag",
        default_kg_per_bag=Decimal("50"),
    )
    row = ItemRow(
        raw_name="Sugar 50kg",
        matched_catalog_item_id=cat.id,
        matched_name=cat.name,
        confidence=0.95,
        match_state="auto",
        unit_type="BAG",
        weight_per_unit_kg=Decimal("50"),
    )
    assert should_demote_item_match(row=row, catalog=cat) is False


def test_catalog_hint_from_name_when_no_default_kg():
    cat = CatalogItem(
        id=uuid4(),
        business_id=uuid4(),
        category_id=uuid4(),
        name="ANNAPURNA CHAKKI ATTA 50 KG",
        default_unit="bag",
        default_kg_per_bag=None,
    )
    assert catalog_pack_kg_hint(cat) == Decimal("50")
