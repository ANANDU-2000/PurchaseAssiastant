"""Business branding: accounts staff WhatsApp number."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"wa{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_patch_business_accounts_whatsapp_round_trip():
    h, bid = _owner_headers()
    patch = client.patch(
        f"/v1/me/businesses/{bid}/branding",
        headers=h,
        json={"accounts_whatsapp_number": "+91 98765 43210"},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json().get("accounts_whatsapp_number") == "9876543210"

    listed = client.get("/v1/me/businesses", headers=h)
    assert listed.status_code == 200, listed.text
    row = next(x for x in listed.json() if x["id"] == bid)
    assert row.get("accounts_whatsapp_number") == "9876543210"

    clear = client.patch(
        f"/v1/me/businesses/{bid}/branding",
        headers=h,
        json={"accounts_whatsapp_number": ""},
    )
    assert clear.status_code == 200, clear.text
    assert clear.json().get("accounts_whatsapp_number") is None


def test_patch_business_accounts_whatsapp_invalid_digits():
    h, bid = _owner_headers()
    bad = client.patch(
        f"/v1/me/businesses/{bid}/branding",
        headers=h,
        json={"accounts_whatsapp_number": "12345"},
    )
    assert bad.status_code == 400, bad.text


def test_patch_business_accounts_whatsapp_uae_round_trip():
    h, bid = _owner_headers()
    patch = client.patch(
        f"/v1/me/businesses/{bid}/branding",
        headers=h,
        json={"accounts_whatsapp_number": "+971 50 123 4567"},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json().get("accounts_whatsapp_number") == "971501234567"

    listed = client.get("/v1/me/businesses", headers=h)
    row = next(x for x in listed.json() if x["id"] == bid)
    assert row.get("accounts_whatsapp_number") == "971501234567"


def test_patch_business_accounts_whatsapp_uae_local_nine_digits():
    h, bid = _owner_headers()
    patch = client.patch(
        f"/v1/me/businesses/{bid}/branding",
        headers=h,
        json={"accounts_whatsapp_number": "501234567"},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json().get("accounts_whatsapp_number") == "971501234567"
