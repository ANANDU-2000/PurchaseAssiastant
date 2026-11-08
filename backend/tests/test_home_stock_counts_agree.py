"""B1: Home stock counts must equal the Stock screen counts (single definition).

Prod bug: Home showed 'Out 525 / Need attention 526' while Stock showed 'Out 0 / Low 1'.
Cause: Home fell back to the raw cur<=0 count (every never-stocked catalog item)
whenever the 'active out' count was 0.
"""

import uuid

from fastapi.testclient import TestClient

from app.main import app
from tests.test_stock_alerts_summary import (
    _create_piece_item,
    _owner_headers,
    _patch_stock,
    _set_reorder,
    _supplier_id,
)

client = TestClient(app)


def _home_counts(h, bid) -> dict:
    r = client.get(
        f"/v1/businesses/{bid}/reports/home-overview",
        headers=h,
        params={"from": "2020-01-01", "to": "2099-01-01", "compact": True, "shell_bundle": True},
    )
    assert r.status_code == 200, r.text
    return r.json()["home_operational"]["stock_status_counts"]


def _setup(h, bid):
    sid = _supplier_id(h, bid)
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    return sid, cat.json()["id"]


def test_never_stocked_items_are_not_counted_as_out_on_home():
    h, bid = _owner_headers()
    sid, cat_id = _setup(h, bid)
    for i in range(5):  # catalog entries nobody ever stocked or bought
        _create_piece_item(h, bid, sid, name=f"Never {i}", cat_id=cat_id)
    low_id = _create_piece_item(h, bid, sid, name="Low Item", cat_id=cat_id)
    _patch_stock(h, bid, low_id, 8, idem=f"low:{uuid.uuid4().hex}")
    _set_reorder(h, bid, low_id, 10)

    summary = client.get(f"/v1/businesses/{bid}/stock/alerts/summary", headers=h).json()
    home = _home_counts(h, bid)

    assert summary["active_out_of_stock"] == 0
    assert home["out"] == summary["active_out_of_stock"] == 0
    assert home["low"] == summary["low_stock"]
    assert home["critical"] == summary["critical_stock"]
    assert home["all"] == summary["total_items"] == 6


def test_active_out_matches_between_home_and_stock():
    h, bid = _owner_headers()
    sid, cat_id = _setup(h, bid)
    out_id = _create_piece_item(h, bid, sid, name="Was stocked", cat_id=cat_id)
    client.post(
        f"/v1/businesses/{bid}/stock/{out_id}/opening-stock",
        headers=h,
        json={"qty": 5, "reason": "Initial", "idempotency_key": f"open:{uuid.uuid4().hex}"},
    ).raise_for_status()
    _patch_stock(h, bid, out_id, 0, idem=f"out:{uuid.uuid4().hex}")
    _create_piece_item(h, bid, sid, name="Never", cat_id=cat_id)

    summary = client.get(f"/v1/businesses/{bid}/stock/alerts/summary", headers=h).json()
    assert summary["active_out_of_stock"] == 1
    assert _home_counts(h, bid)["out"] == 1
