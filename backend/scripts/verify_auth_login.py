"""Verify POST /v1/auth/register + /v1/auth/login (sqlite, no server). Run: python scripts/verify_auth_login.py"""
import os
import sys

_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(_root)
if _root not in sys.path:
    sys.path.insert(0, _root)

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./_verify_login.db"
os.environ.setdefault("REDIS_URL", "")
os.environ.setdefault("APP_ENV", "development")

from starlette.testclient import TestClient  # noqa: E402

from app.config import get_settings  # noqa: E402

get_settings.cache_clear()

from app.main import app  # noqa: E402


def main() -> None:
    with TestClient(app) as client:
        r = client.post(
            "/v1/auth/register",
            json={"username": "verifyu", "email": "verify@local.test", "password": "password12"},
        )
        print("register:", r.status_code, r.text[:500])
        r2 = client.post(
            "/v1/auth/login",
            json={"email": "verify@local.test", "password": "password12"},
        )
        print("login:", r2.status_code, r2.text[:500])


if __name__ == "__main__":
    main()
