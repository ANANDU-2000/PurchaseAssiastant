"""Opening stock setup list + hardened set endpoint."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _headers():
    suffix = uuid.uuid4().hex[:10]
    email = f"openstock{suffix}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"os{suffix}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _supplier_id(h, bid, name: str = "Opening Stock Supplier") -> str:
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"{name} {uuid.uuid4().hex[:6]}", "phone": "9876501234"},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _item(h, bid, *, name: str | None = None, with_opening: bool = False) -> str:
    sid = _supplier_id(h, bid)
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"OS Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    tid = types.json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": name or f"OS Item {uuid.uuid4().hex[:4]}",
            "default_unit": "bag",
            "stock_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
            "current_stock": 0,
            "reorder_level": 2,
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    if with_opening:
        set_r = client.post(
            f"/v1/businesses/{bid}/stock/{iid}/opening-stock",
            headers=h,
            json={"qty": 25, "reason": "seed"},
        )
        assert set_r.status_code == 200, set_r.text
    return iid


def test_opening_setup_list_summary_and_filters():
    h, bid = _headers()
    pending_id = _item(h, bid, name="Pending Rice Unique")
    _item(h, bid, with_opening=True)

    listed = client.get(
        f"/v1/businesses/{bid}/stock/opening/setup",
        headers=h,
        params={"per_page": 200},
    )
    assert listed.status_code == 200, listed.text
    body = listed.json()
    assert body["summary"]["pending_count"] >= 1
    assert body["summary"]["completed_count"] >= 1
    assert body["summary"]["total_count"] >= 2

    pending_only = client.get(
        f"/v1/businesses/{bid}/stock/opening/setup",
        headers=h,
        params={"status": "pending", "q": "Pending Rice"},
    )
    assert pending_only.status_code == 200
    items = pending_only.json()["items"]
    assert any(i["id"] == pending_id for i in items)
    assert all(i["setup_status"] == "pending" for i in items)


def test_set_opening_stock_writes_movement_and_requires_reason_on_change():
    h, bid = _headers()
    iid = _item(h, bid)

    first = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/opening-stock",
        headers=h,
        json={"qty": 100, "reason": "Initial count", "idempotency_key": f"open:{uuid.uuid4().hex}"},
    )
    assert first.status_code == 200, first.text
    assert Decimal(str(first.json()["current_stock"])) == Decimal("100")
    assert Decimal(str(first.json()["opening_stock_qty"])) == Decimal("100")

    no_reason = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/opening-stock",
        headers=h,
        json={"qty": 80},
    )
    assert no_reason.status_code == 400

    with_reason = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/opening-stock",
        headers=h,
        json={"qty": 80, "reason": "Recount correction"},
    )
    assert with_reason.status_code == 200, with_reason.text
    assert Decimal(str(with_reason.json()["opening_stock_qty"])) == Decimal("80")

    activity = client.get(
        f"/v1/businesses/{bid}/stock/{iid}/activity",
        headers=h,
    )
    assert activity.status_code == 200, activity.text
    kinds = [e["kind"] for e in activity.json()["activity"]]
    assert "opening_stock" in kinds or "staff_activity" in kinds
