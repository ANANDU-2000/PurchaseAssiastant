"""PO commit-stock uses stock_movements idempotency (delivery_receive)."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register():
    u = uuid.uuid4().hex[:8]
    email = f"qp{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"qp{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _pipeline_commit(h, bid, pid, line_id):
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


def test_double_commit_stock_is_idempotent_via_movements():
    h, bid = _register()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "CatQP"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "SupQP", "phone": "9000000888", "gst_number": "22AAAAA0000A1Z5"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Rice QP",
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
                    "item_name": "Rice QP",
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

    _pipeline_commit(h, bid, pid, line_id)
    c1 = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock", headers=h
    )
    assert c1.status_code == 200, c1.text
    c2 = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock", headers=h
    )
    assert c2.status_code == 200, c2.text

    stock_final = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock_final.json()["current_stock"])) == Decimal("10")


def test_stock_detail_hides_expected_system_qty():
    h, bid = _register()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "CatExp"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "SupExp", "phone": "9000000777", "gst_number": "22AAAAA0000A1Z6"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Sugar Exp",
            "default_unit": "piece",
            "default_supplier_ids": [sup],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    client.post(
        f"/v1/businesses/{bid}/stock/{iid}/opening-stock",
        headers=h,
        json={"qty": "101"},
    ).raise_for_status()

    detail = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert "expected_system_qty" not in body
    assert Decimal(str(body["current_stock"])) >= Decimal("101")
