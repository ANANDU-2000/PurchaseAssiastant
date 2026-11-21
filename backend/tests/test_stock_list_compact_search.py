"""Regression: /stock/list/compact and /stock/search must not 500.

Both routes call the internal helper `_list_stock_page` without passing every filter.
The helper's defaults used to be `Query(...)` objects (truthy / not strings), so the
omitted filters crashed with `'Query' object has no attribute 'strip'` -> HTTP 500.
"""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner():
    u = uuid.uuid4().hex[:10]
    r = client.post(
        "/v1/auth/register",
        json={"username": f"cs{u}", "email": f"cs{u}@test.hexa.local", "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid




def test_stock_list_compact_returns_200_with_shape():
    h, bid = _owner()
    r = client.get(f"/v1/businesses/{bid}/stock/list/compact", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert isinstance(body["items"], list)
    assert isinstance(body["total"], int)
    assert body["page"] == 1


def test_stock_search_returns_200_with_shape():
    h, bid = _owner()
    r = client.get(f"/v1/businesses/{bid}/stock/search", headers=h, params={"q": "rice"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert isinstance(body["items"], list)
    assert isinstance(body["total"], int)


def test_stock_list_compact_and_search_do_not_apply_phantom_filters():
    """Omitted filters must behave as 'off', not as a truthy Query() object."""
    h, bid = _owner()
    full = client.get(f"/v1/businesses/{bid}/stock/list", headers=h)
    compact = client.get(f"/v1/businesses/{bid}/stock/list/compact", headers=h)
    search = client.get(f"/v1/businesses/{bid}/stock/search", headers=h)
    assert full.status_code == compact.status_code == search.status_code == 200
    assert compact.json()["total"] == full.json()["total"]
    assert search.json()["total"] == full.json()["total"]
