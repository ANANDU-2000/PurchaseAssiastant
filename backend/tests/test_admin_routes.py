"""Admin routes: machine token or super-admin JWT (dependency override in tests)."""

from app.deps import AdminCaller, require_admin_caller
from app.main import app
from fastapi.testclient import TestClient

client = TestClient(app)


async def _machine_caller() -> AdminCaller:
    return AdminCaller(machine=True, user=None)


def test_admin_stats_requires_auth():
    r = client.get("/v1/admin/stats")
    assert r.status_code == 401


def test_admin_users_requires_auth():
    r = client.get("/v1/admin/users")
    assert r.status_code == 401


def test_admin_stats_with_machine_override():
    app.dependency_overrides[require_admin_caller] = _machine_caller
    try:
        r = client.get("/v1/admin/stats", headers={"Authorization": "Bearer unused"})
        assert r.status_code == 200
        data = r.json()
        assert "users" in data
        assert "entries_total" in data
        assert "as_of" in data
    finally:
        app.dependency_overrides.pop(require_admin_caller, None)


def test_admin_users_with_machine_override():
    app.dependency_overrides[require_admin_caller] = _machine_caller
    try:
        r = client.get("/v1/admin/users", headers={"Authorization": "Bearer unused"})
        assert r.status_code == 200
        body = r.json()
        assert "items" in body
        assert "total" in body
    finally:
        app.dependency_overrides.pop(require_admin_caller, None)


def test_api_usage_summary_with_machine_override():
    app.dependency_overrides[require_admin_caller] = _machine_caller
    try:
        r = client.get("/v1/admin/api-usage-summary", headers={"Authorization": "Bearer x"})
        assert r.status_code == 200
        assert "generated_at" in r.json()
    finally:
        app.dependency_overrides.pop(require_admin_caller, None)
