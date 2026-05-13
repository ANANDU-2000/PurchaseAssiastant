"""GET /suppliers ?compact=true optional limit."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _auth_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"supc{u}@test.hexa.local"
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


def test_suppliers_compact_omits_address_notes_and_respects_limit():
    h, bid = _auth_and_business()
    for i in range(3):
        r = client.post(
            f"/v1/businesses/{bid}/suppliers",
            json={
                "name": f"Sup compact {i}",
                "phone": f"900000000{i}",
                "address": f"Long address blob {i}" * 20,
                "notes": f"Long notes blob {i}" * 20,
            },
            headers=h,
        )
        assert r.status_code == 201, r.text

    full = client.get(f"/v1/businesses/{bid}/suppliers", headers=h)
    assert full.status_code == 200, full.text
    full_rows = full.json()
    assert len(full_rows) >= 3
    for row in full_rows:
        assert "address" in row
        assert "notes" in row

    compact = client.get(
        f"/v1/businesses/{bid}/suppliers?compact=true&limit=2",
        headers=h,
    )
    assert compact.status_code == 200, compact.text
    c_rows = compact.json()
    assert len(c_rows) == 2
    for row in c_rows:
        assert "address" not in row
        assert "notes" not in row
        assert "id" in row and "name" in row
