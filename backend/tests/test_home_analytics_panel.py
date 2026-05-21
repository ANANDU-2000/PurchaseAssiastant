"""Home overview analytics panel blocks (stock_in_hand + purchased)."""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"pan{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"po{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_home_overview_shell_bundle_includes_panel_blocks():
    h, bid = _owner_headers()
    today = date.today()
    start = today - timedelta(days=29)
    r = client.get(
        f"/v1/businesses/{bid}/reports/home-overview",
        headers=h,
        params={
            "from": start.isoformat(),
            "to": today.isoformat(),
            "compact": True,
            "shell_bundle": True,
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert "stock_in_hand" in body
    assert "purchased" in body
    stock = body["stock_in_hand"]
    purchased = body["purchased"]
    assert "bags" in stock and "kg" in stock
    assert "total_value_inr" in stock
    assert "amount_inr" in purchased
    assert "deals" in purchased
    assert "home_shell" in body
    assert isinstance(body["home_shell"].get("items"), list)
