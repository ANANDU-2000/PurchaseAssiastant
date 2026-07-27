"""Public item JSON — no auth."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"pub{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _type_id(h, bid):
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
    return types.json()[0]["id"]


def test_public_item_json_includes_last_purchase_fields():
    h, bid = _owner_headers()
    tid = _type_id(h, bid)
    suffix = uuid.uuid4().hex[:8]
    created = client.post(
        f"/v1/businesses/{bid}/catalog-items/from-scan",
        headers=h,
        json={
            "barcode": f"890999{suffix[:6]}",
            "item_code": f"PUB-{suffix}".upper(),
            "name": "Public Test Item",
            "type_id": tid,
            "default_unit": "bag",
            "default_kg_per_bag": 50,
        },
    )
    assert created.status_code == 201, created.text
    token = created.json().get("public_token")
    assert token

    pub = client.get(f"/public/items/{token}.json")
    assert pub.status_code == 200, pub.text
    body = pub.json()
    for key in (
        "current_stock",
        "physical_stock_qty",
        "last_purchase_date",
        "last_purchase_rate",
        "last_purchase_qty",
        "last_purchase_unit",
        "supplier_name",
    ):
        assert key in body, key
