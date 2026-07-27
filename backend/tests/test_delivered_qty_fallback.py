"""Legacy DBs: committed PO lines count when stock_movements is empty."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register():
    u = uuid.uuid4().hex[:8]
    email = f"dqf{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"dq{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _item(h, bid):
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "CatDQ"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "SupDQ", "phone": "9000000299", "gst_number": "22AAAAA0000A1Z5"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "DQ Item",
            "default_unit": "bag",
            "stock_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sup],
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"], sup


def test_stock_list_total_delivered_from_committed_lines_without_movements():
    h, bid = _register()
    iid, sup = _item(h, bid)
    p = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "supplier_id": sup,
            "purchase_date": "2026-05-20",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "DQ Item",
                    "qty": "12",
                    "unit": "BAG",
                    "kg_per_unit": "50",
                    "landing_cost_per_kg": "2",
                    "purchase_rate": "100",
                    "landing_cost": "100",
                }
            ],
        },
    )
    assert p.status_code in (200, 201), p.text
    pid = p.json()["id"]
    line_id = p.json()["lines"][0]["id"]
    client.post(f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive", headers=h, json={})
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": "12",
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ],
        },
    )
    stock = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={"q": "DQ Item"},
    )
    assert stock.status_code == 200, stock.text
    rows = stock.json()["items"]
    assert len(rows) == 1
    assert Decimal(str(rows[0]["total_delivered_qty"])) >= Decimal("12")
    assert Decimal(str(rows[0]["current_stock"])) >= Decimal("12")
