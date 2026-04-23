"""Default workspace + catalog seed (single-tenant bootstrap)."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register():
    u = uuid.uuid4().hex[:10]
    email = f"boot{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"bu{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    assert br.status_code == 200, br.text
    bid = br.json()[0]["id"]
    return h, bid


def test_bootstrap_idempotent_seeds_empty_workspace():
    h, bid = _register()
    r = client.post("/v1/me/bootstrap-workspace", headers=h)
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["business_id"] == bid
    assert j["seeded"] is True
    assert j["seed_stats"] is not None
    assert j["seed_stats"]["items_inserted"] > 0

    r2 = client.post("/v1/me/bootstrap-workspace", headers=h)
    assert r2.status_code == 200, r2.text
    j2 = r2.json()
    assert j2["seeded"] is False
    assert j2["seed_stats"] is None
