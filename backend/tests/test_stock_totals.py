"""GET /stock/totals aggregates on-hand by unit."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"st{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_stock_totals_empty_business():
    h, bid = _owner_headers()
    r = client.get(f"/v1/businesses/{bid}/stock/totals", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["total_items"] == 0
    assert body["total_bags"] == 0
