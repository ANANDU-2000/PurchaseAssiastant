"""Export endpoints: stock XLSX and monthly purchases PDF."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_owner():
    u = uuid.uuid4().hex[:10]
    email = f"exp{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ex{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    client.post("/v1/me/bootstrap-workspace", headers=h)
    return h, bid


def test_stock_inventory_xlsx_export():
    h, bid = _register_owner()
    r = client.get(f"/v1/businesses/{bid}/exports/stock-inventory.xlsx", headers=h)
    assert r.status_code == 200, r.text
    assert r.headers["content-type"].startswith(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    assert len(r.content) > 100
    assert b"PK" in r.content[:4]


def test_purchases_month_pdf_requires_data():
    h, bid = _register_owner()
    r = client.get(f"/v1/businesses/{bid}/exports/purchases-month.pdf", headers=h)
    assert r.status_code in (200, 404), r.text
    if r.status_code == 200:
        assert r.headers["content-type"] == "application/pdf"
        assert r.content[:4] == b"%PDF"
