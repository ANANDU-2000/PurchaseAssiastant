"""Realtime purchase.changed payload helpers."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from types import SimpleNamespace

from app.routers.trade_purchases import (
    _catalog_item_ids_from_create,
    _catalog_item_ids_from_purchase,
)
from app.schemas.trade_purchases import TradePurchaseCreateRequest, TradePurchaseLineIn


def test_catalog_item_ids_from_purchase_dedupes():
    a, b = uuid.uuid4(), uuid.uuid4()
    out = SimpleNamespace(
        lines=[
            SimpleNamespace(catalog_item_id=a),
            SimpleNamespace(catalog_item_id=a),
            SimpleNamespace(catalog_item_id=b),
        ],
    )
    assert _catalog_item_ids_from_purchase(out) == [str(a), str(b)]  # type: ignore[arg-type]


def test_catalog_item_ids_from_create_body():
    item_id = uuid.uuid4()
    body = TradePurchaseCreateRequest(
        supplier_id=uuid.uuid4(),
        purchase_date=date.today(),
        lines=[
            TradePurchaseLineIn(
                catalog_item_id=item_id,
                item_name="Rice",
                qty=Decimal("2"),
                unit="kg",
                landing_cost=Decimal("100"),
            ),
        ],
    )
    assert _catalog_item_ids_from_create(body) == [str(item_id)]
