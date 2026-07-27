"""Stock list period parsing, purchased-in-period gate, pagination, auth."""

import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.main import app
from app.routers.stock import _parse_period_dates

client = TestClient(app)


def test_parse_period_dates_all_time_window():
    ps, pe = _parse_period_dates("1970-01-01", "2099-12-31")
    assert ps == date(1970, 1, 1)
    assert pe == date(2099, 12, 31)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"purch{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"purch{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_stock_list_purchased_in_period_pagination_shape():
    h, bid = _owner_headers()
    r = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={
            "page": 1,
            "per_page": 10,
            "include_period": "true",
            "purchased_in_period": "true",
            "period_start": "2020-01-01",
            "period_end": "2099-12-31",
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert "items" in body
    assert "total" in body
    assert body["page"] == 1
    assert body["per_page"] == 10


def test_stock_list_requires_auth():
    bid = str(uuid.uuid4())
    r = client.get(f"/v1/businesses/{bid}/stock/list")
    assert r.status_code in (401, 403)

