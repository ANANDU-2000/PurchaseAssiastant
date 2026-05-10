"""Tests for ``rate_display_context.validate_rate_label_consistency``."""

from __future__ import annotations

from decimal import Decimal
import uuid

from app.schemas.trade_purchases import TradePurchaseLineIn
from app.services.rate_display_context import validate_rate_label_consistency


def _line(**kw: object) -> TradePurchaseLineIn:
    base: dict[str, object] = {
        "catalog_item_id": uuid.uuid4(),
        "item_name": "SUGAR",
        "qty": Decimal("1"),
        "unit": "bag",
        "landing_cost": Decimal("2750"),
        "purchase_rate": Decimal("2750"),
        "kg_per_unit": Decimal("50"),
        "landing_cost_per_kg": Decimal("55"),
        "discount": None,
        "tax_percent": None,
        "freight_type": None,
        "freight_value": None,
        "delivered_rate": None,
        "billty_rate": None,
        "selling_rate": None,
        "selling_cost": None,
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
    return TradePurchaseLineIn.model_validate(base)


def test_bag_with_kg_only_dim_is_blocker() -> None:
    li = _line()
    issues = validate_rate_label_consistency(li, {"purchase_rate_dim": "kg"})
    assert len(issues) == 1
    assert issues[0].get("severity") == "blocker"
    assert issues[0].get("code") == "rate_dim_bag_mismatch"


def test_bag_with_bag_dim_clean() -> None:
    li = _line()
    assert validate_rate_label_consistency(li, {"purchase_rate_dim": "bag"}) == []
