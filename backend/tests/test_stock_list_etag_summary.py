"""Stock list ETag and item summary endpoint."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"etag{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"etag{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_stock_list_returns_etag_and_honors_if_none_match():
    h, bid = _owner_headers()
    r = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={"page": 1, "per_page": 1},
    )
    assert r.status_code == 200, r.text
    etag = r.headers.get("etag")
    assert etag is not None
    r2 = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers={**h, "If-None-Match": etag},
        params={"page": 1, "per_page": 1},
    )
    assert r2.status_code == 304


def test_stock_item_summary_404_when_missing():
    h, bid = _owner_headers()
    missing = str(uuid.uuid4())
    r = client.get(
        f"/v1/businesses/{bid}/stock/item/{missing}/summary",
        headers=h,
    )
    assert r.status_code == 404
