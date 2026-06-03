"""Stock delivery-indicator-counts and date_from/date_to list aliases."""

from datetime import date

from app.routers.stock import (
    _classify_delivery_indicator,
    _parse_period_dates,
    _resolve_period_query,
)


def test_resolve_period_query_prefers_explicit_period():
    ps, pe = _resolve_period_query("2026-01-01", "2026-01-31", "2025-12-01", "2025-12-31")
    assert ps == "2026-01-01"
    assert pe == "2026-01-31"


def test_parse_period_dates_from_date_aliases():
    ps, pe = _parse_period_dates("2026-06-01", "2026-06-03")
    assert ps == date(2026, 6, 1)
    assert pe == date(2026, 6, 3)


def test_classify_delivery_indicator_pending_qty():
    kind = _classify_delivery_indicator(
        has_pending_order=False,
        pending_delivery_qty=1,
        last_purchase_human_id="PO-1",
        last_purchase_delivered=True,
        last_purchase_at=None,
    )
    assert kind == "pending"


def test_classify_delivery_indicator_delivered_recent():
    from datetime import datetime, timezone

    kind = _classify_delivery_indicator(
        has_pending_order=False,
        pending_delivery_qty=None,
        last_purchase_human_id="PO-2",
        last_purchase_delivered=True,
        last_purchase_at=datetime.now(timezone.utc),
    )
    assert kind == "delivered"
