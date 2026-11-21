"""Report saved views API smoke tests."""

from __future__ import annotations

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers_and_business() -> tuple[dict[str, str], str]:
    u = uuid.uuid4().hex[:10]
    r = client.post(
        "/v1/auth/register",
        json={
            "username": f"rv{u}",
            "email": f"rv{u}@test.hexa.local",
            "password": "testpass12",
        },
    )
    assert r.status_code == 200, r.text
    headers = {"Authorization": f"Bearer {r.json()['access_token']}"}
    br = client.get("/v1/me/businesses", headers=headers)
    assert br.status_code == 200, br.text
    return headers, br.json()[0]["id"]


def test_report_saved_views_crud() -> None:
    owner_headers, business_id = _owner_headers_and_business()
    base = f"/v1/businesses/{business_id}/report-views"
    create = client.post(
        base,
        headers=owner_headers,
        json={
            "name": "High value items",
            "tab": "items",
            "filters_json": {"sort": "highestValue"},
            "is_default": True,
        },
    )
    assert create.status_code == 201, create.text
    view_id = create.json()["id"]

    listed = client.get(base, headers=owner_headers)
    assert listed.status_code == 200
    assert any(r["id"] == view_id for r in listed.json())

    patched = client.patch(
        f"{base}/{view_id}",
        headers=owner_headers,
        json={"name": "Top items"},
    )
    assert patched.status_code == 200
    assert patched.json()["name"] == "Top items"

    deleted = client.delete(f"{base}/{view_id}", headers=owner_headers)
    assert deleted.status_code == 204
