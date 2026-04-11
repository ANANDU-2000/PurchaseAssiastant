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
    r = client.get(f"/v1/businesses/{bid}/item-categories", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 1

    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={"category_id": cid, "name": "Toor Dal", "default_unit": "kg"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    iid = r.json()["id"]
    r = client.get(f"/v1/businesses/{bid}/catalog-items", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 1

    r = client.get(f"/v1/businesses/{bid}/catalog-items?category_id={cid}", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 1
    assert r.json()[0]["id"] == iid

    r = client.delete(f"/v1/businesses/{bid}/item-categories/{cid}", headers=h)
    assert r.status_code == 400

    r = client.delete(f"/v1/businesses/{bid}/catalog-items/{iid}", headers=h)
    assert r.status_code == 204

    r = client.delete(f"/v1/businesses/{bid}/item-categories/{cid}", headers=h)
    assert r.status_code == 204
