"""AUTH-H2 / AUTH-H3 safe product paths (no email / no S3 yet)."""

import io
import uuid

from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app

client = TestClient(app)


def test_forgot_password_reports_no_email_delivery_flag():
    r = client.post(
        "/v1/auth/forgot-password",
        json={"email": f"nobody-{uuid.uuid4().hex[:8]}@test.hexa.local"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body.get("ok") is True
    assert body.get("email_delivery") is False
    assert "message" in body


def test_logo_upload_rejected_in_production_without_s3():
    u = uuid.uuid4().hex[:10]
    reg = client.post(
        "/v1/auth/register",
        json={
            "username": f"lg{u}",
            "email": f"lg{u}@test.hexa.local",
            "password": "testpass12",
        },
    )
    assert reg.status_code == 200, reg.text
    h = {"Authorization": f"Bearer {reg.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]

    base = get_settings()
    override = base.model_copy(update={"app_env": "production", "s3_bucket": None})
    app.dependency_overrides[get_settings] = lambda: override
    try:
        files = {
            "file": (
                "logo.png",
                io.BytesIO(b"\x89PNG\r\n\x1a\n" + b"0" * 64),
                "image/png",
            ),
        }
        r = client.post(
            f"/v1/me/businesses/{bid}/branding/logo",
            headers=h,
            files=files,
        )
        assert r.status_code == 501, r.text
        detail = str(r.json().get("detail", "")).lower()
        assert "logo" in detail or "ephemeral" in detail
    finally:
        app.dependency_overrides.pop(get_settings, None)
