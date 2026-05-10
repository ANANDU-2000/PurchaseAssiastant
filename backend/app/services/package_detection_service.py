"""Thin façade over ``unit_resolution_service`` for package-oriented naming."""

from __future__ import annotations

from app.models.catalog import CatalogItem
from app.services.unit_resolution_service import UnitResolution, resolve_for_catalog_item, resolve_from_text


def detect_from_text(
    item_name: str,
    *,
    category_name: str | None = None,
    brand_detected: bool = False,
) -> UnitResolution:
    return resolve_from_text(item_name, category_name=category_name, brand_detected=brand_detected)


def detect_for_item(
    catalog_item: CatalogItem | None,
    *,
    item_name: str,
    category_name: str | None = None,
    brand_detected: bool = False,
) -> UnitResolution:
    return resolve_for_catalog_item(
        catalog_item,
        item_name=item_name,
        category_name=category_name,
        brand_detected=brand_detected,
    )
