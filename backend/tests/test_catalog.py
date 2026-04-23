"""Item categories + catalog items CRUD."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _auth_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"cat{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    assert br.status_code == 200, br.text
    bid = br.json()[0]["id"]
    return h, bid


def test_category_and_item_crud():
    h, bid = _auth_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/item-categories",
        json={"name": "Pulses"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    r = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert r.status_code == 200
    types = r.json()
    assert len(types) == 1
    assert types[0]["name"] == "General"
    general_tid = types[0]["id"]

    r = client.get(f"/v1/businesses/{bid}/item-categories", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 1

    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={"category_id": cid, "name": "Toor Dal", "default_unit": "kg", "hsn_code": "04061090"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    iid = r.json()["id"]
    assert r.json().get("default_kg_per_bag") is None
    assert r.json().get("type_id") == general_tid
    assert r.json().get("type_name") == "General"

    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={
            "category_id": cid,
            "name": "Rice bulk",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "hsn_code": "10063020",
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    bag_id = r.json()["id"]
    assert r.json().get("default_kg_per_bag") == 50.0

    r = client.patch(
        f"/v1/businesses/{bid}/catalog-items/{bag_id}",
        json={"default_unit": "kg"},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json().get("default_kg_per_bag") is None
    r = client.get(f"/v1/businesses/{bid}/catalog-items", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 2

    r = client.get(f"/v1/businesses/{bid}/catalog-items?category_id={cid}", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 2
    ids = {row["id"] for row in r.json()}
    assert iid in ids and bag_id in ids

    r = client.delete(f"/v1/businesses/{bid}/item-categories/{cid}", headers=h)
    assert r.status_code == 400

    r = client.delete(f"/v1/businesses/{bid}/catalog-items/{bag_id}", headers=h)
    assert r.status_code == 204

    r = client.delete(f"/v1/businesses/{bid}/catalog-items/{iid}", headers=h)
    assert r.status_code == 204

    r = client.delete(f"/v1/businesses/{bid}/item-categories/{cid}", headers=h)
    assert r.status_code == 204
