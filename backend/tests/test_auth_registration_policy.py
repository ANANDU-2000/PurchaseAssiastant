import os
import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_public_register_disabled_by_default(monkeypatch):
    monkeypatch.setenv("ALLOW_PUBLIC_REGISTRATION", "0")
    from app.config import get_settings

    get_settings.cache_clear()

    u = uuid.uuid4().hex[:8]
    r = client.post(
        "/v1/auth/register",
        json={
            "username": f"blocked{u}",
            "email": f"blocked{u}@test.hexa.local",
            "password": "testpass12",
        },
    )
    assert r.status_code == 403
    assert "Self-registration is disabled" in r.json()["detail"]

    get_settings.cache_clear()
    os.environ["ALLOW_PUBLIC_REGISTRATION"] = "1"
