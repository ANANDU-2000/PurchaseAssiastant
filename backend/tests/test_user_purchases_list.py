"""GET /users/{user_id}/purchases — must not lazy-load lines in async session."""

import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"up{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    me = client.get("/v1/me/profile", headers=h)
    assert me.status_code == 200, me.text
    return h, bid, me.json()["id"]


def _supplier_id(h, bid) -> str:
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"UP Sup {uuid.uuid4().hex[:6]}", "phone": "9876501234"},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _catalog_item_id(h, bid, sid: str) -> str:
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
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
            "name": "UP test item",
            "default_unit": "bag",
            "stock_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"]


def test_user_purchases_list_returns_200_with_line_count():
    h, bid, uid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid, sid)
    cr = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "purchase_date": date.today().isoformat(),
            "payment_days": 7,
            "supplier_id": sid,
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "UP test item",
                    "qty": 10,
                    "unit": "BAG",
                    "landing_cost": "100",
                    "tax_percent": "0",
                    "kg_per_unit": "50",
                    "landing_cost_per_kg": "2",
                }
            ],
        },
    )
    assert cr.status_code == 201, cr.text

    r = client.get(
        f"/v1/businesses/{bid}/users/{uid}/purchases",
        headers=h,
        params={"limit": 50},
    )
    assert r.status_code == 200, r.text
    rows = r.json()
    assert len(rows) >= 1
    row = rows[0]
    assert row["human_id"]
    assert row["item_count"] == 1
    assert row["total_amount"] is not None
    assert row["supplier_name"]
