"""Stock movement idempotency key prevents duplicate ledger rows."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    suffix = uuid.uuid4().hex[:10]
    email = f"idem{suffix}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"id{suffix}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _supplier_id(h, bid) -> str:
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={
            "name": f"Sup {uuid.uuid4().hex[:6]}",
            "phone": "9876504321",
            "gst_number": "22AAAAA0000A1Z5",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_patch_stock_same_idempotency_key_is_safe():
    h, bid = _owner_headers()
    sid = _supplier_id(h, bid)
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "name": f"Item {uuid.uuid4().hex[:6]}",
            "category_id": cat.json()["id"],
            "default_unit": "piece",
            "stock_unit": "piece",
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    item_id = item.json()["id"]
    idem = f"patch-test:{uuid.uuid4().hex}"
    body = {
        "new_qty": 7,
        "adjustment_type": "correction",
        "reason": "test",
        "idempotency_key": idem,
    }
    r1 = client.patch(
        f"/v1/businesses/{bid}/stock/{item_id}",
        headers=h,
        json=body,
    )
    assert r1.status_code == 200, r1.text
    r2 = client.patch(
        f"/v1/businesses/{bid}/stock/{item_id}",
        headers=h,
        json=body,
    )
    assert r2.status_code == 200, r2.text
    assert Decimal(str(r1.json()["current_stock"])) == Decimal("7")
    assert Decimal(str(r2.json()["current_stock"])) == Decimal("7")
