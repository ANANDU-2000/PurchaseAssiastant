import uuid
from datetime import datetime
from decimal import Decimal

from app.schemas.stock import StockListItemOut
from app.services.low_stock_priority import compute_low_stock_priority


def _item(
    *,
    name: str = "Rice",
    current_stock: str,
    reorder_level: str,
    stock_status: str,
    pending_order_days: int | None = None,
    has_pending_order: bool = False,
    period_usage_qty: str = "0",
    physical_stock_difference_qty: str = "0",
    needs_verification: bool = False,
) -> StockListItemOut:
    return StockListItemOut(
        id=uuid.uuid4(),
        item_code=None,
        name=name,
        category_name="Food",
        subcategory_name="Grains",
        supplier_name="Supplier A",
        unit="bag",
        rack_location=None,
        stock_status=stock_status,
        stock_unit="bag",
        current_stock=Decimal(current_stock),
        reorder_level=Decimal(reorder_level),
        has_pending_order=has_pending_order,
        pending_order_days=pending_order_days,
        period_usage_qty=Decimal(period_usage_qty),
        physical_stock_difference_qty=Decimal(physical_stock_difference_qty),
        needs_verification=needs_verification,
        last_stock_updated_at=datetime.utcnow(),
        last_stock_updated_by="Staff",
    )


def test_out_of_stock_is_highest():
    normal = _item(
        current_stock="10",
        reorder_level="5",
        stock_status="healthy",
        period_usage_qty="20",
    )
    out = _item(
        current_stock="0",
        reorder_level="5",
        stock_status="out",
        period_usage_qty="20",
    )
    assert compute_low_stock_priority(out).score > compute_low_stock_priority(normal).score


def test_delayed_is_higher_than_pending():
    pending_only = _item(
        current_stock="4",
        reorder_level="10",
        stock_status="low",
        has_pending_order=True,
        pending_order_days=3,
        period_usage_qty="10",
    )
    delayed = _item(
        current_stock="4",
        reorder_level="10",
        stock_status="low",
        has_pending_order=True,
        pending_order_days=10,
        period_usage_qty="10",
    )
    assert compute_low_stock_priority(delayed).score > compute_low_stock_priority(pending_only).score


def test_mismatch_is_higher_than_verification_only():
    verification_only = _item(
        current_stock="9",
        reorder_level="10",
        stock_status="low",
        needs_verification=True,
        period_usage_qty="10",
    )
    mismatch = _item(
        current_stock="9",
        reorder_level="10",
        stock_status="low",
        needs_verification=False,
        period_usage_qty="10",
        physical_stock_difference_qty="-2",
    )
    assert compute_low_stock_priority(mismatch).score > compute_low_stock_priority(verification_only).score

