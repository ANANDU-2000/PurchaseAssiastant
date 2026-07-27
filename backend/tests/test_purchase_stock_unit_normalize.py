"""Delivered purchases must apply stock in catalog stock unit (bags not raw kg)."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_delivered_kg_purchase_increments_bags_not_kg():
    u = uuid.uuid4().hex[:8]
    email = f"bagkg{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"bk{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "Sweet"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sup", "phone": "9000000399", "gst_number": "22AAAAA0000A1Z8"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "SUGAR 50 KG",
            "default_unit": "bag",
            "stock_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sup],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    purchase = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "supplier_id": sup,
            "purchase_date": "2026-05-20",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "SUGAR 50 KG",
                    "qty": "5000",
                    "unit": "kg",
                    "purchase_rate": "50",
                    "landing_cost": "50",
                }
            ],
        },
    )
    assert purchase.status_code in (200, 201), purchase.text
    pid = purchase.json()["id"]

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert stock.status_code == 200, stock.text
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("0")

    delivered = client.patch(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/delivery",
        headers=h,
        json={"is_delivered": True},
    )
    assert delivered.status_code == 200, delivered.text

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert stock.status_code == 200, stock.text
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("100")

    intel = client.get(
        f"/v1/businesses/{bid}/stock/{iid}/intelligence",
        headers=h,
        params={"period_start": "2026-05-01", "period_end": "2026-05-31"},
    )
    assert intel.status_code == 200, intel.text
    body = intel.json()
    assert Decimal(str(body["period_purchased_qty"])) == Decimal("100")
