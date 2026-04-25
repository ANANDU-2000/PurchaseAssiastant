"""Cloud cost reminder API (per business)."""

import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.main import app
from app.services import cloud_expense_service as svc

client = TestClient(app)


def _setup():
    u = uuid.uuid4().hex[:10]
    email = f"cc{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"cc{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    return h, bid


def test_first_next_due_from():
    t = date(2026, 4, 5)
    assert svc.first_next_due_from(t, 9) == date(2026, 4, 9)
    t2 = date(2026, 4, 15)
    assert svc.first_next_due_from(t2, 9) == date(2026, 5, 9)


def test_get_ensure_and_pay():
    h, bid = _setup()
    g = client.get(f"/v1/businesses/{bid}/cloud-cost", headers=h)
    assert g.status_code == 200, g.text
    j = g.json()
    assert "next_due_date" in j
    assert "show_home_card" in j
    assert float(j["amount_inr"]) == 2500.0
    assert j["name"] == "Cloud Cost"
    p = client.post(
        f"/v1/businesses/{bid}/cloud-cost/pay",
        headers=h,
        json={},
    )
    assert p.status_code == 200, p.text
    j2 = p.json()
    assert j2["last_paid_date"] is not None
    assert j2["show_alert"] is False
    hlist = j2["history"]
    assert len(hlist) == 1
    assert float(hlist[0]["amount_inr"]) == 2500.0


def test_pay_optional_payment_id_and_provider():
    h, bid = _setup()
    p = client.post(
        f"/v1/businesses/{bid}/cloud-cost/pay",
        headers=h,
        json={"payment_id": "upi_txn_abc", "provider": "upi"},
    )
    assert p.status_code == 200, p.text
    h0 = p.json()["history"][0]
    assert h0.get("external_payment_id") == "upi_txn_abc"
    assert h0.get("payment_provider") == "upi"


def test_patch_due_day():
    h, bid = _setup()
    r = client.patch(
        f"/v1/businesses/{bid}/cloud-cost",
        headers=h,
        json={"due_day": 15},
    )
    assert r.status_code == 200, r.text
    assert r.json()["due_day"] == 15
