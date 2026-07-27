"""Low-stock operations summary + list endpoints."""

import uuid
from datetime import date, timedelta
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app
from app.services.low_stock_ops_enrichment import derive_lifecycle_stage
from app.schemas.stock import StockListItemOut

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"ls{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _catalog_item_id(h, bid, *, current_stock: float = 1.0, reorder_level: float = 10.0) -> str:
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Sup{uuid.uuid4().hex[:6]}"},
    )
    assert sup.status_code in (200, 201), sup.text
    sid = sup.json()["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat{uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": f"Low item {uuid.uuid4().hex[:4]}",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
            "current_stock": current_stock,
            "reorder_level": reorder_level,
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"]


def test_low_stock_summary_and_operations_enrichment():
    h, bid = _owner_headers()
    _catalog_item_id(h, bid, current_stock=2, reorder_level=20)
    today = date.today()
    start = (today - timedelta(days=30)).isoformat()
    end = today.isoformat()

    summary = client.get(
        f"/v1/businesses/{bid}/stock/low-stock/summary",
        headers=h,
        params={"period_start": start, "period_end": end},
    )
    assert summary.status_code == 200, summary.text
    body = summary.json()
    assert "total_attention" in body
    assert "disputed_items" in body

    ops = client.get(
        f"/v1/businesses/{bid}/stock/low-stock/operations",
        headers=h,
        params={
            "filter": "low",
            "period_start": start,
            "period_end": end,
            "per_page": 50,
        },
    )
    assert ops.status_code == 200, ops.text
    data = ops.json()
    assert "items" in data
    if data["items"]:
        row = data["items"][0]
        assert "lifecycle_stage" in row
        assert "priority_score" in row
        assert "reorder_entry_status" in row


def test_derive_lifecycle_stage_ordered():
    item = StockListItemOut(
        id=uuid.uuid4(),
        item_code=None,
        name="Rice",
        category_name="Grains",
        subcategory_name="Rice",
        current_stock=Decimal("5"),
        reorder_level=Decimal("10"),
        unit="bag",
        rack_location=None,
        stock_status="low",
        last_stock_updated_at=None,
        last_stock_updated_by=None,
        has_pending_order=True,
        pending_order_days=3,
    )
    stage = derive_lifecycle_stage(
        item,
        reorder_entry_status=None,
        has_open_dispute=False,
    )
    assert stage == "ordered"
