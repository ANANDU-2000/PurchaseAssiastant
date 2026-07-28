"""AUTH-H4: Google new-user path respects ALLOW_PUBLIC_REGISTRATION."""

from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.routers import auth as auth_mod

client = TestClient(app)


def test_google_new_user_forbidden_when_public_registration_disabled():
    claims = {
        "sub": "google-sub-auth-h4-new-2",
        "email": "newgoogle_auth_h4b@test.hexa.local",
        "email_verified": True,
        "name": "New Google User",
    }
    real = get_settings()

    class _Settings:
        allow_public_registration = False
        jwt_secret = real.jwt_secret
        jwt_refresh_secret = real.jwt_refresh_secret
        jwt_access_ttl_minutes = real.jwt_access_ttl_minutes
        jwt_refresh_ttl_days = real.jwt_refresh_ttl_days
        superadmin_bootstrap_email = None

        def google_oauth_client_id_list(self):
            return ["test-client.apps.googleusercontent.com"]

    fake = _Settings()
    app.dependency_overrides[get_settings] = lambda: fake
    app.dependency_overrides[auth_mod.get_settings] = lambda: fake
    try:
        with patch(
            "app.routers.auth.verify_google_id_token_async",
            new_callable=AsyncMock,
            return_value=claims,
        ):
            r = client.post("/v1/auth/google", json={"id_token": "x" * 40})
    finally:
        app.dependency_overrides.pop(get_settings, None)
        app.dependency_overrides.pop(auth_mod.get_settings, None)
    assert r.status_code == 403, r.text
    assert "registration" in r.json()["detail"].lower()
