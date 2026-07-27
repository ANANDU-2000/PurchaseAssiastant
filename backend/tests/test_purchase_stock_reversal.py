"""Delivered purchase stock must revert when delivery is revoked or cancelled."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_owner():
    u = uuid.uuid4().hex[:8]
    email = f"rev{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ru{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_cancel_delivered_purchase_reverts_stock():
    h, bid = _register_owner()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "Cat"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sup", "phone": "9000000199", "gst_number": "22AAAAA0000A1Z6"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Rice Bag",
            "default_unit": "piece",
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
                    "item_name": "Rice Bag",
                    "qty": "10",
                    "unit": "piece",
                    "purchase_rate": "100",
                    "landing_cost": "100",
                }
            ],
        },
    )
    assert purchase.status_code in (200, 201), purchase.text
    pid = purchase.json()["id"]
    line_id = purchase.json()["lines"][0]["id"]

    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive", headers=h, json={}
    ).raise_for_status()
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": "10",
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ],
        },
    ).raise_for_status()
    delivered = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=h,
    )
    assert delivered.status_code == 200, delivered.text

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("10")

    cancel = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/cancel",
        headers=h,
    )
    assert cancel.status_code == 200, cancel.text

    stock2 = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock2.json()["current_stock"])) == Decimal("0")


def test_delivery_revoke_reverts_stock():
    h, bid = _register_owner()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "Cat2"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sup2", "phone": "9000000299", "gst_number": "22AAAAA0000A1Z7"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Dal Bag",
            "default_unit": "piece",
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
            "purchase_date": "2026-05-21",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Dal Bag",
                    "qty": "10",
                    "unit": "piece",
                    "purchase_rate": "50",
                    "landing_cost": "50",
                }
            ],
        },
    )
    assert purchase.status_code in (200, 201), purchase.text
    pid = purchase.json()["id"]
    line_id = purchase.json()["lines"][0]["id"]

    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive", headers=h, json={}
    ).raise_for_status()
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": "10",
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ],
        },
    ).raise_for_status()
    delivered = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=h,
    )
    assert delivered.status_code == 200, delivered.text

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("10")

    revoked = client.patch(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/delivery",
        headers=h,
        json={"is_delivered": False},
    )
    assert revoked.status_code == 200, revoked.text

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("0")


def test_delivery_double_commit_is_idempotent():
    """Second deliver PATCH must not double-apply stock (PLAN.MD V2 Task 9)."""
    h, bid = _register_owner()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "Cat3"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sup3", "phone": "9000000399", "gst_number": "22AAAAA0000A1Z8"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Oil Bag",
            "default_unit": "piece",
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
            "purchase_date": "2026-05-22",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Oil Bag",
                    "qty": "5",
                    "unit": "piece",
                    "purchase_rate": "80",
                    "landing_cost": "80",
                }
            ],
        },
    )
    assert purchase.status_code in (200, 201), purchase.text
    pid = purchase.json()["id"]

    line_id = purchase.json()["lines"][0]["id"]
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive", headers=h, json={}
    ).raise_for_status()
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": "5",
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ],
        },
    ).raise_for_status()
    for _ in range(2):
        r = client.post(
            f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
            headers=h,
        )
        assert r.status_code == 200, r.text

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("5")
