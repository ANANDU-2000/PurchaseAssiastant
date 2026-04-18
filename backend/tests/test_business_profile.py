"""Business workspace profile fields on /v1/me/businesses branding patch."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_owner():
    u = uuid.uuid4().hex[:10]
    email = f"bp{u}@test.hexa.local"
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


def test_me_businesses_includes_profile_fields():
    h, bid = _register_owner()
    r = client.get("/v1/me/businesses", headers=h)
    assert r.status_code == 200, r.text
    row = next(x for x in r.json() if x["id"] == bid)
    assert "gst_number" in row
    assert "address" in row
    assert "phone" in row


def test_patch_branding_uppercases_gst_and_round_trips():
    h, bid = _register_owner()
    pr = client.patch(
        f"/v1/me/businesses/{bid}/branding",
        headers=h,
        json={
            "gst_number": "32aaaaa0000a1z5",
            "address": "Ernakulam, Kerala",
            "phone": "0484 1234567",
        },
    )
    assert pr.status_code == 200, pr.text
    d = pr.json()
    assert d["gst_number"] == "32AAAAA0000A1Z5"
    assert "Ernakulam" in (d.get("address") or "")
    assert d.get("phone") == "0484 1234567"

    lr = client.get("/v1/me/businesses", headers=h)
    assert lr.status_code == 200, lr.text
    row = next(x for x in lr.json() if x["id"] == bid)
    assert row["gst_number"] == "32AAAAA0000A1Z5"
