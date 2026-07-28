"""Regression: home-overview / trade-dashboard-snapshot must not 500 from shared-session gather."""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"isce{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"i{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_trade_dashboard_snapshot_returns_summary_keys():
    h, bid = _owner_headers()
    today = date.today()
    start = today - timedelta(days=29)
    r = client.get(
        f"/v1/businesses/{bid}/reports/trade-dashboard-snapshot",
        headers=h,
        params={"from": start.isoformat(), "to": today.isoformat()},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert "summary" in body
    su = body["summary"]
    for key in (
        "deals",
        "total_purchase",
        "total_landing",
        "total_selling",
        "total_profit",
        "pending_delivery_count",
        "supplier_count",
        "broker_count",
        "received_delivery_count",
        "negative_stock_count",
    ):
        assert key in su, key
    assert "categories" in body
    assert "unit_totals" in body


def test_home_overview_shell_bundle_includes_home_operational():
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
    assert "summary" in body
    op = body.get("home_operational")
    assert isinstance(op, dict), op
    assert "stock_status_counts" in op
    assert "warehouse_alerts" in op
    assert "delivery_pipeline" in op
    assert "notifications_unread" in op
    assert "low_stock_top" in op
