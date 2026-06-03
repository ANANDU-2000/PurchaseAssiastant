"""Auto-assign ITM-#### when catalog item is created without item_code."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"cat{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _minimal_item_payload(h, bid, cid, tid, **extra):
    sid = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Sup {uuid.uuid4().hex[:6]}", "phone": "9876501234"},
    ).json()["id"]
    return {
        "category_id": cid,
        "type_id": tid,
        "default_unit": "kg",
        "default_supplier_ids": [sid],
        **extra,
    }


def test_create_catalog_item_auto_item_code():
    h, bid = _owner_headers()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    tid = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    ).json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json=_minimal_item_payload(h, bid, cid, tid, name="AUTO CODE RICE"),
    )
    assert item.status_code == 201, item.text
    code = item.json().get("item_code")
    assert code is not None
    assert str(code).startswith("ITM-")


def test_create_catalog_item_auto_barcode_from_item_code():
    h, bid = _owner_headers()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    tid = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    ).json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json=_minimal_item_payload(h, bid, cid, tid, name="AUTO BARCODE SUGAR"),
    )
    assert item.status_code == 201, item.text
    code = item.json().get("item_code")
    barcode = item.json().get("barcode")
    assert code is not None
    assert barcode == code


def test_create_catalog_item_without_supplier():
    h, bid = _owner_headers()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    tid = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    ).json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": "NO SUPPLIER RICE",
            "default_unit": "kg",
            "default_supplier_ids": [],
        },
    )
    assert item.status_code == 201, item.text
    assert item.json().get("default_supplier_ids") == []


def test_generate_code_for_existing_item():
    h, bid = _owner_headers()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    cid = cat.json()["id"]
    tid = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    ).json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json=_minimal_item_payload(
            h, bid, cid, tid, name="GEN CODE TEA", item_code="CUSTOM-1"
        ),
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    gen = client.post(
        f"/v1/businesses/{bid}/catalog-items/{iid}/generate-code",
        headers=h,
    )
    assert gen.status_code == 409, gen.text
